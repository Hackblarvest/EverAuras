-- ForeverCheck.lua: '/ea check'. Which of the game's APIs the engine (ForeverEngineAura.lua) and its helpers
-- draw with are there in this game build, and whether they still take the engine's calls.
--   By name (also in combat): functions, Enum entries (by name; their numbers may change), the aura
--   container's sort constants, and every event the engine and its helpers listen to.
--   Out of combat: plain numbers through the engine's own formatters, and one hidden set of the game's aura
--   containers (never shown, so they watch no unit and read no aura) that gets the calls the engine makes,
--   each in its own pcall, inside the containers' initializeFrame and on the buttons after it.
-- It changes nothing the engine draws. One line per feature, and a last line to paste on Discord. It also
-- runs once by itself after a new game build or EverAuras version, and says something only when the game
-- build changed or a feature is missing.
local AddonName, Private = ...
local WA = _G[AddonName]
if type(WA) ~= "table" or type(Private) ~= "table" or not (WA.IsLibsOK and WA.IsLibsOK()) then return end

local C = {}
Private.ForeverCheck = C
local L = WA.L
local function T(s) return (L and L[s]) or s end
local function Engine() return Private.ForeverEngine end
local function SV() return _G[AddonName .. "Saved"] end
local function Say(msg) if WA.prettyPrint then WA.prettyPrint(msg) else print(msg) end end

local OK, MISSING, CHANGED, FAILED, SKIP = "ok", "missing", "changed", "failed", "skip"

-- a dotted name -> its value, nil when a part is missing
local function Resolve(name)
  local v = _G
  for part in name:gmatch("[^%.]+") do
    if type(v) ~= "table" then return nil end
    v = v[part]
  end
  return v
end

