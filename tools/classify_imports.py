"""Decode WeakAuras export strings offline and predict how each display behaves on WoW Forever.

Usage: python tools/classify_imports.py <file-with-export-string> [...]
Needs: lupa (pip install lupa). Decoding runs the addon's own libraries (LibDeflate, LibSerialize,
AceSerializer) from the installed EverAuras folder under Lua 5.1, exactly like the in-game import.
The client folder defaults to the usual beta path; set EVERAURAS_CLIENT to point elsewhere.

The verdict comes from the engine itself: tools/forever_files/ForeverEngineAura.lua is loaded with
small WoW stubs and Engine.Classify runs on every display, so this tool can never drift from the
addon's rules. Each display lands in one bucket:
  ENGINE  the engine draws its Aura trigger(s) -> works in combat. Extra non-aura triggers ("gates")
          keep running in WeakAuras and must be readable in combat themselves.
  PLAIN   no Aura trigger (cooldowns, usable, resources, casts ...) -> readable in combat
  CUSTOM  has a custom-code trigger and is not engine-driven -> depends on what the code reads
  BLIND   has an Aura trigger the engine cannot take over -> hidden in combat on Forever
Spell NAMES are assumed to resolve and to have been seen as real auras (true for your own class's
spells once you have used them); names of other classes' spells do not resolve in game.
"""
import os, sys, collections
from lupa.lua51 import LuaRuntime

CLIENT = os.environ.get("EVERAURAS_CLIENT", r"D:\World of Warcraft\World of Warcraft\_classic_beta_")
LIBS = os.path.join(CLIENT, "Interface", "AddOns", "EverAuras", "Libs")
ENGINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_files", "ForeverEngineAura.lua")


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


# Just enough of the client and the addon for ForeverEngineAura.lua to load and classify.
ENGINE_STUBS = r"""
  issecretvalue = function() return false end
  InCombatLockdown = function() return false end
  STANDARD_TEXT_FONT = "font"
  Enum = { LuaCurveType = { Linear = 0, Step = 1 }, DurationTextBindingProperty = { RemainingDuration = 0 },
           StatusBarTimerDirection = { ElapsedTime = 0, RemainingTime = 1 }, SpellBookSpellBank = { Player = 0 },
           SpellBookItemType = { Spell = 1, FutureSpell = 2 } }
  local function frame()
    local f = {}
    for _, m in ipairs({ "RegisterEvent", "RegisterUnitEvent", "SetScript", "Hide", "Show", "SetPoint",
                         "SetAllPoints", "SetFrameLevel", "SetSize", "SetUnit" }) do f[m] = function() end end
    f.AddAuraSlot = function() return {} end
    f.AddAuraGroup = function() return true end
    f.GetFrameLevel = function() return 1 end
    return f
  end
  CreateFrame = function() return frame() end
  C_AddOns = { IsAddOnLoaded = function() return true end }
  C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
  SlashCmdList = {}
  -- every spell name resolves to a stable fake id and counts as seen (see the module docstring)
  local ids, nextId = {}, 100000
  local function idFor(name)
    name = name:lower()
    if not ids[name] then nextId = nextId + 1; ids[name] = nextId end
    return ids[name]
  end
  C_Spell = {
    GetSpellName = function(id) return "spell" .. tostring(id) end,
    GetSpellInfo = function(name) return { spellID = idFor(name) } end,
    IsSpellPassive = function() return false end,
    GetSpellTexture = function() return 134400 end,
  }
  C_SpellBook = { GetNumSpellBookSkillLines = function() return 0 end }
  EverAuras = { IsLibsOK = function() return true end, L = {}, prettyPrint = function() end,
                GetData = function() return nil end,
                LoadFunction = function(src) local f, err = loadstring(src); if not f then error(err) end; return f() end }
  EverAurasSaved = { foreverEngine = { learned = setmetatable({}, { __index = function(_, k) return { [idFor(k)] = true } end }) } }
  local realLibStub = LibStub
  LibStub = setmetatable({}, { __call = function(_, name, silent)
    if name == "LibSharedMedia-3.0" then return { Fetch = function() return "font" end } end
    if name == "Masque" then return nil end
    return realLibStub(name, silent)
  end })
  Private = {
    regionTypes = { icon = { default = {}, modify = function() end }, aurabar = { default = {}, modify = function() end } },
    ApplyFrameLevel = function() end, Pause = function() end, Resume = function() end,
    callbacks = { RegisterCallback = function() end }, frames = {}, AuraWarnings = { UpdateWarning = function() end },
  }
"""

