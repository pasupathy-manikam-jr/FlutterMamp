import 'dart:async';

import '../../domain/models/managed_service.dart';
import '../../domain/models/server_status.dart';
import '../../domain/models/service_type.dart';
import '../services/runtime_service.dart';
import '../services/server_process_service.dart';
import '../services/service_launcher.dart';

/// Single source of truth for the global background services (Redis, MySQL,
/// Memcached, MailHog). Manages our OWN runtime binaries — independent of MAMP.
class ServiceRepository {
  ServiceRepository({
    required RuntimeService runtimeService,
    required ServiceLauncher serviceLauncher,
    required ServerProcessService processService,
  })  : _runtimeService = runtimeService,
        _serviceLauncher = serviceLauncher,
        _processService = processService;

  final RuntimeService _runtimeService;
  final ServiceLauncher _serviceLauncher;
  final ServerProcessService _processService;

  static const int _maxLogLines = 400;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  final List<ManagedService> _services = [];
  final Map<ServiceType, RunningProcess> _processes = {};

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

  Future<void> dispose() async {
    for (final p in _processes.values) {
      await _processService.stop(p);
    }
    _processes.clear();
    await _changes.close();
  }
}
