import 'dart:io';

/// Kills orphaned FlutterMamp-managed processes left over from a previous
/// session (e.g. after a force-quit, where dispose never ran). Run once at
/// startup so ports are free before we seed sites/services.
///
/// Single-instance assumption: the app treats itself as the sole manager of
/// these processes.
class ProcessCleanup {
  const ProcessCleanup();

  Future<void> reapOrphans() async {
    // All our runtime binaries (redis, mysqld, memcached, mailpit, nginx,
    // php-fpm) live under ~/.fluttermamp/runtime.
    await _pkill('.fluttermamp/runtime');
    // Apache still uses MAMP's httpd but with our generated config path.
    await _pkill('Application Support/FlutterMamp/conf/httpd-');
  }

  Future<void> _pkill(String pattern) async {
    try {
      await Process.run('pkill', ['-f', pattern]);
    } catch (_) {
      // pkill missing or nothing matched — nothing to do.
    }
  }
}
