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
  "useNamePattern", "useIgnoreName", "useIgnoreExactSpellId", "use_debuffClass",
  "useStacks", "useTotal", "use_tooltip", "fetchTooltip", "use_unitName", "use_npcId",
  "use_stealable", "use_isBossDebuff", "use_castByPlayer", "useAffected", "showClones", "useGroup_count",
}

local attachments = setmetatable({}, { __mode = "k" })   -- region -> att
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

-- One aura2 trigger -> its part of the plan. Reasons it cannot be drawn go through no().
local function AnalyseAuraTrigger(t, no)
  local unit = t.unit or "player"
  if not UNIT_OK[unit] then no(T("Unit must be Player, Target, Focus or Pet")) end
  local filter = t.debuffType or "HELPFUL"
  if filter ~= "HELPFUL" and filter ~= "HARMFUL" then no(T("Aura Type must be Buff or Debuff (not Both)")) end
  local mode = MODE[t.matchesShowOn or "showOnActive"]
  if not mode then no(T("'Show On: Match Count' cannot be expressed by the engine")) end
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
  if #sorted == 0 then
    if #unresolved > 0 then
      no(T("'%s' is not one of your spells; the engine takes over once this aura has been seen once out of combat"):format(table.concat(unresolved, ", ")))
    else
      no(T("use 'Exact Spell ID(s)' or a spell Name with at least one entry"))
    end
  elseif byName then
    -- Hostile debuffs carry the cast's id, so the spellbook is enough. Everything else waits until
    -- the aura has been seen: self and friendly buffs often carry a different id than the spell.
    local hostileDebuff = (filter == "HARMFUL") and (unit == "target" or unit == "focus")
    if #unresolved > 0 then
      no(T("'%s' is not one of your spells; the engine takes over once this aura has been seen once out of combat"):format(table.concat(unresolved, ", ")))
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
  table.sort(sorted)
  -- Own Only = the filter's PLAYER token ("cast by you"). AuraData.isFromPlayerOrPlayerPet is true for
  -- any player's aura, so another hunter's Serpent Sting passed it.
  local filterString = (t.ownOnly == true) and (filter .. "|PLAYER") or filter
  return { unit = unit, filter = filter, filterString = filterString, mode = mode, rem = rem,
           candidate = { includeSpellIDs = ids }, ids = sorted, firstId = sorted[1],
           byName = byName, unresolved = unresolved, unseen = unseen,
           key = filterString .. ";" .. table.concat(sorted, ",") }
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
function Engine.Classify(data)
  local r = {}
  local function no(msg)
    for _, m in ipairs(r) do if m == msg then return end end
    r[#r + 1] = msg
  end
  local rt = data and data.regionType
  if rt ~= "icon" and rt ~= "aurabar" then return nil, { T("the display is not an Icon or a Progress Bar") } end
  if not GloballyEnabled() then no(T("the engine is switched off (/faengine on)")) end
  if data.foreverEngine == false then no(T("'Let the game engine draw this aura' is off for this display (Display tab)")) end
  if not Engine.IsAvailable() then no(T("Blizzard_AuraContainer is not available")) end
  if LibStub("Masque", true) then no(T("Masque is loaded")) end
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
    infos[#infos + 1] = AnalyseAuraTrigger(triggers[i].trigger, no)
    auraTriggers[i] = true
  end
  local unit = infos[1].unit
  for _, inf in ipairs(infos) do
    if inf.unit ~= unit then no(T("all Aura triggers must watch the same unit")); break end
  end
  local gates = n - #auraIdx

  if #infos == 1 and not infos[1].rem then
    local inf = infos[1]
    if rt == "aurabar" and inf.mode and inf.mode ~= "active" then   -- MODE maps showOnActive -> "active"
      no(T("Progress Bars are engine-driven with 'Show On: Aura(s) Found' only (so far)"))
    end
    if #r > 0 then return nil, r end
    local key = table.concat({ unit, inf.filterString, inf.mode, table.concat(inf.ids, ",") }, ";")
    return { unit = unit, filter = inf.filter, filterString = inf.filterString, mode = inf.mode,
             candidate = inf.candidate, firstId = inf.firstId, key = key,
             ids = inf.ids, byName = inf.byName, gen = spellbookGen, unresolved = inf.unresolved, unseen = inf.unseen,
             auraTriggers = auraTriggers, gates = gates }
  end

  if rt ~= "icon" then
    no(T("Progress Bars are engine-driven with one Aura trigger without 'Remaining Time' only (so far)"))
  end
  local missing, remaining = nil, {}
  for _, inf in ipairs(infos) do
    if inf.mode == "missing" then
      if missing then no(T("only one Aura trigger may use 'Show On: Aura(s) Missing'")) end
      missing = inf
    elseif inf.mode == "active" then
      if inf.rem then
        remaining[#remaining + 1] = { part = inf, op = inf.rem.op, x = inf.rem.x }
      else
        no(T("'Show On: Aura(s) Found' without 'Remaining Time' cannot be combined with other Aura triggers"))
      end
    elseif inf.mode == "always" then
      no(T("'Show On: Always' cannot be combined with other Aura triggers"))
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
  for _, rp in ipairs(remaining) do
    keys[#keys + 1] = ("R%s%s:%s"):format(rp.op, tostring(rp.x), rp.part.key)
    take(rp.part)
  end
  table.sort(all)
  local first = missing or remaining[1].part
  return { unit = unit, mode = "composite", parts = { missing = missing, remaining = remaining },
           filter = first.filter, filterString = first.filterString, firstId = first.firstId,
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

local MODE_TEXT = {
  active = "shows the live aura while it is present, nothing while it is absent",
  missing = "shows your icon while the aura is absent and disappears completely while it is present",
  always = "shows your icon while the aura is absent and the live aura while it is present",
}
local REM_TEXT = { ["<"] = "less than %s s", ["<="] = "at most %s s", [">"] = "more than %s s", [">="] = "at least %s s" }

-- True when no trigger of this display reads auras (cooldown / usable / range / resource triggers
-- are plain data on Forever, in combat too): the engine has nothing to take over.
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
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s). It shows your icon %s, and nothing otherwise. The game checks the time left itself, so it never has to be read. Kept: position, size, groups, the %%p text, static colour/zoom, and the glow: WeakAuras' own animated glow while the aura is missing, a static glow while it runs out. Not available: the border (hidden while engine-driven), the glow animation while it runs out, cooldown swipe, stack count and desaturation on the time-left icon, conditions and texts that read aura state, show/hide animations and actions on aura gain/loss.")
        :format(plan.unit, table.concat(when, T(" or ")))
    else
      local kept = T("border and glow")
      if data.regionType == "icon" and plan.mode ~= "always" then
        kept = T("the border (also while nothing is drawn), and the glow: shown only while the icon is, and animated like WeakAuras' own")
      end
      txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It %s. Kept: position, size, groups, %%n/%%i texts, static colour/desaturate/zoom, %s. Not available: conditions and texts that read aura state (stacks, remaining, active), show/hide animations and actions on aura gain/loss.")
        :format(plan.unit, plan.filterString, T(MODE_TEXT[plan.mode]), kept)
    end
    if plan.parts and Engine.HasGlowPartChoice(data) and (data.foreverEngineGlowPart or "both") ~= "both" then
      txt = txt .. " " .. (data.foreverEngineGlowPart == "remaining" and T("The glow is drawn only while it runs out.")
                                                                    or T("The glow is drawn only while the aura is missing."))
    end
    if (plan.gates or 0) > 0 then
      txt = txt .. " " .. T("Your other trigger(s) still decide when the display may show at all; WeakAuras checks them itself, which works in combat for plain data (combat state, target attackable or hostile, talents, items, cooldowns) but not for values Forever keeps secret, such as health or power amounts.")
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
  local w, h = region:GetWidth(), region:GetHeight()
  if issecretvalue(w) or issecretvalue(h) then return 32, 32 end
  return math.max(math.floor(w + 0.5), 1), math.max(math.floor(h + 0.5), 1)
end

local function BuildHost(region)
  local host = CreateFrame("Frame", nil, region)
  host:SetAllPoints(region)
  host:SetFrameLevel(region:GetFrameLevel() + 1)
  host:Hide()
  local c = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
  -- TOPLEFT only: the engine sets the container's size (secretly). Nothing of ours ever reads it.
  c:SetPoint("TOPLEFT", host, "TOPLEFT")
  c:SetFrameLevel(host:GetFrameLevel())
  return host, c
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
        s.bar:SetAllPoints(region.bar)
        s.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        s.bar:SetFrameLevel(button:GetFrameLevel() + 1)
        s.barBg:SetAllPoints(s.bar)
        s.icon = button:CreateTexture(nil, "ARTWORK")
        s.icon:SetAllPoints(region.icon)
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
      s.icon = button:CreateTexture(nil, "ARTWORK")
      s.icon:SetAllPoints(button)
      pcall(s.icon.SetSnapToPixelGrid, s.icon, false)
      pcall(s.icon.SetTexelSnappingBias, s.icon, 0)
      s.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
      s.cooldown:SetAllPoints(s.icon)
      pcall(s.cooldown.SetDrawBling, s.cooldown, false)
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
    local clip = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
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

-- WA's SubText resolves selfPoint "AUTO" from the anchor: inside the icon the text hugs that corner,
-- outside it hangs off the opposite side.
local MIRROR = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP",
  TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT", CENTER = "CENTER" }
local function ResolveSelfPoint(sub)
  local sp, ap = sub.text_selfPoint, sub.anchor_point or "CENTER"
  if sp and sp ~= "AUTO" then return sp end
  if ap:sub(1, 6) == "INNER_" then return ap:sub(7) end
  if ap:sub(1, 6) == "OUTER_" then return MIRROR[ap:sub(7)] or "CENTER" end
  return "CENTER"
end

local function StyleShadowText(region, fs, sub, isCount)
  local font = (sub.text_font and LSM:Fetch("font", sub.text_font)) or STANDARD_TEXT_FONT
  local ft = sub.text_fontType
  local flags = (not ft or ft == "None") and "" or ft:gsub("|?SLUG", "")
  fs:SetFont(font, sub.text_fontSize or 12, flags)
  if isCount and sub.text_color then fs:SetTextColor(unpack(sub.text_color)) end -- duration colour is engine-owned
  if sub.text_shadowColor then fs:SetShadowColor(unpack(sub.text_shadowColor)) end
  fs:SetShadowOffset(sub.text_shadowXOffset or 0, sub.text_shadowYOffset or 0)
  fs:SetJustifyH(sub.text_justify or "CENTER")
  region:AnchorSubRegion(fs, "point", sub.anchor_point, ResolveSelfPoint(sub), sub.anchorXOffset, sub.anchorYOffset)
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
          if useShadows then StyleShadowText(region, s.duration, sub, false); s.duration:Show() end
        elseif not haveS and txt == "%s" then
          haveS = true
          if live then att.mirrored[live] = true end
          if useShadows then StyleShadowText(region, s.count, sub, true); s.count:SetAlpha(1) end
        elseif not haveN and txt == "%n" and useShadows and s.name then
          haveN = true
          if live then att.mirrored[live] = true end
          StyleShadowText(region, s.name, sub, true); s.name:SetAlpha(1)
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

local function GlowHolder(att, key, clip)
  local holder = att[key]
  if not holder then
    holder = CreateFrame("Frame", nil, clip)   -- created in the clip: never re-parented
    holder:SetAllPoints(att.host)              -- a plain rect, so its size is readable
    holder:Hide()
    att[key] = holder
  end
  holder:SetFrameLevel(clip:GetFrameLevel() + 2)
  return holder
end

local function StopAnimatedGlow(holder)
  if holder and FG() then pcall(FG().Stop, holder) end
end

local glowReported = false
-- Starts sub's glow on holder; false when it cannot (the caller then draws the static glow).
local function StartAnimatedGlow(holder, sub)
  if not (sub and FG()) then return false end
  local ok, started = pcall(FG().Start, holder, sub)
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

local function ApplyBarLook(att, region, data)
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
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

local function ApplySlotLook(att, region, data, plan)
  if att.isBar then return ApplyBarLook(att, region, data) end
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
  local glowSub = found and GlowSub(data) or nil
  local animated = glowSub and att.pclipShown and StartAnimatedGlow(GlowHolder(att, "pglow", att.pclip), glowSub)
  if not animated then StopAnimatedGlow(att.pglow) end
  if s.glow then
    local w, h = RegionSize(region)
    StyleGlowTexture(s.glow, att.button, w, h, (found and not animated) and GlowSpec(data) or nil)
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
  else
    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(firstId)
  end
  if issecretvalue(tex) then tex = nil end
  return tex or data.displayIcon or 134400
end

-- The underlay copies the WA icon's static look.
local function ApplyUnderlayLook(att, region, data, plan, noGlow)
  local u = att.shadows.underlay
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
  local glowSub = not noGlow and GlowSub(data) or nil
  local animated = glowSub and att.shadows.clip and StartAnimatedGlow(GlowHolder(att, "mglowHolder", att.shadows.clip), glowSub)
  if not animated then StopAnimatedGlow(att.mglowHolder) end
  if att.shadows.mglow then
    local w, h = RegionSize(region)
    StyleGlowTexture(att.shadows.mglow, att.host, w, h, (not noGlow and not animated) and GlowSpec(data) or nil)
  end
  MirrorTexts(att, region, data, false)
  HideStaticDecor(att, region, data, false)
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
  elseif (att.kind == "group" or att.kind == "composite") and region.icon then region.icon:Hide() end
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
  if kind == "composite" and att.rslots then
    for key in pairs(att.rslots) do pcall(c.SetAuraSlotEnabled, c, key, false) end
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

-- Slot keys: feR<i> = the icon of Remaining Time part i, feG<i> = its static glow, feT<i> = its %p countdown.
local LEVEL_OF = { R = 0, G = 1, T = 2 }
local function EnsureComposite(att, region, data, plan)
  local c = att.container
  local missingGlow, remainGlow = GlowParts(data, plan)
  local glow = remainGlow
  if plan.parts.missing then
    local w, h = RegionSize(region)
    if not EnsureGroup(att, region, plan.parts.missing, ClipMargin(w, h, data, missingGlow)) then return false end
  else
    DisableKind(att, "group")
  end
  att.rslots = att.rslots or {}
  local used = {}
  local withText = CountdownSub(data) ~= nil
  for i, rp in ipairs(plan.parts.remaining) do
    local keys = { "feR" .. i }
    if glow then keys[#keys + 1] = "feG" .. i end
    if withText then keys[#keys + 1] = "feT" .. i end
    for _, key in ipairs(keys) do
      used[key] = true
      local rs = att.rslots[key]
      if not rs then
        rs = BuildRemainSlot(att, key, rp.part)
        if not rs then return false end
        att.rslots[key] = rs
      else
        if rs.filter ~= rp.part.filterString then c:SetAuraSlotFilterString(key, rp.part.filterString); rs.filter = rp.part.filterString end
        if rs.pkey ~= rp.part.key then c:SetAuraSlotCandidateFilters(key, rp.part.candidate); rs.pkey = rp.part.key end
        c:SetAuraSlotEnabled(key, true)
      end
    end
  end
  for key in pairs(att.rslots) do
    if not used[key] then pcall(c.SetAuraSlotEnabled, c, key, false) end
  end
  att.rslotsUsed = used
  return true
end

local function SetRemainLevels(att)
  if not (att.rslots and att.container) then return end
  local base = att.container:GetFrameLevel()
  for key, rs in pairs(att.rslots) do
    pcall(rs.button.SetFrameLevel, rs.button, base + (LEVEL_OF[key:sub(3, 3)] or 0))
  end
end

local function ApplyCompositeLook(att, region, data, plan)
  local missingGlow, remainGlow = GlowParts(data, plan)
  if plan.parts.missing then ApplyUnderlayLook(att, region, data, plan.parts.missing, not missingGlow) end
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
      StyleShadowText(region, rt.fs, psub, false)
      local tc = psub.text_color or { 1, 1, 1, 1 }
      rt.button:SetDurationText(rt.fs, {
        textColor = { curve = RemainCurve(rp.op, rp.x, tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1), property = property },
      })
    end
  end
  MirrorTexts(att, region, data, false)     -- WA's own %p/%s/%n would read aura state: hidden
  HideStaticDecor(att, region, data, true)  -- the border cannot follow the curve: hidden too
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
local function TurnOff(att, region, data, mode)
  if att.host then att.host:Hide() end
  DisableKind(att, "slot"); DisableKind(att, "group"); DisableKind(att, "composite")
  StopAnimatedGlow(att.pglow); StopAnimatedGlow(att.mglowHolder)
  RemoveGate(att)
  if att.isBar then SetBarVisuals(region, true) elseif region.icon then region.icon:Show() end
  SetMirroredShown(att, true)
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

  if not att.host then att.host, att.container = BuildHost(region) end
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
    local glowSub = plan.mode == "active" and not att.isBar and GlowSub(data)
    if glowSub then
      local w, h = RegionSize(region)
      att.pclipShown = EnsurePresentClip(att, region, plan, AnimatedGlowMargin(w, h, glowSub))
    else
      DisablePresentClip(att)
    end
  elseif kind == "group" then
    local w, h = RegionSize(region)
    if not EnsureGroup(att, region, plan, ClipMargin(w, h, data, GlowSpec(data))) then TurnOff(att, region, data, "off"); return end
  else
    if not EnsureComposite(att, region, data, plan) then TurnOff(att, region, data, "off"); return end
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
  if att.isBar then SetBarVisuals(region, false) else region.icon:SetShown(plan.mode == "always") end
  if region.tooltipFrame then region.tooltipFrame:EnableMouseMotion(false) end
  if kind == "slot" then pcall(att.button.SetFrameLevel, att.button, c:GetFrameLevel()) end
  if kind == "composite" then SetRemainLevels(att) end
  if att.isBar and att.shadows.bar then                  -- keep bar under texts, both above the button
    local sh = att.shadows
    pcall(sh.bar.SetFrameLevel, sh.bar, c:GetFrameLevel() + 1)
    pcall(sh.texts.SetFrameLevel, sh.texts, c:GetFrameLevel() + 2)
  end
  att.host:Show()
  att.mode, att.active, att.sig = "on", true, att.wantSig
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
    table.concat(data.backgroundColor or {}, ","), table.concat(data.icon_color or {}, ","),
    tostring(data.foreverEngineRange), tostring(data.foreverEngineRangeSpell), tostring(data.foreverEngineGlowPart),
    table.concat(data.color or {}, ","), table.concat({ region.icon:GetTexCoord() }, ",") }
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subtext" then
      parts[#parts + 1] = table.concat({ tostring(sub.text_text), tostring(sub.text_visible), tostring(sub.text_font),
        tostring(sub.text_fontSize), tostring(sub.text_fontType), tostring(sub.anchor_point), tostring(sub.text_selfPoint),
        tostring(sub.anchorXOffset), tostring(sub.anchorYOffset), tostring(sub.text_justify),
        sub.text_color and table.concat(sub.text_color, ",") or "" }, "/")
    elseif sub.type == "subglow" then
      parts[#parts + 1] = table.concat({ "glow", tostring(sub.glow), tostring(sub.useGlowColor),
        sub.glowColor and table.concat(sub.glowColor, ",") or "", tostring(sub.glowScale),
        tostring(sub.glowXOffset), tostring(sub.glowYOffset), tostring(sub.glowType), tostring(sub.glowLines),
        tostring(sub.glowFrequency), tostring(sub.glowLength), tostring(sub.glowThickness), tostring(sub.glowBorder),
        tostring(sub.glowStartAnim), tostring(sub.glowDuration) }, "/")
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
  if not att then att = { region = region, shadows = {}, isBar = data.regionType == "aurabar" }; attachments[region] = att end
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
    if isAura2 and (data.regionType == "icon" or data.regionType == "aurabar") then
      SetWarning(att, data.uid, "info", (Engine.Explain(data)))
    else
      SetWarning(att, data.uid, nil, nil)
    end
    return
  end
  local sig = ComputeSig(region, data, plan)
  att.want, att.wantSig = plan, sig
  SetWarning(att, data.uid, "info", (Engine.Explain(data, plan)))
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

local aurabar = Private.regionTypes and Private.regionTypes.aurabar
if aurabar and aurabar.modify and aurabar.default then
  aurabar.default.foreverEngine = true
  aurabar.default.foreverEngineRange = false
  aurabar.default.foreverEngineRangeSpell = ""
  local origBarModify = aurabar.modify
  aurabar.modify = function(parent, region, data)
    origBarModify(parent, region, data)
    Guard("sync", Engine.Sync, region, data)
  end
end

local origModify = icon.modify
icon.modify = function(parent, region, data)
  origModify(parent, region, data)
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
  if att.pglow and att.pclip then att.pglow:SetFrameLevel(att.pclip:GetFrameLevel() + 2) end
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
  decided[uid], nameWatch[uid], readd[uid] = nil, nil, nil
  for region, att in pairs(attachments) do
    if region.id == id and att.want then att.want = nil; Schedule(region) end
  end
end)
Private.callbacks:RegisterCallback("WA_SECRET_STATE_UPDATE", function() Engine.Flush() end)

---------------------------------------------------------------------------- learning + spellbook events
local QueueSpellbookRefresh   -- defined below

-- Walk a unit's auras while they are plain and remember the ids behind the names our triggers use.
local function LearnFromUnit(unit)
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
    LearnFromAllUnits()      -- buffs that procced in combat and are still up become readable now
    Engine.Flush()
  end
  local unit = REFRESH[event]
  if unit then LearnFromUnit(unit) end
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
