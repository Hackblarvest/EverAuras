--[[ Forever Dev Info - /fdpair: can ONE text show two aura values, time AND stacks ("%p (%s)")?

     The game writes only one value into a font string, so EverAuras would draw "%p (%s)" as TWO game texts
     side by side: the time (YELLOW here) and the stacks with the words around them (CYAN here, " (3)"), the
     second hung on the end of the first by ONE point. This probe shows whether that holds up, also in combat.

     1. Out of combat, type /fdpair fmt. Nothing appears on screen; the chat says whether the game takes stack
        formats without a number in them (" ()" at 0 stacks, " (3)" at 3 stacks) and how wide a few short texts
        are with a normal space or a no-break space at their edge.

     2. Put your DoTs on a target (a dummy or a mob) and type /fdpair. Rows of icons appear around the middle of
        the screen, each icon with a small yellow + cyan text under it. Left column, your debuffs on the target
        (/fdpair all: everyone's debuffs, so a friend's stacking Sunder Armor counts too):
          TL   time, then " (stacks)", hung on the icon's left edge: cyan must stay glued to the end of yellow,
               no gap and no overlap, while the time counts 10 -> 9 and 1m -> 59
          TLn  the same with a no-break space instead of the space: compare the gap with TL
          TR   hung on the icon's right edge: cyan's right end stays on the icon's right edge, yellow stays
               glued to cyan's left as the texts change width
          TC   centred: the pair stays centred on the thin white tick, give or take a few pixels
          SL   stacks first ("3 | 12"): yellow hangs on the end of cyan; is the space after the "|" kept?
          SLn  the same with a no-break space
        Right column:
          slot three single-aura buttons (the kind EverAuras really draws texts with) on your DoT that runs
               out first: left / right / centred, as TL, TR and TC
          PL   your own buffs, permanent ones first, time written as "T {} |": what does yellow show on a buff
               WITHOUT a duration (Blood Pact, an aura or aspect)? Nothing, "T  |", or an old time left over?
          PZ   the same with "Z" as the game's zero-duration text: does a Z show on such a buff?
          P0   the same with an empty zero-duration text
        A DoT that does not stack should read " ()" in cyan, a stacking aura " (2)" and so on, also in combat.
        Take one screenshot out of combat and one in combat. Let a DoT run out and put it back: no text may be
        left behind. (If the game refuses a stack format, the chat says so and that row reads " (0)" instead.)

     3. /fdpair relink  out of combat with DoTs up: moves the TL row and the left slot button to the TR layout,
                        and back after 4 s. Both colours must move along; the chat lists any refusal.
        /fdpair dump    the widths the game gave each piece, the gap between them, how far TC is off centre
                        next to the estimate, every P-row time text, and the formatter results again (best
                        out of combat, DoTs up)
        /fdpair hide    removes everything
     Everything is also logged to ForeverDevInfoDB.pairProbe. (The file must be listed in the addon's .toc.)
]]

local pp = {}
local SIZE, GAP, STEP, NMAX = 36, 44, 64, 4
local NBSP = "\194\160"
local YELLOW, CYAN = { 1, 0.85, 0.1, 1 }, { 0.3, 1, 1, 1 }

local function plog(fmt, ...)
	local line = fmt
	if select("#", ...) > 0 then
		local ok, s = pcall(string.format, fmt, ...)
		line = ok and s or (fmt .. " <format error " .. tostring(s) .. ">")
	end
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.pairProbe = ForeverDevInfoDB.pairProbe or {}
	local l = ForeverDevInfoDB.pairProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 400 do table.remove(l, 1) end
	print("|cff33ff99FDI pair|r " .. line)
end

local function secret(v) return issecretvalue and issecretvalue(v) end

local function show(v)
	if secret(v) then return "<secret>" end
	if type(v) == "number" then return ("%.1f"):format(v) end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

-- a text in brackets, with "|" doubled (so chat prints it) and no-break spaces spelled out
local function q(s)
	if secret(s) then return "<secret>" end
	if type(s) ~= "string" then return show(s) end
	return "[" .. (s:gsub("|", "||"):gsub(NBSP, "<nbsp>")) .. "]"
end

local function f1(v) return v and ("%.1f"):format(v) or "n/a" end

local function pack(...) return { n = select("#", ...), ... } end

-- obj:method(...) with the method lookup inside the pcall too (a restricted button may refuse either)
local function pc(obj, method, ...)
	local args = pack(...)
	return pcall(function() return obj[method](obj, unpack(args, 1, args.n)) end)
end

local function num(obj, method)
	local ok, v = pc(obj, method)
	if ok and not secret(v) and type(v) == "number" then return v end
end

local function call(obj, method, ...)
	if not obj then return "nil" end
	local okM, m = pcall(function() return obj[method] end)
	if not okM then return "ERROR " .. show(m) end
	if not m then return "n/a" end
	local r = pack(pc(obj, method, ...))
	if not r[1] then return "ERROR " .. show(r[2]) end
	local out = {}
	for i = 2, r.n do out[#out + 1] = show(r[i]) end
	return table.concat(out, ",")
end

local function rect(o) return call(o, "GetRect") end

local function text(fs)
	local ok, t = pc(fs, "GetText")
	return ok and q(t) or ("ERROR " .. show(t))
end

-- log an error once per row and step; /fdpair dump lists them again
local function once(key, what, ok, err)
	if ok then return true end
	pp.reported = pp.reported or {}
	pp.errors = pp.errors or {}
	if not pp.reported[key .. what] then
		pp.reported[key .. what] = true
		local line = ("%s: %s -> ERROR %s"):format(key, what, show(err))
		pp.errors[#pp.errors + 1] = line
		plog("%s", line)
	end
	return false
end

-- width of a text in the probe's font, on a font string of ours outside any aura button
local function Measure(t)
	if not pp.meterFS then
		local f = CreateFrame("Frame", nil, UIParent)
		f:SetSize(1, 1)
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
		f:SetAlpha(0)
		pp.meter = f
		pp.meterFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		pp.meterFS:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
		pcall(pp.meterFS.SetWordWrap, pp.meterFS, false)
	end
	pp.meter:Show()
	local fs = pp.meterFS
	pc(fs, "SetText", t)
	return num(fs, "GetStringWidth"), num(fs, "GetUnboundedStringWidth"), num(fs, "GetWidth")
end

-- rule formatters: { name, { {threshold, format}, ... }, expected FormatNumber(0), (1), (3) }
local FORMATS = {
	{ "F1", { { 0, " ()" }, { 1, " (%d)" } }, { " ()", " (1)", " (3)" } },
	{ "F2", { { 0, "" }, { 1, "%d" } }, { "", "1", "3" } },
	{ "F3", { { 0, "%d" } }, { "0", "1", "3" } },
	{ "F4", { { 0, "" } }, { "", "", "" } },
	{ "F5", { { 0, NBSP .. "()" }, { 1, NBSP .. "(%d)" } }, { NBSP .. "()", NBSP .. "(1)", NBSP .. "(3)" } },
	{ "F6", { { 0, " | " }, { 1, "%d | " } }, { " | ", "1 | ", "3 | " } },
	{ "F7", { { 0, " |" .. NBSP }, { 1, "%d |" .. NBSP } }, { " |" .. NBSP, "1 |" .. NBSP, "3 |" .. NBSP } },
	{ "F8", { { 0, "|r" }, { 1, "%d" } }, { "|r", "1", "3" } },
}

local function Rules(rules)
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
		return nil, "C_StringUtil.CreateNumericRuleFormatter is missing"
	end
	local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not f then return nil, "CreateNumericRuleFormatter -> ERROR " .. show(f) end
	local R = (Enum and Enum.NumericRuleFormatRounding) or {}
	local bps = {}
	for i, r in ipairs(rules) do bps[i] = { threshold = r[1], step = 1, rounding = R.Down or 2, format = r[2] } end
	local okB, err = pc(f, "SetBreakpoints", bps)
	if not okB then return nil, "SetBreakpoints -> ERROR " .. show(err) end
	return f
end

-- a row's count formatter runs inside the game's own aura update, where an error would break that row in
-- every update: try FormatNumber here first and fall back to the formatter's '%d' rule alone if it throws
local function Checked(spec, f, canCall)
	if not (f and canCall) then return f end
	for _, n in ipairs({ 0, 1, 3 }) do
		local ok, err = pc(f, "FormatNumber", n)
		if not ok then
			local rule = spec[2][#spec[2]][2]
			plog("%s: FormatNumber(%d) -> ERROR %s, so its rows use the single rule %s (0 stacks then read 0)",
				spec[1], n, show(err), q(rule))
			return (Rules({ { 0, rule } }))
		end
	end
	return f
end

local WIDTHS = {
	{ "(3)", " (3)", NBSP .. "(3)" },
	{ "3 |", "3 | ", "3 |" .. NBSP },
	{ "()", " ()", NBSP .. "()" },
	{ "x", " x", "x ", NBSP .. "x" .. NBSP },
}

-- STEP 0: does the game take these formats, and does addon code get FormatNumber's result?
local function fmtStep()
	plog("[fmt] combat %s. Rule formatters: SetBreakpoints, then FormatNumber(0) (1) (3):", show(InCombatLockdown()))
	for _, F in ipairs(FORMATS) do
		local desc = {}
		for _, r in ipairs(F[2]) do desc[#desc + 1] = ("%d:%s"):format(r[1], q(r[2])) end
		local f, why = Rules(F[2])
		if not f then
			plog("%s {%s}: %s", F[1], table.concat(desc, " "), why)
		else
			local out, same = {}, true
			for i, n in ipairs({ 0, 1, 3 }) do
				local ok, s = pc(f, "FormatNumber", n)
				out[i] = ("%d->%s"):format(n, ok and q(s) or ("ERROR " .. show(s)))
				if not ok or secret(s) or s ~= F[3][i] then same = false end
			end
			plog("%s {%s}: SetBreakpoints ok | %s | %s", F[1], table.concat(desc, " "), table.concat(out, " "),
				same and "as expected" or "NOT as expected")
		end
	end
	for _, group in ipairs(WIDTHS) do
		local parts = {}
		for _, t in ipairs(group) do
			local sw, uw, w = Measure(t)
			parts[#parts + 1] = ("%s %s/%s/%s"):format(q(t), f1(sw), f1(uw), f1(w))
		end
		plog("width (string/unbounded/box): %s", table.concat(parts, "  "))
	end
	local w0, w3 = Measure(" ()"), Measure(" (3)")
	if w0 and w3 then
		plog("TC estimate = (w(' ()') + w(' (3)')) / 2 = %.1f (the plan's first idea, w(' (3)'), = %.1f)", (w0 + w3) / 2, w3)
	end
	if pp.meter then pp.meter:Hide() end
end

-- the time piece's number: Blizzard's own aura duration format (whole seconds up to 90 s, then minutes ...)
local function Seconds()
	if pp.sec ~= nil then return pp.sec or nil end
	pp.sec = false
	if not (C_StringUtil and C_StringUtil.CreateSecondsFormatter) then
		plog("C_StringUtil.CreateSecondsFormatter is missing: the time pieces get the game's default text, no format")
		return nil
	end
	local ok, f = pcall(C_StringUtil.CreateSecondsFormatter)
	if not ok or not f then plog("CreateSecondsFormatter -> ERROR %s", show(f)); return nil end
	local E = Enum or {}
	local I = E.SecondsFormatterInterval or {}
	pc(f, "SetDefaultAbbreviation", E.SecondsFormatterAbbreviation and E.SecondsFormatterAbbreviation.OneLetter or 2)
	pc(f, "SetRounding", E.SecondsFormatterRounding and E.SecondsFormatterRounding.Truncate or 1)
	pc(f, "SetCanRoundUpLastUnit", true)
	if I.Seconds then pc(f, "SetMinInterval", I.Seconds) end
	if I.Seconds and I.Minutes and C_CurveUtil and C_CurveUtil.CreateCurve then
		local okC, err = pcall(function()
			local curve = C_CurveUtil.CreateCurve()
			curve:SetType(Enum.LuaCurveType.Step)
			curve:AddPoint(0, I.Seconds)
			curve:AddPoint(1 + 1.5 * 60, I.Minutes)
			if I.Hours then curve:AddPoint(1 + 1.5 * 3600, I.Hours) end
			if I.Days then curve:AddPoint(1 + 1.5 * 86400, I.Days) end
			f:SetMaxIntervalCurve(curve)
		end)
		if not okC then plog("seconds formatter interval curve -> ERROR %s (times may read 1m instead of 75)", show(err)) end
	end
	pc(f, "SetDesiredUnitCount", 1)
	pp.sec = f
	return f
end

-- the duration text's colour belongs to the game's binding, so yellow goes in as a constant colour curve
local function YellowCurve()
	if pp.curve ~= nil then return pp.curve or nil end
	pp.curve = false
	if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then
		plog("C_CurveUtil.CreateColorCurve is missing: the time pieces may stay white")
		return nil
	end
	local ok, cc = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		c:SetType(Enum.LuaCurveType.Step)
		c:AddPoint(0, CreateColor(YELLOW[1], YELLOW[2], YELLOW[3], YELLOW[4]))
		return c
	end)
	if not ok then plog("colour curve -> ERROR %s", show(cc)); return nil end
	pp.curve = cc
	return cc
end

local function DurOptions(formatString)
	local P = (Enum and Enum.DurationTextBindingProperty) or {}
	local opts = {}
	local sec = Seconds()
	if sec then
		opts.textFormat = { formatString = formatString, components = { { property = P.RemainingDuration or 0, formatter = sec } } }
	end
	local curve = YellowCurve()
	if curve then opts.textColor = { curve = curve, property = P.RemainingDuration or 0 } end
	return opts
end

-- rows PZ / P0: the same format, carried by a binding of ours with a zero-duration text
local function ZeroOptions(key, zero)
	local opts = DurOptions("T {} |")
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then
		plog("%s: C_DurationUtil.CreateDurationTextBinding is missing, so this row is the same as PL", key)
		return opts
	end
	local ok, bind = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok or not bind then plog("%s: CreateDurationTextBinding -> ERROR %s", key, show(bind)); return opts end
	local okZ, errZ = pc(bind, "SetZeroDurationText", zero)
	local okG, back = pc(bind, "GetZeroDurationText")
	plog("%s: SetZeroDurationText(%s) -> %s, reads back %s", key, q(zero), okZ and "ok" or ("ERROR " .. show(errZ)),
		okG and q(back) or ("ERROR " .. show(back)))
	if opts.textFormat then
		local okF, errF = pc(bind, "SetTextFormat", opts.textFormat.formatString, opts.textFormat.components)
		if okF then
			opts.textFormat = nil   -- the format travels inside the binding, so nothing resets the zero text
		else
			plog("%s: binding SetTextFormat -> ERROR %s (the format goes in the options instead)", key, show(errF))
		end
	end
	opts.binding = bind
	return opts
end

local function Frame(parent)
	return CreateFrame("Frame", nil, parent, "DisableUntrustedLayoutScriptsTemplate")
end

-- a row: a host frame with a caption above it; left column (1) left of the screen centre, right (2) right of it
local function NewHost(col, idx, caption)
	local W = NMAX * (SIZE + GAP)
	local host = Frame(pp.root)
	host:SetSize(W, SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", col == 1 and -(W + 120) or 40, pp.top - (idx - 1) * STEP)
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 3)
	pc(cap, "SetWordWrap", false)
	cap:SetText(caption)
	return host
end

local function Container(host, unit, key)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then plog("%s: container -> ERROR %s", key, show(c)); return nil end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	local okU, err = pc(c, "SetUnit", unit)
	if not okU then plog("%s: SetUnit(%s) -> ERROR %s", key, unit, show(err)) end
	pp.containers[#pp.containers + 1] = c
	return c
end

local function NewRowRec(key, mode)
	local row = { key = key, mode = mode, frames = {} }
	pp.rows[key] = row
	pp.order[#pp.order + 1] = row
	return row
end

-- the chains: { leading piece, its point, on the button's point, follower's point, on the leader's point }
local CHAIN = {
	L = { "D", "TOPLEFT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT" },
	R = { "C", "TOPRIGHT", "BOTTOMRIGHT", "TOPRIGHT", "TOPLEFT" },
	C = { "D", "TOP", "BOTTOM", "TOPLEFT", "TOPRIGHT" },
	SL = { "C", "TOPLEFT", "BOTTOMLEFT", "TOPLEFT", "TOPRIGHT" },
}

-- clear both pieces, hang the leader on the button and the follower on the leader; detail = log each call
local function Link(mode, d, detail)
	local m = CHAIN[mode]
	local leadName = m[1]
	local followName = leadName == "D" and "C" or "D"
	local lead, follow = d[leadName], d[followName]
	local x = mode == "C" and -(d.est or 0) / 2 or 0
	local fails, first = 0, nil
	local function step(label, obj, method, ...)
		local ok, err = pc(obj, method, ...)
		if not ok then
			fails = fails + 1
			first = first or (label .. ": " .. show(err))
		end
		if detail then plog("  %s %s -> %s", detail, label, ok and "ok" or ("ERROR " .. show(err))) end
	end
	step("D:ClearAllPoints", d.D, "ClearAllPoints")
	step("C:ClearAllPoints", d.C, "ClearAllPoints")
	step(("%s %s on button %s %+.1f"):format(leadName, m[2], m[3], x), lead, "SetPoint", m[2], d.b, m[3], x, -1)
	step(("%s %s on %s %s"):format(followName, m[4], leadName, m[5]), follow, "SetPoint", m[4], lead, m[5], 0, 0)
	return fails, first
end

local function Dress(key, b)
	b:SetSize(SIZE, SIZE)
	pc(b, "SetMouseClickEnabled", false)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(b)
	once(key, "SetIcon", pc(b, "SetIcon", icon))
	local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cd:SetAllPoints(b)
	pc(cd, "SetDrawBling", false)
	pc(cd, "SetHideCountdownNumbers", true)
	once(key, "SetDurationCooldown", pc(b, "SetDurationCooldown", cd))
end

-- the two pieces of one button: D = the game's duration text (yellow), C = its count text (cyan)
local function Pieces(row, b, durOpts, countFmt)
	local d = { b = b, est = pp.est }
	d.D = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	d.C = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	for _, fs in ipairs({ d.D, d.C }) do
		pc(fs, "SetWordWrap", false)
		pc(fs, "SetWidth", 0)
	end
	pc(d.D, "SetTextColor", YELLOW[1], YELLOW[2], YELLOW[3], YELLOW[4])
	pc(d.C, "SetTextColor", CYAN[1], CYAN[2], CYAN[3], CYAN[4])
	row.frames[#row.frames + 1] = d
	local fails, first = Link(row.mode, d)
	if fails > 0 then once(row.key, "anchors", false, first) end
	once(row.key, "SetDurationText", pc(b, "SetDurationText", d.D, durOpts))
	once(row.key, "SetApplicationCount", pc(b, "SetApplicationCount", d.C, countFmt and { formatter = countFmt } or nil))
	if row.mode == "C" then
		local tick = b:CreateTexture(nil, "ARTWORK")
		tick:SetColorTexture(1, 1, 1, 1)
		tick:SetSize(1, 18)
		tick:SetPoint("TOP", b, "BOTTOM", 0, 4)
	end
end

-- s = { col, idx, key, caption, unit, filter, mode, count = formatter, opts = duration options, reverse }
local function GroupRow(s)
	local host = NewHost(s.col, s.idx, s.caption)
	local c = Container(host, s.unit, s.key)
	if not c then return end
	local row = NewRowRec(s.key, s.mode)
	if not s.count then plog("%s: no stack formatter, so the count text uses the game's default", s.key) end
	local M2, D2 = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, err = pc(c, "AddAuraGroup", s.key, s.filter, {
		maxFrameCount = NMAX,
		sortMethod = M2 and M2.ExpirationOnly,
		sortDirection = D2 and (s.reverse and D2.Reverse or D2.Normal),
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = GAP },
		initializeFrame = function(b)
			local okI, e = pcall(function()
				Dress(s.key, b)
				Pieces(row, b, s.opts or DurOptions("{}"), s.count)
			end)
			once(s.key, "initializeFrame", okI, e)
		end,
	})
	plog("%s (%s on %s): AddAuraGroup -> %s", s.key, s.filter, s.unit, okG and "ok" or ("ERROR " .. show(err)))
end

-- three AddAuraSlot buttons (what EverAuras' Text displays and sub-texts use) on the first own debuff
local function SlotRow(s)
	local host = NewHost(s.col, s.idx, s.caption)
	local c = Container(host, s.unit, s.key)
	if not c then return end
	if not s.count then plog("slot: no stack formatter, so the count texts use the game's default") end
	local M2, D2 = AuraContainerSortMethod, AuraContainerSortDirection
	for i, mode in ipairs({ "L", "R", "C" }) do
		local row = NewRowRec("slot" .. mode, mode)
		local ok, err = pc(c, "AddAuraSlot", row.key, s.filter, {
			sortMethod = M2 and M2.ExpirationOnly,
			sortDirection = D2 and D2.Normal,
			initializeFrame = function(b)
				local okI, e = pcall(function()
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", host, "TOPLEFT", (i - 1) * 100, 0)
					Dress(row.key, b)
					Pieces(row, b, DurOptions("{}"), s.count)
				end)
				once(row.key, "initializeFrame", okI, e)
			end,
		})
		plog("%s (%s on %s): AddAuraSlot -> %s", row.key, s.filter, s.unit, ok and "ok" or ("ERROR " .. show(err)))
	end
end

-- is this button showing an aura? true / false, or nil when the game will not say (secret or refused)
local function shown(d)
	local ok, s = pc(d.b, "IsShown")
	if not ok or secret(s) then return nil end
	return s and true or false
end

-- the first frame of a row that shows an aura (readable out of combat), else its first frame
local function pick(row)
	local hidden = false
	for _, d in ipairs(row.frames) do
		local s = shown(d)
		if s == nil then return row.frames[1], " (shown state unreadable: frame 1)" end
		if s then return d, "" end
		hidden = true
	end
	return row.frames[1], hidden and " (no aura shown)" or ""
end

local function teardown()
	if pp.root then pp.root:Hide() end
	if pp.events then pp.events:UnregisterAllEvents() end
	if pp.meter then pp.meter:Hide() end
	pp.root, pp.rows, pp.order, pp.containers, pp.relinking = nil, nil, nil, nil, nil
end

local function relink()
	if not pp.rows then plog("relink: nothing built - type /fdpair first"); return end
	if pp.relinking then plog("relink: still running"); return end
	plog("[relink] combat %s%s", show(InCombatLockdown()),
		InCombatLockdown() and " - this is meant for OUT of combat; trying anyway" or "")
	local rows, gen = {}, pp.gen
	for _, key in ipairs({ "TL", "slotL" }) do
		if pp.rows[key] then rows[#rows + 1] = pp.rows[key] else plog("relink: row %s was not made", key) end
	end
	local function pass(mode)
		for _, row in ipairs(rows) do
			local n, bad, first = 0, 0, nil
			for i, d in ipairs(row.frames) do
				local f, e = Link(mode, d, i == 1 and (row.key .. "#1") or nil)
				n = n + 1
				if f > 0 then bad, first = bad + 1, first or e end
			end
			plog("%s -> %s layout: %d frame(s), %d with a refusal%s", row.key, mode, n, bad, first and (", first: " .. first) or "")
			local d, note = pick(row)
			if d then
				C_Timer.After(0.2, function()
					plog("  %s%s after -> %s: D %s | C %s", row.key, note, mode, rect(d.D), rect(d.C))
				end)
			end
		end
	end
	pp.relinking = true
	pass("R")
	C_Timer.After(4, function()
		if pp.gen ~= gen or not pp.rows then return end   -- hidden or rebuilt meanwhile
		pp.relinking = nil
		pass("L")
		plog("relink done: did TL and the left slot jump to the right-edge layout and come back, both colours moving?")
	end)
end

local function dumpRow(row)
	local d, note = pick(row)
	if not d then plog("%s: no frames were made", row.key); return end
	plog("%s%s: D %s w %s box %s | C %s w %s box %s", row.key, note,
		text(d.D), call(d.D, "GetStringWidth"), call(d.D, "GetWidth"),
		text(d.C), call(d.C, "GetStringWidth"), call(d.C, "GetWidth"))
	local left, right = d.D, d.C
	if row.mode == "SL" then left, right = d.C, d.D end
	local lr, rl = num(left, "GetRight"), num(right, "GetLeft")
	local ll, rr = num(left, "GetLeft"), num(right, "GetRight")
	local bl, br = num(d.b, "GetLeft"), num(d.b, "GetRight")
	local line = ("  gap %s"):format(lr and rl and ("%.1f"):format(rl - lr) or "n/a")
	if row.mode == "R" then
		line = line .. (" | C right - icon right %s"):format(rr and br and ("%.1f"):format(rr - br) or "n/a")
	elseif row.mode == "C" then
		local wC = num(d.C, "GetStringWidth")
		line = line .. (" | pair centre - icon centre %s (estimate says %s)"):format(
			ll and rr and bl and br and ("%.1f"):format((ll + rr) / 2 - (bl + br) / 2) or "n/a",
			wC and pp.est and ("%.1f"):format((wC - pp.est) / 2) or "n/a")
	else
		line = line .. (" | left end - icon left %s"):format(ll and bl and ("%.1f"):format(ll - bl) or "n/a")
	end
	plog("%s", line)
	if row.key:sub(1, 1) ~= "P" then return end
	-- U3: every shown icon of the row, so a buff without a duration is among them
	local texts = {}
	for i, f in ipairs(row.frames) do
		if shown(f) then texts[#texts + 1] = ("#%d D %s C %s"):format(i, text(f.D), text(f.C)) end
	end
	plog("  %s shown icons: %s", row.key, #texts > 0 and table.concat(texts, "  ") or "none readable")
	local okA, getter = pcall(function() return d.b.GetDurationTextBinding end)
	if okA and getter then
		local okB, bind = pcall(getter, d.b)
		if okB and bind then
			plog("  %s button binding: enabled %s, zero text %s, formatted %s", row.key, call(bind, "IsEnabled"),
				call(bind, "GetZeroDurationText"), call(bind, "GetFormattedText"))
		else
			plog("  %s GetDurationTextBinding -> ERROR %s", row.key, show(bind))
		end
	else
		plog("  %s: the button gives no access to its duration binding (expected)", row.key)
	end
end

local function dump()
	fmtStep()
	if not pp.rows then plog("dump: no rows - type /fdpair"); return end
	plog("[dump] combat %s, TC estimate %s. Per row, the first frame with an aura:", show(InCombatLockdown()), f1(pp.est))
	for _, row in ipairs(pp.order) do
		local ok, err = pcall(dumpRow, row)
		if not ok then plog("%s: dump -> ERROR %s", row.key, show(err)) end
	end
	local errs = pp.errors or {}
	plog("errors so far: %d", #errs)
	for _, e in ipairs(errs) do plog("  %s", e) end
end

local function build(filter)
	if pp.root then teardown(); plog("old rows removed") end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	pp.gen = (pp.gen or 0) + 1
	pp.root = Frame(UIParent)
	pp.root:SetAllPoints(UIParent)
	pp.rows, pp.order, pp.containers, pp.reported, pp.errors = {}, {}, {}, {}, {}
	pp.top = math.min(330, (num(UIParent, "GetHeight") or 768) / 2 - 30)
	-- the rows' stack formatters, each tried with FormatNumber first (the control F3 says whether addon code may)
	local F, byName = {}, {}
	for _, spec in ipairs(FORMATS) do
		local f, why = Rules(spec[2])
		F[spec[1]], byName[spec[1]] = f, spec
		if not f and (spec[1] == "F1" or spec[1] == "F3" or spec[1] == "F5" or spec[1] == "F6" or spec[1] == "F7") then
			plog("%s: %s", spec[1], why)
		end
	end
	local canCall = F.F3 and (pc(F.F3, "FormatNumber", 1))
	if F.F3 and not canCall then plog("addon code may not call FormatNumber (control F3 refused): the rows use their formatters untried") end
	for _, name in ipairs({ "F1", "F5", "F6", "F7" }) do F[name] = Checked(byName[name], F[name], canCall) end
	local w0, w3 = Measure(" ()"), Measure(" (3)")
	if pp.meter then pp.meter:Hide() end
	pp.est = (w0 and w3) and (w0 + w3) / 2 or 0
	plog("[run] target filter %s, combat %s, TC estimate %.1f (w(' ()') %s, w(' (3)') %s)", filter,
		show(InCombatLockdown()), pp.est, f1(w0), f1(w3))
	local T, P = "target", "player"
	local specs = {
		{ col = 1, idx = 1, key = "TL", mode = "L", unit = T, filter = filter, count = F.F1,
			caption = "TL  time + ' (n)' on the left edge: cyan glued to yellow" },
		{ col = 1, idx = 2, key = "TLn", mode = "L", unit = T, filter = filter, count = F.F5,
			caption = "TLn  as TL, with a no-break space" },
		{ col = 1, idx = 3, key = "TR", mode = "R", unit = T, filter = filter, count = F.F1,
			caption = "TR  on the right edge: cyan ends there, yellow glued left" },
		{ col = 1, idx = 4, key = "TC", mode = "C", unit = T, filter = filter, count = F.F1,
			caption = ("TC  centred on the white tick (estimate %.1f)"):format(pp.est) },
		{ col = 1, idx = 5, key = "SL", mode = "SL", unit = T, filter = filter, count = F.F6,
			caption = "SL  stacks first '3 || 12': is the space after || kept?" },
		{ col = 1, idx = 6, key = "SLn", mode = "SL", unit = T, filter = filter, count = F.F7,
			caption = "SLn  as SL, with a no-break space" },
		{ col = 2, idx = 1, key = "slot", unit = T, filter = filter, count = F.F1, slot = true,
			caption = "slot  slot buttons, first DoT to end: left / right / centred" },
		{ col = 2, idx = 2, key = "PL", mode = "L", unit = P, filter = "HELPFUL", reverse = true, count = F.F1,
			opts = DurOptions("T {} |"), caption = "PL  your buffs, permanent first, time as 'T {} ||'" },
		{ col = 2, idx = 3, key = "PZ", mode = "L", unit = P, filter = "HELPFUL", reverse = true, count = F.F1,
			opts = ZeroOptions("PZ", "Z"), caption = "PZ  as PL + zero-duration text 'Z'" },
		{ col = 2, idx = 4, key = "P0", mode = "L", unit = P, filter = "HELPFUL", reverse = true, count = F.F1,
			opts = ZeroOptions("P0", ""), caption = "P0  as PL + empty zero-duration text" },
	}
	for _, s in ipairs(specs) do
		local ok, err = pcall(s.slot and SlotRow or GroupRow, s)
		if not ok then plog("%s: row -> ERROR %s (the other rows go on)", s.key, show(err)) end
	end
	pp.events = pp.events or CreateFrame("Frame")
	pp.events:RegisterEvent("PLAYER_TARGET_CHANGED")
	pp.events:SetScript("OnEvent", function()
		for _, c in ipairs(pp.containers or {}) do pc(c, "UpdateAllAuras") end
	end)
	C_Timer.After(1, function()
		if not pp.order then return end
		local parts = {}
		for _, row in ipairs(pp.order) do parts[#parts + 1] = ("%s %d"):format(row.key, #row.frames) end
		plog("frames made (the game makes 10 per group at once): %s", table.concat(parts, ", "))
		plog("Yellow = time, cyan = stacks. Screenshot out of combat and in combat; then /fdpair relink, /fdpair dump, /fdpair hide.")
	end)
end

local COMMANDS = {
	hide = function() teardown(); plog("removed") end,
	fmt = fmtStep,
	dump = dump,
	relink = relink,
	all = function() build("HARMFUL") end,
	[""] = function() build("HARMFUL|PLAYER") end,
}

SLASH_FDIPAIR1 = "/fdpair"
SlashCmdList.FDIPAIR = function(msg)
	msg = strtrim(msg or ""):lower()
	local fn = COMMANDS[msg]
	if not fn then
		plog("unknown '%s'. Use: /fdpair, /fdpair all, /fdpair fmt, /fdpair relink, /fdpair dump, /fdpair hide", msg)
		return
	end
	local ok, err = pcall(fn)
	if not ok then plog("/fdpair %s -> ERROR %s", msg, show(err)) end
end
