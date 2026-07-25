import 'dart:io';

/// Manages `127.0.0.1 <hostname>` entries in `/etc/hosts` so a site's custom
/// hostname resolves locally.
///
/// `/etc/hosts` is world-readable, so we compute the new contents in Dart and
/// only escalate (native admin prompt via `osascript … with administrator
/// privileges`) to write it back. Our lines are tagged with a marker so we only
/// ever touch entries we created.
class HostsService {
  const HostsService();

  static const String _hostsPath = '/etc/hosts';
  static const String _marker = '# FlutterMamp';

  /// True if [hostname] already has one of our entries.
  Future<bool> isMapped(String hostname) async {
    final file = File(_hostsPath);
    if (!file.existsSync()) return false;
    for (final line in await file.readAsLines()) {
      if (line.contains(_marker) && _tokens(line).contains(hostname)) {
        return true;
      }
    }
    return false;
  }

  /// Ensure [hostname] maps to 127.0.0.1. Returns true if the mapping is present
  /// afterwards (already there, or the user approved the admin prompt).
  Future<bool> ensureMapping(String hostname) async {
    if (hostname.isEmpty) return true;
    if (await isMapped(hostname)) return true;

    final file = File(_hostsPath);
    final lines = file.existsSync() ? await file.readAsLines() : <String>[];
    final entry = '127.0.0.1\t$hostname\t$_marker';
    final content = '${[...lines, entry].join('\n')}\n';
    return _writeViaAdmin(content);
  }

  /// Remove any of our entries for [hostname].
  Future<void> removeMapping(String hostname) async {
    if (hostname.isEmpty) return;
    final file = File(_hostsPath);
    if (!file.existsSync()) return;
    final lines = await file.readAsLines();
    final kept = lines
        .where((l) => !(l.contains(_marker) && _tokens(l).contains(hostname)))
        .toList();
    if (kept.length == lines.length) return; // nothing of ours to remove
    await _writeViaAdmin('${kept.join('\n')}\n');
  }

  List<String> _tokens(String line) =>
      line.trim().split(RegExp(r'\s+'));

  /// Write [content] over /etc/hosts using a native admin prompt. We stage the
  /// content in a temp file and `cp` it into place to avoid shell-escaping the
  /// file body.
  Future<bool> _writeViaAdmin(String content) async {
    final tmp = File(
        '${Directory.systemTemp.path}/fluttermamp-hosts-${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(content);
    final script =
        'do shell script "cp \'${tmp.path}\' /etc/hosts" with administrator privileges';
    final result = await Process.run('osascript', ['-e', script]);
    try {
      await tmp.delete();
    } catch (_) {}
    return result.exitCode == 0;
  }
}
