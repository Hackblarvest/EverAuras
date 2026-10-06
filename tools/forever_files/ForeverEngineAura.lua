-- ForeverEngineAura.lua - WoW: Forever.
--
-- Icon and Progress Bar displays with Aura triggers are rendered by Blizzard_AuraContainer
-- (CustomAuraContainerTemplate), so they keep working while auras are secret in combat.
-- The addon never reads aura state. Every inbound call is a secure delegate; the engine writes
-- secret values into regions we hand over and marks them unreadable. Proven in game 2026-09-18.
--
-- Two display modes, both correct by construction:
--   Found / Always : an aura SLOT. The engine draws the live aura (icon, swipe, duration, count)
--                    on a button that covers the WA region while the aura is present.
--   Missing        : an aura GROUP with maxFrameCount 1. The engine sizes the container to a
--                    SECRET width - 1 px while the aura is absent, W+1 px while present. A
--                    clipping frame is anchored from the container's right edge to the region's
--                    right edge, so it is full width while absent and zero width while present.
--                    The "cast this" icon lives inside it. Present = clipped away = nothing drawn.
--                    Pure geometry driven by a value we cannot read.
--
-- Progress Bars (Show On: Found) are engine-driven too: the slot button carries its own StatusBar that
-- Blizzard fills with the aura's duration (SetDurationBar), plus icon, name, timer and stack texts.
-- Progress Textures (Show On: Found): straight ones ride on the same StatusBar, kept invisible: a clipping
-- frame anchored to its fill reveals a copy of the display's texture as the aura runs out. Circular
-- ones are the game's cooldown swipe drawn with the display's texture. Texture displays (Show On: Found
-- or Missing) are icons without a timer: a copy of their texture on the slot button or in the Missing clip.
-- Text displays: plain text the same way, or exactly %p / %s / %n as the engine's own texts (Found).
-- Dynamic Groups whose children are all engine-driven Found displays are packed by the game: a chain of
-- containers sized by the children's auras places them (see "dynamic groups" below).
--
-- Time left (icons): 'Remaining Time' on a Found trigger becomes a slot whose duration text is the
-- display's icon, coloured by a Step curve over the remaining duration (alpha 0 outside the range).
-- Composite displays combine one Missing trigger with Found + Remaining Time triggers through 'Any
-- Triggered' or a custom combination of the form (other triggers) and (any Aura trigger), the common
-- "cast it when it is missing or about to run out" aura.
--
-- Other triggers ("gates") may sit next to the Aura trigger(s): delegated Aura triggers report a
-- constant true to WeakAuras, which keeps evaluating the gates itself (plain data in combat).
--
-- Glow: an animated glow (ForeverGlow.lua, the WA glow's own settings) on a frame of ours inside the clip
-- that follows the aura part (Missing clip; a mirrored Found clip from a second container). Time-left
-- parts draw a static glow as curve-driven text.
--
-- Triggers may use spell NAMES: they resolve to every known rank's id (classic ranks are separate
-- spells) and follow the spellbook as you level. Exact ids stay exact.
--
-- Range gate (per display): 'Only while the spell is in range of the unit' hides the display unless
-- C_Spell.IsSpellInRange says the spell can reach the unit. That call answers with a plain boolean on
-- Forever, in combat too (probe 2026-09-19), and honours the spell's own min/max range.
--
-- Brand-free on purpose: works in the upstream tree and after the rename step.
---@type string
local AddonName = ...
---@class Private
local Private = select(2, ...)
local WA = _G[AddonName]
if not WA or not WA.IsLibsOK or not WA.IsLibsOK() then return end
local L = WA.L
local LSM = LibStub("LibSharedMedia-3.0")

local function T(s) return (L and L[s]) or s end

local Engine = {}
Private.ForeverEngine = Engine

local KEY = "fe"
local WARN = "forever_engine"
local UNIT_OK = { player = true, target = true, focus = true, pet = true }
local MODE = { showOnActive = "active", showOnMissing = "missing", showAlways = "always" }
local UNSUPPORTED = {
  "useNamePattern", "useIgnoreName", "useIgnoreExactSpellId",
  "useTotal", "use_tooltip", "fetchTooltip", "use_unitName", "use_npcId",
  "useAffected", "showClones", "useGroup_count",
}

-- Aura properties Blizzard's containers filter on for EVERY aura (not identity filters, so the rule that
-- keeps addons from picking debuffs on friendly units by spell does not apply to them). WeakAuras' Debuff
-- Type classes -> the aura's dispelName; Enrage has been reported both as "Enrage" and as "".
local DISPEL_NAMES = { magic = { "Magic" }, curse = { "Curse" }, disease = { "Disease" }, poison = { "Poison" },
                       enrage = { "Enrage", "" }, bleed = { "Bleed" } }
local PROPERTY_FLAGS = { { "use_stealable", "isStealable" }, { "use_isBossDebuff", "isBossAura" },
                         { "use_castByPlayer", "isFromPlayerOrPlayerPet" } }

local attachments = setmetatable({}, { __mode = "k" })   -- region -> att
-- read by the dev probes (ForeverDevInfo /fdtext); nothing in the addon uses it
if type(WA) == "table" then
  WA.ForeverEngineDebug = function(region) if region == nil then return attachments end return attachments[region] end
end
local pending = setmetatable({}, { __mode = "k" })       -- region -> true
local decided = {}                                       -- uid -> plan | false (written by the trigger side)
local nameWatch = {}                                     -- uid -> true for aura2 triggers written with spell NAMES
local readd = {}                                         -- uid -> true: re-add when safe (spell learned, eligibility changed)
local available                                          -- nil = not probed yet
local FlushReadds                                        -- defined after Apply

local function SV() return _G[AddonName .. "Saved"] end
local function GloballyEnabled()
  local sv = SV()
  return not (sv and sv.foreverEngine and sv.foreverEngine.disabled)
end

function Engine.IsSafe()
  if InCombatLockdown() then return false end
  if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return false end
  return true
end

function Engine.IsAvailable()
  if available ~= nil then return available end
  if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
    if C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then return false end -- not cached: retry later
  end
  local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
  available = (ok and c ~= nil and type(c.AddAuraSlot) == "function" and type(c.AddAuraGroup) == "function"
               and type(c.SetUnit) == "function") or false
  if ok and c then c:Hide() end
  return available
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

---------------------------------------------------------------------------- secret duration text
-- %p on a secret remaining time: upstream falls back to string.format("%.1f") on the secret number,
-- which renders as "114.5" in combat. The engine can format the duration object itself ("1m 54s",
-- "2.5s"). Prototypes.lua's dynamic_texts.p.func asks here for a SecondsFormatter matching the WA
-- progress precision: 0 = whole seconds, 1-3 = always decimals, 4-6 = decimals under 3 s.
-- Cooldown countdown numbers round UP (36.4 s left -> "37") while Blizzard's buff frame rounds DOWN
-- ("36 s"), so an aura icon and the buff it mirrors disagree by one for most of every second. Aura icons
-- get a countdown formatter that counts like the buff frame: whole seconds rounded down, minutes and
-- hours rounded up past 90 s / 90 min like Blizzard's aura text (Blizzard_AuraContainerShared.lua).
-- Measured 2026-09-28 (ForeverDevInfo /fdcount). Spell cooldown icons keep the default, which counts
-- like the action bar.
local auraCountdownFormatter
function Private.ForeverAuraCountdownFormatter()
  if auraCountdownFormatter ~= nil then return auraCountdownFormatter or nil end
  auraCountdownFormatter = false
  if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
  local R = (Enum and Enum.NumericRuleFormatRounding) or {}
  local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
  if not ok or not f then return nil end
  local okB = pcall(f.SetBreakpoints, f, {
    { threshold = 0, step = 1, rounding = R.Down or 2, format = "%d" },
    { threshold = 90.5, format = "%dm", components = { { div = 60, step = 1, rounding = R.Up or 1 } } },
    { threshold = 5400.5, format = "%dh", components = { { div = 3600, step = 1, rounding = R.Up or 1 } } },
    { threshold = 129600.5, format = "%dd", components = { { div = 86400, step = 1, rounding = R.Up or 1 } } },
  })
  if okB then auraCountdownFormatter = f end
  return auraCountdownFormatter or nil
end

-- A display whose triggers are all Aura triggers shows a buff or debuff: its countdown follows the
-- buff frame. Anything else (cooldowns, mixed) keeps the default countdown.
local function IsAuraOnlyDisplay(data)
  local n = 0
  for _, tr in ipairs(data and data.triggers or {}) do
    local t = tr and tr.trigger
    if not (t and t.type == "aura2") then return false end
    n = n + 1
  end
  return n > 0
end

local secretFormatters = {}
function Private.SecretDurationFormatter(precision)
  precision = tonumber(precision) or 1
  local threshold = 0
  if precision >= 4 then threshold = 3
  elseif precision >= 1 then threshold = 1e9 end
  local fmt = secretFormatters[threshold]
  if fmt then return fmt end
  if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then return nil end
  local ok, f = pcall(C_StringUtil.CreateSecondsFormatter)
  if not ok or not f then return nil end
  local E = Enum or {}
  pcall(f.SetDefaultAbbreviation, f, E.SecondsFormatterAbbreviation and E.SecondsFormatterAbbreviation.OneLetter or 2)
  pcall(f.SetDesiredUnitCount, f, 2)
  pcall(f.SetRounding, f, E.SecondsFormatterRounding and E.SecondsFormatterRounding.Truncate or 1)
  pcall(f.SetStripIntervalWhitespace, f, E.SecondsFormatterIntervalWhitespace and E.SecondsFormatterIntervalWhitespace.Strip or 1)
  pcall(f.SetMillisecondsThreshold, f, threshold)
  secretFormatters[threshold] = f
  return fmt or f
end

---------------------------------------------------------------------------- spellbook (rank-aware names)
-- Classic-era spells have one spell id PER RANK, and a new rank is a new aura id on the target.
-- A trigger written with a spell NAME is resolved here to every id of that name the player
-- knows (all known ranks, so downranked casts match too) and re-resolved whenever the spellbook
-- changes. Names and ids from the spellbook are plain data.
local spellbookGen = 0
local spellbookMap = nil         -- lower(name) -> { [spellID] = true }, castable spells only
local watchNames = {}            -- lower(name) -> true, every name any aura2 trigger uses
local spellbookWarned = false

-- Auras SEEN on a unit while auras were plain (out of combat), persisted per account:
-- lower(name) -> { [auraSpellId] = true }. Needed because many classic buffs carry a different id
-- than the castable spell (Bloodrage 2687 -> buff 29131, Last Stand, Vanish, procs), and the engine
-- filters by exact aura id. Hostile DoTs are the exception: their aura id is the cast id.
local function Learned()
  local sv = SV()
  if not sv then return nil end
  sv.foreverEngine = sv.foreverEngine or {}
  sv.foreverEngine.learned = sv.foreverEngine.learned or {}
  return sv.foreverEngine.learned
end

local function RefreshSpellbook()
  local map = {}
  local ok, err = pcall(function()
    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local IT = Enum.SpellBookItemType or {}
    local SPELL, FUTURE = IT.Spell or 1, IT.FutureSpell or 2
    for i = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
      local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
      if line then
        for j = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do
          local info = C_SpellBook.GetSpellBookItemInfo(j, bank)
          -- passives (talents that share a proc buff's name) and off-spec entries are never the aura
          if info and not info.isPassive and not info.isOffSpec
             and (info.itemType == SPELL or info.itemType == FUTURE) then
            local id, name = info.spellID, info.name
            if id and name and not issecretvalue(id) and not issecretvalue(name) then
              local key = name:lower()
              map[key] = map[key] or {}
              map[key][id] = true
            end
          end
        end
      end
    end
  end)
  if not ok then
    if not spellbookWarned then
      spellbookWarned = true
      WA.prettyPrint("engine: spellbook scan failed: " .. tostring(err))
    end
    spellbookMap = nil        -- never trust a partial map; the next resolve retries
    return
  end
  spellbookMap = map
end

-- Adds every id an aura-name entry stands for into `into`.
-- Returns found (anything at all), seen (at least one id came from a real aura sighting).
local ResolveAuraName
ResolveAuraName = function(entry, into, nameMode)
  local n = tonumber(entry)
  if n then
    into[n] = true
    -- The options panel canonicalises a typed name to ONE spell id. In name mode that id stands for
    -- the spell, not the rank: pull in every rank of the same name too.
    if nameMode and C_Spell and C_Spell.GetSpellName then
      local ok, nm = pcall(C_Spell.GetSpellName, n)
      if ok and type(nm) == "string" and nm ~= "" and not issecretvalue(nm) then
        ResolveAuraName(nm, into, false)
      end
    end
    return true, true
  end
  if type(entry) ~= "string" or entry == "" then return false, false end
  if not spellbookMap then RefreshSpellbook() end
  local key, found, seen = entry:lower(), false, false
  local ids = spellbookMap and spellbookMap[key]
  if ids then
    for id in pairs(ids) do into[id] = true; found = true end
  end
  local learned = Learned()
  learned = learned and learned[key]
  if learned then
    for id in pairs(learned) do into[id] = true; found = true; seen = true end
  end
  if not found and C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, entry)
    local id = ok and type(info) == "table" and info.spellID
    if id and not issecretvalue(id) and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(id)) then
      into[id] = true; found = true
    end
  end
  return found, seen
end

---------------------------------------------------------------------------- eligibility
-- 'Remaining Time' filters the engine can draw without reading the time: the game evaluates a Step colour
-- curve over the aura's remaining duration itself (see RemainCurve). WeakAuras applies the filter to
-- 'Show On: Aura(s) Found' only (CanHaveMatchCheck); its default operator is ">=".
local REM_OPS = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true }

-- Stack Count (useStacks): WA compares the aura's stacks (its applications, 0 for an aura that does not
-- stack) with a number, on Found triggers only (BuffTrigger2 CanHaveMatchCheck). In whole stacks: at
-- least ge and/or at most le. false = always true (no gate); nil, why = cannot be drawn.
do
  local MAX_STACKS = 100
  function Engine.StackRange(t)
    local op, x = t.stacksOperator or ">=", tonumber(t.stacks) or 0
    local ge, le
    if op == ">=" then ge = math.ceil(x)
    elseif op == ">" then ge = math.floor(x) + 1
    elseif op == "<=" then le = math.floor(x)
    elseif op == "<" then le = math.ceil(x) - 1
    elseif op == "==" then
      if x ~= math.floor(x) then return nil, T("'Stack Count' = %s never matches whole stacks"):format(tostring(x)) end
      ge, le = x, x
    else
      return nil, T("'Stack Count' with != cannot be expressed by the engine (use < or >)")
    end
    if ge and ge <= 0 then ge = nil end          -- every aura has at least 0 stacks
    if le and le < 0 then return nil, T("'Stack Count' below 0 never matches") end
    if (ge and ge > MAX_STACKS) or (le and le >= MAX_STACKS) then
      return nil, T("'Stack Count' above %d stacks cannot be expressed by the engine"):format(MAX_STACKS)
    end
    if not ge and not le then return false end
    return { ge = ge, le = le, key = ("%s-%s"):format(tostring(ge or ""), tostring(le or "")) }
  end
end

-- One aura2 trigger -> its part of the plan. Reasons it cannot be drawn go through no().
-- Blizzard's aura containers refuse to pick auras by spell id where that could single out an encounter
-- debuff (Blizzard_AuraContainerUtil.lua, CanApplyIdentityCandidateFilters): debuffs on friendly units
-- (you, your pet, a friendly target) and buffs on hostile units, unless the spell is never secret.
-- Player and pet are always friendly; target and focus depend on who is targeted.
local function NeverSecret(ids)
  if not (C_Secrets and C_Secrets.GetSpellAuraSecrecy and Enum.SecrecyLevel) then return false end
  if #ids == 0 then return false end
  for _, id in ipairs(ids) do
    local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, id)
    if not ok or level ~= Enum.SecrecyLevel.NeverSecret then return false end
  end
  return true
end

-- Fingerprints of debuffs seen on you while auras were plain: spellId -> { duration, dispel, flags }.
-- Blizzard's containers may not filter debuffs on you by spell, but they may filter by these properties
-- (Blizzard_AuraContainerUtil.lua, DoesAuraPassCandidateFilters), so a debuff is matched by all of them.
local FP_FLAGS = { "canApplyAura", "isStealable", "isBossAura", "nameplateShowAll", "nameplateShowPersonal",
                   "isFromPlayerOrPlayerPet" }

local function Fingerprints()
  local sv = SV()
  if not sv then return nil end
  sv.foreverEngine = sv.foreverEngine or {}
  sv.foreverEngine.fingerprints = sv.foreverEngine.fingerprints or {}
  return sv.foreverEngine.fingerprints
end

-- Every aura with a dispel type (or stealable) EverAuras could read while auras were plain, on any unit
-- it can read, plus the untyped debuffs on you: spellId -> { k = "HARMFUL" | "HELPFUL", d = dispelName
-- or "", s = isStealable, b = isBossAura, pp / np = seen cast by a player / by a non-player, m = seen
-- cast by you, t = last seen }. Property-based displays take their sound spell ids from here: the game
-- plays aura sounds by spell id only.
local MAX_SEEN_TOTAL, MAX_SOUND_IDS = 3000, 5000
local seenCount
local seenVersion = 0   -- bumped whenever the memory learns something; invalidates cached id lists
local function AuraSeen()
  local sv = SV()
  if not sv then return nil end
  sv.foreverEngine = sv.foreverEngine or {}
  local fe = sv.foreverEngine
  if not fe.auraSeen then
    fe.auraSeen = {}
    -- development builds kept one list per display ("HARMFUL;t=Poison" -> ids): fold them in
    for key, set in pairs(fe.propertySeen or {}) do
      local filter, dn = tostring(key):match("^(%u+)"), tostring(key):match("t=(%a+)")
      if filter and type(set) == "table" then
        for id in pairs(set) do
          if type(id) == "number" then fe.auraSeen[id] = { k = filter, d = dn or "", t = 0 } end
        end
      end
    end
    fe.propertySeen = nil
  end
  if not seenCount then
    seenCount = 0
    for _ in pairs(fe.auraSeen) do seenCount = seenCount + 1 end
  end
  return fe.auraSeen
end

-- Would the game's candidate filters pass an aura remembered as e?
local function SeenMatches(e, cand)
  if not cand then return true end
  local dn = (e.d ~= nil and e.d ~= "") and e.d or nil
  if cand.includeDispelTypes and not (dn and cand.includeDispelTypes[dn]) then return false end
  if cand.excludeDispelTypes and dn and cand.excludeDispelTypes[dn] then return false end
  if cand.isStealable ~= nil and (e.s == true) ~= cand.isStealable then return false end
  if cand.isBossAura ~= nil and (e.b == true) ~= cand.isBossAura then return false end
  if cand.isFromPlayerOrPlayerPet == true and not e.pp then return false end
  if cand.isFromPlayerOrPlayerPet == false and not e.np then return false end
  return true
end

-- The candidate filters a plan hands to the game (composites: the part that draws the aura).
local function PlanCandidate(plan)
  if plan.candidate then return plan.candidate end
  local p = plan.parts
  local part = p and (p.found or p.missing or (p.remaining[1] and p.remaining[1].part))
  return part and part.candidate
end

