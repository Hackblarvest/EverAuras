"""Decode WeakAuras export strings offline and predict how each display behaves on WoW Forever.

Usage: python tools/classify_imports.py <file-with-export-string> [...]
Needs: lupa (pip install lupa). Decoding runs the addon's own libraries (LibDeflate, LibSerialize,
AceSerializer) from the installed EverAuras folder under Lua 5.1, exactly like the in-game import.

Each display lands in one bucket:
  ENGINE  an Aura trigger the engine can draw  -> works in combat
  PLAIN   no Aura trigger (cooldowns, usable, resources, casts ...) -> readable in combat
  CUSTOM  has a custom-code trigger -> depends on what the code reads; untested
  ENGINE+ one Aura trigger plus readable triggers combined with "all": would become ENGINE if the
          engine accepted extra non-aura triggers
  BLIND   has an Aura trigger the engine cannot take over -> hidden in combat on Forever
The engine rules mirror Engine.Classify in tools/forever_files/ForeverEngineAura.lua. Spell NAMES are
assumed to resolve (they do for your own class's spells); names of other classes' spells do not.
"""
import os, sys, collections
from lupa.lua51 import LuaRuntime

LIBS = r"D:\World of Warcraft\World of Warcraft\_classic_beta_\Interface\AddOns\EverAuras\Libs"

UNIT_OK = {"player", "target", "focus", "pet"}
MODE = {"showOnActive": "found", "showOnMissing": "missing", "showAlways": "always"}
UNSUPPORTED = ["useNamePattern", "useIgnoreName", "useIgnoreExactSpellId", "use_debuffClass",
               "useRem", "useStacks", "useTotal", "use_tooltip", "fetchTooltip", "use_unitName", "use_npcId",
               "use_stealable", "use_isBossDebuff", "use_castByPlayer", "useAffected", "showClones",
               "useGroup_count"]


def make_decoder():
    lua = LuaRuntime(unpack_returned_tuples=True)
    # the WoW client's string/table shorthands the libraries expect as globals
    lua.execute("""
      strmatch, strfind, strsub, strbyte, strchar, strlen = string.match, string.find, string.sub, string.byte, string.char, string.len
      strrep, strlower, strupper, strtrim = string.rep, string.lower, string.upper, function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
      format, gsub, gmatch = string.format, string.gsub, string.gmatch
      tinsert, tremove, tconcat, sort = table.insert, table.remove, table.concat, table.sort
      wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
      floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
    """)
    for rel in ("LibStub/LibStub.lua", "LibDeflate/LibDeflate.lua", "LibSerialize/LibSerialize.lua",
                "AceSerializer-3.0/AceSerializer-3.0.lua"):
        path = os.path.join(LIBS, rel)
        src = open(path, encoding="utf-8").read()
        lua.execute("local f = assert(loadstring(...)); f('" + os.path.basename(rel).split(".")[0] + "')", src)
    decode = lua.eval("""function(s)
      local LibDeflate, LibSerialize = LibStub("LibDeflate"), LibStub("LibSerialize")
      local Ace = LibStub("AceSerializer-3.0")
      local _, _, v, encoded = s:find("^(!WA:%d+!)(.+)$")
      if v then v = tonumber(v:match("%d+")) else encoded, v = s:gsub("^%!", "") end
      if v == 0 then return nil, "legacy (pre-2019) format, not handled here" end
      local decoded = LibDeflate:DecodeForPrint(encoded)
      if not decoded then return nil, "DecodeForPrint failed" end
      local raw = LibDeflate:DecompressDeflate(decoded)
      if not raw then return nil, "DecompressDeflate failed" end
      local ok, t
      if v < 2 then ok, t = Ace:Deserialize(raw) else ok, t = LibSerialize:Deserialize(raw) end
      if not ok then return nil, "deserialize failed" end
      return t, v
    end""")
    return lua, decode


def to_py(lua, v, depth=0):
    if depth > 40:
        return None
    if lua.eval("type")(v) == "table":
        out = {}
        for k, val in v.items():
            out[k] = to_py(lua, val, depth + 1)
        return out
    return v


def triggers_of(d):
    tr = d.get("triggers") or {}
    return [tr[k] for k in sorted(k for k in tr if isinstance(k, int))]


