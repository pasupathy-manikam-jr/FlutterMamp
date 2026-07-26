import 'dart:io';

import '../../domain/models/service_type.dart';
import '../platform/app_paths.dart';

/// Locates OricDevServer's OWN bundled binaries.
///
/// This is the independence boundary: binaries live under the app's runtime
/// directory (downloaded/built), never `/Applications/MAMP`.
class RuntimeService {
  RuntimeService({AppPaths? paths}) : _paths = paths ?? AppPaths();

  final AppPaths _paths;

  // Space-free runtime root (see AppPaths). Internal joins use '/', which Dart
  // accepts on Windows too.
  String get root => _paths.runtimeDir;
  String get binDir => '$root/bin';

  /// Resolve a binary path, tolerating a `.exe` suffix on Windows.
  String? _bin(String path) {
    if (File(path).existsSync()) return path;
    if (Platform.isWindows && File('$path.exe').existsSync()) return '$path.exe';
    return null;
  }

  /// Absolute path to the service's binary, or null if not installed yet.
  String? binaryFor(ServiceType type) => _bin('$root/${type.relativePath}');

  /// The directory holding [type]'s install tree (its basedir), e.g. the MySQL
  /// distribution root. Derived from the binary's relative path.
  String baseDirFor(ServiceType type) {
    // relativePath like "mysql/bin/mysqld" → basedir "<root>/mysql".
    final parts = type.relativePath.split('/');
    if (parts.length >= 3) return '$root/${parts.first}';
    return root;
  }

  // --- web-server binaries (for MAMP-free Sites) ---

  /// Our own Nginx binary, or null if not installed.
  String? get nginxBinary => _bin('$root/nginx/sbin/nginx');

  /// Our own Apache httpd binary, or null if not installed.
  String? get apacheBinary => _bin('$root/apache/bin/httpd');

  /// Apache ServerRoot (its install tree), or null if not installed.
  String? get apacheRoot => apacheBinary != null ? '$root/apache' : null;

  /// Our own php-fpm binary, or null if not installed. (None on Windows — PHP
  /// there has no php-fpm SAPI; sites serve via FrankenPHP instead.)
  String? get phpFpmBinary => _bin('$root/bin/php-fpm');

  /// Our own PHP CLI binary, or null if not installed.
  String? get phpCliBinary => _bin('$root/bin/php');

  /// Our own MySQL client binary, or null if not installed.
  String? get mysqlClient => _bin('$root/mysql/bin/mysql');

  /// FrankenPHP binary (serves the bundled web tools; has mysqli), or null.
  String? get frankenphpBinary => _bin('$root/bin/frankenphp');

  /// Document root for a bundled tool (e.g. `adminer`), or null if missing.
  String? toolRoot(String dirName) {
    final path = '$root/tools/$dirName';
    return Directory(path).existsSync() ? path : null;
  }
}
