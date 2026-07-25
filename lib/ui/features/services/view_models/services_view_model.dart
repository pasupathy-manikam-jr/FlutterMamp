import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/service_repository.dart';
import '../../../../domain/models/managed_service.dart';
import '../../../../domain/models/service_type.dart';

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

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
