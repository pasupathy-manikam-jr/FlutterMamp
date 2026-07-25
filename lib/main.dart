import 'package:flutter/material.dart';

import 'data/repositories/site_repository.dart';
import 'data/services/config_service.dart';
import 'data/services/hosts_service.dart';
import 'data/services/mamp_service.dart';
import 'data/services/server_process_service.dart';
import 'data/services/settings_service.dart';
import 'data/services/system_service.dart';
import 'ui/core/theme.dart';
import 'ui/features/sites/view_models/sites_view_model.dart';
import 'ui/features/sites/views/sites_view.dart';

void main() {
  // Composition root: build the dependency graph once, bottom-up, and inject
  // via constructors (per the Flutter architecture skill — no service locator).
  final repository = SiteRepository(
    mampService: MampService(),
    configService: ConfigService(),
    processService: ServerProcessService(),
    settingsService: SettingsService(),
    systemService: SystemService(),
    hostsService: const HostsService(),
  );
  final viewModel = SitesViewModel(repository: repository)..load();

  runApp(FlutterMampApp(viewModel: viewModel));
}

class FlutterMampApp extends StatelessWidget {
  const FlutterMampApp({super.key, required this.viewModel});

  final SitesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterMamp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: SitesView(viewModel: viewModel),
    );
  }
}
