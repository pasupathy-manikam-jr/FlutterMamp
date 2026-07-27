import 'package:flutter/material.dart';

import '../../../../domain/models/php_version.dart';
import '../../../../domain/models/server_type.dart';
import '../view_models/sites_view_model.dart';

/// Shows the "New Site" dialog and creates the site on confirm.
Future<void> showAddSiteDialog(
  BuildContext context,
  SitesViewModel viewModel,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SiteFormDialog(viewModel: viewModel),
  );
}

class _SiteFormDialog extends StatefulWidget {
  const _SiteFormDialog({required this.viewModel});

  final SitesViewModel viewModel;

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  final _name = TextEditingController(text: 'mysite');
  final _hostname = TextEditingController();
  late final TextEditingController _port =
      TextEditingController(text: widget.viewModel.suggestPort().toString());
  final _sslPort = TextEditingController(text: '8443');
  String? _documentRoot;
  ServerType _server = ServerType.apache;
  PhpVersion? _php;
  bool _ssl = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _php = widget.viewModel.phpVersions.isNotEmpty
        ? widget.viewModel.phpVersions.first
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _hostname.dispose();
    _port.dispose();
    _sslPort.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    final path = await widget.viewModel.chooseFolder();
    if (path != null) setState(() => _documentRoot = path);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final port = int.tryParse(_port.text.trim());
    final sslPort = int.tryParse(_sslPort.text.trim());
    if (name.isEmpty) {
      setState(() => _error = 'Enter a site name.');
      return;
    }
    if (_documentRoot == null) {
      setState(() => _error = 'Choose a document root.');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = 'Enter a valid port (1–65535).');
      return;
    }
    if (_ssl &&
        _server.supportsSsl &&
        (sslPort == null || sslPort < 1 || sslPort > 65535)) {
      setState(() => _error = 'Enter a valid SSL port (1–65535).');
      return;
    }
    await widget.viewModel.addSite(
      name: name,
      documentRoot: _documentRoot!,
      server: _server,
      port: port,
      hostname: _hostname.text.trim(),
      sslEnabled: _ssl,
      sslPort: sslPort ?? 8443,
      phpVersion: _php,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New Site'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Name'),
              TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: _dec(hint: 'mysite')),
              const SizedBox(height: 12),
              _label('Host Name (optional)'),
              TextField(
                controller: _hostname,
                decoration: _dec(hint: 'e.g. mysite.local — added to /etc/hosts'),
              ),
              const SizedBox(height: 12),
              _label('Document Root'),
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
                        _documentRoot ?? 'No folder selected',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _documentRoot == null
                              ? theme.hintColor
                              : theme.textTheme.bodyMedium?.color,
                          fontFamily: 'Menlo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _browse,
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Browse…'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Web Server'),
                        DropdownButtonFormField<ServerType>(
                          initialValue: _server,
                          decoration: _dec(),
                          items: [
                            for (final t in ServerType.values)
                              DropdownMenuItem(value: t, child: Text(t.label)),
                          ],
                          onChanged: (t) =>
                              setState(() => _server = t ?? _server),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Port'),
                        TextField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            decoration: _dec()),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label('PHP Version'),
              DropdownButtonFormField<PhpVersion>(
                initialValue: _php,
                isExpanded: true,
                decoration: _dec(),
                items: [
                  for (final v in widget.viewModel.phpVersions)
                    DropdownMenuItem(value: v, child: Text(v.version)),
                ],
                onChanged: (v) => setState(() => _php = v),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable SSL (HTTPS)'),
                subtitle: Text(_server.supportsSsl
                    ? 'Self-signed certificate via OpenSSL'
                    : '${_server.label} serves HTTP only'),
                value: _ssl && _server.supportsSsl,
                onChanged: _server.supportsSsl
                    ? (v) => setState(() => _ssl = v)
                    : null,
              ),
              if (_ssl && _server.supportsSsl) ...[
                _label('SSL Port'),
                TextField(
                    controller: _sslPort,
                    keyboardType: TextInputType.number,
                    decoration: _dec()),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: Color(0xFFFF3B30), fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Create Site')),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 2),
        child: Text(text,
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
