"""Single source of truth for the ForeverEngineAura integration hunks.

Written with UPSTREAM names (M33kAuras) because forever_patches.py runs before the rename.
apply_engine_to_installed.py maps them to the installed (EverAuras) names.
"""

# (anchor, replacement) pairs for BuffTrigger2.lua. Every anchor must be unique in the file.
BUFFTRIGGER2_HUNKS = [
    # missing-is-unknowable chat notice: name the reason the engine is not driving this display
    # (applies after forever_patches.patch_missing_is_unknowable, which adds the notice)
    ("        M33kAuras.prettyPrint((\"\\\"%s\\\": the client keeps this aura secret during combat, so \\\"Aura(s) Missing\\\" cannot be answered. Hiding it instead of reporting a match that may be false.\"):format(tostring(id)))\n",
     "        -- Forever: say WHY this display is not engine-driven (the engine would answer it in combat)\n        local why = \"\"\n        local Engine = Private.ForeverEngine\n        local data = Engine and Engine.Classify and M33kAuras.GetData(id)\n        if data then\n          local ok, plan, reasons = pcall(Engine.Classify, data)\n          if ok and not plan and type(reasons) == \"table\" and #reasons > 0 then\n            why = \" Not engine-driven because: \" .. table.concat(reasons, \"; \") .. \".\"\n          end\n        end\n        M33kAuras.prettyPrint((\"\\\"%s\\\": the client keeps this aura secret during combat, so \\\"Aura(s) Missing\\\" cannot be answered. Hiding it instead of reporting a match that may be false.%s\"):format(tostring(id), why))\n"),
    # P1 BuffTrigger.Add: let the engine classify and mark the record before it is stored
    ("      triggerInfos[id] = triggerInfos[id] or {}\n      triggerInfos[id][triggernum] = triggerInformation",
     "      if Private.ForeverEngine then\n"
     "        -- Forever: single-unit exact-spell-id Icon triggers are drawn by Blizzard_AuraContainer\n"
     "        Private.ForeverEngine.PrepareTriggerInfo(triggerInformation, trigger, data)\n"
     "      end\n"
     "      triggerInfos[id] = triggerInfos[id] or {}\n      triggerInfos[id][triggernum] = triggerInformation"),
    # P2 LoadAura single-unit branch: no scan funcs; unitExistScanFunc + matchDataChanged kick still run
    ("  else\n    if triggerInfo.debuffType == \"BOTH\" then\n      AddScanFuncs(triggerInfo, \"HELPFUL\", triggerInfo.unit, scanFuncName, scanFuncSpellId, scanFuncGeneral)",
     "  elseif triggerInfo.engineDelegated then\n"
     "    -- Forever: the aura engine renders this trigger; never ask the client about the aura.\n"
     "    unitsToCheck[triggerInfo.unit] = true\n"
     "  else\n    if triggerInfo.debuffType == \"BOTH\" then\n      AddScanFuncs(triggerInfo, \"HELPFUL\", triggerInfo.unit, scanFuncName, scanFuncSpellId, scanFuncGeneral)"),
    # P3 UpdateTriggerState: constant state whose only variable is unit existence
    ("local function UpdateTriggerState(time, id, triggernum)\n"
     "  local triggerStates = M33kAuras.GetTriggerStateForTrigger(id, triggernum)\n"
     "  local triggerInfo = triggerInfos[id][triggernum]\n",
     "-- Forever: an engine-delegated trigger publishes one constant state. Its only variable is\n"
     "-- unit existence (plain-readable); whether the aura is present is the engine's business.\n"
     "local function UpdateDelegatedState(time, triggerInfo, triggerStates)\n"
     "  local unit = triggerInfo.unit\n"
     "  local show = true\n"
     "  if triggerInfo.unitExists ~= nil and not UnitExistsFixed(unit) then\n"
     "    show = triggerInfo.unitExists\n"
     "  end\n"
     "  if not show then\n"
     "    return RemoveState(triggerStates, \"\")\n"
     "  end\n"
     "  local state = triggerStates[\"\"]\n"
     "  if not state then\n"
     "    local name, icon = BuffTrigger.GetNameAndIconSimple(M33kAuras.GetData(triggerInfo.id), triggerInfo.triggernum)\n"
     "    if issecretvalue(name) then name = \"\" end\n"
     "    if issecretvalue(icon) then icon = nil end\n"
     "    triggerStates[\"\"] = {\n"
     "      show = true, changed = true, time = time,\n"
     "      engineDelegated = true, active = false,\n"
     "      progressType = nil, duration = nil, expirationTime = nil, stacks = nil,\n"
     "      unit = unit, name = name, icon = icon,\n"
     "      unitName = \"\", destName = \"\", casterName = \"\",\n"
     "      matchCount = 0, unitCount = 1, maxUnitCount = 1,\n"
     "    }\n"
     "    return true\n"
     "  end\n"
     "  state.time = time\n"
     "  if state.show ~= true then\n"
     "    state.show = true\n"
     "    state.changed = true\n"
     "    return true\n"
     "  end\n"
     "  return false\n"
     "end\n"
     "\n"
     "local function UpdateTriggerState(time, id, triggernum)\n"
     "  local triggerStates = M33kAuras.GetTriggerStateForTrigger(id, triggernum)\n"
     "  local triggerInfo = triggerInfos[id][triggernum]\n"
     "  if triggerInfo.engineDelegated then\n"
     "    return UpdateDelegatedState(time, triggerInfo, triggerStates)\n"
     "  end\n"),
    # P4 ScanGroupUnit: re-evaluate unit-existence triggers on unit LOSS too. Delegated triggers keep
    #    no matchData, so nothing else kicks them when the target is cleared.
    ("  local unitExists = UnitExistsFixed(unit)\n  if unitExists then\n\n    if unitExistScanFunc[unit] then",
     "  local unitExists = UnitExistsFixed(unit)\n  if unitExists or unitExistScanFunc[unit] then -- Forever: also kick unit-existence triggers on loss\n\n    if unitExistScanFunc[unit] then"),
]

