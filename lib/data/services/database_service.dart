import 'dart:convert';
import 'dart:io';

/// Result of a database operation.
class DbResult {
  const DbResult(this.ok, this.message);
  final bool ok;
  final String message;
}

/// Imports SQL dumps into MySQL using our bundled `mysql` client.
///
/// Supports plain `.sql` and gzip-compressed `.sql.gz` dumps (streamed to
/// avoid loading large files into memory).
class DatabaseService {
  const DatabaseService();

  Future<DbResult> importDump({
    required String mysqlClient,
    required String dumpPath,
    required String database,
    String host = '127.0.0.1',
    int port = 3306,
    String user = 'root',
    String password = 'root',
  }) async {
    if (!File(dumpPath).existsSync()) {
      return DbResult(false, 'Dump file not found: $dumpPath');
    }

    final auth = [
      '-h', host, '-P', '$port', '-u', user,
      if (password.isNotEmpty) '-p$password',
      '--max_allowed_packet=1G', // handle large tables/rows
    ];

    // Ensure the target database exists.
    final create = await Process.run(mysqlClient, [
      ...auth,
      '-e',
      'CREATE DATABASE IF NOT EXISTS `$database` '
          'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;',
    ]);
    if (create.exitCode != 0) {
      return DbResult(false, _clean(create.stderr.toString()));
    }

    // Stream the dump into mysql's stdin.
    final proc = await Process.start(mysqlClient, [...auth, database]);
    final err = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(err.write);

    final source = dumpPath.endsWith('.gz')
        ? File(dumpPath).openRead().transform(gzip.decoder)
        : File(dumpPath).openRead();
    try {
      await source.pipe(proc.stdin);
    } catch (e) {
      return DbResult(false, 'Failed to read dump: $e');
    }
    final code = await proc.exitCode;
    if (code != 0) return DbResult(false, _clean(err.toString()));
    return DbResult(true, 'Imported into `$database` successfully.');
  }

  /// Strip the noisy "Using a password on the command line" warning.
  String _clean(String s) => s
      .split('\n')
      .where((l) => !l.contains('[Warning]') && l.trim().isNotEmpty)
      .join('\n')
      .trim();
}
