import 'dart:io';

/// Thin wrapper around macOS system integration points we need.
///
/// Kept as a service (not a plugin) so the app stays free of native plugin
/// dependencies — and therefore free of a CocoaPods requirement.
class SystemService {
  /// Open [url] in the user's default browser via the macOS `open` command.
  Future<void> openUrl(String url) async {
    await Process.run('open', [url]);
  }

  /// Reveal a path in Finder.
  Future<void> revealInFinder(String path) async {
    await Process.run('open', ['-R', path]);
  }

  /// Show a native macOS "choose folder" dialog and return the selected path,
  /// or null if the user cancels. Uses `osascript` so we need no file-picker
  /// plugin (and therefore no CocoaPods).
  Future<String?> chooseFolder({
    String prompt = 'Select the document root',
  }) async {
    final escaped = prompt.replaceAll('"', r'\"');
    final result = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose folder with prompt "$escaped")',
    ]);
    if (result.exitCode != 0) return null; // user cancelled (osascript -128)
    final path = (result.stdout as String).trim();
    if (path.isEmpty) return null;
    // Strip any trailing slash for consistency.
    return path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
  }

  /// Show a native "choose file" dialog and return the selected path, or null
  /// if cancelled. Plugin-free (osascript).
  Future<String?> chooseFile({String prompt = 'Select a file'}) async {
    final escaped = prompt.replaceAll('"', r'\"');
    final result = await Process.run('osascript', [
      '-e',
      'POSIX path of (choose file with prompt "$escaped")',
    ]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }

  /// Add [certPath] to the System keychain as a trusted root so browsers accept
  /// the self-signed certificate (the "green padlock"). Requires admin, so it
  /// goes through the native `osascript … with administrator privileges` prompt.
  /// Returns true on success (or if the user completes the prompt).
  Future<bool> trustCertificate(String certPath) async {
    final script = 'do shell script '
        '"security add-trusted-cert -d -r trustRoot '
        "-k /Library/Keychains/System.keychain '$certPath'\" "
        'with administrator privileges';
    final result = await Process.run('osascript', ['-e', script]);
    return result.exitCode == 0;
  }
}

