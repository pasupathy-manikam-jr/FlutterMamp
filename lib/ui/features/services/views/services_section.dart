import 'package:flutter/material.dart';

import '../../../../domain/models/managed_service.dart';
import '../../../../domain/models/service_type.dart';
import '../../../core/theme.dart';
import '../view_models/services_view_model.dart';
import 'import_db_dialog.dart';

/// The "SERVICES" group pinned at the bottom of the sidebar: Redis, MySQL,
/// Memcached, MailHog with inline start/stop, mirroring MAMP PRO's services.
class ServicesSection extends StatelessWidget {
  const ServicesSection({super.key, required this.viewModel});

  final ServicesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('SERVICES',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF8E8E93))),
        ),
        for (final service in viewModel.services)
          _ServiceRow(service: service, viewModel: viewModel),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.viewModel});

  final ManagedService service;
  final ServicesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = service.status.isActive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: service.available
                  ? statusColor(service.status)
                  : const Color(0xFFC7C7CC),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(service.type.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: service.available ? null : theme.hintColor)),
                Text(
                  service.available
                      ? ':${service.port} · ${service.status.label}'
                      : 'not installed',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor, fontSize: 11),
                ),
              ],
            ),
          ),
          if (service.type == ServiceType.mysql &&
              service.status.isActive &&
              viewModel.mysqlClientAvailable)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Import SQL dump',
              iconSize: 18,
              icon: const Icon(Icons.upload_file),
              onPressed: () => showImportDbDialog(context, viewModel),
            ),
          if (!service.available)
            const SizedBox.shrink()
          else if (service.status.isTransitioning)
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
          else
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: active ? 'Stop' : 'Start',
              iconSize: 20,
              color: active ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
              icon: Icon(active ? Icons.stop_circle : Icons.play_circle),
              onPressed: () => viewModel.toggle(service.type),
            ),
        ],
      ),
    );
  }
}
