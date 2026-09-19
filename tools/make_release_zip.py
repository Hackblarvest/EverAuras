"""Zip a built EverAuras install into a release archive.

Usage: python tools/make_release_zip.py <AddOns dir> <version> [out.zip]

Packs the folders a player copies into Interface/AddOns: the five EverAuras folders, the two
settings-migration stubs upstream ships (WeakAuras keeps the Media folder so texture paths in
imported auras still resolve), and !ForeverCompat. ForeverDevInfo (our probes) and the generated
!ForeverSVBridge (per-player, written by tools/sv_bridge.py) are deliberately left out.
"""
import os, sys, zipfile

FOLDERS = ["EverAuras", "EverAurasOptions", "EverAurasArchive", "EverAurasModelPaths",
           "EverAurasTemplates", "M33Auras", "WeakAuras", "!ForeverCompat"]
SKIP_SUFFIX = (".bak", ".orig", ".tmp")


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    addons, version = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else f"EverAuras-{version}.zip"
    missing = [f for f in FOLDERS if not os.path.isdir(os.path.join(addons, f))]
    if missing:
        print("missing folders:", ", ".join(missing)); sys.exit(1)
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for folder in FOLDERS:
            root = os.path.join(addons, folder)
            for dirpath, dirnames, filenames in os.walk(root):
                dirnames.sort()
                for fn in sorted(filenames):
                    if fn.endswith(SKIP_SUFFIX):
                        continue
                    full = os.path.join(dirpath, fn)
                    arc = os.path.relpath(full, addons).replace(os.sep, "/")
                    z.write(full, arc)
                    n += 1
    print(f"{out}: {n} files, {os.path.getsize(out) / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
