"""Forever-specific patches for the M33kAuras hybrid build. Idempotent: safe to re-run.
Usage: python forever_patches.py <AddOns dir>
Why: the fork's IsRetail() is BuildInfo >= 120000, false on Forever (16001), so several
API-selection sites fall into the Classic path and call removed globals (UnitAura etc.)."""
import os, sys
root = sys.argv[1]
if not os.path.isdir(os.path.join(root, "M33kAuras")):
    print("  (build already rebranded to ForeverAuras - patches belong before the rename, skipping)")
    sys.exit(0)
def patch(rel, pairs):
    p = os.path.join(root, rel)
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    n = 0
    for old, new in pairs:
        if new in s: continue            # already patched
        if old not in s: print("  !! anchor not found in", rel, ":", old.strip()[:60]); continue
        s = s.replace(old, new, 1); n += 1
    if n:
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
    print(f"  {rel}: {n} patch(es) applied")

R = "M33kAuras.IsRetail()"
RF = "(M33kAuras.IsRetail() or M33kAuras.IsForever())"

patch("M33kAuras/BuffTrigger2.lua", [
    ("local FixDebuffClass\nif " + R + " then", "local FixDebuffClass\nif " + RF + " then"),
    ("local newAPI = " + R, "local newAPI = " + RF),
    ("  if " + R + " then\n    -- TODO change this when more events are handled by system",
     "  if " + RF + " then\n    -- TODO change this when more events are handled by system"),
])
patch("M33kAuras/GenericTrigger.lua", [
    ("      if " + R + " then\n        tenchFrame:RegisterEvent(\"WEAPON_ENCHANT_CHANGED\")",
     "      if " + RF + " then\n        tenchFrame:RegisterEvent(\"WEAPON_ENCHANT_CHANGED\")"),
    ("      if " + R + " then\n        getTenchName = function(id)\n          local tooltipData = C_TooltipInfo",
     "      if " + RF + " then\n        getTenchName = function(id)\n          local tooltipData = C_TooltipInfo"),
])
# LibSpecialization: Forever gives every class ONE spec (ChrSpecialization 1.60.1.69913), Role=2 (DAMAGER) for all.
POS = """	[1480] = "RANGED", -- Devourer (DPS)
	-- WoW: Forever 1.60 single-spec classes (ChrSpecialization build 69913)
	[1482] = "RANGED", -- Mage (Forever)
	[1484] = "RANGED", -- Druid (Forever)
	[1485] = "RANGED", -- Hunter (Forever)
	[1486] = "MELEE", -- Paladin (Forever)
	[1487] = "RANGED", -- Priest (Forever)
	[1488] = "MELEE", -- Rogue (Forever)
	[1489] = "MELEE", -- Shaman (Forever)
	[1490] = "RANGED", -- Warlock (Forever)
	[1491] = "MELEE", -- Warrior (Forever)
"""
ROLE = """	[1480] = "DAMAGER", -- Devourer (DPS)
	-- WoW: Forever 1.60 single-spec classes, all flagged DAMAGER by Blizzard
	[1482] = "DAMAGER", -- Mage (Forever)
	[1484] = "DAMAGER", -- Druid (Forever)
	[1485] = "DAMAGER", -- Hunter (Forever)
	[1486] = "DAMAGER", -- Paladin (Forever)
	[1487] = "DAMAGER", -- Priest (Forever)
	[1488] = "DAMAGER", -- Rogue (Forever)
	[1489] = "DAMAGER", -- Shaman (Forever)
	[1490] = "DAMAGER", -- Warlock (Forever)
	[1491] = "DAMAGER", -- Warrior (Forever)
"""
patch("M33kAuras/Libs/LibSpecialization/LibSpecialization.lua", [
    ('\t[1480] = "RANGED", -- Devourer (DPS)\n', POS),
    ('\t[1480] = "DAMAGER", -- Devourer (DPS)\n', ROLE),
])

