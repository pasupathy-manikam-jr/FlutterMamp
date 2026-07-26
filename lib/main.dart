import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'data/repositories/service_repository.dart';
import 'data/repositories/site_repository.dart';
import 'data/services/config_service.dart';
import 'data/services/database_service.dart';
import 'data/services/hosts_service.dart';
import 'data/services/mamp_service.dart';
import 'data/services/process_cleanup.dart';
import 'data/services/runtime_service.dart';
import 'data/services/server_process_service.dart';
import 'data/services/service_launcher.dart';
import 'data/services/settings_service.dart';
import 'data/services/system_service.dart';
import 'ui/core/theme.dart';
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
  final processService = ServerProcessService();
  final runtimeService = RuntimeService();
  final systemService = SystemService();

  // Sites: Nginx sites run on our own runtime (nginx + php-fpm); Apache still
  // uses MAMP for now.
  final siteRepository = SiteRepository(
    mampService: MampService(),
    configService: ConfigService(runtimeService: runtimeService),
    processService: processService,
    settingsService: SettingsService(),
    systemService: systemService,
    hostsService: const HostsService(),
  );
  final sitesViewModel = SitesViewModel(repository: siteRepository)..load();

  // Services (global daemons — our OWN runtime binaries, MAMP-independent).
  final serviceRepository = ServiceRepository(
    runtimeService: runtimeService,
    serviceLauncher: ServiceLauncher(),
    processService: processService,
    databaseService: const DatabaseService(),
    systemService: systemService,
  );
  final servicesViewModel =
      ServicesViewModel(repository: serviceRepository)..load();

  runApp(FlutterMampApp(
    sitesViewModel: sitesViewModel,
    servicesViewModel: servicesViewModel,
    onExit: () async {
      // Stop everything we started so nothing is left orphaned on quit.
      await serviceRepository.dispose();
      await siteRepository.dispose();
    },
  ));
}

class FlutterMampApp extends StatefulWidget {
  const FlutterMampApp({
    super.key,
    required this.sitesViewModel,
    required this.servicesViewModel,
    required this.onExit,
  });

  final SitesViewModel sitesViewModel;
  final ServicesViewModel servicesViewModel;
  final Future<void> Function() onExit;

  @override
  State<FlutterMampApp> createState() => _FlutterMampAppState();
}

class _FlutterMampAppState extends State<FlutterMampApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await widget.onExit();
        return ui.AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OricMamp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SitesView(
        viewModel: widget.sitesViewModel,
        servicesViewModel: widget.servicesViewModel,
      ),
    );
  }
}
