import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'data/platform/app_paths.dart';
import 'data/repositories/service_repository.dart';
import 'data/repositories/site_repository.dart';
import 'data/services/config_service.dart';
import 'data/services/database_service.dart';
import 'data/services/hosts_service.dart';
import 'data/services/environment_service.dart';
import 'data/services/process_cleanup.dart';
import 'data/services/runtime_service.dart';
import 'data/services/server_process_service.dart';
import 'data/services/runtime_installer.dart';
import 'data/services/service_launcher.dart';
import 'data/services/settings_service.dart';
import 'data/services/system_service.dart';
import 'ui/core/theme.dart';
import 'ui/features/runtime/runtime_setup_dialog.dart';
import 'ui/features/runtime/runtime_setup_view_model.dart';
import 'ui/features/services/view_models/services_view_model.dart';
import 'ui/features/sites/view_models/sites_view_model.dart';
import 'ui/features/sites/views/sites_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Kill any orphaned processes from a previous (force-quit) session so ports
  // are free before we seed sites/services.
  await const ProcessCleanup().reapOrphans();

  // Composition root: build the dependency graph once, bottom-up, and inject
  // via constructors (per the Flutter architecture skill — no service locator).
  final paths = AppPaths();
  final processService = ServerProcessService();
  final runtimeService = RuntimeService(paths: paths);
  final systemService = SystemService();

  // Sites: Nginx sites run on our own runtime (nginx + php-fpm); Apache still
  // uses MAMP for now.
  final siteRepository = SiteRepository(
    environmentService: EnvironmentService(),
    configService:
        ConfigService(runtimeService: runtimeService, paths: paths),
    processService: processService,
    settingsService: SettingsService(paths: paths),
    systemService: systemService,
    hostsService: const HostsService(),
  );
  final sitesViewModel = SitesViewModel(repository: siteRepository)..load();

  // Services (global daemons — our OWN runtime binaries, MAMP-independent).
  final serviceRepository = ServiceRepository(
    runtimeService: runtimeService,
    serviceLauncher: ServiceLauncher(paths: paths),
    processService: processService,
    databaseService: const DatabaseService(),
    systemService: systemService,
  );
  final servicesViewModel =
      ServicesViewModel(repository: serviceRepository)..load();

  // First-launch runtime download prompt. When a component finishes installing,
  // re-check the Services list so newly downloaded binaries become startable
  // without an app restart.
  final runtimeSetup = RuntimeSetupViewModel(
    installer: RuntimeInstaller(paths: paths),
    onInstalled: servicesViewModel.refresh,
  );

  runApp(OricDevServerApp(
    sitesViewModel: sitesViewModel,
    servicesViewModel: servicesViewModel,
    runtimeSetup: runtimeSetup,
    onExit: () async {
      // Stop everything we started so nothing is left orphaned on quit.
      await serviceRepository.dispose();
      await siteRepository.dispose();
    },
  ));
}

class OricDevServerApp extends StatefulWidget {
  const OricDevServerApp({
    super.key,
    required this.sitesViewModel,
    required this.servicesViewModel,
    required this.runtimeSetup,
    required this.onExit,
  });

  final SitesViewModel sitesViewModel;
  final ServicesViewModel servicesViewModel;
  final RuntimeSetupViewModel runtimeSetup;
  final Future<void> Function() onExit;

  @override
  State<OricDevServerApp> createState() => _OricDevServerAppState();
}

class _OricDevServerAppState extends State<OricDevServerApp> {
  late final AppLifecycleListener _lifecycle;
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.onExit();
        return ui.AppExitResponse.exit;
      },
    );
    // After first frame, prompt to download any missing runtime components.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.runtimeSetup.check();
      final ctx = _navKey.currentContext;
      if (ctx != null && widget.runtimeSetup.hasMissing) {
        showRuntimeSetupDialog(ctx, widget.runtimeSetup);
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navKey,
      title: 'OricDevServer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SitesView(
        viewModel: widget.sitesViewModel,
        servicesViewModel: widget.servicesViewModel,
        runtimeSetup: widget.runtimeSetup,
      ),
    );
  }
}
