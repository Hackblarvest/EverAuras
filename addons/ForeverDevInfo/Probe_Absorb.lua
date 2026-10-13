--[[ Probe_Absorb.lua - EverAuras Shield, track "apis": what can addon code learn and draw about absorbs on Forever?

     Written for the ForeverDevInfo dev addon (add "Probe_Absorb.lua" to ForeverDevInfo.toc, /reload); it logs
     into ForeverDevInfoDB.absProbe. Nothing here reads, compares or does arithmetic on a secret: secret values
     only ever go to widget setters and formatters the documentation marks AllowedWhenTainted, and every call
     sits in a pcall so a refusal is logged instead of breaking the probe.

       /fdabs          one-shot report in chat + an on-screen panel (secret values are visible ONLY on the panel)
       /fdabs full N   give bar "B" (absorb vs full shield) a plain full size N (e.g. the points[1] seen out of combat)
       /fdabs watch    120 s event log: UNIT_ABSORB_AMOUNT_CHANGED, UNIT_AURA, own/pet casts, combat start/end.
                       A shield you cast yourself IN combat arms a snapshot: the next absorb change within 1 s is
                       stored (secret) as bar B's maximum.
       /fdabs hide     removes the panel and stops the log

     Suggested run: (1) out of combat, no shield: /fdabs. (2) cast your shield out of combat: /fdabs, note the
     panel and the "points" line. (3) /fdabs watch, take some hits (still OOC is impossible - just fight), drop
     combat, /fdabs again: did points[1] go DOWN (remaining) or stay (initial)? (4) in combat with the shield up:
     /fdabs (panel must keep working). (5) /reload so the log lands in SavedVariables.
]]

local P = { lines = {}, fs = {} }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local SECRECY = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }

-- spell ids from SpellName.db2 (client 1.60.1.70338), every rank incl. some NPC copies
local SHIELD_IDS = {
	17, 592, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901,          -- Power Word: Shield
	11426, 13031, 13032, 13033,                                          -- Ice Barrier
	1463, 8494, 8495, 10191, 10192, 10193,                               -- Mana Shield
	543, 8457, 8458, 10223, 10225,                                       -- Fire Ward
	6143, 8461, 8462, 10177, 28609,                                      -- Frost Ward
	6229, 11739, 11740, 28610,                                           -- Shadow Ward
	7812, 19438, 19440, 19441, 19442, 19443,                             -- Sacrifice (Voidwalker)
	128, 17729, 17730,                                                   -- Spellstone (item spells)
}
local IS_SHIELD = {}
for _, id in ipairs(SHIELD_IDS) do IS_SHIELD[id] = true end