VERDICT = r"""function(data)
  if data.foreverEngine == nil then data.foreverEngine = true end   -- the import fills region defaults
  local plan, reasons = Private.ForeverEngine.Classify(data)
  if not plan then return false, table.concat(reasons or {}, "; ") end
  local gates = (plan.gates or 0) > 0 and (" + %d gate(s)"):format(plan.gates) or ""
  if not plan.parts then return true, ("%s %s%s"):format(plan.mode, plan.filterString, gates) end
  local bits = {}
  if plan.parts.missing then bits[#bits + 1] = "missing" end
  for _, rp in ipairs(plan.parts.remaining) do bits[#bits + 1] = ("time left %s %s s"):format(rp.op, tostring(rp.x)) end
  return true, table.concat(bits, " or ") .. gates
end"""


def make_engine(lua):
    lua.execute(ENGINE_STUBS)
    src = open(ENGINE, encoding="utf-8").read()
    lua.execute("local f = assert(loadstring(..., '=ForeverEngineAura')); f('EverAuras', Private)", src)
    return lua.eval(VERDICT)


def trigger_types(item):
    tr = item["triggers"]
    out = []
    i = 1
    while tr and tr[i] is not None:
        t = tr[i]["trigger"]
        out.append(str(t["type"]) if t is not None else "None")
        i += 1
    return out


def classify(verdict, item):
    """-> (bucket, text)"""
    types = trigger_types(item)
    ok, text = verdict(item)
    if ok:
        return "ENGINE", text
    if "custom" in types:
        return "CUSTOM", "custom-code trigger"
    if "aura2" not in types and "aura" not in types:
        return "PLAIN", ""
    return "BLIND", text


def walk(root):
    """yields every non-group display of an import (d = top, c = children), as Lua tables."""
    items = [root["d"]]
    kids = root["c"]
    if kids is not None:
        items += [kids[k] for k in sorted(kids.keys())]
    for item in items:
        if item is not None and not item["controlledChildren"] and item["regionType"] not in ("group", "dynamicgroup"):
            yield item


def main(paths):
    lua, decode = make_decoder()
    verdict = make_engine(lua)
    total = collections.Counter()
    reasons_all = collections.Counter()
    for p in paths:
        s = open(p, encoding="utf-8").read().strip()
        t, info = decode(s)
        name = os.path.basename(p)
        if t is None:
            print("== %s: NOT DECODED (%s)" % (name, info)); continue
        disp = list(walk(t))
        top = t["d"]["id"] if t["d"] is not None else None
        print("== %s  '%s'  format v%s  %d display(s)" % (name, top, info, len(disp)))
        for item in disp:
            bucket, text = classify(verdict, item)
            total[bucket] += 1
            if bucket == "BLIND":
                for x in text.split("; "):
                    reasons_all[x] += 1
            print("   %-7s %-36s %-9s [%s] %s" % (bucket, str(item["id"])[:36], item["regionType"],
                                                ",".join(trigger_types(item)), ("- " + text) if text else ""))
    print("\n== totals:", dict(total))
    if reasons_all:
        print("== why BLIND, most common first:")
        for k, n in reasons_all.most_common():
            print("   %3d  %s" % (n, k))


if __name__ == "__main__":
    main(sys.argv[1:])
