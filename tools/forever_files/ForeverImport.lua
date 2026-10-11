--[[ ForeverImport.lua - WoW: Forever. Media paths in auras made with other WeakAuras forks.

An aura stores full file paths for its textures, sounds and fonts. Auras made in WeakAuras, m33shoq's fork
or ForeverAuras point into those addons' folders (Interface\AddOns\WeakAuras\Media\...), which do not
exist in an EverAuras install, so imported textures would be missing. All of them inherit the same
media set from WeakAuras, and EverAuras ships it under its own folder. This rewrites such paths to
this addon's folder, for the subfolders it actually has, whenever an aura is added (import, load,
options), so it also repairs auras that were imported before. Only aura DATA is touched; nothing is
read from or copied out of any other addon.

Brand-free: works in the upstream tree and after the rename step. Loaded after the core files.
]]
local AddonName, Private = ...
local WA = _G[AddonName]
if not (WA and WA.IsForever and WA.IsForever()) then return end
if type(WA.PreAdd) ~= "function" then return end

local TARGET = AddonName
local SOURCES = { weakauras = true, m33kauras = true, m33auras = true, foreverauras = true }
local SUBFOLDERS = { media = true, poweraurasmedia = true }   -- the folders this addon ships

local function RemapString(s)
  if not s:find("[Aa][Dd][Dd][Oo][Nn][Ss]") then return s end
  return (s:gsub("([Ii][Nn][Tt][Ee][Rr][Ff][Aa][Cc][Ee][\\/]+[Aa][Dd][Dd][Oo][Nn][Ss][\\/]+)([%w_]+)([\\/]+)([%w_]+)",
    function(prefix, addon, sep, sub)
      local a = addon:lower()
      if SOURCES[a] and a ~= TARGET:lower() and SUBFOLDERS[sub:lower()] then
        return prefix .. TARGET .. sep .. sub
      end
    end))
end

local function Remap(t, depth, seen)
  if depth > 12 or seen[t] then return 0 end
  seen[t] = true
  local n = 0
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "string" then
      local r = RemapString(v)
      if r ~= v then t[k] = r; n = n + 1 end
    elseif tv == "table" then
      n = n + Remap(v, depth + 1, seen)
    end
  end
  return n
end

local ForeverImport = {}
Private.ForeverImport = ForeverImport
ForeverImport.RemapString = RemapString

function ForeverImport.RemapData(data)
  if type(data) ~= "table" then return 0 end
  return Remap(data, 0, {})
end

-- Every add (import, login load, options changes) goes through EverAuras.PreAdd.
local origPreAdd = WA.PreAdd
WA.PreAdd = function(data, ...)
  if type(data) == "table" then pcall(ForeverImport.RemapData, data) end
  return origPreAdd(data, ...)
end

-- Auras saved by an EverAuras older than its move onto upstream's ruleset loads may still carry the old
-- Hardcore load check (from Classic Era imports; hidden and ignored on Forever until then). Modernize turns
-- it into the Game Mode load option once (CORE hunk in Modernize.lua) and reports each aura here, so an
-- aura that now loads only on Hardcore (or only off it) is not a silent surprise. One chat line per batch.
do
  local pending
  function Private.ForeverNoteRulesetMigration(id, hardcoreOnly)
    if not pending then
      pending = {}
      C_Timer.After(3, function()
        local list = pending
        pending = nil
        local shown = {}
        for i = 1, math.min(#list, 8) do shown[i] = list[i] end
        local more = #list > 8 and (" (+%d)"):format(#list - 8) or ""
        WA.prettyPrint(("The old Hardcore load check is now the Game Mode load option (Load tab) in: %s%s")
          :format(table.concat(shown, ", "), more))
      end)
    end
    pending[#pending + 1] = ("'%s' (%s)"):format(tostring(id), hardcoreOnly and "Hardcore only" or "not Hardcore")
  end
end
