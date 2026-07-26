#!/usr/bin/env bash
#
# Package the local OricMamp runtime binaries into per-component, self-contained
# tarballs and upload them to the GitHub `runtime-v1` release so the app can
# download them on demand.
#
# Usage:
#   scripts/package-runtime.sh                # small/medium components
#   scripts/package-runtime.sh all            # everything (incl. mysql/frankenphp)
#   scripts/package-runtime.sh redis nginx    # just these
#
# macOS only (uses otool/install_name_tool). Relocates any dylib dependency that
# points into the runtime dir to an @loader_path-relative path, and bundles that
# dylib into the archive — so binaries work under a different $HOME/username.
set -euo pipefail

RUNTIME="${ORICMAMP_RUNTIME:-$HOME/.fluttermamp/runtime}"
STAGE="$(mktemp -d /tmp/oricmamp-pkg.XXXXXX)"
OUT="$(mktemp -d /tmp/oricmamp-out.XXXXXX)"
REPO="pasupathy-manikam-jr/FlutterMamp"
TAG="runtime-v1"

case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  *) ARCH=x64 ;;
esac
PLATFORM="macos-$ARCH"

trap 'rm -rf "$STAGE" "$OUT"' EXIT

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- GitHub auth + release id --------------------------------------------------
TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
[ -n "$TOKEN" ] || { echo "No GitHub token from git credential"; exit 1; }

REL_ID="$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
  | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*' || true)"
if [ -z "${REL_ID:-}" ]; then
  log "Creating release $TAG"
  REL_ID="$(curl -s -H "Authorization: token $TOKEN" -X POST \
    "https://api.github.com/repos/$REPO/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"OricMamp runtime v1\",\"prerelease\":true}" \
    | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')"
fi
log "Release id: $REL_ID  platform: $PLATFORM"

# --- helpers -------------------------------------------------------------------

# Copy a mach-O binary into the stage tree and relocate its runtime dylib deps.
bundle_binary() {
  local rel="$1"                        # e.g. bin/memcached (relative to RUNTIME)
  local src="$RUNTIME/$rel" dst="$STAGE/$rel"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"; chmod u+w "$dst"
  otool -L "$src" | awk 'NR>1{print $1}' | while read -r dep; do
    case "$dep" in
      "$RUNTIME"/*)
        local depRel="${dep#"$RUNTIME"/}"     # deps/lib/libevent-2.1.7.dylib
        mkdir -p "$STAGE/$(dirname "$depRel")"
        cp -f "$dep" "$STAGE/$depRel" 2>/dev/null || true
        local newref
        newref="@loader_path/$(python3 -c "import os;print(os.path.relpath('$depRel', os.path.dirname('$rel')))")"
        install_name_tool -change "$dep" "$newref" "$dst" 2>/dev/null || true
        ;;
    esac
  done
}

# Copy plain files/dirs (no relocation) into the stage tree.
stage_copy() {
  local rel="$1"
  mkdir -p "$STAGE/$(dirname "$rel")"
  cp -R "$RUNTIME/$rel" "$STAGE/$rel"
}

# tar the staged component and upload it.
package_and_upload() {
  local id="$1"; shift
  local name="$PLATFORM-$id.tar.gz"
  local archive="$OUT/$name"
  log "Packaging $name ( $* )"
  tar czf "$archive" -C "$STAGE" "$@"
  local size; size="$(du -h "$archive" | cut -f1)"
  # delete an existing asset of the same name
  local old
  old="$(curl -s -H "Authorization: token $TOKEN" \
    "https://api.github.com/repos/$REPO/releases/$REL_ID/assets" \
    | grep -B2 "\"name\": \"$name\"" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*' || true)"
  if [ -n "${old:-}" ]; then
    curl -s -H "Authorization: token $TOKEN" -X DELETE \
      "https://api.github.com/repos/$REPO/releases/assets/$old" >/dev/null || true
  fi
  log "Uploading $name ($size)…"
  curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/gzip" \
    --data-binary @"$archive" \
    "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$name" \
    | grep -oE '"browser_download_url": "[^"]*"' || echo "  (upload response had no url)"
  rm -rf "${STAGE:?}/"* # reset stage for next component
}

# --- per-component recipes -----------------------------------------------------
pkg() {
  case "$1" in
    redis)
      bundle_binary bin/redis-server; bundle_binary bin/redis-cli
      package_and_upload redis bin/redis-server bin/redis-cli ;;
    memcached)
      bundle_binary bin/memcached
      package_and_upload memcached bin $( [ -d "$STAGE/deps" ] && echo deps ) ;;
    mailpit)
      bundle_binary bin/mailpit
      package_and_upload mailpit bin/mailpit ;;
    php)
      bundle_binary bin/php-fpm; bundle_binary bin/php
      package_and_upload php bin/php-fpm bin/php ;;
    frankenphp)
      bundle_binary bin/frankenphp
      package_and_upload frankenphp bin/frankenphp ;;
    nginx)
      bundle_binary nginx/sbin/nginx
      # include the rest of the nginx tree (conf, html, etc.) unmodified
      for d in conf html; do [ -e "$RUNTIME/nginx/$d" ] && stage_copy "nginx/$d"; done
      package_and_upload nginx nginx $( [ -d "$STAGE/deps" ] && echo deps ) ;;
    tools)
      stage_copy tools/phpmyadmin; stage_copy tools/adminer 2>/dev/null || true
      [ -d "$RUNTIME/etc/php-tools" ] && stage_copy etc/php-tools
      package_and_upload tools tools $( [ -d "$STAGE/etc" ] && echo etc ) ;;
    mysql)
      # Slim: keep mysqld + core client tools + all runtime dylibs + share;
      # drop mysqld-debug (~200M), lib/mecab (~120M), static *.a libs, and the
      # ~30 client tools we never launch. Verified to init + boot.
      mkdir -p "$STAGE/mysql/bin"
      for b in mysqld mysql mysqladmin mysqldump my_print_defaults; do
        cp "$RUNTIME/mysql/bin/$b" "$STAGE/mysql/bin/" 2>/dev/null || true
      done
      cp "$RUNTIME/mysql/bin/"*.dylib "$STAGE/mysql/bin/" 2>/dev/null || true
      cp -R "$RUNTIME/mysql/lib" "$STAGE/mysql/lib"
      rm -rf "$STAGE/mysql/lib/mecab" "$STAGE/mysql/lib/"*.a
      cp -R "$RUNTIME/mysql/share" "$STAGE/mysql/share"
      package_and_upload mysql mysql ;;
    *) echo "unknown component: $1" ;;
  esac
}

# --- selection -----------------------------------------------------------------
DEFAULT=(redis memcached mailpit php nginx tools)   # skip huge frankenphp/mysql by default
ALL=(redis memcached mailpit php frankenphp nginx tools mysql)

if [ "$#" -eq 0 ]; then
  SET=("${DEFAULT[@]}")
elif [ "$1" = "all" ]; then
  SET=("${ALL[@]}")
else
  SET=("$@")
fi

for c in "${SET[@]}"; do pkg "$c"; done
log "Done. Published components: ${SET[*]}"
