--[[ Forever Dev Info - /fddispel: can Blizzard's aura containers pick auras by DISPEL TYPE, by "stealable"
     and by the RAID filter tokens, also for debuffs on YOU, also in combat?

     Why: Blizzard refuses to pick debuffs on friendly units by spell ID while auras are secret (the identity
     rule, AuraContainerUtil.CanApplyIdentityCandidateFilters), but that rule guards only includeSpellIDs /
     excludeSpellIDs. includeDispelTypes / excludeDispelTypes / isStealable are applied to every aura, and
     filter strings like "HARMFUL|RAID" (debuffs YOU can dispel) are not candidate filters at all.

     Two rows of engine-drawn slots, each with a grey square underneath (= nothing matched) and a label:
       row 1, you:    A Magic debuff   B Curse debuff   C Poison debuff   D Disease debuff
                      E debuff you can dispel (HARMFUL|RAID)   F debuff without a type   G any debuff
                      H Magic buff (e.g. Demon Skin: always there, so the in-combat check)
       row 2, target: I Magic buff (purgeable)   J stealable buff   K buff the raid can dispel
                      L any buff   M debuff you can dispel   N Magic debuff
     A slot shows the aura's own icon and time left when something matches.

     /fddispel        build (works in combat too), and out of combat also log what is on you and the target
     /fddispel dump   log the plain aura data of you and your target (out of combat): dispelName, isStealable...
     /fddispel hide   remove
     Log: ForeverDevInfoDB.dispelProbe
]]

local dp = {}
local SIZE, GAP, LABEL_H = 36, 44, 30

local function dlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.dispelProbe = ForeverDevInfoDB.dispelProbe or {}
	local l = ForeverDevInfoDB.dispelProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI dispel|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	if type(v) == "string" then return ("%q"):format(v) end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function dtry(label, fn, ...)
	local ok, res = pcall(fn, ...)
	dlog("%s -> %s", label, ok and "ok" or ("ERROR: " .. show(res)))
	return ok, res
end

local ALL_TYPES = { Magic = true, Curse = true, Poison = true, Disease = true, Enrage = true, Bleed = true, [""] = true }

