"""Forever-specific patches for the M33kAuras hybrid build. Idempotent: safe to re-run.
Usage: python forever_patches.py <AddOns dir>
Why: the fork's IsRetail() is BuildInfo >= 120000, false on Forever (16001), so several
API-selection sites fall into the Classic path and call removed globals (UnitAura etc.)."""
import os, sys
root = sys.argv[1]
if not os.path.isdir(os.path.join(root, "M33kAuras")):
    print("  (build already renamed to EverAuras - patches belong before the rename, skipping)")
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

# Upstream (since 1a002cf / c30886a / 0a8bed9) handles the rest itself on Forever: modern aura scanning,
# weapon-enchant updates and LibSpecialization's Forever specs. FixDebuffClass stays on upstream's branch,
# which reads an empty dispel type as Enrage. This one is still needed (dormant upstream code):
patch("M33kAuras/BuffTrigger2.lua", [
    ("  if " + R + " then\n    -- TODO change this when more events are handled by system",
     "  if " + RF + " then\n    -- TODO change this when more events are handled by system"),
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
    if add in s or "M33kAurasSaved.migrationDisabled = true" in s:   # (engine_hunks' Init.lua hunk replaces it)
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

# --- options footer: the EverAuras Discord button, leftmost. Upstream dropped its Discord button in
#     0cd4f76 (our rename used to point it at our server); the Documentation button moves right of it. ---
patch("M33kAurasOptions/OptionsFrames/OptionsFrame.lua", [
    ('  local documentationButton = addFooter(L["Documentation"], [[Interface\\AddOns\\M33kAuras\\Media\\Textures\\GitHub.tga]], "https://github.com/m33shoq/M33kAuras/wiki",\n'
     '            L["Check out our wiki for a large collection of examples and snippets."])\n'
     '  documentationButton:SetParent(tipFrame)\n'
     '  documentationButton:SetPoint("LEFT", tipFrame, "LEFT")\n',
     '  -- Forever: the EverAuras Discord, leftmost (upstream dropped its own Discord button in 0cd4f76)\n'
     '  local discordButton = addFooter(L["Discord"], [[Interface\\AddOns\\M33kAuras\\Media\\Textures\\discord.tga]], "https://discord.gg/HdRNYvKbY",\n'
     '            L["Chat with M33kAuras experts on our Discord server."])\n'
     '  discordButton:SetParent(tipFrame)\n'
     '  discordButton:SetPoint("LEFT", tipFrame, "LEFT")\n'
     '\n'
     '  local documentationButton = addFooter(L["Documentation"], [[Interface\\AddOns\\M33kAuras\\Media\\Textures\\GitHub.tga]], "https://github.com/m33shoq/M33kAuras/wiki",\n'
     '            L["Check out our wiki for a large collection of examples and snippets."])\n'
     '  documentationButton:SetParent(tipFrame)\n'
     '  documentationButton:SetPoint("LEFT", discordButton, "RIGHT", footerSpacing, 0)\n'),
])

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
-- knowable when every tracked spell id is readable right now. Names never are:
-- GetAuraDataBySpellName answers nil both for "absent" and for "secret".
local secretAbsenceNotified = {}
local missingCountFuncs = setmetatable({}, { __mode = "k" })   -- matchCountFunc -> true (single-unit Missing)
local function CanKnowAuraAbsence(spellIdStrings, byName)
  if not (C_Secrets and C_Secrets.ShouldAurasBeSecret) then return true end
  if not C_Secrets.ShouldAurasBeSecret() then return true end
  if byName or not spellIdStrings then return false end
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
  local byName = false
  if trigger.useName and type(trigger.auranames) == "table" then
    for _, n in ipairs(trigger.auranames) do
      if n ~= "" then byName = true; break end
    end
  end
  local fn = function(x)
    if not CanKnowAuraAbsence(spellIds, byName) then
      if not secretAbsenceNotified[id] then
        secretAbsenceNotified[id] = true
        M33kAuras.prettyPrint(("\\"%s\\": the client keeps this aura secret during combat, so \\"Aura(s) Missing\\" cannot be answered. Hiding it instead of reporting a match that may be false."):format(tostring(id)))
      end
      return false
    end
    return x == 0
  end
  missingCountFuncs[fn] = true
  return fn
end

-- Forever: no scan touches a Missing trigger whose aura is absent or unseen, so nothing re-asks it
-- when secrecy flips. Re-ask both ways: when auras turn secret (a "missing" shown before combat
-- would stay up after the aura lands unseen) and when they turn readable again (a display hidden
-- in combat would stay hidden; rescan first, auras applied while secret were never recorded).
if Private.callbacks then
  Private.callbacks:RegisterCallback("WA_SECRET_STATE_UPDATE", function()
    local readable = not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret())
    local time = GetTime()
    local rescanned = {}
    for id, infos in pairs(triggerInfos) do
      if M33kAuras.IsAuraLoaded(id) then
        for triggernum, info in pairs(infos) do
          if info.matchCountFunc and missingCountFuncs[info.matchCountFunc] then
            if readable and info.unit and not rescanned[info.unit] then
              rescanned[info.unit] = true
              ScanUnit(time, info.unit)
            end
            matchDataChanged[id] = matchDataChanged[id] or {}
            matchDataChanged[id][triggernum] = true
          end
        end
      end
    end
  end)
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
from engine_hunks import BUFFTRIGGER2_HUNKS, PROTOTYPES_HUNKS, OPTIONS_HUNKS, CORE_HUNKS, TOC_HUNKS, NEW_FILES, CHECKS
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
    for rel, hunks in CORE_HUNKS.items():
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
    # every other use of upstream's icon: the addon compartment (on Forever since 369287a), the minimap
    # button, the options footer's "About" button, aura rows without an icon, the other TOCs
    import re
    icon_re = re.compile(r"(Media(?:\\\\|\\)Textures(?:\\\\|\\))icon\.blp")
    refs = 0
    for dp, dn, fn in os.walk(root):
        if "Libs" in dp.split(os.sep):
            continue
        for f in fn:
            if not f.endswith((".lua", ".toc")):
                continue
            p = os.path.join(dp, f)
            s = open(p, encoding="utf-8", errors="surrogateescape").read()
            s2, k = icon_re.subn(r"\1icon.tga", s)
            if k:
                open(p, "w", encoding="utf-8", errors="surrogateescape", newline="").write(s2)
                refs += k
    print("  branding: %d textures installed, IconTexture -> icon.tga, %d more icon references" % (n, refs))

install_branding(root)
