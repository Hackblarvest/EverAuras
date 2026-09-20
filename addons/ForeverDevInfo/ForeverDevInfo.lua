--[[ Forever Dev Info
     Measures at PLAYER_LOGIN, i.e. AFTER every addon's SavedVariables have been
     restored. (Counting at file scope is useless: without LoadSavedVariablesFirst
     the restore happens after the addon's files run and overwrites anything set there.)

     loginCount   - grows every login IF our own SavedVariables restore correctly.
     faDisplays - how many auras EverAurasSaved has once restore is done.
                    If the file on disk holds an aura and this is 0, the file is
                    never read back. If it is 1+, M33kAuras wipes it afterwards.
     Slash: /fdi, /fdierr
]]

local ADDON = ...

local function countDisplays(tbl)
	if type(tbl) ~= "table" then return -2 end          -- global is nil
	if type(tbl.displays) ~= "table" then return -1 end -- table, but no displays key
	local n = 0
	for _ in pairs(tbl.displays) do n = n + 1 end
	return n
end

local function installErrorHandler()
	local previous = geterrorhandler()
	seterrorhandler(function(err)
		ForeverDevInfoDB.errors = ForeverDevInfoDB.errors or {}
		local list = ForeverDevInfoDB.errors
		list[#list + 1] = { t = date("%H:%M:%S"), err = tostring(err), stack = debugstack(2, 20, 0) }
		while #list > 40 do table.remove(list, 1) end
		if previous then pcall(previous, err) end
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	-- everything below runs AFTER SavedVariables have been restored
	local restored = type(ForeverDevInfoDB) == "table" and ForeverDevInfoDB.loginCount ~= nil
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.loginCount = (ForeverDevInfoDB.loginCount or 0) + 1
	ForeverDevInfoDB.errors = ForeverDevInfoDB.errors or {}
	ForeverDevInfoDB.history = ForeverDevInfoDB.history or {}

	installErrorHandler()

	local m33k = countDisplays(_G.EverAurasSaved)
	local snap = {
		t = date("%H:%M:%S"),
		loginCount = ForeverDevInfoDB.loginCount,
		ourSVRestored = restored,
		faDisplays = m33k,
		faDiag = type(_G.EverAurasSaved) == "table" and _G.EverAurasSaved.foreverLoadDiag
			and #_G.EverAurasSaved.foreverLoadDiag or -1,
	}
	local h = ForeverDevInfoDB.history
	h[#h + 1] = snap
	while #h > 15 do table.remove(h, 1) end

	print(("|cff33ff99FDI|r login #%d | our SV restored: %s | EverAuras auras after restore: %s")
		:format(snap.loginCount, tostring(restored), tostring(m33k)))
end)

SLASH_FOREVERDEVINFO1 = "/fdi"
SlashCmdList["FOREVERDEVINFO"] = function()
	local v, b, _, toc = GetBuildInfo()
	print(("|cff33ff99FDI|r client %s (%s) interface %s"):format(tostring(v), tostring(b), tostring(toc)))
	print(("|cff33ff99FDI|r login #%s, EverAuras auras right now: %s")
		:format(tostring(ForeverDevInfoDB and ForeverDevInfoDB.loginCount), tostring(countDisplays(_G.EverAurasSaved))))
	print(("|cff33ff99FDI|r captured errors: %d"):format(ForeverDevInfoDB and #ForeverDevInfoDB.errors or 0))
	local b = _G.ForeverSVBridge
	if b then
		if b.seeded == 0 then
			print("|cff33ff99FDI|r |cff00ff00SavedVariables bridge seeded 0 globals - the client restored them itself. Blizzard has fixed the bug; the bridge can be removed.|r")
		else
			print(("|cff33ff99FDI|r bridge still needed: seeded %d, skipped %d (%s), generated %s")
				:format(b.seeded, b.skipped, table.concat(b.names, ", "), tostring(b.generated)))
		end
	else
		print("|cff33ff99FDI|r SavedVariables bridge not loaded.")
	end
end

SLASH_FOREVERDEVINFOERR1 = "/fdierr"
SlashCmdList["FOREVERDEVINFOERR"] = function()
	local list = ForeverDevInfoDB and ForeverDevInfoDB.errors or {}
	if #list == 0 then print("|cff33ff99FDI|r no errors captured.") return end
	for i, e in ipairs(list) do print(("|cffffd100[%d %s]|r %s"):format(i, e.t or "?", e.err)) end
end

--[[ ------------------------------------------------------------------------
     Secret probe: /fdsecret [spellID]      (default 348 = Immolate rank 1)

     Forever inherits the 12.1 "secret values" system. Enum.AddOnRestrictionType
     has a Combat member ("The player is actively affecting combat"), and every
     aura getter is flagged SecretWhenUnitAuraRestricted, i.e. it yields secret
     values while a combat restriction is active. Two aura getters are also
     flagged RequiresNonSecretAura, which per the client docs "does not raise a
     blocked action error - instead, protected APIs will return no values".

     So an aura trigger can fail completely silently. This dumps the actual
     runtime answers so we can tell which case we are in.

     Run it in combat, with the debuff up, then /reload or exit so the results
     land in SavedVariables.
]]

local SECRECY = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }
local RESTRICTION = { [0] = "Combat", [1] = "Encounter", [2] = "ChallengeMode", [3] = "PvPMatch", [4] = "Map", [5] = "Chat" }
local RSTATE = { [0] = "Inactive", [1] = "Activating", [2] = "Active" }

-- Never touch a value directly: reading, comparing or tostring-ing a secret throws.
local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function ask(fn, ...)
	if type(fn) ~= "function" then return "<api missing>" end
	local ok, res = pcall(fn, ...)
	if not ok then return "ERROR: " .. show(res) end
	return show(res)
end

local function askEnum(names, fn, ...)
	local raw = ask(fn, ...)
	local n = tonumber(raw)
	return n and ("%s (%s)"):format(raw, names[n] or "?") or raw
end

local function describeAura(fn, ...)
	if type(fn) ~= "function" then return "<api missing>" end
	local ok, aura = pcall(fn, ...)
	if not ok then return "ERROR: " .. show(aura) end
	local ok2, desc = pcall(function()
		if issecretvalue(aura) then return "<secret value>" end
		if aura == nil then return "NO VALUES RETURNED (nil)" end
		if type(aura) ~= "table" then return "unexpected " .. show(aura) end
		local f = {}
		for _, k in ipairs({ "spellId", "name", "auraInstanceID", "duration",
			"expirationTime", "applications", "isHarmful", "isHelpful", "sourceUnit" }) do
			f[#f + 1] = k .. "=" .. show(rawget(aura, k))
		end
		return "table { " .. table.concat(f, ", ") .. " }"
	end)
	return ok2 and desc or ("ERROR while reading: " .. show(desc))
end

local function probe(spellID)
	local out = {}
	local function add(fmt, ...)
		local line = select("#", ...) > 0 and fmt:format(...) or fmt
		out[#out + 1] = line
		print("|cff33ff99FDI|r " .. line)
	end

	add("=== secret probe, spell %d, %s ===", spellID, date("%H:%M:%S"))
	add("InCombatLockdown=%s  UnitAffectingCombat(player)=%s",
		ask(InCombatLockdown), ask(UnitAffectingCombat, "player"))

	local parts = {}
	for i = 0, 5 do
		parts[#parts + 1] = ("%s=%s"):format(RESTRICTION[i],
			(askEnum(RSTATE, C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState, i):gsub("^%d+ %((.-)%)$", "%1")))
	end
	add("restrictions: %s", table.concat(parts, " "))

	if C_Secrets then
		add("ShouldAurasBeSecret=%s  HasSecretRestrictions=%s  ShouldCooldownsBeSecret=%s",
			ask(C_Secrets.ShouldAurasBeSecret), ask(C_Secrets.HasSecretRestrictions),
			ask(C_Secrets.ShouldCooldownsBeSecret))
		add("GetSpellAuraSecrecy(%d)=%s", spellID, askEnum(SECRECY, C_Secrets.GetSpellAuraSecrecy, spellID))
		add("ShouldSpellAuraBeSecret(%d)=%s", spellID, ask(C_Secrets.ShouldSpellAuraBeSecret, spellID))
		add("GetSpellCooldownSecrecy(%d)=%s", spellID, askEnum(SECRECY, C_Secrets.GetSpellCooldownSecrecy, spellID))
		add("GetSpellCastSecrecy(%d)=%s", spellID, askEnum(SECRECY, C_Secrets.GetSpellCastSecrecy, spellID))
	else
		add("C_Secrets missing entirely")
	end

	local unit = UnitExists("target") and "target" or "player"
	add("unit=%s name=%s", unit, ask(UnitName, unit))

	-- the call our aura scanner depends on
	add("GetUnitAuraBySpellID(%s,%d) -> %s", unit, spellID,
		describeAura(C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID, unit, spellID))
	add("GetPlayerAuraBySpellID(%d) -> %s", spellID,
		describeAura(C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID, spellID))

	-- bulk enumeration, expected to be blocked outright
	add("ForEachAura(%s,HARMFUL) -> %s", unit, ask(function()
		local n = 0
		AuraUtil.ForEachAura(unit, "HARMFUL", nil, function() n = n + 1 end, true)
		return n .. " auras seen"
	end))
	add("GetUnitAuraInstanceIDs(%s,HARMFUL) -> %s", unit, ask(function()
		local ids = C_UnitAuras.GetUnitAuraInstanceIDs(unit, "HARMFUL")
		if issecretvalue(ids) then return "<secret>" end
		return ("%d ids, first=%s"):format(#ids, show(ids[1]))
	end))

	ForeverDevInfoDB = ForeverDevInfoDB or {}
	local probes = ForeverDevInfoDB.probes or {}
	probes[#probes + 1] = out
	while #probes > 6 do table.remove(probes, 1) end
	ForeverDevInfoDB.probes = probes
	add("(stored - /reload or exit, then the result is on disk)")
end

-- Records the SHAPE of UNIT_AURA payloads for 20s. If addedAuras arrives as a
-- readable list whose per-aura fields are secret, BuffTrigger2's incremental
-- path drops them silently, which looks exactly like "the aura never updates".
local watcher = CreateFrame("Frame")
local watching = false
watcher:SetScript("OnEvent", function(_, _, unit, info)
	if unit ~= "target" and unit ~= "player" then return end
	local ok, line = pcall(function()
		if info == nil then return "updateInfo=nil (forces full scan)" end
		if issecretvalue(info) then return "updateInfo=<secret>" end
		local added = rawget(info, "addedAuras")
		local detail = "nil"
		if issecretvalue(added) then
			detail = "<secret container>"
		elseif type(added) == "table" then
			local first = added[1]
			detail = ("%d entries"):format(#added)
			if first ~= nil then
				detail = detail .. (issecretvalue(first) and ", [1]=<secret>"
					or (", [1].spellId=" .. show(rawget(first, "spellId"))))
			end
		end
		return ("unit=%s isFullUpdate=%s addedAuras=%s updated=%s removed=%s"):format(
			unit, show(rawget(info, "isFullUpdate")), detail,
			show(rawget(info, "updatedAuraInstanceIDs")), show(rawget(info, "removedAuraInstanceIDs")))
	end)
	ForeverDevInfoDB.auraEvents = ForeverDevInfoDB.auraEvents or {}
	local l = ForeverDevInfoDB.auraEvents
	l[#l + 1] = date("%H:%M:%S") .. " " .. (ok and line or ("ERROR " .. show(line)))
	while #l > 40 do table.remove(l, 1) end
	print("|cff33ff99FDI|r UNIT_AURA " .. (ok and line or "ERROR"))
end)

SLASH_FOREVERDEVSECRET1 = "/fdsecret"
SlashCmdList["FOREVERDEVSECRET"] = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "watch" then
		if watching then
			watcher:UnregisterEvent("UNIT_AURA"); watching = false
			print("|cff33ff99FDI|r UNIT_AURA watch off.")
		else
			ForeverDevInfoDB.auraEvents = {}
			watcher:RegisterEvent("UNIT_AURA"); watching = true
			print("|cff33ff99FDI|r UNIT_AURA watch ON for 20s - cast now.")
			C_Timer.After(20, function()
				if watching then
					watcher:UnregisterEvent("UNIT_AURA"); watching = false
					print("|cff33ff99FDI|r UNIT_AURA watch off (20s elapsed).")
				end
			end)
		end
		return
	end
	probe(tonumber(msg) or 348)
end

--[[ ------------------------------------------------------------------------
     /fdsecret2  - probe round 2. Settles the questions the apidocs cannot.

     Run it IN COMBAT with a target, then cast Immolate within the 25 s window,
     then /reload. Everything lands in ForeverDevInfoDB.probes2 / .castLog.

     What each block decides:
       1  own-cast secrecy .... whether a "track my own DoT from my own cast"
                                design is possible at all
       2  secret alpha sink ... whether SetAlphaFromBoolean works from tainted code,
                                and whether the aspect cost then blocks SetScript
                                or geometry reads (would break a WeakAuras layout engine)
       3  duration carrier .... whether a secret-bearing LuaDurationObject may be
                                spent by its own Format/Evaluate methods
       4  spellbook sweep ..... whether ANY spell you know is flagged NeverSecret
       5  proc overlay ........ whether Forever populates spell activation overlays
       6  engine aura button .. whether CustomAuraButtonTemplate exists in FrameXML
       7  secret introspection. which of canaccessvalue/canaccesssecrets exist
]]

local castFrame = CreateFrame("Frame")
castFrame:SetScript("OnEvent", function(_, event, a1, a2, a3)
	local ok, line = pcall(function()
		if event == "UNIT_SPELLCAST_SUCCEEDED" then
			if a1 ~= "player" then return nil end
			return ("UNIT_SPELLCAST_SUCCEEDED player castGUID=%s spellID=%s"):format(show(a2), show(a3))
		end
		return ("%s a1=%s a2=%s"):format(event, show(a1), show(a2))
	end)
	if ok and line == nil then return end
	ForeverDevInfoDB.castLog = ForeverDevInfoDB.castLog or {}
	local l = ForeverDevInfoDB.castLog
	l[#l + 1] = date("%H:%M:%S") .. " " .. (ok and line or ("ERROR " .. show(line)))
	while #l > 60 do table.remove(l, 1) end
	print("|cff33ff99FDI|r " .. (ok and line or "ERROR"))
end)

local function armCastLog()
	ForeverDevInfoDB.castLog = {}
	for _, e in ipairs({ "UNIT_SPELLCAST_SUCCEEDED", "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
		"SPELL_ACTIVATION_OVERLAY_SHOW", "SPELL_UPDATE_COOLDOWN" }) do
		pcall(castFrame.RegisterEvent, castFrame, e)
	end
	print("|cff33ff99FDI|r recording casts for 25s - cast Immolate now.")
	C_Timer.After(25, function()
		pcall(castFrame.UnregisterAllEvents, castFrame)
		print("|cff33ff99FDI|r cast recording finished.")
	end)
end

local function probe2()
	local out = {}
	local function add(fmt, ...)
		local line = select("#", ...) > 0 and fmt:format(...) or fmt
		out[#out + 1] = line
		print("|cff33ff99FDI|r " .. line)
	end

	add("=== probe round 2, %s ===", date("%H:%M:%S"))
	add("InCombatLockdown=%s  ShouldAurasBeSecret=%s  ShouldCooldownsBeSecret=%s",
		ask(InCombatLockdown), ask(C_Secrets and C_Secrets.ShouldAurasBeSecret),
		ask(C_Secrets and C_Secrets.ShouldCooldownsBeSecret))

	-- 1. Is my OWN cast readable even though the target auras are not?
	add("[1] ShouldUnitSpellCastBeSecret(player,348)=%s  (target,348)=%s  ShouldUnitSpellCastingBeSecret(player)=%s",
		ask(C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret, "player", 348),
		ask(C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret, "target", 348),
		ask(C_Secrets and C_Secrets.ShouldUnitSpellCastingBeSecret, "player"))

	-- 2. Does the one tainted-allowed secret sink work, and what does the aspect cost break?
	add("[2] %s", (function()
		local ok, res = pcall(function()
			local f = CreateFrame("Frame", nil, UIParent)
			f:Hide()
			local t = f:CreateTexture()
			local v = C_Spell and C_Spell.IsActiveSpell and C_Spell.IsActiveSpell(348)
			local sink = pcall(t.SetAlphaFromBoolean, t, v, 1, 0)
			local aspect = "n/a"
			if t.HasSecretAspect and Enum and Enum.SecretAspect then
				local ok2, r = pcall(t.HasSecretAspect, t, Enum.SecretAspect.Alpha)
				aspect = ok2 and show(r) or ("err:" .. show(r))
			end
			local rescript = pcall(f.SetScript, f, "OnUpdate", function() end)
			local geom = pcall(function() return t:GetWidth() + 0 end)
			local readback = pcall(function() return t:GetAlpha() + 0 end)
			return ("SetAlphaFromBoolean=%s alphaAspectSecret=%s SetScript-after=%s GetWidth-after=%s GetAlpha-after=%s")
				:format(tostring(sink), aspect, tostring(rescript), tostring(geom), tostring(readback))
		end)
		return "secret alpha sink: " .. (ok and res or ("ERROR " .. show(res)))
	end)())

	-- 3. Can a secret-bearing duration object be spent by its own methods?
	add("[3] %s", (function()
		local ok, res = pcall(function()
			local getter = C_Spell and C_Spell.GetSpellCooldownDuration
			if type(getter) ~= "function" then return "GetSpellCooldownDuration missing" end
			local okg, d = pcall(getter, 348, false)
			if not okg then return "getter ERROR " .. show(d) end
			if issecretvalue(d) then return "duration object itself is <secret>" end
			if d == nil then return "returned nil" end
			local parts = { "obj=ok" }
			if d.HasSecretValues then
				local o, r = pcall(d.HasSecretValues, d)
				parts[#parts + 1] = "hasSecretValues=" .. (o and show(r) or "err")
			end
			local okf, fmt = false, nil
			if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
				okf, fmt = pcall(C_StringUtil.CreateSecondsFormatter)
			end
			if okf and fmt then
				local fs = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				parts[#parts + 1] = "SetText(FormatRemaining)=" ..
					tostring(pcall(function() fs:SetText(d:FormatRemainingDuration(fmt)) end))
			else
				parts[#parts + 1] = "no SecondsFormatter"
			end
			if C_CurveUtil and C_CurveUtil.CreateCurve then
				local oc, c = pcall(C_CurveUtil.CreateCurve)
				if oc and c then
					pcall(c.AddPoint, c, 0, 0)
					pcall(c.AddPoint, c, 1, 1)
					local b = CreateFrame("StatusBar", nil, UIParent)
					b:Hide()
					parts[#parts + 1] = "SetValue(EvaluateRemainingPercent)=" ..
						tostring(pcall(function() b:SetValue(d:EvaluateRemainingPercent(c)) end))
				end
			end
			return table.concat(parts, " ")
		end)
		return "duration carrier: " .. (ok and res or ("ERROR " .. show(res)))
	end)())

	-- 4. Is ANY spell you know exempt from secrecy? Those need no workaround at all.
	add("[4] %s", (function()
		local ok, res = pcall(function()
			if not (C_SpellBook and C_Secrets and C_Secrets.GetSpellAuraSecrecy) then return "api missing" end
			local readable, total = {}, 0
			for i = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
				local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
				if line then
					for j = line.itemIndexOffset + 1, line.itemIndexOffset + (line.numSpellBookItems or 0) do
						local oi, info = pcall(C_SpellBook.GetSpellBookItemInfo, j, 0)
						local sid = oi and info and info.spellID
						if sid then
							total = total + 1
							local oks, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, sid)
							if oks and lvl == 0 then
								readable[#readable + 1] = ("%s(%d)"):format(tostring(C_Spell.GetSpellName(sid)), sid)
							end
						end
					end
				end
			end
			return ("%d spells scanned, %d NeverSecret: %s"):format(total, #readable,
				#readable > 0 and table.concat(readable, ", ") or "none")
		end)
		return "spellbook secrecy sweep: " .. (ok and res or ("ERROR " .. show(res)))
	end)())

	-- 5. Does Forever populate spell activation overlays (the proc-glow channel)?
	add("[5] IsSpellOverlayed(348)=%s  C_SpellActivationOverlay=%s",
		ask(C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed, 348),
		type(C_SpellActivationOverlay))

	-- 6. Does the engine-drawn aura button exist? It would be correct by construction.
	add("[6] C_AuraContainerUtil=%s CustomAuraButtonMixin=%s AuraContainerMixin=%s CreateFrame(CustomAuraButtonTemplate)=%s",
		type(C_AuraContainerUtil), type(_G.CustomAuraButtonMixin), type(_G.AuraContainerMixin),
		tostring(pcall(CreateFrame, "Button", nil, UIParent, "CustomAuraButtonTemplate")))

	-- 7. What introspection exists for telling a secret apart from a nil?
	add("[7] issecretvalue=%s canaccessvalue=%s canaccesssecrets=%s canaccesstable=%s",
		type(_G.issecretvalue), type(_G.canaccessvalue), type(_G.canaccesssecrets), type(_G.canaccesstable))

	ForeverDevInfoDB = ForeverDevInfoDB or {}
	local p2 = ForeverDevInfoDB.probes2 or {}
	p2[#p2 + 1] = out
	while #p2 > 6 do table.remove(p2, 1) end
	ForeverDevInfoDB.probes2 = p2
	add("(stored)")
end

SLASH_FOREVERDEVSECRET21 = "/fdsecret2"
SlashCmdList["FOREVERDEVSECRET2"] = function(msg)
	msg = (msg or ""):lower():gsub("%s", "")
	if msg == "sound" then
		-- Separate on purpose: this REGISTERS a sound the client will play when
		-- Immolate drops off the target. Session-only, but it changes what you hear.
		local ok, res = pcall(C_UnitAuras.AddAuraSound,
			Enum.UnitAuraSoundTrigger.Removed,
			{ unitToken = "target", spellID = 348,
			  soundFileName = "Sound\\Interface\\MagicClick.ogg",
			  outputChannel = "Master", throttleSeconds = 1 })
		print("|cff33ff99FDI|r AddAuraSound -> " .. (ok and show(res) or ("ERROR " .. show(res))))
		return
	end
	probe2()
	armCastLog()
end

--[[ ForeverSlotProbe - proof of concept for an ENGINE-DRAWN aura indicator.

     Blizzard_AuraContainer ships CustomAuraContainerTemplate / CustomAuraButtonTemplate
     in the GLOBAL environment on purpose ("to allow intrinsics and templates to be
     instantiated by external code" - its TOC). Every inbound method is a secure
     delegate: our tainted call crosses into the secure partition, where the aura
     reads happen untainted. The engine then writes SECRET values into regions we
     hand over (icon, cooldown, duration text, count), so the display is correct
     while we can never read it back.

     The "missing" indicator is a plain frame drawn UNDER the aura button. When the
     engine shows the button (aura present) it covers the indicator; when the aura is
     absent the button is hidden and the indicator shows through. No secret ever
     crosses into our code.

     /fdslot        build it (out of combat), idempotent
     /fdslot auto   toggle auto-build at login
     /fdslot hide   hide both frames
     /fdslot show   show both frames
     Log: ForeverDevInfoDB.slotProbe
]]

local SPELL, SIZE = 348, 48
local slot = {}


local function slog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.slotProbe = ForeverDevInfoDB.slotProbe or {}
	local l = ForeverDevInfoDB.slotProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 80 do table.remove(l, 1) end
	print("|cff33ff99FDI slot|r " .. line)
end

local function try(label, fn, ...)
	if type(fn) ~= "function" then
		slog("%s -> missing", label)
		return false
	end
	local ok, res = pcall(fn, ...)
	slog("%s -> %s", label, ok and "ok" or ("ERROR: " .. show(res)))
	return ok, res
end

-- Only plain, never-secret data drives the indicator: does a hostile target exist.
-- Whether Immolate is on it is the engine's business.
local function updateIndicator(event)
	local ind, c = slot.indicator, slot.container
	if not ind or not c then return end
	pcall(function()
		local hostile = UnitExists("target") and UnitCanAttack("player", "target")
		ind:SetShown(hostile and true or false)
	end)
	if event == "PLAYER_TARGET_CHANGED" then
		-- The container refreshes on UNIT_AURA, faction and flags, but the base
		-- mixin says target changes are the caller's job. Does a tainted caller
		-- get to do that in combat? This line answers it.
		local ok, err = pcall(c.UpdateAllAuras, c)
		slog("target changed -> UpdateAllAuras %s (combat=%s)",
			ok and "ok" or ("ERROR: " .. show(err)), tostring(InCombatLockdown()))
	end
end

local function buildSlotProbe()
	if slot.container then
		slog("already built")
		return
	end
	if InCombatLockdown() then
		slog("build it out of combat")
		return
	end

	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
	slog("Blizzard_AuraContainer loaded=%s exportedDefaults=%s", tostring(loaded), type(_G.CustomAuraContainerSlotDefaultOptions))
	if not loaded and C_AddOns and C_AddOns.LoadAddOn then
		try("LoadAddOn(Blizzard_AuraContainer)", C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end

	-- 1. The container. Its intrinsic type is AuraContainer; the template is virtual.
	local ok, c = pcall(CreateFrame, "AuraContainer", "FDISlotContainer", UIParent, "CustomAuraContainerTemplate")
	if not ok or not c then
		slog("CreateFrame(AuraContainer) failed: %s - retrying as Frame", show(c))
		ok, c = pcall(CreateFrame, "Frame", "FDISlotContainer", UIParent, "CustomAuraContainerTemplate")
	end
	if not ok or not c then
		slog("container creation failed: %s", show(c))
		return
	end
	slot.container = c
	slog("container ok: type=%s AddAuraSlot=%s SetUnit=%s UpdateAllAuras=%s",
		show(c:GetObjectType()), type(c.AddAuraSlot), type(c.SetUnit), type(c.UpdateAllAuras))
	c:SetSize(SIZE, SIZE)
	c:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
	c:SetFrameStrata("MEDIUM")

	-- 2. The "missing" indicator, UNDER the container.
	local ind = CreateFrame("Frame", "FDISlotMissing", UIParent)
	ind:SetSize(SIZE, SIZE)
	ind:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
	ind:SetFrameStrata("LOW")
	local bg = ind:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.85, 0.1, 0.1, 0.9)
	local txt = ind:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	txt:SetPoint("CENTER")
	txt:SetText("CAST\nIMMOLATE")
	ind:Hide()
	slot.indicator = ind

	try("SetUnit(target)", c.SetUnit, c, "target")

	-- 3. The slot. Regions are handed over inside initializeFrame, which runs
	--    BEFORE the button gets its DenyTaintedAccessWhenAurasAreSecret restriction.
	local function init(frame)
		slog("initializeFrame: type=%s SetIcon=%s parentIsContainer=%s",
			show(frame:GetObjectType()), type(frame.SetIcon), tostring(frame:GetParent() == c))
		frame:SetSize(SIZE, SIZE)
		local icon = frame:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
		cd:SetAllPoints()
		local dur = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		dur:SetPoint("TOP", frame, "BOTTOM", 0, -2)
		local cnt = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		cnt:SetPoint("BOTTOMRIGHT", -2, 2)
		local pand = frame:CreateTexture(nil, "BACKGROUND")
		pand:SetPoint("TOPLEFT", -4, 4)
		pand:SetPoint("BOTTOMRIGHT", 4, -4)
		pand:SetColorTexture(1, 0.8, 0, 0.8)
		try("SetIcon", frame.SetIcon, frame, icon)
		try("SetDurationCooldown", frame.SetDurationCooldown, frame, cd)
		try("SetDurationText", frame.SetDurationText, frame, dur, nil)
		try("SetApplicationCount", frame.SetApplicationCount, frame, cnt, nil)
		try("AddPandemicRegion", frame.AddPandemicRegion, frame, pand)
		try("SetHideTooltipInCombat", frame.SetHideTooltipInCombat, frame, false)
	end

	local frame
	for _, filter in ipairs({ "HARMFUL|PLAYER", "HARMFUL" }) do
		local okS, res = pcall(c.AddAuraSlot, c, "immolate", filter, {
			candidateFilters = { includeSpellIDs = { [SPELL] = true } },
			initializeFrame = init,
		})
		slog("AddAuraSlot(%s) -> %s", filter, okS and "ok" or ("ERROR: " .. show(res)))
		if okS then
			frame = res
			break
		end
	end
	if not frame then
		slog("no slot frame - stopping")
		return
	end
	slot.frame = frame

	slog("slot frame: type=%s forbidden=%s IsShown-readable=%s",
		show(frame:GetObjectType()), tostring(frame:IsForbidden()),
		tostring(pcall(function() return frame:IsShown() == true end)))
	-- Slots take no part in flow layout and must be anchored by us.
	try("anchor slot frame", function()
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", c, "CENTER")
		frame:SetFrameLevel(c:GetFrameLevel() + 5)
	end)

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("PLAYER_TARGET_CHANGED")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event) updateIndicator(event) end)
	slot.events = ev
	updateIndicator()

	slog("built. Target a mob and cast Immolate: red box = missing, engine icon = present.")
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
	if ForeverDevInfoDB and ForeverDevInfoDB.slotAuto then
		buildSlotProbe()
	end
end)

SLASH_FOREVERDEVSLOT1 = "/fdslot"
SlashCmdList["FOREVERDEVSLOT"] = function(msg)
	msg = (msg or ""):lower():gsub("%s", "")
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	if msg == "auto" then
		ForeverDevInfoDB.slotAuto = not ForeverDevInfoDB.slotAuto
		print("|cff33ff99FDI slot|r auto-build at login: " .. tostring(ForeverDevInfoDB.slotAuto))
	elseif msg == "hide" or msg == "show" then
		local fn = (msg == "hide") and "Hide" or "Show"
		if slot.container then pcall(slot.container[fn], slot.container) end
		if slot.indicator then pcall(slot.indicator[fn], slot.indicator) end
	else
		buildSlotProbe()
	end
end

print("|cff33ff99FDI|r slot probe loaded - /fdslot builds the engine-drawn Immolate indicator (out of combat).")

--[[ ------------------------------------------------------------------------
     /fdsecret3 [spellID]  - probe round 3: COOLDOWN duration-object sinks.

     Builds a visible test widget (default spell 348) and, on every
     SPELL_UPDATE_COOLDOWN, re-fetches C_Spell.GetSpellCooldownDuration(id)
     and feeds the SAME object into five different sinks. Cast anything so the
     GCD produces a 1.5 s cooldown, in combat, and watch which parts move:

       A  Cooldown frame     : cooldown:SetCooldownFromDurationObject(d, true)   (swipe)
       B  DurationTextBinding: binding:SetDuration(d) -> live text, no polling
       C  StatusBar          : bar:SetTimerDuration(d, "Immediate", "RemainingTime")
       D  FontString         : fs:SetText(d:FormatRemainingDuration(fmt))     (snapshot)
       E  Alpha              : cover:SetAlphaFromBoolean(d:IsActive(), 1, 0)  (snapshot: shows a
                               red cover ONLY while the cooldown is active)
     Each call is pcall-logged to ForeverDevInfoDB.probes3.
     /fdsecret3 hide removes the widget.
]]

local cd3 = {}

local function p3log(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.probes3 = ForeverDevInfoDB.probes3 or {}
	local l = ForeverDevInfoDB.probes3
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 120 do table.remove(l, 1) end
	print("|cff33ff99FDI cd|r " .. line)
end

local function p3try(label, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then p3log("%s -> ERROR: %s", label, show(res)) end
	return ok, res
end

local function buildCooldownProbe(spellID)
	if cd3.frame then cd3.frame:Show(); return end
	local f = CreateFrame("Frame", "FDICooldownProbe", UIParent)
	f:SetSize(64, 64)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)

	-- A: cooldown swipe from the duration object
	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	pcall(cd.SetDrawBling, cd, false)

	-- B: live text binding
	local fsB = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	fsB:SetPoint("TOP", f, "BOTTOM", 0, -2)
	local okB, binding = pcall(C_DurationUtil.CreateDurationTextBinding)
	if okB and binding then
		p3try("binding:SetFontString", binding.SetFontString, binding, fsB)
		local okF, fmt = pcall(C_StringUtil.CreateSecondsFormatter)
		if okF and fmt then p3try("binding:SetFormatter", binding.SetFormatter, binding, fmt) end
		p3try("binding:SetZeroDurationText", binding.SetZeroDurationText, binding, "ready")
		p3try("binding:SetEnabled", binding.SetEnabled, binding, true)
	else
		p3log("CreateDurationTextBinding -> ERROR %s", show(binding))
	end

	-- C: live status bar
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetSize(64, 8)
	bar:SetPoint("TOP", fsB, "BOTTOM", 0, -2)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.2, 0.8, 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.6)

	-- D: snapshot text
	local fsD = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fsD:SetPoint("TOP", bar, "BOTTOM", 0, -2)

	-- E: alpha-from-secret cover: visible ONLY while the cooldown is active
	local cover = CreateFrame("Frame", nil, f)
	cover:SetAllPoints(icon)
	cover:SetFrameLevel(f:GetFrameLevel() + 5)
	local ct = cover:CreateTexture(nil, "OVERLAY")
	ct:SetAllPoints(); ct:SetColorTexture(1, 0, 0, 0.55)

	cd3.frame, cd3.cd, cd3.binding, cd3.bar, cd3.fsD, cd3.cover, cd3.spell = f, cd, binding, bar, fsD, cover, spellID
	cd3.fmt = select(2, pcall(C_StringUtil.CreateSecondsFormatter))
	cd3.n = 0

	local ev = CreateFrame("Frame")
	ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event, a1)
		if event == "SPELL_UPDATE_COOLDOWN" and a1 ~= nil and not issecretvalue(a1) and a1 ~= cd3.spell then
			return -- Forever passes the spellID; ignore other spells' updates
		end
		cd3.apply(event .. "(" .. show(a1) .. ")")
	end)
	cd3.events = ev
	p3log("cooldown probe built for spell %d - cast something (GCD = 1.5s cooldown) and watch A-E", spellID)
end

function cd3.apply(reason)
	if not cd3.frame then return end
	cd3.n = cd3.n + 1
	local verbose = cd3.n <= 6 or (cd3.n % 20 == 0)
	local okd, d = pcall(C_Spell.GetSpellCooldownDuration, cd3.spell, false)
	if not okd or not d then p3log("[%s] GetSpellCooldownDuration ERROR %s", reason, show(d)); return end
	local secret = select(2, pcall(d.HasSecretValues, d))
	local r = {}
	local ok
	ok = p3try("A SetCooldownFromDurationObject", cd3.cd.SetCooldownFromDurationObject, cd3.cd, d, true); r[#r + 1] = "A=" .. tostring(ok)
	if cd3.binding then ok = p3try("B binding:SetDuration", cd3.binding.SetDuration, cd3.binding, d); r[#r + 1] = "B=" .. tostring(ok) end
	ok = p3try("C bar:SetTimerDuration", cd3.bar.SetTimerDuration, cd3.bar, d, Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0, Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1); r[#r + 1] = "C=" .. tostring(ok)
	if cd3.fmt then ok = p3try("D SetText(FormatRemaining)", function() cd3.fsD:SetText(d:FormatRemainingDuration(cd3.fmt)) end); r[#r + 1] = "D=" .. tostring(ok) end
	ok = p3try("E SetAlphaFromBoolean(IsActive)", function() cd3.cover:SetAlphaFromBoolean(d:IsActive(), 1, 0) end); r[#r + 1] = "E=" .. tostring(ok)
	local okZ, z = pcall(d.IsZero, d)
	r[#r + 1] = "IsZero=" .. (okZ and show(z) or "err")
	-- The plain-readable half: SpellCooldownInfo.isActive/isEnabled/isOnGCD are NeverSecret, and the
	-- fork's "Show On: Ready" relies on IsSpellReady() built from them. Does it answer right on Forever?
	pcall(function()
		local ci = C_Spell.GetSpellCooldown(cd3.spell)
		if type(ci) == "table" then
			r[#r + 1] = ("cdInfo{active=%s enabled=%s onGCD=%s startRec=%s startSecret=%s}"):format(
				show(rawget(ci, "isActive")), show(rawget(ci, "isEnabled")), show(rawget(ci, "isOnGCD")),
				show(rawget(ci, "timeUntilEndOfStartRecovery")), tostring(issecretvalue(rawget(ci, "startTime"))))
		else
			r[#r + 1] = "cdInfo=" .. show(ci)
		end
		local WA = _G.EverAuras
		if WA and WA.IsSpellReady then r[#r + 1] = "WA.IsSpellReady=" .. show(select(2, pcall(WA.IsSpellReady, cd3.spell))) end
		if WA and WA.IsSpellReadyFromDuration then r[#r + 1] = "WA.IsReadyFromDuration=" .. show(select(2, pcall(WA.IsSpellReadyFromDuration, cd3.spell))) end
		if C_Spell.IsSpellUsable then r[#r + 1] = "usable=" .. show(select(2, pcall(C_Spell.IsSpellUsable, cd3.spell))) end
	end)
	if verbose then
		p3log("[%s] combat=%s cdSecret=%s hasSecretValues=%s | %s", reason, tostring(InCombatLockdown()),
			ask(C_Secrets and C_Secrets.ShouldCooldownsBeSecret), show(secret), table.concat(r, " "))
	end
end

SLASH_FOREVERDEVSECRET31 = "/fdsecret3"
SlashCmdList["FOREVERDEVSECRET3"] = function(msg)
	msg = (msg or ""):lower():gsub("%s", "")
	if msg == "hide" then
		if cd3.frame then cd3.frame:Hide() end
		if cd3.events then cd3.events:UnregisterAllEvents() end
		return
	end
	buildCooldownProbe(tonumber(msg) or 348)
	cd3.apply("initial")
end

---------------------------------------------------------------------------- /fdrange
-- Can tainted code check spell range in combat on Forever?  The API docs list
-- C_Spell.IsSpellInRange WITHOUT SecretReturns (unlike UnitInRange), so it should answer
-- with a plain boolean. This probe logs the raw return, whether it is secret, and drives a
-- box on screen from it through SetAlphaFromBoolean - the one sink that also accepts a
-- secret boolean. Bright box = in range, dim box = out of range / no target.
--   /fdrange                 Serpent Sting on target, samples for 30 s
--   /fdrange <id or name>    another spell, e.g. /fdrange 1978 or /fdrange Arcane Shot
--   /fdrange stop            stop sampling and hide the box
local rng = {}

local function rlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.rangeProbe = ForeverDevInfoDB.rangeProbe or {}
	local l = ForeverDevInfoDB.rangeProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 150 do table.remove(l, 1) end
	print("|cff33ff99FDI range|r " .. line)
end

local function buildRangeBox()
	if rng.frame then return end
	local fr = CreateFrame("Frame", nil, UIParent)
	fr:SetSize(48, 48)
	fr:SetPoint("CENTER", UIParent, "CENTER", 120, -120)
	fr:SetFrameStrata("HIGH")
	local bg = fr:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(fr)
	bg:SetColorTexture(0.1, 0.9, 0.2, 1)
	local fs = fr:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER")
	fs:SetText("RANGE")
	rng.frame = fr
end

-- One sample. Returns the log line, the raw result (or nil) and whether it was secret.
local function rangeSample(spell, verbose)
	local parts = {}
	local okR, r = pcall(C_Spell.IsSpellInRange, spell, "target")
	local secretR = okR and issecretvalue(r) or false
	parts[#parts + 1] = "IsSpellInRange=" .. (okR and show(r) or ("ERROR " .. show(r)))
	parts[#parts + 1] = "combat=" .. tostring(InCombatLockdown())
	if verbose then
		parts[#parts + 1] = "type=" .. ((okR and not secretR) and type(r) or "secret")
		parts[#parts + 1] = "UnitInRange=" .. ask(UnitInRange, "target")
		parts[#parts + 1] = "DistSq=" .. ask(UnitDistanceSquared, "target")
		parts[#parts + 1] = "Interact4=" .. ask(CheckInteractDistance, "target", 4)
		parts[#parts + 1] = "exists=" .. ask(UnitExists, "target")
		parts[#parts + 1] = "canAttack=" .. ask(UnitCanAttack, "player", "target")
		local okI, info = pcall(C_Spell.GetSpellInfo, spell)
		if okI and type(info) == "table" then
			parts[#parts + 1] = ("spell=%s id=%s min=%s max=%s"):format(
				show(info.name), show(info.spellID), show(info.minRange), show(info.maxRange))
		else
			parts[#parts + 1] = "spell=<unknown: " .. show(spell) .. ">"
		end
	end
	-- the sink: a plain OR secret boolean may drive alpha; nil means "no valid check"
	if rng.frame then
		if okR and (secretR or r ~= nil) then
			local okA, err = pcall(rng.frame.SetAlphaFromBoolean, rng.frame, r, 1, 0.15)
			if not okA then parts[#parts + 1] = "SetAlphaFromBoolean ERROR " .. show(err) end
		else
			rng.frame:SetAlpha(0.15)
		end
	end
	return table.concat(parts, " "), okR and r or nil, secretR
end

local function stopRangeProbe()
	if rng.ticker then rng.ticker:Cancel(); rng.ticker = nil end
	if rng.frame then rng.frame:Hide() end
end

SLASH_FOREVERDEVRANGE1 = "/fdrange"
SlashCmdList["FOREVERDEVRANGE"] = function(msg)
	msg = strtrim(msg or "")
	if msg:lower() == "stop" or msg:lower() == "hide" then
		stopRangeProbe()
		rlog("stopped")
		return
	end
	local spell = tonumber(msg) or (msg ~= "" and msg) or "Serpent Sting"
	stopRangeProbe()
	buildRangeBox()
	rng.frame:Show()
	local line, _, secret = rangeSample(spell, true)
	rlog("[start] %s", line)
	-- 30 s at 0.5 s: log every change; when the value is secret (uncomparable) log a heartbeat
	local last, n = nil, 0
	rng.ticker = C_Timer.NewTicker(0.5, function()
		n = n + 1
		local l, _, s = rangeSample(spell, false)
		if s then
			if n % 10 == 0 then rlog("[secret] %s (box alpha tracks it? look at the box)", l) end
		elseif l ~= last then
			rlog("[change] %s", l)
			last = l
		end
		if n >= 60 then
			rlog("[done] %d samples", n)
			rng.ticker = nil
			if rng.frame then rng.frame:Hide() end
		end
	end, 60)   -- 60 iterations: the ticker stops itself
end

---------------------------------------------------------------------------- /fdload
-- Which flavour does EverAuras think this client is, and is each class-filtered display loaded?
--   /fdload          log flavour facts + every display that has a Player Class load condition
local function llog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.loadProbe = ForeverDevInfoDB.loadProbe or {}
	local l = ForeverDevInfoDB.loadProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 80 do table.remove(l, 1) end
	print("|cff33ff99FDI load|r " .. line)
end

SLASH_FOREVERDEVLOAD1 = "/fdload"
SlashCmdList["FOREVERDEVLOAD"] = function()
	local EA = _G.EverAuras
	if not EA then llog("EverAuras not loaded"); return end
	local _, class = UnitClass("player")
	llog("[flavour] BuildInfo=%s IsRetail=%s IsClassicEra=%s IsForever=%s X-Flavor=%s class=%s",
		show(EA.BuildInfo), ask(EA.IsRetail), ask(EA.IsClassicEra), ask(EA.IsForever),
		show(C_AddOns.GetAddOnMetadata("EverAuras", "X-Flavor")), show(class))
	local db = _G.EverAurasSaved
	local n = 0
	for id, data in pairs(db and db.displays or {}) do
		local load = data.load
		if load and load.use_class ~= nil then
			n = n + 1
			local multi = {}
			for k, v in pairs(load.class and load.class.multi or {}) do if v then multi[#multi + 1] = k end end
			llog("[display] %s: use_class=%s single=%s multi=[%s] loaded=%s",
				id, show(load.use_class), show(load.class and load.class.single), table.concat(multi, ","),
				ask(EA.IsAuraLoaded, id))
		end
	end
	llog("[done] %d display(s) with a Player Class condition", n)
end