local function S(v)                    -- printable form; never compares, tests or converts a secret
	if issecretvalue and issecretvalue(v) then return "<secret " .. type(v) .. ">" end
	if v == nil then return "nil" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function log(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.absProbe = ForeverDevInfoDB.absProbe or {}
	local l = ForeverDevInfoDB.absProbe
	l[#l + 1] = date("%H:%M:%S ") .. line
	while #l > 800 do table.remove(l, 1) end
	print("|cff33ff99abs|r " .. line)
end

local function try(label, fn, ...)          -- each refusal is logged once per combat state
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		P.errSeen = P.errSeen or {}
		local key = label .. (InCombatLockdown() and "/combat" or "/ooc")
		if not P.errSeen[key] then P.errSeen[key] = true; log("%s -> ERROR %s", key, S(a)) end
	end
	return ok, a, b, c
end

---------------------------------------------------------------------------- on-screen panel
local function Text(key, y, caption)
	local fs = P.fs[key]
	if not fs then
		fs = P.panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		fs:SetPoint("TOPLEFT", P.panel, "TOPLEFT", 150, y)
		local cap = P.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		cap:SetPoint("TOPLEFT", P.panel, "TOPLEFT", 6, y)
		cap:SetText(caption)
		P.fs[key] = fs
	end
	return fs
end

local function Bar(key, y, caption, r, g, b)
	if P[key] then return P[key] end
	local cap = P.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", P.panel, "TOPLEFT", 6, y)
	cap:SetText(caption)
	local bg = P.panel:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0.15, 0.15, 0.15, 1)
	bg:SetPoint("TOPLEFT", P.panel, "TOPLEFT", 150, y)
	bg:SetSize(200, 12)
	local bar = CreateFrame("StatusBar", nil, P.panel)
	bar:SetStatusBarTexture(WHITE)
	bar:SetStatusBarColor(r, g, b, 1)
	bar:SetAllPoints(bg)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	P[key] = bar
	return bar
end

local function Square(key, x, y, caption, r, g, b)
	if P[key] then return P[key] end
	local t = P.panel:CreateTexture(nil, "ARTWORK")
	t:SetColorTexture(r, g, b, 1)
	t:SetSize(24, 24)
	t:SetPoint("TOPLEFT", P.panel, "TOPLEFT", x, y)
	local cap = P.panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("TOP", t, "BOTTOM", 0, -2)
	cap:SetText(caption)
	P[key] = t
	return t
end

local function BuildPanel()
	if P.panel then P.panel:Show(); return end
	local f = CreateFrame("Frame", "FDAbsProbePanel", UIParent)
	f:SetSize(380, 490)
	f:SetPoint("CENTER", UIParent, "CENTER", 360, 80)
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bgTex = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	f.bgTex:SetAllPoints(); f.bgTex:SetColorTexture(0, 0, 0, 0.7)
	P.panel = f
	local y = -6
	for _, row in ipairs({
		{ "raw",   "SetText(absorb)" },
		{ "twz",   "TruncateWhenZero" },
		{ "abbr",  "AbbreviateNumbers" },
		{ "brk",   "BreakUpLargeNumbers" },
		{ "fmtd",  "SetFormattedText %d" },
		{ "wrap",  "WrapString(TWZ,'Shield: ')" },
		{ "cat",   "'x' .. absorb" },
		{ "sfmt",  "string.format('%d')" },
		{ "tostr", "tostring(absorb)" },
		{ "heal",  "UnitGetTotalHealAbsorbs" },
		{ "calc",  "calc:GetDamageAbsorbs()" },
		{ "frac",  "readout fraction (B)" },
		{ "pct",   "readout x100 -> '62%'" },
	}) do Text(row[1], y, row[2]); y = y - 18 end
	Bar("barA", y, "A absorb / UnitHealthMax", 1, 1, 1); y = y - 20
	Bar("barB", y, "B absorb / full shield", 0.4, 0.8, 1); y = y - 20
	Bar("barC", y, "C gate: range (0,1)", 0.3, 1, 0.3); y = y - 20
	Bar("barD", y, "D range (0,1) Center fill", 1, 0.8, 0.2); y = y - 30

	-- E: StatusBar in Radial render mode (if the client has it)
	local e = CreateFrame("StatusBar", nil, f)
	e:SetSize(64, 64); e:SetPoint("TOPLEFT", f, "TOPLEFT", 10, y)
	e:SetStatusBarTexture(WHITE); e:SetStatusBarColor(0.4, 0.8, 1, 1)
	local okR, errR = pcall(e.SetRenderMode, e, Enum.StatusBarRenderMode and Enum.StatusBarRenderMode.Radial or 1)
	P.radialBar, P.radialOk = e, okR
	if not okR then log("StatusBar:SetRenderMode(Radial) -> ERROR %s", S(errR)) end
	local ecap = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); ecap:SetPoint("TOP", e, "BOTTOM", 0, -2); ecap:SetText("E radial bar (B range)")

	-- F: upstream M33kAuras readout trick: 65536 px driver bar, fill frame scaled 65536 -> GetWidth() = fraction
	local drv = CreateFrame("StatusBar", nil, f)
	drv:SetStatusBarTexture(WHITE); drv:SetStatusBarColor(1, 1, 1, 0)
	drv:SetSize(65536, 1); drv:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	local fill = CreateFrame("Frame", nil, f)
	fill:SetScale(65536)
	fill:SetAllPoints(drv:GetStatusBarTexture())
	local ring = f:CreateTexture(nil, "ARTWORK")
	ring:SetSize(64, 64); ring:SetPoint("TOPLEFT", f, "TOPLEFT", 110, y)
	ring:SetColorTexture(1, 0.6, 0.2, 1)
	-- a second readout on the same fill, scaled 65536/100: its width is the fraction x 100 (multiplication by
	-- geometry, no Lua arithmetic) -> TruncateWhenZero + WrapString make a "62%" text from it
	local fill100 = CreateFrame("Frame", nil, f)
	fill100:SetScale(65536 / 100)
	fill100:SetAllPoints(drv:GetStatusBarTexture())
	P.driver, P.fill, P.fill100, P.ring = drv, fill, fill100, ring
	local fcap = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); fcap:SetPoint("TOP", ring, "BOTTOM", 0, -2); fcap:SetText("F readout pie (B range)")

	Square("sqAlpha", 210, y, "G SetAlpha(absorb)", 1, 0.2, 0.2)
	Square("sqClamp", 300, y, "H clamped bool", 0.8, 0.3, 1)

	f:SetScript("OnUpdate", function()
		-- anchors resolve lazily, so the readout is refreshed every frame (as upstream does on FrameTick)
		local ok, w = pcall(P.fill.GetWidth, P.fill)
		if ok then
			pcall(P.ring.SetRadialProgressBarPercent, P.ring, w)
			pcall(P.fs.frac.SetText, P.fs.frac, w)
		end
		local ok2, w100 = pcall(P.fill100.GetWidth, P.fill100)
		if ok2 then
			pcall(function() P.fs.pct:SetText(C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(w100), "", "%")) end)
		end
	end)