# Prototypes.lua: the Spell Known helper. Upstream now covers the rest on Forever itself (queued spells
# 034d0c5, Spell Usable in combat bf5f5b3, %p on secret durations 7584179).
PROTOTYPES_HUNKS = [
    # Spell Known helper: IsSpellKnown moved to C_SpellBook on Forever
    ("local function IsSpellKnownOrOverridesAndBaseIsKnown(spell, pet)\n  if spell == 0 then return false end\n  if IsSpellKnown(spell, pet) then\n",
     "local function IsSpellKnownOrOverridesAndBaseIsKnown(spell, pet)\n  if spell == 0 then return false end\n  if Private.ExecEnv.IsSpellKnown(spell, pet) then\n"),
    ("      return IsSpellKnown(baseSpell, pet)\n",
     "      return Private.ExecEnv.IsSpellKnown(baseSpell, pet)\n"),
]

# Options addon. Upstream builds the full spell cache on Forever since a236d29; three Cache.lua hunks make
# it work there. Options BuffTrigger2.lua: a typed name nothing matches is kept, and a name shows its spell
# icon. TriggerOptions.lua: 'Add Trigger' adds an Aura trigger again (upstream d2465fd made it 'Condition').
OPTIONS_HUNKS = {
    # The tree list's tooltip (Model Picker, ...) passed the wrap flag where the client's SetText takes alpha
    # (text, r, g, b, alpha, wrap): "bad argument #5 to 'SetText'" on every hover (BugGrabber, 2026-10-06).
    "M33kAurasOptions/AceGUI-Widgets/AceGUIContainer-M33kAurasTreeGroup.lua": [
        ('\t\tGameTooltip:SetText(frame.text:GetText() or "", 1, .82, 0, true)\n',
         '\t\tGameTooltip:SetText(frame.text:GetText() or "", 1, .82, 0, 1, true) -- Forever: alpha before wrap\n'),
    ],
    "M33kAurasOptions/Cache.lua": [
        # (1) GetIcon asks IsSpellKnown for every name with more than one spell id (classic ranks). Only
        #     C_SpellBook.IsSpellKnown is documented on 1.60.1, and GetIcon is reached unprotected from
        #     Icon/Bar thumbnails.
        ("local IsSpellKnown = IsSpellKnown\n",
         "-- Forever: only C_SpellBook.IsSpellKnown is documented on this client. GetIcon below asks it for every\n"
         "-- name with more than one spell id, which the full spell cache (built on Forever) has for most names.\n"
         "local IsSpellKnown = IsSpellKnown or function(spellID)\n"
         "  return C_SpellBook.IsSpellKnown(spellID)\n"
         "end\n"),
        # (2) The scan stays where upstream stops it on Forever (the miss limit ends it at ~554742). Forever's own
        #     spell ids (1213144 to 1323420 on 1.60.1) must not be scanned: asking the client about one of them
        #     killed it (fatal ERROR #110, "Aura '1251678' used in Client PlayerCondition '144600' is not known
        #     on the client", 2026-10-11, while the scan ran past 1213000). The player's own spells, many of
        #     which live there, come from the spellbook instead: after a build and whenever the options open.
        ("function spellCache.Get()\n",
         "-- Forever: the player's own spells from the spellbook (Forever's own spell ids are never scanned, see\n"
         "-- Build); each id once, so it can run whenever the options open.\n"
         "function spellCache.ForeverSeedSpellbook()\n"
         "  if not (cache and M33kAuras.IsForever() and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end\n"
         "  pcall(function()\n"
         "    local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0\n"
         "    for i = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do\n"
         "      local line = C_SpellBook.GetSpellBookSkillLineInfo(i)\n"
         "      if line then\n"
         "        for j = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do\n"
         "          local info = C_SpellBook.GetSpellBookItemInfo(j, bank)\n"
         "          local id, name = info and info.spellID, info and info.name\n"
         "          if id and name and name ~= \"\" and not info.isPassive then\n"
         "            local spells = cache[name] and cache[name].spells or \"\"\n"
         "            if not (\",\" .. spells):find(\",\" .. id .. \"=\", 1, true) then\n"
         "              spellCache.AddIcon(name, id, info.iconID or 134400)\n"
         "              bestIcon[name] = nil\n"
         "            end\n"
         "          end\n"
         "        end\n"
         "      end\n"
         "    end\n"
         "  end)\n"
         "end\n"
         "\n"
         "function spellCache.Get()\n"),
        ("    metaData.needsRebuild = false\n"
         "    metaData.rebuilding = false\n"
         "  end)\n"
         "  OptionsPrivate.Private.Threads:Add(\"spellCache\", co, 'background')\n",
         "    spellCache.ForeverSeedSpellbook() -- Forever: the player's own spells (see the function)\n"
         "    metaData.needsRebuild = false\n"
         "    metaData.rebuilding = false\n"
         "  end)\n"
         "  OptionsPrivate.Private.Threads:Add(\"spellCache\", co, 'background')\n"),
        ("    metaData.neverSecretSpells = { aura = {}, cooldown = {}, cast = {} }\n"
         "    wipe(cache)\n"
         "  end\n"
         "end\n",
         "    metaData.neverSecretSpells = { aura = {}, cooldown = {}, cast = {} }\n"
         "    wipe(cache)\n"
         "  end\n"
         "  if not metaData.needsRebuild then\n"
         "    spellCache.ForeverSeedSpellbook() -- Forever: spells learned since the last build\n"
         "  end\n"
         "end\n"),
        # (3) Load() forces a rebuild below 39000 cached names. Forever's SpellName has 17306 distinct names
        #     in all, so the cache would be wiped and rescanned (~745000 ids) every session the options open.
        #     A half-built cache is still caught by upstream's own `interrupted` flag.
        ("  local num = 0;\n"
         "  for _ in pairs(cache) do\n"
         "    num = num + 1;\n"
         "    if num >= 39000 then break end\n"
         "  end\n"
         "\n"
         "  if(num < 39000 or ",
         "  -- Forever: its whole spell table has ~17000 distinct names, never 39000; a lower floor keeps a\n"
         "  -- finished cache instead of rebuilding it every session.\n"
         "  local minNames = M33kAuras.IsForever() and 5000 or 39000\n"
         "  local num = 0;\n"
         "  for _ in pairs(cache) do\n"
         "    num = num + 1;\n"
         "    if num >= minNames then break end\n"
         "  end\n"
         "\n"
         "  if(num < minNames or "),
    ],
    "M33kAurasOptions/BuffTrigger2.lua": [
        ("            else\n              trigger[optionKey][i] = spellCache.BestKeyMatch(v)\n            end\n",
         "            else\n"
         "              local best = spellCache.BestKeyMatch(v)\n"
         "              -- Forever: while the spell cache builds, or for a name it lacks, there may be no match;\n"
         "              -- keep what was typed\n"
         "              trigger[optionKey][i] = (best and best ~= \"\") and best or strtrim(v)\n"
         "            end\n"),
        ("        elseif input and input ~= \"\" then\n"
         "          icon = \"Interface\\\\AddOns\\\\M33kAuras\\\\Media\\\\Textures\\\\info\"\n"
         "        end\n"
         "        return icon and tostring(icon) or \"\", 18, 18\n",
         "        elseif input and input ~= \"\" then\n"
         "          -- Forever: a name shows the spell's own icon (spell cache, then the game by name);\n"
         "          -- the generic info glyph only when nothing matches. Tooltip and click are unchanged.\n"
         "          if M33kAuras.IsForever and M33kAuras.IsForever() then\n"
         "            local ok, tex = pcall(spellCache.GetIcon, input)\n"
         "            if not (ok and tex) then\n"
         "              ok, tex = pcall(OptionsPrivate.Private.ExecEnv.GetSpellIcon, input)\n"
         "            end\n"
         "            if ok and tex and not issecretvalue(tex) then icon = tex end\n"
         "          end\n"
         "          icon = icon or \"Interface\\\\AddOns\\\\M33kAuras\\\\Media\\\\Textures\\\\info\"\n"
         "        end\n"
         "        return icon and tostring(icon) or \"\", 18, 18\n"),
    ],
    # 'Add Trigger' (pairs with the Types.lua data_stub hunk in CORE_HUNKS)
    "M33kAurasOptions/TriggerOptions.lua": [
        ("            trigger =\n"
         "            {\n"
         "              type = \"unit\",\n"
         "              event = \"Conditions\",\n"
         "              use_alwaystrue = true,\n"
         "            },\n",
         "            trigger =\n"
         "            {\n"
         "              type = \"aura2\", -- Forever: Aura triggers are the ones the game's aura engine draws\n"
         "            },\n"),
    ],
}

