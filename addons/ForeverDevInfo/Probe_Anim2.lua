--[[ Forever Dev Info - /fdanim2 [spellID ... | buff name]: can a TIME GATE stop our start and finish animations
     from playing again every time the game rebuilds its aura buttons?

     What /fdanim showed: the aura button plays our animation (AddAuraShownAnimation) every time it goes from
     hidden to shown, also in combat. But every UNIT_FLAGS on you (combat start, combat end and a couple more
     per fight) makes the game rebuild the whole container: every button is hidden and shown again at once.
     So a start animation plays again, and a Missing icon's finish copy flashes while the buff is up (the
     "ghost").

     The idea tested here: let the animation be seen only during the first X seconds after the buff was put
     on. Each button gets an invisible duration text that shows the buff's ELAPSED time (how long it has been
     up), written very wide during the first X seconds and short afterwards (the text-width gate of /fdtgate,
     but counting up). Two clip frames inside the button hang on the end of that text:
       the FRESH clip   is open only while the text is wide (the first X seconds),
       the SETTLED clip is open only while the text is short (after X seconds).
     The animated icon copy lives in the fresh clip, a still copy in the settled clip. When you cast the buff,
     the animation plays in the open fresh clip; at X seconds the still copy takes over (the animation is
     over by then, so nothing jumps). When the game rebuilds later, the animation plays again inside the
     closed fresh clip, where nobody can see it.

     Build it OUT OF COMBAT. Default buff: your Demon Skin / Demon Armor (every rank); or give spell IDs or the
     name of any self-buff you can cast and cancel. Five icons appear side by side above the screen centre.
     The grey box behind each is where the icon rests and the label above it is ours (not part of any button).

       E   start, gated (X = 1 s): fades in while sliding in from 60 px to the right, 0.6 s.
       E2  the same with X = 3 s and a slow 2 s slide. A small square in its top-right corner tells which copy
           you see: ORANGE = the animated copy (fresh clip), BLUE = the still copy (settled clip). It should
           slide in orange and turn blue at 3 s without the icon moving.
       E0  control: the same start as E with no gate (like /fdanim A). Expected to replay at every rebuild.
       F   Missing, gated (X = 1 s): the buff's icon (grey/red) while the buff is MISSING. When you cast the
           buff, a copy slides up 40 px and fades out (0.8 s). That copy lives in the fresh clip.
       F0  control: the same with no gate (= /fdanim D). Expected to flash (the ghost) at every rebuild.

     What to do (chat notes every combat start/end, every rebuild and every change of the buff):
       1. Buff OFF, out of combat: /fdanim2. Only F and F0 show something (the missing icon).
       2. Cast the buff: E, E2 and E0 slide in, F and F0 slide up and fade out. E2's square turns from orange
          to blue at 3 s. Does E or E2 blink for a moment right when the buff lands? (tell if so)
       3. Wait 5 s. Hit a mob or a target dummy, then leave combat. At the pull and at the end E0 should replay
          and F0 should flash (known). E, E2 and F must stay still: no replay, no flash.
       4. Buff up, out of combat: /fdanim2 kick (the same full rebuild, by hand). Same as step 3.
       5. Buff up: cast it again (a refresh). Nothing should play anywhere (the buttons stay shown). E2's square
          turns orange again for 3 s: a refresh restarts the elapsed time, so the gate opens again, which is
          harmless because the copy is at rest. Chat says whether the game saw the cast as an UPDATE (a refresh)
          or as REMOVED + ADDED (a new aura: then the start may play again, visibly, since its gate is open).
       6. Cancel the buff and cast it again: E, E2, E0, F and F0 all play again. Also try it once in combat.
       7. Optional, out of combat: /fdanim2 show makes E's gate text visible, starting left of E at its bottom:
          a long row of W's during the first second after the buff went on, then plain counting seconds.
          /fdanim2 show again hides it.
       8. Optional, an aura WITHOUT a duration, e.g. your mount: /fdanim2 hide, then /fdanim2 Felsteed (or its
          spell ID), then mount up. The game switches the elapsed text off for such an aura, so the text should
          stay empty. An empty text is zero wide, so its end sits left of the button: the "short" side. Expected:
          E and E2 show the still copy at once with no animation, E0 animates; F's finish does not show, F0's
          does. If E and E2 stay EMPTY instead, an empty text does not count as short (the clips then have no
          valid size). Tell what you saw.
       9. Out of combat, buff up: /fdanim2 dump, then /fdanim2 hide, /reload and send ForeverDevInfoDB.anim2Probe
          plus what you saw.
     Building it with the buff already UP is a test too: E0 plays at once, E, E2 and F should not (the buff is
     already older than X).

     /fdanim2 kick   UpdateAllAuras on the probe's containers (a full rebuild)
     /fdanim2 show   E's gate text visible / invisible again
     /fdanim2 dump   shown / alpha / place of every piece, and how old the buff is (most of it reads
                     <secret>: the game hides it from addons; what you SEE is the result)
     /fdanim2 hide   removes it
     Everything is logged to ForeverDevInfoDB.anim2Probe (and printed). The file must be listed in the .toc.
]]

