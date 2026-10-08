--[[ Forever Dev Info - /fdtgate [seconds]: can a frame open and close by an aura's TIME LEFT, per aura, in combat?

     The idea (a "text-width gate"): every aura button may carry one duration text, and the game formats it
     itself, also in combat. A NumericRuleFormatter picks its format by the value, so the text can be WIDE below
     X seconds ("WWWWWWWWWWWWWW5") and narrow above ("12"). A font string with a single anchor is as wide as its
     text, and a clip frame of ours hangs on its right edge:

       red  clip from the icon's top-left to the text's right edge: open only while the text is wide
            (time left < X): a red tint and EverAuras' animated Pixel glow
       blue clip from the text's right edge to the icon's top-right: open only while the text is narrow
            (time left >= X): a small blue square in the icon's top-right corner

     This needs no total duration (bars do), so it works for every aura of a sorted row, whatever its length.
     Two rows of your own debuffs on the target, sorted least time left first, above the middle of the screen:

       A  the formatter given as textFormatter
       B  the formatter given inside textFormat ({} + RemainingDuration)

       C  no gate: an always-on Pixel glow on a frame INSIDE each aura button (does it move there?)

     The small grey text left of each icon is the gate text itself (normally invisible).
     Put DoTs on a target, out of combat and in a fight: above X the blue square, below X red + a moving glow.
     Errors go to ForeverDevInfoDB.timeGateProbe. /fdtgate hide removes it.
]]

local tg = {}
local SIZE, GAP, M, SHIFT = 36, 8, 6, 30
local WIDE = "WWWWWWWWWWWWWW"

local function tlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.timeGateProbe = ForeverDevInfoDB.timeGateProbe or {}
	local l = ForeverDevInfoDB.timeGateProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI tgate|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function Formatter(x)
	local R = (Enum and Enum.NumericRuleFormatRounding) or {}
	local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not f then return nil, "CreateNumericRuleFormatter: " .. show(f) end
	local okB, err = pcall(f.SetBreakpoints, f, {
		{ threshold = 0, step = 1, rounding = R.Down or 2, format = WIDE .. "%d" },
		{ threshold = x, step = 1, rounding = R.Down or 2, format = "%d" },
	})
	if not okB then return nil, "SetBreakpoints: " .. show(err) end
	return f
end

