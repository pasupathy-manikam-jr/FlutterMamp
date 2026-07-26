import 'package:flutter/material.dart';

import 'runtime_setup_view_model.dart';

/// First-launch prompt to download the runtime components that aren't present.
Future<void> showRuntimeSetupDialog(
  BuildContext context,
  RuntimeSetupViewModel viewModel,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RuntimeSetupDialog(viewModel: viewModel),
  );
}

class _RuntimeSetupDialog extends StatelessWidget {
  const _RuntimeSetupDialog({required this.viewModel});
  final RuntimeSetupViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final anyMissing = viewModel.hasMissing;
        return AlertDialog(
          title: const Text('Set up OricDevServer runtime'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anyMissing
                      ? 'These components need to be downloaded before you can '
                          'start their servers/services:'
                      : 'All runtime components are installed.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final s in viewModel.states) _row(theme, s),
                if (!anyMissing && !viewModel.isDownloading) ...[
                  const SizedBox(height: 8),
                  Text('Tip: restart OricDevServer after downloading so newly added '
                      'services activate.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  viewModel.isDownloading ? null : () => Navigator.pop(context),
              child: Text(anyMissing ? 'Later' : 'Close'),
            ),
            if (anyMissing)
              FilledButton.icon(
                onPressed:
                    viewModel.isDownloading ? null : viewModel.downloadMissing,
                icon: const Icon(Icons.download, size: 18),
                label: Text(viewModel.isDownloading
                    ? 'Downloading…'
                    : 'Download all'),
              ),
          ],
        );
      },
    );
  }

  Widget _row(ThemeData theme, ComponentState s) {
    Widget trailing;
    if (s.installed) {
      trailing = const Icon(Icons.check_circle,
          color: Color(0xFF34C759), size: 18);
    } else if (s.progress != null) {
      trailing = Text('${(s.progress! * 100).round()}%',
          style: theme.textTheme.bodySmall);
    } else {
      // Missing: show size + a per-component install button so you can pick
      // exactly what to download instead of "Download all".
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('~${s.component.approxMB} MB',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'Install ${s.component.label}',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(Icons.download),
            onPressed:
                viewModel.isDownloading ? null : () => viewModel.downloadOne(s),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.component.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: s.installed ? theme.hintColor : null)),
              ),
              trailing,
            ],
          ),
          if (s.progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                  value: s.progress == 0 ? null : s.progress),
            ),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s.error!,
                  style: const TextStyle(
                      color: Color(0xFFFF3B30), fontSize: 11)),
            ),
        ],
      ),
    );
  }
}