-- What each feature needs. f: a function; v: a value (Enum entries by name); a: a value Blizzard_AuraContainer
-- defines (looked up once it is loaded); e: an event; r: a call (or method) on the hidden containers;
-- b: plain numbers through a formatter; x: the engine itself. fallback: without it the engine cannot build
-- those displays, so WeakAuras draws them (blind in combat); the other features go on without that part.
C.FEATURES = {
  { name = "Engine-driven auras", fallback = true, items = {
      "x:loaded", "x:available", "f:CreateFrame", "f:issecretvalue", "f:C_Secrets.ShouldAurasBeSecret",
      "f:C_AddOns.LoadAddOn", "f:C_AddOns.IsAddOnLoaded", "f:C_Texture.GetAtlasInfo", "f:InCombatLockdown", "f:C_Timer.After",
      "r:frame.DisableUntrustedLayoutScriptsTemplate", "r:container.create", "r:slot.AddAuraSlot", "r:initok.icon",
      "r:init.SetIcon", "r:init.Cooldown", "r:init.SetDurationCooldown", "r:init.SetDurationText",
      "r:init.SetApplicationCount", "r:init.SetMouseClickEnabled", "r:init.EnableMouseMotion",
      "r:post.SetAuraSlotFilterString", "r:post.SetAuraSlotCandidateFilters", "r:post.SetAuraSlotEnabled",
      "r:post.SetUnit", "r:post.UpdateAllAuras",
      "e:PLAYER_REGEN_ENABLED", "e:PLAYER_ENTERING_WORLD", "e:PLAYER_TARGET_CHANGED", "e:PLAYER_FOCUS_CHANGED",
      "e:UNIT_PET" } },
  { name = "Countdown numbers like the buff frame", items = {
      "f:C_StringUtil.CreateNumericRuleFormatter", "r:init.SetCountdownFormatter", "b:countdown" } },
  { name = "Progress Bars", fallback = true, items = {
      "v:Enum.StatusBarTimerDirection.RemainingTime", "v:Enum.StatusBarTimerDirection.ElapsedTime", "r:initok.bar", "r:bar.SetDurationBar", "r:bar.SetSpellName" } },
  { name = "Missing displays and refresh icons", fallback = true, items = {
      "r:missing.AddAuraGroup", "r:ginitok", "r:post.SetAuraGroupLayout", "r:post.SetAuraGroupCandidateFilters" } },
  { name = "Dynamic Groups (packed)", fallback = true, items = {
      "v:AnchorUtil.FlowLayoutAxis.Vertical", "r:post.SetFlowLayoutAxis", "r:post.SetFlowLayoutPadding",
      "r:post.SetAuraGroupFilterString", "r:post.SetAuraGroupEnabled" } },
  { name = "Dynamic Groups sorted by the time left", fallback = true, items = {
      "a:AuraContainerSortMethod.ExpirationOnly", "a:AuraContainerSortDirection.Normal",
      "a:AuraContainerSortDirection.Reverse", "v:AnchorUtil.FlowDirection.Right", "r:sorted.AddAuraGroup",
      "r:ginit.SetIcon", "r:ginit.SetDurationText", "r:post.SetFlowLayoutGrowthDirection",
      "r:post.SetFlowLayoutAnchorPoint" } },
  { name = "Stack Count and conditions on stacks", fallback = true, items = {
      "v:Enum.StatusBarInterpolation.Immediate", "r:initok.stack", "r:stack.SetApplicationBar", "r:post.SetApplicationBar" } },
  { name = "Time left: gates and conditions on the time left", fallback = true, items = {
      "f:C_CurveUtil.CreateColorCurve", "v:Enum.LuaCurveType.Step", "f:CreateColor",
      "v:Enum.DurationTextBindingProperty.RemainingDuration", "v:Enum.NumericRuleFormatRounding.Down",
      "v:Enum.NumericRuleFormatRounding.Up", "b:gate", "r:initok.time", "r:time.SetDurationText.formatter",
      "r:time.SetDurationText.color", "r:post.SetDurationText.formatter" } },
  { name = "Texts: WeakAuras' time format, time and stacks in one", items = {
      "v:Enum.DurationTextBindingProperty.TotalDuration", "f:C_StringUtil.CreateSecondsFormatter",
      "v:Enum.SecondsFormatterInterval.Seconds", "v:Enum.SecondsFormatterInterval.Minutes", "b:timefmt", "b:pair", "r:time.SetApplicationCount",
      "r:post.SetApplicationCount.formatter" } },
  { name = "Start and Finish animations", items = {
      "v:Enum.DurationTextBindingProperty.ElapsedDuration", "r:initok.anim", "r:anim.CreateAnimationGroup", "r:anim.Alpha",
      "r:anim.Scale", "r:anim.Path", "r:anim.CreateControlPoint", "r:anim.SetDurationText.elapsed",
      "r:anim.AddAuraShownAnimation", "r:post.RemoveAuraShownAnimation", "r:post.AddAuraShownAnimation",
      "r:post.ClearDurationText" } },
  { name = "Animated glow, Stop Motion and Models", items = {
      "r:anim.SetLooping", "r:anim.FlipBook", "r:anim.CreateMaskTexture", "r:anim.PlayerModel" } },
  { name = "WeakAuras' border on icons", items = {
      "f:PixelUtil.GetPixelToUIUnitFactor", "e:UI_SCALE_CHANGED", "e:DISPLAY_SIZE_CHANGED" } },
  { name = "Sounds on aura gain and loss", items = {
      "f:C_UnitAuras.AddAuraSound", "f:C_UnitAuras.RemoveAuraSound", "v:Enum.UnitAuraSoundTrigger.Added",
      "v:Enum.UnitAuraSoundTrigger.Removed", "f:C_RestrictedActions.GetAddOnRestrictionState",
      "v:Enum.AddOnRestrictionState.Inactive", "e:ADDON_RESTRICTION_STATE_CHANGED" } },
  { name = "Range gate", items = {
      "f:C_Spell.IsSpellInRange", "f:C_Spell.GetSpellIDForSpellIdentifier", "f:C_Spell.SpellHasRange",
      "f:C_SpellBook.IsSpellKnown", "f:C_Timer.NewTicker", "f:C_CurveUtil.EvaluateColorValueFromBoolean" } },
  { name = "Power gates and resources", items = {
      "f:UnitPowerPercent", "f:C_CurveUtil.CreateCurve", "v:Enum.LuaCurveType.Linear",
      "e:UNIT_POWER_FREQUENT", "e:UNIT_MAXPOWER", "e:UNIT_DISPLAYPOWER" } },
  { name = "Spells, ranks and names", items = {
      "f:C_SpellBook.GetNumSpellBookSkillLines", "f:C_SpellBook.GetSpellBookSkillLineInfo",
      "f:C_SpellBook.GetSpellBookItemInfo", "f:C_Spell.GetSpellName", "f:C_Spell.GetSpellInfo",
      "f:C_Spell.GetSpellDescription", "f:C_Spell.GetSpellTexture", "f:C_Spell.IsSpellPassive",
      "f:C_SpellBook.IsSpellInSpellBook", "v:Enum.SpellBookSpellBank.Player", "f:C_Secrets.GetSpellAuraSecrecy",
      "v:Enum.SecrecyLevel.NeverSecret",
      "e:SPELLS_CHANGED", "e:LEARNED_SPELL_IN_SKILL_LINE", "e:PLAYER_LEVEL_UP" } },
  { name = "Learning from auras out of combat", items = {
      "f:C_UnitAuras.GetAuraDataByIndex", "e:UNIT_AURA", "e:NAME_PLATE_UNIT_ADDED", "e:PLAYER_LOGOUT" } },
  { name = "Five Second Rule", items = {
      "f:C_Spell.GetSpellPowerCost", "v:Enum.PowerType.Mana", "e:UNIT_SPELLCAST_SUCCEEDED" } },
  { name = "Party and raid", items = {
      "f:UnitExists", "f:UnitIsDeadOrGhost", "f:UnitIsConnected", "f:UnitGUID", "f:IsInRaid", "f:UnitIsUnit",
      "f:UnitIsVisible", "f:SecureButton_GetUnit", "e:GROUP_ROSTER_UPDATE", "e:UNIT_FLAGS", "e:UNIT_CONNECTION",
      "e:PLAYER_ALIVE", "e:PLAYER_UNGHOST", "e:PARTY_MEMBER_ENABLE", "e:PARTY_MEMBER_DISABLE", "e:UNIT_PHASE" } },
  { name = "Cooldowns and bars in combat (WeakAuras' own)", items = {
      "f:C_Spell.GetSpellCooldownDuration", "r:has.SetCooldownFromDurationObject", "r:has.SetTimerDuration",
      "f:C_CurveUtil.EvaluateColorValueFromBoolean" } },
}

