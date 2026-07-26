import 'php_version.dart';

/// A snapshot of the MAMP installation discovered on this machine.
///
/// Produced by [EnvironmentService]; treated as an immutable single source of truth
/// for "what binaries exist and where".
class DevEnvironment {
  const DevEnvironment({
    required this.rootPath,
    required this.apacheBinary,
    required this.nginxBinary,
    required this.phpVersions,
    required this.defaultDocumentRoot,
    this.opensslBinary,
  });

  /// The MAMP application root, e.g. `/Applications/MAMP`.
  final String rootPath;

  /// Absolute path to the Apache `httpd` binary, or null if not found.
  final String? apacheBinary;

  /// Absolute path to the Nginx binary, or null if not found.
  final String? nginxBinary;

  /// Absolute path to MAMP's `openssl`, used to generate self-signed certs.
  final String? opensslBinary;

  /// All PHP toolchains found, sorted newest-first.
  final List<PhpVersion> phpVersions;

  /// MAMP's default web root, e.g. `/Applications/MAMP/htdocs`.
  final String defaultDocumentRoot;

  bool get hasApache => apacheBinary != null;
  bool get hasNginx => nginxBinary != null;
  bool get hasPhp => phpVersions.isNotEmpty;

  /// The newest PHP toolchain, used as the default selection.
  PhpVersion? get defaultPhp =>
      phpVersions.isEmpty ? null : phpVersions.first;

  /// An empty environment used before discovery completes or when MAMP is
  /// missing.
  static const DevEnvironment none = DevEnvironment(
    rootPath: '',
    apacheBinary: null,
    nginxBinary: null,
    phpVersions: [],
    defaultDocumentRoot: '',
  );

  bool get isPresent => rootPath.isNotEmpty;
}
