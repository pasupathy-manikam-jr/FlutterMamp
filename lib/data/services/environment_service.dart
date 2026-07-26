import 'dart:io';

import '../../domain/models/dev_environment.dart';
import '../../domain/models/php_version.dart';

/// Discovers a local MAMP installation and its binaries.
///
/// Stateless service: it only reads the filesystem and returns clean domain
/// models. All MAMP-specific path knowledge lives here so the rest of the app
/// stays installation-agnostic.
class EnvironmentService {
  EnvironmentService({String? rootPath})
      : rootPath = rootPath ?? _defaultRoot;

  static const String _defaultRoot = '/Applications/MAMP';

  /// MAMP application root to scan.
  final String rootPath;

  /// Scan the installation and return an immutable [DevEnvironment].
  ///
  /// Returns [DevEnvironment.none] when MAMP is not installed at [rootPath].
  Future<DevEnvironment> discover() async {
    if (!Directory(rootPath).existsSync()) {
      return DevEnvironment.none;
    }

    final apache = _firstExisting([
      '$rootPath/Library/bin/httpd',
      '$rootPath/Library/bin/apache2/bin/httpd',
    ]);
    final nginx = _firstExisting([
      '$rootPath/Library/sbin/nginx',
      '$rootPath/Library/bin/nginx',
    ]);

    final openssl = _firstExisting([
      '$rootPath/Library/bin/openssl',
      '$rootPath/Library/OpenSSL/bin/openssl',
    ]);

    final phpVersions = await _discoverPhpVersions();
    final docRoot = Directory('$rootPath/htdocs').existsSync()
        ? '$rootPath/htdocs'
        : rootPath;

    return DevEnvironment(
      rootPath: rootPath,
      apacheBinary: apache,
      nginxBinary: nginx,
      phpVersions: phpVersions,
      defaultDocumentRoot: docRoot,
      opensslBinary: openssl,
    );
  }

  /// Find every `bin/php/php<version>/bin/php` toolchain, newest first.
  Future<List<PhpVersion>> _discoverPhpVersions() async {
    final phpRoot = Directory('$rootPath/bin/php');
    if (!phpRoot.existsSync()) return const [];

    final versions = <PhpVersion>[];
    for (final entry in phpRoot.listSync().whereType<Directory>()) {
      final name = entry.path.split('/').last; // e.g. "php8.3.30"
      final match = RegExp(r'^php(\d+\.\d+\.\d+)$').firstMatch(name);
      if (match == null) continue; // skip the bare "php" symlink dir

      final binary = '${entry.path}/bin/php';
      if (!File(binary).existsSync()) continue;

      final cgi = '${entry.path}/bin/php-cgi';
      versions.add(PhpVersion(
        version: match.group(1)!,
        binaryPath: binary,
        cgiPath: File(cgi).existsSync() ? cgi : null,
      ));
    }

    versions.sort((a, b) => b.compareTo(a)); // newest first
    return versions;
  }

  String? _firstExisting(List<String> candidates) {
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }
}