def classify(d):
    """-> (bucket, reasons)"""
    trigs = triggers_of(d)
    types = [(t or {}).get("trigger", {}).get("type") for t in trigs]
    if "custom" in types:
        return "CUSTOM", ["custom-code trigger"]
    if "aura2" not in types and "aura" not in types:
        return "PLAIN", []
    r = []
    if d.get("regionType") != "icon":
        r.append("region is %s, the engine draws Icons only" % d.get("regionType"))
    if d.get("foreverEngine") is False:
        r.append("engine toggle off")
    if len(trigs) != 1:
        # would it qualify if the engine accepted extra NON-aura triggers combined with "all"?
        auras = [x for x in trigs if ((x or {}).get("trigger") or {}).get("type") in ("aura2", "aura")]
        mode = (d.get("triggers") or {}).get("disjunctive") or "all"
        if len(auras) == 1 and mode == "all" and d.get("regionType") == "icon":
            sub_bucket, sub_r = classify(dict(d, triggers={1: auras[0]}))
            if sub_bucket == "ENGINE":
                return "ENGINE+", ["%d triggers: 1 aura + %d readable, 'all' - ok if the engine accepted extra non-aura triggers"
                                   % (len(trigs), len(trigs) - 1)]
            return "BLIND", ["%d triggers" % len(trigs)] + sub_r
        r.append("%d triggers (%d aura, mode '%s')" % (len(trigs), len(auras), mode))
        return "BLIND", r
    t = trigs[0].get("trigger", {})
    if t.get("type") != "aura2":
        r.append("legacy Aura trigger (converted on import)")
        return "BLIND", r
    if (t.get("unit") or "player") not in UNIT_OK:
        r.append("unit '%s'" % t.get("unit"))
    if (t.get("debuffType") or "HELPFUL") not in ("HELPFUL", "HARMFUL"):
        r.append("Aura Type 'Both'")
    if (t.get("matchesShowOn") or "showOnActive") not in MODE:
        r.append("Show On '%s'" % t.get("matchesShowOn"))
    ids = [s for s in (t.get("auraspellids") or {}).values()] if t.get("useExactSpellId") else []
    names = [s for s in (t.get("auranames") or {}).values() if str(s).strip()] if t.get("useName") else []
    if not ids and not names:
        r.append("no spell id or name")
    for k in UNSUPPORTED:
        if t.get(k):
            r.append("option %s" % k)
    return ("ENGINE" if not r else "BLIND"), r


def walk(root):
    """yields (id, data) for every non-group display in an import (d = top, c = children)."""
    d = root.get("d") or {}
    kids = root.get("c") or {}
    items = [d] + [kids[k] for k in sorted(kids)]
    for item in items:
        if item and not item.get("controlledChildren") and item.get("regionType") not in ("group", "dynamicgroup"):
            yield item.get("id"), item


def main(paths):
    lua, decode = make_decoder()
    total = collections.Counter()
    reasons_all = collections.Counter()
    for p in paths:
        s = open(p, encoding="utf-8").read().strip()
        t, info = decode(s)
        name = os.path.basename(p)
        if t is None:
            print("== %s: NOT DECODED (%s)" % (name, info)); continue
        root = to_py(lua, t)
        disp = list(walk(root))
        top = (root.get("d") or {}).get("id")
        print("== %s  '%s'  format v%s  %d display(s)" % (name, top, info, len(disp)))
        for did, data in disp:
            bucket, reasons = classify(data)
            total[bucket] += 1
            for x in reasons if bucket == "BLIND" else []:
                reasons_all[x.split(" (")[0].split(" '")[0]] += 1
            trig = triggers_of(data)
            tt = ",".join(str(((x or {}).get("trigger") or {}).get("type")) for x in trig)
            print("   %-7s %-36s %-9s [%s] %s" % (bucket, str(did)[:36], data.get("regionType"), tt,
                                                ("- " + "; ".join(reasons)) if reasons else ""))
    print("\n== totals:", dict(total))
    if reasons_all:
        print("== why BLIND, most common first:")
        for k, n in reasons_all.most_common():
            print("   %3d  %s" % (n, k))


if __name__ == "__main__":
    main(sys.argv[1:])
