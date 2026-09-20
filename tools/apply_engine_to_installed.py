"""Apply the ForeverEngineAura integration to the INSTALLED (already renamed) EverAuras copy,
without a full rebuild. Idempotent. Mirrors install_engine_aura() in forever_patches.py exactly,
via the shared hunks in engine_hunks.py, but with EverAuras names.

Usage: python apply_engine_to_installed.py
"""
import io, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from engine_hunks import BUFFTRIGGER2_HUNKS, PROTOTYPES_HUNKS, OPTIONS_HUNKS, CORE_HUNKS, TOC_HUNKS, NEW_FILES, CHECKS, rename

ADDONS = r"D:\World of Warcraft\World of Warcraft\_classic_beta_\Interface\AddOns"
FILES_SRC = os.path.join(HERE, "forever_files")


def read(p):
    return io.open(p, encoding="utf-8", errors="surrogateescape").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)


def apply_hunks(path, hunks, label):
    s = read(path)
    applied = skipped = 0
    for old, new in hunks:
        old, new = rename(old), rename(new)
        if new in s:
            skipped += 1
            continue
        n = s.count(old)
        if n != 1:
            print(f"  !! {label}: anchor count {n} (expected 1): {old.strip()[:70]!r}")
            sys.exit(1)
        s = s.replace(old, new, 1)
        applied += 1
    write(path, s)
    print(f"  {label}: {applied} applied, {skipped} already present")


def main():
    for src_name, rel in NEW_FILES:
        src = os.path.join(FILES_SRC, src_name)
        dst = os.path.join(ADDONS, rename(rel))
        shutil.copyfile(src, dst)
        print(f"  copied {src_name} -> {dst}")

    apply_hunks(os.path.join(ADDONS, rename("M33kAuras/BuffTrigger2.lua")), BUFFTRIGGER2_HUNKS, "BuffTrigger2.lua")
    apply_hunks(os.path.join(ADDONS, rename("M33kAuras/Prototypes.lua")), PROTOTYPES_HUNKS, "Prototypes.lua")
    for rel, hunks in OPTIONS_HUNKS.items():
        apply_hunks(os.path.join(ADDONS, rename(rel)), hunks, rename(rel))
    for rel, hunks in CORE_HUNKS.items():
        apply_hunks(os.path.join(ADDONS, rename(rel)), hunks, rename(rel))
    for rel, old, new in TOC_HUNKS:
        apply_hunks(os.path.join(ADDONS, rename(rel)), [(old, new)], rename(rel))

    for rel, markers in CHECKS.items():
        s = read(os.path.join(ADDONS, rename(rel)))
        for m in markers:
            if rename(m) not in s:
                print("  !! marker missing in", rename(rel), ":", m.strip())
                sys.exit(1)

    # syntax check every Lua file we touched or added
    try:
        from luaparser import ast
    except ImportError:
        print("  (luaparser not available - syntax not verified)")
        return
    for rel in ("M33kAuras/BuffTrigger2.lua", "M33kAuras/Prototypes.lua", "M33kAuras/ForeverEngineAura.lua",
                "M33kAurasOptions/ForeverEngineAuraOptions.lua", "M33kAurasOptions/Cache.lua", "M33kAurasOptions/BuffTrigger2.lua",
                "M33kAuras/M33kAuras.lua"):
        p = os.path.join(ADDONS, rename(rel))
        try:
            ast.parse(io.open(p, encoding="utf-8", errors="replace").read())
            print(f"  syntax OK: {rename(rel)}")
        except Exception as e:
            print(f"  !! SYNTAX ERROR in {rename(rel)}: {e}")
            sys.exit(1)
    print("engine-aura applied to installed copy")


if __name__ == "__main__":
    main()
