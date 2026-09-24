#!/usr/bin/env python3
"""
Rename the M33kAuras build into our fork, EverAuras.

Run as a BUILD STEP, after the upstream overlay and after forever_patches.py (whose
anchors still use the upstream names), and before installing. That way we can keep
pulling fixes from upstream and our branding is re-applied automatically every time.

Every identifier upstream uses is prefixed "M33kAuras", so one ordered replacement
covers folders, TOC names, globals (M33kAurasSaved -> EverAurasSaved), AceGUI
widget names and user-visible strings in one pass.

Usage: python rename_to_everauras.py <build dir>
"""
import os
import re
import sys

OLD, NEW = "M33kAuras", "EverAuras"
AUTHOR = "Hackblarvest"
VERSION = "0.4.0-alpha"

# Links. The footer buttons and the TOC website point at OUR project; anything else that
# mentions upstream (Discord invite, CurseForge page, GitHub credits) must keep pointing
# upstream - a dead link is worse than an upstream link.
PROJECT_URL = "https://github.com/Hackblarvest/EverAuras"
URL_REWRITES = [
    ("https://discord.gg/" + OLD, "https://discord.gg/HdRNYvKbY"),   # the EverAuras Discord
    ("https://github.com/m33shoq/" + OLD + "/issues/new?template=bug_report.yml", PROJECT_URL + "/issues"),
    ("https://github.com/m33shoq/" + OLD + "/wiki", PROJECT_URL),
    ("https://www.patreon.com/" + OLD, PROJECT_URL),   # Thanks button, until we have a donation link
    ("## X-Website: https://www.curseforge.com/wow/addons/" + OLD, "## X-Website: " + PROJECT_URL),
]
URL_GUARDS = [
    ("https://discord.gg/" + OLD, "\x00DISCORD\x00"),
    ("https://www.curseforge.com/wow/addons/" + OLD, "\x00CURSE\x00"),
    ("https://github.com/m33shoq/" + OLD, "\x00GITHUB\x00"),
]

TEXT_EXT = {".lua", ".xml", ".toc", ".md", ".txt", ".json"}


def rewrite(text):
    for real, ours in URL_REWRITES:
        text = text.replace(real, ours)
    for real, token in URL_GUARDS:
        text = text.replace(real, token)
    text = text.replace(OLD, NEW)
    for real, token in URL_GUARDS:
        text = text.replace(token, real)
    return text


def stamp_toc(text, upstream):
    """Give each TOC our identity. Title/Author/Version only; everything else is upstream's."""
    text = re.sub(r"^## Author:.*$", f"## Author: {AUTHOR}", text, flags=re.M)
    text = re.sub(r"^## Version:.*$", f"## Version: {VERSION}+{upstream}", text, flags=re.M)
    if "## X-Upstream:" not in text:
        text = re.sub(
            r"^(## Version:.*)$",
            r"\1\n## X-Upstream: m33shoq/M33kAuras " + upstream + " (fork of WeakAuras/WeakAuras2, GPL-2.0)",
            text, count=1, flags=re.M)
    return text


def main(root, upstream="unknown"):
    if not os.path.isdir(root):
        sys.exit(f"build dir not found: {root}")

    # 1. file contents (deepest first is irrelevant here, but do files before renames)
    touched = 0
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if os.path.splitext(f)[1].lower() not in TEXT_EXT:
                continue
            p = os.path.join(dp, f)
            try:
                s = open(p, encoding="utf-8", errors="surrogateescape").read()
            except OSError:
                continue
            n = rewrite(s)
            if f.lower().endswith(".toc"):
                n = stamp_toc(n, upstream)
            if n != s:
                open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(n)
                touched += 1
    print(f"  rewrote {touched} files")

    # 2. file names (TOCs etc.), deepest first so parents still exist
    renamed_f = 0
    for dp, dn, fn in os.walk(root, topdown=False):
        for f in fn:
            if OLD in f:
                os.replace(os.path.join(dp, f), os.path.join(dp, f.replace(OLD, NEW)))
                renamed_f += 1
    print(f"  renamed {renamed_f} files")

    # 3. directory names, deepest first
    renamed_d = 0
    for dp, dn, fn in os.walk(root, topdown=False):
        for d in dn:
            if OLD in d:
                os.replace(os.path.join(dp, d), os.path.join(dp, d.replace(OLD, NEW)))
                renamed_d += 1
    print(f"  renamed {renamed_d} directories")

    print("  addons now:", ", ".join(sorted(x for x in os.listdir(root) if os.path.isdir(os.path.join(root, x)))))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".", sys.argv[2] if len(sys.argv) > 2 else "unknown")
