--[[ ForeverGate.lua - WoW: Forever. Display gates that act on values addons may not read.

One owner for the two widget methods these features shadow, so they can be combined safely:

  alpha   the region's SetAlpha/GetAlpha. Every WA alpha path ends in self:SetAlpha (data.alpha and
          'Alpha' conditions via SetRegionAlpha, fade/pulse animations via SetAnimAlpha). The wrapper
          remembers the requested ("base") alpha and applies it through the active factors; GetAlpha
          answers with the base so animation seeds never see a gated value.
            range  (engine-driven displays) in range -> base, out of range / no unit -> 0. A secret
                   answer goes through C_CurveUtil.EvaluateColorValueFromBoolean.
            power  "hide while full": UnitPowerPercent evaluated against a curve whose output is
                   the base alpha below full and 0 at full. The result is secret; only the engine
                   ever sees the percentage.
  colour  the SetVertexColor of the display's own texture (Icon: the icon; Progress Bar: the bar
          foreground). Below the threshold the low colour, else the requested colour, again through
          UnitPowerPercent + curves (one per channel).

The player's current mana is secret even out of combat on Forever (measured 2026-09-24), so these
are the only ways to act on it. Shadowing widget methods on the instance has precedent in
RegionPrototype.lua (RealClearAllPoints). Loaded after ForeverEngineAura.lua, which looks it up
at call time.
Brand-free: works in the upstream tree and after the rename step.
]]
local AddonName, Private = ...
local WA = _G[AddonName]
if not (WA and WA.IsForever and WA.IsForever()) then return end
if not Private then return end
local L = WA.L
local function T(s) return (L and L[s]) or s end

local G = {}
Private.ForeverGate = G
local gates = setmetatable({}, { __mode = "k" })     -- region -> state
-- Curves are LINEAR with a near-vertical edge: the documentation does not say which side a Step
-- curve takes between two points, a linear ramp over 0.0001 is unambiguous either way.
local FULL_EDGE = { 0.9994, 0.9995 }                  -- percent is 0..1; the float at full may be a hair short
local EDGE = 0.0005

local function State(region)
  local st = gates[region]
  if not st then st = { region = region }; gates[region] = st end
  return st
end

local function NewCurve()
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
  local ok, c = pcall(C_CurveUtil.CreateCurve)
  if not ok or not c then return nil end
  local linear = Enum and Enum.LuaCurveType and Enum.LuaCurveType.Linear
  if linear then pcall(c.SetType, c, linear) end
  return c
end

-- value `below` up to x1, value `above` from x2 on, over the whole 0..1 range
local function SetEdge(c, below, above, x1, x2)
  pcall(c.ClearPoints, c)
  pcall(c.AddPoint, c, 0, below)
  pcall(c.AddPoint, c, x1, below)
  pcall(c.AddPoint, c, x2, above)
  pcall(c.AddPoint, c, 1, above)
end

local function Percent(unit, ptype, curve)
  if not UnitPowerPercent then return nil end
  local ok, v = pcall(UnitPowerPercent, unit, ptype, false, curve)
  if ok then return v end
end

---------------------------------------------------------------------------- alpha
local function PowerAlpha(st, base)
  local p = st.power
  if issecretvalue(base) then return base end         -- cannot bake a secret into a curve; leave it
  if p.curveBase ~= base then SetEdge(p.curve, base, 0, FULL_EDGE[1], FULL_EDGE[2]); p.curveBase = base end
  local v = Percent(p.unit, p.ptype, p.curve)
  if v == nil then return base end
  return v
end

local function ApplyAlpha(st)
  if not st.alphaInstalled then return end
  local base = st.base
  if type(base) ~= "number" then base = 1 end          -- type() is fine on a secret; == nil is not
  local value = base
  if st.power then value = PowerAlpha(st, base) end
  if st.rangeOn then
    local r = st.inRange
    if issecretvalue(r) then
      local ok, v = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, r, value, 0)
      if ok then value = v else value = 0 end
    elseif not r then
      value = 0
    end
  end
  st.realSet(st.region, value)