---------------------------------------------------------------------------- the hidden containers
local FILTER = "HELPFUL|PLAYER"
local CAND = { includeSpellIDs = { [1] = true } }   -- a spell no aura has: the slots stay empty
local SLOT = { icon = "eaCheckI", bar = "eaCheckB", stack = "eaCheckS", time = "eaCheckT", anim = "eaCheckA" }
local GROUP = { missing = "eaCheckM", sorted = "eaCheckR" }

local function Rec(res, key, f, ...)
  if type(f) ~= "function" then res[key] = MISSING; return false end
  local ok, err = pcall(f, ...)
  res[key] = ok and OK or (FAILED .. ": " .. tostring(err))
  return ok, err
end

local function Has(res, key, obj, method)
  res[key] = (obj and type(obj[method]) == "function") and OK or MISSING
end

local function Font(b) return b:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end

-- inside initializeFrame, before the game guards the button: what the engine does there, per kind of slot
local INIT = {
  icon = function(rig, res, b)
    local icon = b:CreateTexture(nil, "ARTWORK")
    local okC, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
    res["init.Cooldown"] = okC and OK or (FAILED .. ": " .. tostring(cd))
    Rec(res, "init.SetMouseClickEnabled", b.SetMouseClickEnabled, b, false)
    Rec(res, "init.EnableMouseMotion", b.EnableMouseMotion, b, false)
    Rec(res, "init.SetIcon", b.SetIcon, b, icon)
    if okC then
      Rec(res, "init.SetDurationCooldown", b.SetDurationCooldown, b, cd)
      local fmt = Private.ForeverAuraCountdownFormatter and Private.ForeverAuraCountdownFormatter()
      if fmt then Rec(res, "init.SetCountdownFormatter", cd.SetCountdownFormatter, cd, fmt)
      else res["init.SetCountdownFormatter"] = MISSING end
      Has(res, "has.SetCooldownFromDurationObject", cd, "SetCooldownFromDurationObject")
    end
    Rec(res, "init.SetDurationText", b.SetDurationText, b, Font(b), nil)
    rig.count = Font(b)
    Rec(res, "init.SetApplicationCount", b.SetApplicationCount, b, rig.count, nil)
  end,
  bar = function(rig, res, b)
    local bar = CreateFrame("StatusBar", nil, b)
    Has(res, "has.SetTimerDuration", bar, "SetTimerDuration")
    local dirs = Enum and Enum.StatusBarTimerDirection
    Rec(res, "bar.SetDurationBar", b.SetDurationBar, b, bar, { direction = dirs and dirs.RemainingTime })
    Rec(res, "bar.SetSpellName", b.SetSpellName, b, Font(b))
  end,
  stack = function(rig, res, b)
    rig.stackBar = CreateFrame("StatusBar", nil, b)
    local I = Enum and Enum.StatusBarInterpolation
    Rec(res, "stack.SetApplicationBar", b.SetApplicationBar, b, rig.stackBar,
        { minApplications = 0, maxApplications = 3, interpolation = I and I.Immediate })
  end,
  time = function(rig, res, b)
    local E = Engine()
    rig.timeText = Font(b)
    local f = E and E.GateFormatter and E.GateFormatter(3, "WWW")
    if f then Rec(res, "time.SetDurationText.formatter", b.SetDurationText, b, rig.timeText, { textFormatter = f })
    else res["time.SetDurationText.formatter"] = MISSING end
    local P = Enum and Enum.DurationTextBindingProperty
    local okC, cc = pcall(function()
      local c = C_CurveUtil.CreateColorCurve()
      c:SetType(Enum.LuaCurveType.Step)
      c:AddPoint(0, CreateColor(1, 0, 0, 1))
      c:AddPoint(3.001, CreateColor(1, 1, 1, 1))
      return c
    end)
    if okC then
      Rec(res, "time.SetDurationText.color", b.SetDurationText, b, Font(b),
          { textColor = { curve = cc, property = P and P.RemainingDuration or 0 } })
    else
      res["time.SetDurationText.color"] = FAILED .. ": " .. tostring(cc)
    end
    rig.pairCount = Font(b)
    Rec(res, "time.SetApplicationCount", b.SetApplicationCount, b, rig.pairCount, nil)
  end,
  anim = function(rig, res, b)
    local target = b:CreateTexture(nil, "ARTWORK")
    local okG, ag = Rec(res, "anim.CreateAnimationGroup", b.CreateAnimationGroup, b)
    if okG and ag then
      for _, what in ipairs({ "Alpha", "Scale", "Path" }) do
        local ok, a = pcall(ag.CreateAnimation, ag, what)
        res["anim." .. what] = (ok and a) and OK or (FAILED .. ": " .. tostring(a))
        if ok and a then
          pcall(a.SetTarget, a, target)
          pcall(a.SetDuration, a, 0.3)
          if what == "Path" then Rec(res, "anim.CreateControlPoint", a.CreateControlPoint, a, nil, nil, 1) end
        end
      end
      rig.ag = ag
      local E, P = Engine(), Enum and Enum.DurationTextBindingProperty
      local f = E and E.GateFormatter and E.GateFormatter(1, "WWW", -60)
      rig.elapsed = Font(b)
      if f then
        Rec(res, "anim.SetDurationText.elapsed", b.SetDurationText, b, rig.elapsed,
            { textFormat = { formatString = "{}", components = { { property = P and P.ElapsedDuration or 2, formatter = f } } } })
      else
        res["anim.SetDurationText.elapsed"] = MISSING
      end
      rig.added = Rec(res, "anim.AddAuraShownAnimation", b.AddAuraShownAnimation, b, ag)
    end
    local okL, loop = pcall(b.CreateAnimationGroup, b)
    if okL and loop then
      Rec(res, "anim.SetLooping", loop.SetLooping, loop, "REPEAT")
      local okF, fb = pcall(loop.CreateAnimation, loop, "FlipBook")
      res["anim.FlipBook"] = (okF and fb) and OK or (FAILED .. ": " .. tostring(fb))
    else
      res["anim.SetLooping"], res["anim.FlipBook"] = FAILED .. ": " .. tostring(loop), FAILED .. ": " .. tostring(loop)
    end
    Rec(res, "anim.CreateMaskTexture", b.CreateMaskTexture, b)
    local okM, m = pcall(CreateFrame, "PlayerModel", nil, b)
    res["anim.PlayerModel"] = (okM and m) and OK or (FAILED .. ": " .. tostring(m))
  end,
}

