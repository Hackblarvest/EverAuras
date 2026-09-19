"""Single source of truth for the ForeverEngineAura integration hunks.

Written with UPSTREAM names (M33kAuras) because forever_patches.py runs before the rename.
apply_engine_to_installed.py maps them to the installed (EverAuras) names.
"""

# (anchor, replacement) pairs for BuffTrigger2.lua. Every anchor must be unique in the file.
BUFFTRIGGER2_HUNKS = [
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

# TOC line insertions: (relative toc path, anchor, replacement)
TOC_HUNKS = [
    ("M33kAuras/M33kAuras.toc", "DiscordList.lua\n", "DiscordList.lua\nForeverEngineAura.lua\n"),
    ("M33kAurasOptions/M33kAurasOptions.toc", "\nRegionOptions\\ProgressTexture.lua\n",
     "\nRegionOptions\\ProgressTexture.lua\nForeverEngineAuraOptions.lua\n"),
]

# New files: (source basename in tools/forever_files, relative destination)
NEW_FILES = [
    ("ForeverEngineAura.lua", "M33kAuras/ForeverEngineAura.lua"),
    ("ForeverEngineAuraOptions.lua", "M33kAurasOptions/ForeverEngineAuraOptions.lua"),
]

# Markers that must exist afterwards, per relative file
CHECKS = {
    "M33kAuras/BuffTrigger2.lua": [
        "ForeverEngine.PrepareTriggerInfo",
        "elseif triggerInfo.engineDelegated then",
        "return UpdateDelegatedState(time, triggerInfo, triggerStates)",
        "if unitExists or unitExistScanFunc[unit] then",
    ],
    "M33kAuras/Prototypes.lua": ["Private.SecretDurationFormatter(progressPrecision)"],
    "M33kAuras/M33kAuras.toc": ["\nForeverEngineAura.lua\n"],
    "M33kAurasOptions/M33kAurasOptions.toc": ["\nForeverEngineAuraOptions.lua\n"],
    "M33kAuras/ForeverEngineAura.lua": ["Private.ForeverEngine = Engine"],
    "M33kAurasOptions/ForeverEngineAuraOptions.lua": ["foreverEngineNotice"],
}


def rename(s, old="M33kAuras", new="EverAuras"):
    """Map an upstream-named string/path to the installed name."""
    return s.replace(old, new)
