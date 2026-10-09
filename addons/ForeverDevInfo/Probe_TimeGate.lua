--[[ Forever Dev Info - /fdtgate [seconds]: can a frame open and close by an aura's TIME LEFT, per aura, in combat?

     The idea (a "text-width gate"): every aura button may carry one duration text, and the game formats it
     itself, also in combat. A NumericRuleFormatter picks its format by the value, so the text can be WIDE below
     X seconds ("WWWWWWWWWWWWWW5") and narrow above ("12"). A font string with a single anchor is as wide as its
     text, and a clip frame hangs on its right edge. Round 1 (2026-10-08): the text changed as planned (both
     ways of giving the formatter), but nothing anchored to it showed. Round 2 (2026-10-09): a frame of ours
     hung on the text's end by ONE point with a size of its own showed and followed the text, so did one hung
     on the icon's centre; clips of ours sized by TWO points on the aura button (or its text) and textures
     filling them drew nothing; frames of ours hung on a button stayed behind when the aura went.
     Round 3, rows of your own debuffs on the target, sorted least time left first, above the screen centre:

       A  the gate INSIDE the aura button (clip frames are the button's children, like /fdstack's clip D):
          below X a red tint + EverAuras' Pixel glow, from X up a blue square in the top-right corner.
       B  the same with the clips OUTSIDE (ours), but what they hold hangs on the button by one point with a
          size of its own (a red square + glow at the centre, the blue corner square).
       C  an always-on Pixel glow on a frame INSIDE each aura button: do its lines move there?

     The small grey text left of rows A and B is the gate text itself (normally invisible).
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

-- The gate text of a frame: one anchor, so it is as wide as its text (wide below X, narrow from X up).
local function GateText(caption, b, f)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -M - SHIFT, -M)
	fs:SetTextColor(0.75, 0.75, 0.75, 0.8)
	try(caption, "SetDurationText", function() b:SetDurationText(fs, { textFormatter = f }) end)
	return fs
end

local PIXEL = { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10, glowThickness = 2,
	glowXOffset = 0, glowYOffset = 0, glowBorder = true }

-- Row A: the whole gate INSIDE the aura button (like /fdstack's clip D, which worked): it goes with the
-- button when the aura goes. Red tint + Pixel glow below X, a blue corner square from X up.
local function rowGateInside(index, caption, x)
	local host, c = NewRow(index, caption)
	if not c then return end
	local f, why = Formatter(x)
	if not f then tlog("%s: formatter failed: %s", caption, why); return end
	local FG = (_G.EverAuras or {}).ForeverGlow
	AddGroup(c, caption, function(b)
		local d = { b = b }
		local fs = GateText(caption, b, f)
		local level = b:GetFrameLevel() + 5
		local late = CreateFrame("Frame", nil, b)
		late:SetClipsChildren(true)
		late:SetFrameLevel(level)
		try(caption, "anchor red clip", function()
			late:SetPoint("TOPLEFT", b, "TOPLEFT", -M, M)
			late:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, 0)
		end)
		local red = late:CreateTexture(nil, "OVERLAY")
		red:SetAllPoints(b)
		red:SetColorTexture(1, 0, 0, 0.45)
		local holder = CreateFrame("Frame", nil, late)
		holder:SetAllPoints(b)
		holder:SetFrameLevel(level + 1)
		if FG then try(caption, "ForeverGlow.Start", function() assert(FG.Start(holder, PIXEL, SIZE, SIZE), "Start returned false") end) end
		local early = CreateFrame("Frame", nil, b)
		early:SetClipsChildren(true)
		early:SetFrameLevel(level)
		try(caption, "anchor blue clip", function()
			early:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 0, 0)
			early:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		end)
		local blue = early:CreateTexture(nil, "OVERLAY")
		blue:SetSize(10, 10)
		blue:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
		blue:SetColorTexture(0.2, 0.5, 1, 1)
		d.fs, d.late, d.early, d.holder = fs, late, early, holder
		tg.dbg[#tg.dbg + 1] = d
	end)
end

-- Row B: the clips OUTSIDE the button (ours, as in round 2), but what they hold hangs on the button by ONE
-- point with a size of its own (like round 2's green dot and cyan square, which showed).
local function rowGateOutside(index, caption, x)
	local host, c = NewRow(index, caption)
	if not c then return end
	local f, why = Formatter(x)
	if not f then tlog("%s: formatter failed: %s", caption, why); return end
	local FG = (_G.EverAuras or {}).ForeverGlow
	local level = host:GetFrameLevel() + 40
	AddGroup(c, caption, function(b)
		local fs = GateText(caption, b, f)
		local late = Frame(host)
		late:SetClipsChildren(true)
		late:SetFrameLevel(level)
		try(caption, "anchor red clip", function()
			late:SetPoint("TOPLEFT", b, "TOPLEFT", -M, M)
			late:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", 0, 0)
		end)
		local holder = Frame(late)
		holder:SetFrameLevel(level + 1)
		try(caption, "anchor red holder", function() holder:SetSize(SIZE, SIZE); holder:SetPoint("CENTER", b, "CENTER") end)
		Box(holder, 1, 0, 0, 0.45):SetAllPoints(holder)
		if FG then try(caption, "ForeverGlow.Start", function() assert(FG.Start(holder, PIXEL, SIZE, SIZE), "Start returned false") end) end
		local early = Frame(host)
		early:SetClipsChildren(true)
		early:SetFrameLevel(level)
		try(caption, "anchor blue clip", function()
			early:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 0, 0)
			early:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		end)
		local sq = Frame(early)
		sq:SetFrameLevel(level + 1)
		try(caption, "anchor blue square", function() sq:SetSize(10, 10); sq:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1) end)
		Box(sq, 0.2, 0.5, 1, 1):SetAllPoints(sq)
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
	tlog("[run 3] X = %s s, combat = %s, glow: %s", show(x), show(InCombatLockdown()),
		(_G.EverAuras or {}).ForeverGlow and "EverAuras' ForeverGlow" or "not found")
	rowGateInside(1, "A: gate inside", x)
	rowGateOutside(2, "B: gate outside", x)
	rowInside(3, "C: glow inside")
	tg.events = tg.events or CreateFrame("Frame")
	tg.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	tg.events:SetScript("OnEvent", function()
		for _, c in ipairs(tg.containers or {}) do pcall(c.UpdateAllAuras, c) end
	end)
	tlog("A and B: above %s s a blue corner, below red + a glow, per icon; nothing left behind when the mob dies. C: does the glow move? /fdtgate dump, /fdtgate hide.", show(x))
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