local function GroupInit(rig, res, b)
  if rig.gInit then return end
  rig.gInit = true
  res["ginitok"] = FAILED .. ": setting up a group button stopped part way"
  local icon = b:CreateTexture(nil, "ARTWORK")
  Rec(res, "ginit.SetIcon", b.SetIcon, b, icon)
  Rec(res, "ginit.SetDurationText", b.SetDurationText, b, Font(b), nil)
  res["ginitok"] = OK
end

-- built once per session (frames stay, and slot keys must be new in a container); later runs only repeat
-- the calls made on the buttons and containers after initializeFrame
local function BuildRig()
  local rig = { res = {}, buttons = {} }
  local res = rig.res
  local okH, host = pcall(CreateFrame, "Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
  res["frame.DisableUntrustedLayoutScriptsTemplate"] = okH and OK or (FAILED .. ": " .. tostring(host))
  if not okH then host = CreateFrame("Frame", nil, UIParent) end
  host:Hide()
  host:SetSize(1, 1)
  host:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 200, -200)
  rig.host = host
  local okC, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
  res["container.create"] = (okC and c) and OK or (FAILED .. ": " .. tostring(c))
  if not (okC and c) then rig.noContainer = true; return rig end
  rig.c = c
  for kind, key in pairs(SLOT) do
    res["initok." .. kind] = MISSING .. ": the game never set the button up"
    local okS, button = pcall(c.AddAuraSlot, c, key, FILTER, { candidateFilters = CAND,
      initializeFrame = function(b)
        local okI, err = pcall(INIT[kind], rig, res, b)
        res["initok." .. kind] = okI and OK or (FAILED .. ": " .. tostring(err))
      end })
    if kind == "icon" then res["slot.AddAuraSlot"] = (okS and button) and OK or (FAILED .. ": " .. tostring(button)) end
    if okS and button then rig.buttons[kind] = button end
  end
  local okG, g = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
  if okG and g then
    rig.g = g
    res["ginitok"] = MISSING .. ": the game never set a group button up"
    local M, D = AuraContainerSortMethod, AuraContainerSortDirection
    local layout = { elementWidth = 20, elementHeight = 20 }
    Rec(res, "missing.AddAuraGroup", g.AddAuraGroup, g, GROUP.missing, FILTER,
        { candidateFilters = CAND, maxFrameCount = 1, layout = layout,
          initializeFrame = function(b) pcall(GroupInit, rig, res, b) end })
    Rec(res, "sorted.AddAuraGroup", g.AddAuraGroup, g, GROUP.sorted, FILTER,
        { candidateFilters = CAND, maxFrameCount = 2, sortMethod = M and M.ExpirationOnly,
          sortDirection = D and D.Normal, layout = { elementWidth = 20, elementHeight = 20, elementSpacing = 2 },
          initializeFrame = function(b) pcall(GroupInit, rig, res, b) end })
  else
    res["missing.AddAuraGroup"] = FAILED .. ": " .. tostring(g)
    res["sorted.AddAuraGroup"] = res["missing.AddAuraGroup"]
  end
  return rig
