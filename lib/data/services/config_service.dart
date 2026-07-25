import 'dart:io';

import '../../domain/models/mamp_environment.dart';
import '../../domain/models/server_type.dart';
import '../../domain/models/site.dart';
import 'cert_service.dart';

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

/// An ordered set of processes that together serve a site.
///
/// For Apache/Nginx this is `[php-cgi FastCGI, web server]` — the FastCGI PHP
/// handler is started first, then the web server that proxies `.php` to it.
class SiteLaunch {
  const SiteLaunch(this.steps);

  /// Processes to start in order; the last one is the web server.
  final List<LaunchSpec> steps;
}

/// Generates per-engine configuration and the commands to serve a site.
///
/// Isolates the "strategy" differences between Apache and Nginx: each writes a
/// different config file, but both proxy PHP to a shared `php-cgi` FastCGI
/// process and resolve to a uniform [SiteLaunch]. Config is written under the
/// app-support directory so we never touch MAMP PRO's own configuration.
class ConfigService {
  ConfigService({
    CertService certService = const CertService(),
    String? homeOverride,
  })  : _certService = certService,
        _home = homeOverride ??
            Platform.environment['HOME'] ??
            Directory.systemTemp.path;

  final CertService _certService;
  final String _home;

  String get baseDir => '$_home/Library/Application Support/FlutterMamp';
  String get confDir => '$baseDir/conf';
  String get logDir => '$baseDir/logs';
  String get certsDir => '$baseDir/certs';

  Future<void> _ensureDirs() async {
    for (final d in [confDir, logDir, certsDir]) {
      await Directory(d).create(recursive: true);
    }
  }

  /// FastCGI port derived from the site's HTTP port (kept internal).
  int _fcgiPort(Site site) => 40000 + (site.port % 20000);

  /// Ensure a TLS cert exists for [site] and return its path (null if OpenSSL
  /// is unavailable). Used by the "Trust Certificate" action.
  Future<String?> ensureCert(Site site, MampEnvironment env) async {
    final openssl = env.opensslBinary;
    if (openssl == null) return null;
    await _ensureDirs();
    final cert = await _certService.ensureCert(
      commonName: site.host,
      opensslPath: openssl,
      outDir: certsDir,
    );
    return cert.certPath;
  }

  /// Resolve the launch for [site], writing any config it needs.
  Future<SiteLaunch> prepare(Site site, MampEnvironment env) async {
    await _ensureDirs();

    final steps = <LaunchSpec>[];

    // 1) PHP FastCGI handler (php-cgi -b host:port), if a php-cgi is available.
    final cgi = site.phpVersion?.cgiPath;
    if (cgi != null) {
      steps.add(LaunchSpec(
        executable: cgi,
        arguments: ['-b', '127.0.0.1:${_fcgiPort(site)}'],
        workingDirectory: site.documentRoot,
        environment: const {
          'PHP_FCGI_CHILDREN': '4',
          'PHP_FCGI_MAX_REQUESTS': '1000',
        },
      ));
    }

    // 2) Optional TLS cert.
    ({String certPath, String keyPath})? cert;
    if (site.sslEnabled) {
      final openssl = env.opensslBinary;
      if (openssl == null) {
        throw StateError('OpenSSL not found in MAMP; cannot enable SSL.');
      }
      cert = await _certService.ensureCert(
        commonName: site.host,
        opensslPath: openssl,
        outDir: certsDir,
      );
    }

    // 3) The web server.
    switch (site.server) {
      case ServerType.nginx:
        steps.add(await _prepareNginx(site, env, cert));
      case ServerType.apache:
        steps.add(await _prepareApache(site, env, cert));
    }

    return SiteLaunch(steps);
  }

  // --- Nginx ---------------------------------------------------------------

  Future<LaunchSpec> _prepareNginx(
    Site site,
    MampEnvironment env,
    ({String certPath, String keyPath})? cert,
  ) async {
    final nginx = env.nginxBinary;
    if (nginx == null) throw StateError('Nginx binary not found in MAMP.');

    final prefix = '$baseDir/nginx/${site.id}';
    await Directory('$prefix/temp').create(recursive: true);
    await Directory('$prefix/fcgi').create(recursive: true);

    final fcgi = _fcgiPort(site);
    final sslListen = cert != null
        ? '''
    listen 127.0.0.1:${site.sslPort} ssl;
    ssl_certificate ${cert.certPath};
    ssl_certificate_key ${cert.keyPath};'''
        : '';

    final confPath = '$confDir/nginx-${site.id}.conf';
    final conf = '''
worker_processes 1;
daemon off;
error_log $logDir/nginx-${site.id}-error.log;
pid $prefix/nginx.pid;
events { worker_connections 256; }
http {
  access_log $logDir/nginx-${site.id}-access.log;
  types { text/html html htm; text/css css; application/javascript js; application/json json; image/png png; image/jpeg jpg jpeg; image/gif gif; image/svg+xml svg; font/woff2 woff2; }
  default_type application/octet-stream;
  sendfile on;
  client_body_temp_path $prefix/temp;
  fastcgi_temp_path $prefix/fcgi;
  server {
    listen 127.0.0.1:${site.port};
$sslListen
    server_name ${site.host};
    root ${site.documentRoot};
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
''';
    await File(confPath).writeAsString(conf);

    return LaunchSpec(
      executable: nginx,
      arguments: ['-p', prefix, '-c', confPath, '-g', 'daemon off;'],
      workingDirectory: prefix,
    );
  }

  // --- Apache --------------------------------------------------------------

  Future<LaunchSpec> _prepareApache(
    Site site,
    MampEnvironment env,
    ({String certPath, String keyPath})? cert,
  ) async {
    final httpd = env.apacheBinary;
    if (httpd == null) throw StateError('Apache binary not found in MAMP.');

    final serverRoot = '${env.rootPath}/Library';
    final modules = '$serverRoot/modules';
    final confPath = '$confDir/httpd-${site.id}.conf';
    final fcgi = _fcgiPort(site);

    // MAMP ships plain `php-cgi`, a *generic* FastCGI backend. mod_proxy_fcgi
    // defaults to FPM mode, which sets SCRIPT_FILENAME in a way php-cgi rejects
    // ("No input file specified"). GENERIC mode fixes it.
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

    final conf = '''
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
''';
    await File(confPath).writeAsString(conf);

    return LaunchSpec(
      executable: httpd,
      arguments: ['-f', confPath, '-X'],
      workingDirectory: serverRoot,
    );
  }
}
