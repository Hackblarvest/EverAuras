--[[ ForeverImport.lua - WoW: Forever. Auras made with other WeakAuras forks.

Media paths: an aura stores full file paths for its textures, sounds and fonts. Auras made in WeakAuras,
m33shoq's fork or ForeverAuras point into those addons' folders (Interface\AddOns\WeakAuras\Media\...),
which do not exist in an EverAuras install, so imported textures would be missing. All of them inherit
the same media set from WeakAuras, and EverAuras ships it under its own folder. This rewrites such paths
to this addon's folder, for the subfolders it actually has, whenever an aura is added (import, load,
options), so it also repairs auras that were imported before.

ForeverAuras aura strings (AdoptForeign): they carry their own data version 91 (WeakAuras and M33kAuras
are at 90), so they were refused as "made with a newer version", and their in-combat aura trigger is a
type of their own. The import brings them onto this addon's data before its version check: the trigger
becomes the standard Aura trigger (which the engine runs in combat), its conditions follow, and the data
version goes back to the last step WeakAuras and M33kAuras share, so this addon's own data steps run.

Only aura DATA is touched; nothing is read from or copied out of any other addon.

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

-- ForeverAuras aura strings. What their exported data looks like (read from aura strings on wago.io):
--  * every aura at internalVersion 91, without the internalVersionM33kAuras marker this addon's data has
--    (equal to internalVersion; an aura that went through both addons can carry an older one)
--  * the aura trigger type "secretAura": spell lists auraRankSpellIDs (any rank) and auraspellids (exact),
--    switched by secretUseRankSpellIDs / secretUseSpellIDs; secretShowOn (none: Show On Active); own auras
--    by nativeFilters.PLAYER; any player's by isFromPlayerOrPlayerPet; secretUseRem / secretUseStacks /
--    secretUseTotal with value and operator; excluded ids. Fields of the Aura trigger it was switched from
--    can still be there, unused (Show On among them).
--  * conditions on those triggers: faAuraRemaining (op, value), faAuraActive / faAuraPresent /
--    faAuraMissing (a flag; a value of 0 negates it) and faAuraPandemic; changes faAuraHighlight*.
--  * the class load as "Class and Specialization" with Forever's specs (one per class), which this addon
--    has switched off on Forever (it uses Class); a load option forever_spec of their own.
--  * "flow" groups: plain groups (blizzardFlow*) whose children all sit at one point and are laid out
--    in a row by them; Power triggers hidden by a condition on their percentage (secret on Forever).
local FOREIGN_FROM = 91         -- data versions from here on that this addon did not write
local SHARED_STEP = 87          -- WeakAuras' and M33kAuras' data steps are the same up to here; 88-90 differ
local OPS = { ["=="] = "==", ["="] = "==", ["~="] = "~=", ["!="] = "~=",
              ["<"] = "<", ["<="] = "<=", [">"] = ">", [">="] = ">=" }
local SHOW_ON = { showOnActive = true, showOnMissing = true, showAlways = true }
local DEBUFF_TYPES = { HELPFUL = true, HARMFUL = true, BOTH = true }
local GROUP_UNITS = { group = true, party = true, raid = true, boss = true, arena = true, nameplate = true, multi = true }
local FOUND_FLAGS = { faAuraActive = true, faAuraPresent = true, faAuraMissing = false }  -- true: set means found
local CONDITION_NAMES = { faAuraPandemic = "Pandemic",   -- no pandemic window on Forever (Classic rules)
                          faAuraRemaining = "Remaining time", faAuraActive = "Active", faAuraPresent = "Present",
                          faAuraMissing = "Missing" }
-- Forever's specializations (the client's ChrSpecialization table: one per class) -> class
local SPEC_CLASS = { [1482] = "MAGE", [1484] = "DRUID", [1485] = "HUNTER", [1486] = "PALADIN", [1487] = "PRIEST",
                     [1488] = "ROGUE", [1489] = "SHAMAN", [1490] = "WARLOCK", [1491] = "WARRIOR" }