# --- migration churn: m33kMigrated is never set on a native install, so Init's migration
#     block runs every login (enabling/disabling stub addons). Stop it once data exists. ---
def patch_migration(root):
    p = os.path.join(root, "M33kAuras", "Init.lua")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    anchor = "M33kAurasSaved = M33kAurasSaved or {};\n"
    add = ("-- Forever: a native install with data has nothing to migrate from M33Auras/WeakAuras.\n"
           "if M33kAurasSaved.displays and next(M33kAurasSaved.displays) and not M33kAurasSaved.m33kMigrated then\n"
           "  M33kAurasSaved.m33kMigrated = true\n"
           "end\n")
    if add in s:
        print("  Init.lua migration: already patched")
    elif anchor in s:
        s = s.replace(anchor, anchor + add, 1)
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
        print("  Init.lua migration: patched")
    else:
        print("  !! migration anchor not found in Init.lua")

patch_migration(root)

# --- diagnostic: mirror every swallowed Lua error into M33kAurasSaved.foreverErrors,
#     so it lands on disk at /reload/logout even when scriptErrors is off. ---
def patch_error_capture(root):
    p = os.path.join(root, "M33kAuras", "M33kAuras.lua")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    anchor = "  local function waErrorHandler(errorMessage)\n    local juicedMessage = {}\n"
    add = ("    if M33kAurasSaved then\n"
           "      M33kAurasSaved.foreverErrors = M33kAurasSaved.foreverErrors or {}\n"
           "      M33kAurasSaved.foreverErrors[#M33kAurasSaved.foreverErrors + 1] = {\n"
           "        context = tostring(currentErrorHandlerContext),\n"
           "        id = tostring(currentErrorHandlerId or currentErrorHandlerUid),\n"
           "        err = tostring(errorMessage),\n"
           "      }\n"
           "      if #M33kAurasSaved.foreverErrors > 25 then table.remove(M33kAurasSaved.foreverErrors, 1) end\n"
           "    end\n")
    if "M33kAurasSaved.foreverErrors" in s:
        print("  error-capture: already patched")
    elif anchor in s:
        s = s.replace(anchor, anchor + add, 1)
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
        print("  error-capture: patched")
    else:
        print("  !! error-capture anchor not found")

patch_error_capture(root)

# --- load diagnostic: record, at the very first line that touches the SavedVariable,
#     whether the game restored it. -2 = global was nil (SV NOT restored),
#     -1 = table but no displays key, N = number of displays restored. ---
def patch_load_diag(root):
    p = os.path.join(root, "M33kAuras", "Init.lua")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    anchor = "M33kAurasSaved = M33kAurasSaved or {};\n"
    diag = ("do -- Forever load diagnostic\n"
            "  local incoming = -2\n"
            "  if type(M33kAurasSaved) == \"table\" then\n"
            "    if type(M33kAurasSaved.displays) == \"table\" then\n"
            "      incoming = 0\n"
            "      for _ in pairs(M33kAurasSaved.displays) do incoming = incoming + 1 end\n"
            "    else\n"
            "      incoming = -1\n"
            "    end\n"
            "  end\n"
            "  M33kAurasSaved = M33kAurasSaved or {}\n"
            "  M33kAurasSaved.foreverLoadDiag = M33kAurasSaved.foreverLoadDiag or {}\n"
            "  local d = M33kAurasSaved.foreverLoadDiag\n"
            "  d[#d + 1] = { t = date(\"%H:%M:%S\"), incoming = incoming }\n"
            "  while #d > 12 do table.remove(d, 1) end\n"
            "end\n")
    if "foreverLoadDiag" in s:
        print("  load-diag: already patched")
    elif anchor in s:
        s = s.replace(anchor, diag + anchor, 1)
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
        print("  load-diag: patched")
    else:
        print("  !! load-diag anchor not found")

patch_load_diag(root)

# --- our fork's slash commands: /ea primary, /everauras spelled out, /wa kept for
#     muscle memory. Applied before the rename, so the upstream name is still M33kAuras. ---
def patch_slash(root):
    p = os.path.join(root, "M33kAuras", "M33kAuras.lua")
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    old = 'SLASH_M33kAuras1, SLASH_M33kAuras2 = "/wa", "/M33kAuras";'
    new = ('SLASH_M33kAuras1, SLASH_M33kAuras2, SLASH_M33kAuras3 = "/ea", "/everauras", "/wa";')
    if 'SLASH_M33kAuras3' in s:
        print("  slash: already patched")
    elif old in s:
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s.replace(old, new, 1))
        print("  slash: patched (/ea, /everauras, /wa)")
    else:
        print("  !! slash anchor not found:", [l for l in s.splitlines() if "SLASH_M33kAuras" in l][:2])

