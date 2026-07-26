# OricDevServer

A cross-platform local web-development server manager for **macOS, Linux, and
Windows**. Run and manage local development sites (Apache / Nginx / FrankenPHP),
PHP, and services (MySQL, Redis, Memcached, Mailpit) plus DB tools (phpMyAdmin /
Adminer) from one native app — self-contained and open source.

Built with Flutter. No external stack required — OricDevServer downloads and runs
its **own** bundled runtime binaries on first launch.

## Features

- One-click start/stop of web servers, PHP, and services
- Create sites with a document-root picker, custom hostnames, and trusted local
  SSL (a local CA signs per-site certs)
- Bundled, downloaded-on-demand runtime (MySQL, PHP/php-fpm, Nginx, FrankenPHP,
  Redis, Memcached, Mailpit) — nothing else to install
- phpMyAdmin / Adminer, per-site `php.ini` editing, SQL dump import

## Install

Download the app for your OS from the [Releases](../../releases) page
(`app-v1`). Each app fetches its runtime components on first launch.

- **macOS**: unzip and open. It is self-distributed (not Apple-notarized), so the
  first launch needs System Settings → Privacy & Security → **Open Anyway**, or:
  `xattr -dr com.apple.quarantine /path/to/OricDevServer.app`
- **Linux**: extract and run `./OricDevServer` (needs GTK 3).
- **Windows**: unzip and run `OricDevServer.exe`.

## Trademark notice

OricDevServer is an independent, open-source project and is not affiliated with,
endorsed by, or sponsored by any other company. All product names and trademarks
are the property of their respective owners.

## License

© OricLab. See repository for license terms.
