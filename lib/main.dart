import 'package:flutter/material.dart';

import 'data/repositories/service_repository.dart';
import 'data/repositories/site_repository.dart';
import 'data/services/config_service.dart';
import 'data/services/hosts_service.dart';
import 'data/services/mamp_service.dart';
import 'data/services/runtime_service.dart';
import 'data/services/server_process_service.dart';
import 'data/services/service_launcher.dart';
import 'data/services/settings_service.dart';
import 'data/services/system_service.dart';
import 'ui/core/theme.dart';
import 'ui/features/services/view_models/services_view_model.dart';
import 'ui/features/sites/view_models/sites_view_model.dart';
import 'ui/features/sites/views/sites_view.dart';

void main() {
  // Composition root: build the dependency graph once, bottom-up, and inject
  // via constructors (per the Flutter architecture skill — no service locator).
  final processService = ServerProcessService();

  // Sites (web servers — currently backed by MAMP binaries; migrating to our
  // own runtime as we remove MAMP).
  final siteRepository = SiteRepository(
    mampService: MampService(),
    configService: ConfigService(),
    processService: processService,
    settingsService: SettingsService(),
    systemService: SystemService(),
    hostsService: const HostsService(),
  );
  final sitesViewModel = SitesViewModel(repository: siteRepository)..load();

  // Services (global daemons — our OWN runtime binaries, MAMP-independent).
  final serviceRepository = ServiceRepository(
    runtimeService: RuntimeService(),
    serviceLauncher: ServiceLauncher(),
    processService: processService,
  );
  final servicesViewModel =
      ServicesViewModel(repository: serviceRepository)..load();

  runApp(FlutterMampApp(
    sitesViewModel: sitesViewModel,
    servicesViewModel: servicesViewModel,
  ));
}

class FlutterMampApp extends StatelessWidget {
  const FlutterMampApp({
    super.key,
    required this.sitesViewModel,
    required this.servicesViewModel,
  });

  final SitesViewModel sitesViewModel;
  final ServicesViewModel servicesViewModel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterMamp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SitesView(
        viewModel: sitesViewModel,
        servicesViewModel: servicesViewModel,
      ),
    );
  }
}
