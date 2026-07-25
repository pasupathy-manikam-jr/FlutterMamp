import 'dart:io';

import '../../domain/models/service_type.dart';

/// Locates FlutterMamp's OWN bundled binaries.
///
/// This is the independence boundary: binaries live under the app's runtime
/// directory (downloaded/built), never `/Applications/MAMP`. As we move fully
/// off MAMP, web-server binaries will live here too.
class RuntimeService {
  RuntimeService({String? homeOverride})
      : _home = homeOverride ??
            Platform.environment['HOME'] ??
            Directory.systemTemp.path;

  final String _home;

  // A space-free path: several bundled tools are built with autotools/make,
  // which mishandle spaces (as in "Application Support"). Runtime data that is
  // only *used* at run time (datadirs) can still live under Application Support.
  String get root => '$_home/.fluttermamp/runtime';
  String get binDir => '$root/bin';

  /// Absolute path to the service's binary, or null if not installed yet.
  String? binaryFor(ServiceType type) {
    final path = '$root/${type.relativePath}';
    return File(path).existsSync() ? path : null;
  }

  /// The directory holding [type]'s install tree (its basedir), e.g. the MySQL
  /// distribution root. Derived from the binary's relative path.
  String baseDirFor(ServiceType type) {
    // relativePath like "mysql/bin/mysqld" → basedir "<root>/mysql".
    final parts = type.relativePath.split('/');
    if (parts.length >= 3) return '$root/${parts.first}';
    return root;
  }

  // --- web-server binaries (for MAMP-free Sites) ---
  String? _exists(String path) => File(path).existsSync() ? path : null;

  /// Our own Nginx binary, or null if not installed.
  String? get nginxBinary => _exists('$root/nginx/sbin/nginx');

  /// Our own php-fpm binary, or null if not installed.
  String? get phpFpmBinary => _exists('$root/bin/php-fpm');

  /// Our own PHP CLI binary, or null if not installed.
  String? get phpCliBinary => _exists('$root/bin/php');

  /// Our own MySQL client binary, or null if not installed.
  String? get mysqlClient => _exists('$root/mysql/bin/mysql');
}
