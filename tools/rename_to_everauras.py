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
# Our project ids on the addon sites, so their apps (Wago app, CurseForge app, WowUp) match an install
# to EverAuras. Main TOC only.
SITE_IDS = "## X-Wago-ID: qGYBgENg\n## X-Curse-Project-ID: 1710578"
VERSION = "0.9.1-beta"

# Links. The footer buttons and the TOC website point at OUR project; anything else that
# mentions upstream (Discord invite, CurseForge page, GitHub credits) must keep pointing
# upstream - a dead link is worse than an upstream link.
PROJECT_URL = "https://github.com/Hackblarvest/EverAuras"
UPSTREAM_REPO = "https://github.com/m33shoq/" + OLD
# Order matters: the longer, more specific URL first.
URL_REWRITES = [
    ("https://discord.gg/" + OLD, "https://discord.gg/HdRNYvKbY"),   # the EverAuras Discord
    (UPSTREAM_REPO + "/issues/new?template=bug_report.yml", PROJECT_URL + "/issues"),
    # the footer's "About" button: our README says what EverAuras does and cannot do
    (UPSTREAM_REPO + "/wiki/About-" + OLD, PROJECT_URL + "#readme"),
    # the footer's "Documentation" button (the bare, quoted wiki URL). Help links into wiki SUB-pages
    # (Custom-Triggers, Protected-Frames ...) keep pointing at upstream's wiki, where those pages exist.
    ('"' + UPSTREAM_REPO + '/wiki"', '"' + PROJECT_URL + '"'),
    ("https://www.patreon.com/" + OLD, PROJECT_URL),   # Thanks button, until we have a donation link
    ("## X-Website: https://www.curseforge.com/wow/addons/" + OLD, "## X-Website: " + PROJECT_URL),
    ("please report this to m33shoq.", "please report it on the EverAuras GitHub."),
    ("M33KAURAS_", "EVERAURAS_"),   # upper-case globals and menu tags; they would collide with M33kAuras' own
    ("|cff666666[WA]|r|h", "|cff666666[EA]|r|h"),   # the chat tag before print() lines from an aura's custom code
]
URL_GUARDS = [
    ("https://discord.gg/" + OLD, "\x00DISCORD\x00"),
    ("https://www.curseforge.com/wow/addons/" + OLD, "\x00CURSE\x00"),
    (UPSTREAM_REPO, "\x00GITHUB\x00"),
]
# Names that keep upstream's spelling: upstream 9956a92 marks aura data and export strings as M33kAuras-format
# (internalVersion in M33kAuras numbering), which EverAuras data is. Never raise internalVersion on our own.
NAME_GUARDS = [
    ("internalVersion" + OLD, "\x00KEEP1\x00"),
    ("is" + OLD + " = true", "\x00KEEP2\x00"),
]

TEXT_EXT = {".lua", ".xml", ".toc", ".md", ".txt", ".json"}


def rewrite(text):
    for real, ours in URL_REWRITES:
        text = text.replace(real, ours)
    guards = URL_GUARDS + NAME_GUARDS
    for real, token in guards:
        text = text.replace(real, token)
    text = text.replace(OLD, NEW)
    for real, token in guards:
        text = text.replace(token, real)
    return text


def stamp_toc(text, upstream, main=False):
    """Give each TOC our identity. Title/Author/Version (and on the main TOC our site ids) only; everything
    else is upstream's."""
    text = re.sub(r"^## Author:.*$", f"## Author: {AUTHOR}", text, flags=re.M)
    text = re.sub(r"^## Version:.*$", f"## Version: {VERSION}+{upstream}", text, flags=re.M)
    if main and "## X-Wago-ID:" not in text:
        text = re.sub(r"^(## Version:.*)$", lambda m: m.group(1) + "\n" + SITE_IDS, text, count=1, flags=re.M)
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
                n = stamp_toc(n, upstream, main=(f == OLD + ".toc"))
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