# Core addon. (Upstream's own Forever load-argument list, 4005346, replaced our BuildLoadArgs; the devtest
# test_load_args.py checks it against the load prototype.)
CORE_HUNKS = {
    "M33kAuras/Init.lua": [
        ("-- Forever: a native install with data has nothing to migrate from M33Auras/WeakAuras.\nif M33kAurasSaved.displays and next(M33kAurasSaved.displays) and not M33kAurasSaved.m33kMigrated then\n  M33kAurasSaved.m33kMigrated = true\nend\n",
         "-- Forever: nothing to migrate from. The M33Auras / WeakAuras settings-migration stubs are not shipped,\n-- and those folder names belong to other addons, which must never be loaded or disabled from here.\nM33kAurasSaved.m33kMigrated = true\nM33kAurasSaved.migrationDisabled = true\n"),
    ],
    "M33kAuras/Compatibility.lua": [
        ("if IsUsableSpell then\n  Private.ExecEnv.IsUsableSpell = IsUsableSpell\nelse\n  Private.ExecEnv.IsUsableSpell = C_Spell.IsSpellUsable\nend\n",
         "if IsUsableSpell then\n  Private.ExecEnv.IsUsableSpell = IsUsableSpell\nelse\n  Private.ExecEnv.IsUsableSpell = C_Spell.IsSpellUsable\nend\n\n-- Forever: IsSpellKnown(spellID, isPet) now lives in C_SpellBook with a spell-bank enum\nif IsSpellKnown then\n  Private.ExecEnv.IsSpellKnown = IsSpellKnown\nelse\n  Private.ExecEnv.IsSpellKnown = function(spellID, isPet)\n    local banks = Enum.SpellBookSpellBank\n    return C_SpellBook.IsSpellKnown(spellID, banks and (isPet and banks.Pet or banks.Player) or nil)\n  end\nend\n"),
        # Weapon Enchant trigger: Shaman imbues are an enchant type only C_Item.GetWeaponEnchantInfo reports
        ("    return C_SpellBook.IsSpellKnown(spellID, banks and (isPet and banks.Pet or banks.Player) or nil)\n  end\nend\n",
         '    return C_SpellBook.IsSpellKnown(spellID, banks and (isPet and banks.Pet or banks.Player) or nil)\n  end\nend\n\n-- Forever: Shaman imbues (Rockbiter, Windfury ...) are their own enchant type\n-- (Enum.ItemEnchantType.Imbue), which only C_Item.GetWeaponEnchantInfo reports. The legacy\n-- GetWeaponEnchantInfo() and C_PaperDollInfo see temporary enchants (stones, oils, poisons) only\n-- (measured 2026-09-27: Rockbiter = type 3, a Sharpening Stone = type 2). Same return shape as the\n-- legacy call: has, ms left, charges, enchant id for main hand, off hand and ranged.\nif C_Item and C_Item.GetWeaponEnchantInfo then\n  local types = Enum.ItemEnchantType or {}\n  local TEMPORARY, IMBUE = types.Temporary or 2, types.Imbue or 3\n  local function plain(v, default)\n    if issecretvalue(v) then return default end\n    return v\n  end\n  local function slotInfo(weaponSlot)\n    local ok, list = pcall(C_Item.GetWeaponEnchantInfo, weaponSlot)\n    if ok and type(list) == "table" then\n      for _, e in ipairs(list) do\n        local kind = plain(e.enchantType, nil)\n        if plain(e.hasEnchant, false) and (kind == TEMPORARY or kind == IMBUE) then\n          return true, plain(e.timeLeft, 1000), plain(e.charges, 0), plain(e.enchantID, 0)\n        end\n      end\n    end\n    return false, nil, nil, nil\n  end\n  local slots = Enum.WeaponSlot or {}\n  Private.ExecEnv.GetWeaponEnchantInfo = function()\n    local a1, a2, a3, a4 = slotInfo(slots.MainHand or 0)\n    local b1, b2, b3, b4 = slotInfo(slots.OffHand or 1)\n    local c1, c2, c3, c4 = slotInfo(slots.Ranged or 2)\n    return a1, a2, a3, a4, b1, b2, b3, b4, c1, c2, c3, c4\n  end\nelse\n  Private.ExecEnv.GetWeaponEnchantInfo = GetWeaponEnchantInfo\nend\n'),
    ],
    # Custom code written for other clients calls old global names (GetItemInfo, GetSpellInfo ...) that
    # the Forever client does not have: it ships no deprecated-API fallbacks. Inside aura code only, a
    # missing old name falls back to its modern home; a real global of that name always wins.
    "M33kAuras/AuraEnvironment.lua": [
        ("  M33kAuras = FakeM33kAuras,\n  WeakAuras = FakeM33kAuras,\n}\n",
         "  M33kAuras = FakeM33kAuras,\n  WeakAuras = FakeM33kAuras,\n}\n" + """
-- Forever: auras written in m33shoq's fork call the addon by its own name. Inside aura code that name
-- means this addon, as WeakAuras already does. Spelled in two parts so the rename step keeps the key.
overridden["M33k" .. "Auras"] = overridden["M33k" .. "Auras"] or FakeM33kAuras

-- Forever: the client ships no deprecated-API fallbacks, so custom code written for other clients
-- stops at the first old global name (seen 2026-10-05: GetItemInfo in a currency tracker from wago).
-- Inside aura code only, a missing old name falls back to its modern home, with the old return
-- values. A real global of that name always wins.
do
  local function plain(v, f)
    if issecretvalue and issecretvalue(v) then return v end
    return f(v)
  end
  local compat = {
    GetItemInfo = C_Item and C_Item.GetItemInfo,
    GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant,
    GetItemCount = C_Item and C_Item.GetItemCount,
    GetItemQualityColor = C_Item and C_Item.GetItemQualityColor,
    GetItemIcon = C_Item and C_Item.GetItemIconByID,
    GetItemSpell = C_Item and C_Item.GetItemSpell,
    GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo,
    IsEquippedItem = C_Item and C_Item.IsEquippedItem,
    GetSpellTexture = C_Spell and C_Spell.GetSpellTexture,
    GetSpellLink = C_Spell and C_Spell.GetSpellLink,
    GetSpellDescription = C_Spell and C_Spell.GetSpellDescription,
    IsUsableSpell = C_Spell and C_Spell.IsSpellUsable,
    IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded,
    GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata,
  }
  if C_Spell and C_Spell.GetSpellInfo then
    -- old: name, rank, icon, castTime, minRange, maxRange, spellID, originalIcon
    compat.GetSpellInfo = function(spell)
      local i = C_Spell.GetSpellInfo(spell)
      if type(i) ~= "table" then return nil end
      return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID, i.originalIconID
    end
  end
  if C_Spell and C_Spell.GetSpellCooldown then
    -- old: start, duration, enabled (1/0), modRate
    compat.GetSpellCooldown = function(spell)
      local c = C_Spell.GetSpellCooldown(spell)
      if type(c) ~= "table" then return nil end
      return c.startTime, c.duration, plain(c.isEnabled, function(e) return e and 1 or 0 end), c.modRate
    end
  end
  if C_Spell and C_Spell.GetSpellCharges then
    -- old: charges, maxCharges, start, duration, modRate
    compat.GetSpellCharges = function(spell)
      local c = C_Spell.GetSpellCharges(spell)
      if type(c) ~= "table" then return nil end
      return c.currentCharges, c.maxCharges, c.cooldownStartTime, c.cooldownDuration, c.chargeModRate
    end
  end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    -- old: name, amount, texture, earnedThisWeek, weeklyMax, totalMax, isDiscovered, rarity
    compat.GetCurrencyInfo = function(id)
      local c = C_CurrencyInfo.GetCurrencyInfo(id)
      if type(c) ~= "table" then return nil end
      return c.name, c.quantity, c.iconFileID, c.quantityEarnedThisWeek, c.maxWeeklyQuantity, c.maxQuantity,
        c.discovered, c.quality
    end
  end
  for name, fn in pairs(compat) do
    if fn and _G[name] == nil and overridden[name] == nil then overridden[name] = fn end
  end
end
"""),
    ],
    "M33kAuras/GenericTrigger.lua": [
        ('        _, mh_rem, mh_charges, mh_EnchantID, _, oh_rem, oh_charges, oh_EnchantID, _, rw_rem, rw_charges, rw_EnchantID = GetWeaponEnchantInfo();\n',
         '        -- Forever: through the shim in Compatibility.lua, which also sees Shaman imbues\n        _, mh_rem, mh_charges, mh_EnchantID, _, oh_rem, oh_charges, oh_EnchantID, _, rw_rem, rw_charges, rw_EnchantID = Private.ExecEnv.GetWeaponEnchantInfo();\n'),
        ("    if M33kAuras.IsTWW() then\n      return C_Spell.GetSpellLossOfControlCooldown(identifier)\n    else\n      return GetSpellLossOfControlCooldown(identifier)\n    end\n",
         "    -- Forever has neither API: answer 'no loss of control' instead of erroring\n    local getLoC = (C_Spell and C_Spell.GetSpellLossOfControlCooldown) or GetSpellLossOfControlCooldown\n    if getLoC then\n      return getLoC(identifier)\n    end\n"),
    ],
    "M33kAuras/M33kAuras.lua": [
        ("  local currentErrorHandlerContext\n  local function waErrorHandler(errorMessage)\n",
         "  local currentErrorHandlerContext\n  local foreverSecretForwarded = {}   -- Forever: uid..context -> true once sent to BugSack\n  local function waErrorHandler(errorMessage)\n"),
        ("    if data then\n      Private.AuraWarnings.UpdateWarning(data.uid, \"LuaError\", \"error\",\n        L[\"This aura has caused a Lua error.\"] .. \"\\n\" .. L[\"Install the addons BugSack and BugGrabber for detailed error logs.\"], true)\n      table.insert(juicedMessage, L[\"Lua error in Aura '%s': %s\"]:format(data.id, currentErrorHandlerContext or L[\"unknown location\"]))\n",
         "    -- Forever: custom code that reads a value the client keeps secret in combat is the aura's own\n    -- limit, not an addon bug. Say so once per aura, and send it to BugSack once per aura and place.\n    local secretCustom = data and Private.ForeverSecretCustomError\n      and Private.ForeverSecretCustomError(data, currentErrorHandlerContext, errorMessage)\n    if data then\n      if secretCustom then\n        Private.AuraWarnings.UpdateWarning(data.uid, \"ForeverSecretCode\", \"warning\", secretCustom, true)\n      else\n        Private.AuraWarnings.UpdateWarning(data.uid, \"LuaError\", \"error\",\n          L[\"This aura has caused a Lua error.\"] .. \"\\n\" .. L[\"Install the addons BugSack and BugGrabber for detailed error logs.\"], true)\n      end\n      table.insert(juicedMessage, L[\"Lua error in Aura '%s': %s\"]:format(data.id, currentErrorHandlerContext or L[\"unknown location\"]))\n      if secretCustom then table.insert(juicedMessage, secretCustom) end\n"),
        ("      GREMINDER:OnError(err,debugstack(2),currentErrorHandlerContext)\n    end\n    geterrorhandler()(err)\n",
         "      GREMINDER:OnError(err,debugstack(2),currentErrorHandlerContext)\n    end\n    if secretCustom then\n      local key = data.uid .. \"\\n\" .. tostring(currentErrorHandlerContext)\n      if foreverSecretForwarded[key] then return end\n      foreverSecretForwarded[key] = true\n    end\n    geterrorhandler()(err)\n"),
        # '/ea check' (ForeverCheck.lua) and '/ea engine on|off' (the engine's /faengine)
        ('  elseif msg == "repair" then\n    StaticPopup_Show("M33kAuras_CONFIRM_REPAIR", nil, nil, {reason = "user"})\n',
         '  elseif msg == "check" and Private.ForeverCheck then\n    -- Forever: are the game\'s APIs the engine draws with all there in this build (ForeverCheck.lua)\n    Private.ForeverCheck.Run(args[1])\n  elseif msg == "engine" and SlashCmdList.FOREVERENGINE then\n    -- Forever: the game\'s aura engine on or off (/faengine)\n    SlashCmdList.FOREVERENGINE(args[1] or "")\n  elseif msg == "repair" then\n    StaticPopup_Show("M33kAuras_CONFIRM_REPAIR", nil, nil, {reason = "user"})\n'),
        ('  print(L["/wa repair - Repair tool"])\n',
         '  print(L["/wa repair - Repair tool"])\n  print("/ea check - EverAuras on WoW: Forever: are the game\'s aura APIs all there (/ea check full: one line each)")\n  print("/ea engine on|off - EverAuras on WoW: Forever: let the game\'s aura engine draw auras (after /reload)")\n'),
    ],
    # Upstream d2465fd made 'Condition - Always active' the trigger of a new aura. The engine draws Aura triggers,
    # so EverAuras keeps the Aura trigger as the default (exactly f170ed7's stub; TriggerOptions.lua has the
    # 'Add Trigger' half). The stub is also validated into every aura on load: unchanged from 0.8.x.
    "M33kAuras/Types.lua": [
        ('      trigger = {\n        type = "unit",\n        event = "Conditions",\n        use_alwaystrue = true,\n      },\n      untrigger = {},\n',
         '      trigger = {\n'
         '        -- Forever: EverAuras draws Aura triggers through the game\'s aura engine; a new aura starts as one\n'
         '        type = "aura2",\n'
         '        names = {},\n'
         '        event = "Health",\n'
         '        subeventPrefix = "SPELL",\n'
         '        subeventSuffix = "_CAST_START",\n'
         '        spellIds = {},\n'
         '        unit = "player",\n'
         '        debuffType = "HELPFUL",\n'
         '      },\n'
         '      untrigger = {},\n'),
    ],
    # Saved data: EverAuras 0.8.10-0.8.17 took internalVersion 90 early (so M33kAuras exports would import) without
    # upstream's step 90 (5b8d9f7: the old Hardcore load check -> the Game Mode 'ruleset' load). Run that step once
    # more for auras at 90 that never went through it, told apart by the marker every Modernize sets since 9956a92.
    # Each converted aura is named in chat (ForeverImport.lua).
    "M33kAuras/Modernize.lua": [
        ("  if data.internalVersion < 90 and data.load then\n"
         "    local load = data.load\n"
         "    if load.use_hardcore ~= nil and load.use_ruleset == nil and load.ruleset == nil then\n",
         "  -- Forever: auras saved by EverAuras before it moved onto this upstream already carry internalVersion\n"
         "  -- 90 (taken early, so that exports from upstream would import), but that build never ran the step below,\n"
         "  -- so their load data can still hold the old Hardcore check (from Classic Era imports; the option was\n"
         "  -- hidden and ignored on Forever). They are the auras at 90 without internalVersionM33kAuras, which\n"
         "  -- every Modernize sets since 9956a92: run the step once for them too. Changes nothing on data that\n"
         "  -- went through it already.\n"
         "  local foreverMissed90 = data.internalVersion == 90 and data.internalVersionM33kAuras == nil\n"
         "  if (data.internalVersion < 90 or foreverMissed90) and data.load then\n"
         "    local load = data.load\n"
         "    if load.use_hardcore ~= nil and load.use_ruleset == nil and load.ruleset == nil then\n"
         "      if foreverMissed90 and Private.ForeverNoteRulesetMigration then\n"
         "        Private.ForeverNoteRulesetMigration(data.id, load.use_hardcore)\n"
         "      end\n"),
    ],
    # Import/export through the client's own Deflate (upstream a575cd0): never encode an error message as an
    # export string, and a decompress that answers nothing (documented MayReturnNothing) gives the message.
    "M33kAuras/Transmission.lua": [
        ("    ok, compressed = pcall(C_EncodingUtil.CompressString, serialized, Enum.CompressionMethod.Deflate)\n    if ok then\n",
         "    ok, compressed = pcall(C_EncodingUtil.CompressString, serialized, Enum.CompressionMethod.Deflate)\n"
         "    -- Forever: never encode an error message (or nothing) as an export string; LibDeflate is still loaded\n"
         "    if not ok or type(compressed) ~= \"string\" then\n"
         "      ok, compressed = true, LibDeflate:CompressDeflate(serialized, configForDeflate)\n"
         "    end\n"
         "    if ok then\n"),
        ("    ok, decompressed = pcall(C_EncodingUtil.DecompressString, decoded, Enum.CompressionMethod.Deflate)\n    if not(ok) then\n",
         "    ok, decompressed = pcall(C_EncodingUtil.DecompressString, decoded, Enum.CompressionMethod.Deflate)\n"
         "    -- Forever: the API is documented as MayReturnNothing; a bad string must give the message, not a Lua error\n"
         "    if not(ok) or type(decompressed) ~= \"string\" then\n"),
        # Aura strings from ForeverAuras (data version 91, their own aura trigger) are brought onto this
        # addon's data in place, before the version check below and before PreAdd (ForeverImport.lua).
        ("  local highestVersion = data.internalVersion or 0\n",
         "  -- Forever: aura strings from ForeverAuras are brought onto this addon's data first (ForeverImport.lua)\n"
         "  if Private.ForeverImport and Private.ForeverImport.AdoptForeign then\n"
         "    local ok, err = pcall(Private.ForeverImport.AdoptForeign, data, children)\n"
         "    if not ok then geterrorhandler()(err) end\n"
         "  end\n"
         "  local highestVersion = data.internalVersion or 0\n"),
    ],
}