local ap = { reported = {} }
local SIZE, COL, ROWY, M = 40, 120, 200, 6
local SHIFT, PADT = 80, 50   -- the gate text starts SHIFT + M left of the button; the fresh clip reaches PADT above it
local LAYOUT_SAFE = "DisableUntrustedLayoutScriptsTemplate"
local DEFAULT = {
	{ "Demon Skin", { 687, 696 } },
	{ "Demon Armor", { 706, 1086, 11733, 11734, 11735, 27260 } },
}
local ev = CreateFrame("Frame")

local function secret(v) return issecretvalue and issecretvalue(v) end

local function show(v)
	if secret(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function alog(fmt, ...)
	local okF, line = pcall(string.format, fmt, ...)
	if select("#", ...) == 0 then line = fmt elseif not okF then line = fmt .. " (format error: " .. show(line) .. ")" end
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.anim2Probe = ForeverDevInfoDB.anim2Probe or {}
	local l = ForeverDevInfoDB.anim2Probe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 800 do table.remove(l, 1) end
	print("|cff33ff99FDI anim2|r " .. line)
end

local function pack(...) return { n = select("#", ...), ... } end

-- o[k] without an error when o is nil or refuses the read
local function fnOf(o, k)
	if o == nil then return nil end
	local ok, f = pcall(function() return o[k] end)
	return ok and f or nil
end

-- pcall fn, log the outcome (in quiet mode only the first error per label); returns ok, results...
local function try(label, fn, ...)
	if type(fn) ~= "function" then
		if not (ap.quiet and ap.reported[label]) then ap.reported[label] = true; alog("%s -> MISSING (%s)", label, type(fn)) end
		return false
	end
	local r = pack(pcall(fn, ...))
	if r[1] then
		if not ap.quiet then alog("%s -> ok", label) end
	elseif not (ap.quiet and ap.reported[label]) then
		ap.reported[label] = true
		alog("%s -> ERROR %s", label, show(r[2]))
	end
	return unpack(r, 1, r.n)
end

local function call(label, o, method, ...)
	return try(label, fnOf(o, method), o, ...)
end

-- o:method(...) as text, for the log
local function val(o, method, ...)
	if o == nil then return "none" end
	local f = fnOf(o, method)
	if type(f) ~= "function" then return "MISSING" end
	local r = pack(pcall(f, o, ...))
	if not r[1] then return "ERROR(" .. show(r[2]) .. ")" end
	if r.n < 2 then return "-" end
	local out = {}
	for i = 2, r.n do
		local v = r[i]
		if type(v) == "number" and not secret(v) then out[#out + 1] = ("%.2f"):format(v) else out[#out + 1] = show(v) end
	end
	return table.concat(out, ",")
end

-- a gate text's content, short: "'12'" or "...WWW0 (wide, 61 chars)"
local function textOf(fs)
	if not fs then return "none" end
	local ok, s = pcall(function() return fs:GetText() end)
	if not ok then return "ERROR(" .. show(s) .. ")" end
	if secret(s) then return "<secret>" end
	if type(s) ~= "string" then return show(s) end
	if #s > 16 then return ("...%s (wide, %d chars)"):format(s:sub(-6), #s) end
	return "'" .. s .. "'"
end

local function Frame(parent)
	local ok, f = pcall(CreateFrame, "Frame", nil, parent, LAYOUT_SAFE)
	if ok and f then return f end
	if not ap.reported.template then ap.reported.template = true; alog("%s -> ERROR %s (plain frames used)", LAYOUT_SAFE, show(f)) end
	return CreateFrame("Frame", nil, parent)
end

-- one column: a grey box where the icon rests and a label above it, both outside any aura button
local function column(i, caption)
	local host = Frame(ap.root)
	host:SetSize(SIZE, SIZE)
	host:SetPoint("CENTER", UIParent, "CENTER", (i - 3) * COL, ROWY)
	local box = host:CreateTexture(nil, "BACKGROUND")
	box:SetPoint("TOPLEFT", -1, 1)
	box:SetPoint("BOTTOMRIGHT", 1, -1)
	box:SetColorTexture(0.5, 0.5, 0.5, 0.3)
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("BOTTOM", host, "TOP", 0, 6)
	cap:SetText(caption)
	return host
end

-- animation helpers (called inside try)
local function anim(ag, kind, target, duration)
	local a = ag:CreateAnimation(kind)
	if target then a:SetTarget(target) end
	a:SetDuration(duration)
	return a
end

local function setCurve(path, curve)
	local f = fnOf(path, "SetCurveType") or fnOf(path, "SetCurve")
	if f then f(path, curve) end
end

local function points(path, list)
	for i, p in ipairs(list) do
		local cp = path:CreateControlPoint(nil, nil, i)
		cp:SetOffset(p[1], p[2])
	end
end

-- jump 60 px right, then come back in 23 eased steps (as /fdanim A)
local function slidePath(ag, target, duration)
	local path = anim(ag, "Path", target, duration)
	setCurve(path, "NONE")
	local pts = { { 60, 0 } }
	for k = 1, 23 do
		local f = 1 - k / 23
		pts[#pts + 1] = { 60 * f * f, 0 }
	end
	points(path, pts)
end

local function missingLook(t)
	t:SetTexture(ap.iconFile)
	pcall(t.SetDesaturated, t, true)
	t:SetVertexColor(1, 0.45, 0.45, 1)
end

local function marker(parent, anchor, r, g, b)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetSize(10, 10)
	t:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -2, -2)
	t:SetColorTexture(r, g, b, 1)
end

-- the spell IDs: given IDs, or a name / the default names resolved by the spellbook, plus every listed
-- rank, plus whatever buff of that name is on you now (all plain out of combat)
local function spellSet(arg)
	local set, ids, names = {}, {}, {}
	local function add(id)
		if type(id) == "number" and not secret(id) and not set[id] then set[id] = true; ids[#ids + 1] = id end
	end
	local function byName(name)
		names[#names + 1] = name
		if C_Spell and C_Spell.GetSpellInfo then
			local ok, info = pcall(C_Spell.GetSpellInfo, name)
			if ok and type(info) == "table" then add(info.spellID) end
		end
		if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
			for i = 1, 40 do
				local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
				if not ok or type(a) ~= "table" then break end
				if not secret(a.name) and a.name == name then add(a.spellId) end
			end
		end
	end
	if type(arg) == "table" then
		for _, id in ipairs(arg) do add(id) end
		names[1] = "spell ID(s)"
	elseif type(arg) == "string" then
		byName(arg)
	else
		for _, e in ipairs(DEFAULT) do
			for _, id in ipairs(e[2]) do add(id) end
			byName(e[1])
		end
	end
	return set, ids, table.concat(names, " / ")
end

-- the buff's aura data (plain only out of combat)
local function buffNow(set)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or type(a) ~= "table" then return end
		local id = a.spellId
		if not secret(id) and set[id] then return a end
	end
end

local function plain(v) return type(v) == "number" and not secret(v) end

-- how old the buff is: "12.3 s old (of 1800 s)", "no duration", ...
local function ageText(a)
	if not a then return "not on you" end
	local exp, dur = a.expirationTime, a.duration
	if not (plain(exp) and plain(dur)) then return "on you, age unreadable" end
	if exp <= 0 or dur <= 0 then return "on you, NO duration" end
	return ("on you, %.1f s old (of %.0f s)"):format(GetTime() - (exp - dur), dur)
end

-- the same for the probe's buff now (its spell ID is secret in combat)
local function buffAge()
	if InCombatLockdown() then return "n/a in combat" end
	return ageText(buffNow(ap.set))
end

local function iconFor(ids, auraIcon)
	if auraIcon and not secret(auraIcon) then return auraIcon end
	if C_Spell and C_Spell.GetSpellTexture then
		for _, id in ipairs(ids) do
			local ok, t = pcall(C_Spell.GetSpellTexture, id)
			if ok and t and not secret(t) then return t end
		end
	end
	return 134400
end

--------------------------------------------------------------------------------------------------
-- The gate's formatter: a row of W's .. "%d" below X seconds, "%d" from X up (one per X, shared by the
-- buttons). The wide rule starts below 0 if the game takes that, in case the elapsed time reads a hair under 0.
local function formatter(x)
	if ap.fmts[x] then return ap.fmts[x] end
	local ok, f = pcall(C_StringUtil.CreateNumericRuleFormatter)
	if not ok or not f then alog("CreateNumericRuleFormatter -> ERROR %s", show(f)); return nil end
	local R = (Enum and Enum.NumericRuleFormatRounding) or {}
	local down = R.Down or 2
	-- tried in turn: the wide rule from -60, then from 0; 60 W's, then 30 (still far past the slide's
	-- +60 px) in case the game refuses a long format
	local low, nW, done
	for _, t in ipairs({ { -60, 60 }, { 0, 60 }, { -60, 30 }, { 0, 30 } }) do
		low, nW = t[1], t[2]
		local okB, err = pcall(function()
			f:SetBreakpoints({
				{ threshold = low, step = 1, rounding = down, format = string.rep("W", nW) .. "%d" },
				{ threshold = x, step = 1, rounding = down, format = "%d" },
			})
		end)
		if okB then done = true; break end
		alog("formatter X=%s: wide rule from %d with %d W's -> ERROR %s", show(x), low, nW, show(err))
	end
	if not done then alog("formatter X=%s: every try refused, so no gate", show(x)); return nil end
	local out = {}
	for _, n in ipairs({ -0.2, 0, x - 0.1, x, x + 5 }) do
		local okF, s = pcall(function() return f:FormatNumber(n) end)
		local txt
		if not okF then txt = "ERROR " .. show(s)
		elseif secret(s) then txt = "<secret>"
		elseif type(s) == "string" and #s > 16 then txt = ("wide (%d chars)"):format(#s)
		else txt = "'" .. show(s) .. "'" end
		out[#out + 1] = ("%g -> %s"):format(n, txt)
	end
	alog("formatter X=%s (wide rule from %d, %d W's): %s", show(x), low, nW, table.concat(out, " | "))
	ap.fmts[x] = f
	return f
end

-- The time gate inside button b: the elapsed text (invisible, hung by ONE point SHIFT + M left of b, so its end
-- lies past b's right edge while wide and left of b while short) and the clips on that end. Everything is
-- anchored here, in initializeFrame (anchors inside a button are refused once it shows an aura).
-- Returns { fs, fresh, settled } or nil.
local function gate(key, b, x, withSettled)
	local f = formatter(x)
	if not f then return nil end
	local g = {}
	if not try(("%s gate text (invisible, one point %d px left of the button)"):format(key, SHIFT + M), function()
		g.fs = b:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
		g.fs:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -M - SHIFT, -M)
		g.fs:SetTextColor(0.75, 0.75, 0.75, (key == "E" and ap.showGate) and 1 or 0)
	end) then return nil end
	local comps = { { property = ap.prop, formatter = f } }
	local how = "textFormat"
	local ok = call(("%s SetDurationText(textFormat '{}' = ElapsedDuration, X = %s s)"):format(key, show(x)), b,
		"SetDurationText", g.fs, { textFormat = { formatString = "{}", components = comps } })
	if not ok and C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
		how = "a binding of ours"
		local okB, bnd = pcall(C_DurationUtil.CreateDurationTextBinding)
		ok = okB and bnd and call(key .. " fallback: binding of ours SetTextFormat(ElapsedDuration)", bnd, "SetTextFormat", "{}", comps)
		if ok then ok = call(key .. " fallback: SetDurationText({ binding = ours })", b, "SetDurationText", g.fs, { binding = bnd }) end
	end
	ap.gateHow[key] = ok and how or "REFUSED"
	if not ok then
		if not ap.quiet then alog("%s: the game took no elapsed text, so %s has no gate", key, key) end
		return nil
	end
	try(key .. " fresh clip (button top-left to the text's end: open while the text is wide)", function()
		g.fresh = CreateFrame("Frame", nil, b)
		g.fresh:SetClipsChildren(true)
		g.fresh:SetFrameLevel(b:GetFrameLevel() + 2)
		g.fresh:SetPoint("TOPLEFT", b, "TOPLEFT", -M, PADT)
		g.fresh:SetPoint("BOTTOMRIGHT", g.fs, "BOTTOMRIGHT", 0, 0)
	end)
	if withSettled then
		try(key .. " settled clip (the text's end to the button's top-right: open while the text is short)", function()
			g.settled = CreateFrame("Frame", nil, b)
			g.settled:SetClipsChildren(true)
			g.settled:SetFrameLevel(b:GetFrameLevel() + 2)
			g.settled:SetPoint("BOTTOMLEFT", g.fs, "BOTTOMRIGHT", 0, 0)
			g.settled:SetPoint("TOPRIGHT", b, "TOPRIGHT", M, M)
		end)
	end
	if not g.fresh or (withSettled and not g.settled) then return nil end
	return g
end

-- E, E2 (gated) and E0 (no gate): an animated layer holding an icon copy; the start group is made on the
-- button, aimed at the layer, and handed over. Gated: the layer sits in the fresh clip, a still copy in the
-- settled clip.
local function initStart(key)
	return function(b)
		local s = ap[key]
		s.b = b
		local home = b
		if s.x then
			local g = gate(key, b, s.x, true)
			if not g then alog("%s: no gate, so %s stays empty", key, key); return end
			s.fs, s.fresh, s.settled = g.fs, g.fresh, g.settled
			home = g.fresh
		end
		try(key .. " animated layer" .. (s.x and " in the fresh clip" or " (no clip)") .. " + icon copy", function()
			s.layer = CreateFrame("Frame", nil, home)
			s.layer:SetAllPoints(b)
			s.layer:SetFrameLevel(home:GetFrameLevel() + 1)
			local t = s.layer:CreateTexture(nil, "ARTWORK")
			t:SetAllPoints(s.layer)
			t:SetTexture(ap.iconFile)
			if s.markers then marker(s.layer, s.layer, 1, 0.55, 0.1) end
		end)
		if s.settled then
			try(key .. " still icon copy in the settled clip", function()
				local t = s.settled:CreateTexture(nil, "ARTWORK")
				t:SetAllPoints(b)
				t:SetTexture(ap.iconFile)
				if s.markers then marker(s.settled, b, 0.2, 0.5, 1) end
			end)
		end
		if not s.layer then return end
		local okG = try(("%s start group on the button, aimed at the layer (Alpha 0->1 %.1f s + Path from +60 px %.1f s)"):format(key, s.fade, s.slide), function()
			local ag = b:CreateAnimationGroup()
			local a = anim(ag, "Alpha", s.layer, s.fade)
			a:SetFromAlpha(0)
			a:SetToAlpha(1)
			slidePath(ag, s.layer, s.slide)
			s.ag = ag
		end)
		if okG then call(key .. " AddAuraShownAnimation", b, "AddAuraShownAnimation", s.ag) end
	end
end

-- F (gated) and F0 (no gate = /fdanim D): each of the Missing group's buttons (shown while the buff is UP) gets
-- a copy of the missing icon at alpha 0, hanging on the grey box, and a handed-over finish (Alpha 1->0 + Path
-- up 40 px, 0.8 s). Gated: the copy sits in the fresh clip, so it can only be seen during the first X s.
-- The game makes 10 group buttons at once and hands out the LAST one made first (and gets it back
-- first), so the button that holds the buff is s.items[#s.items], not #1.
local function initFinish(key)
	local function init(b)
		local s = ap[key]
		s.inits = s.inits + 1
		ap.quiet = s.inits > 1   -- the first of the pre-made buttons logs in full, the others only errors
		local it = { b = b }
		s.items[#s.items + 1] = it
		pcall(b.SetSize, b, SIZE + 1 + 2 * M, SIZE)
		pcall(b.SetMouseClickEnabled, b, false)
		local home = b
		if s.x then
			local g = gate(key, b, s.x, false)
			if not g then return end
			it.fs, it.fresh = g.fs, g.fresh
			home = g.fresh
		end
		local fin
		try(key .. " finish copy (alpha 0, hangs on the grey box)" .. (s.x and " in the fresh clip" or ""), function()
			fin = CreateFrame("Frame", nil, home)
			fin:SetAllPoints(s.host)
			fin:SetFrameLevel(math.max(s.host:GetFrameLevel() + 10, home:GetFrameLevel() + 1))
			fin:SetAlpha(0)
			local t = fin:CreateTexture(nil, "ARTWORK")
			t:SetAllPoints(fin)
			missingLook(t)
		end)
		if fin then
			local ag
			local okG = try(key .. " finish group (Alpha 1->0 + Path up 40 px, 0.8 s)", function()
				ag = b:CreateAnimationGroup()
				local a = anim(ag, "Alpha", fin, 0.8)
				a:SetFromAlpha(1)
				a:SetToAlpha(0)
				local p = anim(ag, "Path", fin, 0.8)
				setCurve(p, "NONE")
				points(p, { { 0, 20 }, { 0, 40 } })
			end)
			if okG then call(key .. " AddAuraShownAnimation", b, "AddAuraShownAnimation", ag) end
			s.fins[#s.fins + 1] = fin
			it.fin = fin
		end
	end
	return function(b)
		local ok, err = pcall(init, b)
		ap.quiet = false
		if not ok and not ap.reported[key .. " init"] then
			ap.reported[key .. " init"] = true
			alog("%s initializeFrame -> ERROR %s", key, show(err))
		end
	end
end

local function slot(c, key)
	local host = ap[key].host
	local init = initStart(key)
	local ok, b = pcall(c.AddAuraSlot, c, "fdanim2" .. key, "HELPFUL", {
		candidateFilters = { includeSpellIDs = ap.set },
		initializeFrame = function(btn)
			pcall(btn.ClearAllPoints, btn)
			pcall(btn.SetAllPoints, btn, host)
			pcall(btn.SetMouseClickEnabled, btn, false)
			local okI, err = pcall(init, btn)
			if not okI then alog("%s initializeFrame -> ERROR %s", key, show(err)) end
		end,
	})
	alog("%s AddAuraSlot -> %s", key, ok and "ok" or ("ERROR " .. show(b)))
end

local function buildMissing(key)
	local s = ap[key]
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, s.host, "CustomAuraContainerTemplate")
	if not ok or not c then alog("%s container -> ERROR %s", key, show(c)); return end
	s.c = c
	ap.containers[#ap.containers + 1] = c
	c:SetPoint("TOPLEFT", s.host, "TOPLEFT")
	call(key .. " SetUnit(player)", c, "SetUnit", "player")
	call(key .. " AddAuraGroup (Missing: max 1 frame)", c, "AddAuraGroup", "fdanim2" .. key, "HELPFUL", {
		candidateFilters = { includeSpellIDs = ap.set },
		maxFrameCount = 1,
		layout = { elementWidth = SIZE + 1 + 2 * M, elementHeight = SIZE },
		initializeFrame = initFinish(key),
	})
	ap.quiet = false
	alog("%s: %d group button(s) initialised, %d finish copies", key, s.inits, #s.fins)
	-- the Missing clip (ours, outside the buttons): open while the group is empty (container 1 px wide),
	-- shut once the group holds the buff (container SIZE + 1 + 2M wide)
	try(key .. " missing clip on the container's right edge", function()
		local clip = Frame(s.host)
		clip:SetClipsChildren(true)
		clip:SetFrameLevel(s.host:GetFrameLevel() + 3)
		clip:SetPoint("TOPLEFT", c, "TOPRIGHT", -1 - M, M)
		clip:SetPoint("BOTTOMRIGHT", s.host, "BOTTOMRIGHT", M, -M)
		local t = clip:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints(s.host)
		missingLook(t)
		s.clip = clip
	end)
end

local function gatesText()
	local h = ap.gateHow or {}
	return ("E %s, E2 %s, F %s"):format(h.E or "-", h.E2 or "-", h.F or "-")
end

-- what a new duration text binding does by default (how often it rewrites its text, its fallback texts)
local function bindingDefaults()
	if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then
		alog("C_DurationUtil.CreateDurationTextBinding is missing (defaults unknown)")
		return
	end
	local ok, bnd = pcall(C_DurationUtil.CreateDurationTextBinding)
	if not ok or not bnd then alog("CreateDurationTextBinding -> ERROR %s", show(bnd)); return end
	alog("a new duration text binding: update interval %s, zero-duration text %s, expired text %s",
		val(bnd, "GetUpdateInterval"), val(bnd, "GetZeroDurationText"), val(bnd, "GetExpiredText"))
end

local function build(arg)
	if ap.root then alog("already built - /fdanim2 hide first"); return end
	if InCombatLockdown() then alog("build it OUT OF COMBAT"); return end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		try("LoadAddOn(Blizzard_AuraContainer)", C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then alog("C_StringUtil.CreateNumericRuleFormatter is missing"); return end
	local set, ids, what = spellSet(arg)
	if #ids == 0 then alog("no spell ID found for %s: /fdanim2 <spellID> or /fdanim2 <buff name>", show(what)); return end
	local aura = buffNow(set)
	local P = Enum and Enum.DurationTextBindingProperty
	ap.set, ap.reported, ap.containers, ap.quiet, ap.fmts, ap.gateHow, ap.inst = set, {}, {}, false, {}, {}, {}
	ap.prop = P and P.ElapsedDuration or 2
	ap.iconFile = iconFor(ids, aura and aura.icon)
	if aura and plain(aura.auraInstanceID) then ap.inst[aura.auraInstanceID] = aura.spellId end
	local okB, _, bld = pcall(GetBuildInfo)
	alog("[run] build %s, %s = %s, buff %s, combat %s, ElapsedDuration = %s%s", okB and show(bld) or "?", what,
		table.concat(ids, ","), ageText(aura), show(InCombatLockdown()), show(ap.prop),
		P and "" or " (Enum.DurationTextBindingProperty missing: 2 used)")
	bindingDefaults()
	ap.root = Frame(UIParent)
	ap.root:SetAllPoints(UIParent)
	ap.E = { host = column(1, "E  gated 1 s"), x = 1, fade = 0.6, slide = 0.6 }
	ap.E2 = { host = column(2, "E2 gated 3 s"), x = 3, fade = 0.6, slide = 2, markers = true }
	ap.E0 = { host = column(3, "E0 ungated"), fade = 0.6, slide = 0.6 }
	ap.F = { host = column(4, "F  finish gated"), x = 1, inits = 0, fins = {}, items = {} }
	ap.F0 = { host = column(5, "F0 finish ungated"), inits = 0, fins = {}, items = {} }
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, ap.root, "CustomAuraContainerTemplate")
	if ok and c then
		ap.containers[#ap.containers + 1] = c
		pcall(c.SetSize, c, 1, 1)
		pcall(c.SetPoint, c, "CENTER", UIParent, "CENTER", 0, ROWY)
		pcall(c.SetFrameLevel, c, ap.root:GetFrameLevel() + 5)
		call("E-E0 SetUnit(player)", c, "SetUnit", "player")
		slot(c, "E")
		slot(c, "E2")
		slot(c, "E0")
	else
		alog("E-E0 container -> ERROR %s", show(c))
	end
	buildMissing("F")
	buildMissing("F0")
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_DISABLED")
	pcall(ev.RegisterUnitEvent, ev, "UNIT_FLAGS", "player")
	pcall(ev.RegisterUnitEvent, ev, "UNIT_FACTION", "player")
	pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
	alog("built. Elapsed text taken: %s. Cast / cancel the buff, fight; /fdanim2 kick, show, dump, hide (steps: header of Probe_Anim2.lua)", gatesText())
end

local function kick()
	if not ap.root then alog("kick: not built (/fdanim2 first)"); return end
	alog("t=%.1f kick (combat %s, buff %s): UpdateAllAuras = a full rebuild. E0 replays, F0 flashes; E, E2, F still?",
		GetTime(), show(InCombatLockdown()), buffAge())
	for i, c in ipairs(ap.containers or {}) do call("kick container " .. i .. " UpdateAllAuras", c, "UpdateAllAuras") end
end

-- E's gate text visible / invisible (it measures the time by its width, so only its colour may change)
local function toggleGate()
	local want = not ap.showGate
	local fs = ap.root and ap.E and ap.E.fs
	if not fs then
		ap.showGate = want
		alog("show: E's gate text will be built %s at the next /fdanim2", want and "VISIBLE" or "invisible")
		return
	end
	if InCombatLockdown() then alog("show: out of combat only (the game guards the buttons in combat)"); return end
	ap.showGate = want   -- also what the next build uses, if the game refuses the change now
	local a = want and 1 or 0
	if call(("E gate text SetTextColor(grey, alpha %d)"):format(a), fs, "SetTextColor", 0.75, 0.75, 0.75, a) then
		if want then
			alog("E's gate text sits at E's bottom left, starting %d px left of it: a long row of W's = the gate is open (the first %s s after the buff went on), plain seconds = shut", SHIFT + M, show(ap.E.x))
		end
	else
		alog("refused after the hand-over: /fdanim2 hide, then /fdanim2 again: E's gate text is then built %s", want and "visible" or "invisible")
	end
end

local function piece(name, o)
	alog("  %s: shown %s visible %s alpha %s rect %s", name, val(o, "IsShown"), val(o, "IsVisible"), val(o, "GetAlpha"), val(o, "GetRect"))
end

local function gatePieces(key, s)
	if not s.fs then return end
	alog("  %s gate text: %s, string width %s, rect %s", key, textOf(s.fs), val(s.fs, "GetStringWidth"), val(s.fs, "GetRect"))
	piece(key .. " fresh clip (open while wide)", s.fresh)
	if s.settled then piece(key .. " settled clip (open while short)", s.settled) end
end

local function dump()
	if not ap.root then alog("dump: not built (/fdanim2 first)"); return end
	local combat = InCombatLockdown()
	alog("dump at t=%.1f (combat %s, buff %s), elapsed text taken: %s", GetTime(), show(combat),
		buffAge(), gatesText())
	for _, key in ipairs({ "E", "E2", "E0" }) do
		local s = ap[key]
		piece(key .. " button", s.b)
		piece(key .. " animated layer", s.layer)
		gatePieces(key, s)
	end
	for _, key in ipairs({ "F", "F0" }) do
		local s = ap[key]
		piece(key .. " container (1 px wide when empty?)", s.c)
		piece(key .. " missing clip", s.clip)
		local it = s.items and s.items[#s.items]
		if it then
			piece(("%s group button #%d of %d (the one the game hands out first)"):format(key, #s.items, #s.items), it.b)
			gatePieces(key, it)
			piece(key .. " its finish copy", it.fin)
		end
		local vis, hid, other = 0, 0, 0
		for _, f in ipairs(s.fins or {}) do
			local ok, v = pcall(function() return f:IsVisible() and "v" or "h" end)
			if ok and v == "v" then vis = vis + 1 elseif ok then hid = hid + 1 else other = other + 1 end
		end
		alog("  %s finish copies: %d visible, %d hidden, %d unreadable (of %d) | group frame count %s", key, vis, hid, other,
			#(s.fins or {}), val(s.c, "GetAuraGroupFrameCount", "fdanim2" .. key))
	end
end

local function remove()
	for _, c in ipairs(ap.containers or {}) do
		pcall(c.Hide, c)
		pcall(c.SetUnit, c, nil)
	end
	if ap.root then pcall(ap.root.Hide, ap.root) end
	ev:UnregisterAllEvents()
	ap.root, ap.E, ap.E2, ap.E0, ap.F, ap.F0, ap.containers = nil, nil, nil, nil, nil, nil, nil
	alog("removed (a /reload clears it completely)")
end

-- the buff's own changes on you (readable out of combat): a refresh is an UPDATE (the buttons stay shown,
-- nothing may play); REMOVED + ADDED is a new show (everything plays)
local function auraEvent(t, info)
	if type(info) ~= "table" then return end
	local ok, err = pcall(function()
		if info.isFullUpdate then
			if not (ap.lastFull and t - ap.lastFull < 0.25) then ap.lastFull = t; alog("t=%.1f UNIT_AURA: full update on you", t) end
			return
		end
		for _, a in ipairs(info.addedAuras or {}) do
			local id, inst = a.spellId, a.auraInstanceID
			if plain(id) and plain(inst) and ap.set[id] then
				ap.inst[inst] = id
				alog("t=%.1f buff ADDED (%s, instance %s, %s): a new show. E, E2, E0 slide in; F, F0 slide up", t, show(id),
					show(inst), ageText(a))
			end
		end
		for _, inst in ipairs(info.updatedAuraInstanceIDs or {}) do
			if plain(inst) and ap.inst[inst] then
				alog("t=%.1f buff UPDATED (instance %s, a refresh?): no new show, nothing may play. Buff %s; E2's square orange again for 3 s",
					t, show(inst), buffAge())
			end
		end
		for _, inst in ipairs(info.removedAuraInstanceIDs or {}) do
			if plain(inst) and ap.inst[inst] then
				ap.inst[inst] = nil
				alog("t=%.1f buff REMOVED (instance %s)", t, show(inst))
			end
		end
	end)
	if not ok and not ap.reported.auraEvent then ap.reported.auraEvent = true; alog("UNIT_AURA reading -> ERROR %s", show(err)) end
end

ev:SetScript("OnEvent", function(_, event, _, info)
	if not ap.root then return end
	local t = GetTime()
	if event == "UNIT_AURA" then
		auraEvent(t, info)
	elseif event == "PLAYER_REGEN_DISABLED" then
		alog("t=%.1f COMBAT START: E0 replay? F0 flash? E, E2 and F must stay still", t)
	elseif event == "PLAYER_REGEN_ENABLED" then
		alog("t=%.1f COMBAT END: E0 replay? F0 flash? E, E2 and F must stay still", t)
	elseif event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
		if ap.lastFlags and t - ap.lastFlags < 0.25 then return end
		ap.lastFlags = t
		alog("t=%.1f %s on you: the game rebuilds the containers", t, event)
	else
		alog("t=%.1f %s", t, event)
	end
end)

SLASH_FDIANIM21 = "/fdanim2"
SlashCmdList.FDIANIM2 = function(msg)
	msg = strtrim(msg or "")
	local low = msg:lower()
	if low == "hide" then remove(); return end
	if low == "kick" then kick(); return end
	if low == "dump" then dump(); return end
	if low == "show" then toggleGate(); return end
	local ids = {}
	for word in msg:gmatch("%d+") do ids[#ids + 1] = tonumber(word) end
	local arg
	if #ids > 0 then arg = ids elseif msg ~= "" then arg = msg end
	build(arg)
end
