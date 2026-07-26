# FlutterMamp — Local Web Server Manager for macOS

A MAMP PRO–style desktop app built with Flutter, managing traditional web servers
(Apache, Nginx) **and** modern PHP application servers (FrankenPHP, RoadRunner, Swoole).

---

## 0. Current State & Prerequisites

**Directory is now a Flutter macOS project** (`lib/`, `macos/`, `pubspec.yaml`). The
original Android/Gradle scaffold was removed. Code compiles clean (`flutter analyze`:
no issues) and unit tests pass. It cannot be *run* yet — that needs full Xcode.

**Environment status (as of 2026-07-25):**

| Tool | Status | Notes |
|------|--------|-------|
| Flutter SDK | ✅ 3.44.8 stable | `~/development/flutter`, on PATH, macOS desktop enabled |
| Dart | ✅ 3.12.2 | bundled with Flutter |
| **Full Xcode** | ❌ **BLOCKER** | only Command Line Tools present; required to build/run macOS app — user must install from App Store |
| CocoaPods | ❌ not installed | needs Homebrew (system Ruby 2.6 too old); only needed once native plugins are added — not yet |
| Homebrew | ❌ not installed | installer needs interactive sudo/tty; user must run it. Not required for current scope |
| PHP / Apache / Nginx | ✅ via MAMP PRO | PHP 7.3–8.5 (8.3 running as project `cp4`), Apache 2.4.66, Nginx 1.29.4 |
| FrankenPHP / RoadRunner / Swoole | ✅ installed | parked (see §2 scope); binaries in `tools/servers/`, Swoole 6.2.2 built for MAMP PHP 8.3 |

**P0 action item — user only:** install **full Xcode** from the App Store, then
`sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`,
`sudo xcodebuild -runFirstLaunch`, `sudo xcodebuild -license accept`.

**Scope note:** current milestone focuses on **Apache, Nginx, PHP** (all present via
MAMP). FrankenPHP/RoadRunner/Swoole are installed but deferred.

**Flutter skills installed:** the official `flutter/skills` set (22 skills) is in
`.claude/skills/`. The layered architecture below follows
`flutter-apply-architecture-best-practices`.

---

## 1. Goals & Scope

### In scope (v1)
- Native macOS GUI (Flutter desktop) to start/stop/monitor local web servers.
- Per-site configuration: document root, port, PHP version, server type.
- Support **two server families**:
  - **Traditional**: Apache, Nginx (+ PHP-FPM, classic per-request model).
  - **App servers**: FrankenPHP, RoadRunner, Swoole (resident PHP, worker mode).
- Config-file generation per server type (vhost / Caddyfile / `.rr.yaml`).
- Live log viewer and status indicators.

### Out of scope (v1, revisit later)
- Bundling our own compiled Apache/MySQL/PHP binaries + notarized installer.
- Multi-version PHP compilation from source.
- Auto-SSL for Apache/Nginx (FrankenPHP gets it free via Caddy).
- Windows / Linux ports.

### Strategy decision: **manage-existing (Homebrew) first**
Ship a working product faster by managing Homebrew-installed binaries rather than
bundling our own. Bundling + notarization is where months disappear; defer it.

---

## 2. Server Types — Two Categories

The core architectural insight: servers fall into two operational models.

| Server | Language | Model | Config artifact | PHP-FPM? |
|--------|----------|-------|-----------------|----------|
| Apache | C | traditional | `httpd-vhosts.conf` | yes |
| Nginx | C | traditional | `nginx` server block | yes |
| **FrankenPHP** | **Go** (Caddy) | app server | `Caddyfile` | no |
| **RoadRunner** | **Go** | app server | `.rr.yaml` | no |
| **Swoole** | **C ext.** | app server | PHP entrypoint script | no |

Notes:
- **FrankenPHP** & **RoadRunner** = single static Go binaries → easy to bundle later.
- **Swoole** is a **PHP extension**, not a standalone binary. It requires a
  Swoole-enabled PHP build, so it couples to PHP-version management. Usually driven
  via Laravel Octane (`php artisan octane:start --server=swoole`) or a raw
  `Swoole\Http\Server` script.