end

---------------------------------------------------------------------------- refresh
local function Refresh(reason)
	if not (P.panel and P.panel:IsShown()) then return end
	local okA, a = pcall(UnitGetTotalAbsorbs, "player")
	if not okA then log("UnitGetTotalAbsorbs -> ERROR %s", S(a)); return end
	local maxHP = UnitHealthMax("player")

	try("SetText(raw)", P.fs.raw.SetText, P.fs.raw, a)
	try("TruncateWhenZero", function() P.fs.twz:SetText(C_StringUtil.TruncateWhenZero(a)) end)
	try("AbbreviateNumbers", function() P.fs.abbr:SetText(AbbreviateNumbers(a)) end)
	try("BreakUpLargeNumbers", function() P.fs.brk:SetText(BreakUpLargeNumbers(a)) end)
	try("SetFormattedText", function() P.fs.fmtd:SetFormattedText("%d absorb", a) end)
	try("WrapString", function() P.fs.wrap:SetText(C_StringUtil.WrapString(C_StringUtil.TruncateWhenZero(a), "Shield: ", "")) end)
	if not try("concat", function() P.fs.cat:SetText("x" .. a) end) then P.fs.cat:SetText("ERR") end
	if not try("string.format", function() P.fs.sfmt:SetText(string.format("%d", a)) end) then P.fs.sfmt:SetText("ERR") end
	if not try("tostring", function() P.fs.tostr:SetText(tostring(a)) end) then P.fs.tostr:SetText("ERR") end
	try("heal absorbs", function() P.fs.heal:SetText(UnitGetTotalHealAbsorbs("player")) end)

	-- A: absorb against max health (max plain for the player, value secret)
	try("barA", function() P.barA:SetMinMaxValues(0, maxHP); P.barA:SetValue(a) end)
	-- B: absorb against the shield's full size (plain from /fdabs full N, or a secret snapshot from watch).
	-- P.fullKind is a plain flag: a secret is never put through 'or' / 'if'.
	if P.fullKind then
		local full = P.full
		try("barB", function() P.barB:SetMinMaxValues(0, full); P.barB:SetValue(a) end)
		try("radial E", function() P.radialBar:SetMinMaxValues(0, full); P.radialBar:SetValue(a) end)
		try("driver F", function() P.driver:SetMinMaxValues(0, full); P.driver:SetValue(a) end)
	end
	-- C/D: a 0..1 range turns "absorb > 0" into an all-or-nothing fill (gate geometry)
	try("barC", function() P.barC:SetMinMaxValues(0, 1); P.barC:SetValue(a) end)
	try("barD", function() P.barD:SetFillStyle(Enum.StatusBarFillStyle.Center); P.barD:SetMinMaxValues(0, 1); P.barD:SetValue(a) end)
	-- G: does SetAlpha take a secret > 1 (clamp) or refuse it?
	try("SetAlpha(absorb)", P.sqAlpha.SetAlpha, P.sqAlpha, a)
	-- H: heal prediction calculator
	try("calculator", function()
		P.calc = P.calc or CreateUnitHealPredictionCalculator()
		P.calc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
		UnitGetDetailedHealPrediction("player", "player", P.calc)
		local amt, clamped = P.calc:GetDamageAbsorbs()
		P.fs.calc:SetText(amt)
		P.sqClamp:SetAlphaFromBoolean(clamped, 1, 0.15)
	end)
end

