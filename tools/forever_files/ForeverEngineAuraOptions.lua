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

  -- Icon region options: a status line and a per-display opt-out. Entries without 'set' get the
  -- framework setter, exactly like 'cooldown' in RegionOptions/Icon.lua.
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
          desc = T("Needs exactly one Aura trigger with Exact Spell ID(s) on Player, Target, Focus or Pet, Buff or Debuff (not Both), and Show On: Found / Missing / Always. Off = the classic scanner, which is blind while auras are secret (combat)."),
          get = function() return data.foreverEngine ~= false end,
          -- A full (non-simple) re-add so BuffTrigger.Add re-classifies the trigger; the plain
          -- framework setter would only re-run the region modify and leave the trigger side stale.
          set = function(_, v)
            data.foreverEngine = v and true or false
            WA.Add(data)
            if WA.ClearAndUpdateOptions then WA.ClearAndUpdateOptions(data.id) end
          end,
        }
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
