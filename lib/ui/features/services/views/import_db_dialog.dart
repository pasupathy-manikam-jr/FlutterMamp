import 'package:flutter/material.dart';

import '../view_models/services_view_model.dart';

/// Dialog to import a `.sql`/`.sql.gz` dump into MySQL.
Future<void> showImportDbDialog(
  BuildContext context,
  ServicesViewModel viewModel,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ImportDbDialog(viewModel: viewModel),
  );
}

class _ImportDbDialog extends StatefulWidget {
  const _ImportDbDialog({required this.viewModel});
  final ServicesViewModel viewModel;

  @override
  State<_ImportDbDialog> createState() => _ImportDbDialogState();
}

class _ImportDbDialogState extends State<_ImportDbDialog> {
  final _db = TextEditingController();
  final _user = TextEditingController(text: 'root');
  final _password = TextEditingController(text: 'root');
  String? _dumpPath;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void dispose() {
    _db.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final path = await widget.viewModel.chooseSqlFile();
    if (path != null) setState(() => _dumpPath = path);
  }

  Future<void> _import() async {
    if (_dumpPath == null) {
      setState(() => _result = 'Choose a dump file first.');
      return;
    }
    if (_db.text.trim().isEmpty) {
      setState(() => _result = 'Enter a database name.');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    final res = await widget.viewModel.importDump(
      dumpPath: _dumpPath!,
      database: _db.text.trim(),
      user: _user.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = res.ok;
      _result = res.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Import SQL Dump'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Dump file (.sql or .sql.gz)'),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _dumpPath ?? 'No file selected',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 12,
                        color: _dumpPath == null ? theme.hintColor : null,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _browse,
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Browse…'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('Database'),
            TextField(
                controller: _db,
                decoration: _dec(hint: 'e.g. aimsfx_db3')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [_label('User'), TextField(controller: _user, decoration: _dec())],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Password'),
                      TextField(controller: _password, decoration: _dec()),
                    ],
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(children: const [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Importing… (large dumps can take a while)'),
              ]),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                _result!,
                style: TextStyle(
                    fontSize: 12,
                    color: _ok
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF3B30)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_ok ? 'Close' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _import,
          child: const Text('Import'),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(t,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  InputDecoration _dec({String? hint}) => InputDecoration(
        isDense: true,
        hintText: hint,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      );
}
