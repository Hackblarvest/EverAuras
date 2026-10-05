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

# Prototypes.lua: %p on a SECRET remaining time. Upstream falls back to string.format("%.1f") on the
# secret number, which renders as e.g. "114.5" in combat. The engine can format the duration object
# itself; Private.SecretDurationFormatter lives in ForeverEngineAura.lua. Brand-free anchor.
PROTOTYPES_HUNKS = [
    # Spell Known helper: IsSpellKnown moved to C_SpellBook on Forever
    ("local function IsSpellKnownOrOverridesAndBaseIsKnown(spell, pet)\n  if spell == 0 then return false end\n  if IsSpellKnown(spell, pet) then\n",
     "local function IsSpellKnownOrOverridesAndBaseIsKnown(spell, pet)\n  if spell == 0 then return false end\n  if Private.ExecEnv.IsSpellKnown(spell, pet) then\n"),
    ("      return IsSpellKnown(baseSpell, pet)\n",
     "      return Private.ExecEnv.IsSpellKnown(baseSpell, pet)\n"),
    # Queued Action trigger: IsCurrentSpell global is gone on Forever
    ("        test = \"spellname and IsCurrentSpell(spellname)\";\n",
     "        test = \"spellname and Private.ExecEnv.IsCurrentSpell(spellname)\";\n"),
    # Spell Usable trigger: secret-safe in combat (see Cooldown Progress upstream for the same idea)
    ("        local charges, maxCharges, spellCount, chargeGainTime, chargeLostTime = M33kAuras.GetSpellCharges(effectiveSpellId, nil)\n        local stacks = maxCharges and maxCharges > 1 and charges\n                       or spellCount and spellCount > 0 and spellCount\n                       or nil\n        if (charges == nil) then\n          charges = (duration == 0 or gcdCooldown) and 1 or 0;\n        end\n        local ready = (startTime == 0 and not paused) or charges > 0\n        local active = Private.ExecEnv.IsUsableSpell(spellName or \"\") and ready\n",
     "        local charges, maxCharges, spellCount, chargeGainTime, chargeLostTime = M33kAuras.GetSpellCharges(effectiveSpellId, nil)\n        -- Forever: cooldown, charges and cast count are secret in combat (SecretWhenCooldownsRestricted);\n        -- a comparison would throw. Ready-ness is exact (IsSpellReady reads NeverSecret fields) and\n        -- usability is plain data, so the trigger keeps working; stacks follow the cooldown trigger.\n        local isSecret = issecretvalue(startTime) or issecretvalue(duration) or issecretvalue(charges)\n                      or issecretvalue(maxCharges) or issecretvalue(spellCount)\n        local stacks, ready\n        if isSecret then\n          stacks = maxCharges and maxCharges ~= 1 and charges or (spellCount and C_StringUtil.TruncateWhenZero(spellCount)) or C_Spell.GetSpellDisplayCount(effectiveSpellId)\n          ready = M33kAuras.IsSpellReady(effectiveSpellId)\n        else\n          stacks = maxCharges and maxCharges > 1 and charges\n                   or spellCount and spellCount > 0 and spellCount\n                   or nil\n          if (charges == nil) then\n            charges = (duration == 0 or gcdCooldown) and 1 or 0;\n          end\n          ready = (startTime == 0 and not paused) or charges > 0\n        end\n        local active = Private.ExecEnv.IsUsableSpell(spellName or \"\") and ready\n"),
    ("      if issecretvalue(remaining) then\n"
     "        -- todo when secret duration formatting is a thing\n"
     "        return string.format(\"%.1f\", remaining)\n"
     "      end\n",
     "      if issecretvalue(remaining) then\n"
     "        -- Forever: the engine formats the secret remaining time itself (\"1m 54s\", \"2.5s\")\n"
     "        if state.durationObject and Private.SecretDurationFormatter then\n"
     "          local fmt = Private.SecretDurationFormatter(progressPrecision)\n"
     "          if fmt then\n"
     "            local ok, text = pcall(state.durationObject.FormatRemainingDuration, state.durationObject, fmt)\n"
     "            if ok then return text end\n"
     "          end\n"
     "        end\n"
     "        return string.format(\"%.1f\", remaining)\n"
     "      end\n"),
]

