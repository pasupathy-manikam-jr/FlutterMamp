/// Lifecycle state of a managed server process.
enum ServerStatus {
  stopped('Stopped'),
  starting('Starting…'),
  running('Running'),
  stopping('Stopping…'),
  error('Error');

  const ServerStatus(this.label);

  /// Human-friendly label shown next to the status light.
  final String label;

  /// True while a start/stop transition is in flight (UI should show a spinner
  /// and disable the toggle).
  bool get isTransitioning =>
      this == ServerStatus.starting || this == ServerStatus.stopping;

  /// True when the process is up and serving.
  bool get isActive => this == ServerStatus.running;
}
