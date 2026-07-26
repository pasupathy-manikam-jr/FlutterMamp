import 'dart:io';

/// System integration (open URLs, native file/folder pickers, trust certs)
/// implemented with each platform's native tools — **no plugins**, so the
/// macOS build stays CocoaPods-free.
///
/// macOS paths are the original, tested implementations. Linux (xdg-open /
/// zenity / pkexec) and Windows (start / PowerShell / certutil) are best-effort
/// and will be hardened during per-OS testing (Phase 3).
class SystemService {
  const SystemService();

  /// Open [url] in the default browser.
  Future<void> openUrl(String url) async {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else {
      await Process.run('xdg-open', [url]);
    }
  }

  /// Reveal a path in the OS file manager.
  Future<void> revealInFinder(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else {
      // Open the containing directory.
      final dir = FileSystemEntity.isDirectorySync(path)
          ? path
          : File(path).parent.path;
      await Process.run('xdg-open', [dir]);
    }
  }

  /// Native "choose folder" dialog; returns the path or null if cancelled.
  Future<String?> chooseFolder({String prompt = 'Select a folder'}) async {
    if (Platform.isMacOS) {
      return _osascriptPath(
          'POSIX path of (choose folder with prompt "${_esc(prompt)}")');
    }
    if (Platform.isWindows) {
      return _powershellPath('''
Add-Type -AssemblyName System.Windows.Forms
\$d = New-Object System.Windows.Forms.FolderBrowserDialog
\$d.Description = "${_esc(prompt)}"
if (\$d.ShowDialog() -eq "OK") { \$d.SelectedPath }
''');
    }
    return _stdoutPath('zenity', [
      '--file-selection',
      '--directory',
      '--title=$prompt',
    ]);
  }

  /// Native "choose file" dialog; returns the path or null if cancelled.
  Future<String?> chooseFile({String prompt = 'Select a file'}) async {
    if (Platform.isMacOS) {
      return _osascriptPath(
          'POSIX path of (choose file with prompt "${_esc(prompt)}")');
    }
    if (Platform.isWindows) {
      return _powershellPath('''
Add-Type -AssemblyName System.Windows.Forms
\$d = New-Object System.Windows.Forms.OpenFileDialog
\$d.Title = "${_esc(prompt)}"
if (\$d.ShowDialog() -eq "OK") { \$d.FileName }
''');
    }
    return _stdoutPath('zenity', ['--file-selection', '--title=$prompt']);
  }

  /// Trust a CA certificate at the OS level (requires elevation).
  Future<bool> trustCertificate(String certPath) async {
    if (Platform.isMacOS) {
      final script = 'do shell script '
          '"security add-trusted-cert -d -r trustRoot '
          "-k /Library/Keychains/System.keychain '$certPath'\" "
          'with administrator privileges';
      final r = await Process.run('osascript', ['-e', script]);
      return r.exitCode == 0;
    }
    if (Platform.isWindows) {
      // certutil -addstore Root needs admin; relaunch elevated via PowerShell.
      final r = await Process.run('powershell', [
        '-Command',
        "Start-Process certutil -ArgumentList '-addstore','Root','$certPath' "
            "-Verb RunAs -Wait"
      ]);
      return r.exitCode == 0;
    }
    // Linux (Debian/Ubuntu system store). Browsers using NSS may need separate
    // trust — revisit in Phase 3.
    final name = 'oricmamp-ca.crt';
    final r = await Process.run('pkexec', [
      'sh',
      '-c',
      'cp "$certPath" /usr/local/share/ca-certificates/$name && update-ca-certificates',
    ]);
    return r.exitCode == 0;
  }

  // --- helpers -------------------------------------------------------------

  String _esc(String s) => s.replaceAll('"', r'\"');

  Future<String?> _osascriptPath(String appleScript) async {
    final r = await Process.run('osascript', ['-e', appleScript]);
    if (r.exitCode != 0) return null;
    final path = (r.stdout as String).trim();
    if (path.isEmpty) return null;
    return path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
  }

  Future<String?> _stdoutPath(String exe, List<String> args) async {
    try {
      final r = await Process.run(exe, args);
      if (r.exitCode != 0) return null;
      final path = (r.stdout as String).trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null; // tool not installed
    }
  }

  Future<String?> _powershellPath(String script) async {
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-Command', script]);
      if (r.exitCode != 0) return null;
      final path = (r.stdout as String).trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }
}
