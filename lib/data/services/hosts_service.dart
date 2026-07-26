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

  static String get _hostsPath => Platform.isWindows
      ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\drivers\\etc\\hosts'
      : '/etc/hosts';

  // Kept as-is so existing macOS /etc/hosts entries stay recognised.
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
        '${Directory.systemTemp.path}/oricmamp-hosts-${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsString(content);
    try {
      if (Platform.isMacOS) {
        final script =
            'do shell script "cp \'${tmp.path}\' $_hostsPath" with administrator privileges';
        final r = await Process.run('osascript', ['-e', script]);
        return r.exitCode == 0;
      } else if (Platform.isWindows) {
        final r = await Process.run('powershell', [
          '-Command',
          "Start-Process powershell -ArgumentList '-Command',"
              "'Copy-Item ""${tmp.path}"" ""$_hostsPath"" -Force' -Verb RunAs -Wait"
        ]);
        return r.exitCode == 0;
      } else {
        final r = await Process.run(
            'pkexec', ['cp', tmp.path, _hostsPath]);
        return r.exitCode == 0;
      }
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
