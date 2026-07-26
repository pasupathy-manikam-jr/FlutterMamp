import 'package:flutter/foundation.dart';

import '../../../data/services/runtime_installer.dart';

/// UI state for one runtime component in the setup flow.
class ComponentState {
  ComponentState(this.component, this.installed);
  final RuntimeComponent component;
  bool installed;
  double? progress; // 0..1 while downloading, null otherwise
  String? error;
}

/// Drives the first-launch "download runtime" prompt: checks which components
/// are present and downloads the missing ones on demand.
class RuntimeSetupViewModel extends ChangeNotifier {
  RuntimeSetupViewModel({required RuntimeInstaller installer})
      : _installer = installer;

  final RuntimeInstaller _installer;

  final List<ComponentState> states = [];
  bool _checked = false;
  bool _downloading = false;

  bool get isChecked => _checked;
  bool get isDownloading => _downloading;
  bool get hasMissing => states.any((s) => !s.installed);
  List<ComponentState> get missing =>
      states.where((s) => !s.installed).toList();

  /// Re-scan what's installed.
  void check() {
    states
      ..clear()
      ..addAll(RuntimeManifest.components
          .map((c) => ComponentState(c, _installer.isInstalled(c))));
    _checked = true;
    notifyListeners();
  }

  /// Download every missing component, updating progress as it goes.
  Future<void> downloadMissing() => _download(missing);

  /// Download a single component.
  Future<void> downloadOne(ComponentState s) => _download([s]);

  Future<void> _download(List<ComponentState> targets) async {
    if (_downloading) return;
    _downloading = true;
    notifyListeners();
    for (final s in targets) {
      if (s.installed) continue;
      s.error = null;
      s.progress = 0;
      notifyListeners();
      await for (final p in _installer.install(s.component)) {
        if (p.phase.startsWith('error')) {
          s.error = p.phase;
          break;
        }
        s.progress = p.phase == 'downloading' ? p.fraction : 1;
        notifyListeners();
      }
      s.progress = null;
      s.installed = _installer.isInstalled(s.component);
      notifyListeners();
    }
    _downloading = false;
    notifyListeners();
  }
}