---------------------------------------------------------------------------- report
local function AuraLines()
	for i = 1, 40 do
		local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok then log("GetAuraDataByIndex(%d) -> ERROR %s", i, S(d)); return end
		if d == nil then
			if i == 1 then log("auras: none readable (nil at index 1)") end
			return
		end
		if issecretvalue(d) then log("aura %d: <secret table>", i); return end
		local id = d.spellId
		local pts = {}
		if type(d.points) == "table" and not issecretvalue(d.points) then
			for k = 1, 4 do if d.points[k] ~= nil then pts[#pts + 1] = S(d.points[k]) end end
		end
		if (not issecretvalue(id) and IS_SHIELD[id]) or #pts > 0 then
			log("aura %s %s (%s) points={%s} dur=%s src=%s inst=%s", S(id), S(d.name), S(d.icon),
				table.concat(pts, ","), S(d.duration), S(d.sourceUnit), S(d.auraInstanceID))
			if not issecretvalue(id) then
				local okD, desc = pcall(C_Spell.GetSpellDescription, id)
				log("   description(%s): %s", S(id), okD and S(desc) or "ERROR")
			end
		end
	end
end

local function Report()
	local _, build = GetBuildInfo()
	log("---- /fdabs  build %s  combat=%s  restrictions=%s  aurasSecret=%s", S(build), S(InCombatLockdown()),
		S(C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()),
		S(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()))
	local okA, a = pcall(UnitGetTotalAbsorbs, "player")
	log("UnitGetTotalAbsorbs: %s (type %s)  heal absorbs %s  incoming %s", okA and S(a) or "ERROR", okA and type(a) or "-",
		S(select(2, pcall(UnitGetTotalHealAbsorbs, "player"))), S(select(2, pcall(UnitGetIncomingHeals, "player"))))
	log("UnitHealthMax %s  UnitHealth %s  ShouldUnitHealthMaxBeSecret %s  hasanysecretvalues=%s", S(UnitHealthMax("player")),
		S(UnitHealth("player")), S(C_Secrets.ShouldUnitHealthMaxBeSecret and C_Secrets.ShouldUnitHealthMaxBeSecret("player")),
		type(hasanysecretvalues))
	local okC, calc = pcall(CreateUnitHealPredictionCalculator)
	if okC and calc then
		local okP, errP = pcall(UnitGetDetailedHealPrediction, "player", "player", calc)
		log("calculator: fill %s  HasSecretValues %s", okP and "ok" or ("ERROR " .. S(errP)), S(calc:HasSecretValues()))
		local ok1, amt, clamped = pcall(calc.GetDamageAbsorbs, calc)
		log("  GetDamageAbsorbs %s / clamped %s  GetTotalDamageAbsorbs %s  GetMaximumHealth %s  GetMaximumDamageAbsorbs %s",
			ok1 and S(amt) or "ERR", ok1 and S(clamped) or "ERR", S(select(2, pcall(calc.GetTotalDamageAbsorbs, calc))),
			S(select(2, pcall(calc.GetMaximumHealth, calc))), S(select(2, pcall(calc.GetMaximumDamageAbsorbs, calc))))
		pcall(calc.SetMaximumHealthMode, calc, Enum.UnitMaximumHealthMode and Enum.UnitMaximumHealthMode.WithAbsorbs or 1)
		pcall(UnitGetDetailedHealPrediction, "player", "player", calc)
		log("  WithAbsorbs: GetMaximumHealth %s  GetMissingHealthPercent %s", S(select(2, pcall(calc.GetMaximumHealth, calc))),
			S(select(2, pcall(calc.GetMissingHealthPercent, calc))))
	else
		log("CreateUnitHealPredictionCalculator -> %s", S(calc))
	end
	AuraLines()
	-- never-secret flags and the by-spell getters (the only aura getters without RequiresUnitAuraAccess)
	local secrecy, found = {}, {}
	for _, id in ipairs(SHIELD_IDS) do
		local okS, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, id)
		local k = okS and (SECRECY[lvl] or S(lvl)) or "ERR"
		secrecy[k] = (secrecy[k] or 0) + 1
		local okG, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if okG and issecretvalue(aura) then
			found[#found + 1] = ("%d(<secret aura>)"):format(id)
		elseif okG and aura ~= nil then
			local p1 = (type(aura) == "table" and not issecretvalue(aura) and type(aura.points) == "table") and S(aura.points[1]) or "?"
			found[#found + 1] = ("%d(points1=%s)"):format(id, p1)
		elseif not okG then
			found[#found + 1] = ("%d ERROR %s"):format(id, S(aura))
		end
	end
	local parts = {}
	for k, n in pairs(secrecy) do parts[#parts + 1] = k .. "=" .. n end
	log("GetSpellAuraSecrecy over %d shield ids: %s", #SHIELD_IDS, table.concat(parts, " "))
	log("GetPlayerAuraBySpellID hits: %s", #found > 0 and table.concat(found, " ") or "none")
	BuildPanel()
	Refresh("report")
end

---------------------------------------------------------------------------- watch
local function Watch()
	P.watchFrame = P.watchFrame or CreateFrame("Frame")
	local w = P.watchFrame
	w:UnregisterAllEvents()
	w:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
	w:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player")
	w:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
	w:RegisterUnitEvent("UNIT_AURA", "player")
	w:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
	w:RegisterEvent("PLAYER_REGEN_DISABLED")
	w:RegisterEvent("PLAYER_REGEN_ENABLED")
	local t0 = GetTime()
	P.watching = true
	w:SetScript("OnEvent", function(_, event, unit, a2, a3)
		if not P.watching then return end
		local t = GetTime() - t0
		if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
			local a = UnitGetTotalAbsorbs("player")
			if P.armed and GetTime() < P.armed then
				P.full, P.fullKind, P.armed = a, "secret", nil         -- store the secret; never look at it
				log("%6.2f snapshot taken after own shield cast -> bar B max = %s", t, S(a))
			end
			log("%6.2f ABSORB_CHANGED combat=%s value=%s", t, S(InCombatLockdown()), S(a))
			Refresh(event)
		elseif event == "UNIT_AURA" then
			local info = a2
			if info == nil then log("%6.2f UNIT_AURA no updateInfo", t); return end
			if issecretvalue(info) then log("%6.2f UNIT_AURA updateInfo=<secret>", t); return end
			local function each(list, tag)
				if list == nil then return end
				if issecretvalue(list) then log("%6.2f UNIT_AURA %s=<secret>", t, tag); return end
				for _, x in ipairs(list) do
					local d, err = x, nil
					if issecretvalue(x) then
						d, err = nil, "<secret element>"
					elseif type(x) ~= "table" then
						local ok, dd = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", x)
						if ok then d = dd else d, err = nil, "ERROR " .. S(dd) end
					end
					if issecretvalue(d) then
						log("%6.2f UNIT_AURA %s <secret aura>", t, tag)
					elseif d == nil then
						log("%6.2f UNIT_AURA %s inst=%s data=nil %s", t, tag, S(x), err or "")
					else
						local p = nil
						if type(d.points) == "table" and not issecretvalue(d.points) then p = d.points[1] end
						local shield = not issecretvalue(d.spellId) and IS_SHIELD[d.spellId]
						if issecretvalue(d.spellId) or issecretvalue(d.points) then
							log("%6.2f UNIT_AURA %s spellId %s points %s", t, tag, S(d.spellId), S(d.points))
						elseif issecretvalue(p) or p ~= nil or shield then
							log("%6.2f UNIT_AURA %s %s %s points1=%s dur=%s", t, tag, S(d.spellId), S(d.name), S(p), S(d.duration))
						end
					end
				end
			end
			each(info.addedAuras, "added")
			each(info.updatedAuraInstanceIDs, "updated")
			if info.removedAuraInstanceIDs and not issecretvalue(info.removedAuraInstanceIDs) and #info.removedAuraInstanceIDs > 0 then
				log("%6.2f UNIT_AURA removed %d", t, #info.removedAuraInstanceIDs)
			end
		elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
			local id = a3
			if issecretvalue(id) then log("%6.2f CAST %s <secret id>", t, S(unit)); return end
			if IS_SHIELD[id] then
				local okN, nm = pcall(C_Spell.GetSpellName, id)
				log("%6.2f CAST %s %d %s (shield: snapshot armed 1 s)", t, S(unit), id, okN and S(nm) or "?")
				P.armed = GetTime() + 1
			end
		elseif event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" or event == "UNIT_MAXHEALTH" then
			log("%6.2f %s", t, event)
			Refresh(event)
		else
			log("%6.2f %s", t, event == "PLAYER_REGEN_DISABLED" and "COMBAT START" or "COMBAT END")
			Refresh(event)
		end
	end)
	log("watching 120 s")
	C_Timer.After(120, function() if P.watching then P.watching = false; log("watch done (120 s)") end end)
end

SLASH_FDABSPROBE1 = "/fdabs"
SlashCmdList["FDABSPROBE"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "hide" then
		P.watching = false
		if P.panel then P.panel:Hide() end
		return
	elseif msg == "watch" then
		BuildPanel(); Refresh("watch"); Watch()
		return
	end
	local n = msg:match("^full%s+(%d+)$")
	if n then
		P.full, P.fullKind = tonumber(n), "plain"
		log("bar B full size = %d (plain)", P.full)
		BuildPanel(); Refresh("full")
		return
	end
	Report()
end
