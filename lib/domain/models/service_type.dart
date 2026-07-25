/// Global background services FlutterMamp manages, independent of MAMP.
///
/// Binaries live in the app's own `runtime/bin` directory (bundled/downloaded),
/// never `/Applications/MAMP`.
enum ServiceType {
  mysql('MySQL', 3306, 'Database server', 'mysql/bin/mysqld'),
  redis('Redis', 6379, 'In-memory data store', 'bin/redis-server'),
  memcached('Memcached', 11211, 'Memory object cache', 'bin/memcached'),
  mailhog('MailHog', 8025, 'Email testing (SMTP capture)', 'bin/mailhog');

  const ServiceType(this.label, this.defaultPort, this.blurb, this.relativePath);

  /// Human-friendly name.
  final String label;

  /// Default listening port.
  final int defaultPort;

  /// One-line description.
  final String blurb;

  /// Path to the executable relative to the runtime root (some services, like
  /// MySQL, ship with their own basedir tree rather than a single binary).
  final String relativePath;
}
