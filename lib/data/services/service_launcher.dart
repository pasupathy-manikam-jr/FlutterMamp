import 'dart:io';

import '../../domain/models/managed_service.dart';
import '../../domain/models/service_type.dart';
import '../platform/app_paths.dart';
import 'config_service.dart' show LaunchSpec;

/// Builds the foreground launch command for a global service, using our own
/// runtime binaries and writing data/config under the app-support directory.
class ServiceLauncher {
  ServiceLauncher({AppPaths? paths}) : _paths = paths ?? AppPaths();

  final AppPaths _paths;

  String get dataDir => _paths.dataDir;
  String get logDir => _paths.logDir;

  /// Resolve the launch command for [service] using [binaryPath].
  Future<LaunchSpec> prepare(ManagedService service, String binaryPath) async {
    await Directory(logDir).create(recursive: true);
    switch (service.type) {
      case ServiceType.redis:
        final dir = '$dataDir/redis';
        await Directory(dir).create(recursive: true);
        return LaunchSpec(
          executable: binaryPath,
          arguments: [
            '--port', '${service.port}',
            '--bind', '127.0.0.1',
            '--daemonize', 'no',
            '--dir', dir,
          ],
        );
      case ServiceType.memcached:
        return LaunchSpec(
          executable: binaryPath,
          arguments: ['-p', '${service.port}', '-l', '127.0.0.1'],
        );
      case ServiceType.mailpit:
        // Web inbox on the service port; SMTP capture on 1025.
        return LaunchSpec(
          executable: binaryPath,
          arguments: [
            '--listen', '127.0.0.1:${service.port}',
            '--smtp', '127.0.0.1:1025',
          ],
        );
      case ServiceType.mysql:
        // Binary lives at <runtime>/mysql/bin/mysqld → basedir is <runtime>/mysql.
        final base = File(binaryPath).parent.parent.path;
        final dir = '$dataDir/mysql';
        if (!Directory('$dir/mysql').existsSync()) {
          // Fresh/empty data dir → initialise it (system tables + a passwordless
          // root). Runs once; the --init-file below then sets root/root.
          await Directory(dir).create(recursive: true);
          final init = await Process.run(binaryPath, [
            '--no-defaults',
            '--initialize-insecure',
            '--basedir=$base',
            '--datadir=$dir',
          ]);
          if (!Directory('$dir/mysql').existsSync()) {
            throw StateError('MySQL initialise failed: ${init.stderr}');
          }
        }
        // Idempotent on every start: ensure root/root works over TCP (127.0.0.1),
        // matching the MAMP convention the app + DB tools expect.
        final initSql = File('$dataDir/mysql-init.sql');
        await initSql.writeAsString(
          "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root';\n"
          "CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY 'root';\n"
          "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;\n"
          "FLUSH PRIVILEGES;\n",
        );
        return LaunchSpec(
          executable: binaryPath,
          arguments: [
            '--no-defaults',
            '--basedir=$base',
            '--datadir=$dir',
            '--port=${service.port}',
            '--bind-address=127.0.0.1',
            '--socket=$dataDir/mysql.sock',
            '--mysqlx=OFF',
            '--max_allowed_packet=1G',
            '--init-file=${initSql.path}',
          ],
        );
    }
  }
}
