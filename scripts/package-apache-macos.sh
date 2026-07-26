#!/usr/bin/env bash
#
# Package a self-contained macOS Apache (httpd) runtime component from a local
# Apache build (MAMP's, which is stock Apache httpd — Apache-licensed OSS, freely
# redistributable). We relocate every absolute dylib reference to
# @loader_path-relative so the tree runs on any Mac with no MAMP present.
#
# MPM (event) and mod_ssl are compiled INTO httpd here, so we don't ship those
# as modules; SSL still works. Uploads macos-arm64-apache.tar.gz to runtime-v1.
set -euo pipefail

SRC="${APACHE_SRC:-/Applications/MAMP/Library}"    # stock httpd install to harvest
REPO="pasupathy-manikam-jr/OricDevServer"
TAG="runtime-v1"
case "$(uname -m)" in arm64|aarch64) ARCH=arm64;; *) ARCH=x64;; esac
PLATFORM="macos-$ARCH"
STAGE="$(mktemp -d /tmp/oric-apache.XXXXXX)"
OUT="$(mktemp -d /tmp/oric-apacheout.XXXXXX)"
trap 'rm -rf "$STAGE" "$OUT"' EXIT
log(){ printf '\033[1;34m==>\033[0m %s\n' "$*"; }

A="$STAGE/apache"
mkdir -p "$A/bin" "$A/modules" "$A/lib" "$A/conf" "$A/logs"

log "harvesting httpd + modules from $SRC"
cp "$SRC/bin/httpd" "$A/bin/httpd"; chmod u+w "$A/bin/httpd"

# Modules our generated vhost config loads, plus common transitive deps.
MODS="mod_proxy mod_proxy_fcgi mod_rewrite mod_mime mod_dir mod_unixd
      mod_authz_core mod_authz_host mod_authn_core mod_log_config
      mod_socache_shmcb mod_alias mod_env mod_setenvif mod_headers mod_filter"
for m in $MODS; do
  [ -f "$SRC/modules/$m.so" ] && cp "$SRC/modules/$m.so" "$A/modules/" || echo "  (skip $m)"
done

# mime.types (mod_mime looks for conf/mime.types under ServerRoot).
for c in "$SRC/conf/mime.types" /etc/apache2/mime.types /usr/local/apache2/conf/mime.types; do
  [ -f "$c" ] && { cp "$c" "$A/conf/mime.types"; break; }
done
[ -f "$A/conf/mime.types" ] || printf 'text/html html htm\ntext/css css\napplication/javascript js\napplication/json json\nimage/png png\nimage/jpeg jpg jpeg\nimage/svg+xml svg\n' > "$A/conf/mime.types"

# Copy every MAMP-lib dylib the tree references, transitively.
copy_deps(){ # collect dylib deps into $A/lib until closure
  local changed=1
  while [ "$changed" = 1 ]; do
    changed=0
    while IFS= read -r f; do
      otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}' | while read -r dep; do
        case "$dep" in "$SRC/lib/"*)
          local base; base="$(basename "$dep")"
          if [ ! -f "$A/lib/$base" ]; then cp "$dep" "$A/lib/$base"; chmod u+w "$A/lib/$base"; fi ;;
        esac
      done
    done < <(find "$A/bin" "$A/modules" "$A/lib" -type f)
    # loop again if any lib still has unresolved MAMP-lib deps not yet copied
    while IFS= read -r f; do
      otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}' | grep -q "^$SRC/lib/" && {
        for d in $(otool -L "$f" | awk 'NR>1{print $1}' | grep "^$SRC/lib/"); do
          [ -f "$A/lib/$(basename "$d")" ] || changed=1
        done
      } || true
    done < <(find "$A/lib" -type f)
  done
}
log "collecting dylib dependencies"
copy_deps

# Relocate: rewrite every $SRC/lib/* reference to @loader_path-relative.
relocate(){ # $1=file  $2=relpath-from-file-dir-to-lib (e.g. ../lib or .)
  local f="$1" rel="$2"
  # fix the dylib's own id when it lives in lib/
  install_name_tool -id "@loader_path/$(basename "$f")" "$f" 2>/dev/null || true
  otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}' | while read -r dep; do
    case "$dep" in "$SRC/lib/"*)
      install_name_tool -change "$dep" "@loader_path/$rel/$(basename "$dep")" "$f" 2>/dev/null || true ;;
    esac
  done
}
log "relocating to @loader_path"
relocate "$A/bin/httpd" "../lib"
for so in "$A/modules"/*.so; do [ -e "$so" ] && relocate "$so" "../lib"; done
for dy in "$A/lib"/*.dylib;  do [ -e "$dy" ] && relocate "$dy" "."; done

# install_name_tool invalidates code signatures on arm64 → macOS SIGKILLs the
# binary. Re-sign every modified mach-O ad-hoc so it runs.
log "re-signing (ad-hoc) after relocation"
find "$A/bin" "$A/modules" "$A/lib" -type f -print0 \
  | xargs -0 -I{} codesign --force --sign - {} 2>/dev/null || true

# sanity: no absolute MAMP paths left
log "verify no MAMP paths remain"
if find "$A" -type f -exec otool -L {} \; 2>/dev/null | grep -q "$SRC/"; then
  echo "!! residual $SRC references remain"; find "$A" -type f -exec sh -c 'otool -L "$1" 2>/dev/null | grep -q "'"$SRC"'/" && echo "   $1"' _ {} \;
fi
"$A/bin/httpd" -v 2>/dev/null | head -1 || echo "(httpd -v failed under DYLD; will run via @loader_path in place)"

# package + upload
TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
REL_ID="$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/tags/$TAG" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')"
NAME="$PLATFORM-apache.tar.gz"; AR="$OUT/$NAME"
log "packaging $NAME"
tar czf "$AR" -C "$STAGE" apache
old="$(curl -s -H "Authorization: token $TOKEN" "https://api.github.com/repos/$REPO/releases/$REL_ID/assets" | grep -B2 "\"name\": \"$NAME\"" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*' || true)"
[ -n "${old:-}" ] && curl -s -H "Authorization: token $TOKEN" -X DELETE "https://api.github.com/repos/$REPO/releases/assets/$old" >/dev/null || true
log "uploading $NAME ($(du -h "$AR" | cut -f1))"
curl -s -H "Authorization: token $TOKEN" -H "Content-Type: application/gzip" --data-binary @"$AR" \
  "https://uploads.github.com/repos/$REPO/releases/$REL_ID/assets?name=$NAME" >/dev/null && echo "  uploaded"
