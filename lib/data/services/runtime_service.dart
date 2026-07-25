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

  String get root => '$_home/Library/Application Support/FlutterMamp/runtime';
  String get binDir => '$root/bin';

  /// Absolute path to the service's binary, or null if not installed yet.
  String? binaryFor(ServiceType type) {
    final path = '$binDir/${type.binaryName}';
    return File(path).existsSync() ? path : null;
  }
}