end

local function InstallAlpha(st)
  if st.alphaInstalled then return true end
  local region = st.region
  local realSet, realGet = region.SetAlpha, region.GetAlpha
  if type(realSet) ~= "function" or type(realGet) ~= "function" then return false end
  st.shadowSet, st.shadowGet = rawget(region, "SetAlpha"), rawget(region, "GetAlpha")
  st.realSet, st.realGet = realSet, realGet
  local ok, cur = pcall(realGet, region)
  if ok then st.base = cur else st.base = 1 end        -- cur may be a secret number
  region.SetAlpha = function(_, alpha) st.base = alpha; ApplyAlpha(st) end
  region.GetAlpha = function() return st.base end
  st.alphaInstalled = true
  return true
end

local function RemoveAlphaIfUnused(st)
  if not st.alphaInstalled or st.rangeOn or st.power then return end
  local region = st.region
  region.SetAlpha, region.GetAlpha = st.shadowSet, st.shadowGet   -- nil: back to the widget methods
  st.alphaInstalled = false
  local base = st.base
  if type(base) ~= "number" then base = region.animAlpha or region.alpha or 1 end
  pcall(st.realSet, region, base)                      -- hand the plain alpha back to WA
end

-- range: inRange is true / false / nil / a secret boolean
function G.SetRange(region, inRange)
  local st = State(region)
  if not InstallAlpha(st) then return false end
  st.rangeOn, st.inRange = true, inRange
  ApplyAlpha(st)
  return true
end

function G.ClearRange(region)
  local st = gates[region]
  if not (st and st.rangeOn) then return end
  st.rangeOn, st.inRange = false, nil
  ApplyAlpha(st)
  RemoveAlphaIfUnused(st)
end

---------------------------------------------------------------------------- watched units
local watched = {}   -- unit -> true while any gate uses it
local function Watch(unit) watched[unit] = true end

---------------------------------------------------------------------------- power: hide while full
function G.SetPowerHide(region, unit, ptype)
  local st = State(region)
  local p = st.power
  if not p then
    local curve = NewCurve()
    if not curve or not UnitPowerPercent then return false end
    p = { curve = curve }
  end
  if not InstallAlpha(st) then return false end
  p.unit, p.ptype = unit, ptype
  st.power = p
  Watch(unit)
  ApplyAlpha(st)
  return true
end

function G.ClearPowerHide(region)
  local st = gates[region]
  if not (st and st.power) then return end
  st.power = nil
  ApplyAlpha(st)
  RemoveAlphaIfUnused(st)
end

---------------------------------------------------------------------------- power: colour below a threshold
local function ApplyColor(st)
  local c = st.color
  if not c then return end
  local n = c.normal
  local r, g, b, a = n[1] or 1, n[2] or 1, n[3] or 1, n[4] or 1
  if issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or issecretvalue(a) then
    c.realSet(c.texture, r, g, b, a)                   -- a secret colour cannot go into a curve
    return
  end
  local low = c.low
  local key = table.concat({ r, g, b, a, low[1], low[2], low[3], low[4], c.threshold }, ",")
  if key ~= c.key then
    local want = { r, g, b, a }
    for i = 1, 4 do SetEdge(c.curves[i], low[i], want[i], c.threshold - EDGE, c.threshold) end
    c.key = key
  end
  local out = {}
  local want = { r, g, b, a }
  for i = 1, 4 do
    local v = Percent(c.unit, c.ptype, c.curves[i])
    if v == nil then v = want[i] end
    out[i] = v
  end
  c.realSet(c.texture, out[1], out[2], out[3], out[4])
end