-- The game's own spell tables per dispel type (ForeverDispelData.lua, generated from the client's
-- SpellCategories / SpellEffect tables): a "Poison debuff on you" display has its sounds from the first
-- poison on, without learning. Only for plans whose filters are dispel types alone: the tables know
-- nothing about stealable, boss auras, who cast it or 'Own Only'.
local DATA_TYPE = { Magic = "Magic", Curse = "Curse", Disease = "Disease", Poison = "Poison", Enrage = "Enrage", [""] = "Enrage" }
local ALL_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Enrage = true }
local function TableLists(plan, cand)
  local data = Private.ForeverDispelData
  local kinds = data and data[plan.filter]
  if not (kinds and cand) then return nil end
  if (plan.filterString or ""):find("PLAYER", 1, true) then return nil end
  for k in pairs(cand) do
    if k ~= "includeDispelTypes" then return nil end
  end
  local lists, used = {}, {}
  for dn in pairs(cand.includeDispelTypes or ALL_TYPES) do
    local key = DATA_TYPE[dn]
    if key and not used[key] and kinds[key] then used[key] = true; lists[#lists + 1] = kinds[key] end
  end
  return lists
end

-- The spell ids a property-based plan's sounds are registered for: the game's tables plus the learned
-- memory, sorted. Returns ids, how many, how many came from the tables, and a checksum. Cached per plan
-- until the memory learns something: the status line asks on every update.
local idCache = setmetatable({}, { __mode = "k" })
local function SeenIds(plan)
  local c = idCache[plan]
  if c and c.v == seenVersion then return c.ids, #c.ids, c.fromTables, c.sum end
  local set, ids, fromTables = {}, {}, 0
  local cand = PlanCandidate(plan)
  for _, list in ipairs(TableLists(plan, cand) or {}) do
    for _, id in ipairs(list) do
      if not set[id] then set[id] = true; ids[#ids + 1] = id; fromTables = fromTables + 1 end
    end
  end
  local seen = AuraSeen()
  if seen then
    local own = (plan.filterString or ""):find("PLAYER", 1, true) ~= nil
    for id, e in pairs(seen) do
      if #ids >= MAX_SOUND_IDS then break end
      if not set[id] and e.k == plan.filter and (not own or e.m) and SeenMatches(e, cand) then
        set[id] = true
        ids[#ids + 1] = id
      end
    end
  end
  table.sort(ids)
  local sum = 0
  for i, id in ipairs(ids) do sum = (sum + id * (i % 7 + 1)) % 2147483647 end
  idCache[plan] = { v = seenVersion, ids = ids, fromTables = fromTables, sum = sum }
  return ids, #ids, fromTables, sum
end

-- Remember one plain aura; true when that changes which displays it matches.
local function RecordAura(seen, a, filter, unit)
  local id, dn = a.spellId, a.dispelName
  if type(id) ~= "number" or issecretvalue(id) or issecretvalue(dn) then return false end
  local st = a.isStealable
  if issecretvalue(st) then st = nil end
  local typed = type(dn) == "string" and dn ~= ""
  if not typed and st ~= true and not (unit == "player" and filter == "HARMFUL") then return false end
  local e = seen[id]
  local changed = false
  if not e then
    if seenCount >= MAX_SEEN_TOTAL then return false end
    e, changed = {}, true
    seen[id] = e
    seenCount = seenCount + 1
  end
  local function set(k, v) if e[k] ~= v then e[k] = v; changed = true end end
  set("k", filter)
  set("d", typed and dn or "")
  if type(st) == "boolean" then set("s", st) end
  local b = a.isBossAura
  if type(b) == "boolean" and not issecretvalue(b) then set("b", b) end
  local p = a.isFromPlayerOrPlayerPet
  if type(p) == "boolean" and not issecretvalue(p) then
    if p then set("pp", true) else set("np", true) end
  end
  local src = a.sourceUnit
  if type(src) == "string" and not issecretvalue(src) and (src == "player" or src == "pet" or src == "vehicle") then
    set("m", true)
  end
  e.t = time and time() or 0   -- recency only: no re-registration for it
  if changed then seenVersion = seenVersion + 1 end
  return changed
end

-- One fingerprint for a set of ids (the ranks of a spell): the longest duration, and every other
-- property only where all known ranks agree. nil when none of them has been seen yet.
local function FingerprintOf(ids)
  local all = Fingerprints()
  if not all then return nil end
  local out, seen = { flags = {} }, 0
  for _, id in ipairs(ids) do
    local fp = all[id]
    if type(fp) == "table" then
      seen = seen + 1
      out.duration = math.max(out.duration or 0, tonumber(fp.duration) or 0)
      if seen == 1 then
        out.dispel = fp.dispel
        for _, k in ipairs(FP_FLAGS) do out.flags[k] = fp[k] end
      else
        if out.dispel ~= fp.dispel then out.dispel = nil end
        for _, k in ipairs(FP_FLAGS) do if out.flags[k] ~= fp[k] then out.flags[k] = nil end end
      end
    end
  end
  return seen > 0 and out or nil
end

local durWatch = {}   -- uid -> true: a display waiting for a debuff's fingerprint (re-added once seen)
local fpUsers = {}    -- uid -> true: displays that match debuffs on you by fingerprint
local lateUsers = {}  -- uid -> true: time-left displays that want the aura's total duration (late clip)

-- A spell's aura duration from its description ("... over 15 sec", "for 12 sec", "lasts 30 sec",
-- "18 sec." at the end): the only source for a DoT you have never seen out of combat, since casting it
-- starts the fight. Plain data; cached per id. nil when the description has no duration.
local descDurations = {}
local DESC_PATTERNS = {
  "over (%d+%.?%d*) sec", "for (%d+%.?%d*) sec", "lasts (%d+%.?%d*) sec", "lasting (%d+%.?%d*) sec",
  "within (%d+%.?%d*) sec", "next (%d+%.?%d*) sec", "over (%d+%.?%d*) min", "for (%d+%.?%d*) min",
}
local function DescribedDuration(id)
  local cached = descDurations[id]
  if cached ~= nil then return cached or nil end
  descDurations[id] = false
  if not (C_Spell and C_Spell.GetSpellDescription) then return nil end
  local ok, desc = pcall(C_Spell.GetSpellDescription, id)
  if not ok or type(desc) ~= "string" or issecretvalue(desc) or desc == "" then return nil end
  local best
  for _, pat in ipairs(DESC_PATTERNS) do
    for n in desc:gmatch(pat) do
      local v = tonumber(n)
      if v and pat:find("min") then v = v * 60 end
      if v and v > 0 and v > (best or 0) then best = v end
    end
  end
  if best then descDurations[id] = best end
  return best
end

-- The longest known total duration of a set of ids: from a plain sighting (fingerprints, 0.1 s steps,
-- every unit's auras feed them) or, failing that, from the spell descriptions.
local function LearnedDuration(ids)
  local all = Fingerprints()
  local best
  for _, id in ipairs(ids) do
    local fp = all and all[id]
    local d = type(fp) == "table" and tonumber(fp.duration)
    if d and d > 0 and d > (best or 0) then best = d end
  end
  if best then return best end
  for _, id in ipairs(ids) do
    local d = DescribedDuration(id)
    if d and d > (best or 0) then best = d end
  end
  return best
end

-- The candidate filters for WeakAuras' property options of trigger t, or nil; plus a key and a
-- description for the status line.
local function PropertyFilters(t, no)
  local cf, keys, words = {}, {}, {}
  if t.use_debuffClass and type(t.debuffClass) == "table" then
    local inc, names, none = {}, {}, false
    for class, on in pairs(t.debuffClass) do
      if on then
        if class == "none" then
          none = true
        elseif DISPEL_NAMES[class] then
          for _, dn in ipairs(DISPEL_NAMES[class]) do inc[dn] = true end
          names[#names + 1] = DISPEL_NAMES[class][1]
        else
          no(T("Debuff Type '%s' cannot be expressed by the engine"):format(tostring(class)))
        end
      end
    end
    table.sort(names)
    if none and #names > 0 then
      no(T("Debuff Type 'None' together with other types cannot be expressed by the engine"))
    elseif none then
      cf.excludeDispelTypes = {}
      for _, list in pairs(DISPEL_NAMES) do
        for _, dn in ipairs(list) do cf.excludeDispelTypes[dn] = true end
      end
      keys[#keys + 1] = "t=none"
      words[#words + 1] = T("without a dispel type")
    elseif #names > 0 then
      cf.includeDispelTypes = inc
      keys[#keys + 1] = "t=" .. table.concat(names, "+")
      words[#words + 1] = T("of type %s"):format(table.concat(names, T(" or ")))
    end
  end
  local FLAG_WORDS = {
    isStealable = { T("stealable"), T("not stealable") },
    isBossAura = { T("a boss aura"), T("not a boss aura") },
    isFromPlayerOrPlayerPet = { T("cast by a player"), T("not cast by a player") },
  }
  for _, pair in ipairs(PROPERTY_FLAGS) do
    local v = t[pair[1]]
    if v == true or v == false then
      cf[pair[2]] = v
      keys[#keys + 1] = pair[2] .. "=" .. tostring(v)
      words[#words + 1] = FLAG_WORDS[pair[2]][v and 1 or 2]
    end
  end
  if not next(cf) then return nil, "", nil end
  return cf, table.concat(keys, ","), table.concat(words, ", ")
end

local function HasEntries(on, list)
  if not on or type(list) ~= "table" then return false end
  for _, v in ipairs(list) do
    if Trim(tostring(v)) ~= "" then return true end
  end
  return false
end

local function AnalyseAuraTrigger(t, no, data)
  local unit = t.unit or "player"
  if not UNIT_OK[unit] then no(T("Unit must be Player, Target, Focus or Pet")) end
  local filter = t.debuffType or "HELPFUL"
  if filter ~= "HELPFUL" and filter ~= "HARMFUL" then no(T("Aura Type must be Buff or Debuff (not Both)")) end
  local mode = MODE[t.matchesShowOn or "showOnActive"]
  if not mode then no(T("'Show On: Match Count' cannot be expressed by the engine")) end
  -- WeakAuras applies the property options only where it checks matches (Found), like Remaining Time
  local props, propsKey, propsText
  if mode == "active" then props, propsKey, propsText = PropertyFilters(t, no) end
  -- no spell list at all: any aura of the filter (and the properties) counts. An EMPTY list is not that:
  -- WeakAuras then matches nothing.
  local nameless = not (t.useName and type(t.auranames) == "table")
               and not (t.useExactSpellId and type(t.auraspellids) == "table")
  local ids, sorted = {}, {}
  local byName, unresolved = false, {}
  if t.useExactSpellId then
    for _, s in ipairs(t.auraspellids or {}) do
      local n = tonumber(s)
      if n then ids[n] = true end
    end
  end
  local unseen = {}
  if t.useName then
    byName = true
    for _, nm in ipairs(t.auranames or {}) do
      nm = Trim(nm)
      if nm ~= "" then
        local found, seen = ResolveAuraName(nm, ids, true)
        if not found then unresolved[#unresolved + 1] = nm
        elseif not seen then unseen[#unseen + 1] = nm end
      end
    end
  end
  for id in pairs(ids) do sorted[#sorted + 1] = id end
  if nameless then
    if mode ~= "active" then
      no(T("an Aura trigger without spell names is engine-driven with 'Show On: Aura(s) Found' only"))
    end
  elseif #sorted == 0 then
    if #unresolved > 0 then
      no(T("'%s' is not one of your spells and has not been seen as an aura yet (a name cannot be looked up before that); the engine takes over the first time it is seen out of combat"):format(table.concat(unresolved, ", ")))
    else
      no(T("use 'Exact Spell ID(s)' or a spell Name with at least one entry"))
    end
  elseif byName then
    -- Hostile debuffs carry the cast's id, so the spellbook is enough. Everything else waits until
    -- the aura has been seen: self and friendly buffs often carry a different id than the spell.
    local hostileDebuff = (filter == "HARMFUL") and (unit == "target" or unit == "focus")
    if #unresolved > 0 then
      no(T("'%s' is not one of your spells and has not been seen as an aura yet (a name cannot be looked up before that); the engine takes over the first time it is seen out of combat"):format(table.concat(unresolved, ", ")))
    elseif #unseen > 0 and not hostileDebuff then
      no(T("'%s' has not been seen as a real aura yet; the engine takes over the first time it is seen out of combat"):format(table.concat(unseen, ", ")))
    end
  end
  for _, k in ipairs(UNSUPPORTED) do
    if t[k] then no(T("option '%s' cannot be expressed by the engine"):format(k)) end
  end
  if t.ownOnly == false then no(T("'Own Only' set to 'others only' cannot be expressed by the engine")) end
  local rem
  if t.useRem and mode == "active" then
    local op, x = t.remOperator or ">=", tonumber(t.rem)
    if REM_OPS[op] and x and x >= 0 then
      rem = { op = op, x = x }
    else
      no(T("'Remaining Time' must compare with <, <=, > or >= and a number of seconds"))
    end
  end
  local stacks
  if t.useStacks and mode == "active" then
    local range, why = Engine.StackRange(t)
    if range == nil then no(why) elseif range then stacks = range end
  end
  table.sort(sorted)
  -- Own Only = the filter's PLAYER token ("cast by you"). AuraData.isFromPlayerOrPlayerPet is true for
  -- any player's aura, so another hunter's Serpent Sting passed it.
  local filterString = (t.ownOnly == true) and (filter .. "|PLAYER") or filter
  local candidate, byDuration, durationFromSetting, fingerprint = { includeSpellIDs = ids }, nil, nil, nil
  if nameless then candidate = {} end
  local open = NeverSecret(sorted)
  local friendlyDebuff = not nameless and filter == "HARMFUL" and (unit == "player" or unit == "pet") and not open
  if friendlyDebuff then
    if unit == "player" and data and data.foreverEngineSelfDebuff == true then
      -- the approximation: a debuff on you with the same fingerprint (duration, dispel type, flags)
      if data.uid then fpUsers[data.uid] = true end
      local fp = FingerprintOf(sorted)
      local n = tonumber(data.foreverEngineSelfDebuffMax)
      local fromSetting = n and n > 0
      if not fromSetting then n = fp and fp.duration end
      if fp or fromSetting then
        candidate = {}
        -- half a second of headroom: the filter is "at most", and durations carry a few ms of noise
        if n and n > 0 then candidate.maxDuration = n + 0.5 end   -- 0 = permanent: a max duration would drop it
        if fp then
          if type(fp.dispel) == "string" and fp.dispel ~= "" then candidate.includeDispelTypes = { [fp.dispel] = true } end
          for _, k in ipairs(FP_FLAGS) do
            if type(fp.flags[k]) == "boolean" then candidate[k] = fp.flags[k] end
          end
        end
        byDuration, durationFromSetting, fingerprint = n or 0, fromSetting and true or false, fp
      else
        if data.uid then durWatch[data.uid] = true end
        no(T("the debuff's properties are not known yet: let it land on you once out of combat, or enter 'Longest duration' on the Display tab"))
      end
    else
      no(unit == "pet"
        and T("Blizzard does not let addons pick debuffs on your pet by spell while auras are secret")
        or T("Blizzard does not let addons pick debuffs on yourself by spell while auras are secret; turn on 'Match debuffs on you by their properties' on the Display tab to track it approximately"))
    end
  end
  -- target / focus: allowed or not depending on who is targeted, so only a warning (Explain). Not for
  -- your own spells: your DoTs land on enemies and your buffs on friends, where the filter is allowed.
  -- the property filters apply on every unit; the user's Debuff Type wins over a learned fingerprint's
  for k, v in pairs(props or {}) do candidate[k] = v end
  local warn
  if not nameless and not open and (unit == "target" or unit == "focus") then
    local own = false
    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    for _, id in ipairs(sorted) do
      local ok, known = pcall(C_SpellBook.IsSpellKnown, id, bank)
      if ok and known == true then own = true; break end
    end
    if not own then warn = (filter == "HARMFUL") and "friendly" or "hostile" end
  end
  return { unit = unit, filter = filter, filterString = filterString, mode = mode, rem = rem, stacks = stacks,
           candidate = candidate, ids = sorted, firstId = sorted[1], byDuration = byDuration, warn = warn,
           durationFromSetting = durationFromSetting,
           byName = byName, unresolved = unresolved, unseen = unseen,
           fingerprint = fingerprint, nameless = nameless, propsText = propsText, propsKey = propsKey,
           key = filterString .. ";" .. (props and (propsKey .. ";") or "") .. (nameless and "any" or byDuration and ("fp" .. byDuration .. ":" .. tostring(candidate.includeDispelTypes and next(candidate.includeDispelTypes))
             .. ":" .. (function() local f = {} for _, k in ipairs(FP_FLAGS) do f[#f + 1] = tostring(candidate[k]) end return table.concat(f, ",") end)())
             or table.concat(sorted, ",")) }
end

-- Delegated Aura triggers publish a constant "true" to WeakAuras, and the engine decides which aura
-- part is visible. That is only right when the display's combination is
--   (every other trigger) AND (any Aura trigger)
-- The other triggers keep running in WeakAuras (combat state, target attackable, talents, items and
-- cooldowns are plain data on Forever). A custom combination is checked against that shape on every
-- true/false assignment of its triggers; the verdict is cached per logic text.
local logicVerdicts = {}
local function CombinationOK(data, auraIdx, n)
  local how = data.triggers.disjunctive or "all"
  local nOther = n - #auraIdx
  if how == "all" then
    if #auraIdx == 1 then return true end
    return false, T("several Aura triggers combined with 'All Triggers' cannot be expressed by the engine")
  elseif how == "any" then
    if nOther == 0 then return true end
    return false, T("Aura triggers combined with other triggers through 'Any Triggered' cannot be expressed by the engine")
  elseif how ~= "custom" then
    return false, T("unknown trigger combination")
  end
  if n > 8 then return false, T("a custom trigger combination with more than 8 triggers") end
  local src = data.triggers.customTriggerLogic or ""
  local cacheKey = table.concat({ src, n, table.concat(auraIdx, ",") }, "\n")
  local verdict = logicVerdicts[cacheKey]
  if verdict == nil then
    verdict = false
    local isAura = {}
    for _, i in ipairs(auraIdx) do isAura[i] = true end
    local okL, f = pcall(WA.LoadFunction, "return " .. src, data.id)
    if okL and type(f) == "function" then
      verdict = true
      local states = {}
      for mask = 0, 2 ^ n - 1 do
        local others, anyAura = true, false
        for i = 1, n do
          local on = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
          states[i] = on
          if isAura[i] then anyAura = anyAura or on else others = others and on end
        end
        local okC, res = pcall(f, states)
        if not okC or (res and true or false) ~= (others and anyAura) then verdict = false; break end
      end
    end
    logicVerdicts[cacheKey] = verdict
  end
  if verdict then return true end
  return false, T("the custom trigger combination must read: (every other trigger) and (any of the Aura triggers)")
end

-- Pure function of data (and of the spellbook, for name-based triggers). Returns plan | nil, reasons.
--   single plan    : one Aura trigger, Show On Found / Missing / Always (plan.mode active/missing/always)
--   composite plan : plan.parts = { missing = part | nil, remaining = { {part, op, x}, ... } }, icons only.
--                    Shows the icon while the missing part's aura is absent OR a remaining part's aura
--                    has the given time left. Built from Found + 'Remaining Time' triggers.
local ENGINE_REGIONS = { icon = true, aurabar = true, progresstexture = true, texture = true, text = true, stopmotion = true,
                         model = true }
local KIND_NAME = { aurabar = "Progress Bars", progresstexture = "Progress Textures", texture = "Textures", text = "Texts",
                    stopmotion = "Stop Motions", model = "Models" }

-- What a Text display shows: "plain" (no placeholders), or exactly one aura value the engine can draw
-- itself: "p" (time left), "s" (stacks), "n" (spell name). nil = something else (mixed text, %c, ...).
local TextPlan
do
  -- WA's placeholder grammar (M33kAuras.lua nextState): "%%" is a literal %, "%{...}" and "%" followed by
  -- [0-9A-Za-z.]+ are symbols, a % before anything else stays a literal %. Returns { {lit=}, {sym=}, ... }.
  local function ParseText(s)
    local parts, buf, i, n = {}, {}, 1, #s
    local function flush()
      if #buf > 0 then parts[#parts + 1] = { lit = table.concat(buf) }; buf = {} end
    end
    while i <= n do
      local c = s:sub(i, i)
      local nx = s:sub(i + 1, i + 1)
      if c ~= "%" then
        buf[#buf + 1] = c; i = i + 1
      elseif nx == "%" then
        buf[#buf + 1] = "%"; i = i + 2
      elseif nx == "{" then
        local close = s:find("}", i + 2, true) or (n + 1)
        flush(); parts[#parts + 1] = { sym = s:sub(i + 2, close - 1) }; i = close + 1
      elseif nx:match("^[%w%.]$") then
        local j = i + 1
        while j <= n and s:sub(j, j):match("^[%w%.]$") do j = j + 1 end
        flush(); parts[#parts + 1] = { sym = s:sub(i + 1, j - 1) }; i = j
      else
        buf[#buf + 1] = "%"; i = i + 1
      end
    end
    flush()
    return parts
  end

  -- The one spell a display's Aura trigger names ({ name = } or { id = }), or nil when it names none or several.
  local function SingleSpell(data)
    for i, tr in ipairs(type(data.triggers) == "table" and data.triggers or {}) do
      local t = tr and tr.trigger
      if t and t.type == "aura2" then
        local list = {}
        if t.useName and type(t.auranames) == "table" then
          for _, v in ipairs(t.auranames) do if Trim(v) ~= "" then list[#list + 1] = { name = Trim(v) } end end
        end
        if t.useExactSpellId and type(t.auraspellids) == "table" then
          for _, v in ipairs(t.auraspellids) do if tonumber(v) then list[#list + 1] = { id = tonumber(v) } end end
        end
        return #list == 1 and list[1] or nil, i
      end
    end
  end

  -- What a Text display shows, or nil + the reason the engine cannot draw it:
  --   kind "plain": text only; %n and %i become the tracked spell's name and icon when it is one spell
  --   kind "dur"  : text with %p (time left) and/or %t (total time): the engine's duration text, whose
  --                 format string takes the text around them ("Corruption: {}")
  --   kind "count": text with one %s: the engine's stack count, through a rule formatter ("Stacks: %d")
  --   kind "name" : exactly %n: the engine's spell name (any aura the display matches)
  -- tp.pure: the text is that one placeholder alone.
  local DURATION_SYMS = { p = true, t = true }
  function TextPlan(data)
    local parts = ParseText(tostring(data.displayText or ""))
    local single, auraIdx = SingleSpell(data)
    local kinds, nsyms, lits = {}, 0, false
    for _, part in ipairs(parts) do
      if part.sym then
        local sym = part.sym
        local tn, rest = sym:match("^(%d+)%.(.+)$")
        if tn then
          if tonumber(tn) ~= auraIdx then
            return nil, T("the text reads trigger %s; the engine draws only the Aura trigger's values"):format(tn)
          end
          sym = rest
        end
        part.key = sym
        nsyms = nsyms + 1
        if DURATION_SYMS[sym] then kinds.dur = true
        elseif sym == "s" then kinds.count = (kinds.count or 0) + 1
        elseif sym == "n" then if not single then kinds.name = true end
        elseif sym == "i" then
          if not single then return nil, T("%i needs a display that tracks one spell (the engine cannot show the icon inside a text)") end
        else
          return nil, T("the text uses %%%s, which the engine cannot draw (it draws %%p, %%t, %%s, %%n and %%i)"):format(sym)
        end
      elseif part.lit:find("%S") then
        lits = true
      end
    end
    if kinds.name and not (nsyms == 1 and not lits) then
      return nil, T("a text with other words can show the aura's name only when the display tracks one spell")
    end
    local n = (kinds.dur and 1 or 0) + (kinds.count and 1 or 0) + (kinds.name and 1 or 0)
    if n > 1 or (kinds.count or 0) > 1 then
      return nil, T("the text shows more than one kind of aura value (time, stacks, name); one per text (so far)")
    end
    local tp = { parts = parts, single = single, pure = nsyms == 1 and not lits }
    if tp.pure then
      for _, part in ipairs(parts) do if part.key == "n" then kinds.name = true end end   -- the engine's name
    end
    if kinds.dur then tp.kind = "dur"
    elseif kinds.count then tp.kind = "count"
    elseif kinds.name then
      if not tp.pure then return nil, T("a text with other words can show the aura's name only when the display tracks one spell") end
      tp.kind = "name"
    else tp.kind = "plain" end
    if tp.kind == "dur" then
      for _, part in ipairs(parts) do
        local lit = part.lit and (WA.ReplaceRaidMarkerSymbols and WA.ReplaceRaidMarkerSymbols(part.lit) or part.lit)
        if lit and lit:find("[{}]") then return nil, T("the text around %p contains { or }, which the game's time format uses itself") end
      end
    end
    return tp
  end
end

-- compatibility for callers that only need the kind
local function TextKind(data)
  local tp = TextPlan(data)
  return tp and tp.kind or nil
end
local FOUND_ONLY = { aurabar = true, progresstexture = true }

-- A Progress Texture follows the aura's own duration: progress source Automatic, or the Aura
-- trigger's duration, and no adjusted minimum / maximum.
local function IsCircular(data)
  local o = data.orientation or "VERTICAL"
  return o == "CLOCKWISE" or o == "ANTICLOCKWISE"
end

local function TextureFollowsAura(data, no)
  if IsCircular(data) then
    local fg = data.foregroundTexture
    if type(fg) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(fg) then
      no(T("circular Progress Textures need a texture file, not an atlas"))
    end
  end
  if data.useAdjustededMin or data.useAdjustededMax then
    no(T("the Progress Texture uses an adjusted minimum or maximum progress"))
  end
  local ps = type(data.progressSource) == "table" and data.progressSource or nil
  local src = ps and ps[1] or -1
  if src ~= -1 then
    local t = type(src) == "number" and type(data.triggers) == "table" and data.triggers[src]
    t = t and t.trigger
    if not (t and t.type == "aura2" and ps[3] == "expirationTime") then
      no(T("the Progress Texture's progress source is not the aura's duration"))
    end
  end
end

function Engine.Classify(data)
  local r = {}
  local function no(msg)
    for _, m in ipairs(r) do if m == msg then return end end
    r[#r + 1] = msg
  end
  local rt = data and data.regionType
  if not ENGINE_REGIONS[rt] then return nil, { T("the display is not an Icon, a Progress Bar, a Progress Texture, a Texture, a Stop Motion, a Model or a Text") } end
  if rt == "progresstexture" then TextureFollowsAura(data, no) end
  if not GloballyEnabled() then no(T("the engine is switched off (/faengine on)")) end
  if data.foreverEngine == false then no(T("'Let the game engine draw this aura' is off for this display (Display tab)")) end
  if not Engine.IsAvailable() then no(T("Blizzard_AuraContainer is not available")) end
  if LibStub("Masque", true) then no(T("Masque is loaded")) end
  if data.uid then durWatch[data.uid] = nil; fpUsers[data.uid] = nil; lateUsers[data.uid] = nil end
  local triggers = type(data.triggers) == "table" and data.triggers or {}
  local n, auraIdx = #triggers, {}
  for i = 1, n do
    local t = triggers[i] and triggers[i].trigger
    if t and t.type == "aura2" then
      auraIdx[#auraIdx + 1] = i
    elseif t and t.type == "aura" then
      no(T("trigger %d is a legacy Aura trigger"):format(i))
    end
  end
  if #auraIdx == 0 then no(T("the trigger is not an Aura trigger")); return nil, r end
  if n > 1 then
    local ok, why = CombinationOK(data, auraIdx, n)
    if not ok then no(why) end
  end
  local infos, auraTriggers = {}, {}
  for _, i in ipairs(auraIdx) do
    infos[#infos + 1] = AnalyseAuraTrigger(triggers[i].trigger, no, data)
    auraTriggers[i] = true
  end
  local unit = infos[1].unit
  for _, inf in ipairs(infos) do
    if inf.unit ~= unit then no(T("all Aura triggers must watch the same unit")); break end
  end
  local gates = n - #auraIdx

  if #infos == 1 and not infos[1].rem then
    local inf = infos[1]
    if FOUND_ONLY[rt] and inf.mode and inf.mode ~= "active" then   -- MODE maps showOnActive -> "active"
      no(T("%s are engine-driven with 'Show On: Aura(s) Found' only (so far)"):format(T(KIND_NAME[rt])))
    end
    if rt == "texture" and inf.mode == "always" then
      no(T("a Texture with 'Show On: Always' shows all the time and needs no engine; pick 'Aura(s) Found' or 'Aura(s) Missing'"))
    end
    if rt == "stopmotion" then
      if inf.mode == "always" then
        no(T("a Stop Motion with 'Show On: Always' plays all the time and needs no engine; pick 'Aura(s) Found' or 'Aura(s) Missing'"))
      end
      local sheet, why = Engine.MotionSheet(data)
      if not sheet then no(why) end
    end
    if rt == "model" then
      if inf.mode == "always" then
        no(T("a Model with 'Show On: Always' shows all the time and needs no engine; pick 'Aura(s) Found' or 'Aura(s) Missing'"))
      end
      local ok, why = Engine.ModelSheet(data)
      if not ok then no(why) end
    end
    if rt == "text" then
      local tp, why = TextPlan(data)
      if inf.mode == "always" then
        no(T("a Text with 'Show On: Always' is left to WeakAuras; pick 'Aura(s) Found' or 'Aura(s) Missing'"))
      elseif not tp then
        no(why)
      elseif tp.kind ~= "plain" and inf.mode == "missing" then
        no(T("a text shown while the aura is missing has no time, stacks or name to show; use plain text (%n and %i of a single tracked spell are fine)"))
      end
    end
    if #r > 0 then return nil, r end
    local key = table.concat({ unit, inf.mode, inf.key }, ";")
    return { unit = unit, filter = inf.filter, filterString = inf.filterString, mode = inf.mode,
             candidate = inf.candidate, firstId = inf.firstId, key = key, byDuration = inf.byDuration, warn = inf.warn,
             durationFromSetting = inf.durationFromSetting, fingerprint = inf.fingerprint,
             nameless = inf.nameless, propsText = inf.propsText, propsKey = inf.propsKey,
             ids = inf.ids, byName = inf.byName, gen = spellbookGen, unresolved = inf.unresolved, unseen = inf.unseen,
             auraTriggers = auraTriggers, gates = gates, stacks = inf.stacks }
  end

  if rt ~= "icon" then
    no(T("%s are engine-driven with one Aura trigger without 'Remaining Time' only (so far)"):format(T(KIND_NAME[rt])))
  end
  if data.uid then lateUsers[data.uid] = true end
  local missing, found, remaining = nil, nil, {}
  for _, inf in ipairs(infos) do
    if inf.stacks then no(T("'Stack Count' is engine-driven on a display with one Aura trigger (so far)")) end
  end
  for _, inf in ipairs(infos) do
    if inf.mode == "missing" then
      if missing then no(T("only one Aura trigger may use 'Show On: Aura(s) Missing'")) end
      missing = inf
    elseif inf.mode == "active" then
      if inf.rem then
        remaining[#remaining + 1] = { part = inf, op = inf.rem.op, x = inf.rem.x }
      else
        -- Found + Remaining Time: the Found part draws the aura, the time-left part adds the glow
        if found then no(T("only one Aura trigger may use 'Show On: Aura(s) Found' without 'Remaining Time'")) end
        found = inf
      end
    elseif inf.mode == "always" then
      no(T("'Show On: Always' cannot be combined with other Aura triggers"))
    end
  end
  if found and missing then no(T("'Aura(s) Found' and 'Aura(s) Missing' without 'Remaining Time' cannot be combined")) end
  if found and #remaining == 0 then no(T("two 'Aura(s) Found' triggers cannot be combined")) end
  -- a time-left part gets an animated glow through a clip that needs the aura's total duration
  local lateTotal
  for _, rp in ipairs(remaining) do
    if rp.op == "<" or rp.op == "<=" then
      local d = LearnedDuration(rp.part.ids)
      if d and d > rp.x then lateTotal = math.max(lateTotal or 0, d) end
    end
  end
  if #r > 0 then return nil, r end
  local keys, union, all, byName, unresolved, unseen = { unit, "composite" }, {}, {}, false, {}, {}
  local function take(inf)
    for _, id in ipairs(inf.ids) do if not union[id] then union[id] = true; all[#all + 1] = id end end
    byName = byName or inf.byName
    for _, nm in ipairs(inf.unresolved) do unresolved[#unresolved + 1] = nm end
    for _, nm in ipairs(inf.unseen) do unseen[#unseen + 1] = nm end
  end
  if missing then keys[#keys + 1] = "M:" .. missing.key; take(missing) end
  if found then keys[#keys + 1] = "F:" .. found.key; take(found) end
  if lateTotal then keys[#keys + 1] = "late" .. lateTotal end
  for _, rp in ipairs(remaining) do
    keys[#keys + 1] = ("R%s%s:%s"):format(rp.op, tostring(rp.x), rp.part.key)
    take(rp.part)
  end
  table.sort(all)
  local first = missing or found or remaining[1].part
  local warn, byDuration, durationFromSetting, fingerprint
  for _, inf in ipairs(infos) do
    warn = warn or inf.warn
    if inf.byDuration and not byDuration then
      byDuration, durationFromSetting, fingerprint = inf.byDuration, inf.durationFromSetting, inf.fingerprint
    end
  end
  return { unit = unit, mode = "composite", parts = { missing = missing, found = found, remaining = remaining, lateTotal = lateTotal },
           warn = warn, byDuration = byDuration, durationFromSetting = durationFromSetting, fingerprint = fingerprint,
           filter = first.filter, filterString = first.filterString, firstId = first.firstId,
           nameless = (#all == 0 and first.nameless) or nil, propsKey = first.propsKey, propsText = first.propsText,
           key = table.concat(keys, ";"), ids = all, byName = byName, gen = spellbookGen,
           unresolved = unresolved, unseen = unseen, auraTriggers = auraTriggers, gates = gates }
end

-- Conditions on a delegated Aura trigger never see aura data (only 'Buffed' changes).
local function InertConditions(data, plan)
  local aura = plan and plan.auraTriggers or { [1] = true }
  local function bad(check)
    if not check then return false end
    if check.checks then
      for _, c in ipairs(check.checks) do if bad(c) then return true end end
      return false
    end
    return aura[check.trigger] and check.variable ~= nil and check.variable ~= "buffed"
  end
  for _, c in ipairs(data.conditions or {}) do if bad(c.check) then return true end end
  return false
end

-- The spell whose range gates a display: the user's override, else the NAME of the first tracked id
-- (a name resolves to the rank you know; every rank shares the same range).
local function RangeSpell(data, plan)
  local o = Trim(data.foreverEngineRangeSpell)
  if o ~= "" then return tonumber(o) or o end
  if C_Spell and C_Spell.GetSpellName then
    local ok, nm = pcall(C_Spell.GetSpellName, plan.firstId)
    if ok and type(nm) == "string" and nm ~= "" and not issecretvalue(nm) then return nm end
  end
  return plan.firstId
end

local function WantsRangeGate(data, plan)
  return data.foreverEngineRange == true and plan.unit ~= "player"
end

-- A gate that can never answer is worse than none (IsSpellInRange is nil for a spell you do not
-- know, and a rangeless spell is never "in range"). Safe-time plain data. Returns ok, reason.
local function ValidateRangeSpell(spell)
  if spell == nil then return false, T("the display tracks no spell") end
  local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, spell)
  if not ok or type(id) ~= "number" or issecretvalue(id) then
    return false, T("'%s' is not a spell"):format(tostring(spell))
  end
  local known = false
  pcall(function()
    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    if C_SpellBook and C_SpellBook.IsSpellKnown then
      if C_SpellBook.IsSpellKnown(id, bank) then known = true end
    elseif IsSpellKnown and IsSpellKnown(id) then
      known = true
    end
    if not known and C_SpellBook and C_SpellBook.IsSpellInSpellBook and C_SpellBook.IsSpellInSpellBook(id, bank) then known = true end
  end)
  if not known then return false, T("'%s' is not one of your spells"):format(tostring(spell)) end
  local okR, hasRange = pcall(C_Spell.SpellHasRange, spell)
  if not okR or hasRange ~= true then return false, T("'%s' has no range"):format(tostring(spell)) end
  return true
end

---------------------------------------------------------------------------- sounds on show / hide
-- WeakAuras plays 'On Show' / 'On Hide' sounds when ITS state changes, but a delegated display's state
-- is constant: the engine shows and hides the icon, so WeakAuras never sees the aura come or go.
-- C_UnitAuras.AddAuraSound makes the game play a sound itself when an aura is added to or removed from a
-- unit, also in combat. 'On Show' of a Missing display = the aura was removed, of a Found display = it
-- was added; 'On Hide' the other way round. Sounds need spell ids (a display that matches by properties
-- has none) and a sound FILE (the game cannot take a Sound Kit ID here).
local SOUND_ROUTES = {
  missing = { start = "Removed", finish = "Added" },
  active = { start = "Added", finish = "Removed" },
}

-- The routes of a plan, or nil: Always shows all the time, so its sounds stay WeakAuras' own.
local function SoundRoutes(plan)
  if not plan or not plan.ids then return nil end
  if #plan.ids == 0 and not plan.nameless then return nil end
  if plan.parts then
    if plan.parts.missing then return SOUND_ROUTES.missing end
    if plan.parts.found then return SOUND_ROUTES.active end
    return nil
  end
  return SOUND_ROUTES[plan.mode]
end

-- What the game should play for one WeakAuras action table: { soundFileName = ... } or
-- { soundFileID = ... }, or nil plus "kit" when it is a Sound Kit ID.
local function SoundSource(actions)
  if type(actions) ~= "table" or not actions.do_sound or not actions.sound then return nil end
  local snd = actions.sound
  if snd == " KitID" then return nil, "kit" end
  if snd == " custom" then snd = actions.sound_path end
  local id = tonumber(snd)
  if id then return { soundFileID = id } end
  if type(snd) ~= "string" or Trim(snd) == "" then return nil end
  return { soundFileName = Trim(snd) }
end

-- Part of the display's signature: a changed sound must re-register.
local function SoundSig(data)
  local a, out = data.actions or {}, {}
  for _, when in ipairs({ "start", "finish" }) do
    local x = a[when] or {}
    out[#out + 1] = table.concat({ tostring(x.do_sound), tostring(x.sound), tostring(x.sound_path),
      tostring(x.sound_kit_id), tostring(x.sound_channel) }, "/")
  end
  return table.concat(out, ";")
end

local MODE_TEXT = {
  active = "shows the live aura while it is present, nothing while it is absent",
  missing = "shows your icon while the aura is absent and disappears completely while it is present",
  always = "shows your icon while the aura is absent and the live aura while it is present",
}
local REM_TEXT = { ["<"] = "less than %s s", ["<="] = "at most %s s", [">"] = "more than %s s", [">="] = "at least %s s" }

-- True when no trigger of this display reads auras (cooldown / usable / range / resource triggers
-- are plain data on Forever, in combat too): the engine has nothing to take over.
-- The learned duration the approximation would use for this display (nil when not seen yet).
function Engine.LearnedSelfDebuffDuration(data)
  local plan = Engine.Classify(data)
  if plan and plan.fingerprint then return plan.fingerprint.duration end
  return nil
end

-- True when a display tracks debuffs on yourself (the case 'Match debuffs on you by their properties' is for).
function Engine.TracksSelfDebuff(data)
  for _, tr in ipairs(data and data.triggers or {}) do
    local t = tr and tr.trigger
    if t and t.type == "aura2" and (t.unit or "player") == "player" and t.debuffType == "HARMFUL"
       and (HasEntries(t.useName, t.auranames) or HasEntries(t.useExactSpellId, t.auraspellids)) then return true end
  end
  return false
end

function Engine.HasNoAuraTrigger(data)
  if not data or type(data.triggers) ~= "table" or #data.triggers == 0 then return false end
  for _, tr in ipairs(data.triggers) do
    local t = tr and tr.trigger
    if t and t.type == "aura2" then return false end
  end
  return true
end

function Engine.Explain(data, plan, reasons)
  if plan == nil and reasons == nil then plan, reasons = Engine.Classify(data) end
  if not plan and Engine.HasNoAuraTrigger(data) then
    return T("|cff33ff99Nothing to delegate:|r this display has no Aura trigger. Cooldowns, spell usable / in range, casts and resources are readable in combat on Forever, so it works as it is. The engine only takes over aura displays, which are blind while auras are secret."), false
  end
  if plan then
    local txt
    if plan.parts then
      local when = {}
      if plan.parts.missing then when[#when + 1] = T("while the aura is absent") end
      for _, rp in ipairs(plan.parts.remaining) do
        when[#when + 1] = T("while it has %s left"):format(T(REM_TEXT[rp.op]):format(tostring(rp.x)))
      end
      local glowTxt = plan.parts.lateTotal
        and T("animated (the aura's total duration is known: %s s), also while it runs out"):format(tostring(plan.parts.lateTotal))
        or T("WeakAuras' own animated glow while the aura is missing, a static glow while it runs out (animated once the aura's total duration is known: seen out of combat, or read from the spell's description)")
      if plan.parts.found then
        txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows the live aura while it is present and adds the glow %s. The game checks the time left itself, so it never has to be read. Kept: position, size, groups, %%p/%%s texts, static colour/desaturate/zoom, cooldown swipe; glow %s. Not available: the border (hidden while engine-driven), conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
          :format(plan.unit, plan.parts.found.filterString, table.concat(when, T(" or ")), glowTxt)
      else
        txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s). It shows your icon %s, and nothing otherwise. The game checks the time left itself, so it never has to be read. Kept: position, size, groups, the %%p text, static colour/zoom; glow %s. Not available: the border (hidden while engine-driven), cooldown swipe, stack count and desaturation on the time-left icon, conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
          :format(plan.unit, table.concat(when, T(" or ")), glowTxt)
      end
    elseif data.regionType == "text" then
      local tp = TextPlan(data)
      local kind = tp and tp.kind
      local lone = tp and tp.pure and tp.parts[1].key
      local what = T("your text")
      if kind == "dur" then
        what = lone == "p" and T("the aura's time left, counted down by the game")
               or lone == "t" and T("the aura's total duration")
               or T("your text with the aura's time, counted down by the game")
      elseif kind == "count" then
        what = lone and T("the aura's stacks") or T("your text with the aura's stacks (0 stacks read 0)")
      elseif kind == "name" then
        what = T("the aura's name")
      end
      local when = plan.mode == "missing" and T("while the aura is absent and nothing while it is present")
                                         or T("while the aura is present and nothing while it is absent")
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows %s %s. Kept: position, size, groups, font, size, outline (SLUG drawn as a normal outline), colour, shadow, justify and width. Not available: %sconditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, what, when,
                kind == "dur" and T("WeakAuras' %p formatting options (the game formats the time itself), ") or "")
    elseif data.regionType == "model" then
      local when = plan.mode == "missing" and T("while the aura is absent and disappears completely while it is present")
                                         or T("while the aura is present and nothing while it is absent")
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows your model %s. Kept: position, size, groups, the model file or display ID, its position or transform, rotation, portrait zoom, animation and alpha, %%p/%%s/%%n texts, the glow (shown only while the model is). Not drawn: the border (hidden while engine-driven). Not available: a unit's model, conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, when)
    elseif data.regionType == "stopmotion" then
      local when = plan.mode == "missing" and T("while the aura is absent and disappears completely while it is present")
                                         or T("while the aura is present and nothing while it is absent")
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It plays your animation %s, as a FlipBook animation of the game (scripts cannot run there). Kept: position, size, groups, the texture's frames, frame rate, Loop or Bounce, Inverse, End, colours, desaturate, blend mode, the background frame, %%p/%%s/%%n texts, the glow (shown only while the animation is). Not drawn: the border (hidden while engine-driven). Not available: Once and Progress animations, a Start above 0%%, conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, when)
    elseif data.regionType == "texture" then
      local when = plan.mode == "missing" and T("while the aura is absent and disappears completely while it is present")
                                         or T("while the aura is present and nothing while it is absent")
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows your texture %s. Kept: position, size, groups, texture, colour, rotation, mirror, desaturate, blend mode, %%p/%%s/%%n texts, the glow (shown only while the texture is, animated like WeakAuras' own). Not drawn: the border (hidden while engine-driven). Not available: conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, when)
    elseif data.regionType == "progresstexture" and Engine.UsesArcPieces(data) then
      local n, step = Engine.ArcPieces(data)
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows the texture while the aura is present and its arc runs out the way WeakAuras' own does as the aura runs out (grows with 'Inverse'), in %d steps of %s degrees: frames that follow the game's timer bar show the arc piece by piece, so the time left never has to be read. Kept: position, size, groups, textures, colours, desaturate, blend mode, crop, mirror, rotation, legacy rotation, start and end angle, the direction, the background, %%p/%%s/%%n texts, the glow (shown only while the texture is, animated like WeakAuras' own). Not drawn: additional progress and the border (hidden while engine-driven). Not available: conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, n, ("%.1f"):format(step))
    elseif data.regionType == "progresstexture" and IsCircular(data) then
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows the texture while the aura is present and the game's cooldown swipe sweeps it away as the aura runs out (draws the time gone with 'Inverse'); the game checks the time left itself, so it never has to be read. Kept: position, size, groups, textures, colours, crop, mirror, rotation, start angle, the background, %%p/%%s/%%n texts, the glow (shown only while the texture is, animated like WeakAuras' own). Not drawn on the sweeping part: desaturate, blend mode, legacy rotation. Not drawn: additional progress and the border (hidden while engine-driven). Not available: conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString)
    elseif data.regionType == "progresstexture" then
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It shows the texture while the aura is present and empties it as the aura runs out (fills it with 'Inverse'); the game checks the time left itself, so it never has to be read. Kept: position, size, groups, textures, colours, desaturate, blend mode, crop, rotation, mirror, 'Compress', the background, %%p/%%s/%%n texts, the glow (shown only while the texture is, animated like WeakAuras' own). Not drawn: slanted ends (drawn straight), additional progress and the border (hidden while engine-driven). Not available: conditions and texts that read aura state, show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString)
    else
      local kept = T("border and glow")
      if data.regionType == "icon" and plan.mode ~= "always" then
        kept = T("the border (also while nothing is drawn), and the glow: shown only while the icon is, and animated like WeakAuras' own")
      elseif data.regionType == "aurabar" then
        kept = T("the bar colours and gradient, the border (also while nothing is drawn), and the glow: shown only while the bar is, and animated like WeakAuras' own (a glow on the bar's fill goes around the whole bar)")
      end
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It %s. Kept: position, size, groups, %%n/%%i texts, static colour/desaturate/zoom, %s; cooldown numbers count like the buff frame. Not available: conditions and texts that read aura state (stacks, remaining, active), show/hide animations and actions on aura gain/loss other than sounds.")
        :format(plan.unit, plan.filterString, T(MODE_TEXT[plan.mode]), kept)
    end
    if plan.parts and Engine.HasGlowPartChoice(data) and (data.foreverEngineGlowPart or "both") ~= "both" then
      txt = txt .. " " .. (data.foreverEngineGlowPart == "remaining" and T("The glow is drawn only while it runs out.")
                                                                    or T("The glow is drawn only while the aura is missing."))
    end
    if (plan.gates or 0) > 0 then
      txt = txt .. " " .. T("Your other trigger(s) still decide when the display may show at all; WeakAuras checks them itself, which works in combat for plain data (combat state, target attackable or hostile, talents, items, cooldowns) but not for values Forever keeps secret, such as health or power amounts.")
    end
    if plan.nameless then
      txt = txt .. " " .. T("|cff33ff99By properties:|r no spell is named, so any %s%s counts; the icon is that aura's own. When several match, the game shows one of them.")
        :format(plan.filter == "HARMFUL" and T("debuff") or T("buff"),
                plan.propsText and (" " .. T("that is %s"):format(plan.propsText)) or "")
    elseif plan.propsText then
      txt = txt .. " " .. T("Only auras that are %s count."):format(plan.propsText)
    end
    if plan.byName then
      txt = txt .. " " .. T("Spell name resolved to id(s) %s (your spellbook ranks and auras seen so far); re-resolved as you learn spells and see auras."):format(table.concat(plan.ids, ", "))
    end
    if WantsRangeGate(data, plan) then
      local spell = RangeSpell(data, plan)
      local okV, why = ValidateRangeSpell(spell)
      if okV then
        txt = txt .. " " .. T("|cff33ff99Range gate:|r hidden unless '%s' is in range of the unit (the spell's own min/max range, sampled 5x per second, also in combat)."):format(tostring(spell))
      else
        txt = txt .. " " .. T("|cffff9933Range gate off:|r %s. Enter a 'Range check spell' you know that has a range, e.g. Auto Shot."):format(why)
      end
    end
    if plan.byDuration then
      local okN, spell = pcall(C_Spell.GetSpellName, plan.firstId)
      spell = (okN and type(spell) == "string" and not issecretvalue(spell) and spell ~= "") and spell or T("the debuff")
      local parts = {}
      if plan.byDuration > 0 then
        parts[#parts + 1] = T("lasting at most %s s%s"):format(tostring(plan.byDuration), plan.durationFromSetting and T(" (your setting)") or "")
      else
        parts[#parts + 1] = T("without a duration")
      end
      local fp = plan.fingerprint
      if fp then
        parts[#parts + 1] = (type(fp.dispel) == "string" and fp.dispel ~= "") and T("dispel type %s"):format(fp.dispel) or T("any dispel type")
        local n = 0
        for _, k in ipairs(FP_FLAGS) do if type(fp.flags[k]) == "boolean" then n = n + 1 end end
        parts[#parts + 1] = T("%d more of its properties"):format(n)
      end
      txt = txt .. " " .. T("|cffff9933Approximation:|r Blizzard does not let addons tell which debuff on you it is while auras are secret, so this shows a debuff on you that matches %s's fingerprint, learned when it landed on you: %s. A different debuff with exactly the same fingerprint would count too."):format(spell, table.concat(parts, ", "))
      if fp and fp.flags.isFromPlayerOrPlayerPet == false and (plan.filterString or ""):find("PLAYER") then
        txt = txt .. " " .. T("|cffff9933Note:|r %s was not put on you by you, but 'Own Only' is on, so it never counts. Turn 'Own Only' off."):format(spell)
      end
    end
    if plan.warn == "friendly" then
      txt = txt .. " " .. T("|cffff9933Note:|r Blizzard does not let addons pick debuffs on friendly units by spell while auras are secret: on a friendly target this display finds nothing (a 'missing' icon shows as missing).")
    elseif plan.warn == "hostile" then
      txt = txt .. " " .. T("|cffff9933Note:|r Blizzard does not let addons pick buffs on hostile units by spell while auras are secret: on an enemy target this display finds nothing (a 'missing' icon shows as missing).")
    end
    local routes = SoundRoutes(plan)
    local actions = data.actions or {}
    local sounds = {}
    for _, when in ipairs({ "start", "finish" }) do
      local src, why = SoundSource(actions[when])
      local label = when == "start" and T("'On Show'") or T("'On Hide'")
      if src and routes and plan.nameless then
        local _, n, fromTables = SeenIds(plan)
        if n > 0 and fromTables > 0 then
          sounds[#sounds + 1] = T("%s sound plays when a matching aura is %s: %d spells, %d of them from the game's own spell tables (client %s), %d learned from auras EverAuras has seen")
            :format(label, routes[when] == "Added" and T("gained") or T("lost"), n, fromTables,
                    tostring(Private.ForeverDispelData and Private.ForeverDispelData.build), n - fromTables)
        elseif n > 0 then
          sounds[#sounds + 1] = T("%s sound plays when a matching aura is %s, for the %d kind(s) EverAuras has seen so far; it learns more from every aura it can read out of combat (you, your pet, target, focus, group and nearby enemies)")
            :format(label, routes[when] == "Added" and T("gained") or T("lost"), n)
        else
          sounds[#sounds + 1] = T("%s sound waits until EverAuras has seen a matching aura once out of combat, on you, your pet, target, focus, group or a nearby enemy: the game plays aura sounds by spell only"):format(label)
        end
      elseif src and routes then
        sounds[#sounds + 1] = T("%s sound plays when the aura is %s"):format(label,
          routes[when] == "Added" and T("gained") or T("lost"))
      elseif why == "kit" and routes then
        sounds[#sounds + 1] = T("%s uses a Sound Kit ID, which the game cannot play here: pick a sound file"):format(label)
      end
    end
    if #sounds > 0 then
      txt = txt .. " " .. T("|cff33ff99Sounds:|r %s; the game plays them itself, also in combat."):format(table.concat(sounds, "; "))
    end
    if plan.stacks then
      local st = plan.stacks
      local function n(k) return k == 1 and T("1 stack") or T("%d stacks"):format(k) end
      local when = (st.ge and st.le and st.ge == st.le) and T("at exactly %s"):format(n(st.ge))
                or (st.ge and st.le) and T("at %d to %s"):format(st.ge, n(st.le))
                or st.ge and T("at %s or more"):format(n(st.ge))
                or T("at %s or fewer"):format(n(st.le))
      txt = txt .. " " .. T("|cff33ff99Stack Count:|r shown only %s. The game compares the stacks itself: a frame around the display opens and closes with the engine's own stack bar. Sounds still play when the aura comes or goes."):format(when)
    end
    if InertConditions(data, plan) then
      txt = txt .. " " .. T("|cffff9933Note:|r a condition reads trigger data other than 'Buffed'; it never fires on this display.")
    end
    return txt, true
  end
  return T("|cffff8800Not engine-driven|r (blind while auras are secret) because: ") .. table.concat(reasons or {}, "; "), false
end

-- Trigger side. Called from BuffTrigger.Add with the record that is about to be stored, so the
-- trigger and the region can never disagree about whether a display is engine-driven.
function Engine.PrepareTriggerInfo(info, trigger, data)
  local plan = Engine.Classify(data)
  decided[data.uid] = plan or false
  -- called once per Aura trigger: the display is name-watched when ANY of its Aura triggers uses names
  local anyName = false
  for _, tr in ipairs(data.triggers or {}) do
    local t = tr and tr.trigger
    if t and t.type == "aura2" and t.useName then anyName = true end
  end
  nameWatch[data.uid] = anyName or nil
  if trigger.useName then
    for _, nm in ipairs(trigger.auranames or {}) do
      nm = Trim(nm)
      local id = tonumber(nm)
      if id and C_Spell and C_Spell.GetSpellName then
        local ok, real = pcall(C_Spell.GetSpellName, id)
        if ok and type(real) == "string" and real ~= "" and not issecretvalue(real) then nm = real else nm = "" end
      end
      if nm ~= "" then watchNames[nm:lower()] = true end
    end
  end
  info.engineDelegated = plan ~= nil
  if plan then
    info.matchCountFunc, info.remainingFunc, info.remainingCheck = nil, nil, 0
    info.scanFunc, info.fetchTooltip, info.fetchRole, info.fetchRaidMark = nil, nil, nil, nil
    -- The constant state must collapse when target/focus/pet is gone, and LoadAura only registers
    -- the unit-existence kick when unitExists is non-nil. Default it to "hide" for non-player units.
    if plan.unit ~= "player" and info.unitExists == nil then
      info.unitExists = false
    end
  end
end

---------------------------------------------------------------------------- engine objects (safe time only)
local function RegionSize(region)
  local att = attachments[region]
  if att and att.textW then return att.textW, att.textH end
  local w, h = region:GetWidth(), region:GetHeight()
  if issecretvalue(w) or issecretvalue(h) then return 32, 32 end
  return math.max(math.floor(w + 0.5), 1), math.max(math.floor(h + 0.5), 1)
end

local function BuildHost(region)
  -- with the aura containers' ban on layout scripts from the start, so it can hang on a Dynamic Group's
  -- chain of containers; everything of ours is created inside it and inherits the ban
  local host = CreateFrame("Frame", nil, region, "DisableUntrustedLayoutScriptsTemplate")
  host:SetAllPoints(region)
  host:SetFrameLevel(region:GetFrameLevel() + 1)
  host:Hide()
  -- the Stack Count gates (Engine.ApplyStacks): plain frames around the container, clipping only while a
  -- stack filter needs them. The container is created inside them: it cannot change parent later.
  local ge = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
  ge:SetAllPoints(host)
  ge:SetFrameLevel(host:GetFrameLevel())
  local le = CreateFrame("Frame", nil, ge, "DisableUntrustedLayoutScriptsTemplate")
  le:SetAllPoints(host)
  le:SetFrameLevel(host:GetFrameLevel())
  local c = CreateFrame("AuraContainer", nil, le, "CustomAuraContainerTemplate")
  -- TOPLEFT only: the engine sets the container's size (secretly). Nothing of ours ever reads it.
  c:SetPoint("TOPLEFT", host, "TOPLEFT")
  c:SetFrameLevel(host:GetFrameLevel())
  return host, c, { ge = ge, le = le }
end

-- Found / Always: a slot whose button draws the live aura on top of the region.
local function BuildSlot(att, region, plan)
  local host, c, s = att.host, att.container, att.shadows
  local ok, button = pcall(c.AddAuraSlot, c, KEY, plan.filterString, {
    candidateFilters = plan.candidate,
    initializeFrame = function(button)
      -- Runs synchronously inside AddAuraSlot, BEFORE DenyTaintedAccessWhenAurasAreSecret is applied.
      button:ClearAllPoints()
      button:SetAllPoints(host)
      button:SetFrameLevel(c:GetFrameLevel())
      pcall(button.SetMouseClickEnabled, button, false)   -- click-through like a WA icon
      pcall(button.EnableMouseMotion, button, false)      -- engine tooltip only with data.useTooltip
      pcall(button.SetHideTooltipInCombat, button, false)
      if att.isBar then
        -- geometry follows WA's own bar and icon frames, which already account for icon side and size
        s.barBg = button:CreateTexture(nil, "BACKGROUND")
        s.bar = CreateFrame("StatusBar", nil, button)
        Engine.SetAnchors(att, s.bar, { { "TOPLEFT", region.bar, "TOPLEFT" }, { "BOTTOMRIGHT", region.bar, "BOTTOMRIGHT" } })
        s.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        s.bar:SetFrameLevel(button:GetFrameLevel() + 1)
        s.barBg:SetAllPoints(s.bar)
        s.icon = button:CreateTexture(nil, "ARTWORK")
        Engine.SetAnchors(att, s.icon, { { "TOPLEFT", region.icon, "TOPLEFT" }, { "BOTTOMRIGHT", region.icon, "BOTTOMRIGHT" } })
        pcall(s.icon.SetSnapToPixelGrid, s.icon, false)
        s.texts = CreateFrame("Frame", nil, button)
        s.texts:SetAllPoints(button)
        s.texts:SetFrameLevel(button:GetFrameLevel() + 2)
        s.duration = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.duration:SetPoint("CENTER")
        s.count = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.count:SetPoint("CENTER")
        s.name = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.name:SetPoint("CENTER")
        local dirs = Enum and Enum.StatusBarTimerDirection
        att.barDirection = dirs and dirs.RemainingTime
        button:SetDurationBar(s.bar, { direction = att.barDirection })
        button:SetIcon(s.icon)
        button:SetDurationText(s.duration, nil)
        button:SetApplicationCount(s.count, nil)
        button:SetSpellName(s.name)
        return
      end
      if att.isText then
        -- a Text display: plain text, or the engine's own time left / stacks / name, on the button
        s.texts = CreateFrame("Frame", nil, button)
        s.texts:SetAllPoints(button)
        s.texts:SetFrameLevel(button:GetFrameLevel() + 2)
        s.label = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.duration = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.count = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.name = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        for _, fs in ipairs({ s.label, s.duration, s.count, s.name }) do fs:SetPoint("CENTER") end
        button:SetDurationText(s.duration, nil)
        button:SetApplicationCount(s.count, nil)
        button:SetSpellName(s.name)
        return
      end
      if att.isPic or att.isMotion or att.isModel then
        -- a Texture display: a copy of its texture, shown with the button (= while the aura is present);
        -- a Stop Motion: its sheet played by a FlipBook animation, which runs where scripts do not
        if att.isMotion then
          s.motion = Engine.NewMotion(button, button)
        elseif att.isModel then
          s.model = Engine.NewModel(button)
          s.model:SetAllPoints(button)
        else
          s.pic = button:CreateTexture(nil, "ARTWORK")
          s.pic:SetAllPoints(button)
          pcall(s.pic.SetSnapToPixelGrid, s.pic, false)
          pcall(s.pic.SetTexelSnappingBias, s.pic, 0)
        end
        s.texts = CreateFrame("Frame", nil, button)
        s.texts:SetAllPoints(button)
        s.texts:SetFrameLevel(button:GetFrameLevel() + 2)
        s.duration = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.duration:SetPoint("CENTER")
        s.count = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.count:SetPoint("CENTER")
        s.name = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.name:SetPoint("CENTER")
        button:SetDurationText(s.duration, nil)
        button:SetApplicationCount(s.count, nil)
        button:SetSpellName(s.name)
        return
      end
      if att.isTex then
        -- an invisible StatusBar the engine fills; the clip follows its fill and reveals the texture
        s.texBg = button:CreateTexture(nil, "BACKGROUND")
        s.texBg:SetAllPoints(button)
        s.bar = CreateFrame("StatusBar", nil, button)
        s.bar:SetAllPoints(button)
        s.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        s.bar:SetStatusBarColor(1, 1, 1, 0)
        s.bar:SetFrameLevel(button:GetFrameLevel() + 1)
        s.fill = s.bar:GetStatusBarTexture()
        s.fill:SetAlpha(0)
        s.texClip = CreateFrame("Frame", nil, button)
        s.texClip:SetClipsChildren(true)
        s.texClip:SetAllPoints(s.fill)
        s.texClip:SetFrameLevel(button:GetFrameLevel() + 1)
        s.texFg = s.texClip:CreateTexture(nil, "ARTWORK")
        s.texFg:SetAllPoints(button)
        -- circular ones: the game's cooldown swipe, drawn with the display's texture
        s.swipe = CreateFrame("Cooldown", nil, button)
        s.swipe:SetAllPoints(button)
        s.swipe:SetFrameLevel(button:GetFrameLevel() + 1)
        pcall(s.swipe.SetDrawBling, s.swipe, false)
        pcall(s.swipe.SetDrawEdge, s.swipe, false)
        pcall(s.swipe.SetHideCountdownNumbers, s.swipe, true)
        button:SetDurationCooldown(s.swipe)
        for _, tex in ipairs({ s.texBg, s.texFg }) do
          pcall(tex.SetSnapToPixelGrid, tex, false)
          pcall(tex.SetTexelSnappingBias, tex, 0)
        end
        att.texBgOffset, att.texCompress = 0, false
        s.texts = CreateFrame("Frame", nil, button)
        s.texts:SetAllPoints(button)
        s.texts:SetFrameLevel(button:GetFrameLevel() + 2)
        s.duration = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.duration:SetPoint("CENTER")
        s.count = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.count:SetPoint("CENTER")
        s.name = s.texts:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        s.name:SetPoint("CENTER")
        local dirs = Enum and Enum.StatusBarTimerDirection
        att.barDirection = dirs and dirs.RemainingTime
        button:SetDurationBar(s.bar, { direction = att.barDirection })
        button:SetDurationText(s.duration, nil)
        button:SetApplicationCount(s.count, nil)
        button:SetSpellName(s.name)
        return
      end
      s.icon = button:CreateTexture(nil, "ARTWORK")
      s.icon:SetAllPoints(button)
      pcall(s.icon.SetSnapToPixelGrid, s.icon, false)
      pcall(s.icon.SetTexelSnappingBias, s.icon, 0)
      s.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
      s.cooldown:SetAllPoints(s.icon)
      pcall(s.cooldown.SetDrawBling, s.cooldown, false)
      local fmt = Private.ForeverAuraCountdownFormatter()
      if fmt then pcall(s.cooldown.SetCountdownFormatter, s.cooldown, fmt) end
      s.duration = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      s.duration:SetPoint("CENTER")
      s.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      s.count:SetPoint("CENTER")
      s.glow = button:CreateTexture(nil, "OVERLAY")   -- the static glow: shown with the button, i.e. the aura
      s.glow:Hide()
      button:SetIcon(s.icon)
      button:SetDurationCooldown(s.cooldown)
      button:SetDurationText(s.duration, nil)
      button:SetApplicationCount(s.count, nil)
    end,
  })
  if not ok or not button then
    WA.prettyPrint(("%s: engine slot failed: %s"):format(tostring(region.id), tostring(button)))
    att.broken = true
    return false
  end
  att.button, att.slotBuilt = button, true
  return true
end

-- Stack Count: two gates sit between the host and the container (BuildHost) and clip all the display
-- draws there, glows included. Each hangs on a stack bar in an aura slot of its own (same aura): the
-- engine sets that bar's range to 0..max and its value to the aura's stacks (SetApplicationBar), and the
-- bar is W px wide with its right end MARGIN px right of the display, so its fill edge sits W/max px
-- further left for every stack below max. Gate "ge" spans from the bar's left end to the fill edge:
-- with max = N it reaches past the display only at N stacks or more. Gate "le" spans from the fill edge
-- to the bar's right end: with max = N + 1 it closes only above N stacks. The threshold lives in the
-- bar's range alone, so nothing that hangs on the aura's frames ever moves. Measured with /fdstack
-- (2026-10-06): the engine shows such a bar at 0 stacks (min 0), a clip hangs on an empty fill, a frame
-- around the container may hang on a bar inside the aura button, in combat too; a minimum below 0 is
-- refused. Once built, a gate stays on its slot (only its clipping is switched), and the slot follows the
-- display's aura, so the gate always has a place while the aura is shown.
do
  local STACK_W, STACK_MARGIN = 100000, 300
  local SLOT_KEYS = { ge = KEY .. "S1", le = KEY .. "S2" }

  local function Options(kind, n)
    local I = Enum and Enum.StatusBarInterpolation
    return { minApplications = 0, maxApplications = (kind == "ge") and n or (n + 1), interpolation = I and I.Immediate }
  end

  local function BuildStackSlot(att, kind, plan, n)
    local c, host, gate = att.container, att.host, att.gates[kind]
    local sb
    local ok, button = pcall(c.AddAuraSlot, c, SLOT_KEYS[kind], plan.filterString, {
      candidateFilters = plan.candidate,
      initializeFrame = function(button)
        button:ClearAllPoints()
        button:SetAllPoints(host)
        button:SetFrameLevel(c:GetFrameLevel())
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.EnableMouseMotion, button, false)
        sb = CreateFrame("StatusBar", nil, button)
        sb:SetPoint("TOPRIGHT", button, "TOPRIGHT", STACK_MARGIN, STACK_MARGIN)
        sb:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", STACK_MARGIN, -STACK_MARGIN)
        sb:SetWidth(STACK_W)
        sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        sb:SetStatusBarColor(0, 0, 0, 0)
        sb:SetAlpha(0)                               -- never drawn: only its fill edge serves as an anchor
        button:SetApplicationBar(sb, Options(kind, n))
        local fill = sb:GetStatusBarTexture()
        gate:ClearAllPoints()
        if kind == "ge" then
          gate:SetPoint("TOPLEFT", sb, "TOPLEFT")
          gate:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
        else
          gate:SetPoint("TOPLEFT", fill, "TOPRIGHT")
          gate:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT")
        end
      end,
    })
    if not ok or not button or not sb then
      WA.prettyPrint(("%s: engine stack gate failed: %s"):format(tostring(att.region.id), tostring(button)))
      return nil
    end
    return { button = button, bar = sb, n = n, filter = plan.filterString, key = plan.key, on = true }
  end

  -- on = the plan's stack range applies (a Found slot); else the gates only stop clipping
  function Engine.ApplyStacks(att, plan, on)
    local want = on and plan and plan.stacks or nil
    local c, slots = att.container, att.stackSlots or {}
    att.stackSlots = slots
    for _, kind in ipairs({ "ge", "le" }) do
      local n = want and want[kind]
      local gate = att.gates and att.gates[kind]
      local ss = slots[kind]
      if gate and n and not ss then
        ss = BuildStackSlot(att, kind, plan, n)
        slots[kind] = ss
      elseif ss and plan then
        if ss.filter ~= plan.filterString then c:SetAuraSlotFilterString(SLOT_KEYS[kind], plan.filterString); ss.filter = plan.filterString end
        if ss.key ~= plan.key then c:SetAuraSlotCandidateFilters(SLOT_KEYS[kind], plan.candidate); ss.key = plan.key end
        if not ss.on then c:SetAuraSlotEnabled(SLOT_KEYS[kind], true); ss.on = true end
        if n and ss.n ~= n and pcall(ss.button.SetApplicationBar, ss.button, ss.bar, Options(kind, n)) then ss.n = n end
      end
      if gate then gate:SetClipsChildren((n and ss) and true or false) end
    end
  end
end

-- m = margin: the clip reaches m px past the icon on every side (room for the static glow). The element
-- is 2m wider so that "present" still pushes the clip's left edge onto its right edge (zero width).
local function GroupLayout(w, h, m)
  return { elementWidth = w + 1 + 2 * (m or 0), elementHeight = h }
end

local function AnchorClip(att, m)
  local clip, c, host = att.shadows.clip, att.container, att.host
  clip:ClearAllPoints()
  clip:SetPoint("TOPLEFT", c, "TOPRIGHT", -1 - m, m)
  clip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", m, -m)
end

-- Missing: a group of at most one INVISIBLE button. The container's secret width (1 or W+1+2m) drives a
-- clipping frame that holds the "cast this" underlay: full while absent, zero width while present.
local function BuildGroup(att, region, plan, m)
  local host, c, s = att.host, att.container, att.shadows
  local w, h = RegionSize(region)
  m = m or 0
  local ok, err = pcall(c.AddAuraGroup, c, KEY, plan.filterString, {
    candidateFilters = plan.candidate,
    maxFrameCount = 1,
    layout = GroupLayout(w, h, m),
    initializeFrame = function(button)
      -- Ten of these are pre-created per group (the engine hides counts that way). They draw nothing.
      button:SetSize(w + 1 + 2 * m, h)
      pcall(button.SetMouseClickEnabled, button, false)
      pcall(button.EnableMouseMotion, button, false)
    end,
  })
  if not ok then
    WA.prettyPrint(("%s: engine group failed: %s"):format(tostring(region.id), tostring(err)))
    att.broken = true
    return false
  end
  -- Frames anchored to a container that owns an aura group must carry the layout-script aspect
  -- themselves (Blizzard_CustomAuraContainer.lua:317-322); this template is how addons opt in.
  local clip = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
  clip:SetClipsChildren(true)
  clip:SetFrameLevel(host:GetFrameLevel())
  local u = clip:CreateTexture(nil, "ARTWORK")
  u:SetAllPoints(host)
  pcall(u.SetSnapToPixelGrid, u, false)
  pcall(u.SetTexelSnappingBias, u, 0)
  -- the static glow: anchored to the host (a plain rect), clipped by the clip like the underlay
  s.clip, s.underlay, s.mglow = clip, u, clip:CreateTexture(nil, "OVERLAY")
  s.mglow:Hide()
  AnchorClip(att, m)
  att.groupBuilt, att.groupW, att.groupH, att.groupM = true, w, h, m
  return true
end

-- Builds the missing-mode group on first use, else points it at the part's filter and candidates.
-- part = a single plan, or the missing part of a composite plan (both carry filterString/candidate/key).
local function EnsureGroup(att, region, part, m)
  local c = att.container
  m = m or 0
  if not att.groupBuilt then
    if not BuildGroup(att, region, part, m) then return false end
    att.groupFilter, att.groupKey = part.filterString, part.key
  else
    if att.groupFilter ~= part.filterString then c:SetAuraGroupFilterString(KEY, part.filterString); att.groupFilter = part.filterString end
    if att.groupKey ~= part.key then c:SetAuraGroupCandidateFilters(KEY, part.candidate); att.groupKey = part.key end
    local w, h = RegionSize(region)
    if w ~= att.groupW or h ~= att.groupH or m ~= att.groupM then
      c:SetAuraGroupLayout(KEY, GroupLayout(w, h, m)); att.groupW, att.groupH = w, h
      if m ~= att.groupM then AnchorClip(att, m); att.groupM = m end
    end
    c:SetAuraGroupEnabled(KEY, true)
  end
  att.shadows.clip:Show()
  return true
end

-- Found: the Missing trick mirrored. A second container holds a group of at most one invisible button
-- on the same aura; its secret width (1 or W+1+2m) drives a clip that is full while the aura is present
-- and zero width while it is absent. The animated glow lives in it. Built only for Found icons with a
-- glow. Returns false when it cannot be built; the display then keeps the static glow.
local function EnsurePresentClip(att, region, plan, m)
  local host = att.host
  local w, h = RegionSize(region)
  if not att.pBuilt then
    local c2 = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
    c2:SetPoint("TOPLEFT", host, "TOPLEFT")
    c2:SetFrameLevel(host:GetFrameLevel())
    local ok, err = pcall(c2.AddAuraGroup, c2, KEY, plan.filterString, {
      candidateFilters = plan.candidate,
      maxFrameCount = 1,
      layout = GroupLayout(w, h, m),
      initializeFrame = function(button)
        button:SetSize(w + 1 + 2 * m, h)
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.EnableMouseMotion, button, false)
      end,
    })
    if not ok then
      if not att.pWarned then
        att.pWarned = true
        WA.prettyPrint(("%s: engine glow clip failed: %s"):format(tostring(region.id), tostring(err)))
      end
      c2:Hide()
      return false
    end
    -- inside the Stack Count gates, so a glow shows only while the stacks match
    local clip = CreateFrame("Frame", nil, att.gates and att.gates.le or host, "DisableUntrustedLayoutScriptsTemplate")
    clip:SetClipsChildren(true)
    att.container2, att.pclip, att.pBuilt = c2, clip, true
    att.pFilter, att.pKey, att.pW, att.pH, att.pM = plan.filterString, plan.key, w, h, m
    att.pAnchoredM = nil
  else
    local c2 = att.container2
    if att.pFilter ~= plan.filterString then c2:SetAuraGroupFilterString(KEY, plan.filterString); att.pFilter = plan.filterString end
    if att.pKey ~= plan.key then c2:SetAuraGroupCandidateFilters(KEY, plan.candidate); att.pKey = plan.key end
    if w ~= att.pW or h ~= att.pH or m ~= att.pM then
      c2:SetAuraGroupLayout(KEY, GroupLayout(w, h, m)); att.pW, att.pH, att.pM = w, h, m
    end
    c2:SetAuraGroupEnabled(KEY, true)
  end
  if att.pAnchoredM ~= m then
    -- right edge from the secret-width container, left and bottom from the plain host
    local clip = att.pclip
    clip:ClearAllPoints()
    clip:SetPoint("TOPRIGHT", att.container2, "TOPRIGHT", -1 - m, m)
    clip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -m, -m)
    att.pAnchoredM = m
  end
  if att.pUnit ~= plan.unit then att.container2:SetUnit(plan.unit); att.pUnit = plan.unit end
  att.container2:Show()
  att.pclip:SetFrameLevel(host:GetFrameLevel() + 2)
  att.pclip:Show()
  return true
end

local function DisablePresentClip(att)
  if not att.pBuilt then return end
  pcall(att.container2.SetAuraGroupEnabled, att.container2, KEY, false)
  att.pclip:Hide()
  att.pclipShown = false
end

-- WA's SubText (SubText.lua modify) resolves selfPoint "AUTO" per region type: an icon's text hugs the
-- inner corner or hangs off the opposite side of an outer one; a bar's takes the anchor itself (without
-- ICON_ / INNER_); anything else (textures) takes the opposite point of its anchor.
local MIRROR = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP",
  TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT", CENTER = "CENTER" }
local function ResolveSelfPoint(sub, regionType)
  local sp, ap = sub.text_selfPoint, sub.anchor_point or "CENTER"
  if sp and sp ~= "AUTO" then return sp end
  if regionType == "icon" then
    if ap:sub(1, 6) == "INNER_" then return ap:sub(7) end
    if ap:sub(1, 6) == "OUTER_" then return MIRROR[ap:sub(7)] or "CENTER" end
    return "CENTER"
  elseif regionType == "aurabar" then
    if ap:sub(1, 5) == "ICON_" then ap = ap:sub(6) elseif ap:sub(1, 6) == "INNER_" then ap = ap:sub(7) end
    return MIRROR[ap] and ap or "CENTER"
  end
  return MIRROR[ap] or "CENTER"
end

-- Anchors one of our objects and remembers the anchors (att.anchors), so a packed Dynamic Group child can
-- move it onto its host. They are never read back: the game answers GetPoint with secrets on a text it
-- binds to an aura (seen 2026-10-02, "cannot be indexed with secret keys"), even out of combat.
function Engine.SetAnchors(att, obj, pts)
  obj:ClearAllPoints()
  for _, p in ipairs(pts) do obj:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
  if att then
    att.anchors = att.anchors or setmetatable({}, { __mode = "k" })
    att.anchors[obj] = pts
  end
end

local function StyleShadowText(region, fs, sub, isCount, att)
  local font = (sub.text_font and LSM:Fetch("font", sub.text_font)) or STANDARD_TEXT_FONT
  local ft = sub.text_fontType
  local flags = (not ft or ft == "None") and "" or ft:gsub("|?SLUG", "")
  fs:SetFont(font, sub.text_fontSize or 12, flags)
  if isCount and sub.text_color then fs:SetTextColor(unpack(sub.text_color)) end -- duration colour is engine-owned
  if sub.text_shadowColor then fs:SetShadowColor(unpack(sub.text_shadowColor)) end
  fs:SetShadowOffset(sub.text_shadowXOffset or 0, sub.text_shadowYOffset or 0)
  fs:SetJustifyH(sub.text_justify or "CENTER")
  -- WA picks the frame and points (it only ever clears and sets points): taken down on a stand-in, then
  -- set on ours. The offsets WA's options set are text_anchorX/YOffset (SubText.lua); anchorX/YOffset is unused.
  local rec = { pts = {} }
  setmetatable(rec, { __index = function() return function() end end })
  function rec.ClearAllPoints(self) self.pts = {} end
  function rec.SetPoint(self, p, rel, rp, x, y) self.pts[#self.pts + 1] = { p, rel, rp or p, x or 0, y or 0 } end
  function rec.SetAllPoints(self, rel)
    self.pts = { { "TOPLEFT", rel, "TOPLEFT", 0, 0 }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 } }
  end
  region:AnchorSubRegion(rec, "point", sub.anchor_point, ResolveSelfPoint(sub, region.regionType),
    tonumber(sub.text_anchorXOffset) or 0, tonumber(sub.text_anchorYOffset) or 0)
  Engine.SetAnchors(att, fs, rec.pts)
end

-- region.subRegions is built from data.subRegions skipping unknown types (RegionPrototype), so walk
-- both with the same rule. Remembers the live WA sub-texts that read aura state (%p / %s): in slot
-- mode they are mirrored onto engine-fed shadows, in every mode the WA originals are hidden.
local function MirrorTexts(att, region, data, useShadows)
  local s = att.shadows
  att.mirrored = {}
  local haveP, haveS, haveN
  local ri = 0
  for _, sub in ipairs(data.subRegions or {}) do
    if Private.subRegionTypes[sub.type] then
      ri = ri + 1
      local live = region.subRegions and region.subRegions[ri]
      if sub.type == "subtext" and sub.text_visible ~= false then
        local txt = Trim(sub.text_text)
        if not haveP and txt == "%p" then
          haveP = true
          if live then att.mirrored[live] = true end
          if useShadows then StyleShadowText(region, s.duration, sub, false, att); s.duration:Show() end
        elseif not haveS and txt == "%s" then
          haveS = true
          if live then att.mirrored[live] = true end
          if useShadows then StyleShadowText(region, s.count, sub, true, att); s.count:SetAlpha(1) end
        elseif not haveN and txt == "%n" and useShadows and s.name then
          haveN = true
          if live then att.mirrored[live] = true end
          StyleShadowText(region, s.name, sub, true, att); s.name:SetAlpha(1)
        end
      end
    end
  end
  if useShadows then
    if not haveP then s.duration:Hide() end     -- Shown is not a secret aspect of the duration text
    if not haveS then s.count:SetAlpha(0) end   -- Shown IS secret on the count text; Alpha is ours
    if s.name and not haveN then s.name:SetAlpha(0) end
  end
end

-- Glow. WA's glow sits on the WA region, which stays visible while the engine decides what is drawn,
-- so it would frame an empty spot. Engine-driven icons draw a STATIC glow instead, in the element that
-- follows the aura: the slot button (Found), the missing clip (Missing), a curve-driven text (time
-- left). Texture and coordinates are LibCustomGlow's outer button glow; WA's glow colour, scale and
-- offsets apply, the animation does not. 'Show On: Always' keeps WA's own glow (the icon is always there).
local GLOW_TEX = "Interface\\SpellActivationOverlay\\IconAlert"
local GLOW_TC = { 0.00781250, 0.50781250, 0.27734375, 0.52734375 }
local GLOW_SIZE = 1.4

-- The first glow of the display that is switched on: { r, g, b, a, scale, x, y } or nil.
local function GlowSpec(data)
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subglow" and sub.glow then
      local c = sub.useGlowColor and sub.glowColor or nil
      return { c and c[1] or 1, c and c[2] or 1, c and c[3] or 1, c and c[4] or 1,
               tonumber(sub.glowScale) or 1, tonumber(sub.glowXOffset) or 0, tonumber(sub.glowYOffset) or 0 }
    end
  end
end

local function GlowSize(w, h, g)
  return math.floor(w * GLOW_SIZE * g[5] + 0.5), math.floor(h * GLOW_SIZE * g[5] + 0.5)
end

-- How far a glow reaches past the icon: the missing clip must be that much larger to show it whole.
local function GlowMargin(w, h, g)
  if not g then return 0 end
  local gw, gh = GlowSize(w, h, g)
  return math.ceil(math.max(gw - w, gh - h) / 2 + math.max(math.abs(g[6]), math.abs(g[7]))) + 1
end

local function StyleGlowTexture(tex, anchor, w, h, g)
  if not g then tex:Hide(); return end
  local gw, gh = GlowSize(w, h, g)
  tex:SetTexture(GLOW_TEX)
  tex:SetTexCoord(GLOW_TC[1], GLOW_TC[2], GLOW_TC[3], GLOW_TC[4])
  tex:SetVertexColor(g[1], g[2], g[3], g[4])
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", anchor, "CENTER", g[6], g[7])
  tex:SetSize(gw, gh)
  tex:Show()
end

-- WA sub-regions that would show at the wrong time while engine-driven: every glow that is switched on
-- (replaced by the static glow) and, when asked, the border. Joins att.mirrored, so OnLayout hides them
-- and TurnOff gives them back. Only ones that are on: handing back cannot show one that was off.
local function HideStaticDecor(att, region, data, withBorder)
  local ri = 0
  for _, sub in ipairs(data.subRegions or {}) do
    if Private.subRegionTypes[sub.type] then
      ri = ri + 1
      local live = region.subRegions and region.subRegions[ri]
      if live and ((sub.type == "subglow" and sub.glow)
                   or (withBorder and sub.type == "subborder" and sub.border_visible ~= false)) then
        att.mirrored[live] = true
      end
    end
  end
end

-- Animated glow. Where a clip follows the aura part (the Missing clip, or the Found clip of a second
-- container), a frame of ours inside the clip carries the WA glow, drawn by ForeverGlow.lua with the WA
-- glow's own settings, so every glow type animates and shows only with that part. Nothing may be
-- re-parented into these clips (they inherit Blizzard's ban on layout scripts from the aura container):
-- WA's glow frame and LibCustomGlow's pooled frames are refused (tried 2026-09-27), so ForeverGlow
-- creates everything in place. The static glow above stays as the fallback, and a failure is reported.
local function FG() return Private.ForeverGlow end   -- ForeverGlow.lua loads after this file

-- The display's first glow that is switched on (its WA settings), or nil.
local function GlowSub(data)
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subglow" and sub.glow then return sub end
  end
end

-- How far a WA glow reaches past the icon: the clip must be that much larger to show it whole.
local function AnimatedGlowMargin(w, h, sub)
  if not sub then return 0 end
  local off = math.max(math.abs(tonumber(sub.glowXOffset) or 0), math.abs(tonumber(sub.glowYOffset) or 0))
  return math.ceil(math.max(w, h) * 0.5 * (tonumber(sub.glowScale) or 1)) + off + (tonumber(sub.glowThickness) or 1) + 4
end

-- anchor: the rect the glow goes around (default the whole display). Each holder keeps its anchor for
-- good, so a display whose glow moves to another area gets another holder (see PGLOW_KEYS).
local function GlowHolder(att, key, clip, anchor)
  local holder = att[key]
  if not holder then
    holder = CreateFrame("Frame", nil, clip)   -- created in the clip: never re-parented
    -- a plain rect, so its size is readable
    Engine.SetAnchors(att, holder, { { "TOPLEFT", anchor or att.host, "TOPLEFT" }, { "BOTTOMRIGHT", anchor or att.host, "BOTTOMRIGHT" } })
    holder:Hide()
    att[key] = holder
  end
  holder:SetFrameLevel(clip:GetFrameLevel() + 2)
  return holder
end

local function StopAnimatedGlow(holder)
  if holder and FG() then pcall(FG().Stop, holder) end
end

-- Holders in the Found clip: the whole display, a Progress Bar's icon, a Progress Bar's bar.
local PGLOW_KEYS = { "pglow", "pglowIcon", "pglowBar" }
local function StopPresentGlows(att, except)
  for _, k in ipairs(PGLOW_KEYS) do
    if k ~= except then StopAnimatedGlow(att[k]) end
  end
end

local glowReported = false
-- Starts sub's glow on holder; false when it cannot (the caller then draws the static glow).
local function StartAnimatedGlow(holder, sub, w, h)
  if not (sub and FG()) then return false end
  local ok, started = pcall(FG().Start, holder, sub, w, h)
  if not ok then
    pcall(FG().Stop, holder)
    if not glowReported then
      glowReported = true
      local handler = geterrorhandler and geterrorhandler()
      if handler then handler("engine (animated glow): " .. tostring(started)) end
    end
    return false
  end
  return started and true or false
end

-- Margin of the Missing clip: room for the static glow texture or the animated glow, whichever is used.
local function ClipMargin(w, h, data, staticGlow)
  if not staticGlow then return 0 end
  return math.max(GlowMargin(w, h, staticGlow), AnimatedGlowMargin(w, h, GlowSub(data)))
end

-- Found Progress Bars and Progress Textures: WA's glow, animated, in the Found clip, so it shows only
-- with the aura. The area is WA's own: the whole display, or on a bar its icon or bar ('fg', the moving
-- fill, has no plain size: drawn around the bar). WA's own glow is hidden while engine-driven.
local function GlowArea(att, region, data, sub)
  if att.isBar then
    local area = sub and sub.anchor_area or "bar"
    if area == "icon" and region.icon then return "pglowIcon", region.icon end
    if (area == "bg" or area == "fg") and region.bar and region.bar.bg then return "pglowBar", region.bar.bg end
  end
  return "pglow", att.host
end

local function ApplyFoundGlow(att, region, data, plan)
  local sub = plan.mode == "active" and not plan.noGlow and GlowSub(data) or nil
  local key, anchor = GlowArea(att, region, data, sub)
  StopPresentGlows(att, key)
  local animated = false
  if sub and att.pclipShown then
    local w, h = RegionSize(anchor)
    animated = StartAnimatedGlow(GlowHolder(att, key, att.pclip, anchor), sub, w, h)
  end
  if not animated then StopAnimatedGlow(att[key]) end
  HideStaticDecor(att, region, data, att.isTex or att.isPic or att.isMotion or att.isModel)   -- textures: the border too (always shown)
end

-- Progress Bars: the engine drives its own StatusBar inside the slot button (SetDurationBar ->
-- StatusBar:SetTimerDuration with the aura's duration). WA's own bar, background and icon are hidden
-- while the display is engine-driven, and restored when it stops being so.
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function SetBarVisuals(region, shown)
  local bar = region.bar
  if bar then bar:SetShown(shown); if bar.bg then bar.bg:SetShown(shown) end end
  if region.iconFrame then region.iconFrame:SetShown(shown) end
  if region.secretBar then region.secretBar:SetShown(shown) end
end

local function ApplyBarLook(att, region, data, plan)
  local s = att.shadows
  local fg = region.bar and region.bar.fg
  local atlas = fg and fg.GetAtlas and fg:GetAtlas()
  if atlas == "" then atlas = nil end
  local tex = (not atlas) and fg and fg:GetTexture() or nil
  s.bar:SetStatusBarTexture(atlas and WHITE or (tex or WHITE))
  if atlas then
    pcall(function() s.bar:GetStatusBarTexture():SetAtlas(atlas) end)
    s.barBg:SetAtlas(atlas)
  else
    s.barBg:SetTexture(tex or WHITE)
  end
  local c = data.barColor or { 1, 0, 0, 1 }
  s.bar:SetStatusBarColor(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1)
  -- WA's 'Enable Gradient': the bar colour fades into Bar Color 2 across the fill (AuraBar.lua
  -- SetForegroundGradient). Without it, both ends get the bar colour, which clears an earlier gradient.
  local fill = s.bar:GetStatusBarTexture()
  if fill and fill.SetGradient and CreateColor then
    local c2 = (data.enableGradient and data.barColor2) or c
    pcall(fill.SetGradient, fill, data.gradientOrientation == "VERTICAL" and "VERTICAL" or "HORIZONTAL",
      CreateColor(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 1), CreateColor(c2[1] or 1, c2[2] or 0, c2[3] or 0, c2[4] or 1))
  end
  local bc = data.backgroundColor or { 0, 0, 0, 0.5 }
  s.barBg:SetVertexColor(bc[1] or 0, bc[2] or 0, bc[3] or 0, bc[4] or 0.5)
  local o = data.orientation or "HORIZONTAL"
  local vertical = o:find("VERTICAL") ~= nil
  s.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
  s.bar:SetReverseFill(o:find("INVERSE") ~= nil)
  pcall(s.bar.SetRotatesTexture, s.bar, vertical)
  pcall(s.barBg.SetRotation, s.barBg, 0)
  -- WA drains the bar as the aura runs out unless 'Inverse'
  local dirs = Enum and Enum.StatusBarTimerDirection
  local dir = dirs and (data.inverse and dirs.ElapsedTime or dirs.RemainingTime)
  if att.barDirection ~= dir then
    local ok = pcall(att.button.SetDurationBar, att.button, s.bar, { direction = dir })
    if ok then att.barDirection = dir end
  end
  s.icon:SetShown(data.icon and true or false)
  if region.icon then s.icon:SetTexCoord(region.icon:GetTexCoord()) end
  local ic = data.icon_color or { 1, 1, 1, 1 }
  s.icon:SetVertexColor(ic[1] or 1, ic[2] or 1, ic[3] or 1, ic[4] or 1)
  pcall(s.icon.SetDesaturation, s.icon, data.desaturate and 1 or 0)
  MirrorTexts(att, region, data, true)
  ApplyFoundGlow(att, region, data, plan)
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

-- Progress Textures. Straight ones: the slot button carries an invisible StatusBar the engine fills like a
-- Progress Bar's, and a clipping frame anchored to that bar's fill texture, so the clip grows and shrinks
-- with the aura's time left (geometry driven by a value we cannot read, like the Missing clip). Inside
-- the clip sits a copy of WA's foreground at full progress, with WA's own texture coordinates (crop,
-- rotation, mirror), so the clip reveals it the way WA's vertex offsets do; 'Compress' squeezes the copy
-- into the fill instead. Full circles: the game's cooldown swipe on the same button, drawn with the
-- display's texture. Its edge only ever moves clockwise, so it draws 'Anticlockwise' (and 'Clockwise' +
-- 'Inverse'); the other two, and part circles, are arc pieces revealed by the same bar (Engine.StyleArc).
-- The background is drawn whole. WA's own textures are hidden (alpha, which WA never touches on them) while the display is engine-driven.
local TEX_FILL = { HORIZONTAL = { "HORIZONTAL", false }, HORIZONTAL_INVERSE = { "HORIZONTAL", true },
                   VERTICAL = { "VERTICAL", false }, VERTICAL_INVERSE = { "VERTICAL", true } }

local function SetTexVisuals(region, shown)
  local a = shown and 1 or 0
  for _, lin in ipairs({ region.foreground, region.background }) do
    if lin and lin.texture then lin.texture:SetAlpha(a) end
  end
  for _, lin in ipairs(region.extraTextures or {}) do
    if lin.texture then lin.texture:SetAlpha(a) end
  end
  for _, spin in ipairs({ region.foregroundSpinner, region.backgroundSpinner }) do
    for _, tex in ipairs(spin and spin.textures or {}) do tex:SetAlpha(a) end
  end
  for _, spin in ipairs(region.extraSpinners or {}) do
    for _, tex in ipairs(spin.textures or {}) do tex:SetAlpha(a) end
  end
end

-- the swipe runs the right way round: WA's arc shrinks towards its start when it drains clockwise
function Engine.SwipeMatchesDirection(data)
  return (data.orientation == "ANTICLOCKWISE") == (not data.inverse)
end

local function StyleTexCopy(tex, coord, data, path, desaturate, color, circular)
  local wrap = data.textureWrapMode
  Private.SetTextureOrAtlas(tex, path, wrap, wrap)
  pcall(tex.SetDesaturated, tex, desaturate and true or false)
  pcall(tex.SetBlendMode, tex, data.blendMode or "BLEND")
  pcall(tex.SetRotation, tex, (tonumber(data.auraRotation) or 0) / 180 * math.pi)
  -- WA's texture at full progress: SetFull, then WA's transform (ProgressTexture.lua modify; the
  -- circular base leaves out the centre shift)
  coord:SetFull()
  coord:Transform(1 + (tonumber(data.crop_x) or 0.41), 1 + (tonumber(data.crop_y) or 0.41),
    tonumber(data.rotation) or 0, data.mirror and true or false, false,
    circular and 0 or -1 * (tonumber(data.user_x) or 0), circular and 0 or tonumber(data.user_y) or 0)
  coord:Apply()
  tex:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function StyleSwipe(swipe, data)
  local c = data.foregroundColor or { 1, 1, 1, 1 }
  local path = data.foregroundTexture
  pcall(swipe.SetSwipeTexture, swipe, tonumber(path) or path, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
  pcall(swipe.SetSwipeColor, swipe, c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
  -- WA's crop: texture coordinates spread 1.4142 / (1 + crop) around the centre
  local hx = 0.7071 / (1 + (tonumber(data.crop_x) or 0.41))
  local hy = 0.7071 / (1 + (tonumber(data.crop_y) or 0.41))
  local lx, rx = 0.5 - hx, 0.5 + hx
  if data.mirror then lx, rx = rx, lx end
  if CreateVector2D then
    pcall(swipe.SetTexCoordRange, swipe, CreateVector2D(lx, 0.5 - hy), CreateVector2D(rx, 0.5 + hy))
  end
  -- the arc starts at the start angle (clockwise from the top); 'Rotation' turns the whole texture
  local rad = ((tonumber(data.auraRotation) or 0) - (tonumber(data.startAngle) or 0)) / 180 * math.pi
  pcall(swipe.SetRotation, swipe, rad)
  -- not reversed, the swipe covers the time left; 'Inverse' draws the time gone
  pcall(swipe.SetReverse, swipe, data.inverse and true or false)
end

-- Circular Progress Textures the swipe cannot draw: part circles (Start / End Angle), and full circles
-- that WA drains the other way round than the swipe. The invisible StatusBar is laid out W px wide with
-- its right end at the button's centre, so its fill edge travels W px over the aura's duration. WA's arc
-- is cut into N pieces, each in its own clipping frame that ends o_j px right of the fill edge: the frame
-- covers the button while the fill is above (j + 0.5) / N and lies left of it below. So the arc grows and
-- shrinks piece by piece, driven by a value we never read, in any direction. Each piece is WA's own wedge
-- (TextureCoords:SetAngle, as its spinner draws them); the background is a WA spinner with the whole arc.
do
  local MAX_PIECES = 144

  -- WA's arc: start and end angle clockwise from the top, end above start, at most 360 apart
  local function Angles(data)
    local s = (tonumber(data.startAngle) or 0) % 360
    local e = (tonumber(data.endAngle) or 360) % 360
    if e <= s then e = e + 360 end
    return s, e
  end

  function Engine.UsesArcPieces(data)
    if not IsCircular(data) then return false end
    local s, e = Angles(data)
    return e - s < 360 or not Engine.SwipeMatchesDirection(data)
  end

  -- pieces small enough that the arc's end moves about 1.5 px per step (WA moves it every frame)
  function Engine.ArcPieces(data)
    local s, e = Angles(data)
    local w, h = tonumber(data.width) or 64, tonumber(data.height) or 64
    local step = math.max(1, math.deg(1.5 / math.max(1, math.max(w, h) / 2)))
    local n = math.max(math.ceil((e - s) / 90), math.min(MAX_PIECES, math.ceil((e - s) / step)))
    return n, (e - s) / n
  end

  local function Piece(att, s, j)
    local p = s.arcPieces[j]
    if p then return p end
    local clip = CreateFrame("Frame", nil, att.button)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(att.button:GetFrameLevel() + 1)
    local tex = clip:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(att.button)
    pcall(tex.SetSnapToPixelGrid, tex, false)
    pcall(tex.SetTexelSnappingBias, tex, 0)
    p = { clip = clip, tex = tex, coord = Private.TextureCoords.create(tex) }
    s.arcPieces[j] = p
    return p
  end

  local function ShowArc(s, n, shown)
    for j, p in ipairs(s.arcPieces or {}) do p.clip:SetAlpha((shown and j <= n) and 1 or 0) end
    for _, tex in ipairs(s.arcBg and s.arcBg.textures or {}) do tex:SetAlpha(shown and 1 or 0) end
  end

  -- pieces on: lays the bar out wide and styles the arc; off: hides it and puts the bar back on the button
  function Engine.StyleArc(att, data, on)
    local s, button = att.shadows, att.button
    if not on then
      if s.arcPieces then ShowArc(s, 0, false) end
      if att.arcW then
        local ok = pcall(function()
          s.bar:ClearAllPoints()
          s.bar:SetAllPoints(button)
        end)
        if ok then att.arcW = nil end
      end
      return
    end
    s.arcPieces = s.arcPieces or {}
    local a1, a2 = Angles(data)
    local span = a2 - a1
    local n = Engine.ArcPieces(data)
    local w, h = tonumber(data.width) or 64, tonumber(data.height) or 64
    -- a piece passes from hidden to shown while the fill edge moves the drawing's width (rotation
    -- included), a quarter of a step at most
    local ext = 1.5 * math.max(w, h)
    local W = math.min(200000, math.max(20000, 4 * n * ext))
    if att.arcW ~= W then
      local ok = pcall(function()
        s.bar:ClearAllPoints()
        s.bar:SetPoint("TOPRIGHT", button, "TOP")
        s.bar:SetPoint("BOTTOMRIGHT", button, "BOTTOM")
        s.bar:SetWidth(W)
      end)
      if ok then att.arcW = W; att.arcH = nil end
    end
    pcall(s.bar.SetOrientation, s.bar, "HORIZONTAL")
    pcall(s.bar.SetReverseFill, s.bar, false)
    local c = data.foregroundColor or { 1, 1, 1, 1 }
    local cropX, cropY = 1 + (tonumber(data.crop_x) or 0.41), 1 + (tonumber(data.crop_y) or 0.41)
    local texRot, mirror = tonumber(data.rotation) or 0, data.mirror and true or false
    local rad = (tonumber(data.auraRotation) or 0) / 180 * math.pi
    local acw = data.orientation == "ANTICLOCKWISE"
    local relay = att.arcH ~= h
    for j = 1, n do
      local p = Piece(att, s, j)
      local lo, hi
      if acw then lo, hi = a2 - span * j / n, a2 - span * (j - 1) / n
      else lo, hi = a1 + span * (j - 1) / n, a1 + span * j / n end
      local tex = p.tex
      Private.SetTextureOrAtlas(tex, data.foregroundTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      pcall(tex.SetDesaturated, tex, data.desaturateForeground and true or false)
      pcall(tex.SetBlendMode, tex, data.blendMode or "BLEND")
      pcall(tex.SetRotation, tex, rad)
      tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
      p.coord:SetAngle(w, h, lo, hi)
      p.coord:Transform(cropX, cropY, texRot, mirror, false)
      p.coord:Apply()
      local o = W * (1 - (j - 0.5) / n)
      if relay or p.o ~= o then
        local ok = pcall(function()
          p.clip:ClearAllPoints()
          p.clip:SetPoint("TOPLEFT", s.bar, "TOPLEFT", 0, h)
          p.clip:SetPoint("BOTTOMRIGHT", s.fill, "BOTTOMRIGHT", o, -h)
        end)
        p.o = ok and o or nil
      end
    end
    att.arcH = h
    -- the background: WA's spinner with the whole arc
    if not s.arcBg then s.arcBg = Private.CircularProgressTextureBase.create(button, "BACKGROUND", 1) end
    Private.CircularProgressTextureBase.modify(s.arcBg, {
      crop_x = cropX, crop_y = cropY, mirror = mirror, texRotation = texRot,
      texture = data.sameTexture and data.foregroundTexture or data.backgroundTexture,
      blendMode = data.blendMode or "BLEND", desaturated = data.desaturateBackground and true or false,
      auraRotation = rad, width = w, height = h, offset = tonumber(data.backgroundOffset) or 2 })
    local bc = data.backgroundColor or { 0.5, 0.5, 0.5, 0.5 }
    s.arcBg:SetColor(bc[1] or 1, bc[2] or 1, bc[3] or 1, bc[4] or 1)
    s.arcBg:SetProgress(a1, a2)
    ShowArc(s, n, true)
  end
end

local function ApplyTexLook(att, region, data, plan)
  local s = att.shadows
  local circular = IsCircular(data)
  s.texFgCoord = s.texFgCoord or Private.TextureCoords.create(s.texFg)
  s.texBgCoord = s.texBgCoord or Private.TextureCoords.create(s.texBg)
  local fgPath = data.foregroundTexture
  StyleTexCopy(s.texFg, s.texFgCoord, data, fgPath, data.desaturateForeground, data.foregroundColor or { 1, 1, 1, 1 }, circular)
  StyleTexCopy(s.texBg, s.texBgCoord, data, data.sameTexture and fgPath or data.backgroundTexture,
    data.desaturateBackground, data.backgroundColor or { 0.5, 0.5, 0.5, 0.5 }, circular)
  local off = tonumber(data.backgroundOffset) or 2
  if att.texBgOffset ~= off then
    local ok = pcall(function()
      s.texBg:ClearAllPoints()
      s.texBg:SetPoint("BOTTOMLEFT", att.button, "BOTTOMLEFT", -off, -off)
      s.texBg:SetPoint("TOPRIGHT", att.button, "TOPRIGHT", off, off)
    end)
    if ok then att.texBgOffset = off end
  end
  local pieces = Engine.UsesArcPieces(data)
  s.texClip:SetAlpha(circular and 0 or 1)
  s.swipe:SetAlpha((circular and not pieces) and 1 or 0)
  s.texBg:SetAlpha(pieces and 0 or 1)
  Engine.StyleArc(att, data, pieces)
  if circular and not pieces then
    StyleSwipe(s.swipe, data)
  else
    if not circular then
      local compress = data.compress and true or false
      if att.texCompress ~= compress then
        local ok = pcall(function()
          s.texFg:ClearAllPoints()
          s.texFg:SetAllPoints(compress and s.fill or att.button)
        end)
        if ok then att.texCompress = compress end
      end
      local fill = TEX_FILL[data.orientation or "VERTICAL"] or TEX_FILL.VERTICAL
      pcall(s.bar.SetOrientation, s.bar, fill[1])
      pcall(s.bar.SetReverseFill, s.bar, fill[2])
    end
    -- WA drains the texture as the aura runs out unless 'Inverse'
    local dirs = Enum and Enum.StatusBarTimerDirection
    local dir = dirs and (data.inverse and dirs.ElapsedTime or dirs.RemainingTime)
    if att.barDirection ~= dir then
      local ok = pcall(att.button.SetDurationBar, att.button, s.bar, { direction = dir })
      if ok then att.barDirection = dir end
    end
  end
  MirrorTexts(att, region, data, true)
  ApplyFoundGlow(att, region, data, plan)
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

-- Texture displays: a copy of WA's texture, on the slot button (Found) or in the Missing clip. WA turns
-- and mirrors it with texture coordinates, so the copy takes them from WA's own texture. WA's texture is
-- hidden (alpha, which WA never sets on it) while the display is engine-driven.
local function SetPicVisuals(region, shown)
  local wa = region.texture and region.texture.texture
  if wa and wa.SetAlpha then wa:SetAlpha(shown and 1 or 0) end
end

local function CopyPictureLook(tex, region, data)
  local wrap = data.textureWrapMode
  Private.SetTextureOrAtlas(tex, data.texture, wrap, wrap)
  local wa = region.texture and region.texture.texture
  if wa and wa.GetTexCoord then tex:SetTexCoord(wa:GetTexCoord()) end
  pcall(tex.SetDesaturated, tex, data.desaturate and true or false)
  pcall(tex.SetBlendMode, tex, data.blendMode or "BLEND")
  local c = data.color or { 1, 1, 1, 1 }
  tex:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
end

local function ApplyPicLook(att, region, data, plan)
  CopyPictureLook(att.shadows.pic, region, data)
  MirrorTexts(att, region, data, true)
  ApplyFoundGlow(att, region, data, plan)
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

-- Stop Motion displays: Textures that animate. WA steps through a sheet of frames from a script, and
-- scripts never run inside the engine's aura buttons; the game's own FlipBook animation plays the same
-- sheet (rows, columns, frames, as WA reads them), shown with the button (Found) or in the Missing clip.
-- Loop and Bounce play on their own; Once and Progress need a start (the aura appearing, its time) that
-- an animation inside the button cannot be given. The background is WA's still frame, copied.
-- (functions on Engine: the file's main chunk is close to Lua 5.1's limit of 200 locals)
do
  local P1 = "%.x(%d+)y(%d+)f(%d+)%.[tb][gl][ap]"
  local P2 = "%.x(%d+)y(%d+)f(%d+)w(%d+)h(%d+)W(%d+)H(%d+)%.[tb][gl][ap]"

  -- rows, columns, frame count and (when the sheet does not fill the file) the frame size in pixels
  local function Sheet(tex, frames, rows, columns, fileW, fileH, frameW, frameH)
    if type(tex) ~= "string" and type(tex) ~= "number" then return nil end
    local td = WA.StopMotion and WA.StopMotion.texture_data and WA.StopMotion.texture_data[tex]
    if td then
      if not (td.rows and td.columns) then return nil end           -- numbered files: one texture per frame
      return { count = td.count, rows = td.rows, columns = td.columns, fw = 0, fh = 0 }
    end
    local s = tostring(tex)
    local r, c, f = s:lower():match(P1)
    if r then return { count = tonumber(f), rows = tonumber(r), columns = tonumber(c), fw = 0, fh = 0 } end
    local r2, c2, f2, fw, fh, W, H = s:match(P2)
    if r2 then
      fw, fh, W, H = tonumber(fw), tonumber(fh), tonumber(W), tonumber(H)
      return { count = tonumber(f2), rows = tonumber(r2), columns = tonumber(c2),
               fw = (W > 0 and fw > 0) and fw or 0, fh = (H > 0 and fh > 0) and fh or 0 }
    end
    rows, columns, frames = tonumber(rows), tonumber(columns), tonumber(frames)
    if not (rows and columns and frames and rows > 0 and columns > 0 and frames > 0) then return nil end
    fileW, fileH, frameW, frameH = tonumber(fileW) or 0, tonumber(fileH) or 0, tonumber(frameW) or 0, tonumber(frameH) or 0
    return { count = frames, rows = rows, columns = columns,
             fw = (fileW > 0 and frameW > 0) and frameW or 0, fh = (fileH > 0 and frameH > 0) and frameH or 0 }
  end

  -- What the game can play of a Stop Motion display, or nil + why (plain data).
  function Engine.MotionSheet(data)
    local anim = data.animationType or "loop"
    if anim ~= "loop" and anim ~= "bounce" then
      return nil, T("its animation is '%s': only Loop and Bounce play on their own while the aura is up (Once and Progress need a start the game does not give addons)"):format(tostring(anim))
    end
    if (tonumber(data.startPercent) or 0) > 0 then
      return nil, T("its animation starts after the first frame (Start above 0%)")
    end
    local sh = Sheet(data.foregroundTexture, data.customForegroundFrames, data.customForegroundRows,
      data.customForegroundColumns, data.customForegroundFileWidth, data.customForegroundFileHeight,
      data.customForegroundFrameWidth, data.customForegroundFrameHeight)
    if not sh or not sh.count or sh.count < 1 then
      return nil, T("its texture is not a sheet of frames the game can play (numbered texture files, or a custom texture without rows, columns and frames)")
    end
    local last = sh.count - 1
    sh.frames = math.max(1, math.min(sh.count, math.floor((tonumber(data.endPercent) or 1) * last) + 1))
    return sh
  end

  function Engine.SetMotionVisuals(region, shown)
    for _, part in ipairs({ region.foreground, region.background }) do
      if part and part.texture and part.texture.SetAlpha then part.texture:SetAlpha(shown and 1 or 0) end
    end
  end

  -- a still texture and an animated one (a FlipBook on a looping animation group) in parent
  function Engine.NewMotion(parent, anchor)
    local m = {}
    m.bg = parent:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints(anchor)
    m.fg = parent:CreateTexture(nil, "ARTWORK")
    m.fg:SetAllPoints(anchor)
    for _, t in ipairs({ m.bg, m.fg }) do
      pcall(t.SetSnapToPixelGrid, t, false)
      pcall(t.SetTexelSnappingBias, t, 0)
    end
    m.ag = m.fg:CreateAnimationGroup()
    m.flip = m.ag:CreateAnimation("FlipBook")
    return m
  end

  local function SetSheetTexture(tex, path)
    if type(path) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(path) then
      tex:SetAtlas(path)
    else
      tex:SetTexture(path)
      tex:SetTexCoord(0, 1, 0, 1)
    end
  end

  -- styles m like the WA region: the animated sheet with WA's colour, desaturation and blend mode, and
  -- WA's still background frame (texture and coordinates taken from WA's own background)
  function Engine.StyleMotion(m, region, data)
    local sh = Engine.MotionSheet(data)
    if not sh then return false end
    m.ag:Stop()
    SetSheetTexture(m.fg, data.foregroundTexture)
    local c = data.foregroundColor or { 1, 1, 1, 1 }
    m.fg:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    pcall(m.fg.SetDesaturated, m.fg, data.desaturateForeground and true or false)
    pcall(m.fg.SetBlendMode, m.fg, data.blendMode or "BLEND")
    m.flip:SetFlipBookRows(sh.rows)
    m.flip:SetFlipBookColumns(sh.columns)
    m.flip:SetFlipBookFrames(sh.frames)
    m.flip:SetFlipBookFrameWidth(sh.fw)
    m.flip:SetFlipBookFrameHeight(sh.fh)
    local rate = tonumber(data.frameRate) or 15
    if rate <= 0 then rate = 15 end
    m.flip:SetDuration(sh.frames / rate)
    m.ag:SetLooping(data.animationType == "bounce" and "BOUNCE" or "REPEAT")
    local wbg = region.background and region.background.texture
    if wbg and not data.hideBackground then
      local atlas = wbg.GetAtlas and wbg:GetAtlas()
      if atlas and atlas ~= "" then m.bg:SetAtlas(atlas) else m.bg:SetTexture(wbg:GetTexture()) end
      m.bg:SetTexCoord(wbg:GetTexCoord())
      local b = data.backgroundColor or { 0.5, 0.5, 0.5, 0.5 }
      m.bg:SetVertexColor(b[1] or 1, b[2] or 1, b[3] or 1, b[4] or 1)
      pcall(m.bg.SetDesaturated, m.bg, data.desaturateBackground and true or false)
      pcall(m.bg.SetBlendMode, m.bg, data.blendMode or "BLEND")
      m.bg:Show()
    else
      m.bg:Hide()
    end
    m.ag:Play(data.inverse and true or false)
    return true
  end
end

-- Model displays: WA shows a pooled PlayerModel on the region (PreShow) and releases it on hide. While
-- engine-driven, WA's model and border are hidden and our own PlayerModel is set up the same way (file or
-- display ID, position or transform, rotation, zoom, animation, alpha): on the slot button (Found) or in
-- the Missing clip. A unit's model is left to WA: it follows its unit through events, and scripts never
-- run inside the engine's buttons.
do
  function Engine.ModelSheet(data)
    if data.modelIsUnit then
      return nil, T("it shows a unit's model, which follows the unit through events, and scripts cannot run inside the engine's frame; pick a model file or display ID")
    end
    if not tonumber(data.model_fileId) then
      return nil, T("its model is not a file or display ID number")
    end
    return true
  end

  -- WA's own model and border: hidden while engine-driven (Show / Hide; WA sets the model's alpha itself)
  function Engine.SetModelVisuals(region, shown)
    if region.model and region.model.SetShown then region.model:SetShown(shown) end
    if region.border and region.border.SetShown then
      local data = shown and WA.GetData(region.id)
      region.border:SetShown(shown and data and data.border and true or false)
    end
  end

  function Engine.NewModel(parent)
    local m = CreateFrame("PlayerModel", nil, parent)
    pcall(m.SetKeepModelOnHide, m, true)
    return m
  end

  -- as Model.lua's ConfigureModel, for a model file or display ID
  function Engine.StyleModel(m, data)
    WA.SetModel(m, nil, data.model_fileId, false, data.modelDisplayInfo)
    pcall(m.SetPortraitZoom, m, data.portraitZoom and 1 or 0)
    pcall(m.ClearTransform, m)
    local rad = math.rad
    if data.api then
      pcall(m.MakeCurrentCameraCustom, m)
      pcall(Private.ModelSetTransformFixed, m, (tonumber(data.model_st_tx) or 0) / 1000, (tonumber(data.model_st_ty) or 0) / 1000,
        (tonumber(data.model_st_tz) or 0) / 1000, rad(tonumber(data.model_st_rx) or 0), rad(tonumber(data.model_st_ry) or 0),
        rad(tonumber(data.model_st_rz) or 0), (tonumber(data.model_st_us) or 40) / 1000)
    else
      pcall(m.SetPosition, m, tonumber(data.model_z) or 0, tonumber(data.model_x) or 0, tonumber(data.model_y) or 0)
      pcall(m.SetFacing, m, rad(tonumber(data.rotation) or 0))
    end
    pcall(m.SetAnimation, m, data.advance and (tonumber(data.sequence) or 1) or 0)
    m:SetAlpha(type(data.alpha) == "number" and data.alpha or 1)
    m:Show()
  end
end

-- Text displays: WA's text is hidden (alpha; WA colours it with SetTextColor, never SetAlpha) and drawn
-- again on the slot button (Found) or in the Missing clip, in WA's font, size, outline, shadow, justify
-- and width. Plain text is copied as WA shows it (raid markers included); %p / %s / %n are the engine's
-- own duration text, stack count and spell name.
-- (a do-block: the file's main chunk is close to Lua 5.1's limit of 200 locals)
local SetTextVisuals, ApplyTextLook, StyleUnderlayText, PlainText, FitTextHost
do
  -- Hidden by its Shown state, never by alpha: on a FontString, SetTextColor sets the alpha too, and WA
  -- recolours its text whenever an animation starts (ColorAnim), which made the text show again (seen in
  -- game 2026-10-02 with /fdtext mark). WA never calls Show / Hide on a Text display's text.
  function SetTextVisuals(region, shown)
    if region.text and region.text.SetShown then region.text:SetShown(shown) end
  end

  local function StyleTextLike(fs, region, data, anchor, isEngineText)
    local font, size, flags = region.text:GetFont()
    -- SLUG (vector) text ignores the Missing clip (seen in game 2026-10-01: an OUTLINE|SLUG text stayed
    -- visible while the aura was up); the copy is drawn as a normal font, like the icons' texts
    flags = tostring(flags or ""):gsub("[|,]?%s*SLUG", ""):gsub("^[|,]%s*", "")
    if font then fs:SetFont(font, size, flags) end
    if not isEngineText then
      local c = data.color or { 1, 1, 1, 1 }
      fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if data.shadowColor then fs:SetShadowColor(unpack(data.shadowColor)) end
    local slug = data.outline == "OUTLINE|SLUG" or data.outline == "THICKOUTLINE|SLUG"
    fs:SetShadowOffset(slug and 0 or (data.shadowXOffset or 1), slug and 0 or (data.shadowYOffset or -1))
    local justify = data.justify or "LEFT"
    fs:SetJustifyH(justify)
    if data.automaticWidth == "Fixed" then
      fs:SetWidth(tonumber(data.fixedWidth) or 200)
      fs:SetWordWrap(data.wordWrap == "WordWrap")
    else
      fs:SetWidth(0)
      fs:SetWordWrap(true)
    end
    fs:ClearAllPoints()
    fs:SetPoint(justify, anchor, justify)
  end

  -- WA's own text as shown, for plain text (no state in it, so readable)
  function PlainText(region, data)
    local ok, t = pcall(region.text.GetText, region.text)
    if ok and type(t) == "string" and not issecretvalue(t) and t ~= "" then return t end
    return tostring(data.displayText or "")
  end

  local function ConstantColorCurve(c)
    local cc = C_CurveUtil.CreateColorCurve()
    cc:SetType(Enum.LuaCurveType.Step)
    cc:AddPoint(0, CreateColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1))
    return cc
  end

  -- %n / %i of the one spell a display tracks: its name and icon (plain data, safe time)
  local function StaticSymbol(key, tp, plan)
    local sp = tp.single
    local id = (sp and sp.id) or (plan and plan.firstId)
    if key == "n" then
      if sp and sp.name then return sp.name end
      local ok, nm = pcall(C_Spell.GetSpellName, id)
      if ok and type(nm) == "string" and not issecretvalue(nm) then return nm end
    elseif key == "i" then
      local ok, tex = pcall(C_Spell.GetSpellTexture, id)
      if ok and tex and not issecretvalue(tex) then return ("|T%s:0|t"):format(tostring(tex)) end
    end
    return ""
  end

  -- The display text with its static parts filled in (raid markers like WA); dyn(key) supplies the rest.
  local function TextWith(tp, plan, dyn)
    local out = {}
    for _, part in ipairs(tp.parts) do
      if part.lit then
        out[#out + 1] = WA.ReplaceRaidMarkerSymbols and WA.ReplaceRaidMarkerSymbols(part.lit) or part.lit
      elseif part.key == "n" or part.key == "i" then
        out[#out + 1] = StaticSymbol(part.key, tp, plan)
      else
        out[#out + 1] = dyn(part.key)
      end
    end
    return table.concat(out)
  end

  local function HasSymbols(tp)
    for _, part in ipairs(tp.parts) do if part.sym then return true end end
    return false
  end

  -- Time inside other words: Blizzard's own aura duration format (Blizzard_AuraContainerShared.lua), so a
  -- "Corruption: %p" text counts like a lone "%p" one: whole seconds up to 90 s, then minutes, hours, days.
  local auraDurationFormatter
  local function AuraDurationFormatter()
    if auraDurationFormatter ~= nil then return auraDurationFormatter or nil end
    auraDurationFormatter = false
    if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then return nil end
    local ok, f = pcall(C_StringUtil.CreateSecondsFormatter)
    if not ok or not f then return nil end
    local E = Enum or {}
    local I = E.SecondsFormatterInterval or {}
    pcall(f.SetDefaultAbbreviation, f, E.SecondsFormatterAbbreviation and E.SecondsFormatterAbbreviation.OneLetter or 2)
    pcall(f.SetRounding, f, E.SecondsFormatterRounding and E.SecondsFormatterRounding.Truncate or 1)
    pcall(f.SetCanRoundUpLastUnit, f, true)
    if I.Seconds then pcall(f.SetMinInterval, f, I.Seconds) end
    if I.Seconds and I.Minutes and C_CurveUtil and C_CurveUtil.CreateCurve then
      local okC, curve = pcall(C_CurveUtil.CreateCurve)
      if okC and curve then
        curve:SetType(Enum.LuaCurveType.Step)
        curve:AddPoint(0, I.Seconds)
        curve:AddPoint(1 + 1.5 * 60, I.Minutes)
        if I.Hours then curve:AddPoint(1 + 1.5 * 3600, I.Hours) end
        if I.Days then curve:AddPoint(1 + 1.5 * 86400, I.Days) end
        pcall(f.SetMaxIntervalCurve, f, curve)
      end
    end
    pcall(f.SetDesiredUnitCount, f, 1)
    auraDurationFormatter = f
    return f
  end

  -- Stacks inside other words: one rule ("Stacks: %d"). WA leaves %s empty at 0 stacks; a rule without a
  -- number would do that too, but Blizzard formats inside its own aura update, where a bad format would
  -- break the display in combat, so this keeps to one plain %d (0 stacks read "Stacks: 0").
  local stackFormatters = {}
  local function StackFormatter(prefix, suffix)
    local key = prefix .. "\1" .. suffix
    if stackFormatters[key] ~= nil then return stackFormatters[key] or nil end
    stackFormatters[key] = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
    if not ok or not f then return nil end
    local function esc(x) return (x:gsub("%%", "%%%%")) end
    local R = (Enum and Enum.NumericRuleFormatRounding) or {}
    local okB = pcall(f.SetBreakpoints, f, {
      { threshold = 0, step = 1, rounding = R.Down or 2, format = esc(prefix) .. "%d" .. esc(suffix) },
    })
    if okB then stackFormatters[key] = f end
    return stackFormatters[key] or nil
  end

  function ApplyTextLook(att, region, data, plan)
    local s = att.shadows
    local tp = TextPlan(data) or { kind = "plain", parts = { { lit = tostring(data.displayText or "") } } }
    local kind = tp.kind
    local fs = ({ plain = s.label, dur = s.duration, count = s.count, name = s.name })[kind]
    StyleTextLike(fs, region, data, att.button, kind ~= "plain")
    local c = data.color or { 1, 1, 1, 1 }
    if kind == "plain" then
      fs:SetText(HasSymbols(tp) and TextWith(tp, plan, function() return "" end) or PlainText(region, data))
      fs:Show()
    elseif kind == "dur" then
      -- the duration text's colour is the engine's: a constant colour curve carries WA's
      local P = (Enum and Enum.DurationTextBindingProperty) or {}
      local opts = {}
      if C_CurveUtil and CreateColor then
        opts.textColor = { curve = ConstantColorCurve(c), property = P.RemainingDuration or 0 }
      end
      if not (tp.pure and tp.parts[1].key == "p") then
        local fmt, comps = AuraDurationFormatter(), {}
        local formatString = TextWith(tp, plan, function(key)
          comps[#comps + 1] = { property = key == "t" and (P.TotalDuration or 4) or (P.RemainingDuration or 0), formatter = fmt }
          return "{}"
        end)
        if fmt then opts.textFormat = { formatString = formatString, components = comps } end
      end
      pcall(att.button.SetDurationText, att.button, s.duration, opts)
    elseif kind == "count" then
      local f
      if not tp.pure then
        local whole = TextWith(tp, plan, function() return "\1" end)
        local at = whole:find("\1", 1, true)
        f = StackFormatter(whole:sub(1, at - 1), whole:sub(at + 1))
      end
      pcall(att.button.SetApplicationCount, att.button, s.count, f and { formatter = f } or nil)
      fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
      fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if kind ~= "plain" then s.label:Hide() end
    if kind == "dur" then s.duration:Show() else s.duration:Hide() end -- Shown is not secret on it
    s.count:SetAlpha(kind == "count" and 1 or 0)                      -- Shown IS secret on these two
    s.name:SetAlpha(kind == "name" and 1 or 0)
    MirrorTexts(att, region, data, false)
    ApplyFoundGlow(att, region, data, plan)
    pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
  end

  -- plain text in the Missing clip; created in place, like everything in these clips
  function StyleUnderlayText(att, region, data, plan)
    local s = att.shadows
    if not s.underText then s.underText = s.clip:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
    StyleTextLike(s.underText, region, data, att.host, false)
    local tp = TextPlan(data)
    s.underText:SetText((tp and HasSymbols(tp)) and TextWith(tp, plan, function() return "" end) or PlainText(region, data))
    s.underText:Show()
  end

  -- A Missing text is clipped by a frame the size of the display. WA sizes a Text display from its own
  -- text when it is set up, and that can come out as nothing (seen in game 2026-10-01/02: an OUTLINE|SLUG
  -- text, a degenerate clip, the text never hidden). So the engine measures its own copy and gives the
  -- host that size, anchored where WA anchors its text (the justify point). Found texts need no clip
  -- and keep the display's rect.
  function FitTextHost(att, region, data, plan)
    local host = att.host
    if plan.mode ~= "missing" then
      if att.textW then
        att.textW, att.textH = nil, nil
        pcall(function() host:ClearAllPoints(); host:SetAllPoints(region) end)
      end
      return
    end
    local s = att.shadows
    if not s.measure then s.measure = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end
    -- invisible by colour (set after the styling, which colours it), without outline or shadow
    StyleTextLike(s.measure, region, data, host, false)
    local font, size = s.measure:GetFont()
    if font then s.measure:SetFont(font, size, "") end
    s.measure:SetTextColor(1, 1, 1, 0)
    s.measure:SetShadowColor(0, 0, 0, 0)
    local tp = TextPlan(data)
    s.measure:SetText((tp and HasSymbols(tp)) and TextWith(tp, plan, function() return "" end) or PlainText(region, data))
    local w = data.automaticWidth == "Fixed" and (tonumber(data.fixedWidth) or 200) or s.measure:GetStringWidth()
    local h = s.measure:GetStringHeight()
    if issecretvalue(w) or issecretvalue(h) or not w or not h then return end
    w, h = math.max(math.ceil(w), 1), math.max(math.ceil(h), 1)
    if w == att.textW and h == att.textH then return end
    local justify = data.justify or "LEFT"
    local ok = pcall(function()
      host:ClearAllPoints()
      host:SetPoint(justify, region, justify)
      host:SetSize(w, h)
    end)
    if ok then att.textW, att.textH = w, h end
  end
end

local function ApplySlotLook(att, region, data, plan)
  if att.isText then return ApplyTextLook(att, region, data, plan) end
  if att.isPic then return ApplyPicLook(att, region, data, plan) end
  if att.isMotion or att.isModel then
    if att.isModel then Engine.StyleModel(att.shadows.model, data)
    else Engine.StyleMotion(att.shadows.motion, region, data) end
    MirrorTexts(att, region, data, true)
    ApplyFoundGlow(att, region, data, plan)
    pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
    return
  end
  if att.isBar then return ApplyBarLook(att, region, data, plan) end
  if att.isTex then return ApplyTexLook(att, region, data, plan) end
  local s = att.shadows
  s.icon:SetTexCoord(region.icon:GetTexCoord())     -- WA already applied zoom/aspect/offset to its own texture
  pcall(s.icon.SetDesaturation, s.icon, data.desaturate and 1 or 0)
  local col = data.color or { 1, 1, 1, 1 }
  s.icon:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
  local cd = s.cooldown
  cd:SetAlpha(data.cooldown and 1 or 0)
  pcall(cd.SetDrawSwipe, cd, data.cooldownSwipe ~= false)
  pcall(cd.SetDrawEdge, cd, data.cooldownEdge and true or false)
  pcall(cd.SetReverse, cd, not data.inverse)                   -- Icon.lua: WA reverses unless 'inverse'
  pcall(cd.SetHideCountdownNumbers, cd, (not data.cooldown) or data.cooldownTextDisabled or false)
  local found = plan.mode == "active"                  -- Always: the WA icon is always there, so is WA's glow
  local glowSub = found and not plan.noGlow and GlowSub(data) or nil
  local gw, gh = RegionSize(region)
  local animated = glowSub and att.pclipShown and StartAnimatedGlow(GlowHolder(att, "pglow", att.pclip), glowSub, gw, gh)
  if not animated then StopAnimatedGlow(att.pglow) end
  if s.glow then
    local w, h = RegionSize(region)
    StyleGlowTexture(s.glow, att.button, w, h, (found and not plan.noGlow and not animated) and GlowSpec(data) or nil)
  end
  MirrorTexts(att, region, data, true)
  if found then HideStaticDecor(att, region, data, false) end
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

-- The display's own icon choice: the manual icon when one is set, else the first tracked spell's
-- texture (plain data, safe time).
local function DisplayTexture(data, firstId)
  local tex
  if data.iconSource == 0 and data.displayIcon and data.displayIcon ~= "" then
    tex = data.displayIcon
  elseif firstId then
    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(firstId)
  end
  if issecretvalue(tex) then tex = nil end
  return tex or data.displayIcon or 134400
end

-- The underlay copies the WA icon's static look.
local function ApplyUnderlayLook(att, region, data, plan, noGlow)
  local u = att.shadows.underlay
  if att.isText then
    -- plain text in the Missing clip; created in place, like everything in these clips
    StyleUnderlayText(att, region, data, plan)
    u:SetAlpha(0)
  elseif att.isPic then
    CopyPictureLook(u, region, data)
  elseif att.isMotion then
    -- the sheet plays in the Missing clip; created in place, like everything in these clips
    local sh = att.shadows
    if not sh.umotion then sh.umotion = Engine.NewMotion(sh.clip, att.host) end
    Engine.StyleMotion(sh.umotion, region, data)
    u:SetAlpha(0)
  elseif att.isModel then
    -- in the Missing clip, and hung on the clip's own edges: zero wide while the aura is present, even
    -- if the game drew a model past a clipping frame
    local sh, m = att.shadows, att.groupM or 0
    if not sh.umodel then sh.umodel = Engine.NewModel(sh.clip) end
    sh.umodel:ClearAllPoints()
    sh.umodel:SetPoint("TOPLEFT", sh.clip, "TOPLEFT", m, -m)
    sh.umodel:SetPoint("BOTTOMRIGHT", sh.clip, "BOTTOMRIGHT", -m, m)
    Engine.StyleModel(sh.umodel, data)
    u:SetAlpha(0)
  else
    local tex = DisplayTexture(data, plan.firstId)
    if type(tex) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tex) then
      u:SetAtlas(tex)
    else
      u:SetTexture(tex)
    end
    u:SetTexCoord(region.icon:GetTexCoord())
    pcall(u.SetDesaturation, u, data.desaturate and 1 or 0)
    local col = data.color or { 1, 1, 1, 1 }
    u:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
  end
  local glowSub = not noGlow and GlowSub(data) or nil
  local gw, gh = RegionSize(region)
  local animated = glowSub and att.shadows.clip and StartAnimatedGlow(GlowHolder(att, "mglowHolder", att.shadows.clip), glowSub, gw, gh)
  if not animated then StopAnimatedGlow(att.mglowHolder) end
  if att.shadows.mglow then
    local w, h = RegionSize(region)
    StyleGlowTexture(att.shadows.mglow, att.host, w, h, (not noGlow and not animated) and GlowSpec(data) or nil)
  end
  MirrorTexts(att, region, data, false)
  HideStaticDecor(att, region, data, att.isPic or att.isMotion or att.isModel)   -- a Texture's border would frame an empty spot
end

local function SetMirroredShown(att, shown)
  if not att.mirrored then return end
  for sub in pairs(att.mirrored) do
    if sub.SetShown then sub:SetShown(shown) end
  end
end

function Engine.OnLayout(region)          -- after every ApplyFrameLevel (Expand/modify/group/anchor)
  local att = attachments[region]
  if not (att and att.active) then return end
  SetMirroredShown(att, false)
  if att.isBar then SetBarVisuals(region, false)
  elseif att.isTex then SetTexVisuals(region, false)
  elseif att.isPic then SetPicVisuals(region, false)
  elseif att.isMotion then Engine.SetMotionVisuals(region, false)
  elseif att.isModel then Engine.SetModelVisuals(region, false)
  elseif att.isText then SetTextVisuals(region, false)
  elseif (att.kind == "group" or att.kind == "composite") and region.icon then region.icon:Hide() end
  if att.kind == "composite" and att.want and att.want.parts and att.want.parts.found and region.icon then region.icon:Hide() end
end

local function InPreview()
  return (WA.IsPaused and WA.IsPaused()) or (WA.IsOptionsOpen and WA.IsOptionsOpen())
end

local function DisableKind(att, kind)
  local c = att.container
  if kind == "slot" and att.slotBuilt then pcall(c.SetAuraSlotEnabled, c, KEY, false) end
  if kind == "slot" then DisablePresentClip(att) end
  if (kind == "group" or kind == "composite") and att.groupBuilt then
    pcall(c.SetAuraGroupEnabled, c, KEY, false)
    if att.shadows.clip then att.shadows.clip:Hide() end
  end
  if kind == "composite" then
    DisablePresentClip(att)
    for key, rs in pairs(att.rslots or {}) do
      pcall(c.SetAuraSlotEnabled, c, key, false)
      if rs.clip then pcall(rs.clip.Hide, rs.clip) end
    end
  end
end

---------------------------------------------------------------------------- time left (composite plans)
-- "Less than X s left" without reading the time. Each Remaining Time part gets its own slot on the same
-- aura. The slot's duration text is handed a Step colour curve over the remaining duration (visible
-- below X, alpha 0 above) and a text that is only the display's icon as an inline texture, so the icon
-- appears and disappears with the curve. The game evaluates the curve; nothing of ours reads it. A
-- second slot on the same aura carries the %p countdown with the same curve. Proven in game 2026-09-27
-- (Serpent Sting on a mob, in combat, ForeverDevInfo /fdremain).
local REMAIN_EPS = 0.001

local function RemainCurve(op, x, r, g, b, a)
  local cc = C_CurveUtil.CreateColorCurve()
  cc:SetType(Enum.LuaCurveType.Step)          -- a point rules from its own x on ("exact matches promote")
  local on, off = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
  if op == "<" then
    if x > 0 then cc:AddPoint(0, on); cc:AddPoint(x, off) else cc:AddPoint(0, off) end
  elseif op == "<=" then
    cc:AddPoint(0, on); cc:AddPoint(x + REMAIN_EPS, off)
  elseif op == ">" then
    cc:AddPoint(0, off); cc:AddPoint(x + REMAIN_EPS, on)
  else -- ">="
    if x > 0 then cc:AddPoint(0, off); cc:AddPoint(x, on) else cc:AddPoint(0, on) end
  end
  return cc
end

-- The display's icon as inline text, with WA's zoom (the icon's texcoords) and colour.
local TEXCOORD_UNITS = 1024
local function IconMarkup(tex, w, h, region, col)
  if type(tex) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tex) then
    return ("|A:%s:%d:%d|a"):format(tex, h, w)
  end
  local ulx, uly, _, lly, urx = region.icon:GetTexCoord()
  local function u(v) return math.floor((tonumber(v) or 0) * TEXCOORD_UNITS + 0.5) end
  local function c(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 1)) * 255 + 0.5) end
  return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t"):format(tostring(tex), h, w,
    TEXCOORD_UNITS, TEXCOORD_UNITS, u(ulx), u(urx), u(uly), u(lly), c(col[1]), c(col[2]), c(col[3]))
end

-- The WA sub-text that shows the time left, if the display has one (same rule as MirrorTexts).
local function CountdownSub(data)
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subtext" and sub.text_visible ~= false and Trim(sub.text_text) == "%p" then return sub end
  end
end

local function BuildRemainSlot(att, key, part)
  local host, c = att.host, att.container
  local rs = {}
  local ok, button = pcall(c.AddAuraSlot, c, key, part.filterString, {
    candidateFilters = part.candidate,
    initializeFrame = function(button)
      -- Runs synchronously inside AddAuraSlot, BEFORE DenyTaintedAccessWhenAurasAreSecret is applied.
      button:ClearAllPoints()
      button:SetAllPoints(host)
      button:SetFrameLevel(c:GetFrameLevel())
      pcall(button.SetMouseClickEnabled, button, false)
      pcall(button.EnableMouseMotion, button, false)
      rs.fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      rs.fs:SetPoint("CENTER")
      pcall(rs.fs.SetWordWrap, rs.fs, false)
    end,
  })
  if not ok or not button or not rs.fs then
    WA.prettyPrint(("%s: engine time-left slot failed: %s"):format(tostring(att.region.id), tostring(button)))
    att.broken = true
    return nil
  end
  rs.button, rs.filter, rs.pkey = button, part.filterString, part.key
  return rs
end

-- A display that shows its icon both while the aura is missing and while it runs out lets the user pick
-- where the static glow goes (data.foreverEngineGlowPart: "both" | "remaining" | "missing").
local function GlowParts(data, plan)
  local g = GlowSpec(data)
  if not g then return nil, nil end
  local both = plan.parts.missing and #plan.parts.remaining > 0
  local where = both and data.foreverEngineGlowPart or "both"
  return (where ~= "remaining") and g or nil, (where ~= "missing") and g or nil
end

function Engine.HasGlowPartChoice(data)
  local plan = Engine.Classify(data)
  return plan and plan.parts and plan.parts.missing and #plan.parts.remaining > 0 and GlowSpec(data) ~= nil or false
end

-- Late clip: an animated glow that appears when X seconds are left (clip geometry proven 2026-09-28,
-- /fdlate). The engine fills a StatusBar by the aura's remaining time (SetDurationBar); with the aura's
-- total duration known, the bar is K px per second wide and placed so the fill edge passes a fixed point
-- exactly when X seconds are left, and the clip spans from the fill edge to that point: zero wide above X,
-- open below. The bar must live in the aura button, but the clip must NOT: aura buttons carry
-- UntrustedScriptExecution, which stops every script of their children, so an OnUpdate-driven glow never
-- moves there. The clip is a child of our present clip instead (closed while the aura is absent) and only
-- ANCHORS to the fill; DisableUntrustedLayoutScriptsTemplate makes that anchor legal.
local LATE_K = 2000   -- px per second

local function BuildLateSlot(att, key, part, x, total, region)
  local host, c = att.host, att.container
  local ls = {}
  local ok, button = pcall(c.AddAuraSlot, c, key, part.filterString, {
    candidateFilters = part.candidate,
    initializeFrame = function(button)
      button:ClearAllPoints()
      button:SetAllPoints(host)
      button:SetFrameLevel(c:GetFrameLevel())
      pcall(button.SetMouseClickEnabled, button, false)
      pcall(button.EnableMouseMotion, button, false)
      local w, h = RegionSize(region)
      local m = AnimatedGlowMargin(w, h, GlowSub(att.data or {}))
      local bar = CreateFrame("StatusBar", nil, button)
      bar:SetSize(total * LATE_K, h + 2 * m)
      bar:SetPoint("LEFT", button, "RIGHT", m - x * LATE_K, 0)
      bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
      bar:SetStatusBarColor(0, 0, 0, 0)
      bar:SetAlpha(0)                               -- never drawn: only its fill edge serves as an anchor
      bar:SetFrameLevel(button:GetFrameLevel())
      local dirs = Enum and Enum.StatusBarTimerDirection
      button:SetDurationBar(bar, { direction = dirs and dirs.RemainingTime })
      -- outside the button (scripts run there), anchored to the fill inside it
      local clip = CreateFrame("Frame", nil, att.pclip, "DisableUntrustedLayoutScriptsTemplate")
      clip:SetClipsChildren(true)
      clip:SetFrameLevel(att.pclip:GetFrameLevel() + 1)
      clip:SetPoint("TOPLEFT", bar:GetStatusBarTexture(), "TOPRIGHT")
      clip:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", x * LATE_K, 0)
      ls.bar, ls.clip, ls.m = bar, clip, m
    end,
  })
  if not ok or not button or not ls.clip then
    WA.prettyPrint(("%s: engine late glow failed: %s"):format(tostring(att.region.id), tostring(button)))
    return nil
  end
  ls.button, ls.filter, ls.pkey, ls.x, ls.total = button, part.filterString, part.key, x, total
  return ls
end

-- Slot keys: feR<i> = the icon of Remaining Time part i, feG<i> = its static glow, feT<i> = its %p countdown,
-- feL<i> = its late clip (animated glow).
local LEVEL_OF = { R = 0, G = 1, T = 2, L = 3 }
local function EnsureComposite(att, region, data, plan)
  local c = att.container
  att.data = data
  local missingGlow, remainGlow = GlowParts(data, plan)
  local glow = remainGlow
  if plan.parts.missing then
    local w, h = RegionSize(region)
    if not EnsureGroup(att, region, plan.parts.missing, ClipMargin(w, h, data, missingGlow)) then return false end
  else
    DisableKind(att, "group")
  end
  -- Found + time left: the Found slot draws the live aura as in a single plan
  if plan.parts.found then
    local f = plan.parts.found
    if not att.slotBuilt then
      if not BuildSlot(att, region, f) then return false end
      att.slotFilter, att.slotKey = f.filterString, f.key
    else
      if att.slotFilter ~= f.filterString then c:SetAuraSlotFilterString(KEY, f.filterString); att.slotFilter = f.filterString end
      if att.slotKey ~= f.key then c:SetAuraSlotCandidateFilters(KEY, f.candidate); att.slotKey = f.key end
      c:SetAuraSlotEnabled(KEY, true)
    end
  elseif att.slotBuilt then
    pcall(c.SetAuraSlotEnabled, c, KEY, false)
  end
  att.rslots = att.rslots or {}
  local used = {}
  local withText = CountdownSub(data) ~= nil and not plan.parts.found
  local late = plan.parts.lateTotal
  -- one time-left part gets the animated glow: its late clip sits in the present clip of that part's aura
  local lateIdx
  if glow and late then
    for i, rp in ipairs(plan.parts.remaining) do
      if (rp.op == "<" or rp.op == "<=") and rp.x < late then lateIdx = i; break end
    end
  end
  if lateIdx then
    local w, h = RegionSize(region)
    local part = plan.parts.remaining[lateIdx].part
    att.pclipShown = EnsurePresentClip(att, region, part, AnimatedGlowMargin(w, h, GlowSub(data)))
    if not att.pclipShown then lateIdx = nil end
  end
  if not lateIdx then DisablePresentClip(att) end
  att.lateActive = lateIdx ~= nil
  for i, rp in ipairs(plan.parts.remaining) do
    local keys = {}
    if not plan.parts.found then keys[#keys + 1] = "feR" .. i end
    local animated = i == lateIdx
    if animated then
      keys[#keys + 1] = "feL" .. i
    elseif glow then
      keys[#keys + 1] = "feG" .. i
    end
    if withText then keys[#keys + 1] = "feT" .. i end
    for _, key in ipairs(keys) do
      used[key] = true
      local rs = att.rslots[key]
      -- a late clip is built for one X and total: rebuild when they change
      if rs and key:sub(3, 3) == "L" and (rs.x ~= rp.x or rs.total ~= late) then
        pcall(c.RemoveAuraSlot, c, key)
        StopAnimatedGlow(rs.glowHolder)
        if rs.clip then pcall(rs.clip.Hide, rs.clip) end
        att.rslots[key], rs = nil, nil
      end
      if not rs then
        if key:sub(3, 3) == "L" then rs = BuildLateSlot(att, key, rp.part, rp.x, late, region)
        else rs = BuildRemainSlot(att, key, rp.part) end
        if not rs then return false end
        att.rslots[key] = rs
      else
        if rs.filter ~= rp.part.filterString then c:SetAuraSlotFilterString(key, rp.part.filterString); rs.filter = rp.part.filterString end
        if rs.pkey ~= rp.part.key then c:SetAuraSlotCandidateFilters(key, rp.part.candidate); rs.pkey = rp.part.key end
        c:SetAuraSlotEnabled(key, true)
      end
      if rs.clip then pcall(rs.clip.Show, rs.clip) end
    end
  end
  for key, rs in pairs(att.rslots) do
    if not used[key] then
      pcall(c.SetAuraSlotEnabled, c, key, false)
      if rs.glowHolder then StopAnimatedGlow(rs.glowHolder) end
      if rs.clip then pcall(rs.clip.Hide, rs.clip) end
    end
  end
  att.rslotsUsed = used
  return true
end

local function SetRemainLevels(att)
  if not (att.rslots and att.container) then return end
  local base = att.container:GetFrameLevel()
  for key, rs in pairs(att.rslots) do
    pcall(rs.button.SetFrameLevel, rs.button, base + (LEVEL_OF[key:sub(3, 3)] or 0))
    -- the late clip hangs on the aura button's bar and is forbidden to us while an aura is shown (even
    -- GetFrameLevel): its levels come from the present clip, which is ours to ask, and are best effort
    if rs.clip and att.pclip then
      local pl = att.pclip:GetFrameLevel()
      pcall(rs.clip.SetFrameLevel, rs.clip, pl + 1)
      if rs.glowHolder then pcall(rs.glowHolder.SetFrameLevel, rs.glowHolder, pl + 2) end
    end
  end
end

local function ApplyCompositeLook(att, region, data, plan)
  local missingGlow, remainGlow = GlowParts(data, plan)
  if plan.parts.missing then ApplyUnderlayLook(att, region, data, plan.parts.missing, not missingGlow) end
  if plan.parts.found then
    -- the Found slot looks like a single Found plan, but its glow belongs to the time-left part
    ApplySlotLook(att, region, data, { mode = "active", filterString = plan.parts.found.filterString, noGlow = true })
    StopAnimatedGlow(att.pglow)
    if att.shadows.glow then att.shadows.glow:Hide() end
  end
  local glowSub = GlowSub(data)
  for i, rp in ipairs(plan.parts.remaining) do
    local ls = att.rslotsUsed["feL" .. i] and att.rslots["feL" .. i]
    if ls and glowSub and remainGlow then
      if not ls.glowHolder then
        ls.glowHolder = CreateFrame("Frame", nil, ls.clip)
        ls.glowHolder:SetAllPoints(att.host)
      end
      if att.pclip then pcall(ls.glowHolder.SetFrameLevel, ls.glowHolder, att.pclip:GetFrameLevel() + 2) end
      local gw, gh = RegionSize(region)
      if not StartAnimatedGlow(ls.glowHolder, glowSub, gw, gh) then StopAnimatedGlow(ls.glowHolder) end
    elseif ls then
      StopAnimatedGlow(ls.glowHolder)
    end
  end
  local w, h = RegionSize(region)
  local col = data.color or { 1, 1, 1, 1 }
  local property = (Enum.DurationTextBindingProperty and Enum.DurationTextBindingProperty.RemainingDuration) or 0
  local psub = CountdownSub(data)
  for i, rp in ipairs(plan.parts.remaining) do
    local ri = att.rslots["feR" .. i]
    if ri then
      ri.fs:SetFont(STANDARD_TEXT_FONT, 12, "")
      ri.button:SetDurationText(ri.fs, {
        textFormat = { formatString = IconMarkup(DisplayTexture(data, rp.part.firstId), w, h, region, col), components = {} },
        textColor = { curve = RemainCurve(rp.op, rp.x, 1, 1, 1, col[4] or 1), property = property },
      })
    end
    local rg = att.rslotsUsed["feG" .. i] and att.rslots["feG" .. i]
    local g = remainGlow
    if rg and g then
      local gw, gh = GlowSize(w, h, g)
      local u = TEXCOORD_UNITS
      rg.fs:SetFont(STANDARD_TEXT_FONT, 12, "")
      rg.fs:ClearAllPoints()
      rg.fs:SetPoint("CENTER", att.host, "CENTER", g[6], g[7])
      rg.button:SetDurationText(rg.fs, {
        textFormat = { formatString = ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t"):format(GLOW_TEX, gh, gw, u, u,
          math.floor(GLOW_TC[1] * u + 0.5), math.floor(GLOW_TC[2] * u + 0.5), math.floor(GLOW_TC[3] * u + 0.5),
          math.floor(GLOW_TC[4] * u + 0.5), math.floor(g[1] * 255 + 0.5), math.floor(g[2] * 255 + 0.5),
          math.floor(g[3] * 255 + 0.5)), components = {} },
        textColor = { curve = RemainCurve(rp.op, rp.x, 1, 1, 1, g[4]), property = property },
      })
    end
    local rt = att.rslotsUsed["feT" .. i] and att.rslots["feT" .. i]
    if rt and psub then
      StyleShadowText(region, rt.fs, psub, false, att)
      local tc = psub.text_color or { 1, 1, 1, 1 }
      rt.button:SetDurationText(rt.fs, {
        textColor = { curve = RemainCurve(rp.op, rp.x, tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1), property = property },
      })
    end
  end
  if not plan.parts.found then MirrorTexts(att, region, data, false) end   -- WA's own %p/%s/%n would read aura state: hidden
  HideStaticDecor(att, region, data, true, true)  -- WA's glow (the clips have it) and the border: hidden
end

---------------------------------------------------------------------------- range gate
-- The alpha itself is owned by ForeverGate.lua (Private.ForeverGate), which also serves the power
-- gates: one wrapper on the region's SetAlpha, so range and "hide while full" combine instead of
-- fighting over the same widget method. Here: sample the range and hand the answer over.
local rangeTicker
local function Gate() return Private.ForeverGate end   -- ForeverGate.lua loads after this file

local function SampleRange(att)
  local ok, r = pcall(C_Spell.IsSpellInRange, att.rangeSpell, att.unit)
  att.inRange = nil
  if ok then att.inRange = r end                     -- true / false / nil, untested: a secret must reach the gate
  if att.gateInstalled then Gate().SetRange(att.region, att.inRange) end
end

local function InstallGate(att)
  if att.gateInstalled then return true end
  if not (Gate() and Gate().SetRange(att.region, nil)) then return false end
  att.gateInstalled = true
  return true
end

local function RemoveGate(att)
  if not att.gateInstalled then return end
  att.gateInstalled, att.inRange = false, nil
  if Gate() then Gate().ClearRange(att.region) end
end

local function RangeTick()
  local any = false
  for _, att in pairs(attachments) do
    if att.active and att.gateInstalled and att.rangeSpell then any = true; SampleRange(att) end
  end
  if not any and rangeTicker then rangeTicker:Cancel(); rangeTicker = nil end
end

local function EnsureRangeTicker()
  if not rangeTicker then rangeTicker = C_Timer.NewTicker(0.2, RangeTick) end   -- upstream's range cadence
end

-- Every way out of "on" (off, preview, a failed engine build) hands the region back the same way.
local soundReported = false

-- How long registering took, for the record (SavedVariables foreverEngine.soundStats): nothing here
-- runs per frame, only when a display's sounds or its spell list change.
local function SoundStats(count, ms)
  local sv = SV()
  if not sv then return end
  sv.foreverEngine = sv.foreverEngine or {}
  local st = sv.foreverEngine.soundStats or {}
  sv.foreverEngine.soundStats = st
  st.runs = (st.runs or 0) + 1
  st.lastCount, st.lastMs = count, math.floor(ms * 100 + 0.5) / 100
  if count > (st.maxCount or 0) then st.maxCount, st.maxCountMs = count, st.lastMs end
end

-- Does the game keep aura sounds over a /reload? The ids of the last session are saved at logout; the
-- first id the game hands out now tells: a counter that went on means the old sounds are still there,
-- so they are removed (they are ours); a counter that started again means the game cleared them, and
-- the old numbers may belong to other addons' new sounds, so they are left alone.
local staleChecked = false
local function CheckStaleSounds(firstNewId)
  if staleChecked then return end
  staleChecked = true
  local sv = SV()
  local fe = sv and sv.foreverEngine
  local old = fe and fe.soundIDs
  if type(old) ~= "table" or #old == 0 then return end
  local maxOld = 0
  for _, sid in ipairs(old) do
    if type(sid) == "number" and sid > maxOld then maxOld = sid end
  end
  if firstNewId > maxOld then
    for _, sid in ipairs(old) do pcall(C_UnitAuras.RemoveAuraSound, sid) end
    fe.soundRegistry = ("kept over a reload: %d old sounds removed"):format(#old)
  else
    fe.soundRegistry = "cleared by the game on reload"
  end
  fe.soundIDs = nil
end

local function ClearSounds(att)
  for _, sid in ipairs(att.soundIDs or {}) do
    pcall(C_UnitAuras.RemoveAuraSound, sid)
  end
  att.soundIDs, att.soundSig, att.soundRouted = nil, nil, nil
end

-- WeakAuras' own playback of a routed sound would play at login / reload; skip it while engine-driven.
local function HookSoundPlay(att, region)
  if not region.SoundPlay or region.SoundPlay == att.soundWrapper then return end
  local orig = region.SoundPlay
  att.soundWrapper = function(self, options, ...)
    local a = attachments[self]
    if a and a.active and a.soundRouted then
      local d = WA.GetData(self.id)
      local acts = d and d.actions
      if acts and ((options == acts.start and a.soundRouted.start) or (options == acts.finish and a.soundRouted.finish)) then
        return
      end
    end
    return orig(self, options, ...)
  end
  region.SoundPlay = att.soundWrapper
end

local function ApplySounds(att, region, data, plan)
  local routes = SoundRoutes(plan)
  local api = C_UnitAuras and C_UnitAuras.AddAuraSound and Enum.UnitAuraSoundTrigger
  local ids = plan.ids or {}
  local idSig
  if #ids == 0 and plan.nameless then
    local n, fromTables, sum
    ids, n, fromTables, sum = SeenIds(plan)
    idSig = ("%d:%d"):format(n, sum)          -- a thousand ids: a checksum, not a string of them
  else
    idSig = table.concat(ids, ",")
  end
  local want, sig = {}, { plan.unit, idSig }
  if routes and api then
    for _, when in ipairs({ "start", "finish" }) do
      local acts = data.actions and data.actions[when]
      local src = SoundSource(acts)
      if src then
        local channel = (acts.sound_channel and acts.sound_channel ~= "") and acts.sound_channel or "Master"
        want[#want + 1] = { when = when, trigger = routes[when], src = src, channel = channel }
        sig[#sig + 1] = table.concat({ when, routes[when], tostring(src.soundFileName or src.soundFileID), channel }, "/")
      end
    end
  end
  sig = table.concat(sig, ";")
  if att.soundSig == sig then return end
  ClearSounds(att)
  att.soundSig, att.soundIDs, att.soundRouted = sig, {}, {}
  if #want == 0 then return end
  HookSoundPlay(att, region)
  local t0 = debugprofilestop and debugprofilestop()
  local info = { unitToken = plan.unit, throttleSeconds = 0.5 }   -- one table for the whole run
  for _, w in ipairs(want) do
    local okCount, failed = 0, 0
    -- nothing known yet: silent, rather than WeakAuras playing it when the options close
    if #ids == 0 then att.soundRouted[w.when] = true end
    info.outputChannel, info.soundFileName, info.soundFileID = w.channel, w.src.soundFileName, w.src.soundFileID
    local trigger = Enum.UnitAuraSoundTrigger[w.trigger]
    for _, id in ipairs(ids) do
      info.spellID = id
      local ok, sid = pcall(C_UnitAuras.AddAuraSound, trigger, info)
      if ok and type(sid) == "number" and not issecretvalue(sid) then
        att.soundIDs[#att.soundIDs + 1] = sid
        okCount = okCount + 1
        if okCount == 1 then CheckStaleSounds(sid) end
      else
        failed = failed + 1
        if not soundReported then
          soundReported = true
          local handler = geterrorhandler and geterrorhandler()
          if handler then handler(("engine (aura sound): %s"):format(ok and ("no sound id for spell " .. id) or tostring(sid))) end
        end
      end
    end
    -- a sound the game took over (for at least one spell) is kept from WeakAuras; otherwise WeakAuras
    -- plays it as before
    if okCount > 0 then att.soundRouted[w.when] = true end
  end
  if t0 then SoundStats(#att.soundIDs, debugprofilestop() - t0) end
  -- a failed registration is tried again on the next apply (e.g. after combat)
  if #ids > 0 and not (att.soundRouted.start or att.soundRouted.finish) then att.soundSig = nil end
end

---------------------------------------------------------------------------- dynamic groups
-- A Dynamic Group closes the gap when a child hides. Engine-driven children never hide for WeakAuras (their
-- trigger is handed to the game), so WA lays the group out as if every child were shown. When every child
-- is an engine-driven Found display, the game packs them instead (probe /fddyn chain, 2026-10-02): a chain
-- of invisible containers, one LINK per child in layout order, each a group of at most one button on that
-- child's aura with 1 px of padding, so a link is 1 px long plus the child and the spacing while the aura
-- is up and 1 px while it is not (AnchorUtil.ApplyFlowLayout reports max(size, 1)). Link k hangs on the far
-- end of link k-1 (less that 1 px) and child k's host hangs 1 px into link k: right after every earlier
-- child that is up. Centred groups hang the chain from a container that holds every child (2 px of
-- padding plus the row), by its middle. The chain starts where WA puts the first child.
-- Whatever hangs on an aura container must carry its ban on layout scripts (DisableUntrustedLayoutScripts-
-- Template). Our hosts do and everything of ours is created inside them; WA's own frames are refused
-- ("Anchoring disallowed as dependent object would inherit forbidden aspects", /fddyn chain). So a packed
-- child shows what the engine draws (icon, bar or texture, %p/%s/%n texts, glow), our copies that sat on
-- WA's frames move onto the host, and WA's other texts and the border are hidden.
local Dyn = {}
do
  local GROW = {
    RIGHT = { axis = "x", sign = 1 }, LEFT = { axis = "x", sign = -1 },
    UP = { axis = "y", sign = 1 }, DOWN = { axis = "y", sign = -1 },
    HORIZONTAL = { axis = "x", sign = 1, centred = true }, VERTICAL = { axis = "y", sign = 1, centred = true },
  }
  -- sub-elements a packed child hides (the ones that are on); any other kind keeps the group from packing
  local HIDE_ON = { subtext = "text_visible", subborder = "border_visible", subglow = "glow" }
  local FRAC = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 },
                 RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 } }
  local states = {}      -- group id -> the chain
  local lastSig = {}     -- group id -> plan signature (or reason) last acted on
  local queued = {}      -- group id -> true while its children are queued to re-apply
  local failReported = false

  local function RegionOf(id)
    local r = Private.regions[id]
    return r and r.region
  end

  local function Rect(f)
    if not (f and f.GetLeft) then return nil end
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    if not (l and b and w and h) or issecretvalue(l) or issecretvalue(b) or issecretvalue(w) or issecretvalue(h) then
      return nil
    end
    return l, b, w, h
  end

  -- The packing plan of a dynamic group (plain data): nil + reason when WA keeps laying it out.
  function Dyn.Plan(gdata)
    if not (gdata and gdata.regionType == "dynamicgroup") then return nil end
    local grow = gdata.grow or "DOWN"
    local g = GROW[grow]
    if not g then return nil, T("it grows in a circle, a grid or by custom code") end
    if gdata.useAnchorPerUnit then return nil, T("it anchors per unit") end
    if (gdata.sort or "none") ~= "none" then
      return nil, T("it sorts its children (only 'None' can be packed: the time left is secret in combat)")
    end
    if gdata.useLimit then return nil, T("it limits how many children it shows") end
    if (tonumber(gdata.stagger) or 0) ~= 0 then return nil, T("it staggers its children") end
    local ct = gdata.centerType or "LR"
    if g.centred and ct ~= "LR" and ct ~= "RL" then return nil, T("it fills from the centre outwards") end
    local space = tonumber(gdata.space) or 0
    if g.centred and space < 0 then return nil, T("its spacing is negative") end
    local ids = {}
    for _, id in ipairs(gdata.controlledChildren or {}) do ids[#ids + 1] = id end
    if #ids == 0 then return nil, T("it has no children") end
    if g.centred and ct == "RL" then
      local rev = {}
      for i = #ids, 1, -1 do rev[#rev + 1] = ids[i] end
      ids = rev
    end
    local unit
    local sizes = {}
    for _, id in ipairs(ids) do
      local cd = WA.GetData(id)
      if not cd then return nil, T("a child is missing") end
      sizes[#sizes + 1] = tostring(cd.width) .. "x" .. tostring(cd.height)
      local p = ENGINE_REGIONS[cd.regionType] and cd.uid and decided[cd.uid] or nil
      if not p then return nil, T("'%s' is not engine-driven"):format(tostring(id)) end
      if p.stacks then
        return nil, T("'%s' uses 'Stack Count' (its place would stay empty while the count does not match)"):format(tostring(id))
      end
      if p.parts or p.mode ~= "active" then
        return nil, T("'%s' is not shown on Aura(s) Found (only those leave a gap to close)"):format(tostring(id))
      end
      for _, sub in ipairs(cd.subRegions or {}) do
        if Private.subRegionTypes[sub.type] and not HIDE_ON[sub.type] and sub.type ~= "subbackground" then
          return nil, T("'%s' has a %s (a packed display keeps only texts, glows and borders)"):format(tostring(id), tostring(sub.type))
        end
      end
      if g.centred then
        if unit and unit ~= p.unit then return nil, T("its children watch different units (a centred group is measured on one)") end
        unit = p.unit
      end
    end
    return { axis = g.axis, sign = g.sign, centred = g.centred, ids = ids, space = space, unit = unit,
             sig = table.concat({ grow, ct, tostring(space), tostring(gdata.align), tostring(gdata.selfPoint),
                                  table.concat(ids, "\1"), table.concat(sizes, ",") }, "|") }
  end

  local function Retire(st)
    if not st then return end
    for _, link in pairs(st.links) do pcall(link.SetUnit, link, nil); link:Hide() end
    if st.total then pcall(st.total.SetUnit, st.total, nil); st.total:Hide() end
    st.root:Hide()
  end

  local function NewContainer(st)
    return CreateFrame("AuraContainer", nil, st.root, "CustomAuraContainerTemplate")
  end

  -- The chain of a group: links in layout order, hung on each other. Rebuilt when the plan changes.
  local function State(gregion, gid, gp)
    local st = states[gid]
    if st and st.sig == gp.sig and st.gregion == gregion then return st end
    Retire(st)
    st = { sig = gp.sig, gregion = gregion, gp = gp, links = {}, lg = {}, tg = {} }
    st.root = CreateFrame("Frame", nil, gregion, "DisableUntrustedLayoutScriptsTemplate")
    st.root:SetSize(1, 1)
    st.root:SetPoint("CENTER", gregion, "CENTER")
    local horiz = gp.axis == "x"
    if gp.centred then
      local t = NewContainer(st)
      if horiz then
        t:SetFlowLayoutPadding(1, 1, 0, 0)
      else
        t:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Vertical)
        t:SetFlowLayoutPadding(0, 0, 1, 1)
      end
      st.total = t
    end
    for k, id in ipairs(gp.ids) do
      local link = NewContainer(st)
      if horiz then link:SetFlowLayoutPadding(1, 0, 0, 0) else link:SetFlowLayoutPadding(0, 0, 1, 0) end
      local prev = k > 1 and st.links[gp.ids[k - 1]]
      if prev then
        if horiz and gp.sign > 0 then link:SetPoint("TOPLEFT", prev, "TOPRIGHT", -1, 0)
        elseif horiz then link:SetPoint("TOPRIGHT", prev, "TOPLEFT", 1, 0)
        elseif gp.sign > 0 then link:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, -1)
        else link:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 1) end
      end
      st.links[id] = link
    end
    states[gid] = st
    return st
  end

  -- The chain starts where WA puts the first child it shows (WA leaves out children that are not loaded;
  -- their links stay 1 px, their aura being nowhere); a centred one hangs by the middle of WA's row.
  local function AnchorStart(st)
    local gp = st.gp
    local first, last
    for _, id in ipairs(gp.ids) do
      local r = RegionOf(id)
      if r and r:IsShown() and Rect(r) then first = first or r; last = r end
    end
    -- nothing shown (no target): the chain keeps the place it was given last time
    if not first then return st.ref ~= nil end
    st.ref = first
    local fl, fb = Rect(first)
    local ll, lb, lw, lh = Rect(last)
    -- the chain measures in the children's own units (a group anchored to a scaled frame scales them)
    local want = first:GetEffectiveScale() / st.gregion:GetEffectiveScale()
    if math.abs(st.root:GetScale() - want) > 0.0001 then st.root:SetScale(want) end
    local k = 1
    local link = st.links[gp.ids[1]]
    link:ClearAllPoints()
    if gp.centred then
      local t = st.total
      t:ClearAllPoints()
      if gp.axis == "x" then
        t:SetPoint("TOP", first, "TOPLEFT", (ll + lw - fl) / 2 * k, 0)
        link:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
      else
        t:SetPoint("LEFT", first, "BOTTOMLEFT", 0, (lb + lh - fb) / 2 * k)
        link:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
      end
    elseif gp.axis == "x" and gp.sign > 0 then link:SetPoint("TOPLEFT", first, "TOPLEFT", -1, 0)
    elseif gp.axis == "x" then link:SetPoint("TOPRIGHT", first, "TOPRIGHT", 1, 0)
    elseif gp.sign > 0 then link:SetPoint("BOTTOMLEFT", first, "BOTTOMLEFT", 0, -1)
    else link:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 1) end
    return true
  end

  -- A group of at most one invisible button on the child's aura (its slot's filter and candidates).
  local function MeasureGroup(c, key, plan, ew, eh, extra)
    local layout = { elementWidth = ew, elementHeight = eh }
    for k2, v in pairs(extra or {}) do layout[k2] = v end
    return pcall(c.AddAuraGroup, c, key, plan.filterString, {
      candidateFilters = plan.candidate,
      maxFrameCount = 1,
      layout = layout,
      initializeFrame = function(button)
        button:SetSize(ew, eh)
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.EnableMouseMotion, button, false)
      end,
    })
  end

  local function SyncMeasure(c, key, rec, plan, ew, eh, extra)
    if rec.filter ~= plan.filterString then c:SetAuraGroupFilterString(key, plan.filterString); rec.filter = plan.filterString end
    if rec.pkey ~= plan.key then c:SetAuraGroupCandidateFilters(key, plan.candidate); rec.pkey = plan.key end
    if rec.ew ~= ew or rec.eh ~= eh then
      local layout = { elementWidth = ew, elementHeight = eh }
      for k2, v in pairs(extra or {}) do layout[k2] = v end
      c:SetAuraGroupLayout(key, layout); rec.ew, rec.eh = ew, eh
    end
    c:SetAuraGroupEnabled(key, true)
  end

  local function EnsureLink(st, id, k, plan, w, h)
    local gp = st.gp
    local horiz = gp.axis == "x"
    local link = st.links[id]
    local ew, eh = horiz and (w + gp.space) or w, horiz and h or (h + gp.space)
    local rec = st.lg[id]
    if not rec then
      local ok, err = MeasureGroup(link, KEY, plan, ew, eh)
      if not ok then return false, err end
      st.lg[id] = { filter = plan.filterString, pkey = plan.key, ew = ew, eh = eh }
      rec = st.lg[id]
    else
      SyncMeasure(link, KEY, rec, plan, ew, eh)
    end
    if rec.unit ~= plan.unit then link:SetUnit(plan.unit); rec.unit = plan.unit end
    pcall(link.UpdateAllAuras, link)
    if st.total then
      local key, extra = "t" .. k, { groupSpacing = gp.space }
      local trec = st.tg[id]
      if not trec then
        local ok, err = MeasureGroup(st.total, key, plan, w, h, extra)
        if not ok then return false, err end
        st.tg[id] = { filter = plan.filterString, pkey = plan.key, ew = w, eh = h }
      else
        SyncMeasure(st.total, key, trec, plan, w, h, extra)
      end
      if st.totalUnit ~= gp.unit then st.total:SetUnit(gp.unit); st.totalUnit = gp.unit end
      pcall(st.total.UpdateAllAuras, st.total)
    end
    return true
  end

  -- The host hangs 1 px into its link; across the chain it keeps WA's own place (WA's alignment).
  local function PlaceHost(att, region, st, id, w, h)
    local gp = st.gp
    local link = st.links[id]
    local rl, rb, _, rh = Rect(region)
    local fl, fb, _, fh = Rect(st.ref)
    -- across the chain: WA's own offset from the chain's start (its alignment); kept from last time
    -- while the display or the start is not shown (no target)
    local cross
    if rl and fl and region:IsShown() and st.ref:IsShown() then
      cross = gp.axis == "x" and ((rb + rh) - (fb + fh)) or (rl - fl)
      att.dynCross = cross
    else
      cross = att.dynCross
    end
    if not cross then return false end
    local host = att.host
    host:ClearAllPoints()
    host:SetSize(w, h)
    if gp.axis == "x" then
      if gp.sign > 0 then host:SetPoint("TOPLEFT", link, "TOPLEFT", 1, cross)
      else host:SetPoint("TOPRIGHT", link, "TOPRIGHT", -1, cross) end
    else
      if gp.sign > 0 then host:SetPoint("BOTTOMLEFT", link, "BOTTOMLEFT", cross, 1)
      else host:SetPoint("TOPLEFT", link, "TOPLEFT", cross, -1) end
    end
    return true
  end

  local function Under(f, top)
    for _ = 1, 12 do
      if f == top then return true end
      if not (f and f.GetParent) then return false end
      f = f:GetParent()
    end
    return false
  end

  -- Our copies that hang on WA's frames (a bar's bar and icon, the sub-texts, a glow around a bar's icon)
  -- move onto the host, at the same place within the display. Their anchors come from Engine.SetAnchors
  -- (att.anchors): reading them back is not possible on texts the game binds to an aura.
  local function OnWA(att, region, rel)
    return type(rel) == "table" and rel ~= att.host and Under(rel, region) and not Under(rel, att.host)
  end

  local function Rebase(att, region, obj, pts)
    local any = false
    for _, p in ipairs(pts) do if OnWA(att, region, p[2]) then any = true end end
    if not any then return end
    att.rebasedPts = att.rebasedPts or setmetatable({}, { __mode = "k" })
    local gl, gb = Rect(region)
    local out = {}
    for i, p in ipairs(pts) do
      if not out then break end
      if OnWA(att, region, p[2]) then
        local l, b, w, h = Rect(p[2])
        if gl and l and region:IsShown() then
          local fr = FRAC[tostring(p[3] or p[1]):upper()] or FRAC.CENTER
          out[i] = { p[1], att.host, "BOTTOMLEFT", l - gl + fr[1] * w + (p[4] or 0), b - gb + fr[2] * h + (p[5] or 0) }
        else
          out = nil                                    -- not laid out (hidden): as worked out last time
        end
      else
        out[i] = p
      end
    end
    out = out or att.rebasedPts[obj]
    if not out then return end
    att.rebasedPts[obj] = out
    obj:ClearAllPoints()
    for _, p in ipairs(out) do obj:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
    att.rebased = att.rebased or {}
    att.rebased[obj] = true
  end

  -- back on WA's frames, as last set (a fresh look may have set them again since)
  local function Unbase(att)
    for obj in pairs(att.rebased or {}) do
      local pts = att.anchors and att.anchors[obj]
      if pts then
        obj:ClearAllPoints()
        for _, p in ipairs(pts) do obj:SetPoint(p[1], p[2], p[3], p[4] or 0, p[5] or 0) end
      end
    end
    att.rebased = nil
  end

  -- WA's sub-elements that stay where WA puts the child: hidden (only the ones that are on).
  local function HideWASubs(att, region, data)
    att.dynHidden = att.dynHidden or {}
    att.mirrored = att.mirrored or {}
    local ri = 0
    for _, sub in ipairs(data.subRegions or {}) do
      if Private.subRegionTypes[sub.type] then
        ri = ri + 1
        local live = region.subRegions and region.subRegions[ri]
        local flag = HIDE_ON[sub.type]
        if live and flag and sub[flag] ~= false and (sub.type ~= "subglow" or sub.glow) then
          att.mirrored[live] = true
          att.dynHidden[live] = true
        end
      end
    end
  end

  -- Every child of the group syncs again next frame: its status line says whether it is packed (WA shows
  -- a group's status lines from its children), and a child whose packing changed applies again, on the
  -- new chain or back in its own place.
  local function Requeue(gdata)
    if queued[gdata.id] then return end
    queued[gdata.id] = true
    local ids = {}
    for _, id in ipairs(gdata.controlledChildren or {}) do ids[#ids + 1] = id end
    C_Timer.After(0, function()
      queued[gdata.id] = nil
      for _, id in ipairs(ids) do
        local r, cd = RegionOf(id), WA.GetData(id)
        if r and cd and attachments[r] then
          local ok = pcall(Engine.Sync, r, cd)
          if not ok then Dyn.Schedule(r) end
        end
      end
    end)
  end

  -- Re-plans a group; when the plan changed, retires the old chain and re-applies every child.
  function Dyn.Refresh(gdata)
    if not (gdata and gdata.regionType == "dynamicgroup") then return nil end
    local gp, why = Dyn.Plan(gdata)
    local sig = gp and gp.sig or ("-" .. tostring(why))
    if lastSig[gdata.id] ~= sig then
      lastSig[gdata.id] = sig
      if not gp and states[gdata.id] then Retire(states[gdata.id]); states[gdata.id] = nil end
      Requeue(gdata)
    end
    return gp, why
  end

  local function ParentOf(data)
    local gdata = data and data.parent and WA.GetData(data.parent)
    return gdata and gdata.regionType == "dynamicgroup" and gdata or nil
  end

  -- Status line of a child (appended to its own), nil outside dynamic groups.
  function Dyn.Note(data)
    local gdata = ParentOf(data)
    if not gdata then return nil end
    local gp, why = Dyn.Plan(gdata)
    if gp then
      return T("|cff33ff99Dynamic Group:|r packed by the game, so it leaves no gap while its aura is absent, in combat too. While packed, its border and texts other than %p/%s/%n are hidden.")
    end
    return T("|cffff9933Dynamic Group:|r keeps its place while its aura is absent, because %s."):format(tostring(why))
  end

  -- For the signature: a child re-applies when its group's packing changes.
  function Dyn.Sig(data)
    local gdata = ParentOf(data)
    if not gdata then return "" end
    local gp, why = Dyn.Plan(gdata)
    return gp and gp.sig or ("-" .. tostring(why))
  end

  function Dyn.Release(att, region)
    if att.rebased then Unbase(att) end
    if att.dynHidden then
      for live in pairs(att.dynHidden) do
        if not (att.mirrored and att.mirrored[live]) and live.SetShown then live:SetShown(true) end
      end
      att.dynHidden = nil
    end
    if att.dyn then
      att.dyn = nil
      if att.host then att.host:ClearAllPoints(); att.host:SetAllPoints(region) end
    end
  end

  -- An engine-driven Found slot: packed when its group can be. Called at safe time, after the look.
  function Dyn.Place(att, region, data, plan)
    local gdata = ParentOf(data)
    local gp = gdata and Dyn.Refresh(gdata)
    local gregion = gp and RegionOf(gdata.id)
    local k
    for i, id in ipairs(gp and gp.ids or {}) do if id == data.id then k = i end end
    if not (gp and gregion and k) then Dyn.Release(att, region); return false end
    local st = State(gregion, gdata.id, gp)
    local w, h = RegionSize(region)
    local ok, err = AnchorStart(st)
    if ok then ok, err = EnsureLink(st, data.id, k, plan, w, h) end
    if ok then
      att.dyn = st                                   -- from here on, Release puts the host back
      ok = PlaceHost(att, region, st, data.id, w, h)
    end
    if not ok then
      if err and not failReported then
        failReported = true
        WA.prettyPrint(("%s: engine dynamic group failed: %s"):format(tostring(region.id), tostring(err)))
      end
      -- no place to read yet (nothing of the group shown): tried again when WA lays the display out
      if not err then att.dynRetry = (att.dynRetry or 0) + 1 end
      Dyn.Release(att, region)
      return false
    end
    att.dynRetry = nil
    for obj, pts in pairs(att.anchors or {}) do Rebase(att, region, obj, pts) end
    HideWASubs(att, region, data)
    return true
  end

  -- A display that stops being a packed slot (off, preview, Missing, ...): its group re-plans.
  function Dyn.Leave(att, region, data)
    att.dynRetry = nil
    Dyn.Release(att, region)
    local gdata = ParentOf(data)
    if gdata then Dyn.Refresh(gdata) end
  end

  Engine.DynPlan, Engine.DynNote = Dyn.Plan, Dyn.Note   -- for the tests

  -- A container does not refresh itself when its unit token points at another unit (a new target):
  -- the links and totals of every chain on that unit are told, like the display slots. Missed, a link
  -- kept the old target's aura and its child's successors sat one place too far (seen 2026-10-03/04).
  function Dyn.UpdateUnit(unit)
    for _, st in pairs(states) do
      for id, rec in pairs(st.lg) do
        if unit == nil or rec.unit == unit then pcall(st.links[id].UpdateAllAuras, st.links[id]) end
      end
      if st.total and (unit == nil or st.totalUnit == unit) then pcall(st.total.UpdateAllAuras, st.total) end
    end
  end

  -- A child that could not be placed (its group not shown yet) tries again once WA shows it, a few times.
  local onLayout = Engine.OnLayout
  function Engine.OnLayout(region)
    onLayout(region)
    local att = attachments[region]
    if att and att.dynRetry and att.dynRetry <= 3 and not att.dynQueued and region:IsVisible() then
      att.dynQueued = true
      C_Timer.After(0, function() att.dynQueued = nil; Dyn.Schedule(region) end)
    end
  end
end

local function TurnOff(att, region, data, mode)
  if att.host then att.host:Hide() end
  pcall(Dyn.Leave, att, region, data)
  DisableKind(att, "slot"); DisableKind(att, "group"); DisableKind(att, "composite")
  StopPresentGlows(att); StopAnimatedGlow(att.mglowHolder)
  for _, rs in pairs(att.rslots or {}) do if rs.glowHolder then StopAnimatedGlow(rs.glowHolder) end end
  RemoveGate(att)
  if att.isBar then SetBarVisuals(region, true)
  elseif att.isTex then SetTexVisuals(region, true)
  elseif att.isPic then SetPicVisuals(region, true)
  elseif att.isMotion then Engine.SetMotionVisuals(region, true)
  elseif att.isModel then Engine.SetModelVisuals(region, true)
  elseif att.isText then SetTextVisuals(region, true)
  elseif region.icon then region.icon:Show() end
  SetMirroredShown(att, true)
  ClearSounds(att)
  if region.tooltipFrame and data then region.tooltipFrame:EnableMouseMotion(data.useTooltip and true or false) end
  att.mode, att.active, att.sig, att.kind = mode, false, nil, nil
end

local function ApplyUnguarded(region)
  local att = attachments[region]
  if not att then return end
  local data = WA.GetData(region.id)
  local live = data and Private.regions[region.id] and Private.regions[region.id].region == region
  local plan = live and att.want or nil
  local mode = (not plan or att.broken) and "off" or (InPreview() and "preview") or "on"

  if mode ~= "on" then
    if att.mode == mode then return end
    TurnOff(att, region, data, mode)
    return
  end

  if not att.host then att.host, att.container, att.gates = BuildHost(region) end
  if att.isText then FitTextHost(att, region, data, plan) end
  local c = att.container
  local kind = plan.parts and "composite" or ((plan.mode == "missing") and "group" or "slot")
  if att.kind and att.kind ~= kind then DisableKind(att, att.kind) end

  if kind == "slot" then
    if not att.slotBuilt then
      if not BuildSlot(att, region, plan) then TurnOff(att, region, data, "off"); return end
      att.slotFilter, att.slotKey = plan.filterString, plan.key
    else
      if att.slotFilter ~= plan.filterString then c:SetAuraSlotFilterString(KEY, plan.filterString); att.slotFilter = plan.filterString end
      if att.slotKey ~= plan.key then c:SetAuraSlotCandidateFilters(KEY, plan.candidate); att.slotKey = plan.key end
      c:SetAuraSlotEnabled(KEY, true)
    end
    local glowSub = plan.mode == "active" and GlowSub(data)
    if glowSub then
      local w, h = RegionSize(region)
      att.pclipShown = EnsurePresentClip(att, region, plan, AnimatedGlowMargin(w, h, glowSub))
    else
      DisablePresentClip(att)
    end
  elseif kind == "group" then
    local w, h = RegionSize(region)
    local m = ClipMargin(w, h, data, GlowSpec(data))
    if att.isText then m = math.max(m, 3) end      -- the outline reaches past the measured text
    if not EnsureGroup(att, region, plan, m) then TurnOff(att, region, data, "off"); return end
  else
    if not EnsureComposite(att, region, data, plan) then TurnOff(att, region, data, "off"); return end
  end
  local okSt, errSt = pcall(Engine.ApplyStacks, att, plan, kind == "slot")
  if not okSt and not att.stackWarned then
    att.stackWarned = true
    WA.prettyPrint(("%s: engine stack count failed: %s"):format(tostring(region.id), tostring(errSt)))
  end
  att.kind = kind
  if att.unit ~= plan.unit then c:SetUnit(plan.unit); att.unit = plan.unit end

  local okLook, err
  if kind == "slot" then okLook, err = pcall(ApplySlotLook, att, region, data, plan)
  elseif kind == "group" then okLook, err = pcall(ApplyUnderlayLook, att, region, data, plan)
  else okLook, err = pcall(ApplyCompositeLook, att, region, data, plan) end
  if not okLook and not att.lookWarned then
    att.lookWarned = true
    WA.prettyPrint(("%s: engine look failed: %s"):format(tostring(region.id), tostring(err)))
  end

  -- Underlay policy: Found = nothing beneath; Always = the WA icon beneath the live aura;
  -- Missing = the WA icon is replaced by our clipped copy.
  if att.isBar then SetBarVisuals(region, false)
  elseif att.isTex then SetTexVisuals(region, false)
  elseif att.isPic then SetPicVisuals(region, false)
  elseif att.isMotion then Engine.SetMotionVisuals(region, false)
  elseif att.isModel then Engine.SetModelVisuals(region, false)
  elseif att.isText then SetTextVisuals(region, false)
  else region.icon:SetShown(plan.mode == "always") end
  if region.tooltipFrame then region.tooltipFrame:EnableMouseMotion(false) end
  if kind == "slot" then pcall(att.button.SetFrameLevel, att.button, c:GetFrameLevel()) end
  if kind == "composite" then
    SetRemainLevels(att)
    if plan.parts.found and att.button then pcall(att.button.SetFrameLevel, att.button, c:GetFrameLevel()) end
  end
  if att.isBar and att.shadows.bar then                  -- keep bar under texts, both above the button
    local sh = att.shadows
    pcall(sh.bar.SetFrameLevel, sh.bar, c:GetFrameLevel() + 1)
    pcall(sh.texts.SetFrameLevel, sh.texts, c:GetFrameLevel() + 2)
  elseif (att.isPic or att.isMotion or att.isModel or att.isText) and kind == "slot" and att.shadows.texts then
    pcall(att.shadows.texts.SetFrameLevel, att.shadows.texts, c:GetFrameLevel() + 2)
  elseif att.isTex and att.shadows.texClip then         -- texture under texts, both above the button
    local sh = att.shadows
    pcall(sh.bar.SetFrameLevel, sh.bar, c:GetFrameLevel() + 1)
    pcall(sh.texClip.SetFrameLevel, sh.texClip, c:GetFrameLevel() + 1)
    pcall(sh.texts.SetFrameLevel, sh.texts, c:GetFrameLevel() + 2)
  end
  -- in a Dynamic Group of engine-driven Found displays, the game packs the children (after the look:
  -- the copies the look hung on WA's frames move onto the host)
  local okD, errD = pcall((kind == "slot" and plan.mode == "active") and Dyn.Place or Dyn.Leave, att, region, data, plan)
  if not okD then
    pcall(Dyn.Release, att, region)
    if not att.dynWarned then
      att.dynWarned = true
      WA.prettyPrint(("%s: engine dynamic group failed: %s"):format(tostring(region.id), tostring(errD)))
    end
  end
  att.host:Show()
  att.mode, att.active, att.sig = "on", true, att.wantSig
  local okS, errS = pcall(ApplySounds, att, region, data, plan)
  if not okS and not soundReported then
    soundReported = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler("engine (aura sound): " .. tostring(errS)) end
  end
  att.rangeSpell = nil
  if WantsRangeGate(data, plan) then
    local spell = RangeSpell(data, plan)
    if ValidateRangeSpell(spell) and InstallGate(att) then
      att.rangeSpell = spell
      SampleRange(att)               -- right answer now, not 0.2 s from now
      EnsureRangeTicker()
    else
      RemoveGate(att)                -- Explain tells the user why (status line + aura warning)
    end
  else
    RemoveGate(att)
  end
  Engine.OnLayout(region)
  pcall(c.UpdateAllAuras, c)
  if att.pclipShown then pcall(att.container2.UpdateAllAuras, att.container2) end
end

-- The engine rides on WeakAuras' own modify / layout calls. A bug here must never stop WeakAuras from
-- loading or updating displays: every entry point is guarded, and each kind of error is reported once.
local reported = {}
local function Guard(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported[label] then
    reported[label] = true
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(("engine (%s): %s"):format(label, tostring(err))) end
  end
  return ok
end

local function Apply(region) Guard("apply", ApplyUnguarded, region) end

local function Schedule(region)
  if Engine.IsSafe() then pending[region] = nil; Apply(region) else pending[region] = true end
end
Dyn.Schedule = Schedule

-- A display whose spell was unknown at load is not engine-driven; once the spell is learned only a
-- full re-add lets the trigger side re-classify it. Done at safe time, like everything else.
FlushReadds = function()
  if not Engine.IsSafe() then return end
  for uid in pairs(readd) do
    readd[uid] = nil
    local data = Private.GetDataByUID and Private.GetDataByUID(uid)
    if data then xpcall(WA.Add, Private.GetErrorHandlerUid(uid, "ForeverEngine re-add"), data) end
  end
end

function Engine.Flush()
  if not Engine.IsSafe() then return end
  for region in pairs(pending) do pending[region] = nil; Apply(region) end
  FlushReadds()
end

local function ScheduleAll()
  for region, att in pairs(attachments) do if att.want or att.active then Schedule(region) end end
end

local function ComputeSig(region, data, plan)
  local w, h = RegionSize(region)
  local parts = { plan.key, w, h, tostring(data.cooldown), tostring(data.cooldownSwipe), tostring(data.cooldownEdge),
    tostring(data.cooldownTextDisabled), tostring(data.inverse), tostring(data.desaturate), tostring(data.useTooltip),
    tostring(data.iconSource), tostring(data.displayIcon),
    tostring(data.texture), tostring(data.textureSource), tostring(data.textureInput), tostring(data.orientation),
    tostring(data.icon), tostring(data.icon_side), table.concat(data.barColor or {}, ","),
    tostring(data.enableGradient), table.concat(data.barColor2 or {}, ","), tostring(data.gradientOrientation),
    table.concat(data.backgroundColor or {}, ","), table.concat(data.icon_color or {}, ","),
    tostring(data.foreverEngineRange), tostring(data.foreverEngineRangeSpell), tostring(data.foreverEngineGlowPart),
    SoundSig(data), tostring(data.parent), Dyn.Sig(data), plan.stacks and plan.stacks.key or "",
    table.concat(data.color or {}, ","), region.icon and table.concat({ region.icon:GetTexCoord() }, ",") or "" }
  if data.regionType == "progresstexture" then
    for _, k in ipairs({ "foregroundTexture", "backgroundTexture", "sameTexture", "desaturateForeground",
                         "desaturateBackground", "blendMode", "textureWrapMode", "backgroundOffset", "compress",
                         "crop_x", "crop_y", "rotation", "auraRotation", "mirror", "user_x", "user_y",
                         "startAngle", "endAngle" }) do
      parts[#parts + 1] = tostring(data[k])
    end
    parts[#parts + 1] = table.concat(data.foregroundColor or {}, ",")
  elseif data.regionType == "model" then
    for _, k in ipairs({ "model_fileId", "modelIsUnit", "modelDisplayInfo", "api", "model_x", "model_y", "model_z",
                         "model_st_tx", "model_st_ty", "model_st_tz", "model_st_rx", "model_st_ry", "model_st_rz",
                         "model_st_us", "rotation", "sequence", "advance", "portraitZoom", "alpha", "border" }) do
      parts[#parts + 1] = tostring(data[k])
    end
  elseif data.regionType == "stopmotion" then
    for _, k in ipairs({ "foregroundTexture", "backgroundTexture", "sameTexture", "hideBackground", "frameRate",
                         "animationType", "inverse", "startPercent", "endPercent", "backgroundPercent",
                         "desaturateForeground", "desaturateBackground", "blendMode",
                         "customForegroundFrames", "customForegroundRows", "customForegroundColumns",
                         "customForegroundFileWidth", "customForegroundFileHeight", "customForegroundFrameWidth",
                         "customForegroundFrameHeight", "customBackgroundFrames", "customBackgroundRows",
                         "customBackgroundColumns" }) do
      parts[#parts + 1] = tostring(data[k])
    end
    parts[#parts + 1] = table.concat(data.foregroundColor or {}, ",")
    parts[#parts + 1] = table.concat(data.backgroundColor or {}, ",")
  elseif data.regionType == "texture" then
    for _, k in ipairs({ "texture", "rotation", "rotate", "mirror", "desaturate", "blendMode", "textureWrapMode" }) do
      parts[#parts + 1] = tostring(data[k])
    end
    local wa = region.texture and region.texture.texture
    if wa and wa.GetTexCoord then parts[#parts + 1] = table.concat({ wa:GetTexCoord() }, ",") end
  elseif data.regionType == "text" then
    for _, k in ipairs({ "displayText", "font", "fontSize", "outline", "justify", "automaticWidth", "fixedWidth",
                         "wordWrap", "shadowXOffset", "shadowYOffset" }) do
      parts[#parts + 1] = tostring(data[k])
    end
    parts[#parts + 1] = table.concat(data.shadowColor or {}, ",")
    if region.text and TextKind(data) == "plain" then parts[#parts + 1] = PlainText(region, data) end
  end
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subtext" then
      parts[#parts + 1] = table.concat({ tostring(sub.text_text), tostring(sub.text_visible), tostring(sub.text_font),
        tostring(sub.text_fontSize), tostring(sub.text_fontType), tostring(sub.anchor_point), tostring(sub.text_selfPoint),
        tostring(sub.text_anchorXOffset), tostring(sub.text_anchorYOffset), tostring(sub.text_justify),
        sub.text_color and table.concat(sub.text_color, ",") or "" }, "/")
    elseif sub.type == "subglow" then
      parts[#parts + 1] = table.concat({ "glow", tostring(sub.glow), tostring(sub.useGlowColor),
        sub.glowColor and table.concat(sub.glowColor, ",") or "", tostring(sub.glowScale),
        tostring(sub.glowXOffset), tostring(sub.glowYOffset), tostring(sub.glowType), tostring(sub.glowLines),
        tostring(sub.glowFrequency), tostring(sub.glowLength), tostring(sub.glowThickness), tostring(sub.glowBorder),
        tostring(sub.glowStartAnim), tostring(sub.glowDuration), tostring(sub.anchor_area) }, "/")
    elseif sub.type == "subborder" then
      parts[#parts + 1] = "border/" .. tostring(sub.border_visible)
    end
  end
  return table.concat(parts, "|")
end

local function SetWarning(att, uid, severity, message)
  local key = tostring(severity) .. "\n" .. tostring(message)
  if att.warn == key then return end
  att.warn = key
  pcall(Private.AuraWarnings.UpdateWarning, uid, WARN, severity, message)
end

-- Region side; runs after every icon modify (incl. the mover's per-frame Add): idempotent and cheap.
function Engine.Sync(region, data)
  if not data then return end
  if region.cloneId and region.cloneId ~= "" then return end
  -- Private.Convert drops Private.regions[id] without a Delete: retire attachments on orphans with our id.
  for other, oatt in pairs(attachments) do
    if other ~= region and other.id == region.id and oatt.want then oatt.want = nil; Schedule(other) end
  end
  local att = attachments[region]
  if not att then
    att = { region = region, shadows = {}, isBar = data.regionType == "aurabar", isTex = data.regionType == "progresstexture",
            isPic = data.regionType == "texture", isText = data.regionType == "text",
            isMotion = data.regionType == "stopmotion", isModel = data.regionType == "model" }
    attachments[region] = att
  end
  local plan = decided[data.uid]
  local isAura2 = false
  for _, tr in ipairs(data.triggers or {}) do
    if tr and tr.trigger and tr.trigger.type == "aura2" then isAura2 = true; break end
  end
  if plan and not isAura2 then
    -- the trigger side only re-classifies aura2 triggers; a display whose Aura triggers all changed
    -- type would otherwise keep yesterday's plan
    plan = false; decided[data.uid] = false; nameWatch[data.uid] = nil
  end
  if plan == nil then plan = Engine.Classify(data) or false end   -- no Add seen yet (should not happen)
  if plan and plan.byName and plan.gen ~= spellbookGen then
    local fresh = Engine.Classify(data)
    if fresh then plan = fresh; decided[data.uid] = fresh          -- new ranks / sightings -> new filters
    else plan.gen = spellbookGen end                               -- eligibility is the trigger side's call
  end
  if not plan then
    if att.want or att.active then att.want = nil; Schedule(region) end
    if isAura2 and ENGINE_REGIONS[data.regionType] then
      SetWarning(att, data.uid, "info", (Engine.Explain(data)))
    else
      SetWarning(att, data.uid, nil, nil)
    end
    return
  end
  local sig = ComputeSig(region, data, plan)
  att.want, att.wantSig = plan, sig
  local status = (Engine.Explain(data, plan))
  local note = Dyn.Note(data)
  if note and status then status = status .. "\n\n" .. note end
  SetWarning(att, data.uid, "info", status)
  if att.active and att.sig == sig and not pending[region] then return end
  Schedule(region)
end

---------------------------------------------------------------------------- secret values in custom code
-- An aura's own custom code (custom trigger, custom text, custom check, actions) that reads a value
-- the client keeps secret in combat fails by design on Forever; no addon change can make it compare
-- a secret. Recognised by the error text plus the place: a custom trigger, or a chunk the aura's
-- author wrote (the addon compiles user code as "return <code>"). Anything else stays a real error.
local function IsSecretError(msg)
  return msg:find("a secret [%a ]*value") or msg:find("secret value") or msg:find("when secret")
end

function Private.ForeverSecretCustomError(data, context, message)
  local msg = tostring(message or "")
  if not IsSecretError(msg) then return nil end
  local custom = msg:find('^%[string "return') ~= nil
  local n = tonumber(tostring(context or ""):match("(%d+)"))
  local trig = n and type(data.triggers) == "table" and data.triggers[n] and data.triggers[n].trigger
  if trig and trig.type == "custom" then custom = true end
  if not custom then return nil end
  return T("The custom code in '%s' (%s) reads a value WoW Forever keeps secret from addons (most of them in combat, some such as your current mana always), so that part of the aura cannot work. It is the aura's own code, not an EverAuras bug: turn the aura off, or replace the custom trigger with a built-in one.")
    :format(tostring(data.id), tostring(context or T("custom code")))
end

---------------------------------------------------------------------------- zero-diff hooks into the core
local icon = Private.regionTypes and Private.regionTypes.icon
if not icon then return end
icon.default.foreverEngine = true            -- per-display opt-out (false); Private.validate fills it in
icon.default.foreverEngineRange = false      -- 'only while the spell is in range of the unit'
icon.default.foreverEngineRangeSpell = ""    -- override for the range-check spell (blank = trigger's spell)
icon.default.foreverEngineGlowPart = "both"  -- missing + time left: where the static glow goes
icon.default.foreverEngineSelfDebuff = false  -- debuffs on yourself: match any own debuff by duration
icon.default.foreverEngineSelfDebuffMax = ""  -- its longest duration in seconds (blank = as seen)

for _, rt in ipairs({ "aurabar", "progresstexture", "texture", "text", "stopmotion", "model" }) do
  local regionType = Private.regionTypes and Private.regionTypes[rt]
  if regionType and regionType.modify and regionType.default then
    regionType.default.foreverEngine = true
    regionType.default.foreverEngineRange = false
    regionType.default.foreverEngineRangeSpell = ""
    regionType.default.foreverEngineSelfDebuff = false
    regionType.default.foreverEngineSelfDebuffMax = ""
    local origModify = regionType.modify
    regionType.modify = function(parent, region, data)
      origModify(parent, region, data)
      Guard("sync", Engine.Sync, region, data)
    end
  end
end

do
  -- WA shows every shown display's model again after a cinematic or the world map (PreShowModels),
  -- without a layout pass: engine-driven Models hide WA's own model again right after
  local preShowModels = Private.PreShowModels
  if type(preShowModels) == "function" then
    Private.PreShowModels = function(...)
      preShowModels(...)
      for region, att in pairs(attachments) do
        if att.active and att.isModel then pcall(Engine.SetModelVisuals, region, false) end
      end
    end
  end
end

do
  -- a Dynamic Group re-plans its packing whenever WA sets it up (grow, spacing, children, ...)
  local dyn = Private.regionTypes and Private.regionTypes.dynamicgroup
  if dyn and dyn.modify then
    local origDyn = dyn.modify
    dyn.modify = function(parent, region, data)
      origDyn(parent, region, data)
      Guard("dynamic group", Dyn.Refresh, data)
    end
  end
end

local function ApplyAuraCountdown(region, data)
  local cd = region and region.cooldown
  if not (cd and cd.SetCountdownFormatter) then return end
  local fmt = IsAuraOnlyDisplay(data) and Private.ForeverAuraCountdownFormatter() or nil
  if region.foreverCountdown ~= fmt then
    region.foreverCountdown = fmt
    pcall(cd.SetCountdownFormatter, cd, fmt)
  end
end

local origModify = icon.modify
icon.modify = function(parent, region, data)
  origModify(parent, region, data)
  Guard("countdown", ApplyAuraCountdown, region, data)
  Guard("sync", Engine.Sync, region, data)
end

local origApplyFrameLevel = Private.ApplyFrameLevel
local ApplyEngineFrameLevels
function Private.ApplyFrameLevel(region, frameLevel)
  origApplyFrameLevel(region, frameLevel)
  Guard("layout", ApplyEngineFrameLevels, region, frameLevel)
end
ApplyEngineFrameLevels = function(region, frameLevel)
  local att = attachments[region]
  if not (att and att.active and att.host) then return end
  local base = frameLevel or (Private.frameLevels and Private.frameLevels[region.id]) or 5
  att.host:SetFrameLevel(region:GetFrameLevel() + 1)       -- L+2 (region is L+1 via subbackground)
  att.container:SetFrameLevel(att.host:GetFrameLevel())
  if att.shadows.clip then att.shadows.clip:SetFrameLevel(att.host:GetFrameLevel()) end
  if att.container2 then att.container2:SetFrameLevel(att.host:GetFrameLevel()) end
  if att.pclip then att.pclip:SetFrameLevel(att.host:GetFrameLevel() + 2) end
  for _, k in ipairs(PGLOW_KEYS) do
    if att[k] and att.pclip then att[k]:SetFrameLevel(att.pclip:GetFrameLevel() + 2) end
  end
  if att.mglowHolder and att.shadows.clip then att.mglowHolder:SetFrameLevel(att.shadows.clip:GetFrameLevel() + 2) end
  SetRemainLevels(att)
  if region.subRegions then
    for index, sub in pairs(region.subRegions) do
      if sub.type ~= "subbackground" and sub.SetFrameLevel then sub:SetFrameLevel(base + index + 1) end
    end
  end
  Engine.OnLayout(region)
end

local origPause, origResume = Private.Pause, Private.Resume
function Private.Pause(...)  origPause(...);  ScheduleAll() end
function Private.Resume(...) origResume(...); ScheduleAll() end

Private.callbacks:RegisterCallback("AboutToDelete", function(_, uid, id)
  decided[uid], nameWatch[uid], readd[uid], durWatch[uid], fpUsers[uid], lateUsers[uid] = nil, nil, nil, nil, nil, nil
  for region, att in pairs(attachments) do
    if region.id == id and att.want then att.want = nil; Schedule(region) end
  end
end)
Private.callbacks:RegisterCallback("WA_SECRET_STATE_UPDATE", function() Engine.Flush() end)

---------------------------------------------------------------------------- learning + spellbook events
local QueueSpellbookRefresh   -- defined below

-- Walk a unit's auras while they are plain and remember the ids behind the names our triggers use.
-- While auras are plain, remember every debuff on you as a fingerprint, for displays that match by it.
local function LearnFingerprints(unit)
  if not (next(durWatch) or next(fpUsers) or next(lateUsers)) or not Engine.IsSafe() then return end
  local all = Fingerprints()
  if not all then return end
  local changed = false
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
    if not ok or type(a) ~= "table" then break end
    local id, dur = a.spellId, a.duration
    if type(id) == "number" and type(dur) == "number" and not issecretvalue(id) and not issecretvalue(dur) then
      -- durations come with a few ms of noise (60 one time, 60.001 the next): keep a tenth
      local fp = { duration = math.floor(dur * 10 + 0.5) / 10 }
      local dispel = a.dispelName
      if type(dispel) == "string" and not issecretvalue(dispel) and dispel ~= "" then fp.dispel = dispel end
      for _, k in ipairs(FP_FLAGS) do
        local v = a[k]
        if type(v) == "boolean" and not issecretvalue(v) then fp[k] = v end
      end
      local old = all[id]
      local same = type(old) == "table" and old.duration == fp.duration and old.dispel == fp.dispel
      if same then
        for _, k in ipairs(FP_FLAGS) do if old[k] ~= fp[k] then same = false; break end end
      end
      if not same then all[id] = fp; changed = true end
    end
  end
  if changed then
    for uid in pairs(durWatch) do readd[uid] = true end
    for uid in pairs(fpUsers) do readd[uid] = true end
    for uid in pairs(lateUsers) do readd[uid] = true end
    FlushReadds()
  end
end

-- Property-based displays with a sound take their spell ids from the shared memory: re-register them.
local function RefreshPropertySounds()
  for region, att in pairs(attachments) do
    local plan = att.active and att.want
    local data = plan and plan.nameless and WA.GetData(region.id)
    local acts = data and data.actions
    if data and SoundRoutes(plan) and acts and (SoundSource(acts.start) or SoundSource(acts.finish)) then
      pcall(ApplySounds, att, region, data, plan)
      SetWarning(att, data.uid, "info", (Engine.Explain(data, plan)))
    end
  end
end

-- Units whose auras feed the shared memory. Other players' nameplates are left out (a city would keep
-- it busy for nothing); group members count.
local function Learnable(unit)
  if type(unit) ~= "string" then return false end
  if unit == "player" or unit == "pet" or unit == "target" or unit == "focus" then return true end
  if unit:match("^party%d$") or unit:match("^partypet%d$") or unit:match("^raid%d+$") then return true end
  if unit:match("^nameplate%d+$") then return not UnitIsPlayer(unit) end
  return false
end

local learnDirty, learnQueued = {}, false
local LEARN_PER_SCAN = 12
local function ScanLearnable()
  learnQueued = false
  if not Engine.IsSafe() then wipe(learnDirty); return end
  local seen = AuraSeen()
  if not (seen and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then wipe(learnDirty); return end
  local changed, done = false, 0
  for unit in pairs(learnDirty) do
    learnDirty[unit] = nil
    done = done + 1
    if UnitExists(unit) then
      for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 40 do
          local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
          if not ok or type(a) ~= "table" then break end
          if RecordAura(seen, a, filter, unit) then changed = true end
        end
      end
    end
    if done >= LEARN_PER_SCAN then break end
  end
  if next(learnDirty) and not learnQueued then learnQueued = true; C_Timer.After(1, ScanLearnable) end
  if changed then RefreshPropertySounds() end
end

local function QueueLearn(unit)
  if not Learnable(unit) or not Engine.IsSafe() then return end
  learnDirty[unit] = true
  if not learnQueued then learnQueued = true; C_Timer.After(1, ScanLearnable) end
end

local function QueueLearnGroup()
  for _, u in ipairs({ "player", "pet", "target", "focus" }) do QueueLearn(u) end
  local n = GetNumGroupMembers and GetNumGroupMembers() or 0
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and math.min(n, 40) or math.min(n, 4) do QueueLearn((raid and "raid" or "party") .. i) end
end

local learnEv = CreateFrame("Frame")
Private.frames["ForeverEngine Aura Memory"] = learnEv
learnEv:RegisterEvent("UNIT_AURA")
learnEv:RegisterEvent("PLAYER_REGEN_ENABLED")
learnEv:RegisterEvent("PLAYER_TARGET_CHANGED")
learnEv:RegisterEvent("PLAYER_FOCUS_CHANGED")
learnEv:RegisterEvent("NAME_PLATE_UNIT_ADDED")
learnEv:RegisterEvent("GROUP_ROSTER_UPDATE")
learnEv:RegisterEvent("PLAYER_LOGOUT")
learnEv:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGOUT" then
    -- keep our aura sound ids, so the next session can tell whether the game kept them (CheckStaleSounds)
    local sv = SV()
    if sv then
      sv.foreverEngine = sv.foreverEngine or {}
      local ids = {}
      for _, att in pairs(attachments) do
        for _, sid in ipairs(att.soundIDs or {}) do ids[#ids + 1] = sid end
      end
      sv.foreverEngine.soundIDs = #ids > 0 and ids or nil
    end
    return
  end
  if event == "UNIT_AURA" or event == "NAME_PLATE_UNIT_ADDED" then QueueLearn(unit)
  elseif event == "PLAYER_TARGET_CHANGED" then QueueLearn("target")
  elseif event == "PLAYER_FOCUS_CHANGED" then QueueLearn("focus")
  else QueueLearnGroup() end   -- combat ended (debuffs still on are readable now), group changed
end)

local function LearnFromUnit(unit)
  if UNIT_OK[unit] and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    LearnFingerprints(unit)
  end
  if not UNIT_OK[unit] or not Engine.IsSafe() or not next(watchNames) then return end
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  local learned = Learned()
  if not learned then return end
  local changed = false
  for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
    local i = 1
    while i < 200 do
      local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
      if not ok or type(a) ~= "table" then break end
      local nm, id = a.name, a.spellId
      if type(nm) == "string" and type(id) == "number" and not issecretvalue(nm) and not issecretvalue(id) then
        local key = nm:lower()
        if watchNames[key] then
          learned[key] = learned[key] or {}
          if not learned[key][id] then learned[key][id] = true; changed = true end
        end
      end
      i = i + 1
    end
  end
  if changed then QueueSpellbookRefresh() end   -- bumps the generation: re-classify, re-add, refilter
end

local function LearnFromAllUnits()
  for unit in pairs(UNIT_OK) do LearnFromUnit(unit) end
end

local spellbookDirty = false
local function OnSpellbookChanged()
  spellbookDirty = false
  spellbookGen = spellbookGen + 1
  RefreshSpellbook()
  for uid in pairs(nameWatch) do
    if decided[uid] == false then
      local data = Private.GetDataByUID and Private.GetDataByUID(uid)
      if data and Engine.Classify(data) then readd[uid] = true end
    end
  end
  for region, att in pairs(attachments) do
    if att.want then
      local data = WA.GetData(region.id)
      if data and data.foreverEngineRange == true then att.sig = nil end   -- re-validate the range spell
      if data and (att.want.byName or att.sig == nil) then Engine.Sync(region, data) end
    end
  end
  FlushReadds()
end

QueueSpellbookRefresh = function()
  if spellbookDirty then return end
  spellbookDirty = true
  C_Timer.After(0.3, OnSpellbookChanged)     -- SPELLS_CHANGED bursts at login; coalesce
end

---------------------------------------------------------------------------- events
local REFRESH = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus", UNIT_PET = "pet" }
local ev = CreateFrame("Frame")
Private.frames["ForeverEngine Events"] = ev
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterUnitEvent("UNIT_PET", "player")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterUnitEvent("UNIT_AURA", "player", "target", "focus", "pet")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "UNIT_AURA" then
    LearnFromUnit(arg1)      -- plain data out of combat; a no-op while auras are secret
    return
  end
  if event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "PLAYER_LEVEL_UP" then
    QueueSpellbookRefresh()
    return
  end
  if event == "PLAYER_ENTERING_WORLD" then QueueSpellbookRefresh() end   -- spellbook may not exist at Add time
  if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD" then
    wipe(descDurations)      -- a new rank changes the description
    LearnFromAllUnits()      -- buffs that procced in combat and are still up become readable now
    Engine.Flush()
    for region, att in pairs(attachments) do
      if att.active and att.want and att.soundSig == nil then
        local d = WA.GetData(region.id)
        if d then pcall(ApplySounds, att, region, d, att.want) end
      end
    end
  end
  local unit = REFRESH[event]
  if unit then LearnFromUnit(unit) end
  if unit or event == "PLAYER_ENTERING_WORLD" then pcall(Dyn.UpdateUnit, unit) end
  for _, att in pairs(attachments) do
    -- Inbound secure delegate, PoC-verified in combat. The container refreshes itself only on
    -- UNIT_AURA/UNIT_FACTION/UNIT_FLAGS/PLAYER_REGEN_*; unit swaps are our job.
    if att.active and (event == "PLAYER_ENTERING_WORLD" or att.unit == unit) then
      pcall(att.container.UpdateAllAuras, att.container)
      if att.pclipShown then pcall(att.container2.UpdateAllAuras, att.container2) end
    end
  end
end)

---------------------------------------------------------------------------- kill switch
SLASH_FOREVERENGINE1 = "/faengine"
SlashCmdList["FOREVERENGINE"] = function(msg)
  local sv = SV()
  if not sv then return end
  sv.foreverEngine = sv.foreverEngine or {}
  msg = (msg or ""):lower():gsub("%s", "")
  if msg == "off" then sv.foreverEngine.disabled = true elseif msg == "on" then sv.foreverEngine.disabled = nil end
  local n, g = 0, 0
  for _, att in pairs(attachments) do
    if att.active then n = n + 1; if att.kind == "group" then g = g + 1 end end
  end
  WA.prettyPrint(("engine-driven auras: %s, %d active (%d in 'missing' mode). on/off takes effect after /reload")
    :format(GloballyEnabled() and "on" or "off", n, g))
end