# Options addon. (a) Cache.lua: upstream disables the spell-name cache on test builds (Forever's beta
# IS a test build), so typing a spell name stored an empty string. Seed the cache from the player's
# spellbook instead - cheap, and it covers the spells rotation auras are about. (b) BuffTrigger2.lua:
# when the cache has no match, keep the typed name instead of blanking the entry.
OPTIONS_HUNKS = {
    "M33kAurasOptions/Cache.lua": [
        ("  if IsTestBuild() then -- disable for 12.0.7\n    return\n  end\n",
         "  if IsTestBuild() then -- disable for 12.0.7\n"
         "    -- Forever (a test build): the full id scan stays off, but the cache is seeded from the\n"
         "    -- spellbook so typed names resolve and the autocomplete list works for your own spells.\n"
         "    if M33kAuras.IsForever and M33kAuras.IsForever() then\n"
         "      wipe(cache)\n"
         "      pcall(function()\n"
         "        local bank = (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0\n"
         "        for i = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do\n"
         "          local line = C_SpellBook.GetSpellBookSkillLineInfo(i)\n"
         "          if line then\n"
         "            for j = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do\n"
         "              local info = C_SpellBook.GetSpellBookItemInfo(j, bank)\n"
         "              if info and info.spellID and info.name and info.name ~= \"\" and not info.isPassive then\n"
         "                spellCache.AddIcon(info.name, info.spellID, info.iconID or 134400)\n"
         "              end\n"
         "            end\n"
         "          end\n"
         "        end\n"
         "      end)\n"
         "      metaData.needsRebuild = true   -- re-seed whenever the options open: new spells, new ranks\n"
         "    end\n"
         "    return\n  end\n"),
    ],
    "M33kAurasOptions/BuffTrigger2.lua": [
        ("            else\n              trigger[optionKey][i] = spellCache.BestKeyMatch(v)\n            end\n",
         "            else\n"
         "              local best = spellCache.BestKeyMatch(v)\n"
         "              -- Forever: without the full cache a name may have no match; keep what was typed\n"
         "              trigger[optionKey][i] = (best and best ~= \"\") and best or strtrim(v)\n"
         "            end\n"),
        ("        elseif input and input ~= \"\" then\n"
         "          icon = \"Interface\\\\AddOns\\\\M33kAuras\\\\Media\\\\Textures\\\\info\"\n"
         "        end\n"
         "        return icon and tostring(icon) or \"\", 18, 18\n",
         "        elseif input and input ~= \"\" then\n"
         "          -- Forever: a name shows the spell's own icon (the cache is seeded from the spellbook);\n"
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
}

# Core (M33kAuras.lua): the load scanner's argument list is generated from the load prototype so
# it can never drift from the parameter list on Forever (Player Class, Mounted, Zone ... loads).
CORE_HUNKS = {
    "M33kAuras/Init.lua": [
        ("-- Forever: a native install with data has nothing to migrate from M33Auras/WeakAuras.\nif M33kAurasSaved.displays and next(M33kAurasSaved.displays) and not M33kAurasSaved.m33kMigrated then\n  M33kAurasSaved.m33kMigrated = true\nend\n",
         "-- Forever: nothing to migrate from. The M33Auras / WeakAuras settings-migration stubs are not shipped,\n-- and those folder names belong to other addons, which must never be loaded or disabled from here.\nM33kAurasSaved.m33kMigrated = true\nM33kAurasSaved.migrationDisabled = true\n"),
    ],
    "M33kAuras/Compatibility.lua": [
        ("if IsUsableSpell then\n  Private.ExecEnv.IsUsableSpell = IsUsableSpell\nelse\n  Private.ExecEnv.IsUsableSpell = C_Spell.IsSpellUsable\nend\n",
         "if IsUsableSpell then\n  Private.ExecEnv.IsUsableSpell = IsUsableSpell\nelse\n  Private.ExecEnv.IsUsableSpell = C_Spell.IsSpellUsable\nend\n\n-- Forever: the IsCurrentSpell global is gone (mainline engine); the Queued Action trigger\n-- and the queued-spell watcher called it directly and errored.\nif IsCurrentSpell then\n  Private.ExecEnv.IsCurrentSpell = IsCurrentSpell\nelse\n  Private.ExecEnv.IsCurrentSpell = C_Spell.IsCurrentSpell\nend\n"),
        ("if IsCurrentSpell then\n  Private.ExecEnv.IsCurrentSpell = IsCurrentSpell\nelse\n  Private.ExecEnv.IsCurrentSpell = C_Spell.IsCurrentSpell\nend\n",
         "if IsCurrentSpell then\n  Private.ExecEnv.IsCurrentSpell = IsCurrentSpell\nelse\n  Private.ExecEnv.IsCurrentSpell = C_Spell.IsCurrentSpell\nend\n\n-- Forever: IsSpellKnown(spellID, isPet) now lives in C_SpellBook with a spell-bank enum\nif IsSpellKnown then\n  Private.ExecEnv.IsSpellKnown = IsSpellKnown\nelse\n  Private.ExecEnv.IsSpellKnown = function(spellID, isPet)\n    local banks = Enum.SpellBookSpellBank\n    return C_SpellBook.IsSpellKnown(spellID, banks and (isPet and banks.Pet or banks.Player) or nil)\n  end\nend\n"),
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
        ("            if IsCurrentSpell(maxRank) then\n",
         "            if maxRank and Private.ExecEnv.IsCurrentSpell(maxRank) then\n"),
        ("    if M33kAuras.IsTWW() then\n      return C_Spell.GetSpellLossOfControlCooldown(identifier)\n    else\n      return GetSpellLossOfControlCooldown(identifier)\n    end\n",
         "    -- Forever has neither API: answer 'no loss of control' instead of erroring\n    local getLoC = (C_Spell and C_Spell.GetSpellLossOfControlCooldown) or GetSpellLossOfControlCooldown\n    if getLoC then\n      return getLoC(identifier)\n    end\n"),
    ],
    "M33kAuras/M33kAuras.lua": [
        # Import of auras made in current M33kAuras: version 90 there only turns its Hardcore load into a
        # 'ruleset' load. This build's load options keep Hardcore and ignore 'ruleset', so their data is
        # safe to take. Refused as 'made with a newer version' before (Metz on Discord, 2026-10-05).
        # When rebasing onto an upstream with that step: auras saved here at 90 skip it (keep use_hardcore).
        ("local internalVersion = 89\n",
         "-- Forever: 90 is M33kAuras' Hardcore -> ruleset load option; nothing to convert in this build (its\n"
         "-- load options keep Hardcore and ignore 'ruleset'), but auras exported from M33kAuras carry 90 and\n"
         "-- were refused on import as made with a newer version.\n"
         "local internalVersion = 90\n"),
        ("local function scanForLoadsImpl(toCheck, event, arg1, ...)\n",
         "-- Forever: the load function's parameter list is built from Private.load_prototype (only the\n-- args whose init is \"arg\" for THIS flavour), but upstream keeps one retail-shaped call below.\n-- Forever is neither retail (BuildInfo 16001) nor classic, so the two lists differ and every value\n-- after 'encounter' lands in the wrong parameter: Player Class, Mounted, Zone ... all broken.\n-- Build the argument list from the prototype instead, so they can never disagree.\nlocal function BuildLoadArgs(values)\n  local args, n = {}, 0\n  for _, arg in ipairs(Private.load_prototype.args) do\n    if arg.init == \"arg\" then\n      n = n + 1\n      args[n] = values[arg.name]\n    end\n  end\n  args.n = n\n  return args\nend\n\nlocal function scanForLoadsImpl(toCheck, event, arg1, ...)\n"),
        ("      shouldBeLoaded = loadFunc and loadFunc(\"ScanForLoads_Auras\", inCombat, alive, inEncounter, warmodeActive, inPetBattle, vehicle, vehicleUi, dragonriding, mounted, addonRestrictionsActive, specId, player, realm, guild, race, faction, playerLevel, effectiveLevel, role, position, group, groupSize, raidMemberType, zone, zoneId, zonegroupId, instanceId, minimapText, encounter_id, size, difficulty, difficultyIndex, affixes)\n      couldBeLoaded =  loadOpt and loadOpt(\"ScanForLoads_Auras\",   inCombat, alive, inEncounter, warmodeActive, inPetBattle, vehicle, vehicleUi, dragonriding, mounted, addonRestrictionsActive, specId, player, realm, guild, race, faction, playerLevel, effectiveLevel, role, position, group, groupSize, raidMemberType, zone, zoneId, zonegroupId, instanceId, minimapText, encounter_id, size, difficulty, difficultyIndex, affixes)\n",
         "      -- Forever: arguments in prototype order (see BuildLoadArgs above); names are the prototype's\n      local loadArgs = BuildLoadArgs({\n        combat = inCombat, alive = alive, encounter = inEncounter, warmode = warmodeActive, pvpmode = pvp,\n        petbattle = inPetBattle, vehicle = vehicle, vehicleUi = vehicleUi, dragonriding = dragonriding,\n        mounted = mounted, addonRestrictionsActive = addonRestrictionsActive, hardcore = hardcore,\n        engraving = runeEngraving, class = class, class_and_spec = specId, player = player, realm = realm,\n        guild = guild, race = race, faction = faction, level = playerLevel, effectiveLevel = effectiveLevel,\n        role = role, spec_position = position, raid_role = raidRole, ingroup = group, groupSize = groupSize,\n        group_leader = raidMemberType, zone = zone, zoneId = zoneId, zonegroupId = zonegroupId,\n        instanceId = instanceId, minimapZoneText = minimapText, encounterid = encounter_id, size = size,\n        difficulty = difficulty, instance_type = difficultyIndex, affixes = affixes,\n      })\n      shouldBeLoaded = loadFunc and loadFunc(\"ScanForLoads_Auras\", unpack(loadArgs, 1, loadArgs.n))\n      couldBeLoaded =  loadOpt and loadOpt(\"ScanForLoads_Auras\", unpack(loadArgs, 1, loadArgs.n))\n"),
        ("  local currentErrorHandlerContext\n  local function waErrorHandler(errorMessage)\n",
         "  local currentErrorHandlerContext\n  local foreverSecretForwarded = {}   -- Forever: uid..context -> true once sent to BugSack\n  local function waErrorHandler(errorMessage)\n"),
        ("    if data then\n      Private.AuraWarnings.UpdateWarning(data.uid, \"LuaError\", \"error\",\n        L[\"This aura has caused a Lua error.\"] .. \"\\n\" .. L[\"Install the addons BugSack and BugGrabber for detailed error logs.\"], true)\n      table.insert(juicedMessage, L[\"Lua error in Aura '%s': %s\"]:format(data.id, currentErrorHandlerContext or L[\"unknown location\"]))\n",
         "    -- Forever: custom code that reads a value the client keeps secret in combat is the aura's own\n    -- limit, not an addon bug. Say so once per aura, and send it to BugSack once per aura and place.\n    local secretCustom = data and Private.ForeverSecretCustomError\n      and Private.ForeverSecretCustomError(data, currentErrorHandlerContext, errorMessage)\n    if data then\n      if secretCustom then\n        Private.AuraWarnings.UpdateWarning(data.uid, \"ForeverSecretCode\", \"warning\", secretCustom, true)\n      else\n        Private.AuraWarnings.UpdateWarning(data.uid, \"LuaError\", \"error\",\n          L[\"This aura has caused a Lua error.\"] .. \"\\n\" .. L[\"Install the addons BugSack and BugGrabber for detailed error logs.\"], true)\n      end\n      table.insert(juicedMessage, L[\"Lua error in Aura '%s': %s\"]:format(data.id, currentErrorHandlerContext or L[\"unknown location\"]))\n      if secretCustom then table.insert(juicedMessage, secretCustom) end\n"),
        ("      GREMINDER:OnError(err,debugstack(2),currentErrorHandlerContext)\n    end\n    geterrorhandler()(err)\n",
         "      GREMINDER:OnError(err,debugstack(2),currentErrorHandlerContext)\n    end\n    if secretCustom then\n      local key = data.uid .. \"\\n\" .. tostring(currentErrorHandlerContext)\n      if foreverSecretForwarded[key] then return end\n      foreverSecretForwarded[key] = true\n    end\n    geterrorhandler()(err)\n"),
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
    ("ForeverEngineAuraOptions.lua", "M33kAurasOptions/ForeverEngineAuraOptions.lua"),
]

# Markers that must exist afterwards, per relative file
CHECKS = {
    "M33kAuras/BuffTrigger2.lua": ["Not engine-driven because: ", 
        "ForeverEngine.PrepareTriggerInfo",
        "elseif triggerInfo.engineDelegated then",
        "return UpdateDelegatedState(time, triggerInfo, triggerStates)",
        "if unitExists or unitExistScanFunc[unit] then",
    ],
    "M33kAuras/Prototypes.lua": ["Private.SecretDurationFormatter(progressPrecision)",
                                 "spellname and Private.ExecEnv.IsCurrentSpell(spellname)",
                                 "return Private.ExecEnv.IsSpellKnown(baseSpell, pet)",
                                 "ready = M33kAuras.IsSpellReady(effectiveSpellId)"],
    "M33kAuras/Init.lua": ["M33kAurasSaved.migrationDisabled = true"],
    "M33kAuras/M33kAuras.lua": ["local internalVersion = 90\n", "unpack(loadArgs, 1, loadArgs.n)", "Private.ForeverSecretCustomError(data, currentErrorHandlerContext, errorMessage)",
                                "if foreverSecretForwarded[key] then return end"],
    "M33kAuras/Compatibility.lua": ["Private.ExecEnv.IsCurrentSpell = C_Spell.IsCurrentSpell",
                                    "Private.ExecEnv.IsSpellKnown = function(spellID, isPet)",
                                    "Private.ExecEnv.GetWeaponEnchantInfo = function()"],
    "M33kAuras/AuraEnvironment.lua": ["compat.GetSpellInfo = function(spell)",
                                      "if fn and _G[name] == nil and overridden[name] == nil then overridden[name] = fn end"],
    "M33kAuras/GenericTrigger.lua": ["if maxRank and Private.ExecEnv.IsCurrentSpell(maxRank) then",
                                     "local getLoC = (C_Spell and C_Spell.GetSpellLossOfControlCooldown)",
                                     "= Private.ExecEnv.GetWeaponEnchantInfo();"],
    "M33kAurasOptions/Cache.lua": ["spellCache.AddIcon(info.name, info.spellID"],
    "M33kAurasOptions/BuffTrigger2.lua": ["(best and best ~= \"\") and best or strtrim(v)",
                                          "pcall(spellCache.GetIcon, input)"],
    "M33kAuras/M33kAuras.toc": ["\nForeverEngineAura.lua\n"],
    "M33kAurasOptions/M33kAurasOptions.toc": ["\nForeverEngineAuraOptions.lua\n"],
    "M33kAuras/ForeverEngineAura.lua": ["Private.ForeverEngine = Engine"],
    "M33kAuras/ForeverGlow.lua": ["Private.ForeverGlow = G"],
    "M33kAuras/ForeverDispelData.lua": ["Private.ForeverDispelData = {"],
    "M33kAurasOptions/ForeverEngineAuraOptions.lua": ["foreverEngineNotice"],
}


def rename(s, old="M33kAuras", new="EverAuras"):
    """Map an upstream-named string/path to the installed name."""
    return s.replace(old, new)
