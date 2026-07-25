import 'package:flutter/material.dart';

import '../../services/view_models/services_view_model.dart';
import '../../services/views/services_section.dart';
import '../view_models/sites_view_model.dart';
import 'site_detail.dart';
import 'site_form_dialog.dart';
import 'site_tile.dart';

/// The main window: a MAMP-style master/detail with a toolbar on top, a
/// source-list sidebar of sites (with add/remove), and a configuration + log
/// detail pane.
class SitesView extends StatelessWidget {
  const SitesView({
    super.key,
    required this.viewModel,
    required this.servicesViewModel,
  });

  final SitesViewModel viewModel;
  final ServicesViewModel servicesViewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([viewModel, servicesViewModel]),
      builder: (context, _) {
        if (!viewModel.isReady) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: Column(
            children: [
              _Toolbar(viewModel: viewModel),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    _Sidebar(
                        viewModel: viewModel,
                        servicesViewModel: servicesViewModel),
                    const VerticalDivider(width: 1),
                    Expanded(child: _Detail(viewModel: viewModel)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.viewModel});
  final SitesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = viewModel.anyRunning;
    final env = viewModel.environment;
    final hasSites = viewModel.sites.isNotEmpty;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.dns_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text('FlutterMamp',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 16),
          _StatusLight(running: running, count: viewModel.runningCount),
          const Spacer(),
          if (!env.isPresent)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text('MAMP not found',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: const Color(0xFFFF3B30))),
            ),
          FilledButton.icon(
            onPressed: hasSites ? viewModel.toggleAll : null,
            icon: Icon(running ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(running ? 'Stop All' : 'Start All'),
            style: FilledButton.styleFrom(
              backgroundColor: running ? const Color(0xFFFF3B30) : null,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLight extends StatelessWidget {
  const _StatusLight({required this.running, required this.count});
  final bool running;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = running ? const Color(0xFF34C759) : const Color(0xFF8E8E93);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(running ? '$count running' : 'All stopped',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ],
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.viewModel, required this.servicesViewModel});
  final SitesViewModel viewModel;
  final ServicesViewModel servicesViewModel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                const Text('SITES',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFF8E8E93))),
                const Spacer(),
                IconButton(
                  tooltip: 'Add site',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add, size: 20),
                  onPressed: () => showAddSiteDialog(context, viewModel),
                ),
              ],
            ),
          ),
          Expanded(
            child: viewModel.sites.isEmpty
                ? _EmptySidebar(viewModel: viewModel)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final site in viewModel.sites)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: SiteTile(
                            site: site,
                            selected: site.id == viewModel.selectedId,
                            onTap: () => viewModel.select(site.id),
                          ),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          ServicesSection(viewModel: servicesViewModel),
        ],
      ),
    );
  }
}

class _EmptySidebar extends StatelessWidget {
  const _EmptySidebar({required this.viewModel});
  final SitesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.web_asset_off, color: Color(0xFF8E8E93)),
            const SizedBox(height: 8),
            Text('No sites yet',
                style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => showAddSiteDialog(context, viewModel),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Site'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.viewModel});
  final SitesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selected;
    if (selected == null) {
      return Center(
        child: Text('Select or add a site',
            style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }
    return SiteDetail(viewModel: viewModel, site: selected);
  }
}