# TOC line insertions: (relative toc path, anchor, replacement)
TOC_HUNKS = [
    ("M33kAuras/M33kAuras.toc", "DiscordList.lua\n", "DiscordList.lua\nForeverEngineAura.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverEngineAura.lua\n", "ForeverEngineAura.lua\nForeverManaRegen.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverManaRegen.lua\n", "ForeverManaRegen.lua\nForeverGate.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverGate.lua\n", "ForeverGate.lua\nForeverImport.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverImport.lua\n", "ForeverImport.lua\nForeverGlow.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverGlow.lua\n", "ForeverGlow.lua\nForeverDispelData.lua\n"),
    ("M33kAuras/M33kAuras.toc", "ForeverDispelData.lua\n", "ForeverDispelData.lua\nForeverCheck.lua\n"),
    ("M33kAurasOptions/M33kAurasOptions.toc", "\nRegionOptions\\ProgressTexture.lua\n",
     "\nRegionOptions\\ProgressTexture.lua\nForeverEngineAuraOptions.lua\n"),
]

# New files: (source basename in tools/forever_files, relative destination)
NEW_FILES = [
    ("ForeverEngineAura.lua", "M33kAuras/ForeverEngineAura.lua"),
    ("ForeverGate.lua", "M33kAuras/ForeverGate.lua"),
    ("ForeverImport.lua", "M33kAuras/ForeverImport.lua"),
    ("ForeverManaRegen.lua", "M33kAuras/ForeverManaRegen.lua"),
    ("ForeverGlow.lua", "M33kAuras/ForeverGlow.lua"),
    ("ForeverDispelData.lua", "M33kAuras/ForeverDispelData.lua"),
    ("ForeverCheck.lua", "M33kAuras/ForeverCheck.lua"),
    ("ForeverEngineAuraOptions.lua", "M33kAurasOptions/ForeverEngineAuraOptions.lua"),
]

