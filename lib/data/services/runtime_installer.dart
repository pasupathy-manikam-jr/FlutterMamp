import 'dart:io';

import '../platform/app_paths.dart';

/// A downloadable runtime component (a self-contained tar.gz that extracts into
/// the runtime directory with the correct structure).
class RuntimeComponent {
  const RuntimeComponent(this.id, this.label, this.probePath, this.approxMB,
      {this.windowsProbe});

  final String id;
  final String label;

  /// Path (relative to runtimeDir) whose existence means "installed".
  final String probePath;

  /// Windows-specific probe, when the layout differs (e.g. PHP has no php-fpm
  /// on Windows, so we probe the CLI instead). Falls back to [probePath].
  final String? windowsProbe;

  /// Rough download size, for the UI.
  final int approxMB;
}

/// The set of components the app can fetch. Each is published to GitHub
/// Releases as `<os>-<arch>-<id>.tar.gz` under the [RuntimeInstaller._tag] tag.
class RuntimeManifest {
  static const List<RuntimeComponent> components = [
    RuntimeComponent('php', 'PHP (php-fpm + CLI)', 'bin/php-fpm', 40,
        windowsProbe: 'bin/php'),
    RuntimeComponent('nginx', 'Nginx', 'nginx/sbin/nginx', 5),
    RuntimeComponent('mysql', 'MySQL', 'mysql/bin/mysqld', 520),
    RuntimeComponent('redis', 'Redis', 'bin/redis-server', 4),
    RuntimeComponent('memcached', 'Memcached', 'bin/memcached', 2),
    RuntimeComponent('mailpit', 'Mailpit', 'bin/mailpit', 20),
    RuntimeComponent('frankenphp', 'FrankenPHP', 'bin/frankenphp', 180),
    RuntimeComponent('tools', 'DB tools (phpMyAdmin/Adminer)',
        'tools/phpmyadmin/index.php', 20),
  ];

  static RuntimeComponent? byId(String id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// Progress event for an ongoing install.
class InstallProgress {
  const InstallProgress(this.phase, this.fraction);
  final String phase; // 'downloading' | 'extracting' | 'done' | 'error'
  final double fraction; // 0..1 (download), 1 when done
}

/// Downloads and installs runtime components from GitHub Releases into the
/// runtime directory. Pure Dart HTTP + platform `tar` for extraction (tar is
/// present on macOS, Linux, and Windows 10+).
class RuntimeInstaller {
  RuntimeInstaller({required AppPaths paths}) : _paths = paths;

  final AppPaths _paths;

  static const String _base =
      'https://github.com/pasupathy-manikam-jr/FlutterMamp/releases/download';
  static const String _tag = 'runtime-v1';

  /// e.g. `macos-arm64`, `linux-x64`, `windows-x64`.
  String get platformKey {
    final os = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
            ? 'windows'
            : 'linux';
    return '$os-$_arch';
  }

  String get _arch {
    if (Platform.isWindows) {
      final a = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '')
          .toLowerCase();
      return a.contains('arm') ? 'arm64' : 'x64';
    }
    try {
      final m = Process.runSync('uname', ['-m']).stdout.toString().trim();
      return (m == 'arm64' || m == 'aarch64') ? 'arm64' : 'x64';
    } catch (_) {
      return 'x64';
    }
  }

  String urlFor(RuntimeComponent c) =>
      '$_base/$_tag/$platformKey-${c.id}.tar.gz';

  bool isInstalled(RuntimeComponent c) {
    final probe = (Platform.isWindows && c.windowsProbe != null)
        ? c.windowsProbe!
        : c.probePath;
    final p = '${_paths.runtimeDir}/$probe';
    return File(p).existsSync() ||
        (Platform.isWindows && File('$p.exe').existsSync());
  }

  /// Download + extract [c] into the runtime dir, yielding progress.
  Stream<InstallProgress> install(RuntimeComponent c) async* {
    final runtime = Directory(_paths.runtimeDir);
    await runtime.create(recursive: true);
    final tmp = File(
        '${Directory.systemTemp.path}/oricmamp-${c.id}-${DateTime.now().microsecondsSinceEpoch}.tar.gz');

    try {
      // --- download ---
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(urlFor(c)));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        yield InstallProgress('error (HTTP ${resp.statusCode})', 0);
        return;
      }
      final total = resp.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        yield InstallProgress(
            'downloading', total > 0 ? received / total : 0);
      }
      await sink.close();
      client.close();

      // --- extract ---
      yield const InstallProgress('extracting', 1);
      final r = await Process.run(
          'tar', ['xzf', tmp.path, '-C', _paths.runtimeDir]);
      if (r.exitCode != 0) {
        yield InstallProgress('error: ${r.stderr}', 1);
        return;
      }
      // Ensure the probe binary is executable (unix).
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', '${_paths.runtimeDir}/${c.probePath}']);
      }
      yield const InstallProgress('done', 1);
    } catch (e) {
      yield InstallProgress('error: $e', 0);
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
