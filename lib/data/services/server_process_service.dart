import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'config_service.dart';

/// A handle to a launched server process.
class RunningProcess {
  RunningProcess(this._process);

  final Process _process;

  int get pid => _process.pid;
}

/// Stateless wrapper around `dart:io` [Process] for launching and stopping
/// server engines. Knows nothing about Apache/Nginx/PHP specifics — it just
/// runs a [LaunchSpec] and streams its output line by line.
class ServerProcessService {
  /// Launch [spec]. Each stdout/stderr line is delivered to [onLog]; [onExit]
  /// fires once with the process exit code.
  ///
  /// Throws if the executable cannot be started (e.g. missing binary); callers
  /// translate that into an error status.
  Future<RunningProcess> start(
    LaunchSpec spec, {
    required void Function(String line) onLog,
    required void Function(int exitCode) onExit,
  }) async {
    final process = await Process.start(
      spec.executable,
      spec.arguments,
      workingDirectory: spec.workingDirectory,
      environment: spec.environment,
      includeParentEnvironment: true,
      mode: ProcessStartMode.normal,
    );

    void pipe(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(onLog, onError: (Object e) => onLog('[stream error] $e'));
    }

    pipe(process.stdout);
    pipe(process.stderr);

    unawaited(process.exitCode.then(onExit));

    return RunningProcess(process);
  }

  /// Stop [running] gracefully (SIGTERM), escalating to SIGKILL if it does not
  /// exit within [grace].
  Future<void> stop(
    RunningProcess running, {
    Duration grace = const Duration(seconds: 5),
  }) async {
    final process = running._process;
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(grace);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
  }
}