-- Row C: no gate, EverAuras' Pixel glow on a frame INSIDE each aura button, always on. Aura buttons stop every
-- script of their children (forbidden aspect UntrustedScriptExecution); the glow is made of animations only,
-- so it may still move there. Moving = sorted rows can get animated glows of their own.
local function rowInside(index, caption)
	local host = CreateFrame("Frame", nil, tg.root, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(5 * (SIZE + GAP), SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", -2 * (SIZE + GAP), 300 - (index - 1) * (SIZE + 40))
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("RIGHT", host, "LEFT", -40, 0)
	cap:SetText(caption)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then tlog("%s container -> ERROR %s", caption, show(c)); return host end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	pcall(c.SetUnit, c, "target")
	local FG = (_G.EverAuras or {}).ForeverGlow
	local reported = false
	local M2, D2 = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, err = pcall(c.AddAuraGroup, c, "inside", "HARMFUL|PLAYER", {
		maxFrameCount = 5,
		sortMethod = M2 and M2.ExpirationOnly,
		sortDirection = D2 and D2.Normal,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = function(b)
			b:SetSize(SIZE, SIZE)
			pcall(b.SetMouseClickEnabled, b, false)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			pcall(b.SetIcon, b, icon)
			local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("CENTER")
			pcall(b.SetDurationText, b, fs, nil)
			local holder = CreateFrame("Frame", nil, b)
			holder:SetAllPoints(b)
			holder:SetFrameLevel(b:GetFrameLevel() + 5)
			if FG then
				local okS, res = pcall(FG.Start, holder, { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25,
					glowLength = 10, glowThickness = 2, glowXOffset = 0, glowYOffset = 0, glowBorder = true }, SIZE, SIZE)
				if (not okS or not res) and not reported then reported = true; tlog("%s: ForeverGlow.Start -> ERROR %s", caption, show(res)) end
			end
		end,
	})
	tlog("%s AddAuraGroup -> %s", caption, okG and "ok" or ("ERROR " .. show(err)))
	tg.containers[#tg.containers + 1] = c
	return host
end

local function row(index, caption, x, how)
	local host = CreateFrame("Frame", nil, tg.root, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(5 * (SIZE + GAP), SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", -2 * (SIZE + GAP), 300 - (index - 1) * (SIZE + 40))
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("RIGHT", host, "LEFT", -40, 0)
	cap:SetText(caption)
	local f, why = Formatter(x)
	if not f then tlog("%s: formatter failed: %s", caption, why); return host end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then tlog("%s container -> ERROR %s", caption, show(c)); return host end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	pcall(c.SetUnit, c, "target")
	local P = (Enum and Enum.DurationTextBindingProperty) or {}
	local FG = (_G.EverAuras or {}).ForeverGlow
	local reported, frames = false, 0
	local function fail(what, err)
		if not reported then reported = true; tlog("%s frame: %s -> ERROR %s", caption, what, show(err)) end
	end
	local M2, D2 = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, err = pcall(c.AddAuraGroup, c, "tgate", "HARMFUL|PLAYER", {
		maxFrameCount = 5,
		sortMethod = M2 and M2.ExpirationOnly,
		sortDirection = D2 and D2.Normal,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = function(b)
			frames = frames + 1
			b:SetSize(SIZE, SIZE)
			pcall(b.SetMouseClickEnabled, b, false)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			pcall(b.SetIcon, b, icon)
			local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
			cd:SetAllPoints(b)
			pcall(cd.SetDrawBling, cd, false)
			pcall(b.SetDurationCooldown, b, cd)
			-- the gate text: one anchor, so it is as wide as its text
			local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -M - SHIFT, -M)
			fs:SetTextColor(0.75, 0.75, 0.75, 0.8)
			local opts
			if how == "formatter" then
				opts = { textFormatter = f }
			else
				opts = { textFormat = { formatString = "{}", components = { { property = P.RemainingDuration or 0, formatter = f } } } }
			end
			local okT, errT = pcall(b.SetDurationText, b, fs, opts)
			if not okT then fail("SetDurationText", errT) end
			-- red: open while the text is wide (time left < X)
			local late = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
			late:SetClipsChildren(true)
			local okA, errA = pcall(function()
				late:SetPoint("TOPLEFT", b, "TOPLEFT", -M, M)
				late:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, 0)
			end)
			if not okA then fail("anchor red clip", errA) end
			late:SetFrameLevel(host:GetFrameLevel() + 40)
			local holder = CreateFrame("Frame", nil, late, "DisableUntrustedLayoutScriptsTemplate")
			local okH, errH = pcall(holder.SetAllPoints, holder, b)
			if not okH then fail("anchor glow holder", errH) end
			local tint = holder:CreateTexture(nil, "OVERLAY")
			tint:SetAllPoints(holder)
			tint:SetColorTexture(1, 0, 0, 0.35)
			if FG then
				local okS, res = pcall(FG.Start, holder, { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25,
					glowLength = 10, glowThickness = 2, glowXOffset = 0, glowYOffset = 0, glowBorder = true }, SIZE, SIZE)
				if not okS or not res then fail("ForeverGlow.Start", res) end
			end
			-- blue: open while the text is narrow (time left >= X)
			local early = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
			early:SetClipsChildren(true)
			local okE, errE = pcall(function()
				early:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 0, 0)
				early:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
			end)
			if not okE then fail("anchor blue clip", errE) end
			early:SetFrameLevel(host:GetFrameLevel() + 40)
			local dot = CreateFrame("Frame", nil, early, "DisableUntrustedLayoutScriptsTemplate")
			local okD, errD = pcall(function()
				dot:SetSize(10, 10)
				dot:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
			end)
			if not okD then fail("anchor blue square", errD) end
			local sq = dot:CreateTexture(nil, "OVERLAY")
			sq:SetAllPoints(dot)
			sq:SetColorTexture(0.2, 0.5, 1, 1)
		end,
	})
	tlog("%s AddAuraGroup -> %s (glow: %s)", caption, okG and "ok" or ("ERROR " .. show(err)), FG and "EverAuras' ForeverGlow" or "not found, tint only")
	tg.containers[#tg.containers + 1] = c
	return host
end

local function build(x)
	if tg.root then tlog("already built - /fdtgate hide first"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then tlog("C_StringUtil.CreateNumericRuleFormatter is missing"); return end
	tg.root = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
	tg.root:SetAllPoints(UIParent)
	tg.containers = {}
	tlog("[run] X = %s s, combat = %s", show(x), show(InCombatLockdown()))
	row(1, "A: textFormatter", x, "formatter")
	row(2, "B: textFormat {}", x, "format")
	rowInside(3, "C: glow inside")
	tg.events = tg.events or CreateFrame("Frame")
	tg.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	tg.events:SetScript("OnEvent", function()
		for _, c in ipairs(tg.containers or {}) do pcall(c.UpdateAllAuras, c) end
	end)
	tlog("Put DoTs on a target: above %s s a blue square, below it red + a moving glow, per icon, also in combat. /fdtgate hide removes it.", show(x))
end

SLASH_FDITGATE1 = "/fdtgate"
SlashCmdList.FDITGATE = function(msg)
	msg = strtrim(msg or "")
	if msg == "hide" then
		if tg.root then tg.root:Hide() end
		if tg.events then tg.events:UnregisterAllEvents() end
		tg.root, tg.containers = nil, nil
		tlog("removed")
		return
	end
	build(tonumber(msg) or 6)
end