do -- and whatever the client reports, should it have more
  local getClass, getSpec = _G.GetClassInfo, _G.GetSpecializationInfoForClassID
  if type(getClass) == "function" and type(getSpec) == "function" then
    for classID = 1, 20 do
      local ok, _, classFile = pcall(getClass, classID)
      if ok and type(classFile) == "string" then
        for index = 1, 4 do
          local ok2, specID = pcall(getSpec, classID, index)
          if ok2 and type(specID) == "number" then SPEC_CLASS[specID] = classFile end
        end
      end
    end
  end
end

-- non-empty strings from a saved list (strings or numbers), in key order
local function StringList(src)
  local out = {}
  if type(src) ~= "table" then return out end
  local keys = {}
  for k in pairs(src) do
    if type(k) == "number" then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local v = src[k]
    if type(v) == "number" then v = tostring(v) end
    if type(v) == "string" then
      v = v:match("^%s*(.-)%s*$")
      if v ~= "" then out[#out + 1] = v end
    end
  end
  return out
end

local function NumberString(v)
  local n = tonumber(v)
  return n and tostring(n) or nil
end

local function IsForeignData(d)
  return type(d) == "table" and type(d.internalVersion) == "number" and d.internalVersion >= FOREIGN_FROM
    and d.internalVersionM33kAuras ~= d.internalVersion
end

-- a field of their own trigger options (not one left over from the Aura trigger)
local function HasOwnFields(t)
  for k in pairs(t) do
    if type(k) == "string" and (k:find("^secret") or k == "nativeFilters" or k == "auraRankSpellIDs") then
      return true
    end
  end
  return false
end

-- value/operator pair under their names -> the Aura trigger's (switched off unless complete)
local function Filter(t, use, value, op, toUse, toValue, toOp)
  local v, o = NumberString(t[value]), OPS[t[op] or ">="]
  if t[use] == true and v and o then
    t[toUse], t[toValue], t[toOp] = true, v, o
  else
    t[toUse] = nil
  end
end

-- their aura trigger -> the Aura trigger (aura2), in place. Returns the Show On its conditions mean and
-- whether it watches a group of units.
local function TranslateAuraTrigger(t, report)
  local own = HasOwnFields(t)
  local names, ids = {}, {}
  local showOn
  if own then
    -- a spell id under names matches the spell's every rank (and the engine resolves it in combat)
    if t.secretUseRankSpellIDs == true then names = StringList(t.auraRankSpellIDs) end
    if t.secretUseSpellIDs == true then ids = StringList(t.auraspellids) end
    showOn = t.secretShowOn            -- a matchesShowOn beside it is left over and not kept in step
  else
    if t.useName then names = StringList(t.auranames) end
    if t.useExactSpellId then ids = StringList(t.auraspellids) end
    showOn = t.matchesShowOn
  end
  if not SHOW_ON[showOn] then showOn = "showOnActive" end

  t.type = "aura2"
  if type(t.unit) ~= "string" or t.unit == "" then t.unit = "player" end
  if not DEBUFF_TYPES[t.debuffType] then t.debuffType = "HELPFUL" end
  t.matchesShowOn = showOn
  t.useName, t.auranames = #names > 0, names
  t.useExactSpellId, t.auraspellids = #ids > 0, ids
  local group = GROUP_UNITS[t.unit] == true
  if own then
    local filters = type(t.nativeFilters) == "table" and t.nativeFilters or {}
    -- own auras only, or anyone's (never "not mine", which their options do not have)
    t.ownOnly = filters.PLAYER == true or nil
    for key, on in pairs(filters) do
      if on == true and key ~= "PLAYER" then
        local what = tostring(key)
        report.filters[what] = (report.filters[what] or 0) + 1   -- no such filter here: matches without it
      end
    end
    -- any player's (or their pets') auras: the aura's own flag, as "Cast by a Player"
    t.use_castByPlayer = t.isFromPlayerOrPlayerPet == true or nil
    Filter(t, "secretUseRem", "secretRem", "secretRemOperator", "useRem", "rem", "remOperator")
    Filter(t, "secretUseStacks", "secretStacks", "secretStacksOperator", "useStacks", "stacks", "stacksOperator")
    Filter(t, "secretUseTotal", "secretTotal", "secretTotalOperator", "useTotal", "total", "totalOperator")
    local excluded = t.secretUseExcludedSpellIDs == true and StringList(t.excludedAuraSpellIDs) or {}
    t.useIgnoreExactSpellId = #excluded > 0 or nil
    if #excluded > 0 then t.ignoreAuraSpellids = excluded end
    -- the Aura trigger reads Show On only for single units; a group says it with its unit count, or with
    -- one clone per member who has it (or, for Missing, per member who lacks it)
    if group and not t.showClones then
      if showOn == "showOnActive" then
        t.useGroup_count, t.group_countOperator, t.group_count = true, ">", "0"
      elseif showOn == "showOnMissing" then
        t.useGroup_count, t.group_countOperator, t.group_count = true, "==", "0"
      else
        t.useGroup_count = nil
      end
    elseif group then
      if showOn == "showOnMissing" and t.unit ~= "multi" then
        t.combinePerUnit, t.perUnitMode, t.useGroup_count = true, "unaffected", nil
      else
        if showOn == "showOnMissing" then
          report.missing["Missing with Auto-clone on this unit"] = (report.missing["Missing with Auto-clone on this unit"] or 0) + 1
        end
        showOn = "showOnActive"            -- the clones are found auras
      end
    end
  end
  return showOn, group
