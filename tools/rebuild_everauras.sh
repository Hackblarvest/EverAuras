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
#   EVERAURAS_UPSTREAM=<commit|tag|branch>         pins the upstream source (default: latest main).
#                                                  A file tools/UPSTREAM with the same content does the
#                                                  same without the variable - commit it to freeze a
#                                                  known-good upstream for everyone building the repo.
set -euo pipefail

REPO="m33shoq/M33kAuras"
VERSION="0.4.0-alpha"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TOOLS/.." && pwd)"
W="$ROOT/m33k-build"
ADDONS="${EVERAURAS_ADDONS:-/d/World of Warcraft/World of Warcraft/_classic_beta_/Interface/AddOns}"
UPSTREAM_DIRS="M33Auras M33kAuras M33kAurasArchive M33kAurasModelPaths M33kAurasOptions M33kAurasTemplates WeakAuras"

rm -rf "$W"; mkdir -p "$W"; cd "$W"

echo "== upstream release (for the bundled libraries)"
url=$(gh api "repos/$REPO/releases/latest" --jq '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -1)
echo "   $url"
curl -sL --max-time 600 -o release.zip "$url"
mkdir release && (cd release && unzip -q ../release.zip)

UPSTREAM_REF="${EVERAURAS_UPSTREAM:-}"
if [ -z "$UPSTREAM_REF" ] && [ -f "$TOOLS/UPSTREAM" ]; then
  UPSTREAM_REF="$(tr -d '[:space:]' < "$TOOLS/UPSTREAM")"
fi
echo "== upstream source (for the Forever fixes): ${UPSTREAM_REF:-latest main}"
if [ -z "$UPSTREAM_REF" ]; then
  git clone -q --depth 1 --branch main "https://github.com/$REPO.git" src
else
  # a shallow fetch of exactly the pinned ref, whether it is a commit, a tag or a branch.
  # A commit must be fetched by its FULL sha (git refuses abbreviated ones); expand it via the API.
  if [[ "$UPSTREAM_REF" =~ ^[0-9a-f]{4,39}$ ]]; then
    UPSTREAM_REF="$(gh api "repos/$REPO/commits/$UPSTREAM_REF" --jq .sha)"
  fi
  git init -q src && git -C src remote add origin "https://github.com/$REPO.git"
  git -C src fetch -q --depth 1 origin "$UPSTREAM_REF"
  git -C src checkout -q FETCH_HEAD
fi
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

echo "== drop the settings-migration stubs (nothing to migrate from on Forever; the names belong to other addons)"
rm -rf release/M33Auras release/WeakAuras

echo "== install"
# our own settings-migration stubs from 0.2-0.4 builds; other addons use the same folder names,
# so remove them only when the TOC says they are ours. Nothing else is ever deleted.
for d in M33Auras WeakAuras; do
  if grep -qs "EverAuras Settings Migration" "$ADDONS/$d/$d.toc"; then rm -rf "$ADDONS/$d"; fi
done
for d in release/*/; do n=$(basename "$d"); rm -rf "$ADDONS/$n"; cp -r "$d" "$ADDONS/$n"; done
for d in "$ROOT"/addons/*/; do n=$(basename "$d"); rm -rf "$ADDONS/$n"; cp -r "$d" "$ADDONS/$n"; done
echo "installed EverAuras $VERSION+$upstream -> $ADDONS"
ls "$ADDONS" | grep -E 'EverAuras|Forever|M33|WeakAuras'
