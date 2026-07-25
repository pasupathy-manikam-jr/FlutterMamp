/// Bundled web tools (database admin UIs) served on demand by FrankenPHP.
///
/// phpMyAdmin needs the `mysqli` extension, which FrankenPHP's embedded PHP
/// provides (our php-fpm build does not) — so both tools are served by
/// FrankenPHP for consistency.
enum ToolType {
  adminer('Adminer', 8081, 'adminer'),
  phpmyadmin('phpMyAdmin', 8082, 'phpmyadmin');

  const ToolType(this.label, this.port, this.dirName);

  final String label;
  final int port;

  /// Directory name under the runtime `tools/` folder.
  final String dirName;

  String get url => 'http://127.0.0.1:$port';
}
