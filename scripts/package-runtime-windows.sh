#!/usr/bin/env bash
#
# Package prebuilt WINDOWS runtime components and upload to the runtime-v1 release.
# Runnable from macOS: we only download + unzip + rearrange + tar (no .exe run).
#
# Windows sites serve via FrankenPHP (embedded PHP), like Linux — so we don't
# need a Windows php-fpm. nginx/memcached for Windows can be added later.
#
# Usage: scripts/package-runtime-windows.sh [component ...]   (default: all here)
set -euo pipefail

PLATFORM="windows-x64"
REPO="pasupathy-manikam-jr/FlutterMamp"
TAG="runtime-v1"
RT="${ORICMAMP_RUNTIME:-$HOME/.fluttermamp/runtime}"   # for platform-independent 'tools'
STAGE="$(mktemp -d /tmp/oricmamp-win.XXXXXX)"
OUT="$(mktemp -d /tmp/oricmamp-winout.XXXXXX)"
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
    mailpit)
      mkdir -p "$STAGE/bin" "$STAGE/src"
      dl "$STAGE/src/m.zip" "https://github.com/axllent/mailpit/releases/latest/download/mailpit-windows-amd64.zip"
      unzip -oq "$STAGE/src/m.zip" -d "$STAGE/src"
      cp "$(find "$STAGE/src" -iname 'mailpit.exe' | head -1)" "$STAGE/bin/mailpit.exe"
      rm -rf "$STAGE/src"; upload mailpit bin/mailpit.exe ;;
    frankenphp)
      mkdir -p "$STAGE/bin" "$STAGE/src"
      dl "$STAGE/src/f.zip" "https://github.com/php/frankenphp/releases/latest/download/frankenphp-windows-x86_64.zip"
      unzip -oq "$STAGE/src/f.zip" -d "$STAGE/src"
      cp "$(find "$STAGE/src" -iname 'frankenphp*.exe' | head -1)" "$STAGE/bin/frankenphp.exe"
      rm -rf "$STAGE/src"; upload frankenphp bin/frankenphp.exe ;;
    redis)
      mkdir -p "$STAGE/bin" "$STAGE/src"
      dl "$STAGE/src/r.zip" "https://github.com/tporadowski/redis/releases/download/v5.0.14.1/Redis-x64-5.0.14.1.zip"
      unzip -oq "$STAGE/src/r.zip" -d "$STAGE/src"
      cp "$(find "$STAGE/src" -iname 'redis-server.exe' | head -1)" "$STAGE/bin/redis-server.exe"
      cp "$(find "$STAGE/src" -iname 'redis-cli.exe' | head -1)" "$STAGE/bin/redis-cli.exe"
      rm -rf "$STAGE/src"; upload redis bin/redis-server.exe bin/redis-cli.exe ;;
    tools)
      # platform-independent PHP web tools (phpMyAdmin/Adminer) + their php.ini
      mkdir -p "$STAGE/tools"
      cp -R "$RT/tools/phpmyadmin" "$STAGE/tools/" 2>/dev/null || true
      cp -R "$RT/tools/adminer"    "$STAGE/tools/" 2>/dev/null || true
      [ -d "$RT/etc/php-tools" ] && { mkdir -p "$STAGE/etc"; cp -R "$RT/etc/php-tools" "$STAGE/etc/"; }
      upload tools tools $( [ -d "$STAGE/etc" ] && echo etc ) ;;
    mysql)
      mkdir -p "$STAGE/src"
      log "downloading MySQL winx64 zip (~350MB)…"
      dl "$STAGE/src/mysql.zip" "https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-8.4.6-winx64.zip"
      unzip -oq "$STAGE/src/mysql.zip" -d "$STAGE/src"
      local top; top="$(find "$STAGE/src" -maxdepth 1 -type d -name 'mysql-*' | head -1)"
      mkdir -p "$STAGE/mysql/bin"
      for b in mysqld mysql mysqladmin mysqldump my_print_defaults; do
        cp "$top/bin/$b.exe" "$STAGE/mysql/bin/" 2>/dev/null || true
      done
      cp "$top/bin/"*.dll "$STAGE/mysql/bin/" 2>/dev/null || true   # runtime DLLs
      cp -R "$top/lib" "$STAGE/mysql/lib" 2>/dev/null || true
      cp -R "$top/share" "$STAGE/mysql/share" 2>/dev/null || true
      # drop debug symbols + static libs
      find "$STAGE/mysql" \( -name '*.pdb' -o -name '*.lib' \) -delete 2>/dev/null || true
      rm -rf "$STAGE/src"; upload mysql mysql ;;
    *) echo "skip $1" ;;
  esac
}

SET=("$@"); [ "${#SET[@]}" -eq 0 ] && SET=(mailpit frankenphp redis tools)
for c in "${SET[@]}"; do pkg "$c"; done
log "done: ${SET[*]}"
