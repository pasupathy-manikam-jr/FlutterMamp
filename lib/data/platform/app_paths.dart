import 'dart:io';

/// Cross-platform application paths.
///
/// macOS deliberately keeps its ORIGINAL hidden locations (`Application Support/
/// FlutterMamp` and `~/.fluttermamp/runtime`) so existing installs don't lose
/// their data/runtime on the rebrand. These are internal paths, never shown in
/// UI. Linux and Windows are new installs, so they use the current name.
///
/// Two roots:
///  - [supportDir] — mutable app data: sites.json, conf/, logs/, certs/,
///    service datadirs. Spaces are tolerated here (only read/written at run
///    time), except where a tool disagrees.
///  - [runtimeDir] — bundled/downloaded binaries. Kept **space-free** on every
///    platform because several tools are built/served from here and autotools /
///    some launchers choke on spaces.
class AppPaths {
  AppPaths({Map<String, String>? environment})
      : _env = environment ?? Platform.environment;

  final Map<String, String> _env;

  String get _home =>
      _env['HOME'] ?? _env['USERPROFILE'] ?? Directory.systemTemp.path;

  String get sep => Platform.isWindows ? '\\' : '/';

  /// Mutable application data directory.
  String get supportDir {
    if (Platform.isMacOS) {
      // Keep the original folder name so existing data is not orphaned.
      return '$_home/Library/Application Support/FlutterMamp';
    }
    if (Platform.isWindows) {
      final appData = _env['APPDATA'] ?? '$_home\\AppData\\Roaming';
      return '$appData\\OricDevServer';
    }
    // Linux / other Unix — XDG.
    final xdg = _env['XDG_DATA_HOME'] ?? '$_home/.local/share';
    return '$xdg/OricDevServer';
  }

  /// Space-free directory holding our own binaries.
  String get runtimeDir {
    if (Platform.isWindows) {
      final local = _env['LOCALAPPDATA'] ?? '$_home\\AppData\\Local';
      return '$local\\OricDevServer\\runtime';
    }
    // macOS keeps its existing location; Linux mirrors it.
    return '$_home/.fluttermamp/runtime';
  }

  // Convenience sub-paths under supportDir.
  String get confDir => '$supportDir${sep}conf';
  String get logDir => '$supportDir${sep}logs';
  String get certsDir => '$supportDir${sep}certs';
  String get dataDir => '$supportDir${sep}data';
  String get sitesFile => '$supportDir${sep}sites.json';
}
