import 'php_version.dart';
import 'server_status.dart';
import 'server_type.dart';

/// A user-created site (host): a named document root served by a chosen engine,
/// optionally under a custom hostname and/or HTTPS.
///
/// Central domain model — the app manages a list of these, like MAMP PRO's
/// Hosts. Config fields are persisted; runtime fields (status, pid, logs) are
/// not.
class Site {
  const Site({
    required this.id,
    required this.name,
    required this.documentRoot,
    required this.server,
    required this.port,
    this.hostname = '',
    this.sslEnabled = false,
    this.sslPort = 8443,
    this.phpVersion,
    this.status = ServerStatus.stopped,
    this.pid,
    this.errorMessage,
    this.logLines = const [],
  });

  final String id;
  final String name;
  final String documentRoot;

  /// Engine that serves this site (Apache or Nginx).
  final ServerType server;

  /// Plain HTTP port.
  final int port;

  /// Optional custom hostname (e.g. `cp4.local`). Empty → served on 127.0.0.1.
  /// When set, a `127.0.0.1 <hostname>` entry is added to /etc/hosts on start.
  final String hostname;

  /// Whether HTTPS is enabled (self-signed cert).
  final bool sslEnabled;

  /// HTTPS port used when [sslEnabled].
  final int sslPort;

  /// Selected PHP toolchain, executed via FastCGI.
  final PhpVersion? phpVersion;

  // --- runtime (not persisted) ---
  final ServerStatus status;
  final int? pid;
  final String? errorMessage;
  final List<String> logLines;

  /// Host used in the URL — the custom hostname if set, else loopback.
  String get host => hostname.isNotEmpty ? hostname : '127.0.0.1';

  /// The primary URL to open in a browser.
  String get url =>
      sslEnabled ? 'https://$host:$sslPort' : 'http://$host:$port';

  Site copyWith({
    String? name,
    String? documentRoot,
    ServerType? server,
    int? port,
    String? hostname,
    bool? sslEnabled,
    int? sslPort,
    PhpVersion? phpVersion,
    ServerStatus? status,
    int? pid,
    bool clearPid = false,
    String? errorMessage,
    bool clearError = false,
    List<String>? logLines,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      documentRoot: documentRoot ?? this.documentRoot,
      server: server ?? this.server,
      port: port ?? this.port,
      hostname: hostname ?? this.hostname,
      sslEnabled: sslEnabled ?? this.sslEnabled,
      sslPort: sslPort ?? this.sslPort,
      phpVersion: phpVersion ?? this.phpVersion,
      status: status ?? this.status,
      pid: clearPid ? null : (pid ?? this.pid),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      logLines: logLines ?? this.logLines,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'documentRoot': documentRoot,
        'server': server.name,
        'port': port,
        'hostname': hostname,
        'sslEnabled': sslEnabled,
        'sslPort': sslPort,
        if (phpVersion != null) 'phpBinaryPath': phpVersion!.binaryPath,
      };

  static Site? fromJson(
    Map<String, dynamic> json,
    PhpVersion? Function(String? binaryPath) resolvePhp,
  ) {
    final id = json['id'];
    final name = json['name'];
    final docRoot = json['documentRoot'];
    final serverName = json['server'];
    final port = json['port'];
    if (id is! String ||
        name is! String ||
        docRoot is! String ||
        serverName is! String ||
        port is! int) {
      return null;
    }
    final server = ServerType.values.where((t) => t.name == serverName);
    if (server.isEmpty) return null; // e.g. legacy "php" engine → dropped
    return Site(
      id: id,
      name: name,
      documentRoot: docRoot,
      server: server.first,
      port: port,
      hostname: json['hostname'] as String? ?? '',
      sslEnabled: json['sslEnabled'] as bool? ?? false,
      sslPort: json['sslPort'] as int? ?? 8443,
      phpVersion: resolvePhp(json['phpBinaryPath'] as String?),
    );
  }
}
