-- ForeverEngineAuraOptions.lua - WoW: Forever. Options-side companion of ForeverEngineAura.lua.
-- Zero diff to upstream option files: wraps the Icon region options and the Aura trigger options
-- from inside the registerRegions closure, which the options addon runs once it has a Private.
-- Brand-free: works in the upstream tree and after the rename step.
local AddonName, OptionsPrivate = ...
local CoreName = AddonName:gsub("Options$", "")
local WA = _G[CoreName]
if not WA or not WA.IsLibsOK or not WA.IsLibsOK() then return end
local L = WA.L

-- L may be a plain table without a metatable in this fork; never let a missing key blow up.
local function T(s) return (L and L[s]) or s end

OptionsPrivate.registerRegions = OptionsPrivate.registerRegions or {}
table.insert(OptionsPrivate.registerRegions, function()
  local Private = OptionsPrivate.Private
  local Engine = Private and Private.ForeverEngine
  if not Engine then return end

  -- Power gates (ForeverGate.lua): hide while full / colour below a threshold, for Icons and Progress
  -- Bars, engine-driven or not. The values are secret on Forever; Blizzard evaluates them for us.
  local POWER_UNITS = { player = T("Player"), target = T("Target"), focus = T("Focus"), pet = T("Pet") }
  local POWER_TYPES = { [0] = T("Mana"), [1] = T("Rage"), [3] = T("Energy"), [2] = T("Focus") }
  local function AddPowerOptions(group, data, base)
    local function redo()
      WA.Add(data)
      if WA.ClearAndUpdateOptions then WA.ClearAndUpdateOptions(data.id) end
    end
    local function any() return data.foreverPowerHide or data.foreverPowerColor end
    group.foreverPowerHeader = { type = "header", order = base, name = T("Power (WoW: Forever)") }
    group.foreverPowerNote = {
      type = "description", order = base + 0.01, width = WA.doubleWidth, fontSize = "medium",
      name = T("Resource values are secret to addons on Forever (your mana even out of combat). These options let the game compare them for you, so they also work in combat."),
    }
    group.foreverPowerHide = {
      type = "toggle", order = base + 0.02, width = WA.normalWidth,
      name = T("Hide while full"),
      desc = T("Hides the display while the chosen resource is full. Shown again as soon as any is missing."),
      get = function() return data.foreverPowerHide == true end,
      set = function(_, v) data.foreverPowerHide = v and true or false; redo() end,
    }
    group.foreverPowerColor = {
      type = "toggle", order = base + 0.03, width = WA.normalWidth,
      name = T("Colour below a threshold"),
      desc = T("Colours the icon or the bar with the low colour while the resource is below the threshold. Applies to the display's own icon or bar texture (not to an engine-drawn aura icon, and not to a gradient bar)."),
      get = function() return data.foreverPowerColor == true end,
      set = function(_, v) data.foreverPowerColor = v and true or false; redo() end,
    }
    group.foreverPowerUnit = {
      type = "select", order = base + 0.04, width = WA.normalWidth,
      name = T("Unit"), values = POWER_UNITS,
      get = function() return data.foreverPowerUnit or "player" end,
      set = function(_, v) data.foreverPowerUnit = v; WA.Add(data) end,
      hidden = function() return not any() end,
    }
    group.foreverPowerType = {
      type = "select", order = base + 0.05, width = WA.normalWidth,
      name = T("Resource"), values = POWER_TYPES,
      get = function() return tonumber(data.foreverPowerType) or 0 end,
      set = function(_, v) data.foreverPowerType = tonumber(v) or 0; WA.Add(data) end,
      hidden = function() return not any() end,
    }
    group.foreverPowerThreshold = {
      type = "range", order = base + 0.06, width = WA.normalWidth,
      name = T("Threshold (%)"), min = 1, max = 99, step = 1,
      get = function() return tonumber(data.foreverPowerThreshold) or 30 end,
      set = function(_, v) data.foreverPowerThreshold = v; WA.Add(data) end,
      hidden = function() return not data.foreverPowerColor end,
    }
    group.foreverPowerLowColor = {
      type = "color", order = base + 0.07, width = WA.normalWidth, hasAlpha = true,
      name = T("Low colour"),
      get = function()
        local c = data.foreverPowerLowColor or { 1, 0.25, 0.25, 1 }
        return c[1], c[2], c[3], c[4]
      end,
      set = function(_, r, g, b, a) data.foreverPowerLowColor = { r, g, b, a }; WA.Add(data) end,
      hidden = function() return not data.foreverPowerColor end,
    }
  end

  -- Engine section (status, opt-out, range gate) for Icons and Progress Bars alike.
  local function AddEngineOptions(group, data)
    group.foreverEngineHeader = {
      type = "header", order = 100.1,
      name = T("Engine-driven aura (WoW: Forever)"),
    }
    group.foreverEngineStatus = {
      type = "description", order = 100.2, width = WA.doubleWidth, fontSize = "medium",
      name = function() return (Engine.Explain(data)) end,
    }
    group.foreverEngine = {
      type = "toggle", order = 100.3, width = WA.doubleWidth,
      name = T("Let the game engine draw this aura"),
      desc = T("Needs exactly one Aura trigger (spell names or Exact Spell IDs) on Player, Target, Focus or Pet, Buff or Debuff (not Both). Icons: Show On Found / Missing / Always. Progress Bars: Show On Found. Off = the classic scanner, which is blind while auras are secret (combat)."),
      get = function() return data.foreverEngine ~= false end,
      -- A full (non-simple) re-add so BuffTrigger.Add re-classifies the trigger; the plain
      -- framework setter would only re-run the region modify and leave the trigger side stale.
      set = function(_, v)
        data.foreverEngine = v and true or false
        WA.Add(data)
        if WA.ClearAndUpdateOptions then WA.ClearAndUpdateOptions(data.id) end
      end,
      hidden = function() return Engine.HasNoAuraTrigger and Engine.HasNoAuraTrigger(data) end,
    }
    local function gateHidden(needToggle)
      if data.foreverEngine == false then return true end
      if Engine.HasNoAuraTrigger and Engine.HasNoAuraTrigger(data) then return true end
      if needToggle and data.foreverEngineRange ~= true then return true end
      local plan = Engine.Classify(data)
      return not plan or plan.unit == "player"
    end
    group.foreverEngineRange = {
      type = "toggle", order = 100.4, width = WA.doubleWidth,
      name = T("Only while the spell is in range of the unit"),
      desc = T("Hides the display unless the trigger's spell can reach the unit right now (C_Spell.IsSpellInRange: the spell's own minimum and maximum range, sampled 5x per second, also in combat). Hidden while there is no valid unit. The display's own alpha, conditions and animations still apply on top. The spell must be one you know that has a range; the status line above says when it is not."),
      get = function() return data.foreverEngineRange == true end,
      set = function(_, v)
        data.foreverEngineRange = v and true or false
        WA.Add(data)
        if WA.ClearAndUpdateOptions then WA.ClearAndUpdateOptions(data.id) end
      end,
      hidden = function() return gateHidden(false) end,
    }
    group.foreverEngineRangeSpell = {
      type = "input", order = 100.5, width = WA.doubleWidth,
      name = T("Range check spell (blank = the trigger's spell)"),
      desc = T("Name or id of the spell whose range is checked, for example Auto Shot for a hunter's 8-35 yd window. Blank uses the name of the lowest tracked spell id, i.e. the rank you know."),
      get = function() return data.foreverEngineRangeSpell or "" end,
      set = function(_, v)
        data.foreverEngineRangeSpell = strtrim(v or "")
        WA.Add(data)
        if WA.ClearAndUpdateOptions then WA.ClearAndUpdateOptions(data.id) end
      end,
      hidden = function() return gateHidden(true) end,
    }
  end

  local barOptions = Private.regionOptions and Private.regionOptions.aurabar
  if barOptions and barOptions.create and not barOptions.foreverPowerWrapped then
    barOptions.foreverPowerWrapped = true
    local origBarCreate = barOptions.create
    barOptions.create = function(id, data)
      local options = origBarCreate(id, data)
      local group = type(options) == "table" and options.aurabar
      if type(group) == "table" then
        AddEngineOptions(group, data)
        AddPowerOptions(group, data, 101)
      end
      return options
    end
  end

  -- Icon region options: a status line, a per-display opt-out and the range gate. Entries without
  -- 'set' get the framework setter, exactly like 'cooldown' in RegionOptions/Icon.lua.
  local iconOptions = Private.regionOptions and Private.regionOptions.icon
  if iconOptions and iconOptions.create and not iconOptions.foreverEngineWrapped then
    iconOptions.foreverEngineWrapped = true
    local origCreate = iconOptions.create
    iconOptions.create = function(id, data)
      local options = origCreate(id, data)
      -- create() returns option GROUPS ({ icon = {...__order=1...}, position = ..., progressOptions = ... });
      -- entries must live inside a group, or CommonOptions' flattener trips on a missing __order.
      local group = type(options) == "table" and options.icon
      if type(group) == "table" then
        AddEngineOptions(group, data)
        AddPowerOptions(group, data, 101)
      end
      return options
    end
  end

  -- Aura trigger options: one notice right after upstream's 12.1 restriction warning (order 11.16).
  local origAura2 = Private.triggerTypesOptions and Private.triggerTypesOptions.aura2
  if origAura2 and not Private.triggerTypesOptions.foreverEngineWrapped then
    Private.triggerTypesOptions.foreverEngineWrapped = true
    Private.triggerTypesOptions.aura2 = function(data, triggernum, ...)
      local options = origAura2(data, triggernum, ...)
      local auraOptions = type(options) == "table" and options["trigger." .. triggernum .. ".aura_options"]
      if auraOptions then
        auraOptions.foreverEngineNotice = {
          type = "description", width = WA.doubleWidth, order = 11.17, fontSize = "medium",
          name = function() return (Engine.Explain(data)) end,
        }
      end
      return options
    end
  end
end)
