#!/usr/bin/env bash
# Rebuilds EverAuras - our World of Warcraft: Forever fork of M33kAuras / WeakAuras - and installs it.
#
#   libs    = latest upstream GitHub release zip (packager output, has all externals)
#   source  = upstream main branch (where the Forever fixes land)
#   patches = our Forever fixes + the engine-driven aura system
#             (tools/forever_patches.py, tools/engine_hunks.py, tools/forever_files/)
#   brand   = our rename to EverAuras (tools/rename_to_everauras.py)
#   addons  = our companion addons (addons/*), installed alongside
#
# Upstream: m33shoq/M33kAuras, itself a fork of WeakAuras/WeakAuras2 (GPL-2.0).
# Our changes live in this repository, never in the vendored source, so upstream fixes can
# be pulled at any time by simply re-running this script. Every anchored patch hard-fails
# the build if upstream moved underneath it.
#
# Usage (Git Bash):   bash tools/rebuild_everauras.sh
#   EVERAURAS_ADDONS=<path to Interface/AddOns>   overrides the install location
set -euo pipefail

REPO="m33shoq/M33kAuras"
VERSION="0.2.0-alpha"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOLS/.." && pwd)"
W="$ROOT/m33k-build"
ADDONS="${EVERAURAS_ADDONS:-/d/World of Warcraft/World of Warcraft/_classic_beta_/Interface/AddOns}"
UPSTREAM_DIRS="M33Auras M33kAuras M33kAurasArchive M33kAurasModelPaths M33kAurasOptions M33kAurasTemplates WeakAuras"
# earlier brand of this fork; removed on install so nothing loads twice
LEGACY_DIRS="ForeverAuras ForeverAurasArchive ForeverAurasModelPaths ForeverAurasOptions ForeverAurasTemplates"

rm -rf "$W"; mkdir -p "$W"; cd "$W"

echo "== upstream release (for the bundled libraries)"
url=$(gh api "repos/$REPO/releases/latest" --jq '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -1)
echo "   $url"
curl -sL --max-time 600 -o release.zip "$url"
mkdir release && (cd release && unzip -q ../release.zip)

echo "== upstream main (for the Forever fixes)"
git clone -q --depth 1 --branch main "https://github.com/$REPO.git" src
upstream="$(git -C src rev-parse --short HEAD)"
echo "   $upstream  ($(git -C src log -1 --format='%ci %s'))"

echo "== overlay source over the release libraries"
for d in $UPSTREAM_DIRS; do
  [ -d "src/$d" ] || continue
  (cd "src/$d" && find . -type f ! -path '*/Libs/*' | while read -r f; do
     mkdir -p "$W/release/$d/$(dirname "$f")"; cp "$f" "$W/release/$d/$f"; done)
done

echo "== interface version + packager tokens"
today=$(date +%Y-%m-%d)
for t in release/*/*.toc; do
  grep -q '^## Interface:.*16001' "$t" || sed -i -E 's/^(## Interface: [0-9, ]+)$/\1, 16001/' "$t"
done
grep -rlE '@project-version@|@build-time@|@project-date-iso@|@project-abbreviated-hash@' release \
  --include=*.lua --include=*.xml --include=*.toc | while read -r f; do
  sed -i -E "s/@project-version@/$VERSION+$upstream/g; s/@build-time@/$today/g; s/@project-date-iso@/$today/g; s/@project-abbreviated-hash@/$upstream/g" "$f"
done
# Init.lua compares the TOC version against the literal token to detect an unpackaged build.
sed -i "s/if versionStringFromToc == \"$VERSION+$upstream\" then/if versionStringFromToc == \"@project-version@\" then/" release/M33kAuras/Init.lua

echo "== packager filters (@debug@/@alpha@ off, @non-debug@ on, @do-not-package@ dropped)"
python "$TOOLS/packager_filters.py" $(for d in $UPSTREAM_DIRS; do [ -d "release/$d" ] && printf 'release/%s ' "$d"; done)

echo "== Forever fixes (IsRetail routing, spec IDs, secrets, engine-driven auras)"
python "$TOOLS/forever_patches.py" release

echo "== rebrand to EverAuras"
python "$TOOLS/rename_to_everauras.py" release "$upstream"

echo "== install"
for d in $UPSTREAM_DIRS $LEGACY_DIRS; do rm -rf "$ADDONS/$d"; done
for d in release/*/; do n=$(basename "$d"); rm -rf "$ADDONS/$n"; cp -r "$d" "$ADDONS/$n"; done
for d in "$ROOT"/addons/*/; do n=$(basename "$d"); rm -rf "$ADDONS/$n"; cp -r "$d" "$ADDONS/$n"; done
echo "installed EverAuras $VERSION+$upstream -> $ADDONS"
ls "$ADDONS" | grep -E 'EverAuras|Forever|M33|WeakAuras'