end

-- after initializeFrame: what the engine calls on the buttons and containers at safe time
local function PostCalls(rig)
  local res, c, g, B, E = rig.res, rig.c, rig.g, rig.buttons, Engine()
  if c then
    Rec(res, "post.SetAuraSlotFilterString", c.SetAuraSlotFilterString, c, SLOT.icon, FILTER)
    Rec(res, "post.SetAuraSlotCandidateFilters", c.SetAuraSlotCandidateFilters, c, SLOT.icon, CAND)
    Rec(res, "post.SetAuraSlotEnabled", c.SetAuraSlotEnabled, c, SLOT.icon, true)
    Rec(res, "post.SetUnit", c.SetUnit, c, "player")
    Rec(res, "post.UpdateAllAuras", c.UpdateAllAuras, c)
  end
  local s, I = B.stack, Enum and Enum.StatusBarInterpolation
  if s and rig.stackBar then
    Rec(res, "post.SetApplicationBar", s.SetApplicationBar, s, rig.stackBar,
        { minApplications = 0, maxApplications = 5, interpolation = I and I.Immediate })
  end
  local t = B.time
  if t and rig.timeText then
    local f = E and E.GateFormatter and E.GateFormatter(5, "WWW")
    if f then Rec(res, "post.SetDurationText.formatter", t.SetDurationText, t, rig.timeText, { textFormatter = f }) end
    local pf = E and E.PairStackFormatter and E.PairStackFormatter(" (", ")")
    if pf and rig.pairCount then
      Rec(res, "post.SetApplicationCount.formatter", t.SetApplicationCount, t, rig.pairCount, { formatter = pf })
    else
      res["post.SetApplicationCount.formatter"] = MISSING
    end
  end
  local a = B.anim
  if a and rig.ag then
    if rig.added then
      Rec(res, "post.RemoveAuraShownAnimation", a.RemoveAuraShownAnimation, a, rig.ag)
      Rec(res, "post.AddAuraShownAnimation", a.AddAuraShownAnimation, a, rig.ag)   -- back, as Configure does
    end
    Rec(res, "post.ClearDurationText", a.ClearDurationText, a)
  end
  if g then
    local A, D = AnchorUtil and AnchorUtil.FlowLayoutAxis, AnchorUtil and AnchorUtil.FlowDirection
    Rec(res, "post.SetAuraGroupLayout", g.SetAuraGroupLayout, g, GROUP.missing, { elementWidth = 21, elementHeight = 21 })
    Rec(res, "post.SetAuraGroupCandidateFilters", g.SetAuraGroupCandidateFilters, g, GROUP.missing, CAND)
    Rec(res, "post.SetAuraGroupFilterString", g.SetAuraGroupFilterString, g, GROUP.missing, FILTER)
    Rec(res, "post.SetAuraGroupEnabled", g.SetAuraGroupEnabled, g, GROUP.missing, true)
    Rec(res, "post.SetFlowLayoutPadding", g.SetFlowLayoutPadding, g, 0, 0, 1, 0)
    if A then Rec(res, "post.SetFlowLayoutAxis", g.SetFlowLayoutAxis, g, A.Horizontal) else res["post.SetFlowLayoutAxis"] = MISSING end
    if D then Rec(res, "post.SetFlowLayoutGrowthDirection", g.SetFlowLayoutGrowthDirection, g, D.Right, D.Down)
    else res["post.SetFlowLayoutGrowthDirection"] = MISSING end
    Rec(res, "post.SetFlowLayoutAnchorPoint", g.SetFlowLayoutAnchorPoint, g, "TOPLEFT")
  end