---

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter (Dart) — UI layer                   │
│  sidebar · site list · start/stop · logs     │
└───────────────┬─────────────────────────────┘
                │ Riverpod state
┌───────────────▼─────────────────────────────┐
│  Core (Dart)                                 │
│  ServiceManager · ServerStrategy (per type)  │
│  ConfigGenerator · ProcessRunner · LogTailer │
└───────────────┬─────────────────────────────┘
                │ dart:io Process / platform channels
┌───────────────▼──────────────┐  ┌────────────┐
│  Server binaries             │  │ Swift native│
│  apache/nginx/php-fpm        │  │ privileged  │
│  frankenphp/rr/php(swoole)   │  │ helper      │
└──────────────────────────────┘  └────────────┘
```

### Key abstraction: `ServerStrategy`
```dart
abstract class ServerStrategy {
  ServerType get type;
  Future<void> renderConfig(Site site);   // writes vhost / Caddyfile / .rr.yaml
  Future<ServerProcess> start(Site site); // spawns process, returns handle
  Future<void> stop(ServerProcess p);
  Stream<ServerStatus> watch(ServerProcess p);
  Stream<String> logs(ServerProcess p);
}
```
Concrete implementations: `ApacheStrategy`, `NginxStrategy`, `FrankenPhpStrategy`,
`RoadRunnerStrategy`, `SwooleStrategy`. Each renders a different config file but
shares the same `ProcessRunner`.

### Data model
```dart
enum ServerType { apache, nginx, frankenphp, roadrunner, swoole }