local SLOTS = {
	{ row = 1, key = "A", unit = "player", filter = "HARMFUL", cf = { includeDispelTypes = { Magic = true } }, text = "A you: Magic debuff" },
	{ row = 1, key = "B", unit = "player", filter = "HARMFUL", cf = { includeDispelTypes = { Curse = true } }, text = "B you: Curse debuff" },
	{ row = 1, key = "C", unit = "player", filter = "HARMFUL", cf = { includeDispelTypes = { Poison = true } }, text = "C you: Poison debuff" },
	{ row = 1, key = "D", unit = "player", filter = "HARMFUL", cf = { includeDispelTypes = { Disease = true } }, text = "D you: Disease debuff" },
	{ row = 1, key = "E", unit = "player", filter = "HARMFUL|RAID", cf = nil, text = "E you: debuff you can dispel" },
	{ row = 1, key = "F", unit = "player", filter = "HARMFUL", cf = { excludeDispelTypes = ALL_TYPES }, text = "F you: debuff, no type" },
	{ row = 1, key = "G", unit = "player", filter = "HARMFUL", cf = nil, text = "G you: any debuff" },
	{ row = 1, key = "H", unit = "player", filter = "HELPFUL", cf = { includeDispelTypes = { Magic = true } }, text = "H you: Magic buff" },
	{ row = 2, key = "I", unit = "target", filter = "HELPFUL", cf = { includeDispelTypes = { Magic = true } }, text = "I target: Magic buff (purge)" },
	{ row = 2, key = "J", unit = "target", filter = "HELPFUL", cf = { isStealable = true }, text = "J target: stealable buff" },
	{ row = 2, key = "K", unit = "target", filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", cf = nil, text = "K target: buff raid can dispel" },
	{ row = 2, key = "L", unit = "target", filter = "HELPFUL", cf = nil, text = "L target: any buff" },
	{ row = 2, key = "M", unit = "target", filter = "HARMFUL|RAID", cf = nil, text = "M target: debuff you can dispel" },
	{ row = 2, key = "N", unit = "target", filter = "HARMFUL", cf = { includeDispelTypes = { Magic = true } }, text = "N target: Magic debuff" },
}

local FILTER_STRINGS = { "HARMFUL", "HELPFUL", "HARMFUL|RAID", "HELPFUL|RAID", "HELPFUL|RAID_PLAYER_DISPELLABLE",
	"HARMFUL|DISPELLABLE", "HELPFUL|DISPELLABLE", "HARMFUL|RAID_PLAYER_DISPELLABLE" }

local function dump()
	if InCombatLockdown() then dlog("dump: in combat aura data is secret - run it out of combat"); return end
	for _, unit in ipairs({ "player", "target" }) do
		if UnitExists(unit) then
			for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
				local n = 0
				for i = 1, 40 do
					local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
					if not ok or type(a) ~= "table" then break end
					n = n + 1
					dlog("  %s %s #%d %s (%s) dispelName=%s isStealable=%s fromPlayer=%s boss=%s duration=%s",
						unit, filter, i, show(a.name), show(a.spellId), show(a.dispelName), show(a.isStealable),
						show(a.isFromPlayerOrPlayerPet), show(a.isBossAura), show(a.duration))
				end
				-- which of the RAID-style tokens pass for these auras (plain out of combat)
				for _, extra in ipairs({ "RAID", "DISPELLABLE", "RAID_PLAYER_DISPELLABLE" }) do
					local names = {}
					for i = 1, 40 do
						local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter .. "|" .. extra)
						if not ok or type(a) ~= "table" then break end
						names[#names + 1] = show(a.name)
					end
					if #names > 0 then dlog("  %s %s|%s: %s", unit, filter, extra, table.concat(names, ", ")) end
				end
				if n == 0 then dlog("  %s %s: none", unit, filter) end
			end
		else
			dlog("  %s: none", unit)
		end
	end
end

local function hide()
	if not dp.host then dlog("nothing to hide"); return end
	for _, c in pairs(dp.containers or {}) do pcall(c.SetEnabled, c, false) end
	dp.host:Hide()
	if dp.events then dp.events:UnregisterAllEvents() end
	dp.host, dp.containers = nil, nil
	dlog("removed")
end

local function build()
	if dp.host then dlog("already built - /fddispel hide first"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	dlog("[run] combat=%s ShouldAurasBeSecret=%s", tostring(InCombatLockdown()),
		show(C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()))
	for _, fs in ipairs(FILTER_STRINGS) do
		local ok, valid = pcall(AuraUtil.IsValidFilterString, fs)
		dlog("filter %s valid=%s", fs, ok and show(valid) or ("ERROR " .. show(valid)))
	end

	local host = CreateFrame("Frame", "FDIDispelHost", UIParent)
	host:SetSize(8 * (SIZE + GAP), 2 * (SIZE + LABEL_H + 16))
	host:SetPoint("CENTER", UIParent, "CENTER", 0, 230)
	dp.host = host
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	cap:SetPoint("BOTTOM", host, "TOP", 0, 4)
	cap:SetText("dispel probe: grey = nothing matched, an icon = the engine found a matching aura")

	dp.containers = {}
	for _, unit in ipairs({ "player", "target" }) do
		local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
		if not ok or not c then dlog("container %s -> ERROR %s", unit, show(c)); return end
		c:SetPoint("TOPLEFT", host, "TOPLEFT")
		c:SetSize(1, 1)
		dtry("SetUnit(" .. unit .. ")", c.SetUnit, c, unit)
		dp.containers[unit] = c
	end

	local col = { 0, 0 }
	for _, s in ipairs(SLOTS) do
		col[s.row] = col[s.row] + 1
		local cell = CreateFrame("Frame", nil, host)
		cell:SetSize(SIZE, SIZE)
		cell:SetPoint("TOPLEFT", host, "TOPLEFT", (col[s.row] - 1) * (SIZE + GAP) + GAP / 2, -(s.row - 1) * (SIZE + LABEL_H + 16))
		local grey = cell:CreateTexture(nil, "BACKGROUND")
		grey:SetAllPoints(cell)
		grey:SetColorTexture(0.3, 0.3, 0.3, 0.6)
		local label = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOP", cell, "BOTTOM", 0, -2)
		label:SetWidth(SIZE + GAP - 4)
		label:SetText(s.text)

		local c = dp.containers[s.unit]
		local desc = {
			initializeFrame = function(b)
				b:ClearAllPoints()
				b:SetAllPoints(cell)
				local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
				local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal"); fs:SetPoint("CENTER", b, "CENTER")
				pcall(b.SetIcon, b, icon)
				pcall(b.SetDurationText, b, fs, nil)
			end,
		}
		if s.cf then desc.candidateFilters = s.cf end
		dtry(("slot %s %s %s"):format(s.key, s.unit, s.filter), c.AddAuraSlot, c, s.key, s.filter, desc)
	end

	dp.events = dp.events or CreateFrame("Frame")
	dp.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	dp.events:SetScript("OnEvent", function()
		local c = dp.containers and dp.containers.target
		if c then
			local ok, err = pcall(c.UpdateAllAuras, c)
			if not ok then dlog("target UpdateAllAuras -> ERROR %s (combat=%s)", show(err), tostring(InCombatLockdown())) end
		end
	end)
	for _, c in pairs(dp.containers) do pcall(c.UpdateAllAuras, c) end
	dlog("built. Compare the icons with what you know is on you and your target, in and out of combat.")
	if not InCombatLockdown() then dump() end
end

SLASH_FOREVERDEVDISPEL1 = "/fddispel"
SlashCmdList["FOREVERDEVDISPEL"] = function(msg)
	msg = (msg or ""):lower():match("%a*")
	if msg == "hide" then hide()
	elseif msg == "dump" then dump()
	else build() end
end
