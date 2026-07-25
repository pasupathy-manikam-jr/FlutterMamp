import 'package:flutter/material.dart';

import '../../../../domain/models/tool_type.dart';
import '../view_models/services_view_model.dart';

/// The "TOOLS" group in the sidebar: database admin UIs (Adminer, phpMyAdmin)
/// served on demand by FrankenPHP. Each has an Open button (starts + opens in
/// the browser) and a stop when running.
class ToolsSection extends StatelessWidget {
  const ToolsSection({super.key, required this.viewModel});

  final ServicesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('TOOLS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: Color(0xFF8E8E93))),
        ),
        for (final tool in viewModel.tools)
          _ToolRow(tool: tool, viewModel: viewModel),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.tool, required this.viewModel});

  final ToolType tool;
  final ServicesViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = viewModel.toolAvailable(tool);
    final running = viewModel.isToolRunning(tool);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: !available
                  ? const Color(0xFFC7C7CC)
                  : (running
                      ? const Color(0xFF34C759)
                      : const Color(0xFF8E8E93)),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: available ? null : theme.hintColor)),
                Text(
                  available ? ':${tool.port}' : 'not installed',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor, fontSize: 11),
                ),
              ],
            ),
          ),
          if (available) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Open in browser',
              iconSize: 18,
              icon: const Icon(Icons.open_in_new),
              onPressed: () => viewModel.openTool(tool),
            ),
            if (running)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Stop',
                iconSize: 18,
                color: const Color(0xFFFF3B30),
                icon: const Icon(Icons.stop_circle),
                onPressed: () => viewModel.stopTool(tool),
              ),
          ],
        ],
      ),
    );
  }
}