class Site {
  String name;
  String docRoot;
  ServerType server;
  int port;
  String phpVersion;              // swoole needs a swoole-enabled build
  String? workerScript;           // frankenphp/rr/swoole worker mode
  bool https;                     // free on frankenphp
  Map<String, dynamic> extra;     // strategy-specific knobs
}
```

### The privilege problem
Binding ports < 1024 and editing `/etc/hosts` needs root. MAMP PRO installs a
privileged helper via `launchd`. Plan:
- v1: use **high ports** (e.g. 8000+) to avoid privilege escalation entirely.
- v2: Swift privileged helper (`SMAppService`) invoked over a platform channel for
  low ports + `/etc/hosts` entries.

---

## 4. Tech Stack

- **Flutter** (stable), macOS desktop target.
- **State**: MVVM with `ChangeNotifier` ViewModels + manual constructor injection
  (per the `flutter-apply-architecture-best-practices` skill — **no Riverpod**).
- **Process control**: `dart:io` `Process.start`.
- **Native glue**: Swift via `MethodChannel` (privileged helper, macOS niceties).
- **Config templating**: plain Dart string templates (mustache-style) per strategy.
- **Persistence**: JSON config file in `~/Library/Application Support/FlutterMamp/`.
- **Packaging (later)**: `flutter build macos` → codesign → notarize → DMG.

---

## 5. Milestones

### M0 — Environment & scaffold
- [x] Install Flutter 3.44.8, enable macOS desktop, device detected.
- [x] Removed unused Android scaffold; `flutter create` macOS app in this dir.
- [x] Disable macOS sandbox entitlements (needed to spawn MAMP binaries).
- [ ] Run the default window — **blocked on full Xcode install**.

### M1 — Core process layer
- [ ] `ProcessRunner` wrapper around `Process.start` (spawn, stop, capture stdout/err).
- [ ] `ServerStrategy` interface + `ServerProcess` handle.
- [ ] `LogTailer` streaming process output to UI.
- [ ] Config + persistence (`Site` model ↔ JSON).

### M2 — First server: FrankenPHP (recommended starting strategy)
- [ ] `FrankenPhpStrategy`: render `Caddyfile`, `frankenphp run`, status, logs.
- [ ] Minimal UI: one site, Start/Stop button, live status, log pane.
- [ ] Verify a "Hello World" PHP file serves over HTTP.

### M3 — Second app server: RoadRunner
- [ ] `RoadRunnerStrategy`: render `.rr.yaml`, `rr serve`, status via RPC.
- [ ] Prove the strategy abstraction holds with a second, differently-configured server.

### M4 — Traditional servers: Nginx + PHP-FPM
- [ ] `NginxStrategy` + PHP-FPM lifecycle (two coordinated processes).
- [ ] Vhost generation.
- [ ] (Apache after Nginx — same pattern.)

### M5 — Swoole
- [ ] Requires Swoole-enabled PHP build → depends on PHP-version handling.
- [ ] Drive via Octane or raw `Swoole\Http\Server` entrypoint.

### M6 — Full UI & sites management
- [ ] Multi-site sidebar, add/edit/delete, per-site server-type picker.
- [ ] Global status, port-conflict detection.

### M7 — Privilege escalation & polish (v2)
- [ ] Swift privileged helper for low ports + `/etc/hosts`.
- [ ] Codesign + notarize + DMG.

---

## 6. Build Order Rationale

1. **FrankenPHP first** — single static Go binary, auto-HTTPS, worker mode. Easiest
   to install/bundle and validates the `AppServer` abstraction.
2. **RoadRunner** — same single-binary pattern, different config renderer. Confirms
   the strategy layer generalizes.
3. **Nginx / Apache** — introduces the two-process (server + PHP-FPM) coordination.
4. **Swoole last** — coupled to PHP-version/extension management; needs that groundwork.

---

## 7. Open Questions

- [ ] Bundle binaries eventually, or stay Homebrew-managed permanently?
- [ ] Which PHP versions to support, and how (Homebrew formulae vs. static builds)?
- [ ] MySQL/MariaDB + phpMyAdmin — in scope for v1 or a later milestone?
- [ ] Reuse this `FlutterMamp` directory (wipe Android scaffold) or start clean?

---

## 8. Immediate Next Steps

1. **User:** install full Xcode (P0 blocker for running the app).
2. Once Xcode is in: `flutter run -d macos`, then debug the real start/stop of
   Apache/Nginx/PHP against MAMP binaries.
3. Refine Apache/Nginx generated configs against runtime (module paths, PHP FastCGI).
4. Add persistence (`Site` list to JSON) and multi-host support.

---

## 9. Implemented Architecture (as built)

Layered per the `flutter-apply-architecture-best-practices` skill:

```text
lib/
├── domain/models/          # immutable: ServerType, ServerStatus, PhpVersion,
│                           #   MampEnvironment, ManagedServer
├── data/
│   ├── services/           # MampService (discovery), ConfigService (per-engine
│   │                       #   config + LaunchSpec — the "strategy"),
│   │                       #   ServerProcessService (dart:io Process wrapper)
│   └── repositories/       # ServerRepository — single source of truth, emits
│                           #   changes stream, orchestrates the services
└── ui/
    ├── core/theme.dart     # palette + status→traffic-light color
    └── features/servers/
        ├── view_models/    # ServersViewModel (ChangeNotifier)
        └── views/          # ServersView (toolbar+sidebar+detail), ServerTile,
                            #   ServerDetail, LogPanel
