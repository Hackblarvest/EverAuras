--[[ Forever Dev Info - /fdanim [spellID ... | buff name]: can the game play OUR animation when an aura appears?

     Blizzard's custom aura button takes animation groups with button:AddAuraShownAnimation(group) and
     plays them itself whenever the button goes from hidden to shown (Blizzard_CustomAuraButton.lua
     ApplyVisibility), also in combat. EverAuras wants that for WeakAuras "Start" animations. Build it
     OUT OF COMBAT. Default buff: your Demon Skin / Demon Armor (every rank); or give spell IDs or the
     name of any self-buff you can cast and cancel. Best: build it with the buff OFF.

     Four icons appear side by side above the screen centre. The grey box behind each is where the
     icon rests and the small label above it is ours: neither of them is part of the aura button, so
     they never move.

       A  slide + fade     fades in while sliding in from 60 px to the right. Below it: a duration
                           text and a blue bar that BELONG to the button but hang on the grey box
                           (as EverAuras' texts and bars hang on the WeakAuras region). Left of it:
                           your character in a grey box (a PlayerModel inside the button). Look:
                           do the text, the bar and the character slide WITH the icon, only fade,
                           or just pop in? A small green square in A's top-right corner is made
                           AFTER the build: if it shrinks from big over 2 s when A appears,
                           objects made and handed over late work too.
       B  late config      built to grow from a dot in 0.6 s, then changed right after the build to
                           shrink from 3x over 1.5 s while dipping 50 px down and back up.
                           3x + dip = a handed-over animation can still be changed; a dot growing =
                           it cannot (3x without the dip = only the path change was refused).
                           The words "B text" below it belong to the button but hang on the grey
                           box: do they also start 3x big, or keep their size?
       C  fade + our loop  fades in slowly (1.5 s) while it flashes and shakes (our own looping
                           animations on a frame inside the button). No flash and no shake at all:
                           chat says 0.5 s after the build whether they were still playing. With
                           the buff UP, /fdanim loop starts them again; then cancel and recast:
                           flashing again = our loops survive the button hiding; still = a hide
                           stops them. Flash and shake, but the flash cannot be seen DURING the
                           fade = the button's fade and the inner flash do not stack.
       D  missing          the buff's icon (grey/red) while the buff is MISSING. When you cast the
                           buff it should slide up and fade out instead of just vanishing. Expected
                           to misbehave (kept to show it): with the buff UP, a copy will probably
                           flash and slide up again at every combat start/end and on /fdanim kick.

     What to do (chat notes every combat start/end and every rebuild the game makes on its own):
       1. Buff OFF, out of combat: cast it and watch A-D. Cancel it: A-C vanish at once, D is back at
          once. Cast it again: everything plays again (does C still flash and shake?).
       2. Buff UP, idle: hit a target dummy or a mob, then leave combat. Do A-C play their start
          again at the pull and at the end? Does D flash? Being stunned or feared counts too.
       3. Do step 1 again in combat.
       4. Buff UP: /fdanim kick (the full rebuild the game also does by itself). A-C replay? D flash?
       5. Buff UP: /reload. The probe rebuilds itself at login: count how often A-C play. (B's first
          play after a reload may be the dot growing: its change comes 0.5 s after the rebuild.)
       6. Optional, today's state: give one of your EverAuras icons a WeakAuras Main animation
          (Flash, then Shake) and check that it still plays in combat.
       7. Out of combat with the buff up: /fdanim dump, then /fdanim hide (so the next login does
          not rebuild it), then /reload and send ForeverDevInfoDB.animProbe plus what you saw.

     /fdanim kick   UpdateAllAuras on the probe's containers
     /fdanim loop   plays C's own loops again (and says whether they were still playing)
     /fdanim dump   shown / alpha / place of every piece, our loops, B's values now
     /fdanim hide   removes it and stops the rebuild at login
     Everything is logged to ForeverDevInfoDB.animProbe (and printed).
]]

local ap = { reported = {} }
local SIZE, COL, ROWY, M = 40, 120, 200, 6
local LAYOUT_SAFE = "DisableUntrustedLayoutScriptsTemplate"
local DEFAULT = {
	{ "Demon Skin", { 687, 696 } },
	{ "Demon Armor", { 706, 1086, 11733, 11734, 11735, 27260 } },
}
local ev = CreateFrame("Frame")

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function alog(fmt, ...)
	local okF, line = pcall(string.format, fmt, ...)
	if select("#", ...) == 0 then line = fmt elseif not okF then line = fmt .. " (format error: " .. show(line) .. ")" end
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.animProbe = ForeverDevInfoDB.animProbe or {}
	local l = ForeverDevInfoDB.animProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 800 do table.remove(l, 1) end
	print("|cff33ff99FDI anim|r " .. line)
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
		if type(v) == "number" and not (issecretvalue and issecretvalue(v)) then out[#out + 1] = ("%.2f"):format(v) else out[#out + 1] = show(v) end
	end
	return table.concat(out, ",")
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
	host:SetPoint("CENTER", UIParent, "CENTER", (i - 2.5) * COL, ROWY)
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

local function setScale(a, fx, fy, tx, ty)
	local from = fnOf(a, "SetScaleFrom") or fnOf(a, "SetFromScale")
	local to = fnOf(a, "SetScaleTo") or fnOf(a, "SetToScale")
	from(a, fx, fy)
	to(a, tx, ty)
end

local function setCurve(path, curve)
	local f = fnOf(path, "SetCurveType") or fnOf(path, "SetCurve")
	if f then f(path, curve) end
end

local function points(path, list)
	local cps = {}
	for i, p in ipairs(list) do
		local cp = path:CreateControlPoint(nil, nil, i)
		cp:SetOffset(p[1], p[2])
		cps[i] = cp
	end
	return cps
end

local function missingLook(t)
	t:SetTexture(ap.iconFile)
	pcall(t.SetDesaturated, t, true)
	t:SetVertexColor(1, 0.45, 0.45, 1)
end

-- the spell IDs: given IDs, or a name / the default names resolved by the spellbook, plus every listed
-- rank, plus whatever buff of that name is on you now (all plain out of combat)
local function spellSet(arg)
	local set, ids, names = {}, {}, {}
	local function add(id)
		if type(id) == "number" and not (issecretvalue and issecretvalue(id)) and not set[id] then set[id] = true; ids[#ids + 1] = id end
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
				if not (issecretvalue and issecretvalue(a.name)) and a.name == name then add(a.spellId) end
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

local function buffNow(set)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or type(a) ~= "table" then return end
		local id = a.spellId
		if not (issecretvalue and issecretvalue(id)) and set[id] then return id, a.icon end
	end
end

local function iconFor(ids, auraIcon)
	if auraIcon and not (issecretvalue and issecretvalue(auraIcon)) then return auraIcon end
	if C_Spell and C_Spell.GetSpellTexture then
		for _, id in ipairs(ids) do
			local ok, t = pcall(C_Spell.GetSpellTexture, id)
			if ok and t and not (issecretvalue and issecretvalue(t)) then return t end
		end
	end
	return 134400
end

--------------------------------------------------------------------------------------------------
-- A: Alpha 0->1 + a Path that jumps 60 px right and comes back in 23 eased steps, on the button.
-- Children of the button that hang OUTSIDE it (text, bar), a PlayerModel child.
local function initA(b)
	local s = ap.A
	s.b = b
	local types = {}
	for _, k in ipairs({ "AddAuraShownAnimation", "RemoveAuraShownAnimation", "ClearAuraShownAnimations",
		"AddAuraAssignedAnimation", "CreateAnimationGroup", "SetIcon", "SetDurationText", "SetDurationBar" }) do
		types[#types + 1] = k .. "=" .. type(fnOf(b, k))
	end
	alog("A button: %s", table.concat(types, " "))
	try("A icon on the button", function()
		s.icon = b:CreateTexture(nil, "ARTWORK")
		s.icon:SetAllPoints(b)
	end)
	if s.icon then call("A SetIcon", b, "SetIcon", s.icon) end
	try("A text: child of the button, hangs on the grey box", function()
		s.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		s.fs:SetPoint("TOP", s.host, "BOTTOM", 0, -3)
		s.fs:SetText("A text")   -- placeholder; the game writes the time left over it
	end)
	if s.fs then call("A SetDurationText (outside-anchored text)", b, "SetDurationText", s.fs, nil) end
	try("A bar: child of the button, hangs on the grey box", function()
		local bar = CreateFrame("StatusBar", nil, b)
		bar:SetPoint("TOPLEFT", s.host, "BOTTOMLEFT", 0, -18)
		bar:SetPoint("TOPRIGHT", s.host, "BOTTOMRIGHT", 0, -18)
		bar:SetHeight(6)
		bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		bar:SetStatusBarColor(0.3, 0.75, 1, 1)
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(1)
		local bg = bar:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints(bar)
		bg:SetColorTexture(0, 0, 0, 0.6)
		s.bar = bar
	end)
	if s.bar then
		local dirs = Enum and Enum.StatusBarTimerDirection
		call("A SetDurationBar (outside-anchored bar)", b, "SetDurationBar", s.bar, { direction = dirs and dirs.RemainingTime })
	end
	try("A PlayerModel inside the button (left of it)", function()
		s.model = CreateFrame("PlayerModel", nil, b)
		s.model:SetSize(48, 64)
		s.model:SetPoint("RIGHT", b, "LEFT", -12, 0)
		s.modelBg = s.model:CreateTexture(nil, "BACKGROUND")
		s.modelBg:SetAllPoints(s.model)
		s.modelBg:SetColorTexture(0.5, 0.5, 0.5, 0.35)
	end)
	if s.model then call("A PlayerModel SetUnit(player)", s.model, "SetUnit", "player") end
	local okG = try("A start group on the button (Alpha 0->1 + Path from +60 px, 0.6 s)", function()
		local ag = b:CreateAnimationGroup()
		local alpha = anim(ag, "Alpha", nil, 0.6)
		alpha:SetFromAlpha(0)
		alpha:SetToAlpha(1)
		local path = anim(ag, "Path", nil, 0.6)
		setCurve(path, "NONE")
		local pts = { { 60, 0 } }
		for k = 1, 23 do
			local f = 1 - k / 23
			pts[#pts + 1] = { 60 * f * f, 0 }
		end
		points(path, pts)
		s.ag, s.alpha, s.path = ag, alpha, path
	end)
	if okG then
		call("A AddAuraShownAnimation", b, "AddAuraShownAnimation", s.ag)
		alog("A right after the hand-over: button GetAlpha %s", val(b, "GetAlpha"))
	end
end

-- B: Scale 0.05->1 + a Path that (almost) stays put (0.6 s), handed over now, changed after the build.
local function initB(b)
	local s = ap.B
	s.b = b
	try("B icon on the button", function()
		s.icon = b:CreateTexture(nil, "ARTWORK")
		s.icon:SetAllPoints(b)
	end)
	if s.icon then call("B SetIcon", b, "SetIcon", s.icon) end
	try("B plain text: child of the button, hangs on the grey box (does it scale with B?)", function()
		s.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		s.fs:SetPoint("TOP", s.host, "BOTTOM", 0, -3)
		s.fs:SetText("B text")
	end)
	local okG = try("B start group on the button (Scale 0.05->1 + a 2 px Path, 0.6 s)", function()
		local ag = b:CreateAnimationGroup()
		local scale = anim(ag, "Scale", nil, 0.6)
		setScale(scale, 0.05, 0.05, 1, 1)
		scale:SetOrigin("CENTER", 0, 0)
		scale:SetSmoothing("NONE")
		local path = anim(ag, "Path", nil, 0.6)
		setCurve(path, "NONE")
		path:SetSmoothing("NONE")
		local cps = points(path, { { 0, -2 }, { 0, 0 } })   -- a 2 px dip: not a zero-length path
		s.ag, s.scale, s.path, s.cp1 = ag, scale, path, cps[1]
	end)
	if okG then call("B AddAuraShownAnimation", b, "AddAuraShownAnimation", s.ag) end
end

-- C: the icon on an inner root; Start (Alpha 0->1, 1.5 s) on the button, handed over; our own loops
-- (flash BOUNCE, shake REPEAT) on the root, played by us once now.
local function initC(b)
	local s = ap.C
	s.b = b
	try("C inner root + icon on it", function()
		s.root = CreateFrame("Frame", nil, b)
		s.root:SetAllPoints(b)
		s.root:SetFrameLevel(b:GetFrameLevel())
		s.icon = s.root:CreateTexture(nil, "ARTWORK")
		s.icon:SetAllPoints(s.root)
	end)
	if s.icon then call("C SetIcon (the icon lives on the inner root)", b, "SetIcon", s.icon) end
	local okG = try("C start group on the button (Alpha 0->1, 1.5 s)", function()
		s.ag = b:CreateAnimationGroup()
		local a = anim(s.ag, "Alpha", nil, 1.5)
		a:SetFromAlpha(0)
		a:SetToAlpha(1)
	end)
	if okG then call("C AddAuraShownAnimation", b, "AddAuraShownAnimation", s.ag) end
	if not s.root then return end
	try("C our loops on the root (flash 1->0.3 BOUNCE 0.25 s, shake +-8 px REPEAT 0.5 s)", function()
		s.flash = s.root:CreateAnimationGroup()
		s.flash:SetLooping("BOUNCE")
		local a = anim(s.flash, "Alpha", nil, 0.25)
		a:SetFromAlpha(1)
		a:SetToAlpha(0.3)
		s.shake = s.root:CreateAnimationGroup()
		s.shake:SetLooping("REPEAT")
		local p = anim(s.shake, "Path", nil, 0.5)
		setCurve(p, "NONE")
		points(p, { { 8, 0 }, { -8, 0 }, { 0, 0 } })
	end)
	if s.flash then call("C our flash Play", s.flash, "Play") end
	if s.shake then call("C our shake Play", s.shake, "Play") end
end

-- D: each of the Missing group's buttons gets a copy of the missing icon at alpha 0 (hanging on the
-- grey box, not on the button) and a handed-over Finish (Alpha 1->0 + Path up 40 px, 0.8 s).
local function initD(b)
	local s = ap.D
	s.inits = s.inits + 1
	ap.quiet = s.inits > 1   -- the first of the pre-made buttons logs in full, the others only errors
	pcall(b.SetSize, b, SIZE + 1 + 2 * M, SIZE)
	pcall(b.SetMouseClickEnabled, b, false)
	local fin
	try("D finish copy (alpha 0, hangs on the grey box)", function()
		fin = CreateFrame("Frame", nil, b)
		fin:SetAllPoints(s.host)
		fin:SetFrameLevel(s.host:GetFrameLevel() + 10)
		fin:SetAlpha(0)
		local t = fin:CreateTexture(nil, "ARTWORK")
		t:SetAllPoints(fin)
		missingLook(t)
	end)
	if fin then
		local ag
		local okG = try("D finish group (Alpha 1->0 + Path up 40 px, 0.8 s)", function()
			ag = b:CreateAnimationGroup()
			local a = anim(ag, "Alpha", fin, 0.8)
			a:SetFromAlpha(1)
			a:SetToAlpha(0)
			local p = anim(ag, "Path", fin, 0.8)
			setCurve(p, "NONE")
			points(p, { { 0, 20 }, { 0, 40 } })
		end)
		if okG then call("D AddAuraShownAnimation", b, "AddAuraShownAnimation", ag) end
		s.fins[#s.fins + 1] = fin
	end
	ap.quiet = false
end

local function slot(c, key, host, init)
	local ok, b = pcall(c.AddAuraSlot, c, "fdanim" .. key, "HELPFUL", {
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

local function buildD()
	local s = ap.D
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, s.host, "CustomAuraContainerTemplate")
	if not ok or not c then alog("D container -> ERROR %s", show(c)); return end
	s.c = c
	ap.containers[#ap.containers + 1] = c
	c:SetPoint("TOPLEFT", s.host, "TOPLEFT")
	call("D SetUnit(player)", c, "SetUnit", "player")
	call("D AddAuraGroup (Missing: max 1 frame)", c, "AddAuraGroup", "fdanimD", "HELPFUL", {
		candidateFilters = { includeSpellIDs = ap.set },
		maxFrameCount = 1,
		layout = { elementWidth = SIZE + 1 + 2 * M, elementHeight = SIZE },
		initializeFrame = initD,
	})
	ap.quiet = false
	alog("D: %d group button(s) initialised, %d finish copies", s.inits, #s.fins)
	-- the Missing clip (ours, outside the buttons): open while the group is empty (container 1 px wide),
	-- shut once the group holds the buff (container SIZE + 1 + 2M wide)
	try("D missing clip on the container's right edge", function()
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

-- C's own loops (not handed over, so IsPlaying is ours to ask); 'again' plays them once more
local function loops(tag, again)
	local C = ap.C
	if not (C and (C.flash or C.shake)) then alog("%s: C has no loops (/fdanim first)", tag); return end
	alog("%s: C button shown %s | our loops: flash playing %s, shake playing %s", tag, val(C.b, "IsShown"),
		val(C.flash, "IsPlaying"), val(C.shake, "IsPlaying"))
	if not again then return end
	if C.flash then call("C our flash Play again", C.flash, "Play") end
	if C.shake then call("C our shake Play again", C.shake, "Play") end
	alog("  now: flash playing %s, shake playing %s", val(C.flash, "IsPlaying"), val(C.shake, "IsPlaying"))
end

-- After the build, at safe time: change B, make and hand over objects late on A, and check what the
-- engine would still do to a button whose group was handed over.
local function lateTests()
	if not ap.root then return end
	if InCombatLockdown() then alog("late tests skipped: in combat (they need safe time)"); return end
	alog("--- late tests (after the build, out of combat) ---")
	local A, B, C, D = ap.A, ap.B, ap.C, ap.D
	loops("C 0.5 s after the build (buff off + loops not playing = the hide right after the build stopped them)")
	if B.ag then
		local sf = fnOf(B.scale, "SetScaleFrom") and "SetScaleFrom" or "SetFromScale"
		call("B late scale " .. sf .. "(3, 3)", B.scale, sf, 3, 3)
		call("B late scale SetDuration(1.5)", B.scale, "SetDuration", 1.5)
		call("B late scale SetSmoothing(OUT)", B.scale, "SetSmoothing", "OUT")
		call("B late path SetDuration(1.5)", B.path, "SetDuration", 1.5)
		call("B late control point 1 SetOffset(0, -50)", B.cp1, "SetOffset", 0, -50)
		call("B late path SetSmoothing(IN_OUT)", B.path, "SetSmoothing", "IN_OUT")
		local sc = fnOf(B.path, "SetCurveType") and "SetCurveType" or "SetCurve"
		call("B late path " .. sc .. "(SMOOTH)", B.path, sc, "SMOOTH")
		alog("B read back: scale from %s, duration %s, smoothing %s | path duration %s, smoothing %s, curve %s | point 1 %s | group duration %s",
			val(B.scale, "GetScaleFrom"), val(B.scale, "GetDuration"), val(B.scale, "GetSmoothing"),
			val(B.path, "GetDuration"), val(B.path, "GetSmoothing"), val(B.path, "GetCurveType"),
			val(B.cp1, "GetOffset"), val(B.ag, "GetDuration"))
	else
		alog("B: no group to change")
	end
	alog("GetAlpha after the hand-over: A button %s, B button %s, C button %s, D copy #1 %s",
		val(A.b, "GetAlpha"), val(B.b, "GetAlpha"), val(C.b, "GetAlpha"), val(D.fins[1], "GetAlpha"))
	local b = A.b
	if not b then alog("A: no button, A's late tests skipped"); return end
	-- (f) the engine's usual later calls on and inside a button that handed over a group
	call("A button SetAlpha(1)", b, "SetAlpha", 1)
	try("A button SetFrameLevel(same level)", function() b:SetFrameLevel(b:GetFrameLevel()) end)
	try("A button SetPoint(TOPLEFT, same place)", function() b:SetPoint("TOPLEFT", A.host, "TOPLEFT", 0, 0) end)
	if A.icon then
		call("A icon (given to SetIcon) SetVertexColor(1,1,1,1)", A.icon, "SetVertexColor", 1, 1, 1, 1)
		try("A icon SetPoint(TOPLEFT, same place)", function() A.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0) end)
		alog("A icon: alpha %s, vertex colour %s", val(A.icon, "GetAlpha"), val(A.icon, "GetVertexColor"))
	end
	if A.modelBg then call("A plain child texture SetVertexColor(1,1,1,1)", A.modelBg, "SetVertexColor", 1, 1, 1, 1) end
	if A.model then
		try("A model SetFrameLevel(same) + SetPoint(same place)", function()
			A.model:SetFrameLevel(A.model:GetFrameLevel())
			A.model:SetPoint("RIGHT", b, "LEFT", -12, 0)
		end)
		call("A model SetUnit(player) again", A.model, "SetUnit", "player")
	end
	if A.fs then try("A text SetPoint(same place on the grey box)", function() A.fs:SetPoint("TOP", A.host, "BOTTOM", 0, -3) end) end
	if A.alpha then call("A handed-over Alpha SetTarget(button) (ChangeAnimationTarget: expect refused)", A.alpha, "SetTarget", b) end
	-- objects made and handed over AFTER initializeFrame
	local L = {}
	A.late = L
	local okT = try("A late CreateTexture in the button (green square)", function()
		L.sq = b:CreateTexture(nil, "OVERLAY")
		L.sq:SetSize(12, 12)
		L.sq:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2)
		L.sq:SetColorTexture(0.2, 1, 0.2, 1)
	end)
	local okG = okT and try("A late CreateAnimationGroup on the button", function() L.ag = b:CreateAnimationGroup() end)
	local okS = okG and try("A late Scale 4->1 on the green square, 2 s", function()
		local a = anim(L.ag, "Scale", L.sq, 2)
		setScale(a, 4, 4, 1, 1)
		a:SetOrigin("CENTER", 0, 0)
	end)
	if okS and call("A late AddAuraShownAnimation", b, "AddAuraShownAnimation", L.ag) then
		call("A late AddAuraShownAnimation AGAIN (expect 'already been added')", b, "AddAuraShownAnimation", L.ag)
		call("A late RemoveAuraShownAnimation", b, "RemoveAuraShownAnimation", L.ag)
		call("A late AddAuraShownAnimation after the remove", b, "AddAuraShownAnimation", L.ag)
		local okA, extra = call("A late CreateAnimation on a handed-over group (AddAnimations: expect refused)", L.ag, "CreateAnimation", "Translation")
		if okA and extra then pcall(extra.SetOffset, extra, 0, 0); pcall(extra.SetDuration, extra, 0.01) end
	end
	alog("--- late tests done. Now cast / cancel the buff (steps: header of Probe_Anim.lua) ---")
end

local function build(arg, auto)
	if ap.root then alog("already built - /fdanim hide first"); return end
	if InCombatLockdown() then alog("build it OUT OF COMBAT"); return end
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		try("LoadAddOn(Blizzard_AuraContainer)", C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local set, ids, what = spellSet(arg)
	if #ids == 0 then alog("no spell ID found for %s: /fdanim <spellID> or /fdanim <buff name>", show(what)); return end
	local nowId, auraIcon = buffNow(set)
	ap.set, ap.reported, ap.containers, ap.quiet = set, {}, {}, false
	ap.iconFile = iconFor(ids, auraIcon)
	local okB, _, bld = pcall(GetBuildInfo)
	alog("[run%s] build %s, %s = %s, buff on you now: %s, combat %s", auto and " at login" or "", okB and show(bld) or "?",
		what, table.concat(ids, ","), nowId and ("yes (" .. show(nowId) .. ")") or "no", show(InCombatLockdown()))
	ap.root = Frame(UIParent)
	ap.root:SetAllPoints(UIParent)
	ap.A = { host = column(1, "A  slide + fade") }
	ap.B = { host = column(2, "B  late config") }
	ap.C = { host = column(3, "C  fade + loop") }
	ap.D = { host = column(4, "D  missing"), inits = 0, fins = {} }
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, ap.root, "CustomAuraContainerTemplate")
	if ok and c then
		ap.containers[#ap.containers + 1] = c
		pcall(c.SetSize, c, 1, 1)
		pcall(c.SetPoint, c, "CENTER", UIParent, "CENTER", 0, ROWY)
		pcall(c.SetFrameLevel, c, ap.root:GetFrameLevel() + 5)
		alog("container: AddAuraSlot=%s AddAuraGroup=%s UpdateAllAuras=%s", type(fnOf(c, "AddAuraSlot")), type(fnOf(c, "AddAuraGroup")), type(fnOf(c, "UpdateAllAuras")))
		call("A-C SetUnit(player)", c, "SetUnit", "player")
		slot(c, "A", ap.A.host, initA)
		slot(c, "B", ap.B.host, initB)
		slot(c, "C", ap.C.host, initC)
	else
		alog("A-C container -> ERROR %s", show(c))
	end
	buildD()
	ev:RegisterEvent("PLAYER_REGEN_DISABLED")
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:RegisterEvent("PLAYER_ENTERING_WORLD")
	pcall(ev.RegisterEvent, ev, "LOADING_SCREEN_DISABLED")
	pcall(ev.RegisterUnitEvent, ev, "UNIT_FLAGS", "player")
	pcall(ev.RegisterUnitEvent, ev, "UNIT_FACTION", "player")
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	if not auto then ForeverDevInfoDB.animProbeAuto = { arg = arg, reloads = 0 } end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, lateTests) else alog("C_Timer.After missing: late tests skipped") end
	alog("built (rebuilds itself at every login until /fdanim hide). Cancel and cast the buff; /fdanim kick, loop, dump, hide.")
end

local function kick()
	if not ap.root then alog("kick: not built (/fdanim first)"); return end
	alog("t=%.1f kick (combat %s): UpdateAllAuras = a full rebuild. A-C replay? D flashes (the ghost)?", GetTime(), show(InCombatLockdown()))
	for i, c in ipairs(ap.containers or {}) do call("kick container " .. i .. " UpdateAllAuras", c, "UpdateAllAuras") end
end

local function piece(name, o)
	alog("  %s: shown %s visible %s alpha %s rect %s", name, val(o, "IsShown"), val(o, "IsVisible"), val(o, "GetAlpha"), val(o, "GetRect"))
end

local function dump()
	if not ap.root then alog("dump: not built (/fdanim first)"); return end
	local A, B, C, D = ap.A, ap.B, ap.C, ap.D
	local combat = InCombatLockdown()
	alog("dump at t=%.1f (combat %s, buff on you %s):", GetTime(), show(combat), combat and "n/a in combat" or show(buffNow(ap.set) ~= nil))
	piece("A button", A.b)
	piece("A text (hangs outside)", A.fs)
	piece("A bar (hangs outside)", A.bar)
	piece("A model", A.model)
	piece("A late green square", A.late and A.late.sq)
	alog("  A start group (handed over) IsPlaying %s (expect refused) | late group IsPlaying %s", val(A.ag, "IsPlaying"), val(A.late and A.late.ag, "IsPlaying"))
	piece("B button", B.b)
	piece("B text (hangs outside)", B.fs)
	alog("  B now: scale from %s, duration %s | point 1 %s | path duration %s", val(B.scale, "GetScaleFrom"), val(B.scale, "GetDuration"), val(B.cp1, "GetOffset"), val(B.path, "GetDuration"))
	piece("C button", C.b)
	piece("C inner root", C.root)
	alog("  C our loops: flash playing %s, shake playing %s (want true, true)", val(C.flash, "IsPlaying"), val(C.shake, "IsPlaying"))
	piece("D container (1 px wide when empty?)", D.c)
	piece("D missing clip", D.clip)
	local vis, hid, other = 0, 0, 0
	for _, f in ipairs(D.fins or {}) do
		local ok, v = pcall(function() return f:IsVisible() and "v" or "h" end)
		if ok and v == "v" then vis = vis + 1 elseif ok then hid = hid + 1 else other = other + 1 end
	end
	alog("  D finish copies: %d visible, %d hidden, %d unreadable (of %d)", vis, hid, other, #(D.fins or {}))
	alog("  D group frame count %s", val(D.c, "GetAuraGroupFrameCount", "fdanimD"))
end

local function remove()
	if ap.C then
		pcall(function() ap.C.flash:Stop() end)
		pcall(function() ap.C.shake:Stop() end)
	end
	for _, c in ipairs(ap.containers or {}) do
		pcall(c.Hide, c)
		pcall(c.SetUnit, c, nil)
	end
	if ap.root then pcall(ap.root.Hide, ap.root) end
	ev:UnregisterAllEvents()
	ev:RegisterEvent("PLAYER_LOGIN")
	ap.root, ap.A, ap.B, ap.C, ap.D, ap.containers = nil, nil, nil, nil, nil, nil
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.animProbeAuto = nil
	alog("removed, no rebuild at login any more (a /reload clears it completely)")
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		local auto = ForeverDevInfoDB and ForeverDevInfoDB.animProbeAuto
		if type(auto) ~= "table" then return end
		auto.reloads = (auto.reloads or 0) + 1
		alog("[reload #%d] rebuilding /fdanim at login: with the buff up, count how often A, B and C play now", auto.reloads)
		build(auto.arg, true)
		return
	end
	if not ap.root then return end
	local t = GetTime()
	if event == "PLAYER_REGEN_DISABLED" then
		alog("t=%.1f COMBAT START: did A-C replay? did D flash?", t)
	elseif event == "PLAYER_REGEN_ENABLED" then
		alog("t=%.1f COMBAT END: did A-C replay? did D flash?", t)
	elseif event == "UNIT_FLAGS" or event == "UNIT_FACTION" then
		if ap.lastFlags and t - ap.lastFlags < 0.25 then return end
		ap.lastFlags = t
		alog("t=%.1f %s on you: the game rebuilds the containers", t, event)
	else
		alog("t=%.1f %s", t, event)
	end
end)

SLASH_FDIANIM1 = "/fdanim"
SlashCmdList.FDIANIM = function(msg)
	msg = strtrim(msg or "")
	local low = msg:lower()
	if low == "hide" then remove(); return end
	if low == "kick" then kick(); return end
	if low == "dump" then dump(); return end
	if low == "loop" then
		if not ap.root then alog("loop: not built (/fdanim first)"); return end
		loops(("t=%.1f loop (combat %s)"):format(GetTime(), show(InCombatLockdown())), true)
		return
	end
	local ids = {}
	for word in msg:gmatch("%d+") do ids[#ids + 1] = tonumber(word) end
	local arg
	if #ids > 0 then arg = ids elseif msg ~= "" then arg = msg end
	build(arg, false)
end
