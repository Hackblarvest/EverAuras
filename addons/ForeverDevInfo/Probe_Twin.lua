--[[ Forever Dev Info - /fdtwin: do two aura groups with the same filter and sort put the same aura in the same
     place, so a second, invisible row can carry the time gates of the first?

     A sorted row's frame has one duration text. EverAuras' sorted rows use it either for a %p text or for the
     time gate that turns the icon red and glowing below X seconds, not both. The idea: a twin row of the same
     auras, sorted the same way and laid out on the same spot, whose frames carry the gates (and a red colour
     multiplied over the row below), while the visible row keeps its %p.

       visible row  icon + the game's countdown text (its duration text)
       twin row     on top, the same size: a SMALL icon ABOVE each frame (which aura the twin frame holds),
                    and a red colour over the frame below 3 s left (the twin frame's duration text is the gate)

     Put three or four DoTs on a target (also two at nearly the same time, refresh one, change targets, out of
     combat and in a fight). Each small icon must match the icon under it, and only the icon with less than 3 s
     left must turn red, with its countdown still readable. Lines go to ForeverDevInfoDB.twinProbe.
     /fdtwin hide removes it.
]]

local tp = {}
local IDS = {
	980, 1014, 6217, 11711, 11712, 11713,                  -- Bane of Agony
	603, 1225228, 1243338, 1243339,                        -- Bane of Doom, Bane of Havoc
	172, 6222, 6223, 7648, 11671, 11672, 25311,            -- Corruption
	348, 707, 1094, 2941, 11665, 11667, 11668, 25309,      -- Immolate
	18265, 18879, 18880, 18881, 1242957,                   -- Siphon Life
	440892, 1311676, 1311677, 1311680,                     -- Curse of the Elements
	704, 7658, 7659, 11717, 702, 1108, 6205, 7646, 11707, 11708, 1714, 11719, 18223,   -- other curses
}
local SIZE, GAP, MAX = 40, 4, 8
local X = 3                 -- seconds: the gate's threshold
local SHIFT = 80            -- the gate text starts this far left of its frame (EverAuras' Dyn.GATE_SHIFT)

local function tlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.twinProbe = ForeverDevInfoDB.twinProbe or {}
	local l = ForeverDevInfoDB.twinProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI twin|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

-- wide ("WWW..") below X seconds, just the number from X up: the gate text's end passes the frame only below X
local function GateFormatter()
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
	local R = (Enum and Enum.NumericRuleFormatRounding) or {}
	local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not f then return nil end
	local wide = string.rep("W", math.ceil((SHIFT + SIZE + 30) / 8))
	local okB = pcall(f.SetBreakpoints, f, {
		{ threshold = 0, step = 1, rounding = R.Down or 2, format = wide .. "%d" },
		{ threshold = X, step = 1, rounding = R.Down or 2, format = "%d" },
	})
	return okB and f or nil
end

local function container(parent, key, level, init)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not c then tlog("%s container -> ERROR %s", key, show(c)); return nil end
	c:SetPoint("TOPLEFT", parent, "TOPLEFT")
	pcall(c.SetFrameLevel, c, level)
	pcall(c.SetUnit, c, "target")
	local set = {}
	for _, id in ipairs(IDS) do set[id] = true end
	local M, D = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, err = pcall(c.AddAuraGroup, c, key, "HARMFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = set },
		maxFrameCount = MAX,
		sortMethod = M and M.ExpirationOnly,
		sortDirection = D and D.Normal,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = init,
	})
	tlog("%s AddAuraGroup -> %s", key, okG and "ok" or ("ERROR " .. show(err)))
	tp.containers[#tp.containers + 1] = c
	return c
end

local function build()
	if tp.host then tlog("already built - /fdtwin hide first"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local fmt = GateFormatter()
	tlog("[run] combat = %s, gate formatter = %s, sort ExpirationOnly = %s", show(InCombatLockdown()), fmt and "ok" or "MISSING",
		show(AuraContainerSortMethod and AuraContainerSortMethod.ExpirationOnly))
	tp.containers = {}
	local host = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(MAX * (SIZE + GAP), SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", -2 * (SIZE + GAP), 260)
	tp.host = host
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 26)
	cap:SetText("/fdtwin: small icons = the twin row, red below " .. X .. " s")

	-- the visible row: icon and the game's countdown (its duration text)
	container(host, "visible", host:GetFrameLevel() + 2, function(b)
		b:SetSize(SIZE, SIZE)
		pcall(b.SetMouseClickEnabled, b, false)
		local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); fs:SetPoint("CENTER")
		pcall(b.SetIcon, b, icon)
		pcall(b.SetDurationText, b, fs, nil)
	end)

	-- the twin row on top: a small icon above the frame, the gate, and red multiplied over the frame below X
	local n = 0
	container(host, "twin", host:GetFrameLevel() + 6, function(b)
		n = n + 1
		b:SetSize(SIZE, SIZE)
		pcall(b.SetMouseClickEnabled, b, false)
		pcall(b.EnableMouseMotion, b, false)
		local mini = b:CreateTexture(nil, "ARTWORK")
		mini:SetSize(18, 18)
		mini:SetPoint("BOTTOM", b, "TOP", 0, 3)
		pcall(b.SetIcon, b, mini)
		if not fmt then return end
		local gate = b:CreateFontString(nil, "BACKGROUND", "GameFontHighlight")
		gate:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -SHIFT, 0)
		gate:SetTextColor(1, 1, 1, 0)
		local okD, errD = pcall(b.SetDurationText, b, gate, { textFormatter = fmt })
		if not okD then tlog("twin frame %d: SetDurationText(gate) -> ERROR %s", n, show(errD)); return end
		local late = CreateFrame("Frame", nil, b)
		late:SetClipsChildren(true)
		late:SetFrameLevel(b:GetFrameLevel() + 1)
		late:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
		late:SetPoint("BOTTOMRIGHT", gate, "BOTTOMRIGHT", 0, 0)
		local red = late:CreateTexture(nil, "ARTWORK")
		red:SetPoint("TOPLEFT", b, "TOPLEFT")
		red:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
		red:SetColorTexture(1, 0.35, 0.35, 1)
		local okM = pcall(red.SetBlendMode, red, "MOD")
		if n == 1 then tlog("twin frames: gate ok, red overlay blend MOD -> %s", okM and "ok" or "ERROR") end
	end)

	-- the containers do not notice that "target" means another unit: refresh them on a new target
	tp.events = tp.events or CreateFrame("Frame")
	tp.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	tp.events:SetScript("OnEvent", function()
		for _, c in ipairs(tp.containers or {}) do pcall(c.UpdateAllAuras, c) end
	end)
	tlog("Put three or four DoTs on a target. Each small icon must match the icon under it; only the one below %d s turns red. /fdtwin hide removes it.", X)
end

SLASH_FDITWIN1 = "/fdtwin"
SlashCmdList.FDITWIN = function(msg)
	msg = strtrim(msg or "")
	if msg == "hide" then
		if tp.host then tp.host:Hide() end
		for _, c in ipairs(tp.containers or {}) do pcall(c.SetUnit, c, nil) end
		if tp.events then tp.events:UnregisterAllEvents() end
		tp.host, tp.containers = nil, nil
		tlog("removed")
		return
	end
	build()
end