end

-- conditions on translated triggers -> the Aura trigger's (recursing into and/or groups)
local function TranslateCheck(check, triggerOf, report, inAnd)
  if type(check) ~= "table" then return end
  local v = check.variable
  local trig = triggerOf[check.trigger]
  local showOn = trig and trig.showOn
  if showOn and type(v) == "string" and v:find("^faAura") then
    if v == "faAuraRemaining" and OPS[check.op or ""] and NumberString(check.value) then
      check.variable, check.op, check.value = "expirationTime", OPS[check.op], NumberString(check.value)
    elseif FOUND_FLAGS[v] ~= nil and not (trig.group and showOn == "showAlways") then
      local set = check.value == nil or (check.value ~= 0 and check.value ~= false and check.value ~= "0")
      local found = FOUND_FLAGS[v] == set
      if showOn == "showAlways" then
        check.variable, check.value = "buffed", found and 1 or 0
      else
        -- the trigger is Active exactly while the aura is found (Show On Active) or absent (Missing)
        check.variable, check.value = "show", (found == (showOn == "showOnActive")) and 1 or 0
      end
      check.op = nil
    else
      report.conditions[v] = (report.conditions[v] or 0) + 1
      if inAnd then
        -- a check the condition code does not know is left out of an and-group, which would then hold on
        -- its other checks; one that can never be true keeps the group inactive, as the chat line says
        check.foreignCheck = { variable = v, op = check.op, value = check.value }
        check.trigger, check.variable, check.op, check.value = -2, "AND", nil, nil
        check.checks = { { trigger = -1, variable = "incombat", value = 1 },
                         { trigger = -1, variable = "incombat", value = 0 } }
        return
      end
    end
  end
  if type(check.checks) == "table" then
    for _, sub in pairs(check.checks) do TranslateCheck(sub, triggerOf, report, check.variable == "AND") end
  end
end

-- the class load as "Class and Specialization" with Forever's specs -> Class (one spec per class)
local function TranslateClassLoad(load)
  local cas = load.class_and_spec
  if load.use_class_and_spec == nil or type(cas) ~= "table" then return end
  if load.use_class_and_spec == true then
    local file = SPEC_CLASS[tonumber(cas.single) or -1]
    if file then
      load.use_class, load.class = true, { single = file, multi = {} }
    end
  elseif type(cas.multi) == "table" then
    local multi
    for id, on in pairs(cas.multi) do
      local file = on and SPEC_CLASS[tonumber(id) or -1]
      if file then
        multi = multi or {}
        multi[file] = true
      end
    end
    if multi then
      load.use_class, load.class = false, { multi = multi }
    end
  end
end

