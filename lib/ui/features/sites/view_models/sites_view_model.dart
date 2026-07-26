import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/site_repository.dart';
import '../../../../domain/models/dev_environment.dart';
import '../../../../domain/models/php_version.dart';
import '../../../../domain/models/server_status.dart';
import '../../../../domain/models/server_type.dart';
import '../../../../domain/models/site.dart';

/// ViewModel for the sites feature (MVVM per the Flutter architecture skill).
class SitesViewModel extends ChangeNotifier {
  SitesViewModel({required SiteRepository repository})
      : _repository = repository {
    _sub = _repository.changes.listen((_) => _syncSelectionAndNotify());
  }

  final SiteRepository _repository;
  late final StreamSubscription<void> _sub;

  bool _initialized = false;
  bool get isReady => _initialized;

  String? _selectedId;

  Future<void> load() async {
    await _repository.initialize();
    _selectedId ??= _repository.sites.isNotEmpty ? _repository.sites.first.id : null;
    _initialized = true;
    notifyListeners();
  }

  DevEnvironment get environment => _repository.environment;
  List<Site> get sites => _repository.sites;
  List<PhpVersion> get phpVersions => environment.phpVersions;

  Site? get selected =>
      _selectedId == null ? null : _repository.site(_selectedId!);

  String? get selectedId => _selectedId;

  int get runningCount => sites.where((s) => s.status.isActive).length;
  bool get anyRunning => runningCount > 0;

  void select(String id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Keep the selection valid when the underlying list changes (e.g. delete).
  void _syncSelectionAndNotify() {
    final ids = sites.map((s) => s.id).toSet();
    if (_selectedId != null && !ids.contains(_selectedId)) {
      _selectedId = sites.isNotEmpty ? sites.first.id : null;
    }
    notifyListeners();
  }

  // --- CRUD ----------------------------------------------------------------

  Future<void> addSite({
    required String name,
    required String documentRoot,
    required ServerType server,
    required int port,
    String hostname = '',
    bool sslEnabled = false,
    int sslPort = 8443,
    String phpIni = '',
    PhpVersion? phpVersion,
  }) async {
    final id = await _repository.addSite(
      name: name,
      documentRoot: documentRoot,
      server: server,
      port: port,
      hostname: hostname,
      sslEnabled: sslEnabled,
      sslPort: sslPort,
      phpIni: phpIni,
      phpVersion: phpVersion,
    );
    _selectedId = id;
    notifyListeners();
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
    String? phpIni,
    PhpVersion? phpVersion,
  }) =>
      _repository.updateSite(
        id,
        name: name,
        documentRoot: documentRoot,
        server: server,
        port: port,
        hostname: hostname,
        sslEnabled: sslEnabled,
        sslPort: sslPort,
        phpIni: phpIni,
        phpVersion: phpVersion,
      );

  Future<void> deleteSite(String id) => _repository.deleteSite(id);

  // --- lifecycle & actions -------------------------------------------------

  Future<void> start(String id) => _repository.start(id);
  Future<void> stop(String id) => _repository.stop(id);

  Future<void> toggle(String id) async {
    final s = _repository.site(id);
    if (s == null) return;
    if (s.status.isActive) {
      await stop(id);
    } else if (!s.status.isTransitioning) {
      await start(id);
    }
  }

  Future<void> toggleAll() async {
    final futures = <Future<void>>[];
    for (final s in sites) {
      if (anyRunning) {
        if (s.status.isActive) futures.add(stop(s.id));
      } else if (s.status == ServerStatus.stopped) {
        futures.add(start(s.id));
      }
    }
    await Future.wait(futures);
  }

  Future<void> openInBrowser(String id) => _repository.openInBrowser(id);
  Future<void> revealDocumentRoot(String id) =>
      _repository.revealDocumentRoot(id);

  /// Show the native folder picker; returns the chosen path or null.
  Future<String?> chooseFolder() => _repository.chooseFolder();

  /// Trust the site's self-signed certificate in the Keychain.
  Future<bool> trustCertificate(String id) =>
      _repository.trustCertificate(id);

  int suggestPort() => _repository.suggestPort();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