patch_slash(root)

# --- the aura-secrecy version trap: upstream decides whether auras can be secret with
#     select(4, GetBuildInfo()) >= 120100. Forever reports interface 16001 but DOES inherit
#     the 12.1 secrets system, so it fell into the else branch and got the bare
#     AuraUtil.ForEachAura, which throws "Auras cannot be accessed when secret while tainted"
#     the moment a tracked aura goes secret (i.e. any target debuff in combat).
#     Detect the capability instead of comparing build numbers. ---
def patch_auras_locked(root):
    p = os.path.join(root, "M33kAuras", "BuffTrigger2.lua")
    if not os.path.exists(p):
        print("  auras-locked: BuffTrigger2.lua not found"); return
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    old = "local aurasAreLocked = select(4, GetBuildInfo()) >= 120100"
    new = ("-- Forever reports interface 16001 yet inherits the 12.1 secrets system, so ask the\n"
           "-- client whether secrets exist rather than comparing build numbers.\n"
           "local aurasAreLocked = (C_Secrets and C_Secrets.ShouldAurasBeSecret ~= nil)\n"
           "                       or select(4, GetBuildInfo()) >= 120100")
    if "ShouldAurasBeSecret ~= nil" in s:
        print("  auras-locked: already patched")
    elif old in s:
        open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s.replace(old, new, 1))
        print("  auras-locked: patched")
    else:
        print("  !! auras-locked anchor not found")

patch_auras_locked(root)

# --- "Aura(s) Missing" lies while auras are secret. ---
#     C_UnitAuras.GetUnitAuraBySpellID / GetPlayerAuraBySpellID / GetAuraDataBySpellName carry
#     the RequiresNonSecretAura precondition, documented in the client's own apidocs as:
#       "This does not raise a blocked action error - instead, protected APIs will return no values."
#     It is the ONLY precondition in secretpredicatesdocumentation.lua with no FailureMode key.
#     So in combat the scanner gets nil, the match count is 0, and EqualZero happily reports
#     "missing" - telling a rotation helper to re-apply a DoT that is already ticking.
#     A wrong recommendation is worse than no display, so report not-active instead.
#     Measured 2026-09-18: open-world combat alone sets Combat=Active and
#     ShouldAurasBeSecret()=true; GetSpellAuraSecrecy(348 Immolate) = ContextuallySecret.
def patch_missing_is_unknowable(root):
    p = os.path.join(root, "M33kAuras", "BuffTrigger2.lua")
    if not os.path.exists(p):
        print("  missing-unknowable: BuffTrigger2.lua not found"); return
    s = open(p, encoding="utf-8", errors="surrogateescape").read()
    if "CanKnowAuraAbsence" in s:
        print("  missing-unknowable: already patched"); return

    anchor = "local function EqualZero(x)\n  return x == 0\nend\n"
    helper = anchor + """
-- Forever: while aura data is secret the getters answer nil rather than erroring
-- (RequiresNonSecretAura - "protected APIs will return no values"), so a match count of
-- zero means "cannot see" and not "not present". Claiming "missing" then puts a false
-- recommendation on screen, which is worse than showing nothing. Absence is only
-- knowable when every tracked spell id is readable right now.
local secretAbsenceNotified = {}
local function CanKnowAuraAbsence(spellIdStrings)
  if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return true end
  if not C_Secrets.ShouldAurasBeSecret() then return true end
  if not spellIdStrings then return false end   -- name matching cannot work at all while secret
  local checked = false
  for _, s in ipairs(spellIdStrings) do
    local spellId = tonumber(s)
    if spellId then
      checked = true
      if C_Secrets.ShouldSpellAuraBeSecret(spellId) then return false end
    end
  end
  return checked
end

local function MakeMissingCountFunc(trigger, id)
  local spellIds = trigger.useExactSpellId and trigger.auraspellids or nil
  return function(x)
    if not CanKnowAuraAbsence(spellIds) then
      if not secretAbsenceNotified[id] then
        secretAbsenceNotified[id] = true
        M33kAuras.prettyPrint(("\\"%s\\": the client keeps this aura secret during combat, so \\"Aura(s) Missing\\" cannot be answered. Hiding it instead of reporting a match that may be false."):format(tostring(id)))
      end
      return false
    end
    return x == 0
  end
end
"""
    old_use = ("        if trigger.matchesShowOn == \"showOnMissing\" then\n"
               "          matchCountFunc = EqualZero")
    new_use = ("        if trigger.matchesShowOn == \"showOnMissing\" then\n"
               "          matchCountFunc = MakeMissingCountFunc(trigger, id)")
    n = 0
    if anchor in s:
        s = s.replace(anchor, helper, 1); n += 1
    else:
        print("  !! missing-unknowable: EqualZero anchor not found"); return
    if old_use in s:
        s = s.replace(old_use, new_use, 1); n += 1
    else:
        print("  !! missing-unknowable: showOnMissing anchor not found"); return
    open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s)
    print(f"  missing-unknowable: {n} patch(es) applied")

