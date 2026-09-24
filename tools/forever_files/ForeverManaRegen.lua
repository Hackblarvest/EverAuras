--[[ ForeverManaRegen.lua - WoW: Forever. A built-in "Mana Regen" trigger that works in combat.

Popular Classic auras track the five-second rule and spirit regen ticks with custom code that
compares UnitPower readings. On Forever UnitPower is secret in combat, so that code errors. This
trigger never compares mana in combat:

  Five Second Rule  starts when you cast a spell that costs mana. Your own cast events carry a
                    readable spell id in combat (probe 2026-09-19) and costs are spell data.
                    Out of combat a readable mana drop starts it too.
  Regen tick        Classic regen arrives in ticks on a fixed rhythm. The rhythm is learned out
                    of combat, where mana is readable, and kept by the clock in combat. If the
                    client turns out to regenerate continuously, the tick mode stays inactive and
                    /eamana says so.
  Hide at full mana only knowable out of combat; in combat the display keeps showing.

Brand-free: works in the upstream tree and after the rename step. Loaded after Prototypes.lua.
]]
local AddonName, Private = ...
local WA = _G[AddonName]
if not (WA and WA.IsForever and WA.IsForever()) then return end
if not (Private and Private.event_prototypes and Private.category_event_prototype) then return end
local L = WA.L
local function T(s) return (L and L[s]) or s end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local FSR = 5
local DEFAULT_TICK = 2
local EVENT = "FOREVER_MANA_UPDATE"

local Mana = {
  fsrExpires = nil,     -- GetTime() when the five-second rule ends
  tickPhase = nil,      -- GetTime() of a regen tick seen out of combat
  tickInterval = DEFAULT_TICK,
  continuous = false,   -- true if the client regenerates in small steps (no ticks to show)
  lastMana = nil,       -- last readable mana, nil while secret
  lastIncrease = nil,
  intervals = {},       -- recent gaps between readable mana increases
  initialized = false,
  tickLoop = 0,
}
Private.ForeverMana = Mana

local function Plain(v) return v ~= nil and not issecretvalue(v) end

local function ReadableMana()
  local ok1, cur = pcall(UnitPower, "player", MANA)
  local ok2, max = pcall(UnitPowerMax, "player", MANA)
  if ok1 and ok2 and Plain(cur) and Plain(max) then return cur, max end
end

local function CostsMana(spellID)
  if not Plain(spellID) then return nil end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
  if not ok or type(costs) ~= "table" then return false end
  for _, c in ipairs(costs) do
    if Plain(c.type) and c.type == MANA and Plain(c.cost) and c.cost > 0 then return true end
  end
  return false
end

local function Fire() Private.ScanEvents(EVENT) end

local function NextTick(now)
  if Mana.continuous or not Mana.tickPhase then return nil end
  local k = math.floor((now - Mana.tickPhase) / Mana.tickInterval) + 1
  return Mana.tickPhase + k * Mana.tickInterval
end

-- One self-rescheduling timer that rescans at every predicted tick. A new phase restarts it.
local function RunTickLoop()
  Mana.tickLoop = Mana.tickLoop + 1
  local token = Mana.tickLoop
  local function step()
    if token ~= Mana.tickLoop then return end
    local now = GetTime()
    local nextTick = NextTick(now)
    if not nextTick then return end
    Fire()
    C_Timer.After(math.max(nextTick - now, 0.05) + 0.01, step)
  end
  step()
end

local function StartFiveSecondRule()
  local now = GetTime()
  Mana.fsrExpires = now + FSR
  Fire()
  C_Timer.After(FSR + 0.02, Fire)
end

