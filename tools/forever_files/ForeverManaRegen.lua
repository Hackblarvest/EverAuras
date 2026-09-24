--[[ ForeverManaRegen.lua - WoW: Forever. A built-in "Five Second Rule" trigger that works in combat.

Popular Classic auras track the five-second rule with custom code that compares UnitPower readings.
On Forever the player's current mana is secret even out of combat (probe 2026-09-24: combat=false,
mana=<secret>, max readable), so that code errors. This trigger never reads mana:

  Five Second Rule  starts when a cast of your own costs mana. Your own cast events carry a
                    readable spell id (in combat too) and costs are spell data. Measured on
                    build 69977: regen resumes exactly 5.00 s after the cast, and regen is
                    continuous (~10 updates per second), so there is no tick to track.

The prototype key stays "Forever Mana Regen" so displays made with the first version keep working.
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
local EVENT = "FOREVER_MANA_UPDATE"

local Mana = { fsrExpires = nil, lastSpell = nil, initialized = false }
Private.ForeverMana = Mana

local function Plain(v) return v ~= nil and not issecretvalue(v) end

local function CostsMana(spellID)
  if not Plain(spellID) then return false end
  local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
  if not ok or type(costs) ~= "table" then return false end
  for _, c in ipairs(costs) do
    if Plain(c.type) and c.type == MANA and Plain(c.cost) and c.cost > 0 then return true end
  end
  return false
end

local function Fire() Private.ScanEvents(EVENT) end

local function StartFiveSecondRule(spellID)
  Mana.fsrExpires = GetTime() + FSR
  Mana.lastSpell = spellID
  Fire()
  C_Timer.After(FSR + 0.02, Fire)
end

function Mana.Init()
  if Mana.initialized then return end
  Mana.initialized = true
  local f = CreateFrame("Frame")
  Private.frames["Forever Five Second Rule"] = f
  f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  f:SetScript("OnEvent", function(_, _, _, _, spellID)
    if CostsMana(spellID) then StartFiveSecondRule(spellID) end
  end)
end

-- duration, expirationTime, active
function Mana.GetState()
  local now = GetTime()
  if Mana.fsrExpires and Mana.fsrExpires > now then
    return FSR, Mana.fsrExpires, true
  end
  return 0, 0, false
end
Private.ExecEnv.ForeverManaState = Mana.GetState

Private.event_prototypes["Forever Mana Regen"] = {
  type = "unit",
  events = {},
  internal_events = { EVENT },
  force_events = EVENT,
  name = T("Five Second Rule (mana)"),
  loadFunc = function() Mana.Init() end,
  init = function()
    return ([=[
      local duration, expirationTime, active = Private.ExecEnv.ForeverManaState()
      local name = %q
    ]=]):format(T("Five Second Rule"))
  end,
  args = {
    { name = "duration", hidden = true, init = "duration", test = "true", store = true },
    { name = "expirationTime", hidden = true, init = "expirationTime", test = "true", store = true },
    { name = "progressType", hidden = true, init = "'timed'", test = "true", store = true },
    { name = "name", hidden = true, init = "name", test = "true", store = true },
    { hidden = true, test = "active" },
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
  local now = GetTime()
  local left = Mana.fsrExpires and Mana.fsrExpires - now
  local okN, name = pcall(C_Spell.GetSpellName, Mana.lastSpell or 0)
  WA.prettyPrint(("five second rule: %s | last mana spell: %s"):format(
    (left and left > 0) and ("%.1fs left"):format(left) or "inactive",
    Mana.lastSpell and ("%s (%s)"):format(tostring(Mana.lastSpell), okN and tostring(name) or "?") or "none yet"))
end
