import 'dart:async';

import '../../domain/models/mamp_environment.dart';
import '../../domain/models/php_version.dart';
import '../../domain/models/server_status.dart';
import '../../domain/models/server_type.dart';
import '../../domain/models/site.dart';
import '../services/config_service.dart';
import '../services/hosts_service.dart';
import '../services/mamp_service.dart';
import '../services/server_process_service.dart';
import '../services/settings_service.dart';
import '../services/system_service.dart';

/// Single source of truth for the user's sites.
///
/// Owns the site list, orchestrates the services (discovery, config, process,
/// persistence, hosts, system), and emits on [changes] on every update. Each
/// running site is backed by a small list of processes: a `php-cgi` FastCGI
/// handler plus the web server.
class SiteRepository {
  SiteRepository({
    required MampService mampService,
    required ConfigService configService,
    required ServerProcessService processService,
    required SettingsService settingsService,
    required SystemService systemService,
    required HostsService hostsService,
  })  : _mampService = mampService,
        _configService = configService,
        _processService = processService,
        _settingsService = settingsService,
        _systemService = systemService,
        _hostsService = hostsService;

  final MampService _mampService;
  final ConfigService _configService;
  final ServerProcessService _processService;
  final SettingsService _settingsService;
  final SystemService _systemService;
  final HostsService _hostsService;

  static const int _maxLogLines = 500;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  MampEnvironment _environment = MampEnvironment.none;
  MampEnvironment get environment => _environment;

  final List<Site> _sites = [];
  final Map<String, List<RunningProcess>> _processes = {};

  int _idCounter = 0;

  List<Site> get sites => List.unmodifiable(_sites);
  Site? site(String id) {
    for (final s in _sites) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<void> initialize() async {
    _environment = await _mampService.discover();

    final loaded = await _settingsService.loadSites(_resolvePhp);
    _sites
      ..clear()
      ..addAll(loaded);

    if (_sites.isEmpty && _environment.isPresent) {
      _sites.add(Site(
        id: _newId(),
        name: 'localhost',
        documentRoot: _environment.defaultDocumentRoot,
        server: ServerType.apache,
        port: 8000,
        phpVersion: _environment.defaultPhp,
      ));
      await _persist();
    }
    _notify();
  }

  PhpVersion? _resolvePhp(String? binaryPath) {
    if (binaryPath != null) {
      for (final v in _environment.phpVersions) {
        if (v.binaryPath == binaryPath) return v;
      }
    }
    return _environment.defaultPhp;
  }

  String _newId() =>
      'site-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  int suggestPort() {
    final used = _sites.expand((s) => [s.port, s.sslPort]).toSet();
    var port = 8000;
    while (used.contains(port)) {
      port++;
    }
    return port;
  }

  // --- CRUD ----------------------------------------------------------------

  Future<String> addSite({
    required String name,
    required String documentRoot,
    required ServerType server,
    required int port,
    String hostname = '',
    bool sslEnabled = false,
    int sslPort = 8443,
    PhpVersion? phpVersion,
  }) async {
    final id = _newId();
    _sites.add(Site(
      id: id,
      name: name,
      documentRoot: documentRoot,
      server: server,
      port: port,
      hostname: hostname,
      sslEnabled: sslEnabled,
      sslPort: sslPort,
      phpVersion: phpVersion ?? _environment.defaultPhp,
    ));
    await _persist();
    _notify();
    return id;
  }

  Future<void> updateSite(
    String id, {
    String? name,
    String? documentRoot,
    ServerType? server,
    int? port,
    String? hostname,
    bool? sslEnabled,
    int? sslPort,
    PhpVersion? phpVersion,
  }) async {
    final current = site(id);
    if (current == null || current.status.isActive) return;
    _replace(current.copyWith(
      name: name,
      documentRoot: documentRoot,
      server: server,
      port: port,
      hostname: hostname,
      sslEnabled: sslEnabled,
      sslPort: sslPort,
      phpVersion: phpVersion,
    ));
    await _persist();
  }

  Future<void> deleteSite(String id) async {
    final procs = _processes.remove(id);
    if (procs != null) {
      for (final p in procs) {
        await _processService.stop(p);
      }
    }
    final removed = site(id);
    _sites.removeWhere((s) => s.id == id);
    if (removed != null && removed.hostname.isNotEmpty) {
      unawaited(_hostsService.removeMapping(removed.hostname));
    }
    await _persist();
    _notify();
  }

