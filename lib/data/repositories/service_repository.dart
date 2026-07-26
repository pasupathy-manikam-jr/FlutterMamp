import 'dart:async';

import '../../domain/models/managed_service.dart';
import '../../domain/models/server_status.dart';
import '../../domain/models/service_type.dart';
import '../../domain/models/tool_type.dart';
import '../services/config_service.dart' show LaunchSpec;
import '../services/database_service.dart';
import '../services/runtime_service.dart';
import '../services/server_process_service.dart';
import '../services/service_launcher.dart';
import '../services/system_service.dart';

/// Single source of truth for the global background services (Redis, MySQL,
/// Memcached, MailHog). Manages our OWN runtime binaries — independent of MAMP.
class ServiceRepository {
  ServiceRepository({
    required RuntimeService runtimeService,
    required ServiceLauncher serviceLauncher,
    required ServerProcessService processService,
    required DatabaseService databaseService,
    required SystemService systemService,
  })  : _runtimeService = runtimeService,
        _serviceLauncher = serviceLauncher,
        _processService = processService,
        _databaseService = databaseService,
        _systemService = systemService;

  final RuntimeService _runtimeService;
  final ServiceLauncher _serviceLauncher;
  final ServerProcessService _processService;
  final DatabaseService _databaseService;
  final SystemService _systemService;

  bool get mysqlClientAvailable => _runtimeService.mysqlClient != null;

  /// Native picker for a `.sql`/`.sql.gz` dump.
  Future<String?> chooseSqlFile() =>
      _systemService.chooseFile(prompt: 'Select a .sql or .sql.gz dump');

  /// Import [dumpPath] into [database] (creates it if missing).
  Future<DbResult> importDump({
    required String dumpPath,
    required String database,
    String user = 'root',
    String password = 'root',
    void Function(double fraction)? onProgress,
  }) async {
    final client = _runtimeService.mysqlClient;
    if (client == null) {
      return const DbResult(false, 'MySQL client not installed.');
    }
    return _databaseService.importDump(
      mysqlClient: client,
      dumpPath: dumpPath,
      database: database,
      user: user,
      password: password,
      onProgress: onProgress,
    );
  }

  static const int _maxLogLines = 400;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  final List<ManagedService> _services = [];
  final Map<ServiceType, RunningProcess> _processes = {};
  final Map<ToolType, RunningProcess> _tools = {};

  List<ManagedService> get services => List.unmodifiable(_services);
  ManagedService? service(ServiceType type) {
    for (final s in _services) {
      if (s.type == type) return s;
    }
    return null;
  }

  /// Seed one entry per service type, marking availability by binary presence.
  Future<void> initialize() async {
    _services
      ..clear()
      ..addAll(ServiceType.values.map((t) => ManagedService(
            type: t,
            status: ServerStatus.stopped,
            port: t.defaultPort,
            available: _runtimeService.binaryFor(t) != null,
          )));
    _notify();
  }

  /// Re-check binary availability (e.g. after an on-demand runtime download)
  /// without disturbing services that are already running.
  void refreshAvailability() {
    for (var i = 0; i < _services.length; i++) {
      final s = _services[i];
      final avail = _runtimeService.binaryFor(s.type) != null;
      if (avail != s.available) _services[i] = s.copyWith(available: avail);
    }
    _notify();
  }

  Future<void> start(ServiceType type) async {
    final current = service(type);
    if (current == null ||
        !current.available ||
        current.status.isActive ||
        current.status.isTransitioning) {
      return;
    }
    final binary = _runtimeService.binaryFor(type);
    if (binary == null) return;

    _replace(current.copyWith(
        status: ServerStatus.starting, clearError: true, logLines: const []));
    try {
      final spec = await _serviceLauncher.prepare(service(type)!, binary);
      final running = await _processService.start(
        spec,
        onLog: (line) => _appendLog(type, line),
        onExit: (code) => _onExit(type, code),
      );
      _processes[type] = running;
      _replace(service(type)!
          .copyWith(status: ServerStatus.running, pid: running.pid));
    } catch (e) {
      _replace(service(type)!.copyWith(
          status: ServerStatus.error,
          errorMessage: e.toString(),
          clearPid: true));
    }
  }

  Future<void> stop(ServiceType type) async {
    final running = _processes[type];
    if (running == null) return;
    final current = service(type);
    if (current != null) {
      _replace(current.copyWith(status: ServerStatus.stopping));
    }
    await _processService.stop(running);
  }

  void _onExit(ServiceType type, int exitCode) {
    _processes.remove(type);
    final current = service(type);
    if (current == null) return;
    final graceful = exitCode == 0 || current.status == ServerStatus.stopping;
    _replace(current.copyWith(
      status: graceful ? ServerStatus.stopped : ServerStatus.error,
      errorMessage: graceful ? null : 'Exited with code $exitCode',
      clearError: graceful,
      clearPid: true,
    ));
  }

  void _appendLog(ServiceType type, String line) {
    final current = service(type);
    if (current == null) return;
    final lines = [...current.logLines, line];
    if (lines.length > _maxLogLines) {
      lines.removeRange(0, lines.length - _maxLogLines);
    }
    _replace(current.copyWith(logLines: lines));
  }

  void _replace(ManagedService updated) {
    final i = _services.indexWhere((s) => s.type == updated.type);
    if (i == -1) return;
    _services[i] = updated;
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // --- bundled web tools (Adminer / phpMyAdmin via FrankenPHP) -------------

  List<ToolType> get toolTypes => ToolType.values;

  bool isToolRunning(ToolType type) => _tools.containsKey(type);

  bool toolAvailable(ToolType type) =>
      _runtimeService.phpCliBinary != null &&
      _runtimeService.toolRoot(type.dirName) != null;

  /// Start the tool's server (if not already running) and open it in a browser.
  ///
  /// The DB tools are plain PHP web apps, so we serve them with the bundled PHP
  /// CLI's built-in server (`php -S`) — no separate web server needed.
  Future<void> openTool(ToolType type) async {
    if (!_tools.containsKey(type)) {
      final php = _runtimeService.phpCliBinary;
      final root = _runtimeService.toolRoot(type.dirName);
      if (php == null || root == null) return;
      final spec = LaunchSpec(
        executable: php,
        arguments: ['-S', '127.0.0.1:${type.port}', '-t', root],
        workingDirectory: root,
        environment: {
          // Suppress PHP deprecation noise from tool vendor libs.
          'PHP_INI_SCAN_DIR': '${_runtimeService.root}/etc/php-tools',
          // php -S is single-threaded by default; workers let phpMyAdmin load
          // its assets concurrently instead of one request at a time.
          'PHP_CLI_SERVER_WORKERS': '4',
        },
      );
      final running = await _processService.start(
        spec,
        onLog: (_) {},
        onExit: (_) {
          _tools.remove(type);
          _notify();
        },
      );
      _tools[type] = running;
      _notify();
      // Give FrankenPHP a moment to bind before opening the browser.
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    await _systemService.openUrl(type.url);
  }

  Future<void> stopTool(ToolType type) async {
    final running = _tools.remove(type);
    if (running != null) await _processService.stop(running);
    _notify();
  }

  Future<void> dispose() async {
    for (final p in _processes.values) {
      await _processService.stop(p);
    }
    for (final p in _tools.values) {
      await _processService.stop(p);
    }
    _processes.clear();
    _tools.clear();
    await _changes.close();
  }
}