# Markers that must exist afterwards, per relative file
CHECKS = {
    "M33kAuras/BuffTrigger2.lua": ["Not engine-driven because: ", 
        "ForeverEngine.PrepareTriggerInfo",
        "elseif triggerInfo.engineDelegated then",
        "return UpdateDelegatedState(time, triggerInfo, triggerStates)",
        "if unitExists or unitExistScanFunc[unit] then",
        "local function SafeForEachAura(unit, filter, maxCount, func, usePackedAura)\n  if not C_Secrets.ShouldAurasBeSecret() then",
        "missingCountFuncs[info.matchCountFunc]"],
    "M33kAuras/Prototypes.lua": ["if Private.ExecEnv.IsSpellKnown(spell, pet) then",
        "return Private.ExecEnv.IsSpellKnown(baseSpell, pet)",
        'test = "spellname and C_Spell.IsCurrentSpell(spellname)";',
        "local ready = M33kAuras.IsSpellReady(effectiveSpellId) == true",
        'return M33kAuras.GetDurationObjectValue(remaining, "remaining", formatter)'],
    "M33kAuras/Init.lua": ["M33kAurasSaved.migrationDisabled = true"],
    "M33kAuras/M33kAuras.lua": ["local internalVersion = 90\n",
        '      if M33kAuras.IsForever() then\n        shouldBeLoaded = loadFunc and loadFunc("ScanForLoads_Auras",',
        "Private.ForeverSecretCustomError(data, currentErrorHandlerContext, errorMessage)",
        "if foreverSecretForwarded[key] then return end",
        "Private.ForeverCheck.Run(args[1])"],
    "M33kAuras/Compatibility.lua": ["Private.ExecEnv.IsSpellKnown = function(spellID, isPet)",
        "Private.ExecEnv.GetWeaponEnchantInfo = function()"],
    "M33kAuras/AuraEnvironment.lua": ["compat.GetSpellInfo = function(spell)",
        "if fn and _G[name] == nil and overridden[name] == nil then overridden[name] = fn end",
        'overridden["M33k" .. "Auras"] = overridden["M33k" .. "Auras"] or FakeM33kAuras'],
    "M33kAuras/GenericTrigger.lua": ["local getLoC = (C_Spell and C_Spell.GetSpellLossOfControlCooldown)",
        "= Private.ExecEnv.GetWeaponEnchantInfo();",
        "if maxRank and C_Spell.IsCurrentSpell(maxRank) then",
        'if M33kAuras.IsRetail() or M33kAuras.IsForever() then\n        tenchFrame:RegisterEvent("WEAPON_ENCHANT_CHANGED")'],
    "M33kAurasOptions/Cache.lua": ["return C_SpellBook.IsSpellKnown(spellID)",
        "spellCache.ForeverSeedSpellbook() -- Forever: the player's own spells",
        "spellCache.ForeverSeedSpellbook() -- Forever: spells learned since the last build",
        "local minNames = M33kAuras.IsForever() and 5000 or 39000",
        "if IsTestBuild() and not M33kAuras.IsForever() then"],
    "M33kAurasOptions/AceGUI-Widgets/AceGUIContainer-M33kAurasTreeGroup.lua": ["1, .82, 0, 1, true) -- Forever: alpha before wrap"],
    "M33kAurasOptions/BuffTrigger2.lua": ["(best and best ~= \"\") and best or strtrim(v)",
                                          "pcall(spellCache.GetIcon, input)"],
    "M33kAuras/Types.lua": ["a new aura starts as one\n        type = \"aura2\","],
    "M33kAuras/Modernize.lua": ["local foreverMissed90 = data.internalVersion == 90 and data.internalVersionM33kAuras == nil"],
    "M33kAuras/Transmission.lua": ["if not ok or type(compressed) ~= \"string\" then",
                                   "if not(ok) or type(decompressed) ~= \"string\" then",
                                   "pcall(Private.ForeverImport.AdoptForeign, data, children)"],
    "M33kAurasOptions/TriggerOptions.lua": ["type = \"aura2\", -- Forever: Aura triggers are the ones"],
    "M33kAurasOptions/OptionsFrames/OptionsFrame.lua": ["local discordButton = addFooter(L[\"Discord\"]"],
    "M33kAuras/M33kAuras.toc": ["\nForeverEngineAura.lua\n"],
    "M33kAurasOptions/M33kAurasOptions.toc": ["\nForeverEngineAuraOptions.lua\n"],
    "M33kAuras/ForeverEngineAura.lua": ["Private.ForeverEngine = Engine"],
    "M33kAuras/ForeverGlow.lua": ["Private.ForeverGlow = G"],
    "M33kAuras/ForeverDispelData.lua": ["Private.ForeverDispelData = {"],
    "M33kAuras/ForeverCheck.lua": ["Private.ForeverCheck = C"],
    "M33kAurasOptions/ForeverEngineAuraOptions.lua": ["foreverEngineNotice"],
}


def rename(s):
    """Map an upstream-named string/path to the installed name, exactly as the build's rename step does
    (its guarded names, e.g. internalVersionM33kAuras, keep their spelling)."""
    import os, sys
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    from rename_to_everauras import rewrite
    return rewrite(s)
