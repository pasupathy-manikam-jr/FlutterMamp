# Web server benchmark — Apache vs Nginx vs FrankenPHP

Measured 2026-07-27 on macOS (Darwin 25.5.0, Apple silicon, 10 cores), serving the
same real Laravel 13 + Inertia/React application (`cp4`) from the same document
root against the same bundled MySQL.

**Headline: the three engines are equivalent on application work. The difference
people perceive is response compression, not the engine.**

---

## 1. What was compared

| Engine | Version | PHP | How PHP runs |
| --- | --- | --- | --- |
| Apache | 2.4.66 (Unix) OpenSSL/1.1.1w | 8.4.8 | `mod_proxy_fcgi` → php-fpm over TCP |
| Nginx | 1.27.4 | 8.4.8 | `fastcgi_pass` → php-fpm over TCP |
| FrankenPHP | 1.12.6 (Caddy 2.11.4) | 8.5.8 | embedded in-process (no FastCGI hop) |

All three are the binaries OricDevServer bundles in `~/.fluttermamp/runtime`.

### Method

- Configs were **derived from the ones `ConfigService` actually renders**, so the
  comparison reflects how the app ships them — including php-fpm's
  `pm.max_children = 5` / `pm.start_servers = 1` pool.
- Plain **HTTP only**, on three separate ports (9101/9102/9103), so no TLS or
  HTTP/2 asymmetry contaminates the engine comparison.
- Authenticated as a real user (`user_ID` 16205) with a live session cookie;
  every request does real framework boot, session load, and database work.
- Client sends `Accept-Encoding: gzip, deflate`. The **bytes** column is what
  actually crossed the socket.
- 2×concurrency warm-up requests discarded before each measurement (OPcache).

### Endpoints

| Endpoint | Work involved |
| --- | --- |
| `/dashboard` | baseline authenticated page |
| `/aplan/hierarchy` | Inertia page, ~424 KB uncompressed |
| `/aplan/hierarchy/tree?project=7409` | **recursive CTE over 9,154 nodes**, 1.35 MB JSON |

Plan 7409 (“UT105 MS-11”) is the largest hierarchy this account owns — confirmed
by running the same `WITH RECURSIVE` descent the app uses:

| plan | name | subtree nodes |
| --- | --- | --- |
| **7409** | UT105 MS-11 | **9,154** |
| 17670 | UT105 MS-II T5 (D) | 3,817 |
| 9740 | APM-Festival PFT 2024 (D) | 1,319 |

---

## 2. Results

All latencies in milliseconds. `bytes` = on-the-wire response size.

### `/dashboard` — baseline, serial

| Server | p50 | p95 | mean | req/s | bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apache 2.4.66 | 56 | 58 | 56 | 17.8 | 345,115 |
| Nginx 1.27.4 | 56 | 59 | 57 | 17.7 | 344,336 |
| FrankenPHP | 57 | 59 | 58 | 17.3 | **70,842** |

### `/aplan/hierarchy` — Inertia page, serial

| Server | p50 | p95 | mean | req/s | bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apache 2.4.66 | 16 | 17 | 16 | 64.0 | 328,785 |
| Nginx 1.27.4 | 16 | 17 | 16 | 62.9 | 328,000 |
| FrankenPHP | 17 | 17 | 17 | 59.5 | **68,758** |

### `/aplan/hierarchy/tree` — 9,154 nodes, serial

| Server | p50 | p95 | mean | req/s | bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apache 2.4.66 | **178** | 181 | 179 | 5.6 | 1,346,561 |
| Nginx 1.27.4 | **177** | 182 | 177 | 5.6 | 1,346,561 |
| FrankenPHP | 196 | 199 | 196 | 5.1 | **260,099** |

### `/aplan/hierarchy/tree` — concurrency 6

| Server | p50 | p95 | mean | req/s | bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Apache 2.4.66 | 317 | 418 | 310 | 17.0 | 1,346,561 |
| Nginx 1.27.4 | 349 | 406 | 303 | 17.6 | 1,346,561 |
| FrankenPHP | **297** | **383** | 314 | **18.6** | **260,099** |

