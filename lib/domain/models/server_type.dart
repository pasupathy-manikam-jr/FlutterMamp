/// The web server engines this app can manage.
///
/// Matches MAMP PRO's "Web server: Apache / Nginx" choice. PHP is not an engine
/// here — it is a *version* selected per site and executed via FastCGI. The
/// modern application servers (FrankenPHP, RoadRunner, Swoole) are parked for a
/// later milestone — see PLAN.md.
enum ServerType {
  apache('Apache', 'Traditional web server (httpd)'),
  nginx('Nginx', 'Traditional web server');

  const ServerType(this.label, this.blurb);

  /// Human-friendly name shown in the UI.
  final String label;

  /// One-line description shown under the name.
  final String blurb;
}