-- their "flow" group (a plain group whose children all sit at one point, laid out in a row by them) ->
-- a Dynamic Group with the same direction, spacing, limit and order
local FLOW_GROW = { CENTER_HORIZONTAL = "HORIZONTAL", CENTER_VERTICAL = "VERTICAL",
                    LEFT = "LEFT", RIGHT = "RIGHT", UP = "UP", DOWN = "DOWN" }
-- a child's anchor: frame type, frame (Select Frame only), its own point, the point it sits on
local function ChildAnchor(c)
  local t = c.anchorFrameType or "SCREEN"
  return t, t == "SELECTFRAME" and c.anchorFrameFrame or nil, c.selfPoint or "CENTER", c.anchorPoint or "CENTER"
end

-- whether group h (or its children) sits on the aura `id`
local function AnchorsOnto(h, id, lookup)
  local mark = "WeakAuras:" .. tostring(id)
  if h.anchorFrameType == "SELECTFRAME" and h.anchorFrameFrame == mark then return true end
  if type(h.controlledChildren) == "table" then
    for _, cid in ipairs(h.controlledChildren) do
      local c = lookup(cid)
      if type(c) == "table" and c.anchorFrameType == "SELECTFRAME" and c.anchorFrameFrame == mark then return true end
    end
  end
  return false
end

-- Returns true when converted. Kept as a plain group (and reported) when a child is a group (a Dynamic
-- Group cannot lay those out), cannot be found, or the children sit on different frames or points.
local function TranslateFlowGroup(d, lookup, report)
  if d.regionType ~= "group" or d.blizzardFlow ~= true then return false end
  local kept = function() report.flowKept = report.flowKept + 1; return false end
  -- the row starts where the children sit: one shared Select Frame anchor moves onto the group
  local lift, key
  if type(d.controlledChildren) == "table" then
    for _, cid in ipairs(d.controlledChildren) do
      local c = lookup(cid)
      if type(c) ~= "table" or c.regionType == "group" or c.regionType == "dynamicgroup" then return kept() end
      local t, frame, sp, ap = ChildAnchor(c)
      if t ~= "SCREEN" and t ~= "PARENT" and t ~= "SELECTFRAME" then return kept() end
      local k = t == "SELECTFRAME" and table.concat({ t, tostring(frame), sp, ap }, "|") or "plain"
      if key and key ~= k then return kept() end
      key = k
      if t == "SELECTFRAME" then lift = { frame = frame, sp = sp, ap = ap } end
    end
  end
  local space = tonumber(d.blizzardFlowSpacing) or 2
  local limit = tonumber(d.blizzardFlowLimit)
  local sorted = d.blizzardFlowSortMode == "expiration"
  d.regionType = "dynamicgroup"
  if d.blizzardFlowGrid == true then
    d.grow, d.gridType = "GRID", type(d.blizzardFlowGridType) == "string" and d.blizzardFlowGridType or "RD"
    d.gridWidth = limit and limit >= 1 and math.floor(limit) or 5
    d.rowSpace, d.columnSpace = space, space
    d.useLimit = false
  else
    d.grow = FLOW_GROW[d.blizzardFlowGrowth] or "HORIZONTAL"
    -- a limit only where the game draws it (a row sorted by the time left); elsewhere every
    -- engine-drawn child counts as shown, so a limit would keep the same first ones forever
    d.useLimit = sorted and d.blizzardFlowUseLimit == true and limit ~= nil and limit >= 1
    if d.useLimit then d.limit = math.floor(limit) end
  end
  d.space, d.align, d.stagger, d.animate = space, "CENTER", 0, false
  if sorted then
    d.sort = d.blizzardFlowReverse == true and "descending" or "ascending"   -- by time left
  else
    d.sort = "none"
  end
  if lift then
    local target = type(lift.frame) == "string" and lift.frame:match("^WeakAuras:(.+)$")
    local h = target and lookup(target)
    local ok = true
    if target and (target == d.id or type(h) == "table" and h.parent == d.id) then
      ok = false                                   -- onto itself or one of its own children
    elseif type(h) == "table" and AnchorsOnto(h, d.id, lookup) and tostring(d.id) < tostring(target) then
      ok = false                                   -- two rows on each other: the other one moves
    end
    if ok then
      d.anchorFrameType, d.anchorFrameFrame = "SELECTFRAME", lift.frame
      d.selfPoint, d.anchorPoint = lift.sp, lift.ap
      d.xOffset, d.yOffset = 0, 0                  -- the children keep their own offsets on top
    end
  end
  return true