patch_missing_is_unknowable(root)

# --- WoW: Forever engine-driven Icon displays (Blizzard_AuraContainer / CustomAuraContainerTemplate). ---
#     Proven in game 2026-09-18: a tainted addon may configure an engine-drawn aura button that keeps
#     rendering (icon, swipe, duration, count) while auras are secret in combat, and can never read it
#     back. The hunks live in engine_hunks.py (shared with apply_engine_to_installed.py).
#     HARD-FAILS on a missing anchor or file: patch() only prints, and a build without the TOC line
#     would install a silently inert feature.
import shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from engine_hunks import BUFFTRIGGER2_HUNKS, PROTOTYPES_HUNKS, OPTIONS_HUNKS, TOC_HUNKS, NEW_FILES, CHECKS
FILES_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "forever_files")

def install_engine_aura(root):
    for src_name, rel in NEW_FILES:
        src = os.path.join(FILES_SRC, src_name)
        if not os.path.exists(src):
            print("  !! engine-aura: missing", src); sys.exit(1)
        shutil.copyfile(src, os.path.join(root, rel))
    patch("M33kAuras/BuffTrigger2.lua", BUFFTRIGGER2_HUNKS)
    patch("M33kAuras/Prototypes.lua", PROTOTYPES_HUNKS)
    for rel, hunks in OPTIONS_HUNKS.items():
        patch(rel, hunks)
    for rel, old, new in TOC_HUNKS:
        patch(rel, [(old, new)])
    for rel, markers in CHECKS.items():
        s = open(os.path.join(root, rel), encoding="utf-8", errors="surrogateescape").read()
        for m in markers:
            if m not in s:
                print("  !! engine-aura: marker missing in", rel, ":", m.strip()); sys.exit(1)
    print("  engine-aura: installed")

install_engine_aura(root)

# --- branding artwork: the EverAuras badge (logo/build/*.tga, rendered from logo/EVERAURAS.jpg)
#     replaces upstream's logo files by name, and the addon-list icon switches from the
#     upstream BLP to our TGA (WoW accepts TGA for ## IconTexture). HARD-FAILS if the art is missing.
def install_branding(root):
    art = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logo", "build")
    dst = os.path.join(root, "M33kAuras", "Media", "Textures")
    if not os.path.isdir(art) or not os.path.isdir(dst):
        print("  !! branding: missing", art if not os.path.isdir(art) else dst); sys.exit(1)
    n = 0
    for name in ("logo_256_round.tga", "logo_256.tga", "logo_64.tga", "logo_64_nobg.tga", "icon.tga"):
        src = os.path.join(art, name)
        if not os.path.exists(src):
            print("  !! branding: missing", src); sys.exit(1)
        shutil.copyfile(src, os.path.join(dst, name)); n += 1
    toc = os.path.join(root, "M33kAuras", "M33kAuras.toc")
    t = open(toc, encoding="utf-8", errors="surrogateescape").read()
    old = "## IconTexture: Interface" + chr(92) + "AddOns" + chr(92) + "M33kAuras" + chr(92) + "Media" + chr(92) + "Textures" + chr(92) + "icon.blp"
    new = old[:-3] + "tga"
    if old in t:
        open(toc, "w", encoding="utf-8", errors="surrogateescape", newline="").write(t.replace(old, new, 1))
    elif new not in t:
        print("  !! branding: IconTexture line not found in", toc); sys.exit(1)
    print("  branding: %d textures installed, IconTexture -> icon.tga" % n)

install_branding(root)