---

## 3. Findings

### 3.1 The engines are equivalent on application work

Serial latency differs by **under 1 ms** on both page endpoints — well inside
run-to-run noise. Time is dominated by Laravel boot and MySQL, which are
identical across engines. Removing the FastCGI hop (FrankenPHP's structural
advantage) buys nothing measurable, because that hop is a loopback TCP write
costing microseconds against a 56 ms request.

### 3.2 FrankenPHP is ~10% *slower* on the heavy endpoint

196 ms vs 177–178 ms on the 1.35 MB tree — consistently, not noise. The likely
cause is compression itself: zstd/brotli over 1.35 MB costs real CPU per request,
and on loopback that buys nothing because bandwidth is effectively free. Over a
real network the trade reverses.

### 3.3 Compression is the whole story

| Endpoint | Apache / Nginx | FrankenPHP | Ratio |
| --- | ---: | ---: | ---: |
| `/dashboard` | 345 KB | 71 KB | **4.9×** |
| `/aplan/hierarchy` | 329 KB | 69 KB | **4.8×** |
| tree (9,154 nodes) | 1,347 KB | 260 KB | **5.2×** |

FrankenPHP compresses by default. **The generated Nginx and Apache configs
contain no compression directives at all** — verified: zero `gzip`, `brotli`, or
`zstd` matches in `nginx-site-*.conf`, and no `mod_deflate` in the Apache config.

On loopback that costs nothing. In a browser over any real link it is the
difference between 1.35 MB and 260 KB per request.

### 3.4 Under concurrency FrankenPHP edges ahead — slightly

18.6 vs 17.0–17.6 req/s at concurrency 6, with the best p50 and p95. Real but
small (~6–9%). php-fpm's shipped `pm.max_children = 5` did not prove to be the
bottleneck at this level; MySQL and PHP execution dominate.

### 3.5 Configuration gaps found while measuring

1. **No compression in the Nginx or Apache configs.** Adding `gzip on` (Nginx)
   or `mod_deflate` (Apache) would erase FrankenPHP's only real advantage here.
2. **No HTTP/2 in the Nginx config.** It renders `listen 127.0.0.1:8443 ssl;`
   with no `http2 on;`, so TLS sites are HTTP/1.1 — Chrome then caps at ~6
   connections per origin, each with its own handshake, while FrankenPHP's Caddy
   serves h2. Not captured by this benchmark (HTTP-only), but it is a real
   browser-level difference on a page issuing many parallel requests.
3. **`site.phpVersion` is never used.** It is not referenced anywhere in
   `config_service.dart`; every engine runs the bundled php-fpm 8.4.8 (or
   FrankenPHP's embedded 8.5.8). The per-site PHP Version dropdown currently has
   no effect on any engine.

---

## 4. Caveats

- **Loopback only.** Zero network latency and effectively infinite bandwidth,
  which systematically understates compression's value and overstates its CPU cost.
- **`APP_DEBUG=true` with Laravel Debugbar active** — inflates every number, but
  equally across all three engines, so relative comparison holds.
- **No FrankenPHP worker mode.** Every request boots Laravel from scratch, the
  same as php-fpm. Worker mode (PLAN.md M2) is where FrankenPHP's real advantage
  would appear and was *not* measured here.
- Single machine, single run per cell; differences under ~5 ms are not meaningful.
- Serial numbers use one client thread, so they measure latency, not capacity.

## 5. Conclusion

For this workload, **choose the engine on features, not speed.** Apache and Nginx
are indistinguishable. FrankenPHP is marginally slower on CPU-bound single
requests, marginally faster under concurrency, and ships far fewer bytes purely
because compression is on by default.

The perception that FrankenPHP is dramatically faster comes from its defaults —
compression and HTTP/2 — not from its architecture. Turning those on for Nginx
and Apache is a small config change and would likely close the gap entirely.

Reproduce with `scratchpad/setup3.sh` + `scratchpad/bench3.py`.