end

-- "hide at / above (or below) X% of a resource" as a condition on their Power trigger: resource amounts
-- are secret on Forever, so the condition can never be checked here; the power gate (ForeverGate.lua)
-- lets the game compare them instead
local GATE_REGIONS = { icon = true, aurabar = true, text = true, texture = true, progresstexture = true }
local GATE_UNITS = { player = true, target = true, focus = true, pet = true }
local GATE_POWER = { [0] = true, [1] = true, [2] = true, [3] = true }
local function TranslatePowerHide(d)
  if not GATE_REGIONS[d.regionType] or d.foreverPowerHide or type(d.conditions) ~= "table"
     or type(d.triggers) ~= "table" then
    return false
  end
  for _, c in ipairs(d.conditions) do
    local check, changes = type(c) == "table" and c.check, type(c) == "table" and c.changes
    if type(check) == "table" and check.variable == "percentpower" and type(changes) == "table" and #changes == 1
       and type(changes[1]) == "table" and changes[1].property == "alpha" and tonumber(changes[1].value) == 0 then
      local td = type(check.trigger) == "number" and d.triggers[check.trigger]
      local t = type(td) == "table" and td.trigger
      local at = tonumber(check.value)
      local mode = (check.op == ">=" or check.op == ">") and "above" or (check.op == "<" or check.op == "<=") and "below"
      local unit = type(t) == "table" and (t.unit or "player")
      local ptype = type(t) == "table" and t.use_powertype and tonumber(t.powertype)
      if type(t) == "table" and t.type == "unit" and t.event == "Power" and GATE_UNITS[unit] and GATE_POWER[ptype]
         and mode and at and at > 0 and at < 100 then
        d.foreverPowerHide, d.foreverPowerHideMode, d.foreverPowerHideAt = true, mode, at
        d.foreverPowerHideStrict = (check.op == ">" or check.op == "<=") or nil   -- the threshold itself shows / hides
        d.foreverPowerUnit, d.foreverPowerType = unit, ptype
        return true
      end
    end
  end
  return false
end

-- one aura or group, in place. Returns true when anything was changed.
local function AdoptOne(d, report, lookup)
  if type(d) ~= "table" then return false end
  local changed = false
  local triggerOf = {}
  if type(d.triggers) == "table" then
    for i, td in ipairs(d.triggers) do
      local t = type(td) == "table" and td.trigger
      if type(t) == "table" then
        if t.type == "secretAura" then
          local showOn, group = TranslateAuraTrigger(t, report)
          triggerOf[i] = { showOn = showOn, group = group }
          report.triggers = report.triggers + 1
          changed = true
        elseif t.type ~= "aura2" and t.type ~= "aura" and t.type ~= "custom" then
          local proto = type(t.event) == "string" and Private.event_prototypes and Private.event_prototypes[t.event]
          if not proto then
            local what = tostring(t.event or t.type)
            report.missing[what] = (report.missing[what] or 0) + 1
          end
        end
      end
    end
  end
  local foreign = IsForeignData(d)
  -- their flow groups also come at older data versions (only they write these fields)
  if TranslateFlowGroup(d, lookup, report) then changed = true end
  if type(d.conditions) == "table" then
    for _, condition in ipairs(d.conditions) do
      if type(condition) == "table" then
        if next(triggerOf) then TranslateCheck(condition.check, triggerOf, report) end
        if (foreign or next(triggerOf)) and type(condition.changes) == "table" then
          for _, change in ipairs(condition.changes) do
            local p = type(change) == "table" and change.property
            if type(p) == "string" and p:find("^faAuraHighlight") then
              report.highlights = report.highlights + 1    -- their own highlight; nothing here draws it
            end
          end
        end
      end
    end
  end
  if foreign then
    -- the steps this addon's data has beyond the shared ones run on it at PreAdd (Modernize)
    d.internalVersion = SHARED_STEP
    d.internalVersionM33kAuras = nil
    if type(d.actions) ~= "table" then d.actions = {} end
    if TranslatePowerHide(d) then report.powerGates = report.powerGates + 1 end
    if type(d.load) == "table" then
      TranslateClassLoad(d.load)
      local fs = d.load.forever_spec
      if d.load.use_forever_spec ~= nil and type(fs) == "table"
         and (fs.single ~= nil or type(fs.multi) == "table" and next(fs.multi) ~= nil) then
        report.specLoads = report.specLoads + 1   -- their own spec load option: not here
      end
    end
    changed = true
  end
  if changed then report.auras = report.auras + 1 end
  return changed