-- Learn the regen rhythm from readable increases: gaps near a multiple of ~2 s mean ticks
-- (ticks during the five-second rule may give nothing, so 4 s and 6 s gaps are ticks too);
-- several gaps well under a second mean continuous regen.
local function LearnIncrease(now)
  if Mana.lastIncrease then
    local gap = now - Mana.lastIncrease
    local list = Mana.intervals
    list[#list + 1] = gap
    while #list > 8 do table.remove(list, 1) end
    local small, tick = 0, 0
    for _, g in ipairs(list) do
      if g < 0.9 then small = small + 1 end
      local r = g / DEFAULT_TICK
      if g >= 1.7 and math.abs(r - math.floor(r + 0.5)) * DEFAULT_TICK <= 0.25 then tick = tick + 1 end
    end
    Mana.continuous = small >= 3 and small > tick
  end
  Mana.lastIncrease = now
  if not Mana.continuous then
    local restart = not Mana.tickPhase
    Mana.tickPhase = now
    if restart then RunTickLoop() end
  end
end

local function OnPower()
  local cur = ReadableMana()
  if not cur then Mana.lastMana = nil; return end
  local now = GetTime()
  if Mana.lastMana then
    if cur > Mana.lastMana then
      LearnIncrease(now)
      Fire()
    elseif cur < Mana.lastMana then
      -- a readable drop is mana spent (out of combat); the cast event usually got there first
      if not (Mana.fsrExpires and Mana.fsrExpires - now > FSR - 0.3) then StartFiveSecondRule() end
    end
  end
  Mana.lastMana = cur
end

function Mana.Init()
  if Mana.initialized then return end
  Mana.initialized = true
  local f = CreateFrame("Frame")
  Private.frames["Forever Mana Regen"] = f
  f:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
  f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  f:RegisterEvent("PLAYER_REGEN_ENABLED")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event, unit, arg2, arg3)
    if event == "UNIT_POWER_FREQUENT" then
      if arg2 == "MANA" then OnPower() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if CostsMana(arg3) then StartFiveSecondRule() end
    else
      Mana.lastMana = ReadableMana()   -- leaving combat: compare against a fresh value
      Fire()
    end
  end)
  Mana.lastMana = ReadableMana()
end

-- duration, expirationTime, active, fullKnown
function Mana.GetState(mode)
  local now = GetTime()
  local cur, max = ReadableMana()
  local full = cur and max and max > 0 and cur >= max or false
  if mode == "tick" then
    local nextTick = NextTick(now)
    if not nextTick then return 0, 0, false, full end
    return Mana.tickInterval, nextTick, true, full
  end
  if Mana.fsrExpires and Mana.fsrExpires > now then
    return FSR, Mana.fsrExpires, true, full
  end
  return 0, 0, false, full
end
Private.ExecEnv.ForeverManaState = Mana.GetState

Private.forever_mana_modes = {
  fsr = T("Five Second Rule"),
  tick = T("Next regen tick"),
}

Private.event_prototypes["Forever Mana Regen"] = {
  type = "unit",
  events = {},
  internal_events = { EVENT },
  force_events = EVENT,
  name = T("Mana Regen (Five Second Rule / Tick)"),
  loadFunc = function() Mana.Init() end,
  init = function(trigger)
    local ret = [=[
      local mode = %q
      local hideFull = %s
      local duration, expirationTime, active, full = Private.ExecEnv.ForeverManaState(mode)
      local show = active and not (hideFull and full)
      local name = mode == "tick" and %q or %q
    ]=]
    return ret:format(trigger.mode or "fsr", trigger.use_hideFull and "true" or "false",
      T("Mana Tick"), T("Five Second Rule"))
  end,
  args = {
    {
      name = "mode",
      display = T("Show"),
      type = "select",
      values = "forever_mana_modes",
      required = true,
      test = "true",
    },
    {
      name = "hideFull",
      display = T("Hide at full mana (known out of combat)"),
      type = "toggle",
      test = "true",
    },
    { name = "duration", hidden = true, init = "duration", test = "true", store = true },
    { name = "expirationTime", hidden = true, init = "expirationTime", test = "true", store = true },
    { name = "progressType", hidden = true, init = "'timed'", test = "true", store = true },
    { name = "name", hidden = true, init = "name", test = "true", store = true },
    { hidden = true, test = "show" },
  },
  automaticrequired = true,
  progressType = "timed",
  statesParameter = "one",
}
Private.category_event_prototype.unit = Private.category_event_prototype.unit or {}
Private.category_event_prototype.unit["Forever Mana Regen"] = Private.event_prototypes["Forever Mana Regen"].name

SLASH_FOREVERMANA1 = "/eamana"
SlashCmdList["FOREVERMANA"] = function()
  Mana.Init()
  local cur, max = ReadableMana()
  local gaps = {}
  for _, g in ipairs(Mana.intervals) do gaps[#gaps + 1] = ("%.2f"):format(g) end
  local now = GetTime()
  WA.prettyPrint(("mana %s/%s | regen: %s | interval %.1fs | next tick %s | five second rule %s | recent gaps [%s]"):format(
    cur and tostring(cur) or "secret", max and tostring(max) or "secret",
    Mana.continuous and "continuous (no ticks)" or (Mana.tickPhase and "ticks" or "not learned yet (let mana regenerate out of combat)"),
    Mana.tickInterval,
    NextTick(now) and ("in %.1fs"):format(NextTick(now) - now) or "-",
    (Mana.fsrExpires and Mana.fsrExpires > now) and ("%.1fs left"):format(Mana.fsrExpires - now) or "inactive",
    table.concat(gaps, ", ")))
end
