import 'package:flutter/material.dart';

import '../../../../domain/models/php_version.dart';
import '../../../../domain/models/server_status.dart';
import '../../../../domain/models/server_type.dart';
import '../../../../domain/models/site.dart';
import '../../../core/theme.dart';
import '../view_models/sites_view_model.dart';
import 'log_panel.dart';

/// Right-hand detail pane for the selected site: configuration + controls +
/// live logs. Mirrors MAMP PRO's per-host settings panel.
class SiteDetail extends StatefulWidget {
  const SiteDetail({super.key, required this.viewModel, required this.site});

  final SitesViewModel viewModel;
  final Site site;

  @override
  State<SiteDetail> createState() => _SiteDetailState();
}

class _SiteDetailState extends State<SiteDetail> {
  late final TextEditingController _name;
  late final TextEditingController _port;
  late final TextEditingController _hostname;
  late final TextEditingController _sslPort;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.site.name);
    _port = TextEditingController(text: widget.site.port.toString());
    _hostname = TextEditingController(text: widget.site.hostname);
    _sslPort = TextEditingController(text: widget.site.sslPort.toString());
  }

  @override
  void didUpdateWidget(covariant SiteDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.id != widget.site.id) {
      _name.text = widget.site.name;
      _port.text = widget.site.port.toString();
      _hostname.text = widget.site.hostname;
      _sslPort.text = widget.site.sslPort.toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _port.dispose();
    _hostname.dispose();
    _sslPort.dispose();
    super.dispose();
  }

  SitesViewModel get vm => widget.viewModel;

  void _commit() {
    vm.updateSite(
      widget.site.id,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      port: int.tryParse(_port.text.trim()),
      hostname: _hostname.text.trim(),
      sslPort: int.tryParse(_sslPort.text.trim()),
    );
  }

  Future<void> _browse() async {
    final path = await vm.chooseFolder();
    if (path != null) {
      await vm.updateSite(widget.site.id, documentRoot: path);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "${widget.site.name}"?'),
        content: const Text(
            'This removes the site from FlutterMamp. Your files are not touched.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await vm.deleteSite(widget.site.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final site = widget.site;
    final editable = !site.status.isActive && !site.status.isTransitioning;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme, site),
          const SizedBox(height: 20),
          _label('Site Name'),
          TextField(
            controller: _name,
            enabled: editable,
            decoration: _dec(),
            onChanged: (_) => _commit(),
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
          ),
          const SizedBox(height: 12),
          _label('Document Root'),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    site.documentRoot,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: editable ? _browse : null,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Browse…'),
              ),
              IconButton(
                tooltip: 'Reveal in Finder',
                onPressed: () => vm.revealDocumentRoot(site.id),
                icon: const Icon(Icons.arrow_outward, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _engineSelector(site, editable)),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Port'),
                    TextField(
                      controller: _port,
                      enabled: editable,
                      keyboardType: TextInputType.number,
                      decoration: _dec(),
                      onChanged: (_) => _commit(),
                      onSubmitted: (_) => _commit(),
                      onEditingComplete: _commit,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _phpSelector(site, editable)),
            ],
          ),
          const SizedBox(height: 12),
          _label('Host Name (optional)'),
          TextField(
            controller: _hostname,
            enabled: editable,
            decoration: _dec().copyWith(
                hintText: 'e.g. ${site.name}.local — added to /etc/hosts'),
            onChanged: (_) => _commit(),
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('SSL (HTTPS)'),
                  subtitle: const Text('Self-signed certificate'),
                  value: site.sslEnabled,
                  onChanged: editable
                      ? (v) => vm.updateSite(site.id, sslEnabled: v)
                      : null,
                ),
              ),
              if (site.sslEnabled) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('SSL Port'),
                      TextField(
                        controller: _sslPort,
                        enabled: editable,
                        keyboardType: TextInputType.number,
                        decoration: _dec(),
                        onChanged: (_) => _commit(),
                        onSubmitted: (_) => _commit(),
                        onEditingComplete: _commit,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (site.status == ServerStatus.error &&
              site.errorMessage != null) ...[
            const SizedBox(height: 12),
            _errorBanner(site.errorMessage!),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Output',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(site.url,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor, fontFamily: 'Menlo')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: LogPanel(lines: site.logLines)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, Site site) {
    final active = site.status.isActive;
    final busy = site.status.isTransitioning;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: statusColor(site.status), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(site.name,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text('${site.server.label} · ${site.status.label}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Delete site',
          onPressed: busy ? null : _confirmDelete,
          icon: const Icon(Icons.delete_outline),
        ),
        const SizedBox(width: 4),
        if (active) ...[
          OutlinedButton.icon(
            onPressed: () => vm.openInBrowser(site.id),
            icon: const Icon(Icons.open_in_browser_rounded, size: 18),
            label: const Text('Open'),
            style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          onPressed: busy ? null : () => vm.toggle(site.id),
          icon: Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(active ? 'Stop' : 'Start'),
          style: FilledButton.styleFrom(
            backgroundColor: active ? const Color(0xFFFF3B30) : null,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _engineSelector(Site site, bool editable) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Engine'),
        DropdownButtonFormField<ServerType>(
          initialValue: site.server,
          isExpanded: true,
          decoration: _dec(),
          items: [
            for (final t in ServerType.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: editable
              ? (t) {
                  if (t != null) vm.updateSite(site.id, server: t);
                }
              : null,
        ),
      ],
    );
  }

  Widget _phpSelector(Site site, bool editable) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('PHP Version'),
        DropdownButtonFormField<PhpVersion>(
          initialValue: site.phpVersion,
          isExpanded: true,
          decoration: _dec(),
          items: [
            for (final v in vm.phpVersions)
              DropdownMenuItem(value: v, child: Text(v.version)),
          ],
          onChanged: editable
              ? (v) {
                  if (v != null) vm.updateSite(site.id, phpVersion: v);
                }
              : null,
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );

  InputDecoration _dec() => const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      );

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF3B30).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    const TextStyle(color: Color(0xFFFF3B30), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