```

- **Engine strategies** live in `ConfigService`: PHP = `php -S`; Nginx = generated
  foreground `nginx.conf`; Apache = generated foreground `httpd.conf` (`-X`). All
  run in the foreground and are stopped by killing the pid.
- **Ports** default to 8000/8001/8002 to avoid clashing with running MAMP PRO.
- **Config output** goes to `~/Library/Application Support/FlutterMamp/` — never
  touches MAMP PRO's own config.
- **Verified:** `flutter analyze` clean; domain unit tests pass. Not yet run (Xcode).

---

## 10. Progress Log

- **2026-07-25**
  - Installed Flutter 3.44.8 + macOS desktop; parked FrankenPHP/RoadRunner/Swoole
    (built Swoole 6.2.2 for MAMP PHP 8.3 via a from-source m4→autoconf toolchain).
  - Narrowed active scope to Apache/Nginx/PHP (all via MAMP).
  - Installed official `flutter/skills` (22) into `.claude/skills/`.
  - Scaffolded Flutter macOS app; removed Android scaffold; disabled sandbox.
  - Built full layered MVVM vertical slice (domain + data + UI) for Apache/Nginx/PHP.
  - Added settings persistence (`SettingsService` → `settings.json`) and
    open-in-browser / reveal-in-Finder (`SystemService` via macOS `open`, no plugin).
  - Chose the non-App-Store Xcode route: installed the `xcodes` CLI; user is
    downloading Xcode direct from Apple (accepted Developer T&Cs to clear a 403).
  - Installed Xcode 26.6 (via `xcodes`, non-App-Store); app **builds & runs** on macOS.
  - Removed the Claude co-author trailer from git history (amend + force-push).
  - **Refactored from fixed engines → user-created Sites** (like MAMP PRO Hosts):
    `Site` model, `SiteRepository` with add/edit/delete/start/stop + JSON persistence
    (`sites.json`), native folder picker via `osascript` (no plugin/CocoaPods),
    Add-Site dialog, editable detail pane, sidebar with +/− and status dots.
  - Dropped PHP built-in server as an engine — engines are now **Apache/Nginx only**
    (matches MAMP PRO); PHP runs via **FastCGI** to MAMP's `php-cgi` (2 processes/site).
  - Added **custom hostnames** (`/etc/hosts` via native admin prompt — `HostsService`)
    and **SSL/HTTPS** (self-signed certs via MAMP `openssl` — `CertService`), with
    Apache/Nginx TLS + FastCGI config generation. UI gains Host Name + SSL toggle/port.
  - Fixes from live testing on the real `cp4` PHP app:
    - Detail-pane fields now commit **on change** (hostname/port were lost if you
      clicked Start/Open before pressing Enter).
    - Apache FastCGI: added **`ProxyFCGIBackendType GENERIC`** — MAMP's `php-cgi`
      is a generic FastCGI backend, and mod_proxy_fcgi's default FPM mode caused
      "No input file specified". Verified by reproducing via curl against MAMP's
      httpd + php-cgi (plain SetHandler failed; GENERIC served the real app).
  - Added **Trust Certificate** action: adds the self-signed cert to the System
    keychain as a trusted root (`security add-trusted-cert` via admin prompt) for
    a real green padlock, mirroring MAMP.
  - Committed & pushed the app to the private repo (no co-author trailer).
  - **Direction change → independence from MAMP.** Goal: FlutterMamp manages its
    OWN binaries (bundle/download/build) and eventually MAMP PRO is removed.
    - New `runtime/` dir (`~/Library/Application Support/FlutterMamp/runtime/bin`)
      holds our own binaries — **Redis 8.8.1** (built from source, arm64) and
      **MailHog** (downloaded) so far. `RuntimeService` discovers them (never MAMP).
    - Added global **Services** feature (like MAMP PRO's Server tab): `ServiceType`
      / `ManagedService`, `ServiceLauncher`, `ServiceRepository`, `ServicesViewModel`,
      and a **SERVICES** sidebar section (Redis, MySQL, Memcached, MailHog) with
      inline start/stop. Redis/Memcached/MailHog launchable; MySQL shows until we
      bundle MariaDB + init a datadir (next).
    - Sites (Apache/Nginx/PHP) still use MAMP binaries for now — the hard part of
      independence; migrating to bundled/own binaries is the remaining big work.
  - `flutter analyze`: no issues. Unit tests: pass. App verified running on macOS.

### M8 — Independence from MAMP (new, in progress)
- [x] `runtime/` dir + `RuntimeService`; bundle Redis (built) + MailHog (downloaded).
- [x] Global Services feature (Redis/Memcached/MailHog start-stop, MySQL stub).
- [x] Bundle **MySQL 8.4.6** (own arm64 tarball) + init datadir; wire start/stop.
      Smoke-tested: boots, accepts connections.
- [x] Bundle **Memcached 1.6.38** (+ libevent) built from source.
- [x] Bundle **Nginx 1.27.4** (+ pcre2) built from source.
- [x] **Runtime lives at `~/.fluttermamp/runtime`** (space-free) — "Application
      Support" breaks autotools/make; runtime datadirs may still live there.
- [x] Bundle **PHP 8.4.8** (static php-fpm + cli from static-php.dev; has
      pdo_mysql/redis/mbstring/openssl/curl/gd).
- [x] **Wire Nginx sites to our own Nginx + php-fpm** — MAMP-free. Smoke-tested:
      served the real cp4 app end-to-end (843 KB HTML) via bundled nginx+php-fpm.
- [x] SSL cert generation switched to system `/usr/bin/openssl` (MAMP-free).
- [ ] **Apache** independence (hardest — APR toolchain). Recommendation: use
      Nginx for the MAMP-free path; keep Apache on MAMP or defer.
- [ ] PHP version selection for nginx sites (currently fixed at bundled 8.4.8).
- [ ] Data migration: cp4's DB lives in MAMP's MySQL; ours is empty.
- [ ] Data migration: cp4's DB currently lives in MAMP's MySQL; our MySQL is a
      fresh empty instance (dump/import needed to fully switch).
- [ ] In-app "download runtime" so a fresh install fetches its own binaries.
- [x] **Import SQL dump** view: pick a `.sql`/`.sql.gz`, choose DB + creds
      (root/root), imports via bundled mysql client (`DatabaseService`). Button on
      the running MySQL row.
- [x] MySQL: our PHP connects fine (PDO OK) even with caching_sha2_password;
      set root password + created cp4's `aimsfx_db3`.
- [x] **Mailpit** (native arm64) replaces MailHog — working start/stop.
- [x] **Orphan cleanup**: reap-on-startup (`ProcessCleanup` pkills our runtime
      processes) + stop-on-quit (`AppLifecycleListener.onExitRequested` disposes
      repos). Fixes leftover redis/httpd squatting on ports after force-quit.
- [x] **Database admin tools** (TOOLS sidebar section): **Adminer** (single file)
      and **phpMyAdmin** — both served on demand by **FrankenPHP** (its embedded
      PHP 8.5.8 has `mysqli`, which our php-fpm build lacks). Open button starts
      FrankenPHP + opens browser; phpMyAdmin auto-logs into our MySQL (root/root).
      Verified: both return HTTP 200 with their UIs.
- [x] **Import SQL dump** view (📤 on the MySQL row) via bundled mysql client.
      Hardened (max_allowed_packet=1G); imported cp4's real DB — **254 tables,
      18M+ rows** (860 MB gzip) that phpMyAdmin's web upload couldn't handle.
- [x] **Working SSL** via a local root CA (mkcert model): `CertService` makes a
      CA:TRUE root + per-site leaf certs (SAN, serverAuth) signed by it. Trust the
      CA once → every site's HTTPS is valid (verified `ssl_verify_result=0`, real
      padlock). Fixed the earlier "can't trust a leaf as root" failure.
- [x] **Copyable log panel** (SelectionArea + Copy button).
- [x] Suppressed phpMyAdmin PHP 8.5 deprecation noise (tools php.ini via
      PHP_INI_SCAN_DIR).
- [x] **Renamed app FlutterMamp → OricMamp** (toolbar, window title, PRODUCT_NAME).

### cp4 migration: COMPLETE
cp4 runs entirely on OricMamp's own stack — Nginx/Apache + php-fpm + MySQL (full
data) + Redis — with working trusted HTTPS. MAMP PRO no longer needed for it.
Known false-positive: the Trust Certificate button can report "could not trust"
even when the CA was trusted (osascript exit-code quirk) — harden later.

### Post-migration fixes & features
- [x] Fixed nginx **duplicate `daemon` directive** (conf sets `daemon off;`; dropped
      the redundant `-g 'daemon off;'`).
- [x] **Rebuilt Nginx with `--with-http_ssl_module`** (OpenSSL 3.0.15 statically
      compiled from source) so HTTPS works on Nginx too — still MAMP-free.
- [x] **Per-site php.ini editing**: PHP Configuration field on each site; applied
      to php-fpm via `-c` (nginx) and php-cgi via additive `-d` flags (Apache).

### Open / next
- [ ] Nginx `client_max_body_size` knob (large uploads need it alongside php.ini).
- [ ] Harden Trust Certificate button (verify trust status vs. osascript exit code).
- [ ] Auto-start MySQL when opening phpMyAdmin/Adminer.
- [ ] Bundle Apache for full independence (Nginx already is); or drop Apache.
- [ ] In-app "download runtime" so a fresh install fetches its own binaries.