end

---------------------------------------------------------------------------- plain numbers
local function Reads(f, n, want)
  if not (f and f.FormatNumber) then return MISSING end
  local ok, out = pcall(f.FormatNumber, f, n)
  if not ok then return FAILED .. ": " .. tostring(out) end
  if type(out) ~= "string" or (issecretvalue and issecretvalue(out)) then return CHANGED .. ": no plain text for " .. n end
  if out ~= want then return ("%s: %s reads '%s' (EverAuras expects '%s')"):format(CHANGED, tostring(n), out, want) end
  return OK
end

local function All(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v ~= OK then return v end
  end
  return OK
end

local BEHAVIOUR = {
  countdown = function()
    local f = Private.ForeverAuraCountdownFormatter and Private.ForeverAuraCountdownFormatter()
    if not f then return MISSING end
    return All(Reads(f, 36.4, "36"), Reads(f, 95, "2m"))
  end,
  gate = function()
    local E = Engine()
    local f = E and E.GateFormatter and E.GateFormatter(3, "WWW")
    if not f then return MISSING end
    return All(Reads(f, 2, "WWW2"), Reads(f, 5, "5"))
  end,
  timefmt = function()
    local E = Engine()
    if not (E and E.TimeFormatter) then return MISSING end
    local f = E.TimeFormatter({ eaCheck_p_format = "timed", eaCheck_p_time_format = 0, eaCheck_p_time_precision = 1,
                                eaCheck_p_time_dynamic_threshold = 3 }, "eaCheck_", "p")
    if not f then return MISSING end
    return All(Reads(f, 2.44, "2.4"), Reads(f, 4.2, "5"), Reads(f, 65, "1:05"))
  end,
  pair = function()
    local E = Engine()
    if not (E and E.PairStackFormatter) then return MISSING end
    E.PairStackFormatter(" (", ")")
    local verdict = E.pairRuleOK and E.pairRuleOK[" (\1)"]
    if verdict == true then return OK end
    if verdict == false then return CHANGED .. ": 0 stacks would read '0' in '%p (%s)' texts" end
    return MISSING
  end,
}

---------------------------------------------------------------------------- one run
local function EventOK(name)
  local E = Engine()
  for _, bad in ipairs(E and E.badEvents or {}) do if bad == name then return MISSING end end
  if C_EventUtils and C_EventUtils.IsEventValid then
    local ok, valid = pcall(C_EventUtils.IsEventValid, name)
    if ok and valid == false then return MISSING end
  end
  return OK
end

local function Item(spec, rig, safe, auraLoaded)
  local kind, name = spec:match("^(%a):(.+)$")
  if kind == "f" then return type(Resolve(name)) == "function" and OK or MISSING end
  if kind == "v" then return Resolve(name) ~= nil and OK or MISSING end
  if kind == "a" then
    if not auraLoaded then return SKIP end
    return Resolve(name) ~= nil and OK or MISSING
  end
  if kind == "e" then return EventOK(name) end
  if kind == "x" then
    local E = Engine()
    if name == "loaded" then return (E and E.loaded) and OK or (FAILED .. ": the engine's file stopped part way") end
    if name == "available" then
      if not safe then return SKIP end
      return (E and E.IsAvailable and E.IsAvailable()) and OK or (FAILED .. ": Blizzard_AuraContainer is not available")
    end
  end
  if kind == "b" then
    if not safe then return SKIP end
    local ok, v = pcall(BEHAVIOUR[name])
    return ok and v or (FAILED .. ": " .. tostring(v))
  end
  if kind == "r" then
    if not rig then return SKIP end
    local v = rig.res[name]
    if v == nil and rig.noContainer and not name:find("^has%.") then return FAILED .. ": no aura container to try it on" end
    return v or SKIP
  end
  return SKIP
end

-- every feature's items and verdict; nil rig while auras are secret (names only then)
function C.Collect()
  local E = Engine()
  local safe = not (E and E.IsSafe) or E.IsSafe()
  local auraLoaded = false
  if safe and E and E.IsAvailable then pcall(E.IsAvailable) end
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, l = pcall(C_AddOns.IsAddOnLoaded, "Blizzard_AuraContainer")
    auraLoaded = ok and l and true or false
  end
  local rig
  if safe then
    if not C.rig then
      local ok, r = pcall(BuildRig)
      C.rig = ok and r or { res = { ["container.create"] = FAILED .. ": " .. tostring(r) }, buttons = {}, noContainer = true }
    end
    rig = C.rig
    pcall(PostCalls, rig)
  end
  local out = { safe = safe, features = {}, ok = 0, changed = 0, missing = 0 }
  for _, ft in ipairs(C.FEATURES) do
    local f = { name = ft.name, items = {} }
    local worst, checked = OK, false
    for _, spec in ipairs(ft.items) do
      local v = Item(spec, rig, safe, auraLoaded)
      f.items[#f.items + 1] = { spec = spec, v = v }
      local k = v:match("^(%a+)")
      if k ~= SKIP then checked = true end
      if k == MISSING then worst = MISSING
      elseif (k == CHANGED or k == FAILED) and worst ~= MISSING then worst = CHANGED end
    end
    f.verdict = checked and worst or SKIP
    f.fallback = ft.fallback
    out.features[#out.features + 1] = f
    if f.verdict == MISSING then out.missing = out.missing + 1
    elseif f.verdict == CHANGED then out.changed = out.changed + 1
    elseif f.verdict == OK then out.ok = out.ok + 1 end
  end
  if rig and rig.noContainer then C.rig = nil end   -- tried again next time
  out.combat = InCombatLockdown and InCombatLockdown() or false
  return out
end

---------------------------------------------------------------------------- what it says
local COLOR = { [OK] = "ff33ff99", [MISSING] = "ffff3333", [CHANGED] = "ffff9933", [SKIP] = "ffaaaaaa" }
local WORD = { [OK] = "OK", [MISSING] = "MISSING", [CHANGED] = "CHANGED", [SKIP] = "NOT CHECKED" }

function C.Build()
  local version, build, _, toc = GetBuildInfo()
  return tostring(version), tostring(build), tonumber(toc) or 0
end

local function AddonVersion()
  local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(AddonName, "Version") or "?"
  return (tostring(v):gsub("%+.*$", ""))
end

local function EngineCounts()
  local n, broken = 0, 0
  local list = WA.ForeverEngineDebug and WA.ForeverEngineDebug() or {}
  for _, att in pairs(list) do
    if att.active then n = n + 1 end
    if att.broken then broken = broken + 1 end
  end
  return n, broken
end

local function EngineOn()
  local sv = SV()
  return not (sv and sv.foreverEngine and sv.foreverEngine.disabled)
end

local function BadNames(r)
  local out = {}
  for _, f in ipairs(r.features) do
    if f.verdict == MISSING or f.verdict == CHANGED then out[#out + 1] = f.name end
  end
  return out
end

local function Unsafe(r)
  if r.safe then return "" end
  return r.combat and " (in combat: names only)" or " (auras secret: names only)"
end

-- the line to paste on Discord (in English, for us)
function C.Summary(r)
  local version, build, toc = C.Build()
  local n, broken = EngineCounts()
  local bad = BadNames(r)
  return ("EverAuras %s | %s.%s i%d | engine %s, %d drawn, %d broken | %d OK, %d changed, %d missing%s%s"):format(
    AddonVersion(), version, build, toc, EngineOn() and "on" or "off", n, broken, r.ok, r.changed, r.missing,
    #bad > 0 and (" | " .. table.concat(bad, "; ")) or "", Unsafe(r))
end

local function Problems(f)
  local out = {}
  for _, it in ipairs(f.items) do
    local k = it.v:match("^(%a+)")
    if k == MISSING or k == CHANGED or k == FAILED then
      local name = it.spec:gsub("^%a:", ""):gsub("^post%.", ""):gsub("^init%.", "")
      local why = it.v:match("^%a+: (.+)$")
      if why then why = why:gsub("|", "||") end
      out[#out + 1] = why and (name .. " (" .. why .. ")") or name
    end
  end
  return out
end

function C.Print(r, full)
  local version, build, toc = C.Build()
  local n, broken = EngineCounts()
  Say(T("engine check: game %s (interface %d), EverAuras %s, the engine %s, %d displays drawn by it, %d broken"):format(
    version .. "." .. build, toc, AddonVersion(), EngineOn() and T("on") or T("off (/ea engine on)"), n, broken))
  if WA.IsForever and not WA.IsForever() then Say(T("|cffff9933This client is not WoW: Forever.|r")) end
  if toc ~= 16001 then
    Say(T("|cffff9933This game build has interface %d; EverAuras was made for 16001.|r"):format(toc))
  end
  for _, f in ipairs(r.features) do
    local probs = Problems(f)
    local line = ("|c%s%s|r %s"):format(COLOR[f.verdict], WORD[f.verdict], T(f.name))
    if f.fallback and (f.verdict == MISSING or f.verdict == CHANGED) then line = line .. T(" (falls back to WeakAuras)") end
    if #probs > 0 then line = line .. ": " .. table.concat(probs, ", ") end
    print(line)
    if full then
      for _, it in ipairs(f.items) do
        local k = it.v:match("^(%a+)")
        print(("    |c%s%s|r %s"):format(COLOR[k == FAILED and CHANGED or k] or COLOR[SKIP], it.spec,
          k == OK and "" or (it.v:gsub("|", "||"))))
      end
    end
  end
  if not r.safe then
    Say(r.combat and T("In combat the check reads names only; the rest runs when combat ends.")
        or T("While auras are secret (a boss encounter, a PvP match) the check reads names only; the rest runs once they can be read."))
  end
  if r.missing + r.changed > 0 then
    local fallback = false
    for _, f in ipairs(r.features) do
      if f.fallback and (f.verdict == MISSING or f.verdict == CHANGED) then fallback = true end
    end
    if fallback then
      Say(T("Displays that need a MISSING or CHANGED feature marked above fall back to WeakAuras' own drawing (blind in combat); the rest go on without that part."))
    else
      Say(T("The engine still draws its displays; only what is MISSING or CHANGED does not work (for example no sound, no gate, the game's own countdown)."))
    end
    Say(T("Please post the line below on our Discord. Turn the engine off ('/ea engine off') only if it draws something wrong."))
  end
  print(C.Summary(r))
end

-- the last result, kept with the build it was made on
local function Store(r)
  local sv = SV()
  if not sv then return end
  sv.foreverEngine = sv.foreverEngine or {}
  local version, build, toc = C.Build()
  local bad = {}
  for _, f in ipairs(r.features) do
    if f.verdict == MISSING or f.verdict == CHANGED then bad[#bad + 1] = f.name end
  end
  sv.foreverEngine.check = { version = version, build = build, toc = toc, addon = AddonVersion(),
                             at = time and time() or 0, bad = bad }
end

-- '/ea check' and '/ea check full'
function C.Run(arg)
  local full = arg == "full"
  local r = C.Collect()
  C.Print(r, full)
  if r.safe then Store(r) else C.queued = full and "full" or "" end
end

---------------------------------------------------------------------------- by itself
-- Once after the world loads (and is safe): when the game build or EverAuras changed since the last result.
-- A new build says one line either way; a new EverAuras, or the first run, only when something is wrong.
function C.Auto()
  local E = Engine()
  if not E then return end
  if E.IsSafe and not E.IsSafe() then C.autoQueued = true; return end
  C.autoQueued = nil
  local sv = SV()
  local last = sv and sv.foreverEngine and sv.foreverEngine.check
  local version, build, toc = C.Build()
  if last and last.build == build and last.toc == toc and last.addon == AddonVersion() then return end
  local r = C.Collect()
  Store(r)
  local bad = r.missing + r.changed
  local newBuild = last and (last.build ~= build or last.toc ~= toc)
  if bad > 0 then
    local names = {}
    for _, f in ipairs(r.features) do
      if f.verdict == MISSING or f.verdict == CHANGED then names[#names + 1] = T(f.name) end
    end
    Say((newBuild and T("|cffff9933engine check: %d feature(s) changed in this game build (%s): type /ea check|r")
         or T("|cffff9933engine check: %d feature(s) missing or changed (%s): type /ea check|r")):format(bad, table.concat(names, ", ")))
  elseif newBuild then
    Say(T("engine check: the game build changed (%s -> %s), the engine's APIs are all there"):format(
      tostring(last.version) .. "." .. tostring(last.build), version .. "." .. build))
  end
end

local ev = CreateFrame("Frame")
Private.frames = Private.frames or {}
Private.frames["Forever Check"] = ev
pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_ENTERING_WORLD" then
    if C.autoDone then return end
    C.autoDone = true
    if C_Timer and C_Timer.After then C_Timer.After(5, function() pcall(C.Auto) end) else pcall(C.Auto) end
  elseif event == "PLAYER_REGEN_ENABLED" then
    C.Retry()
  end
end)

-- a check asked for while it was not safe, and the run by itself: once it is (still not: they keep waiting,
-- silently), after combat or when auras stop being secret
function C.Retry()
  if not (C.queued or C.autoQueued) or not (C_Timer and C_Timer.After) then return end
  C_Timer.After(1, function()
    local E = Engine()
    if E and E.IsSafe and not E.IsSafe() then return end
    if C.queued then local q = C.queued; C.queued = nil; pcall(C.Run, q) end
    if C.autoQueued then pcall(C.Auto) end
  end)
end
if Private.callbacks and Private.callbacks.RegisterCallback then
  Private.callbacks:RegisterCallback("WA_SECRET_STATE_UPDATE", function() pcall(C.Retry) end)
end
