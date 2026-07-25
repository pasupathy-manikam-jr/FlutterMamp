import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/service_repository.dart';
import '../../../../data/services/database_service.dart';
import '../../../../domain/models/managed_service.dart';
import '../../../../domain/models/service_type.dart';
import '../../../../domain/models/tool_type.dart';

/// ViewModel for the global services section.
class ServicesViewModel extends ChangeNotifier {
  ServicesViewModel({required ServiceRepository repository})
      : _repository = repository {
    _sub = _repository.changes.listen((_) => notifyListeners());
  }

  final ServiceRepository _repository;
  late final StreamSubscription<void> _sub;

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> load() async {
    await _repository.initialize();
    _ready = true;
    notifyListeners();
  }

  List<ManagedService> get services => _repository.services;

  Future<void> toggle(ServiceType type) async {
    final s = _repository.service(type);
    if (s == null || !s.available) return;
    if (s.status.isActive) {
      await _repository.stop(type);
    } else if (!s.status.isTransitioning) {
      await _repository.start(type);
    }
  }

  bool get mysqlClientAvailable => _repository.mysqlClientAvailable;

  Future<String?> chooseSqlFile() => _repository.chooseSqlFile();

  Future<DbResult> importDump({
    required String dumpPath,
    required String database,
    String user = 'root',
    String password = 'root',
  }) =>
      _repository.importDump(
        dumpPath: dumpPath,
        database: database,
        user: user,
        password: password,
      );

  // --- bundled web tools ---
  List<ToolType> get tools => _repository.toolTypes;
  bool toolAvailable(ToolType t) => _repository.toolAvailable(t);
  bool isToolRunning(ToolType t) => _repository.isToolRunning(t);
  Future<void> openTool(ToolType t) => _repository.openTool(t);
  Future<void> stopTool(ToolType t) => _repository.stopTool(t);

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
