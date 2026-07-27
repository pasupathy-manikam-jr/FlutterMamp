#!/usr/bin/env bash
#
# Package prebuilt LINUX runtime components and upload to the runtime-v1 release.
# Runnable from macOS: we only download + rearrange + tar (no ELF execution).
# Components needing a Linux compile (nginx, redis, memcached) are handled by CI
# (.github/workflows), not here.
#
# Usage: scripts/package-runtime-linux.sh [component ...]   (default: all here)
set -euo pipefail

ARCH="${ORICDEVSERVER_ARCH:-x86_64}"       # static-php uses x86_64
PLATFORM="linux-x64"
REPO="pasupathy-manikam-jr/OricDevServer"
TAG="runtime-v1"
RT="${ORICDEVSERVER_RUNTIME:-$HOME/.fluttermamp/runtime}"   # for platform-independent 'tools'
STAGE="$(mktemp -d /tmp/oricdevserver-lx.XXXXXX)"
OUT="$(mktemp -d /tmp/oricdevserver-lxout.XXXXXX)"
trap 'rm -rf "$STAGE" "$OUT"' EXIT
log(){ printf '\033[1;34m==>\033[0m %s\n' "$*"; }

TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
REL_ID="$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
  | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')"
log "release $REL_ID  platform $PLATFORM"

upload(){ # $1=id ; tars $STAGE contents listed in $2..
  local id="$1"; shift
  local name="$PLATFORM-$id.tar.gz" a="$OUT/$PLATFORM-$id.tar.gz"
  log "packaging $name ( $* )"
  tar czf "$a" -C "$STAGE" "$@"
  local old
  old="$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO/releases/$REL_ID/assets" \
    | grep -B2 "\"name\": \"$name\"" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*' || true)"
  [ -n "${old:-}" ] && curl -s -H "Authorization: token $TOKEN" -X DELETE \
    "https://api.github.com/repos/$REPO/releases/assets/$old" >/dev/null || true
  log "uploading $name ($(du -h "$a" | cut -f1))"
  curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/gzip" \
    --data-binary @"$a" \
    "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$name" >/dev/null \
    && echo "  uploaded"
  rm -rf "${STAGE:?}/"*
}

dl(){ curl -sSL -o "$1" "$2"; }

pkg(){
  case "$1" in
    php)
      mkdir -p "$STAGE/bin" "$STAGE/src"
      dl "$STAGE/src/fpm.tgz" "https://dl.static-php.dev/static-php-cli/common/php-8.4.8-fpm-linux-$ARCH.tar.gz"
      dl "$STAGE/src/cli.tgz" "https://dl.static-php.dev/static-php-cli/common/php-8.4.8-cli-linux-$ARCH.tar.gz"
      tar xzf "$STAGE/src/fpm.tgz" -C "$STAGE/bin" php-fpm
      tar xzf "$STAGE/src/cli.tgz" -C "$STAGE/bin" php
      chmod +x "$STAGE/bin/php-fpm" "$STAGE/bin/php"; rm -rf "$STAGE/src"
      upload php bin ;;
    mailpit)
      mkdir -p "$STAGE/bin" "$STAGE/src"
      dl "$STAGE/src/m.tgz" "https://github.com/axllent/mailpit/releases/latest/download/mailpit-linux-amd64.tar.gz"
      tar xzf "$STAGE/src/m.tgz" -C "$STAGE/src"
      cp "$(find "$STAGE/src" -name mailpit -type f | head -1)" "$STAGE/bin/mailpit"
      chmod +x "$STAGE/bin/mailpit"; rm -rf "$STAGE/src"
      upload mailpit bin/mailpit ;;
    frankenphp)
      mkdir -p "$STAGE/bin"
      dl "$STAGE/bin/frankenphp" "https://github.com/php/frankenphp/releases/latest/download/frankenphp-linux-$ARCH"
      chmod +x "$STAGE/bin/frankenphp"
      upload frankenphp bin/frankenphp ;;
    tools)
      # platform-independent PHP files — reuse local runtime/tools + php-tools ini
      mkdir -p "$STAGE/tools"
      cp -R "$RT/tools/phpmyadmin" "$STAGE/tools/" 2>/dev/null || true
      cp -R "$RT/tools/adminer"    "$STAGE/tools/" 2>/dev/null || true
      [ -d "$RT/etc/php-tools" ] && { mkdir -p "$STAGE/etc"; cp -R "$RT/etc/php-tools" "$STAGE/etc/"; }
      upload tools tools $( [ -d "$STAGE/etc" ] && echo etc ) ;;
    mysql)
      mkdir -p "$STAGE/src"
      log "downloading MySQL linux MINIMAL tarball (pre-stripped)…"
      dl "$STAGE/src/mysql.tar.xz" "https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.6-linux-glibc2.28-$ARCH-minimal.tar.xz"
      mkdir -p "$STAGE/mysql"; tar xJf "$STAGE/src/mysql.tar.xz" -C "$STAGE/mysql" --strip-components=1
      # slim (same policy as macOS)
      ( cd "$STAGE/mysql/bin"; ls | grep -vxE 'mysqld|mysql|mysqladmin|mysqldump|my_print_defaults' | xargs -I{} rm -f {} 2>/dev/null || true )
      rm -rf "$STAGE/mysql/lib/mecab" "$STAGE/mysql/lib/"*.a "$STAGE/mysql/bin/mysqld-debug" \
             "$STAGE/mysql/docs" "$STAGE/mysql/man" "$STAGE/mysql/include" "$STAGE/mysql/mysql-test" 2>/dev/null || true
      rm -rf "$STAGE/src"
      upload mysql mysql ;;
    *) echo "skip $1" ;;
  esac
}

SET=("$@"); [ "${#SET[@]}" -eq 0 ] && SET=(php mailpit frankenphp tools)
for c in "${SET[@]}"; do pkg "$c"; done
log "done: ${SET[*]}"
