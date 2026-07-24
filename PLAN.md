# FlutterMamp — Local Web Server Manager for macOS

A MAMP PRO–style desktop app built with Flutter, managing traditional web servers
(Apache, Nginx) **and** modern PHP application servers (FrankenPHP, RoadRunner, Swoole).

---

## 0. Current State & Prerequisites

**Current state of this directory:** it is an empty Android Studio / Gradle scaffold
(`build.gradle.kts`, `gradlew`, `app/`). It is **not** a Flutter project. We will
either re-scaffold it as a Flutter app or start fresh.

**Missing from this machine — must be installed first:**

| Tool | Status | Needed for |
|------|--------|-----------|
| Flutter SDK | ❌ not installed | everything |
| Xcode + CLI tools | ❔ verify | macOS desktop build, codesigning |
| CocoaPods | ❔ verify | Flutter macOS plugins |
| Homebrew | ❌ not installed | fast path: managing existing services |
| PHP | ❌ not installed | testing any server |

**Action item P0:** install Flutter, enable macOS desktop
(`flutter config --enable-macos-desktop`), confirm `flutter doctor` is green for macOS.

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
- **State**: Riverpod.
- **Process control**: `dart:io` `Process.start`.
- **Native glue**: Swift via `MethodChannel` (privileged helper, macOS niceties).
- **Config templating**: plain Dart string templates (mustache-style) per strategy.
- **Persistence**: JSON config file in `~/Library/Application Support/FlutterMamp/`.
- **Packaging (later)**: `flutter build macos` → codesign → notarize → DMG.

---

## 5. Milestones

### M0 — Environment & scaffold
- [ ] Install Flutter, enable macOS desktop, `flutter doctor` green.
- [ ] Decide: re-scaffold this dir as Flutter, or new dir (Android scaffold is unused).
- [ ] `flutter create` the macOS app; run the default window.

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

1. Install Flutter + enable macOS desktop (P0 blocker).
2. Confirm whether to reuse this directory or create a fresh Flutter project.
3. Scaffold the app and build the `ProcessRunner` + `ServerStrategy` skeleton.
4. Implement `FrankenPhpStrategy` end-to-end as the first vertical slice.