  // --- lifecycle -----------------------------------------------------------

  Future<void> start(String id) async {
    final current = site(id);
    if (current == null ||
        current.status.isActive ||
        current.status.isTransitioning) {
      return;
    }

    _replace(current.copyWith(
      status: ServerStatus.starting,
      clearError: true,
      logLines: const [],
    ));

    final procs = <RunningProcess>[];
    try {
      final s = site(id)!;
      if (s.hostname.isNotEmpty) {
        final ok = await _hostsService.ensureMapping(s.hostname);
        if (!ok) {
          _appendLog(id,
              '[hosts] Could not map ${s.hostname} (admin cancelled); serving on 127.0.0.1 only.');
        }
      }

      final launch = await _configService.prepare(site(id)!, _environment);
      for (var i = 0; i < launch.steps.length; i++) {
        final isServer = i == launch.steps.length - 1;
        final rp = await _processService.start(
          launch.steps[i],
          onLog: (line) => _appendLog(id, isServer ? line : '[php] $line'),
          onExit: (code) => isServer
              ? _onServerExit(id, code)
              : _appendLog(id, '[php-cgi] exited ($code)'),
        );
        procs.add(rp);
      }
      _processes[id] = procs;
      _replace(site(id)!
          .copyWith(status: ServerStatus.running, pid: procs.last.pid));
    } catch (e) {
      for (final p in procs) {
        unawaited(_processService.stop(p));
      }
      _processes.remove(id);
      _replace(site(id)!.copyWith(
        status: ServerStatus.error,
        errorMessage: e.toString(),
        clearPid: true,
      ));
    }
  }

  Future<void> stop(String id) async {
    final procs = _processes[id];
    if (procs == null || procs.isEmpty) return;
    final current = site(id);
    if (current != null) {
      _replace(current.copyWith(status: ServerStatus.stopping));
    }
    // Stopping the web server (last) triggers [_onServerExit], which settles
    // status and tears down the FastCGI process too.
    await _processService.stop(procs.last);
  }

  void _onServerExit(String id, int exitCode) {
    final procs = _processes.remove(id) ?? const <RunningProcess>[];
    for (final p in procs) {
      unawaited(_processService.stop(p)); // ensure php-cgi is torn down
    }
    final current = site(id);
    if (current == null) return;
    final graceful = exitCode == 0 || current.status == ServerStatus.stopping;
    _replace(current.copyWith(
      status: graceful ? ServerStatus.stopped : ServerStatus.error,
      errorMessage: graceful ? null : 'Web server exited with code $exitCode',
      clearError: graceful,
      clearPid: true,
    ));
  }

  // --- system actions ------------------------------------------------------

  Future<void> openInBrowser(String id) async {
    final s = site(id);
    if (s != null) await _systemService.openUrl(s.url);
  }

  Future<void> revealDocumentRoot(String id) async {
    final s = site(id);
    if (s != null) await _systemService.revealInFinder(s.documentRoot);
  }

  Future<String?> chooseFolder() => _systemService.chooseFolder();

  /// Generate (if needed) and trust the site's TLS certificate in the Keychain.
  /// Returns false if the site is unknown or OpenSSL is unavailable.
  Future<bool> trustCertificate(String id) async {
    final s = site(id);
    if (s == null) return false;
    final certPath = await _configService.ensureCert(s, _environment);
    if (certPath == null) return false;
    return _systemService.trustCertificate(certPath);
  }

  // --- internals -----------------------------------------------------------

  void _appendLog(String id, String line) {
    final current = site(id);
    if (current == null) return;
    final lines = [...current.logLines, line];
    if (lines.length > _maxLogLines) {
      lines.removeRange(0, lines.length - _maxLogLines);
    }
    _replace(current.copyWith(logLines: lines));
  }

  void _replace(Site updated) {
    final index = _sites.indexWhere((s) => s.id == updated.id);
    if (index == -1) return;
    _sites[index] = updated;
    _notify();
  }

  Future<void> _persist() => _settingsService.saveSites(_sites);

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> dispose() async {
    for (final procs in _processes.values) {
      for (final p in procs) {
        await _processService.stop(p);
      }
    }
    _processes.clear();
    await _changes.close();
  }
}
