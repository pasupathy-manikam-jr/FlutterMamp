import 'dart:convert';
import 'dart:io';

import '../../domain/models/php_version.dart';
import '../../domain/models/site.dart';
import '../platform/app_paths.dart';

/// Reads and writes the list of sites to a JSON file under the app-support
/// directory. Stateless wrapper around the filesystem.
class SettingsService {
  SettingsService({AppPaths? paths}) : _paths = paths ?? AppPaths();

  final AppPaths _paths;

  String get _filePath => _paths.sitesFile;

  /// Load persisted sites. [resolvePhp] maps a stored PHP binary path back to a
  /// discovered [PhpVersion]. Returns an empty list when no file exists or it
  /// is unreadable/corrupt.
  Future<List<Site>> loadSites(
    PhpVersion? Function(String? binaryPath) resolvePhp,
  ) async {
    final file = File(_filePath);
    if (!file.existsSync()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final sites = <Site>[];
      for (final raw in decoded) {
        if (raw is Map<String, dynamic>) {
          final site = Site.fromJson(raw, resolvePhp);
          if (site != null) sites.add(site);
        }
      }
      return sites;
    } catch (_) {
      return []; // corrupt file → start fresh
    }
  }

  /// Persist [sites] (write to a temp file then rename).
  Future<void> saveSites(List<Site> sites) async {
    final file = File(_filePath);
    await file.parent.create(recursive: true);
    final json = sites.map((s) => s.toJson()).toList();
    final tmp = File('$_filePath.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await tmp.rename(_filePath);
  }
}
