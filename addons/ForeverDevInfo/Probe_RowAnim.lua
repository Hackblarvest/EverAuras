--[[ Probe_RowAnim.lua - /fdrowanim: the in-game questions behind Start animations in sorted rows (EverAuras'
     Dynamic Groups sorted by the time left). Made for the local GM server and a level 60 warlock.

     Written for the ForeverDevInfo dev addon (in both TOCs, after Probe_Sound.lua; copy the addon folder into the
     client's Interface\AddOns\ForeverDevInfo while the client is closed). It logs into ForeverDevInfoDB.rowAnimProbe
     (max 3000 lines); the step you are on is kept in ForeverDevInfoDB.rowAnimStep.

     Seven rows of the game's aura group buttons: 40 px, your HELPFUL auras, sorted by expiration (the soonest to
     expire first), each with a caption. Nothing here is EverAuras: each row is built the way the engine builds (or
     would build) its sorted rows, and coloured squares show what the game did. The gate texts are invisible
     (/fdrowanim show):
       BLUE    top left      settled clip: open from X s after the aura went on (its elapsed text is short)
       ORANGE  top right     fresh clip: open during the first X s (the elapsed text is wide, or tall in W2)
       GREEN   bottom right  late clip (W2): open while the time left is below T
       GREY    bottom left   early clip (W2): open while the time left is T or more
       YELLOW  at an edge    inside a clip exactly the frame's size (L): cut off = the clip did not move along
       white dots            clocks: looping animations of our own (L's big one, B2)
       GREEN dot             L's small clock (the one started half a turn on)

     Z0  one frame (Demon Skin / Armor or Blood Pact, whichever expires first), X = 2 s, the elapsed text as the
         engine builds it today (ElapsedOptions).
     ZB  the planned fix, the engine's way: a binding with SetZeroDurationText("0") and the elapsed format inside
         it (SetTextFormat), options { binding = b }. If the binding takes no format, the format goes in the options.
         Should SetTextFormat change the zero text, ZB (ZE, B2) sets it again after it, which the engine does not:
         the build then says so in chat, and the engine must change before ZB's result holds for it.
     ZE  as ZB with the zero text "".
     ZF  a binding with the zero text "0" and the format in the options next to it: does that format reset the
         zero text?
         Q1: the game gives Blood Pact (no duration) the frame Demon Armor left within 2 s: does it keep the old,
         wide elapsed text? ORANGE = stale (the engine's frame would stay empty), BLUE = clean.
     W2  two frames, X = 2 s, ONE text "{}{}": elapsed (12 empty lines below 2 s, nothing from 2 s), then the time
         left (40 W's below T = the buff's duration less 5 s, the number from T). ORANGE and BLUE hang on the text's
         top edge, GREEN and GREY on its end, inside BLUE. Q2: two parts in one text, the newlines making it taller,
         in and out of combat. (Should empty lines add no height on a text of ours, measured at the build, each
         line holds a no-break space instead; the log says which.)
     L   three frames: Demon Armor, Unending Breath, Detect Invisibility (not Blood Pact, so the frame of a buff you
         cancel stays hidden until the buff comes back). Q3: the icon on a mover that shakes (our Path +-10 px, 1 s,
         REPEAT) holding the gate (BLUE), a clip of the frame's size with a YELLOW square at its right edge, a cyan
         dot anchored to the mover and a magenta dot parented to the mover but anchored to the button; a white
         outline that pulses (Scale 1 -> 1.3, BOUNCE, 0.5 s) with its own clip and a YELLOW square at its left edge;
         a big clock (a white dot circling 12 px in 4 s, Play()) and a small GREEN one started half a turn on
         (Play(false, 2)).
     B2  every buff on you (no spell filter), up to 20 frames. Q4: each frame is built like the Stage 2 copy row
         (the engine's gate text, fresh clip, a copy of the icon, swipe and count fed by the game that slides down
         50 px while fading in, its group handed over, the zero-text binding of ZB), plus a white clock; every step
         is logged with the combat flag. Frames 11-20 are made when the 11th buff comes: "B2 batch 2" in chat.

     /fdrowanim [spellIDs | buff name]   builds it, out of combat (Z, W2 and L then use these spells; B2 all)
     /fdrowanim                          the current step (once built); next | back | step <n> | steps
     /fdrowanim show    the gate texts of Z, W2 and L visible / invisible again (out of combat)
     /fdrowanim kick    UpdateAllAuras on every row (the game's full rebuild)
     /fdrowanim reset   SetText("0") by the addon on Z0's gate texts, no other row's (out of combat; Q5)
     /fdrowanim phase   how far each clock is into its turn (GetElapsed; out of combat)
     /fdrowanim dump    what can be read of every row (best out of combat)
     /fdrowanim note <text>   what you saw, into the log;  /fdrowanim hide   removes it

     What the answers decide (the plan, section 4):
       Q1  ZB or ZE BLUE -> row gates and copies get the zero-text binding (with the zero text set after
           SetTextFormat, if the build said SetTextFormat changed it). Neither, but reset works -> no Start for
           rows with auras without a duration, plus a reset at safe time. Neither -> no Start for those rows.
       Q2  W2 right in and out of combat -> Stage 3 uses one two-part text; otherwise a fourth "time" row.
       Q3  magenta left behind -> everything anchored to the mover; YELLOW cut -> keep the reach margins; clocks
           behind after a hide -> "in step while shown"; the small clock opposite -> later batches get the phase.
       Q4  B2 batch 2 refused in combat -> the row is rebuilt without Start after the fight.
     Nothing here compares, tests, formats or does arithmetic on a value that may be secret: every read passes
     issecretvalue first ("<secret>" in the log), and every call on the game's objects sits in a pcall.
]]

local R = { reported = {}, showGate = false }   -- the probe's state; rows, containers, ... while it is built
local BUGS = {}
local BatchLine, Build, ShowStep                 -- defined further down

local PREFIX = "|cff33ff99FDI row|r "
local CAP = 3000                     -- the log's lines: room for several dumps without losing the build's lines
local SIZE = 40
local X = 2                          -- the gate's seconds in Z, W2 and L
local SHIFT, M, PADT = 80, 6, 50     -- the small gates (as /fdanim2): the text starts SHIFT + M left of the frame
local NL, NW, SOON = 12, 40, 5       -- W2: empty lines below X; W's below T; T = the buff's duration less SOON
local NBSP = "\194\160"              -- a no-break space: W2's lines hold one if empty lines add no height
local LAYOUT_SAFE = "DisableUntrustedLayoutScriptsTemplate"
-- the engine's numbers (ForeverEngineAura.lua, its animation block): the gate's font size, how far left of the
-- frame its text hangs, the room around the frame, the path's samples
local ENG = { font = 64, shift = 620, margin = 300, samples = 20 }
local COLOR = {
	BLUE = { 0.2, 0.5, 1 }, ORANGE = { 1, 0.55, 0.1 }, GREEN = { 0.2, 0.9, 0.2 }, GREY = { 0.62, 0.62, 0.62 },
	YELLOW = { 1, 0.9, 0.1 }, WHITE = { 1, 1, 1 }, CYAN = { 0.2, 1, 1 }, MAGENTA = { 1, 0.3, 1 },
}
-- B2's Start: WA's Slide from Top, slowed down (from 50 px above, alpha 0 -> 1, 0.6 s); X = ceil(0.6 + 0.2) = 1 s
-- as the engine's AnimSpec counts it
local SLIDE = { d = 0.6, x = 1, a0 = 0, a1 = 1, pts = {} }
for i = 1, ENG.samples + 1 do SLIDE.pts[i] = { 0, 50 * (1 - (i - 1) / ENG.samples) } end
-- the default spells: every rank in this client's data (SpellName.db2 + SkillLineAbility.db2: warlock Demonology
-- 354, the Imp 188), plus the names (the spellbook and the auras on you add whatever rank you have)
local SPELLS = {
	armor = { ids = { 687, 696, 706, 1086, 11733, 11734, 11735 }, names = { "Demon Skin", "Demon Armor" } },  -- 30 min
	breath = { ids = { 5697 }, names = { "Unending Breath" } },                                                -- 10 min
	-- 10 min; this client names all three ranks "Detect Invisibility"
	detect = { ids = { 132, 2970, 11743 }, names = { "Detect Invisibility", "Detect Lesser Invisibility",
		"Detect Greater Invisibility" } },
	pact = { ids = { 6307, 7804, 7805, 11766, 11767 }, names = { "Blood Pact" } },                            -- no duration
}
local ARMOR_DUR = 1800               -- Demon Skin / Armor: W2's T when no buff of its set is up at the build
-- where each row's first frame sits (its top left, from the screen centre); the Z captions go to the right
local PLACE = {
	Z0 = { -470, 200 }, ZB = { -470, 140 }, ZE = { -470, 80 }, ZF = { -470, 20 },
	W2 = { 140, 200 }, L = { 140, 110 }, B2 = { -440, -70 },
}

---------------------------------------------------------------------------- helpers
local function secret(v) return issecretvalue ~= nil and issecretvalue(v) == true end

local function S(v)                  -- printable form; never compares, tests or converts a secret
	if secret(v) then return "<secret>" end
	if type(v) == "number" then
		if v ~= v or v == math.huge or v == -math.huge then return tostring(v) end
		if v == math.floor(v) and math.abs(v) < 1e9 then return ("%d"):format(v) end
		return ("%.2f"):format(v)
	end
	if v == nil then return "nil" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function Short(err, n)         -- an error without its "file:line: " prefix, first line only, cut to n chars
	local s = S(err)
	s = s:gsub("^[^:\n]*:%d+: ", "")
	s = s:gsub("\n.*$", "")
	n = n or 90
	if #s > n then s = s:sub(1, n - 3) .. "..." end
	return s
end

local function DB()
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	return ForeverDevInfoDB
end

local function push(line, loud)
	local db = DB()
	if type(db.rowAnimProbe) ~= "table" then db.rowAnimProbe = {} end
	local l = db.rowAnimProbe
	l[#l + 1] = date("%H:%M:%S ") .. line
	while #l > CAP do table.remove(l, 1) end
	if loud then print(PREFIX .. (line:gsub("|", "||"))) end    -- a "|" in chat would start a colour code
end

local function F(fmt, ...)
	if select("#", ...) == 0 then return fmt end
	local ok, s = pcall(string.format, fmt, ...)
	return ok and s or (fmt .. " <format error>")
end
local function log(fmt, ...) push(F(fmt, ...), true) end      -- chat + log
local function qlog(fmt, ...) push(F(fmt, ...), false) end    -- log only
local function say(line) print(PREFIX .. line) end            -- chat only

local function Bug(where, err)       -- an error in the probe itself (not a refused API call)
	if BUGS[where] then return end
	BUGS[where] = true
	log("PROBE BUG in %s: %s", where, Short(err, 200))
end

local function Later(sec, where, fn) -- C_Timer.After with the probe's error guard
	C_Timer.After(sec, function()
		local ok, err = pcall(fn)
		if not ok then Bug(where, err) end
	end)
end

local function pack(...) return { n = select("#", ...), ... } end

local function fnOf(o, k)            -- o[k] without an error when o is nil or refuses the read
	if o == nil then return nil end
	local ok, f = pcall(function() return o[k] end)
	if ok then return f end
end

local function pc(o, method, ...)    -- o:method(...) in a pcall: ok, results
	local f = fnOf(o, method)
	if type(f) ~= "function" then return false, "no " .. method end
	return pcall(f, o, ...)
end

local function val(o, method, ...)   -- o:method(...) as text for the log
	if o == nil then return "none" end
	local f = fnOf(o, method)
	if type(f) ~= "function" then return "MISSING" end
	local r = pack(pcall(f, o, ...))
	if not r[1] then return "ERROR(" .. Short(r[2], 70) .. ")" end
	if r.n < 2 then return "-" end
	local out = {}
	for i = 2, r.n do out[#out + 1] = S(r[i]) end
	return table.concat(out, ",")
end

local function plainNum(v) return not secret(v) and type(v) == "number" end

local function num(o, method, ...)   -- a plain number, else nil
	local ok, v = pc(o, method, ...)
	if ok and plainNum(v) then return v end
end

local function Quote(s)              -- a text for the log: newlines counted, long ones cut
	if secret(s) then return "<secret>" end
	if type(s) ~= "string" then return S(s) end
	local rest, nl = s:gsub("\n", "")
	local body = #rest > 14 and ("'..%s' (%d chars)"):format(rest:sub(-6), #rest) or ("'" .. rest .. "'")
	return nl > 0 and ("%d newlines + %s"):format(nl, body) or body
end

local function Read(o, method, ...)  -- the first result of o:method(...) quoted, or the error
	local ok, v = pc(o, method, ...)
	if not ok then return "ERROR(" .. Short(v, 50) .. ")" end
	return Quote(v)
end

local function List(v)               -- a plain table, else an empty one
	if not secret(v) and type(v) == "table" then return v end
	return {}
end

local function Frame(parent)         -- a frame of ours outside the game's buttons
	local ok, f = pcall(CreateFrame, "Frame", nil, parent, LAYOUT_SAFE)
	if ok and f then return f end
	if not R.reported.template then
		R.reported.template = true
		qlog("%s -> ERROR %s (plain frames used)", LAYOUT_SAFE, Short(f))
	end
	return CreateFrame("Frame", nil, parent)
end

---------------------------------------------------------------------------- pieces (made inside initializeFrame)
local function Square(parent, anchor, point, c, w, h, inset)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetSize(w or 10, h or 10)
	local i = inset or 2
	local dx = point:find("LEFT") and i or (point:find("RIGHT") and -i or 0)
	local dy = point:find("TOP") and -i or (point:find("BOTTOM") and i or 0)
	t:SetPoint(point, anchor, point, dx, dy)
	t:SetColorTexture(c[1], c[2], c[3], 1)
	return t
end

local function Clip(parent, level)   -- a frame that clips its children
	local c = CreateFrame("Frame", nil, parent)
	c:SetClipsChildren(true)
	c:SetFrameLevel(level)
	return c
end

local function Dot(parent, anchor, point, x, y, c, level, size)
	local d = CreateFrame("Frame", nil, parent)
	d:SetSize(size or 6, size or 6)
	d:SetPoint(point, anchor, point, x, y)
	d:SetFrameLevel(level)
	local t = d:CreateTexture(nil, "OVERLAY")
	t:SetAllPoints(d)
	t:SetColorTexture(c[1], c[2], c[3], 1)
	return d
end

local function Outline(f, c)         -- a 1 px frame around f
	for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" },
		{ "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetPoint(e[1], f, e[1])
		t:SetPoint(e[2], f, e[2])
		if e[1]:sub(1, 3) == e[2]:sub(1, 3) then t:SetHeight(1) else t:SetWidth(1) end
		t:SetColorTexture(c[1], c[2], c[3], 0.9)
	end
end

local function SetCurve(path, curve)
	local f = fnOf(path, "SetCurveType") or fnOf(path, "SetCurve")
	if f then f(path, curve) end
end

local function Points(path, list)
	local cps = {}
	for i, q in ipairs(list) do
		cps[i] = path:CreateControlPoint(nil, nil, i)
		cps[i]:SetOffset(q[1], q[2])
	end
	return cps
end

-- a dot (white unless c) circling r px around the centre of b once per 'period' s: a looping group of ours, never
-- handed over
local function Clock(b, size, r, period, level, c)
	local d = Dot(b, b, "CENTER", 0, r, c or COLOR.WHITE, level, size)
	local ag = d:CreateAnimationGroup()
	ag:SetLooping("REPEAT")
	local p = ag:CreateAnimation("Path")
	p:SetDuration(period)
	SetCurve(p, "NONE")
	local pts = {}
	for k = 1, 24 do
		local a = 2 * math.pi * k / 24
		pts[k] = { r * math.sin(a), r * math.cos(a) - r }   -- from 12 o'clock, clockwise, back to the start
	end
	Points(p, pts)
	return ag
end

-- a small gate text: invisible (unless /fdrowanim show), starting short ("0"), hung by ONE point SHIFT + M left of
-- anchor's bottom left and dy below it, so its end lies past the frame while wide and left of it while short
local function SmallGate(row, parent, anchor, dy)
	local fs = parent:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
	fs:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -SHIFT - M, dy)
	fs:SetTextColor(0.75, 0.75, 0.75, R.showGate and 1 or 0)
	fs:SetText("0")
	row.gates[#row.gates + 1] = fs
	return fs
end

-- the engine's gate text (GateText): 64 px, invisible, "0", hung 620 px left of the frame and 300 px below it
local function EngineGate(row, b)
	local fs = b:CreateFontString(nil, "BACKGROUND")
	fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", ENG.font, "")
	fs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -ENG.shift, -ENG.margin)
	fs:SetTextColor(1, 1, 1, 0)
	fs:SetText("0")
	row.gates[#row.gates + 1] = fs
	return fs
end

---------------------------------------------------------------------------- formatters and duration text options
local function Prop(name, default)
	local P = Enum and Enum.DurationTextBindingProperty
	return (P and P[name]) or default
end

local function Rules(rules)          -- a rule formatter (Down rounding), or nil and why
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil, "CreateNumericRuleFormatter is missing" end
	local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not f then return nil, "CreateNumericRuleFormatter -> ERROR " .. Short(f) end
	local RND = (Enum and Enum.NumericRuleFormatRounding) or {}
	local bps = {}
	for i, r in ipairs(rules) do bps[i] = { threshold = r[1], step = 1, rounding = RND.Down or 2, format = r[2] } end
	local okB, err = pc(f, "SetBreakpoints", bps)
	if not okB then return nil, "SetBreakpoints -> ERROR " .. Short(err) end
	return f
end

local function Sample(f, list)       -- FormatNumber at a few values, for the log (addon code may call it: /fdpair fmt)
	local out = {}
	for _, n in ipairs(list) do
		local ok, s = pc(f, "FormatNumber", n)
		out[#out + 1] = ("%s -> %s"):format(S(n), ok and Quote(s) or ("ERROR " .. Short(s, 40)))
	end
	return table.concat(out, ", ")
end

-- wide below x, the number from x: the engine's GateFormatter, tried as its ElapsedOptions tries it
local function Wide(x)
	if R.fmts[x] ~= nil then return R.fmts[x] or nil end
	R.fmts[x] = false
	for _, t in ipairs({ { -60, 60 }, { 0, 60 }, { -60, 30 }, { 0, 30 } }) do
		local f, why = Rules({ { t[1], ("W"):rep(t[2]) .. "%d" }, { x, "%d" } })
		if f then
			R.fmts[x] = f
			qlog("elapsed formatter X = %s (W's from %d, %d of them): %s", S(x), t[1], t[2],
				Sample(f, { -0.2, 0, x - 0.1, x, x + 5 }))
			return f
		end
		qlog("elapsed formatter X = %s with %d W's from %d: %s", S(x), t[2], t[1], why)
	end
	log("no elapsed formatter for X = %s: its rows get no gate", S(x))
	return nil
end

local function PlainOpts(x)          -- today's ElapsedOptions(x)
	local f = Wide(x)
	if not f then return nil end
	return { textFormat = { formatString = "{}", components = { { property = Prop("ElapsedDuration", 2), formatter = f } } } }
end

-- the planned fix: a binding of ours with a zero-duration text; inside = the format goes into the binding as well
-- (SetTextFormat), else into the options next to it. Every step logged. Returns the options, how they were made and
-- a note for the caption when SetTextFormat changed the zero text (it is then set again, so the row tests its caption)
local function ZeroOpts(key, x, zero, inside)
	local plain = PlainOpts(x)
	if not plain then return nil, "no formatter" end
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then
		log("%s: C_DurationUtil.CreateDurationTextBinding is missing: plain options (as Z0)", key)
		return plain, "plain: no binding API"
	end
	local ok, b = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok or not b then
		log("%s: CreateDurationTextBinding -> ERROR %s: plain options (as Z0)", key, Short(b))
		return plain, "plain: no binding"
	end
	R.bindings[key] = b
	local okZ, errZ = pc(b, "SetZeroDurationText", zero)
	local z0 = Read(b, "GetZeroDurationText")   -- read-backs are compared as their log text: plain strings
	qlog("%s: binding SetZeroDurationText('%s') -> %s, reads back %s", key, zero, okZ and "ok" or ("ERROR " .. Short(errZ)), z0)
	if not okZ then log("%s: SetZeroDurationText -> ERROR %s", key, Short(errZ)) end
	local tf = plain.textFormat
	if inside then
		local okF, errF = pc(b, "SetTextFormat", tf.formatString, tf.components)
		local z1 = Read(b, "GetZeroDurationText")
		qlog("%s: binding SetTextFormat('{}', elapsed) -> %s; zero text after it %s", key,
			okF and "ok" or ("ERROR " .. Short(errF)), z1)
		if okF then
			local how = ("binding, zero '%s', format inside"):format(zero)
			-- set again, so the row tests what its caption says; the engine's ElapsedOptions(x, true) sets the zero
			-- text before SetTextFormat only, so from here on this row is NOT the engine's order, and chat says so
			if okZ and z1 ~= z0 then
				local okA, errA = pc(b, "SetZeroDurationText", zero)
				local z2 = Read(b, "GetZeroDurationText")
				log("%s: SetTextFormat changed the binding's zero text (%s -> %s): set again after it -> %s, reads %s. "
					.. "That is not the engine's order (ElapsedOptions(x, true) sets it before SetTextFormat only): for "
					.. "%s's result to hold, the engine must set it after SetTextFormat too", key,
					z0, z1, okA and "ok" or ("ERROR " .. Short(errA)), z2, key)
				return { binding = b }, how .. ", zero set again", "SetTextFormat changed the zero text; set again: " .. z2
					.. " (the engine must too)"
			end
			return { binding = b }, how
		end
		log("%s: the binding took no format (%s): it goes in the options next to the binding", key, Short(errF))
	end
	return { binding = b, textFormat = tf }, ("binding, zero '%s', format in the options"):format(zero)
end

-- W2's text "{}{}": elapsed (NL empty lines below X, "" from X), then the time left (NW W's below T, the number from
-- T). Returns the options, and the same format inside a binding of ours to try if the options are refused.
local function TwoAxisOpts(T)
	local el, whyE = Rules({ { -60, R.lines:rep(NL) }, { X, "" } })
	if not el then log("W2: the elapsed part's formatter: %s (Q2: no)", whyE); return nil end
	qlog("W2 elapsed part: %s", Sample(el, { 0, X - 0.1, X, X + 3 }))
	local rem, whyR = Rules({ { -60, ("W"):rep(NW) .. "%d" }, { T, "%d" } })
	if not rem then log("W2: the time left part's formatter: %s", whyR); return nil end
	qlog("W2 time left part, T = %s: %s", S(T), Sample(rem, { T - 1, T, T + 1 }))
	local tf = { formatString = "{}{}", components = {
		{ property = Prop("ElapsedDuration", 2), formatter = el },
		{ property = Prop("RemainingDuration", 0), formatter = rem } } }
	local fallback
	if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		local ok, b = pcall(C_DurationUtil.CreateDurationTextBinding)
		local okF, errF = false, b
		if ok and b then okF, errF = pc(b, "SetTextFormat", tf.formatString, tf.components) end
		qlog("W2: a binding of ours SetTextFormat('{}{}', elapsed, time left) -> %s", okF and "ok" or ("ERROR " .. Short(errF)))
		if okF then R.bindings.W2 = b; fallback = { binding = b } end
	end
	return { textFormat = tf }, fallback
end

-- line height and widths in the small gates' font, on a text of ours outside the buttons
local function Meter()
	local f = Frame(R.root)
	f:SetSize(1, 1)
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT")
	f:SetAlpha(0)
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT")
	local function size(t)
		pc(fs, "SetText", t)
		return num(fs, "GetStringHeight"), num(fs, "GetStringWidth")
	end
	local m = {}
	m.h1, m.w0 = size("0")
	m.hN = size(("\n"):rep(NL) .. "1795")
	m.hS = size((NBSP .. "\n"):rep(NL) .. "1795")
	m.wZ = select(2, size(("W"):rep(60) .. "0"))
	m.wW = select(2, size(("W"):rep(NW) .. "1795"))
	f:Hide()
	return m
end

---------------------------------------------------------------------------- spells and auras (plain out of combat)
local function NewSet() return { set = {}, ids = {} } end

local function AddId(s, id)
	if plainNum(id) and not s.set[id] then s.set[id] = true; s.ids[#s.ids + 1] = id end
end

local function Aura(i)               -- your i-th HELPFUL aura's data, or nil
	local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
	if ok and not secret(a) and type(a) == "table" then return a end
end

local function AddName(s, name)      -- the spellbook's rank and whatever aura of that name is on you now
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		if ok and not secret(info) and type(info) == "table" then AddId(s, info.spellID) end
	end
	for i = 1, 40 do
		local a = Aura(i)
		if not a then break end
		if not secret(a.name) and a.name == name then AddId(s, a.spellId) end
	end
end

-- z: Z0-ZF and W2 (Demon Skin / Armor + Blood Pact); l: L (Demon Skin / Armor, Unending Breath, Detect
-- Invisibility; no Blood Pact: it would take the frame of a buff cancelled in step 6 at once, so that frame would
-- never hide); all: every one of them (the events watch these). Spells given by ID or name go into all three.
local function Sets(arg)
	local z, l, all = NewSet(), NewSet(), NewSet()
	if type(arg) == "table" then
		for _, id in ipairs(arg) do AddId(z, id); AddId(l, id); AddId(all, id) end
		return z, l, all, "spell ID(s) " .. table.concat(z.ids, ", ")
	elseif type(arg) == "string" then
		AddName(z, arg)
		AddName(l, arg)
		AddName(all, arg)
		return z, l, all, arg
	end
	for _, k in ipairs({ "armor", "pact", "breath", "detect" }) do
		local inZ, inL = k == "armor" or k == "pact", k ~= "pact"
		for _, id in ipairs(SPELLS[k].ids) do
			if inZ then AddId(z, id) end
			if inL then AddId(l, id) end
			AddId(all, id)
		end
		for _, name in ipairs(SPELLS[k].names) do
			if inZ then AddName(z, name) end
			if inL then AddName(l, name) end
			AddName(all, name)
		end
	end
	return z, l, all, "the warlock defaults"
end

local function Applied(a)            -- when the aura went on and its duration (plain values only), or nil
	local exp, dur = a.expirationTime, a.duration
	if plainNum(exp) and plainNum(dur) and dur > 0 and exp > 0 then return exp - dur, dur end
end

local function BuffDuration(set)     -- the duration of the first aura of 'set' on you that has one
	for i = 1, 40 do
		local a = Aura(i)
		if not a then return nil end
		local id, dur = a.spellId, a.duration
		if plainNum(id) and set[id] and plainNum(dur) and dur > SOON then return dur, S(a.name) end
	end
end

local function BuffsNow()            -- the probe's auras on you now, with their age
	if InCombatLockdown() then return "buffs: n/a in combat" end
	local out, n = {}, 0
	for i = 1, 40 do
		local a = Aura(i)
		if not a then break end
		n = n + 1
		local id = a.spellId
		if plainNum(id) and R.watch and R.watch[id] then
			local t0 = Applied(a)
			out[#out + 1] = t0 and ("%s %.1f s old"):format(S(a.name), GetTime() - t0) or (S(a.name) .. " (no duration)")
		end
	end
	return ("buffs: %s (%d in all)"):format(#out > 0 and table.concat(out, ", ") or "none of the probe's", n)
end

local function SeedInstances()       -- the probe's auras up at the build, so their removal can be timed
	for i = 1, 40 do
		local a = Aura(i)
		if not a then return end
		local id, inst = a.spellId, a.auraInstanceID
		if plainNum(id) and plainNum(inst) and R.watch[id] then
			R.inst[inst] = { name = S(a.name), t0 = (Applied(a)), z = R.zset[id] and true or false }
		end
	end
end

local function CountUp(set)          -- how many auras of 'set' are on you now
	local n = 0
	for i = 1, 40 do
		local a = Aura(i)
		if not a then break end
		if plainNum(a.spellId) and set[a.spellId] then n = n + 1 end
	end
	return n
end

local function Kind(a)               -- which default spell aura a is ("armor", "pact", "breath", "detect"), or nil
	local id, name = a.spellId, a.name
	for _, k in ipairs({ "armor", "pact", "breath", "detect" }) do
		if plainNum(id) then
			for _, x in ipairs(SPELLS[k].ids) do if x == id then return k end end
		end
		if not secret(name) and type(name) == "string" then
			for _, x in ipairs(SPELLS[k].names) do if x == name then return k end end
		end
	end
end

-- step 1's setup, read at the build (default spells, on step 1): Blood Pact up, the probe's other buffs off. Each
-- can be put right after the build, so it only says what to change.
local function SetupCheck()
	local up, pact = {}, false
	for i = 1, 40 do
		local a = Aura(i)
		if not a then break end
		local k = Kind(a)
		if k == "pact" then pact = true elseif k then up[#up + 1] = S(a.name) end
	end
	if #up > 0 then
		log("setup: cancel %s now (step 1 has them off: the Z rows then show Blood Pact, and L's frames come one at a "
			.. "time in step 5)", table.concat(up, ", "))
	end
	if not pact then log("setup: no Blood Pact on you: summon the Imp (the Z rows need it)") end
	if #up == 0 and pact then qlog("setup as step 1 wants: Blood Pact up, the probe's other buffs off") end
end

---------------------------------------------------------------------------- rows
local function NewRow(key, caption, capRight, small)
	local p = PLACE[key]
	local host = Frame(R.root)
	host:SetSize(SIZE, SIZE)
	host:SetPoint("TOPLEFT", UIParent, "CENTER", p[1], p[2])
	local box = host:CreateTexture(nil, "BACKGROUND")   -- where the row's first frame sits (ours, not a button)
	box:SetAllPoints(host)
	box:SetColorTexture(0.5, 0.5, 0.5, 0.2)
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	if capRight then cap:SetPoint("LEFT", host, "RIGHT", 8, 0) else cap:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 4) end
	cap:SetJustifyH("LEFT")
	cap:SetText(caption)
	local row = { key = key, host = host, cap = cap, caption = caption, small = small, items = {}, gates = {},
		inits = 0, batches = {} }
	R.rows[key] = row
	R.order[#R.order + 1] = row
	return row
end

-- the row's container with its one aura group (sorted by expiration, soonest first); init(row, button) makes a frame
local function Group(row, set, maxN, init, spacing, lineSize)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, row.host, "CustomAuraContainerTemplate")
	if not ok or not c then log("%s: container -> ERROR %s", row.key, Short(c)); return end
	row.c, row.maxN = c, maxN
	R.containers[#R.containers + 1] = c
	pc(c, "SetPoint", "TOPLEFT", row.host, "TOPLEFT")
	pc(c, "SetFrameLevel", (num(row.host, "GetFrameLevel") or 1) + 2)
	if lineSize then
		local okL, errL = pc(c, "SetFlowLayoutMaximumLineSize", lineSize)
		qlog("%s: SetFlowLayoutMaximumLineSize(%d) -> %s", row.key, lineSize, okL and "ok" or ("ERROR " .. Short(errL)))
	end
	local okU, errU = pc(c, "SetUnit", "player")
	if not okU then log("%s: SetUnit(player) -> ERROR %s", row.key, Short(errU)) end
	local SM, SD = AuraContainerSortMethod, AuraContainerSortDirection
	local okG, errG = pc(c, "AddAuraGroup", "fdrowanim" .. row.key, "HELPFUL", {
		candidateFilters = set and { includeSpellIDs = set } or nil,
		maxFrameCount = maxN,
		sortMethod = SM and SM.ExpirationOnly,
		sortDirection = SD and SD.Normal,
		layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = spacing or 4, lineSpacing = 4 },
		initializeFrame = function(b)
			local okI, errI = pcall(init, row, b)
			if not okI then Bug(row.key .. " initializeFrame", errI) end
		end,
	})
	row.added = okG and true or false
	qlog("%s: AddAuraGroup(HELPFUL, %s, max %d) -> %s", row.key, set and "the probe's spells" or "every buff", maxN,
		okG and "ok" or ("ERROR " .. Short(errG, 200)))
	if not okG then log("%s: AddAuraGroup -> ERROR %s", row.key, Short(errG)) end
end

-- one frame: its number in the row, its batch (the game makes 10 at a time) and whether it logs every step
local function Begin(row, b)
	row.inits = row.inits + 1
	local n = row.inits
	local it = { b = b, n = n, batch = math.floor((n - 1) / 10) + 1, first = (n - 1) % 10 == 0 }
	row.items[n] = it
	local bt = row.batches[it.batch]
	if not bt then
		bt = { from = n, count = 0, combat = InCombatLockdown() and true or false, ok = {}, fail = {}, err = {}, order = {} }
		row.batches[it.batch] = bt
		-- a batch the game makes after the build (frames 11+, maybe in combat): its line in chat a frame later
		if R.built then Later(0, "batch line", function() BatchLine(row, it.batch, true) end) end
	end
	bt.count = bt.count + 1
	it.bt = bt
	return it
end

-- one step of a frame's build in a pcall, counted per batch; the batch's first frame logs every step with the
-- combat flag, the others only their first refusal of each step
local function Step(row, it, label, fn)
	local bt = it.bt
	if not bt.ok[label] then
		bt.ok[label], bt.fail[label] = 0, 0
		bt.order[#bt.order + 1] = label
	end
	local ok, err = pcall(fn)
	if ok then bt.ok[label] = bt.ok[label] + 1 else bt.fail[label] = bt.fail[label] + 1 end
	if it.first or (not ok and not bt.err[label]) then
		qlog("%s #%d [combat %s] %s -> %s", row.key, it.n, S(InCombatLockdown()), label, ok and "ok" or ("ERROR " .. Short(err, 200)))
	end
	if not ok and not bt.err[label] then bt.err[label] = Short(err, 100) end
	return ok
end

local function SizeAndIcon(row, it, b, parent)
	return Step(row, it, "size + icon", function()
		b:SetSize(SIZE, SIZE)
		pcall(b.SetMouseClickEnabled, b, false)
		pcall(b.EnableMouseMotion, b, false)
		it.icon = parent:CreateTexture(nil, "ARTWORK")
		it.icon:SetAllPoints(parent)
		b:SetIcon(it.icon)
	end)
end

-- the button's duration text: the row's options, else its fallback (the row then says so)
local function DurationText(row, it, b, what)
	if row.opts and Step(row, it, what .. ": " .. S(row.how), function() b:SetDurationText(it.fs, row.opts) end) then
		return true
	end
	if row.fallback and Step(row, it, what .. ": " .. S(row.fallbackHow), function() b:SetDurationText(it.fs, row.fallback) end) then
		row.fellBack = true
		return true
	end
	return false
end

-- Z: the icon on the button; the gate text with the row's options; ORANGE in the fresh clip, BLUE in the settled one
local function InitZ(row, b)
	local it = Begin(row, b)
	local lvl = num(b, "GetFrameLevel") or 1
	SizeAndIcon(row, it, b, b)
	if not Step(row, it, "gate text", function() it.fs = SmallGate(row, b, b, -M) end) then return end
	if not DurationText(row, it, b, "elapsed text") then return end
	Step(row, it, "fresh clip + ORANGE", function()
		it.fresh = Clip(b, lvl + 2)
		it.fresh:SetPoint("TOPLEFT", b, "TOPLEFT", -M, PADT)
		it.fresh:SetPoint("BOTTOMRIGHT", it.fs, "BOTTOMRIGHT")
		Square(it.fresh, b, "TOPRIGHT", COLOR.ORANGE)
	end)
	Step(row, it, "settled clip + BLUE", function()
		it.settled = Clip(b, lvl + 2)
		it.settled:SetPoint("BOTTOMLEFT", it.fs, "BOTTOMRIGHT")
		it.settled:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		Square(it.settled, b, "TOPLEFT", COLOR.BLUE)
	end)
end

-- W2: the text hangs one line and a bit below the frame, so one line high its top edge lies below the frame and
-- NL + 1 lines high far above it; ORANGE / BLUE hang on that top edge, GREEN / GREY on the text's end inside BLUE
local function InitW2(row, b)
	local it = Begin(row, b)
	local lvl = num(b, "GetFrameLevel") or 1
	SizeAndIcon(row, it, b, b)
	if not Step(row, it, "gate text", function() it.fs = SmallGate(row, b, b, -(M + R.lineH + 6)) end) then return end
	if not DurationText(row, it, b, "two-part text") then return end
	Step(row, it, "fresh clip + ORANGE (top edge)", function()
		it.fresh = Clip(b, lvl + 2)
		it.fresh:SetPoint("TOPLEFT", it.fs, "TOPLEFT")
		it.fresh:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", M, -M)
		Square(it.fresh, b, "TOPRIGHT", COLOR.ORANGE)
	end)
	if not Step(row, it, "settled clip + BLUE (top edge)", function()
		it.settled = Clip(b, lvl + 2)
		it.settled:SetPoint("BOTTOMLEFT", it.fs, "TOPLEFT")
		it.settled:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		Square(it.settled, b, "TOPLEFT", COLOR.BLUE)
	end) then return end
	Step(row, it, "late clip + GREEN (end, in BLUE)", function()
		it.late = Clip(it.settled, lvl + 3)
		it.late:SetPoint("TOPLEFT", b, "TOPLEFT", -M, M)
		it.late:SetPoint("BOTTOMRIGHT", it.fs, "BOTTOMRIGHT")
		Square(it.late, b, "BOTTOMRIGHT", COLOR.GREEN)
	end)
	Step(row, it, "early clip + GREY (end, in BLUE)", function()
		it.early = Clip(it.settled, lvl + 3)
		it.early:SetPoint("BOTTOMLEFT", it.fs, "BOTTOMRIGHT")
		it.early:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		Square(it.early, b, "BOTTOMLEFT", COLOR.GREY)
	end)
end

-- L: mover 1 (shake) holds the icon, the gate and BLUE, a tight clip with YELLOW at its right edge and the two dots;
-- mover 2 (pulse) holds a white outline and a tight clip with YELLOW at its left edge; two clocks on the button
local function InitL(row, b)
	local it = Begin(row, b)
	local lvl = num(b, "GetFrameLevel") or 1
	if not Step(row, it, "mover 1", function()
		it.m1 = CreateFrame("Frame", nil, b)
		it.m1:SetAllPoints(b)
		it.m1:SetFrameLevel(lvl + 1)
	end) then return end
	SizeAndIcon(row, it, b, it.m1)
	if Step(row, it, "gate text on mover 1", function() it.fs = SmallGate(row, it.m1, it.m1, -M) end)
		and DurationText(row, it, b, "elapsed text") then
		Step(row, it, "settled clip + BLUE on mover 1", function()
			it.settled = Clip(it.m1, lvl + 2)
			it.settled:SetPoint("BOTTOMLEFT", it.fs, "BOTTOMRIGHT")
			it.settled:SetPoint("TOPRIGHT", it.m1, "TOPRIGHT", M, M)
			Square(it.settled, it.m1, "TOPLEFT", COLOR.BLUE)
		end)
	end
	Step(row, it, "tight clip 1 + YELLOW", function()
		it.tight1 = Clip(it.m1, lvl + 2)
		it.tight1:SetAllPoints(it.m1)
		Square(it.tight1, it.tight1, "RIGHT", COLOR.YELLOW, 10, 16, 0)
	end)
	Step(row, it, "dots: cyan on mover 1, magenta on the button", function()
		it.dot1 = Dot(it.m1, it.m1, "BOTTOMLEFT", 5, 4, COLOR.CYAN, lvl + 3)
		it.dot2 = Dot(it.m1, b, "BOTTOMLEFT", 15, 4, COLOR.MAGENTA, lvl + 3)
	end)
	Step(row, it, "shake loop + Play", function()
		local ag = it.m1:CreateAnimationGroup()
		ag:SetLooping("REPEAT")
		local p = ag:CreateAnimation("Path")
		p:SetDuration(1)
		SetCurve(p, "NONE")
		Points(p, { { 10, 0 }, { 0, 0 }, { -10, 0 }, { 0, 0 } })
		it.shake = ag
		ag:Play()
	end)
	if Step(row, it, "mover 2: outline + tight clip 2 + YELLOW", function()
		it.m2 = CreateFrame("Frame", nil, b)
		it.m2:SetAllPoints(b)
		it.m2:SetFrameLevel(lvl + 4)
		Outline(it.m2, COLOR.WHITE)
		it.tight2 = Clip(it.m2, lvl + 5)
		it.tight2:SetAllPoints(it.m2)
		Square(it.tight2, it.tight2, "LEFT", COLOR.YELLOW, 10, 16, 0)
	end) then
		Step(row, it, "pulse loop + Play", function()
			local ag = it.m2:CreateAnimationGroup()
			ag:SetLooping("BOUNCE")
			local s = ag:CreateAnimation("Scale")
			s:SetDuration(0.5)
			s:SetScaleFrom(1, 1)
			s:SetScaleTo(1.3, 1.3)
			s:SetOrigin("CENTER", 0, 0)
			it.pulse = ag
			ag:Play()
		end)
	end
	Step(row, it, "big clock + Play()", function()
		it.c1 = Clock(b, 6, 12, 4, lvl + 6)
		it.c1:Play()
	end)
	-- GREEN (L has no late clip): half a turn on, a white dot that fell 2 s behind would sit where the others' small
	-- dots are, so a same-coloured small dot would make it look in step
	if not Step(row, it, "small clock + Play(false, 2)", function()
		it.c2 = Clock(b, 4, 12, 4, lvl + 6, COLOR.GREEN)
		it.c2:Play(false, 2)
	end) and it.c2 then
		Step(row, it, "small clock + Play() (fallback)", function() it.c2:Play() end)
	end
end

-- B2's start group, as the engine's NewGroup: Alpha, Scale and a Path of samples + 1 points, all on the copy
local function NewRig(it, b, target)
	local ag = b:CreateAnimationGroup()
	local function new(kind)
		local a = ag:CreateAnimation(kind)
		a:SetTarget(target)
		return a
	end
	it.alpha, it.scale, it.path = new("Alpha"), new("Scale"), new("Path")
	SetCurve(it.path, "NONE")
	it.cps = {}
	for i = 1, ENG.samples + 1 do it.cps[i] = it.path:CreateControlPoint(nil, nil, i) end
	it.ag = ag
end

local function SetRig(it, spec)      -- the engine's SetRig: setters only
	it.alpha:SetDuration(spec.d)
	it.alpha:SetFromAlpha(spec.a0)
	it.alpha:SetToAlpha(spec.a1)
	it.scale:SetDuration(spec.d)
	it.scale:SetScaleFrom(1, 1)
	it.scale:SetScaleTo(1, 1)
	it.scale:SetOrigin("CENTER", 0, 0)
	it.path:SetDuration(spec.d)
	for i, cp in ipairs(it.cps) do
		local q = spec.pts[i] or spec.pts[#spec.pts]
		cp:SetOffset(q[1], q[2])
	end
end

-- B2: the Stage 2 copy frame (the engine's BuildStartSlot rig without the host), BLUE settled, and a clock
local function InitB2(row, b)
	local it = Begin(row, b)
	local lvl = num(b, "GetFrameLevel") or 1
	Step(row, it, "size + grey box", function()
		b:SetSize(SIZE, SIZE)
		pcall(b.SetMouseClickEnabled, b, false)
		pcall(b.EnableMouseMotion, b, false)
		local bg = b:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(b)
		bg:SetColorTexture(0.35, 0.35, 0.35, 0.45)
	end)
	if not Step(row, it, "gate text (the engine's)", function() it.fs = EngineGate(row, b) end) then return end
	if not Step(row, it, "fresh clip + layer", function()
		it.fresh = Clip(b, lvl + 1)
		it.fresh:SetPoint("TOPLEFT", b, "TOPLEFT", -ENG.margin, ENG.margin)
		it.fresh:SetPoint("BOTTOMRIGHT", it.fs, "BOTTOMRIGHT")
		it.layer = CreateFrame("Frame", nil, it.fresh)
		it.layer:SetAllPoints(b)
		it.layer:SetFrameLevel(lvl + 2)
	end) then return end
	Step(row, it, "copy: icon, swipe, count", function()
		it.icon = it.layer:CreateTexture(nil, "ARTWORK")
		it.icon:SetAllPoints(it.layer)
		it.cd = CreateFrame("Cooldown", nil, it.layer, "CooldownFrameTemplate")
		it.cd:SetAllPoints(it.icon)
		pcall(it.cd.SetDrawBling, it.cd, false)
		pcall(it.cd.SetHideCountdownNumbers, it.cd, true)
		it.count = it.layer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		it.count:SetPoint("BOTTOMRIGHT", it.layer, "BOTTOMRIGHT", -2, 2)
	end)
	Step(row, it, "fed by the game: SetIcon, SetDurationCooldown, SetApplicationCount", function()
		b:SetIcon(it.icon)
		b:SetDurationCooldown(it.cd)
		b:SetApplicationCount(it.count, nil)
	end)
	local okR = Step(row, it, "start group (Alpha, Scale, Path of 21 points) + setters", function()
		NewRig(it, b, it.layer)
		SetRig(it, SLIDE)
	end)
	local okT = DurationText(row, it, b, "elapsed text")
	if okR and okT then Step(row, it, "hand-over (AddAuraShownAnimation)", function() b:AddAuraShownAnimation(it.ag) end) end
	Step(row, it, "settled clip + BLUE", function()
		it.settled = Clip(b, lvl + 1)
		it.settled:SetPoint("BOTTOMLEFT", it.fs, "BOTTOMRIGHT")
		it.settled:SetPoint("TOPRIGHT", b, "TOPRIGHT", ENG.margin, ENG.margin)
		Square(it.settled, b, "TOPLEFT", COLOR.BLUE)
	end)
	Step(row, it, "clock + Play()", function()
		it.clock = Clock(b, 5, 9, 2, lvl + 5)
		it.clock:Play()
	end)
end

-- the steps of one batch: in the log always; in chat for a later batch (frames 11+) and whenever one was refused
BatchLine = function(row, k, loud)
	local bt = row.batches[k]
	if not bt or bt.reported then return end
	bt.reported = true
	local parts, bad, first = {}, 0, nil
	for _, label in ipairs(bt.order) do
		local okN, failN = bt.ok[label], bt.fail[label]
		parts[#parts + 1] = ("%s %d/%d"):format(label, okN, okN + failN)
		if failN > 0 then
			bad = bad + 1
			first = first or ("'%s' %d/%d: %s"):format(Short(label, 30), okN, okN + failN, Short(bt.err[label], 45))
		end
	end
	local head = ("%s batch %d (frames %d-%d, combat %s)"):format(row.key, k, bt.from, bt.from + bt.count - 1, S(bt.combat))
	qlog("%s: %s", head, table.concat(parts, ", "))
	if bad > 0 then
		log("%s batch %d (%d-%d, combat %s) refused %d: %s", row.key, k, bt.from, bt.from + bt.count - 1, S(bt.combat), bad, first)
	elseif loud then
		log("%s: all %d steps ok on %d frames", head, #bt.order, bt.count)
	end
end

local function RowState(row)         -- "Z0 10 ok" for the build's chat line
	if not row.added then return row.key .. " FAILED" end
	local bad = 0
	for _, bt in pairs(row.batches) do
		for _, n in pairs(bt.fail) do bad = bad + n end
	end
	local n = num(row.c, "GetAuraGroupFrameCount", "fdrowanim" .. row.key)
	return ("%s %s%s"):format(row.key, n and S(n) or "?", bad > 0 and (" (%d refused)"):format(bad) or " ok")
end

---------------------------------------------------------------------------- reading the clocks
local function Elapsed(ag)
	local ok, v = pc(ag, "GetElapsed")
	if ok and plainNum(v) then return v end
end

local function Spread(vals, period)  -- how far apart values on a circle of 'period' s lie (0 = all in step)
	if #vals < 2 then return 0 end
	local s = {}
	for i, v in ipairs(vals) do s[i] = v % period end
	table.sort(s)
	local gap = s[1] + period - s[#s]
	for i = 2, #s do
		if s[i] - s[i - 1] > gap then gap = s[i] - s[i - 1] end
	end
	return period - gap
end

-- 0.5 s after the build: do the loops play, and did Play(false, 2) take? On the frame the game hands out first, which
-- shows only if a buff of L's was up at the build (step 1 has none: then 'phase' in step 6 reads frames that show)
local function LateCheck()
	local L = R.root and R.rows.L
	local it = L and L.items[#L.items]
	if not it then return end
	local state = (R.lUp or 0) > 0 and "shown" or "hidden: no buff of L's up"
	qlog("L #%d (%s) 0.5 s after the build: shake playing %s, pulse playing %s, big clock at %s s, small clock at %s s",
		it.n, state, val(it.shake, "IsPlaying"), val(it.pulse, "IsPlaying"), val(it.c1, "GetElapsed"), val(it.c2, "GetElapsed"))
	local e1, e2 = Elapsed(it.c1), Elapsed(it.c2)
	if e1 and e2 then
		log("L #%d (%s): the small clock runs %.2f s ahead of the big one (2.00 = Play(false, 2) works)", it.n, state,
			(e2 - e1) % 4)
	else
		log("L: the clocks' GetElapsed: %s / %s", val(it.c1, "GetElapsed"), val(it.c2, "GetElapsed"))
	end
end

---------------------------------------------------------------------------- the build
Build = function(arg)
	if R.root then say("already built: /fdrowanim hide first (/fdrowanim alone shows the current step)"); return end
	if InCombatLockdown() then say("build it OUT OF COMBAT: the game guards its aura frames in combat."); return end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
		log("C_StringUtil.CreateNumericRuleFormatter or C_UnitAuras.GetAuraDataByIndex is missing: nothing built")
		return
	end
	R.reported, R.rows, R.order, R.containers, R.bindings, R.fmts, R.inst = {}, {}, {}, {}, {}, {}, {}
	R.built = false
	local z, lset, all, what = Sets(arg)
	if #z.ids == 0 then say(("no spell ID found for %s: /fdrowanim <spellIDs> or /fdrowanim <buff name>"):format(what)); return end
	R.watch, R.zset = all.set, z.set
	R.lUp = CountUp(lset.set)
	local okB, _, bld = pcall(GetBuildInfo)
	log("[run] build %s, out of combat, spells: %s", okB and S(bld) or "?", what)
	qlog("spell IDs of Z0-ZF and W2 (Demon Skin / Armor, Blood Pact by default): %s", table.concat(z.ids, ","))
	qlog("spell IDs of L (Demon Skin / Armor, Unending Breath, Detect Invisibility by default; %d up now): %s", R.lUp,
		table.concat(lset.ids, ","))
	R.root = Frame(UIParent)
	R.root:SetAllPoints(UIParent)
	local m = Meter()
	R.lineH = m.h1 or 14
	qlog("small gate font: one line %s px high, %d lines %s px (with a no-break space on each: %s px); '0' %s px wide, "
		.. "60 W's %s px, %d W's %s px", S(m.h1), NL + 1, S(m.hN), S(m.hS), S(m.w0), S(m.wZ), NW, S(m.wW))
	-- W2's elapsed part: empty lines, or lines holding a no-break space if only those make the text taller
	local need = SIZE + 2 * M + 12
	R.lines = "\n"
	if m.h1 and m.hN and m.hN - m.h1 < need then
		if m.hS and m.hS - m.h1 >= need then
			R.lines = NBSP .. "\n"
			log("W2: empty lines add no height (%s px), lines with a no-break space do (%s px): W2 uses those",
				S(m.hN - m.h1), S(m.hS - m.h1))
		else
			log("W2: %d lines are only %s px taller than one: its ORANGE may never open", NL + 1, S(m.hN - m.h1))
		end
	end
	if m.wZ and m.wZ < SHIFT + 2 * M + SIZE then log("Z, L: 60 W's are only %s px wide: their ORANGE may never open", S(m.wZ)) end
	local dur, dname = BuffDuration(z.set)
	R.T = (dur or ARMOR_DUR) - SOON
	qlog("W2: T = %s s (%s)", S(R.T), dur and (("%s lasts %s s, read now"):format(dname, S(dur)))
		or "no buff of its set is up: Demon Skin / Armor's 30 min assumed")
	SeedInstances()

	local head = R.root:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	head:SetPoint("BOTTOMLEFT", UIParent, "CENTER", PLACE.Z0[1], PLACE.Z0[2] + 8)
	head:SetText("Z: the frame Blood Pact gets back - BLUE top left = clean, ORANGE top right = stale")
	for _, s in ipairs({
		{ "Z0", "Z0  elapsed text as today" },
		{ "ZB", "ZB  zero text '0', format in the binding (the fix)", "0", true },
		{ "ZE", "ZE  zero text '', format in the binding", "", true },
		{ "ZF", "ZF  zero text '0', format in the options", "0", false },
	}) do
		local row = NewRow(s[1], s[2], true, true)
		if s[3] then
			row.opts, row.how, row.zeroNote = ZeroOpts(s[1], X, s[3], s[4])
			row.fallback, row.fallbackHow = PlainOpts(X), "plain (fallback)"
			row.noBinding = row.opts and not row.opts.binding
		else
			row.opts, row.how = PlainOpts(X), "plain"
		end
		qlog("%s: %s", row.key, S(row.how))
		Group(row, z.set, 1, InitZ)
	end
	local w2 = NewRow("W2", "W2  elapsed + time left in one text: ORANGE 2 s, then BLUE + GREY, GREEN from 5 s", false, true)
	w2.opts, w2.fallback = TwoAxisOpts(R.T)
	w2.how, w2.fallbackHow = "textFormat '{}{}'", "'{}{}' in a binding (fallback)"
	if w2.opts then Group(w2, z.set, 2, InitW2, 8) end
	local l = NewRow("L", "L  shaking icon, pulsing outline: YELLOW cut = clip stays put; cyan dot on the mover,\n"
		.. "magenta on the button; white clock Play(), green clock Play(false, 2)", false, true)
	l.opts, l.how = PlainOpts(X), "plain"
	Group(l, lset.set, 3, InitL, 30)
	local b2 = NewRow("B2", "B2  every buff, 20 frames: the copy slides down, BLUE after 1 s; frames 11-20 come later", false, false)
	b2.opts, b2.how, b2.zeroNote = ZeroOpts("B2", SLIDE.x, "0", true)
	b2.fallback, b2.fallbackHow = PlainOpts(SLIDE.x), "plain (fallback)"
	b2.noBinding = b2.opts and not b2.opts.binding
	Group(b2, nil, 20, InitB2, 4, 10 * SIZE + 9 * 4)
	R.built = true

	local parts = {}
	for _, row in ipairs(R.order) do
		for k in pairs(row.batches) do BatchLine(row, k, false) end
		parts[#parts + 1] = RowState(row)
		local last = row.items[#row.items]
		local note = (last and not (last.fresh or last.settled)) and "  [NO GATE: see the log]" or ""
		if row.noBinding then note = note .. "  [no binding: plain options]" end
		if row.zeroNote then note = note .. "  [" .. row.zeroNote .. "]" end
		if row.fellBack then
			note = note .. "  [fell back: " .. S(row.fallbackHow) .. "]"
			log("%s FELL BACK to %s: its frames show what that gives", row.key, S(row.fallbackHow))
		end
		if note ~= "" then pc(row.cap, "SetText", row.caption .. note) end
	end
	log("built (frames per row): %s", table.concat(parts, ", "))
	local nb = 0
	for i = 1, 40 do if Aura(i) then nb = i else break end end
	if nb > 10 then log("B2: %d buffs on you now, so its frames 11+ come out of combat; for Q4 build with 10 or fewer", nb) end
	pcall(R.ev.RegisterEvent, R.ev, "PLAYER_REGEN_DISABLED")
	pcall(R.ev.RegisterEvent, R.ev, "PLAYER_REGEN_ENABLED")
	pcall(R.ev.RegisterUnitEvent, R.ev, "UNIT_FLAGS", "player")
	pcall(R.ev.RegisterUnitEvent, R.ev, "UNIT_AURA", "player")
	Later(0.5, "late check", LateCheck)
	if arg == nil and (tonumber(DB().rowAnimStep) or 1) <= 1 then SetupCheck() end
	ShowStep()
end

---------------------------------------------------------------------------- the probe's auras on you (out of combat)
local function Added(t, a)
	if secret(a) or type(a) ~= "table" then return end
	local id, inst = a.spellId, a.auraInstanceID
	if not (plainNum(id) and plainNum(inst) and R.watch[id]) then return end
	local t0, dur = Applied(a)
	R.inst[inst] = { name = S(a.name), t0 = t0, z = R.zset[id] and true or false }
	log("t=%.1f %s ADDED (%s)", t, S(a.name), dur and (S(dur) .. " s") or "no duration")
	if dur and R.zset[id] and R.T and math.abs(dur - SOON - R.T) > 0.5 then
		log("W2's T is %s s but %s lasts %s s: for W2, hide and build again with it up", S(R.T), S(a.name), S(dur))
	end
end

local function Updated(t, inst)
	if not (plainNum(inst) and R.inst[inst]) then return end
	local rec = R.inst[inst]
	local getter = C_UnitAuras.GetAuraDataByAuraInstanceID
	local t0
	if getter then
		local ok, a = pcall(getter, "player", inst)
		if ok and not secret(a) and type(a) == "table" then t0 = (Applied(a)) end
	end
	if not t0 or (rec.t0 and math.abs(t0 - rec.t0) < 0.05) then
		qlog("t=%.1f %s updated (%s)", t, rec.name, t0 and "same start" or "no duration read")
		return
	end
	rec.t0 = t0
	log("t=%.1f %s REFRESHED (an update, no new show): its gates open again for %d s", t, rec.name, X)
end

local function Removed(t, inst)
	if not (plainNum(inst) and R.inst[inst]) then return end
	local rec = R.inst[inst]
	R.inst[inst] = nil
	local age = rec.t0 and (t - rec.t0)
	if not age then
		log("t=%.1f %s REMOVED", t, rec.name)
	elseif rec.z and age < X then
		log("t=%.1f %s REMOVED at %.1f s, its gate open: read the Z rows now (ORANGE = stale, BLUE = clean)", t, rec.name, age)
	elseif rec.z then
		log("t=%.1f %s REMOVED at %.1f s, its gate already shut (for Z: cancel within %d s of a cast)", t, rec.name, age, X)
	else
		log("t=%.1f %s REMOVED at %.1f s", t, rec.name, age)
	end
end

local function AuraEvent(t, info)
	if InCombatLockdown() then R.auraN = (R.auraN or 0) + 1; return end   -- the contents are closed in combat
	if secret(info) or type(info) ~= "table" then return end
	local full = info.isFullUpdate
	if not secret(full) and full then
		if not (R.lastFull and t - R.lastFull < 0.25) then R.lastFull = t; qlog("t=%.1f UNIT_AURA: full update on you", t) end
		return
	end
	for _, a in ipairs(List(info.addedAuras)) do Added(t, a) end
	for _, inst in ipairs(List(info.updatedAuraInstanceIDs)) do Updated(t, inst) end
	for _, inst in ipairs(List(info.removedAuraInstanceIDs)) do Removed(t, inst) end
end

local function OnEvent(event, ...)
	if not R.root then return end
	local t = GetTime()
	if event == "UNIT_AURA" then
		AuraEvent(t, select(2, ...))
	elseif event == "PLAYER_REGEN_DISABLED" then
		R.auraN = 0
		log("t=%.1f COMBAT START, the game redraws the rows: W2 no ORANGE flash? L clocks no jump?", t)
	elseif event == "PLAYER_REGEN_ENABLED" then
		log("t=%.1f COMBAT END, the game redraws the rows: W2 no ORANGE flash? L clocks no jump?", t)
		if (R.auraN or 0) > 0 then qlog("%d UNIT_AURA on you in combat (contents closed)", R.auraN) end
		R.auraN = 0
	elseif event == "UNIT_FLAGS" then
		if R.lastFlags and t - R.lastFlags < 0.25 then return end
		R.lastFlags = t
		qlog("t=%.1f UNIT_FLAGS on you: the game rebuilds the rows", t)
	end
end

R.ev = CreateFrame("Frame")
R.ev:SetScript("OnEvent", function(_, event, ...)
	local ok, err = pcall(OnEvent, event, ...)
	if not ok then Bug(event, err) end
end)

---------------------------------------------------------------------------- the steps (chat)
local STEPS = {
	{ "Setup", {
		"Out of combat with .gm off (the fights in steps 2, 4, 6 and 7 must be real combat), Imp out (Blood Pact);",
		"Demon Armor, Unending Breath, Detect Invisibility off",
		"(the build checked this: any 'setup:' line above says what to change; no new build needed).",
		"Z0, ZB, ZE, ZF show Blood Pact with BLUE (top left). ORANGE (top right) = stale already.",
		"A Z row without any square: its text is empty (ZE's ''; on Z0 or ZF the game blanked the text of an aura",
		"without a duration), and an empty text gives its clips no size. /fdrowanim next",
	} },
	{ "Z rows: a reused frame's old text (Q1)", {
		"Cast Demon Armor: each Z row shows it, ORANGE for 2 s, then BLUE.",
		"Cast it again, cancel it within 2 s (chat tells its age): Blood Pact gets that frame back.",
		"Each Z row now: ORANGE = the old text stayed (stale), BLUE = clean.",
		"Z0 ORANGE + ZB BLUE = the fix works. ZF ORANGE + ZB BLUE = the options' format resets the zero text.",
		"(Did the build say 'SetTextFormat changed the binding's zero text'? Then ZB set it again after the format,",
		"and the fix works only in that order: the engine must change.)",
		"Once more in combat on a dummy (no age in chat then). /fdrowanim note <what you saw>, then next",
	} },
	{ "Reset by the addon (Q5)", {
		"Z0 not ORANGE after the cancel in step 2 (BLUE, or no square)? Nothing stale to reset: /fdrowanim next.",
		"Make Z0 stale again (step 2, out of combat), then /fdrowanim reset (it touches Z0's gate texts only).",
		"Chat: how many gate texts took SetText. Z0 turning BLUE = our SetText clears a stale text.",
		"Then cast Demon Armor: Z0 ORANGE for 2 s, then BLUE = the game still writes that text after our reset.",
		"BLUE at once = our SetText cut the game off (a reset would break the gate; Z0 stays so until a new build).",
		"/fdrowanim note <what you saw>, then next",
	} },
	{ "W2: two gates in one text (Q2)", {
		"Cancel Demon Armor, cast it and watch W2's first frame:",
		"0-2 s only ORANGE (top right); 2-5 s BLUE (top left) + GREY (bottom left); from 5 s BLUE + GREEN.",
		"At about 10 s pull a dummy, then let combat end: no ORANGE flash either time.",
		"In a fight: cancel, cast again: the same order?",
		"Out of combat: /fdrowanim show shows the gate texts (W2's is 13 lines tall in its first 2 s; show again",
		"hides them). /fdrowanim next",
	} },
	{ "L: a frame that moves (Q3)", {
		"Put up Demon Armor, Unending Breath and Detect Invisibility: L shows three frames.",
		"Shaking icon: its YELLOW (right edge) cut off at times = clips stay put.",
		"Magenta dot standing still while cyan shakes = anchors must go on the mover.",
		"BLUE (top left) from 2 s, also while shaking. Pulsing outline: its YELLOW (left edge) cut?",
		"/fdrowanim next",
	} },
	{ "L: clocks (Q3)", {
		"White dots in step on all three frames? Green dots opposite them (half a turn on = the Play offset works)?",
		"/fdrowanim phase. Cancel one buff (its frame stays empty), wait about 1 s, cast it again: its white dot",
		"with the others' (in step), or behind? /fdrowanim phase again. The phase lines decide, not the eye:",
		"the never-shown frames (1-7) the same in both readings = loops stand still while hidden; changed = they run.",
		"Pull a dummy, let combat end: do the clocks jump? /fdrowanim next",
	} },
	{ "B2: frames made in combat (Q4)", {
		"B2 shows every buff on you. Its frames 11-20 are made when an 11th buff comes, and that must happen in combat.",
		"Out of combat: F1 (target yourself: .aura goes on your target), .aura buffs with a duration until B2 shows 10",
		"icons, e.g. 1243 1126 1459 976 14752 19740 15366 22888 (a buff without a duration shows no copy).",
		"Then pull a mob that keeps hitting you (.gm off; Imp on passive, so the fight lasts), F1 again, .aura one or two",
		"more. Chat must then say 'B2 batch 2 (... 11-20, combat true)': 'all ... steps ok', or which one was refused.",
		"New icons: does each copy slide down into place, then leave a grey box with BLUE after 1 s?",
		"'combat false' (the 11th came out of combat)? hide, cancel buffs to 10 or fewer, build again, redo this step.",
		"/fdrowanim next",
	} },
	{ "Done", {
		"Out of combat: /fdrowanim dump, /fdrowanim hide, then /reload.",
		"Send ForeverDevInfoDB.rowAnimProbe (your notes are in it) and what you saw.",
	} },
}

local function StepNo()
	local n = tonumber(DB().rowAnimStep) or 1
	if n < 1 then n = 1 elseif n > #STEPS then n = #STEPS end
	return n
end

ShowStep = function()
	local n = StepNo()
	say(("step %d/%d: %s"):format(n, #STEPS, STEPS[n][1]))
	for _, line in ipairs(STEPS[n][2]) do say("  " .. line) end
end

---------------------------------------------------------------------------- commands
local function ShowGates()
	local want = not R.showGate
	if not R.root then
		R.showGate = want
		say(("show: the gate texts will be built %s"):format(want and "VISIBLE" or "invisible"))
		return
	end
	if InCombatLockdown() then say("show: out of combat only (the game guards its frames in combat)"); return end
	R.showGate = want                -- also what the next build uses, should the game refuse the change now
	local okN, n, first = 0, 0, nil
	for _, row in ipairs(R.order) do
		if row.small then
			for _, fs in ipairs(row.gates) do
				n = n + 1
				local ok, err = pc(fs, "SetTextColor", 0.75, 0.75, 0.75, want and 1 or 0)
				if ok then okN = okN + 1 else first = first or Short(err) end
			end
		end
	end
	log("show: gate texts of Z, W2 and L %s, %d of %d took it%s", want and "VISIBLE" or "invisible", okN, n,
		first and ("; first error: " .. first) or "")
	if want and okN > 0 then say("Each starts left of its frame: W's = gate open; W2's is 13 lines tall in its first 2 s.") end
	if n > 0 and okN == 0 then say("Refused: /fdrowanim hide and build again: the gate texts are then made visible.") end
end

local function Kick()
	if not R.root then say("kick: not built (/fdrowanim first)"); return end
	local okN = 0
	for _, c in ipairs(R.containers) do
		if pc(c, "UpdateAllAuras") then okN = okN + 1 end
	end
	log("t=%.1f kick (combat %s): UpdateAllAuras on %d of %d rows, the game's full rebuild", GetTime(),
		S(InCombatLockdown()), okN, #R.containers)
	qlog("  %s", BuffsNow())
end

-- Q5 reads Z0 only, so only Z0's gate texts get our SetText: should it cut the game off, the gates of the rows read
-- in steps 4-7 (W2, L, B2) and of the other Z rows stay as the game writes them
local function Reset()
	if not R.root then say("reset: not built (/fdrowanim first)"); return end
	if InCombatLockdown() then say("reset: out of combat only (the game guards its frames in combat)"); return end
	local gates = R.rows.Z0 and R.rows.Z0.gates or {}
	local okN, first = 0, nil
	for _, fs in ipairs(gates) do
		local ok, err = pc(fs, "SetText", "0")
		if ok then okN = okN + 1 else first = first or Short(err) end
	end
	log("reset (addon SetText) on Z0's gate texts only, no other row's: %d/%d%s", okN, #gates,
		first and ("; first error: " .. first) or "; no error")
	if okN > 0 then
		say("A stale ORANGE that turned BLUE now = our SetText clears it (Q5). Now cast Demon Armor: Z0 ORANGE for 2 s")
		say("= the game still writes the text after our reset; BLUE at once = the reset cut the game off (Z0 then stays")
		say("so until a new build; the other rows were not touched).")
	end
end

-- L's clocks on frames i..j: the big ones, the small ones and small - big as text, and the plain values
local function Clocks(items, i, j)
	local big, small, diff, v1, v2 = {}, {}, {}, {}, {}
	for k = i, j do
		local e1, e2 = Elapsed(items[k].c1), Elapsed(items[k].c2)
		big[#big + 1] = e1 and ("%.2f"):format(e1) or "?"
		small[#small + 1] = e2 and ("%.2f"):format(e2) or "?"
		if e1 then v1[#v1 + 1] = e1 end
		if e2 then v2[#v2 + 1] = e2 end
		if e1 and e2 then diff[#diff + 1] = ("%.2f"):format((e2 - e1) % 4) end
	end
	return table.concat(big, " "), table.concat(small, " "), #diff > 0 and table.concat(diff, " ") or "n/a", v1, v2
end

local function Phase()
	if not R.root then say("phase: not built (/fdrowanim first)"); return end
	if InCombatLockdown() then say("phase: out of combat only (the game guards its frames in combat)"); return end
	local L, B = R.rows.L, R.rows.B2
	local n = L and #L.items or 0
	if n > 0 then
		-- the game hands out the frames made last first (a LIFO pool), so with at most maxN auras only the last maxN
		-- frames ever show: those are compared with each other; the others have stayed hidden since the build
		local first = n - math.min(L.maxN or 3, n) + 1
		local big, small, diff, v1, v2 = Clocks(L.items, first, n)
		log("phase t=%.1f, L frames %d-%d (the ones the game hands out; a hidden frame's clock may lag):", GetTime(), first, n)
		log("  big clocks %s (spread %.2f s of 4)", big, Spread(v1, 4))
		log("  small clocks %s (spread %.2f s)", small, Spread(v2, 4))
		log("  small - big %s (2.00 = half a turn)", diff)
		if #v1 == 0 then log("  GetElapsed: %s", val(L.items[n].c1, "GetElapsed")) end
		if first > 1 then
			local big0, small0, _, v0 = Clocks(L.items, 1, first - 1)
			local all = {}
			for _, v in ipairs(v0) do all[#all + 1] = v end
			for _, v in ipairs(v1) do all[#all + 1] = v end
			log("  frames 1-%d, never shown: big %s, small %s", first - 1, big0, small0)
			log("  all %d big clocks: spread %.2f s (about 0 = loops run on hidden frames too; 1-%d as at the last phase = "
				.. "they stand still)", #all, Spread(all, 4), first - 1)
		end
	end
	local b2, per, top = {}, {}, 0
	for _, it in ipairs(B and B.items or {}) do
		local e = Elapsed(it.clock)
		b2[#b2 + 1] = e and ("%.2f"):format(e) or "?"
		if e then
			per[it.batch] = per[it.batch] or {}
			per[it.batch][#per[it.batch] + 1] = e
			if it.batch > top then top = it.batch end
		end
	end
	qlog("  B2 clocks (2 s turn) %s", table.concat(b2, " "))
	local parts = {}
	for k = 1, top do
		if per[k] then parts[#parts + 1] = ("batch %d: %d read, spread %.2f s"):format(k, #per[k], Spread(per[k], 2)) end
	end
	if #parts > 0 then log("  B2 clocks of 2 s, %s (frames that never showed may stand still)", table.concat(parts, "; ")) end
end

local function Piece(name, o)
	return ("%s shown %s visible %s rect %s"):format(name, val(o, "IsShown"), val(o, "IsVisible"), val(o, "GetRect"))
end

local function DumpItem(row, it)
	qlog("%s #%d: %s", row.key, it.n, Piece("button", it.b))
	if it.fs then
		qlog("  gate text %s, width %s, height %s, rect %s", Read(it.fs, "GetText"), val(it.fs, "GetStringWidth"),
			val(it.fs, "GetStringHeight"), val(it.fs, "GetRect"))
	end
	for _, k in ipairs({ "fresh", "settled", "late", "early", "layer", "m1", "tight1", "dot1", "dot2", "m2", "tight2" }) do
		if it[k] then qlog("  %s", Piece(k, it[k])) end
	end
	for _, k in ipairs({ "shake", "pulse", "c1", "c2", "clock" }) do
		if it[k] then qlog("  %s playing %s, at %s s", k, val(it[k], "IsPlaying"), val(it[k], "GetElapsed")) end
	end
end

local function Dump()
	if not R.root then say("dump: not built (/fdrowanim first)"); return end
	local combat = InCombatLockdown()
	log("dump t=%.1f, combat %s%s. %s", GetTime(), S(combat), combat and " (the game refuses most reads now)" or "", BuffsNow())
	for key, b in pairs(R.bindings) do
		qlog("binding %s: zero text %s, update interval %s, can format %s, enabled %s", key, Read(b, "GetZeroDurationText"),
			val(b, "GetUpdateInterval"), val(b, "CanFormatText"), val(b, "IsEnabled"))
	end
	for _, row in ipairs(R.order) do
		local nb = 0
		for _ in pairs(row.batches) do nb = nb + 1 end
		qlog("%s: %s%s; frames made %s in %d batch(es); W2's T %s s", row.key, S(row.how),
			row.fellBack and (" -> FELL BACK to " .. S(row.fallbackHow)) or "",
			val(row.c, "GetAuraGroupFrameCount", "fdrowanim" .. row.key), nb, S(R.T))
		-- the game hands out the frames made last first (a LIFO pool): with at most maxN auras only the last maxN
		-- frames ever show, so the last of those (up to 3) are the ones worth reading
		local keep = math.min(3, row.maxN or 3)
		for i = #row.items, math.max(1, #row.items - keep + 1), -1 do DumpItem(row, row.items[i]) end
	end
	log("dump: %d lines in ForeverDevInfoDB.rowAnimProbe so far", #DB().rowAnimProbe)
end

local function Remove()
	if not R.root then say("hide: nothing built"); return end
	if not InCombatLockdown() then     -- our own loops stop (in combat the game guards them, the hide is enough)
		for _, row in ipairs(R.order) do
			for _, it in ipairs(row.items) do
				for _, k in ipairs({ "shake", "pulse", "c1", "c2", "clock" }) do
					if it[k] then pc(it[k], "Stop") end
				end
			end
		end
	end
	for _, c in ipairs(R.containers) do
		pc(c, "SetUnit", nil)
		pc(c, "Hide")
	end
	pc(R.root, "Hide")
	pcall(R.ev.UnregisterAllEvents, R.ev)
	R.root, R.rows, R.order, R.containers, R.built = nil, nil, nil, nil, false
	log("removed (a /reload clears it completely)")
end

local function GoStep(n)            -- a new step, also as a mark in the log
	DB().rowAnimStep = n
	qlog("---- step %d: %s (combat %s)", StepNo(), STEPS[StepNo()][1], S(InCombatLockdown()))
	ShowStep()
end

local COMMANDS = {
	next = function() GoStep(StepNo() + 1) end,
	back = function() GoStep(StepNo() - 1) end,
	step = function(rest) GoStep(tonumber(rest) or StepNo()) end,
	steps = function()
		for i, s in ipairs(STEPS) do say(("%s%d. %s"):format(i == StepNo() and "> " or "  ", i, s[1])) end
	end,
	show = ShowGates, kick = Kick, reset = Reset, phase = Phase, dump = Dump, hide = Remove,
	note = function(rest) log("NOTE (step %d): %s", StepNo(), rest) end,
	help = function()
		say("/fdrowanim [IDs or name], next, back, step n, steps, show, kick, reset, phase, dump, note x, hide")
	end,
}

SLASH_FDROWANIM1 = "/fdrowanim"
SlashCmdList.FDROWANIM = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	local fn = COMMANDS[(cmd or ""):lower()]
	local ok, err = pcall(function()
		if fn then
			fn(rest or "")
		elseif msg == "" then
			if R.root then ShowStep() else Build(nil) end
		elseif R.root then
			say(("unknown '%s' (/fdrowanim help)"):format(msg))
		else
			local ids = {}
			for w in msg:gmatch("%d+") do ids[#ids + 1] = tonumber(w) end
			Build(#ids > 0 and ids or msg)
		end
	end)
	if not ok then Bug("/fdrowanim " .. msg, err) end
end
