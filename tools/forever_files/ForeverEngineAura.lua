-- ForeverEngineAura.lua - WoW: Forever.
--
-- Icon displays with ONE exact-spell-id Aura trigger are rendered by Blizzard_AuraContainer
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
  "useRem", "useStacks", "useTotal", "use_tooltip", "fetchTooltip", "use_unitName", "use_npcId",
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
-- Pure function of data (and of the spellbook, for name-based triggers). Returns plan | nil, reasons.
function Engine.Classify(data)
  local r = {}
  local function no(msg) r[#r + 1] = msg end
  if not data or data.regionType ~= "icon" then return nil, { T("the display is not an Icon") } end
  if not GloballyEnabled() then no(T("the engine is switched off (/faengine on)")) end
  if data.foreverEngine == false then no(T("'Let the game engine draw this aura' is off for this display (Display tab)")) end
  if not Engine.IsAvailable() then no(T("Blizzard_AuraContainer is not available")) end
  if LibStub("Masque", true) then no(T("Masque is loaded")) end
  local t = data.triggers and #data.triggers == 1 and data.triggers[1] and data.triggers[1].trigger
  if not t then no(T("the display must have exactly one trigger")); return nil, r end
  if t.type ~= "aura2" then no(T("the trigger is not an Aura trigger")); return nil, r end
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
  if #r > 0 then return nil, r end
  table.sort(sorted)
  local candidate = { includeSpellIDs = ids }
  if t.ownOnly ~= nil then candidate.isFromPlayerOrPlayerPet = (t.ownOnly == true) end
  local key = table.concat({ unit, filter, mode, tostring(t.ownOnly), table.concat(sorted, ",") }, ";")
  return { unit = unit, filter = filter, mode = mode, candidate = candidate, firstId = sorted[1], key = key,
           ids = sorted, byName = byName, gen = spellbookGen, unresolved = unresolved, unseen = unseen }
end

local function InertConditions(data)
  local function bad(check)
    if not check then return false end
    if check.checks then
      for _, c in ipairs(check.checks) do if bad(c) then return true end end
      return false
    end
    return check.trigger == 1 and check.variable ~= nil and check.variable ~= "buffed"
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
    local txt = T("|cff33ff99Engine-driven:|r the game's aura engine draws this aura, also in combat (unit %s, %s). It %s. Kept: position, size, groups, %%n/%%i texts, static colour/desaturate/zoom, border and glow. Not available: conditions and texts that read aura state (stacks, remaining, active), show/hide animations and actions on aura gain/loss.")
      :format(plan.unit, plan.filter, T(MODE_TEXT[plan.mode]))
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
    if InertConditions(data) then
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
  if trigger.useName then
    nameWatch[data.uid] = true
    for _, nm in ipairs(trigger.auranames or {}) do
      nm = Trim(nm)
      local id = tonumber(nm)
      if id and C_Spell and C_Spell.GetSpellName then
        local ok, real = pcall(C_Spell.GetSpellName, id)
        if ok and type(real) == "string" and real ~= "" and not issecretvalue(real) then nm = real else nm = "" end
      end
      if nm ~= "" then watchNames[nm:lower()] = true end
    end
  else
    nameWatch[data.uid] = nil
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
  local ok, button = pcall(c.AddAuraSlot, c, KEY, plan.filter, {
    candidateFilters = plan.candidate,
    initializeFrame = function(button)
      -- Runs synchronously inside AddAuraSlot, BEFORE DenyTaintedAccessWhenAurasAreSecret is applied.
      button:ClearAllPoints()
      button:SetAllPoints(host)
      button:SetFrameLevel(c:GetFrameLevel())
      pcall(button.SetMouseClickEnabled, button, false)   -- click-through like a WA icon
      pcall(button.EnableMouseMotion, button, false)      -- engine tooltip only with data.useTooltip
      pcall(button.SetHideTooltipInCombat, button, false)
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

local function GroupLayout(w, h)
  return { elementWidth = w + 1, elementHeight = h }
end

-- Missing: a group of at most one INVISIBLE button. The container's secret width (1 or W+1) drives a
-- clipping frame that holds the "cast this" underlay: full while absent, zero width while present.
local function BuildGroup(att, region, plan)
  local host, c, s = att.host, att.container, att.shadows
  local w, h = RegionSize(region)
  local ok, err = pcall(c.AddAuraGroup, c, KEY, plan.filter, {
    candidateFilters = plan.candidate,
    maxFrameCount = 1,
    layout = GroupLayout(w, h),
    initializeFrame = function(button)
      -- Ten of these are pre-created per group (the engine hides counts that way). They draw nothing.
      button:SetSize(w + 1, h)
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
  clip:SetPoint("TOPLEFT", c, "TOPRIGHT", -1, 0)
  clip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
  clip:SetFrameLevel(host:GetFrameLevel())
  local u = clip:CreateTexture(nil, "ARTWORK")
  u:SetAllPoints(host)
  pcall(u.SetSnapToPixelGrid, u, false)
  pcall(u.SetTexelSnappingBias, u, 0)
  s.clip, s.underlay = clip, u
  att.groupBuilt, att.groupW, att.groupH = true, w, h
  return true
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
  local haveP, haveS
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
        end
      end
    end
  end
  if useShadows then
    if not haveP then s.duration:Hide() end     -- Shown is not a secret aspect of the duration text
    if not haveS then s.count:SetAlpha(0) end   -- Shown IS secret on the count text; Alpha is ours
  end
end

local function ApplySlotLook(att, region, data)
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
  MirrorTexts(att, region, data, true)
  pcall(att.button.EnableMouseMotion, att.button, data.useTooltip and true or false)
end

-- The underlay copies the WA icon's static look. Its texture is the display's own icon choice:
-- the manual icon when one is set, else the first tracked spell's texture (plain data, safe time).
local function ApplyUnderlayLook(att, region, data, plan)
  local u = att.shadows.underlay
  local tex
  if data.iconSource == 0 and data.displayIcon and data.displayIcon ~= "" then
    tex = data.displayIcon
  else
    tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(plan.firstId)
  end
  if issecretvalue(tex) then tex = nil end
  tex = tex or data.displayIcon or 134400
  if type(tex) == "string" and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(tex) then
    u:SetAtlas(tex)
  else
    u:SetTexture(tex)
  end
  u:SetTexCoord(region.icon:GetTexCoord())
  pcall(u.SetDesaturation, u, data.desaturate and 1 or 0)
  local col = data.color or { 1, 1, 1, 1 }
  u:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1)
  MirrorTexts(att, region, data, false)
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
  if att.kind == "group" and region.icon then region.icon:Hide() end
end

local function InPreview()
  return (WA.IsPaused and WA.IsPaused()) or (WA.IsOptionsOpen and WA.IsOptionsOpen())
end

local function DisableKind(att, kind)
  local c = att.container
  if kind == "slot" and att.slotBuilt then pcall(c.SetAuraSlotEnabled, c, KEY, false) end
  if kind == "group" and att.groupBuilt then
    pcall(c.SetAuraGroupEnabled, c, KEY, false)
    if att.shadows.clip then att.shadows.clip:Hide() end
  end
end

---------------------------------------------------------------------------- range gate
-- Gated at the one choke point every WA alpha path ends in: the region's SetAlpha (data.alpha and
-- 'Alpha' conditions arrive via SetRegionAlpha, fade/pulse animations via SetAnimAlpha; both call
-- self:SetAlpha). The wrapper remembers what WA asked for, applies asked x inRange, and answers
-- GetAlpha with the asked value so animation seeds never see the gated one. A secret answer is folded
-- through C_CurveUtil.EvaluateColorValueFromBoolean (upstream's 'Alpha (Boolean)' path); nil (no valid
-- unit) hides. Shadowing a widget method on the instance has precedent: RegionPrototype.lua keeps
-- RealClearAllPoints the same way.
local rangeTicker

local function GateAlpha(att)
  if not att.gateInstalled then return end
  local base = att.baseAlpha
  if type(base) ~= "number" then base = 1 end        -- type() is fine on a secret; == nil is not
  local r, value = att.inRange, 0
  if issecretvalue(r) then
    local ok, v = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, r, base, 0)
    if ok then value = v end
  elseif r then
    value = base
  end
  att.realSetAlpha(att.region, value)
end

local function SampleRange(att)
  local ok, r = pcall(C_Spell.IsSpellInRange, att.rangeSpell, att.unit)
  att.inRange = nil
  if ok then att.inRange = r end                     -- true / false / nil, untested: a secret must reach GateAlpha
  GateAlpha(att)
end

local function InstallGate(att)
  if att.gateInstalled then return true end
  local region = att.region
  local realSet, realGet = region.SetAlpha, region.GetAlpha
  if type(realSet) ~= "function" or type(realGet) ~= "function" then return false end
  att.shadowedSetAlpha, att.shadowedGetAlpha = rawget(region, "SetAlpha"), rawget(region, "GetAlpha")
  att.realSetAlpha, att.realGetAlpha = realSet, realGet
  local ok, cur = pcall(realGet, region)
  if ok then att.baseAlpha = cur else att.baseAlpha = 1 end   -- cur may be a secret number
  region.SetAlpha = function(_, alpha) att.baseAlpha = alpha; GateAlpha(att) end
  region.GetAlpha = function() return att.baseAlpha end
  att.gateInstalled = true
  return true
end

local function RemoveGate(att)
  if not att.gateInstalled then return end
  local region = att.region
  region.SetAlpha, region.GetAlpha = att.shadowedSetAlpha, att.shadowedGetAlpha   -- nil: back to the widget methods
  att.gateInstalled, att.inRange = false, nil
  local base = att.baseAlpha
  if type(base) ~= "number" then base = region.animAlpha or region.alpha or 1 end
  pcall(att.realSetAlpha, region, base)               -- hand the plain alpha back to WA
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
  DisableKind(att, "slot"); DisableKind(att, "group")
  RemoveGate(att)
  if region.icon then region.icon:Show() end
  SetMirroredShown(att, true)
  if region.tooltipFrame and data then region.tooltipFrame:EnableMouseMotion(data.useTooltip and true or false) end
  att.mode, att.active, att.sig, att.kind = mode, false, nil, nil
end

local function Apply(region)
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
  local kind = (plan.mode == "missing") and "group" or "slot"
  if att.kind and att.kind ~= kind then DisableKind(att, att.kind) end

  if kind == "slot" then
    if not att.slotBuilt then
      if not BuildSlot(att, region, plan) then TurnOff(att, region, data, "off"); return end
      att.slotFilter, att.slotKey = plan.filter, plan.key
    else
      if att.slotFilter ~= plan.filter then c:SetAuraSlotFilterString(KEY, plan.filter); att.slotFilter = plan.filter end
      if att.slotKey ~= plan.key then c:SetAuraSlotCandidateFilters(KEY, plan.candidate); att.slotKey = plan.key end
      c:SetAuraSlotEnabled(KEY, true)
    end
  else
    if not att.groupBuilt then
      if not BuildGroup(att, region, plan) then TurnOff(att, region, data, "off"); return end
      att.groupFilter, att.groupKey = plan.filter, plan.key
    else
      if att.groupFilter ~= plan.filter then c:SetAuraGroupFilterString(KEY, plan.filter); att.groupFilter = plan.filter end
      if att.groupKey ~= plan.key then c:SetAuraGroupCandidateFilters(KEY, plan.candidate); att.groupKey = plan.key end
      local w, h = RegionSize(region)
      if w ~= att.groupW or h ~= att.groupH then
        c:SetAuraGroupLayout(KEY, GroupLayout(w, h)); att.groupW, att.groupH = w, h
      end
      c:SetAuraGroupEnabled(KEY, true)
    end
    att.shadows.clip:Show()
  end
  att.kind = kind
  if att.unit ~= plan.unit then c:SetUnit(plan.unit); att.unit = plan.unit end

  local okLook, err
  if kind == "slot" then okLook, err = pcall(ApplySlotLook, att, region, data)
  else okLook, err = pcall(ApplyUnderlayLook, att, region, data, plan) end
  if not okLook and not att.lookWarned then
    att.lookWarned = true
    WA.prettyPrint(("%s: engine look failed: %s"):format(tostring(region.id), tostring(err)))
  end

  -- Underlay policy: Found = nothing beneath; Always = the WA icon beneath the live aura;
  -- Missing = the WA icon is replaced by our clipped copy.
  region.icon:SetShown(plan.mode == "always")
  if region.tooltipFrame then region.tooltipFrame:EnableMouseMotion(false) end
  if kind == "slot" then pcall(att.button.SetFrameLevel, att.button, c:GetFrameLevel()) end
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
end

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
    tostring(data.foreverEngineRange), tostring(data.foreverEngineRangeSpell),
    table.concat(data.color or {}, ","), table.concat({ region.icon:GetTexCoord() }, ",") }
  for _, sub in ipairs(data.subRegions or {}) do
    if sub.type == "subtext" then
      parts[#parts + 1] = table.concat({ tostring(sub.text_text), tostring(sub.text_visible), tostring(sub.text_font),
        tostring(sub.text_fontSize), tostring(sub.text_fontType), tostring(sub.anchor_point), tostring(sub.text_selfPoint),
        tostring(sub.anchorXOffset), tostring(sub.anchorYOffset), tostring(sub.text_justify),
        sub.text_color and table.concat(sub.text_color, ",") or "" }, "/")
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
  if not att then att = { region = region, shadows = {} }; attachments[region] = att end
  local plan = decided[data.uid]
  local t = data.triggers and #data.triggers == 1 and data.triggers[1] and data.triggers[1].trigger
  local isAura2 = t and t.type == "aura2"
  if plan and not isAura2 then
    -- the trigger side only re-classifies aura2 triggers; a display whose only trigger changed type
    -- would otherwise keep yesterday's plan
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
    if isAura2 and data.regionType == "icon" then
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

---------------------------------------------------------------------------- zero-diff hooks into the core
local icon = Private.regionTypes and Private.regionTypes.icon
if not icon then return end
icon.default.foreverEngine = true            -- per-display opt-out (false); Private.validate fills it in
icon.default.foreverEngineRange = false      -- 'only while the spell is in range of the unit'
icon.default.foreverEngineRangeSpell = ""    -- override for the range-check spell (blank = trigger's spell)

local origModify = icon.modify
icon.modify = function(parent, region, data)
  origModify(parent, region, data)
  Engine.Sync(region, data)
end

local origApplyFrameLevel = Private.ApplyFrameLevel
function Private.ApplyFrameLevel(region, frameLevel)
  origApplyFrameLevel(region, frameLevel)
  local att = attachments[region]
  if not (att and att.active and att.host) then return end
  local base = frameLevel or (Private.frameLevels and Private.frameLevels[region.id]) or 5
  att.host:SetFrameLevel(region:GetFrameLevel() + 1)       -- L+2 (region is L+1 via subbackground)
  att.container:SetFrameLevel(att.host:GetFrameLevel())
  if att.shadows.clip then att.shadows.clip:SetFrameLevel(att.host:GetFrameLevel()) end
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
