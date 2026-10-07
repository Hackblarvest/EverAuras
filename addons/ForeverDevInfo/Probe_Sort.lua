--[[ Forever Dev Info - /fdsort: can the game keep a row of auras SORTED BY TIME LEFT, also in combat?

     CustomAuraContainer:AddAuraGroup takes a sortMethod (AuraContainerSortMethod) and a sortDirection.
     ExpirationOnly orders the group's auras by expiration time (Blizzard_FrameXMLUtil/AuraUtil.lua); the
     comparison runs inside Blizzard's own aura update, where the secret times may be compared. Three rows
     of your DoTs on the target (Corruption, Immolate, Curse/Bane of Agony), above the middle of the screen:

       A  ExpirationOnly, Normal   the DoT with the LEAST time left first (left)
       B  ExpirationOnly, Reverse  the DoT with the MOST time left first
       C  Default                  as the game picks without a time order (for comparison)

     Put two or three DoTs on a target, out of combat first and then in a fight, and check that rows A and B
     reorder themselves when you refresh one. Errors go to ForeverDevInfoDB.sortProbe. /fdsort hide removes it.
]]

local sp = {}
local IDS = {
	172, 6222, 6223, 7648, 11671, 11672, 25311, 27216,          -- Corruption
	348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 27215,    -- Immolate
	980, 1014, 6217, 11711, 11712, 11713, 27218,                -- Curse / Bane of Agony
}
local SIZE, GAP = 36, 4

local function slog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.sortProbe = ForeverDevInfoDB.sortProbe or {}
	local l = ForeverDevInfoDB.sortProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI sort|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function row(index, caption, sortMethod, sortDirection)
	local host = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(4 * (SIZE + GAP), SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", -2 * (SIZE + GAP), 300 - (index - 1) * (SIZE + 30))
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("RIGHT", host, "LEFT", -8, 0)
	cap:SetText(caption)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then slog("%s container -> ERROR %s", caption, show(c)); return host end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	pcall(c.SetUnit, c, "target")
	local set = {}
	for _, id in ipairs(IDS) do set[id] = true end
	local okG, err = pcall(c.AddAuraGroup, c, "sort", "HARMFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = set },
		maxFrameCount = 6,
		sortMethod = sortMethod,
		sortDirection = sortDirection,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = function(b)
			b:SetSize(SIZE, SIZE)
			pcall(b.SetMouseClickEnabled, b, false)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("CENTER")
			pcall(b.SetIcon, b, icon)
			pcall(b.SetDurationText, b, fs, nil)
		end,
	})
	slog("%s AddAuraGroup(sortMethod %s, direction %s) -> %s", caption, show(sortMethod), show(sortDirection), okG and "ok" or ("ERROR " .. show(err)))
	sp.containers[#sp.containers + 1] = c
	return host
end

local function build()
	if sp.hosts then slog("already built - /fdsort hide first"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local M, D = AuraContainerSortMethod, AuraContainerSortDirection
	if not (M and D) then slog("AuraContainerSortMethod / AuraContainerSortDirection are missing"); return end
	slog("[run] sort methods: ExpirationOnly = %s, Default = %s; directions: Normal = %s, Reverse = %s; combat = %s",
		show(M.ExpirationOnly), show(M.Default), show(D.Normal), show(D.Reverse), show(InCombatLockdown()))
	sp.hosts, sp.containers = {}, {}
	sp.hosts[1] = row(1, "A: least time left first", M.ExpirationOnly, D.Normal)
	sp.hosts[2] = row(2, "B: most time left first", M.ExpirationOnly, D.Reverse)
	sp.hosts[3] = row(3, "C: no time order", M.Default, D.Normal)
	-- the containers do not notice that "target" means another unit: refresh them on a new target
	sp.events = sp.events or CreateFrame("Frame")
	sp.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	sp.events:SetScript("OnEvent", function()
		for _, c in ipairs(sp.containers or {}) do pcall(c.UpdateAllAuras, c) end
	end)
	slog("Put two or three DoTs on a target. A and B must reorder when you refresh one, also in combat. /fdsort hide removes it.")
end

SLASH_FDISORT1 = "/fdsort"
SlashCmdList.FDISORT = function(msg)
	msg = strtrim(msg or "")
	if msg == "hide" then
		for _, h in ipairs(sp.hosts or {}) do h:Hide() end
		if sp.events then sp.events:UnregisterAllEvents() end
		sp.hosts, sp.containers = nil, nil
		slog("removed")
		return
	end
	build()
end
