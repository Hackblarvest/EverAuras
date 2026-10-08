--[[ Forever Dev Info - /fdtgate [seconds]: can a frame open and close by an aura's TIME LEFT, per aura, in combat?

     The idea (a "text-width gate"): every aura button may carry one duration text, and the game formats it
     itself, also in combat. A NumericRuleFormatter picks its format by the value, so the text can be WIDE below
     X seconds ("WWWWWWWWWWWWWW5") and narrow above ("12"). A font string with a single anchor is as wide as its
     text, and a clip frame of ours hangs on its right edge. Round 1 (2026-10-08): the text changed as planned
     (both ways of giving the formatter), but nothing anchored to it showed. Round 2 tells the causes apart.
     Rows of your own debuffs on the target, sorted least time left first, above the middle of the screen:

       A  the gate. GREEN dot: hangs on the gate text's right end, always (does it follow the text?).
          RED: a clip from the icon's top-left to the text's right end, filled red (open below X).
          BLUE: a clip from the text's right end to the icon's top-right, filled blue (open from X up).
          Inside the red clip also EverAuras' Pixel glow, around the icon.
       B  no gate text: YELLOW = a clip hung on the icon's corners, filled yellow (always open);
          CYAN = a small square of ours hung on the icon's centre (no clip). Do frames of ours that hang on
          an aura button show at all?
       C  an always-on Pixel glow on a frame INSIDE each aura button: do its lines move there?

     The small grey text left of row A's icons is the gate text itself (normally invisible).
     /fdtgate dump prints what the game tells about row A's first frame (best out of combat, DoTs up).
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

local function Box(parent, r, g, b, a)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetColorTexture(r, g, b, a)
	return t
end

local function Frame(parent)
	return CreateFrame("Frame", nil, parent, "DisableUntrustedLayoutScriptsTemplate")
end

local function NewRow(index, caption)
	local host = Frame(tg.root)
	host:SetSize(5 * (SIZE + GAP), SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", -2 * (SIZE + GAP), 300 - (index - 1) * (SIZE + 40))
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("RIGHT", host, "LEFT", -40, 0)
	cap:SetText(caption)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then tlog("%s container -> ERROR %s", caption, show(c)); return host end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	pcall(c.SetUnit, c, "target")
	return host, c
end

local function AddGroup(c, caption, init)
	local M2, D2 = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, err = pcall(c.AddAuraGroup, c, "tgate", "HARMFUL|PLAYER", {
		maxFrameCount = 5,
		sortMethod = M2 and M2.ExpirationOnly,
		sortDirection = D2 and D2.Normal,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = function(b)
			b:SetSize(SIZE, SIZE)
			pcall(b.SetMouseClickEnabled, b, false)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			pcall(b.SetIcon, b, icon)
			local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
			cd:SetAllPoints(b)
			pcall(cd.SetDrawBling, cd, false)
			pcall(b.SetDurationCooldown, b, cd)
			init(b)
		end,
	})
	tlog("%s AddAuraGroup -> %s", caption, okG and "ok" or ("ERROR " .. show(err)))
	tg.containers[#tg.containers + 1] = c
end

local function try(caption, what, fn)
	local ok, err = pcall(fn)
	if not ok and not tg.reported[caption .. what] then
		tg.reported[caption .. what] = true
		tlog("%s frame: %s -> ERROR %s", caption, what, show(err))
	end
	return ok
end

local function rowGate(index, caption, x)
	local host, c = NewRow(index, caption)
	if not c then return end
	local f, why = Formatter(x)
	if not f then tlog("%s: formatter failed: %s", caption, why); return end
	local FG = (_G.EverAuras or {}).ForeverGlow
	local level = host:GetFrameLevel() + 40
	AddGroup(c, caption, function(b)
		local d = { b = b }
		-- the gate text: one anchor, so it is as wide as its text
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -M - SHIFT, -M)
		fs:SetTextColor(0.75, 0.75, 0.75, 0.8)
		try(caption, "SetDurationText", function() b:SetDurationText(fs, { textFormatter = f }) end)
		d.fs = fs
		-- green: on the text's right end, always
		local dot = Frame(host)
		dot:SetFrameLevel(level + 2)
		try(caption, "anchor green dot", function() dot:SetSize(6, 6); dot:SetPoint("LEFT", fs, "RIGHT", 1, 0) end)
		Box(dot, 0.1, 1, 0.1, 1):SetAllPoints(dot)
		d.dot = dot
		-- red: open while the text is wide (time left < X)
		local late = Frame(host)
		late:SetClipsChildren(true)
		late:SetFrameLevel(level)
		try(caption, "anchor red clip", function()
			late:SetPoint("TOPLEFT", b, "TOPLEFT", -M, M)
			late:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, 0)
		end)
		Box(late, 1, 0, 0, 0.45):SetAllPoints(late)
		local holder = Frame(late)
		holder:SetFrameLevel(level + 1)
		try(caption, "anchor glow holder", function() holder:SetPoint("TOPLEFT", late, "TOPLEFT", M, -M); holder:SetSize(SIZE, SIZE) end)
		if FG then try(caption, "ForeverGlow.Start", function()
			assert(FG.Start(holder, { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10,
				glowThickness = 2, glowXOffset = 0, glowYOffset = 0, glowBorder = true }, SIZE, SIZE), "Start returned false")
		end) end
		d.late, d.holder = late, holder
		-- blue: open while the text is narrow (time left >= X)
		local early = Frame(host)
		early:SetClipsChildren(true)
		early:SetFrameLevel(level)
		try(caption, "anchor blue clip", function()
			early:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 0, 0)
			early:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		end)
		Box(early, 0.2, 0.5, 1, 0.45):SetAllPoints(early)
		d.early = early
		tg.dbg[#tg.dbg + 1] = d
	end)
end

local function rowAnchors(index, caption)
	local host, c = NewRow(index, caption)
	if not c then return end
	local level = host:GetFrameLevel() + 40
	AddGroup(c, caption, function(b)
		local clip = Frame(host)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(level)
		try(caption, "anchor yellow clip", function()
			clip:SetPoint("TOPLEFT", b, "TOPLEFT", -3, 3)
			clip:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -3)
		end)
		Box(clip, 1, 0.9, 0, 0.45):SetAllPoints(clip)
		local sq = Frame(host)
		sq:SetFrameLevel(level + 2)
		try(caption, "anchor cyan square", function() sq:SetSize(12, 12); sq:SetPoint("CENTER", b, "CENTER") end)
		Box(sq, 0, 1, 1, 1):SetAllPoints(sq)
	end)
end

local function rowInside(index, caption)
	local host, c = NewRow(index, caption)
	if not c then return end
	local FG = (_G.EverAuras or {}).ForeverGlow
	AddGroup(c, caption, function(b)
		local holder = CreateFrame("Frame", nil, b)
		holder:SetAllPoints(b)
		holder:SetFrameLevel(b:GetFrameLevel() + 5)
		if FG then try(caption, "ForeverGlow.Start", function()
			assert(FG.Start(holder, { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10,
				glowThickness = 2, glowXOffset = 0, glowYOffset = 0, glowBorder = true }, SIZE, SIZE), "Start returned false")
		end) end
	end)
end

local function rect(o)
	if not o then return "nil" end
	local ok, l, b, w, h = pcall(o.GetRect, o)
	if not ok then return "ERROR " .. show(l) end
	return ("%s,%s %sx%s"):format(show(l), show(b), show(w), show(h))
end

local function dump()
	local d = tg.dbg and tg.dbg[1]
	if not d then tlog("dump: no frame of row A yet (put a DoT on the target)"); return end
	local function q(o, m) local ok, v = pcall(o[m], o); return ok and show(v) or ("ERROR " .. show(v)) end
	tlog("dump A#1 (combat %s): button shown %s visible %s rect %s", show(InCombatLockdown()), q(d.b, "IsShown"), q(d.b, "IsVisible"), rect(d.b))
	tlog("  gate text: shown %s, rect %s, string width %s, points %s", q(d.fs, "IsShown"), rect(d.fs), q(d.fs, "GetStringWidth"), q(d.fs, "GetNumPoints"))
	tlog("  green dot: visible %s, rect %s", q(d.dot, "IsVisible"), rect(d.dot))
	tlog("  red clip: visible %s, rect %s, points %s, level %s", q(d.late, "IsVisible"), rect(d.late), q(d.late, "GetNumPoints"), q(d.late, "GetFrameLevel"))
	tlog("  blue clip: visible %s, rect %s", q(d.early, "IsVisible"), rect(d.early))
	tlog("  glow holder: visible %s, rect %s", q(d.holder, "IsVisible"), rect(d.holder))
end

local function build(x)
	if tg.root then tlog("already built - /fdtgate hide first"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then tlog("C_StringUtil.CreateNumericRuleFormatter is missing"); return end
	tg.root = Frame(UIParent)
	tg.root:SetAllPoints(UIParent)
	tg.containers, tg.dbg, tg.reported = {}, {}, {}
	tlog("[run 2] X = %s s, combat = %s, glow: %s", show(x), show(InCombatLockdown()),
		(_G.EverAuras or {}).ForeverGlow and "EverAuras' ForeverGlow" or "not found")
	rowGate(1, "A: gate (green/red/blue)", x)
	rowAnchors(2, "B: yellow clip + cyan")
	rowInside(3, "C: glow inside")
	tg.events = tg.events or CreateFrame("Frame")
	tg.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	tg.events:SetScript("OnEvent", function()
		for _, c in ipairs(tg.containers or {}) do pcall(c.UpdateAllAuras, c) end
	end)
	tlog("A: green dot at the end of the grey text; above %s s blue, below red + glow. B: yellow + cyan on every icon. C: moving glow? /fdtgate dump, /fdtgate hide.", show(x))
end

SLASH_FDITGATE1 = "/fdtgate"
SlashCmdList.FDITGATE = function(msg)
	msg = strtrim(msg or "")
	if msg == "hide" then
		if tg.root then tg.root:Hide() end
		if tg.events then tg.events:UnregisterAllEvents() end
		tg.root, tg.containers, tg.dbg = nil, nil, nil
		tlog("removed")
		return
	end
	if msg == "dump" then dump(); return end
	build(tonumber(msg) or 6)
end