-- texture: the texture to colour; normal: {r,g,b,a} the display asks for; low: {r,g,b,a};
-- threshold: 0..1
function G.SetPowerColor(region, texture, unit, ptype, threshold, low, normal)
  if not (texture and texture.SetVertexColor and UnitPowerPercent) then return false end
  local st = State(region)
  local c = st.color
  if c and c.texture ~= texture then G.ClearPowerColor(region); c = nil end
  if not c then
    local curves = {}
    for i = 1, 4 do
      curves[i] = NewCurve()
      if not curves[i] then return false end
    end
    c = { texture = texture, curves = curves }
    c.realSet = texture.SetVertexColor
    c.shadow = rawget(texture, "SetVertexColor")
    texture.SetVertexColor = function(_, r, g, b, a) c.normal = { r, g, b, a }; ApplyColor(st) end
    st.color = c
  end
  c.unit, c.ptype = unit, ptype
  c.threshold = math.min(math.max(threshold or 0.3, 0.01), 0.99)
  c.low = { low and low[1] or 1, low and low[2] or 0.25, low and low[3] or 0.25, low and low[4] or 1 }
  c.normal = normal and { normal[1], normal[2], normal[3], normal[4] } or { 1, 1, 1, 1 }
  c.key = nil
  Watch(unit)
  ApplyColor(st)
  return true
end

function G.ClearPowerColor(region)
  local st = gates[region]
  local c = st and st.color
  if not c then return end
  st.color = nil
  c.texture.SetVertexColor = c.shadow                   -- nil: back to the widget method
  local n = c.normal or {}
  pcall(c.realSet, c.texture, n[1] or 1, n[2] or 1, n[3] or 1, n[4] or 1)
end

---------------------------------------------------------------------------- events
local UNIT_OF = { PLAYER_TARGET_CHANGED = "target", PLAYER_FOCUS_CHANGED = "focus", UNIT_PET = "pet" }
local ev = CreateFrame("Frame")
Private.frames = Private.frames or {}
Private.frames["Forever Gates"] = ev
ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player", "target", "focus", "pet")
ev:RegisterUnitEvent("UNIT_MAXPOWER", "player", "target", "focus", "pet")
ev:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player", "target", "focus", "pet")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterUnitEvent("UNIT_PET", "player")
ev:SetScript("OnEvent", function(_, event, unit)
  unit = UNIT_OF[event] or unit
  if not watched[unit] then return end
  for _, st in pairs(gates) do
    if st.power and st.power.unit == unit then ApplyAlpha(st) end
    if st.color and st.color.unit == unit then ApplyColor(st) end
  end
end)

---------------------------------------------------------------------------- per-display options
local POWER_DEFAULTS = {
  foreverPowerHide = false, foreverPowerColor = false, foreverPowerUnit = "player", foreverPowerType = 0,
  foreverPowerThreshold = 30, foreverPowerLowColor = { 1, 0.25, 0.25, 1 },
}

local function PowerTexture(region, data)
  if data.regionType == "icon" then return region.icon, data.color end
  if data.regionType == "aurabar" then return region.bar and region.bar.fg, data.barColor end
end

local function ApplyPowerOptions(region, data)
  if not (region and data) then return end
  local unit = data.foreverPowerUnit or "player"
  local ptype = tonumber(data.foreverPowerType) or 0
  if data.foreverPowerHide then G.SetPowerHide(region, unit, ptype) else G.ClearPowerHide(region) end
  local tex, normal = PowerTexture(region, data)
  if data.foreverPowerColor and tex then
    G.SetPowerColor(region, tex, unit, ptype, (tonumber(data.foreverPowerThreshold) or 30) / 100,
      data.foreverPowerLowColor, normal)
  else
    G.ClearPowerColor(region)
  end
end
G.ApplyPowerOptions = ApplyPowerOptions

for _, rt in ipairs({ "icon", "aurabar" }) do
  local regionType = Private.regionTypes and Private.regionTypes[rt]
  if regionType and regionType.modify and regionType.default then
    for k, v in pairs(POWER_DEFAULTS) do
      if regionType.default[k] == nil then regionType.default[k] = v end
    end
    local origModify = regionType.modify
    regionType.modify = function(parent, region, data)
      origModify(parent, region, data)
      local ok, err = pcall(ApplyPowerOptions, region, data)
      if not ok and not G.warned then
        G.warned = true
        WA.prettyPrint(("%s: power gate failed: %s"):format(tostring(data and data.id), tostring(err)))
      end
    end
  end
end

G.T = T
