import 'dart:io';

import '../../domain/models/dev_environment.dart';
import '../../domain/models/server_type.dart';
import '../../domain/models/site.dart';
import '../platform/app_paths.dart';
import 'cert_service.dart';
import 'runtime_service.dart';

/// A fully-resolved command to launch one process in the foreground.
class LaunchSpec {
  const LaunchSpec({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String>? environment;
}

/// An ordered set of processes that together serve a site (PHP handler first,
/// then the web server).
class SiteLaunch {
  const SiteLaunch(this.steps);
  final List<LaunchSpec> steps;
}

/// Generates per-engine configuration and the commands to serve a site.
///
/// Nginx sites run on our OWN runtime (nginx + php-fpm) — MAMP-free. Apache
/// sites still use MAMP's httpd + php-cgi for now (Apache is the hardest engine
/// to source independently). Config is written under the app-support directory.
class ConfigService {
  ConfigService({
    CertService certService = const CertService(),
    required RuntimeService runtimeService,
    AppPaths? paths,
  })  : _certService = certService,
        _runtimeService = runtimeService,
        _paths = paths ?? AppPaths();

  final CertService _certService;
  final RuntimeService _runtimeService;
  final AppPaths _paths;

  String get baseDir => _paths.supportDir;
  String get confDir => _paths.confDir;
  String get logDir => _paths.logDir;
  String get certsDir => _paths.certsDir;

  Future<void> _ensureDirs() async {
    for (final d in [confDir, logDir, certsDir]) {
      await Directory(d).create(recursive: true);
    }
  }

  int _fcgiPort(Site site) => 40000 + (site.port % 20000);

  /// Write the site's php.ini overrides to a file and return its path.
  Future<String> _writePhpIni(Site site) async {
    final path = '$confDir/php-${site.id}.ini';
    await File(path).writeAsString(site.phpIni);
    return path;
  }

  /// System openssl keeps SSL cert generation MAMP-free (falls back to MAMP's).
  String _opensslPath(DevEnvironment env) =>
      File('/usr/bin/openssl').existsSync()
          ? '/usr/bin/openssl'
          : (env.opensslBinary ?? '/usr/bin/openssl');

  /// Ensure the site's leaf cert exists and return the **CA** cert path — that
  /// is the certificate to trust in the keychain (trusting the CA covers every
  /// site signed by it).
  Future<String?> ensureCert(Site site, DevEnvironment env) async {
    await _ensureDirs();
    await _certService.ensureCert(
      commonName: site.host,
      opensslPath: _opensslPath(env),
      outDir: certsDir,
    );
    return _certService.caCertPath(certsDir);
  }

  Future<SiteLaunch> prepare(Site site, DevEnvironment env) async {
    await _ensureDirs();
    switch (site.server) {
      case ServerType.nginx:
        return _nginxSteps(site, env);
      case ServerType.apache:
        return _apacheSteps(site, env);
      case ServerType.frankenphp:
        return _frankenPhpSteps(site, env);
    }
  }

  Future<({String certPath, String keyPath})?> _cert(
      Site site, DevEnvironment env) async {
    if (!site.sslEnabled) return null;
    return _certService.ensureCert(
      commonName: site.host,
      opensslPath: _opensslPath(env),
      outDir: certsDir,
    );
  }

  // --- Nginx (independent: our nginx + php-fpm) ----------------------------

  Future<SiteLaunch> _nginxSteps(Site site, DevEnvironment env) async {
    final nginx = _runtimeService.nginxBinary;
    final phpFpm = _runtimeService.phpFpmBinary;
    if (nginx == null || phpFpm == null) {
      // No bundled nginx (e.g. Linux, where nginx needs a CI build): serve via
      // FrankenPHP, which embeds its own PHP — a single cross-platform binary.
      return _frankenPhpSteps(site, env);
    }

    final fcgi = _fcgiPort(site);
    final phpFpmSpec = await _phpFpmSpec(site, phpFpm, fcgi);

    // nginx.
    final cert = await _cert(site, env);
    final prefix = '$baseDir/nginx/${site.id}';
    // nginx opens <prefix>/logs/error.log before reading the config, so the
    // dir must exist.
    await Directory('$prefix/logs').create(recursive: true);
    await Directory('$prefix/temp').create(recursive: true);
    await Directory('$prefix/fcgi').create(recursive: true);

    // Paths are quoted because our config lives under "Application Support"
    // (a space), which unquoted nginx directives cannot parse.
    final sslListen = cert != null
        ? '''
    listen 127.0.0.1:${site.sslPort} ssl;
    ssl_certificate "${cert.certPath}";
    ssl_certificate_key "${cert.keyPath}";'''
        : '';

    final confPath = '$confDir/nginx-${site.id}.conf';
    await File(confPath).writeAsString('''
worker_processes 1;
daemon off;
error_log "$logDir/nginx-${site.id}-error.log";
pid "$prefix/nginx.pid";
events { worker_connections 256; }
http {
  access_log "$logDir/nginx-${site.id}-access.log";
  types { text/html html htm; text/css css; application/javascript js; application/json json; image/png png; image/jpeg jpg jpeg; image/gif gif; image/svg+xml svg; font/woff2 woff2; }
  default_type application/octet-stream;
  sendfile on;
  client_body_temp_path "$prefix/temp";
  fastcgi_temp_path "$prefix/fcgi";
  server {
    listen 127.0.0.1:${site.port};
$sslListen
    server_name ${site.host};
    root "${site.documentRoot}";
    index index.php index.html index.htm;
    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \\.php\$ {
      fastcgi_pass 127.0.0.1:$fcgi;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
      fastcgi_param QUERY_STRING \$query_string;
      fastcgi_param REQUEST_METHOD \$request_method;
      fastcgi_param CONTENT_TYPE \$content_type;
      fastcgi_param CONTENT_LENGTH \$content_length;
      fastcgi_param REQUEST_URI \$request_uri;
      fastcgi_param DOCUMENT_URI \$document_uri;
      fastcgi_param DOCUMENT_ROOT \$document_root;
      fastcgi_param SERVER_PROTOCOL \$server_protocol;
      fastcgi_param GATEWAY_INTERFACE CGI/1.1;
      fastcgi_param SERVER_SOFTWARE nginx;
      fastcgi_param REMOTE_ADDR \$remote_addr;
      fastcgi_param SERVER_NAME \$server_name;
      fastcgi_param HTTPS \$https if_not_empty;
    }
  }
}
''');

    final nginxSpec = LaunchSpec(
      executable: nginx,
      // The generated config already sets `daemon off;`, so don't also pass
      // `-g 'daemon off;'` — nginx rejects the duplicate directive.
      arguments: ['-p', prefix, '-c', confPath],
      workingDirectory: prefix,
    );

    // php-fpm first, then nginx (which the repository treats as the server).
    return SiteLaunch([phpFpmSpec, nginxSpec]);
  }

  // --- FrankenPHP (single binary, embedded PHP) -------------------------------
  //
  // Two roles: the engine a site can pick directly (ServerType.frankenphp), and
  // the fallback when nginx/Apache + php-fpm aren't bundled (Windows, Linux).
  //
  // Uses a rendered Caddyfile rather than `php-server`, because php-server can
  // only do plain HTTP. Dropping a site from HTTPS to HTTP on the same hostname
  // breaks logins: cookies the browser stored as `Secure` are neither sent to
  // nor overwritable by an insecure origin (RFC 6265bis "Leave Secure Cookies
  // Alone"), so the session silently restarts every request and Laravel-style
  // CSRF checks fail with 419. Serving TLS keeps the cookie jar intact.
  //
  // Still no worker mode — that stays PLAN.md M2.
  Future<SiteLaunch> _frankenPhpSteps(Site site, DevEnvironment env) async {
    final fp = _runtimeService.frankenphpBinary;
    if (fp == null) {
      throw StateError('FrankenPHP is not installed — install it from the '
          'Runtime panel (or pick Nginx/Apache instead).');
    }

    final cert = await _cert(site, env);
    final prefix = '$baseDir/frankenphp/${site.id}';
    await Directory(prefix).create(recursive: true);

    // Site addresses omit the host so any Host header matches — the site may be
    // reached as either 127.0.0.1 or its custom hostname, and unlike nginx we
    // have no separate default vhost to fall back to. `bind` is then required:
    // a host-less address otherwise listens on every interface, which would put
    // the site on the LAN (nginx/Apache here listen on 127.0.0.1 only).
    //
    // `tls` is explicit because Caddy's automatic HTTPS would otherwise mint a
    // cert from *its* internal CA, which the keychain doesn't trust; ours is
    // signed by the CA the Trust Certificate button installs. `auto_https off`
    // also stops Caddy grabbing port 80 for redirects.
    final httpsSite = cert != null
        ? '''

https://:${site.sslPort} {
	bind 127.0.0.1
	tls "${cert.certPath}" "${cert.keyPath}"
	root * "${site.documentRoot}"
	encode zstd br gzip
	php_server
}'''
        : '';

    final confPath = '$confDir/frankenphp-${site.id}.caddy';
    await File(confPath).writeAsString('''
{
	frankenphp
	order php_server before file_server
	auto_https off
	admin off
	log {
		output file "$logDir/frankenphp-${site.id}.log"
	}
}

http://:${site.port} {
	bind 127.0.0.1
	root * "${site.documentRoot}"
	encode zstd br gzip
	php_server
}$httpsSite
''');

    return SiteLaunch([
      LaunchSpec(
        executable: fp,
        arguments: ['run', '--config', confPath, '--adapter', 'caddyfile'],
        workingDirectory: site.documentRoot,
        // Keep Caddy's own state (its internal CA, OCSP cache) inside the
        // site's dir instead of the user's ~/Library/Application Support/Caddy.
        environment: {
          'XDG_CONFIG_HOME': prefix,
          'XDG_DATA_HOME': prefix,
        },
      ),
    ]);
  }

  /// php-fpm pool + launch spec, shared by the Nginx and Apache paths.
  Future<LaunchSpec> _phpFpmSpec(Site site, String phpFpm, int fcgi) async {
    final fpmConf = '$confDir/php-fpm-${site.id}.conf';
    await File(fpmConf).writeAsString('''
[global]
error_log = $logDir/php-fpm-${site.id}.log
daemonize = no
[www]
listen = 127.0.0.1:$fcgi
pm = dynamic
pm.max_children = 5
pm.start_servers = 1
pm.min_spare_servers = 1
pm.max_spare_servers = 3
''');
    // Our static php-fpm has extensions compiled in, so loading the site's
    // php.ini via -c is safe (empty → built-in defaults, so we keep -n).
    final ini = site.phpIni.trim();
    return LaunchSpec(
      executable: phpFpm,
      arguments: ini.isEmpty
          ? ['-F', '-n', '-y', fpmConf]
          : ['-F', '-y', fpmConf, '-c', await _writePhpIni(site)],
    );
  }

  // --- Apache (independent: bundled httpd + php-fpm via mod_proxy_fcgi) -----

  Future<SiteLaunch> _apacheSteps(Site site, DevEnvironment env) async {
    final httpd = _runtimeService.apacheBinary;
    final phpFpm = _runtimeService.phpFpmBinary;
    final serverRoot = _runtimeService.apacheRoot;
    if (httpd == null || phpFpm == null || serverRoot == null) {
      // No bundled Apache/php-fpm yet: serve via FrankenPHP so the site works.
      return _frankenPhpSteps(site, env);
    }
    final modules = '$serverRoot/modules';
    final cert = await _cert(site, env);
    final confPath = '$confDir/httpd-${site.id}.conf';
    final fcgi = _fcgiPort(site);
    final phpFpmSpec = await _phpFpmSpec(site, phpFpm, fcgi);

    final proxyFcgiPresent = File('$modules/mod_proxy_fcgi.so').existsSync();
    final backendType =
        proxyFcgiPresent ? 'ProxyFCGIBackendType GENERIC' : '';

    String loadIfPresent(String mod, String file) =>
        File('$modules/$file').existsSync()
            ? 'LoadModule $mod modules/$file'
            : '';

    final phpHandler = '''
<FilesMatch \\.php\$>
    SetHandler "proxy:fcgi://127.0.0.1:$fcgi"
</FilesMatch>''';

    final dirBlock = '''
<Directory "${site.documentRoot}">
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
    DirectoryIndex index.php index.html index.htm
</Directory>''';

    final sslBlock = cert != null
        ? '''
${loadIfPresent('ssl_module', 'mod_ssl.so')}
${loadIfPresent('socache_shmcb_module', 'mod_socache_shmcb.so')}
Listen 127.0.0.1:${site.sslPort}
SSLSessionCache "shmcb:$logDir/ssl_scache-${site.id}(512000)"
<VirtualHost 127.0.0.1:${site.sslPort}>
    ServerName ${site.host}
    DocumentRoot "${site.documentRoot}"
    SSLEngine on
    SSLCertificateFile "${cert.certPath}"
    SSLCertificateKeyFile "${cert.keyPath}"
    $dirBlock
    $phpHandler
</VirtualHost>'''
        : '';

    await File(confPath).writeAsString('''
ServerRoot "$serverRoot"
Listen 127.0.0.1:${site.port}
${loadIfPresent('mpm_prefork_module', 'mod_mpm_prefork.so')}
${loadIfPresent('mpm_event_module', 'mod_mpm_event.so')}
${loadIfPresent('unixd_module', 'mod_unixd.so')}
${loadIfPresent('authz_core_module', 'mod_authz_core.so')}
${loadIfPresent('mime_module', 'mod_mime.so')}
${loadIfPresent('dir_module', 'mod_dir.so')}
${loadIfPresent('rewrite_module', 'mod_rewrite.so')}
${loadIfPresent('log_config_module', 'mod_log_config.so')}
${loadIfPresent('proxy_module', 'mod_proxy.so')}
${loadIfPresent('proxy_fcgi_module', 'mod_proxy_fcgi.so')}
$backendType
ServerName ${site.host}:${site.port}
PidFile "$logDir/httpd-${site.id}.pid"
ErrorLog "$logDir/httpd-${site.id}-error.log"
DocumentRoot "${site.documentRoot}"
$dirBlock
$phpHandler
$sslBlock
''');

    return SiteLaunch([
      phpFpmSpec,
      LaunchSpec(
        executable: httpd,
        arguments: ['-f', confPath, '-X'],
        workingDirectory: serverRoot,
      ),
    ]);
  }
}
