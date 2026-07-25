/// A PHP toolchain discovered inside the MAMP installation.
///
/// Clean domain model — the [MampService] transforms raw filesystem paths into
/// these; the rest of the app never sees a raw path string.
class PhpVersion implements Comparable<PhpVersion> {
  const PhpVersion({
    required this.version,
    required this.binaryPath,
    required this.cgiPath,
  });

  /// Dotted version string, e.g. `8.3.30`.
  final String version;

  /// Absolute path to the `php` CLI binary.
  final String binaryPath;

  /// Absolute path to the `php-cgi` binary, if present (used by Apache/Nginx
  /// as the FastCGI handler). Null when only the CLI binary exists.
  final String? cgiPath;

  /// Major.minor label for compact display, e.g. `8.3`.
  String get shortLabel {
    final parts = version.split('.');
    return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
  }

  /// Sort newest-first is achieved by reversing a natural comparison.
  @override
  int compareTo(PhpVersion other) {
    final a = version.split('.').map(int.tryParse).toList();
    final b = other.version.split('.').map(int.tryParse).toList();
    for (var i = 0; i < a.length && i < b.length; i++) {
      final av = a[i] ?? 0;
      final bv = b[i] ?? 0;
      if (av != bv) return av.compareTo(bv);
    }
    return a.length.compareTo(b.length);
  }

  @override
  bool operator ==(Object other) =>
      other is PhpVersion && other.binaryPath == binaryPath;

  @override
  int get hashCode => binaryPath.hashCode;

  @override
  String toString() => 'PhpVersion($version)';
}
