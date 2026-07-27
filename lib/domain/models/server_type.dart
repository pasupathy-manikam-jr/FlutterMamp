/// The web server engines this app can manage.
///
/// Matches MAMP PRO's "Web server: Apache / Nginx" choice. PHP is not an engine
/// here — it is a *version* selected per site and executed via FastCGI.
///
/// [frankenphp] serves via a rendered Caddyfile (HTTP + HTTPS on our own CA's
/// cert) but ignores the site's PHP version, since its PHP is compiled in.
/// Worker mode is still PLAN.md M2. RoadRunner and Swoole remain parked.
enum ServerType {
  apache('Apache', 'Traditional web server (httpd)',
      supportsSsl: true, usesSitePhpVersion: true),
  nginx('Nginx', 'Traditional web server',
      supportsSsl: true, usesSitePhpVersion: true),
  frankenphp('FrankenPHP', 'App server, embedded PHP (Caddy)',
      supportsSsl: true, usesSitePhpVersion: false);

  // Stated per value rather than defaulted: engines still to come (RoadRunner,
  // Swoole) differ on both, and a silent default is the wrong thing to inherit.
  const ServerType(
    this.label,
    this.blurb, {
    required this.supportsSsl,
    required this.usesSitePhpVersion,
  });

  /// Human-friendly name shown in the UI.
  final String label;

  /// One-line description shown under the name.
  final String blurb;

  /// Whether this engine's generated config actually serves HTTPS. Guards the
  /// SSL toggle and [Site.url], so an engine that can't do TLS never yields a
  /// dead https:// link.
  final bool supportsSsl;

  /// Whether the site's selected PHP version is honoured. False for
  /// [frankenphp], whose PHP is compiled into the binary.
  final bool usesSitePhpVersion;
}