end

-- Brings aura data from ForeverAuras onto this addon's, in place: the import string's display and its
-- children (before the import's version check), or one aura at PreAdd (quiet). Safe to call on any data.
function ForeverImport.AdoptForeign(data, children, quiet)
  local report = { auras = 0, triggers = 0, missing = {}, conditions = {}, highlights = 0, specLoads = 0, filters = {},
                   powerGates = 0, flowKept = 0 }
  -- the import's own auras by id (its children are not saved yet), else the saved ones
  local byId = {}
  if type(data) == "table" and data.id ~= nil then byId[data.id] = data end
  if type(children) == "table" then
    for _, child in pairs(children) do
      if type(child) == "table" and child.id ~= nil then byId[child.id] = child end
    end
  end
  local function lookup(id)
    if byId[id] ~= nil then return byId[id] end
    local ok, d = pcall(WA.GetData, id)
    return ok and d or nil
  end
  local any = AdoptOne(data, report, lookup)
  if type(children) == "table" then
    for _, child in pairs(children) do
      if AdoptOne(child, report, lookup) then any = true end
    end
  end
  if any and not quiet and WA.prettyPrint then
    local parts = {}
    for what, n in pairs(report.missing) do parts[#parts + 1] = ("%s (%d)"):format(what, n) end
    for what, n in pairs(report.conditions) do
      parts[#parts + 1] = ("%s conditions (%d)"):format(CONDITION_NAMES[what] or what, n)
    end
    if report.highlights > 0 then parts[#parts + 1] = ("aura highlight changes (%d)"):format(report.highlights) end
    table.sort(parts)
    local msg = ("Aura string from ForeverAuras: %d aura(s) brought over, %d aura trigger(s) now use the Aura trigger.")
      :format(report.auras, report.triggers)
    if #parts > 0 then
      msg = msg .. " Not available here, so they stay inactive: " .. table.concat(parts, ", ") .. "."
    end
    local filters = {}
    for key, n in pairs(report.filters) do filters[#filters + 1] = ("%s (%d)"):format(key, n) end
    if #filters > 0 then
      table.sort(filters)
      msg = msg .. (" Aura filters that are not here, so those triggers match without them: %s.")
        :format(table.concat(filters, ", "))
    end
    if report.flowKept > 0 then
      msg = msg .. (" %d of their flow group(s) stay plain groups (children on different anchors, or groups inside).")
        :format(report.flowKept)
    end
    if report.powerGates > 0 then
      msg = msg .. (" %d display(s) now hide by a resource amount, which the game checks for them (Display tab, Power).")
        :format(report.powerGates)
    end
    if report.specLoads > 0 then
      msg = msg .. (" %d aura(s) use their spec load option, which is not here: they load for every spec of their class.")
        :format(report.specLoads)
    end
    WA.prettyPrint(msg)
  end
  return any, report
end

-- Every add (import, login load, options changes) goes through EverAuras.PreAdd.
local origPreAdd = WA.PreAdd
WA.PreAdd = function(data, ...)
  if type(data) == "table" then
    pcall(ForeverImport.AdoptForeign, data, nil, true)
    pcall(ForeverImport.RemapData, data)
  end
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
