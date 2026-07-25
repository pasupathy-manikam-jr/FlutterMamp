import 'server_status.dart';
import 'service_type.dart';

/// Immutable snapshot of a global background service.
class ManagedService {
  const ManagedService({
    required this.type,
    required this.status,
    required this.port,
    this.available = false,
    this.pid,
    this.errorMessage,
    this.logLines = const [],
  });

  final ServiceType type;
  final ServerStatus status;
  final int port;

  /// Whether the binary is present in the runtime dir.
  final bool available;

  final int? pid;
  final String? errorMessage;
  final List<String> logLines;

  ManagedService copyWith({
    ServerStatus? status,
    int? port,
    bool? available,
    int? pid,
    bool clearPid = false,
    String? errorMessage,
    bool clearError = false,
    List<String>? logLines,
  }) {
    return ManagedService(
      type: type,
      status: status ?? this.status,
      port: port ?? this.port,
      available: available ?? this.available,
      pid: clearPid ? null : (pid ?? this.pid),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      logLines: logLines ?? this.logLines,
    );
  }
}
