/// Global background services FlutterMamp manages, independent of MAMP.
///
/// Binaries live in the app's own `runtime/bin` directory (bundled/downloaded),
/// never `/Applications/MAMP`.
enum ServiceType {
  mysql('MySQL', 3306, 'Database server', 'mariadbd'),
  redis('Redis', 6379, 'In-memory data store', 'redis-server'),
  memcached('Memcached', 11211, 'Memory object cache', 'memcached'),
  mailhog('MailHog', 8025, 'Email testing (SMTP capture)', 'mailhog');

  const ServiceType(this.label, this.defaultPort, this.blurb, this.binaryName);

  /// Human-friendly name.
  final String label;

  /// Default listening port.
  final int defaultPort;

  /// One-line description.
  final String blurb;

  /// Expected executable name inside the runtime `bin` directory.
  final String binaryName;
}
