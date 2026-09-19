"""Apply BigWigs-packager release filters to unpackaged addon source (Lua + XML).
Usage: python packager_filters.py <addon dir> [<addon dir> ...]   (Libs/ subfolders are skipped)
Filters: debug, alpha, experimental -> commented out; non-<filter> blocks -> uncommented;
do-not-package blocks -> removed. Run ONCE on fresh source (not idempotent for XML)."""
import os, sys
FILTERS = ["debug", "alpha", "experimental"]
def lua(t):
    for f in FILTERS:
        t = t.replace("--[===[@non-" + f + "@", "--@non-" + f + "@")
        t = t.replace("--@end-non-" + f + "@]===]", "--@end-non-" + f + "@")
        t = t.replace("--@" + f + "@", "--[===[@" + f + "@")
        t = t.replace("--@end-" + f + "@", "--@end-" + f + "@]===]")
    return strip_block(t, "--@do-not-package@", "--@end-do-not-package@")
def xml(t):
    for f in FILTERS:
        t = t.replace("<!--@non-" + f + "@", "<!--@non-" + f + "@-->")
        t = t.replace("@end-non-" + f + "@-->", "<!--@end-non-" + f + "@-->")
        t = t.replace("<!--@" + f + "@-->", "<!--@" + f + "@")
        t = t.replace("<!--@end-" + f + "@-->", "@end-" + f + "@-->")
    return strip_block(t, "<!--@do-not-package@-->", "<!--@end-do-not-package@-->")
def strip_block(t, start, end):
    out, skip = [], False
    for line in t.splitlines(keepends=True):
        if start in line: skip = True; continue
        if end in line: skip = False; continue
        if not skip: out.append(line)
    return "".join(out)
changed = 0
for root in sys.argv[1:]:
    for dp, dn, fn in os.walk(root):
        if "Libs" in dp.split(os.sep): continue
        for f in fn:
            p = os.path.join(dp, f); low = f.lower()
            if not (low.endswith(".lua") or low.endswith(".xml")): continue
            s = open(p, encoding="utf-8", errors="surrogateescape").read()
            n = lua(s) if low.endswith(".lua") else xml(s)
            if n != s:
                open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(n); changed += 1
print("files changed:", changed)
