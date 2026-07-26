# OricDevServer

A cross-platform local web-development server manager for **macOS, Linux, and
Windows** — a self-contained, open alternative to MAMP PRO-style tools. Manage
local sites (Apache / Nginx / FrankenPHP), PHP, and services (MySQL, Redis,
Memcached, Mailpit) plus DB tools (phpMyAdmin / Adminer) from one native app.

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

OricDevServer is an independent project and is **not affiliated with, endorsed
by, or sponsored by appsolute GmbH**. "MAMP" and "MAMP PRO" are trademarks of
appsolute GmbH, used here only for descriptive comparison (nominative fair use).
All other trademarks are the property of their respective owners.

## License

© OricLab. See repository for license terms.
