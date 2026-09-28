--[[ Forever Dev Info - /fdlate [X] [total]: a clip that OPENS when X seconds are left, for an animated glow.

     The engine fills a StatusBar by the aura's remaining time (SetDurationBar). A clip INSIDE the aura
     button may anchor to the bar's fill edge (measured with /fdbar). With the aura's TOTAL duration known
     (we learn it out of combat), the bar is made K px per second wide and placed so that the fill edge
     passes a fixed point exactly when X seconds are left: the clip spans from the fill edge to that point,
     so its width is (X - remaining) * K: zero (nothing drawn) while more than X seconds are left, and wide
     enough to show the whole icon + glow a few milliseconds after.

     Inside the clip, anchored to the icon (a plain rect):
       red box     a static colour texture                     (does the clip open at X?)
       green pulse a texture faded by an AnimationGroup        (do animation groups run in the button in combat?)
       blue dot    a texture moved by an OnUpdate script       (do OnUpdate scripts run there in combat?)
     Plus the icon and a plain countdown. Build OUT OF COMBAT with your own DoT on the target (the probe
     reads its duration; else pass it: /fdlate 10 18). Then fight and screenshot at > X and < X seconds.
     Errors go to ForeverDevInfoDB.lateProbe. /fdlate hide removes it.
]]

local lp = {}
local IDS = {
	1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 27016,  -- Serpent Sting
	172, 6222, 6223, 7648, 11671, 11672, 25311, 27216,                   -- Corruption
	348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 27215,             -- Immolate
	980, 1014, 6217, 11711, 11712, 11713, 27218,                         -- Curse of Agony
}
local K, MARGIN = 2000, 24   -- px per second, glow room around the icon

local function llog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.lateProbe = ForeverDevInfoDB.lateProbe or {}
	local l = ForeverDevInfoDB.lateProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 200 do table.remove(l, 1) end
	print("|cff33ff99FDI late|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function ltry(label, fn, ...)
	local ok, res = pcall(fn, ...)
	llog("%s -> %s", label, ok and "ok" or ("ERROR: " .. show(res)))
	return ok, res
end

-- your own DoT on the target while auras are plain: its duration
local function targetDotDuration(set)
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "target", i, "HARMFUL|PLAYER")
		if not ok or type(a) ~= "table" then break end
		if set[a.spellId] and type(a.duration) == "number" and not issecretvalue(a.duration) and a.duration > 0 then
			return a.duration, a.spellId
		end
	end
end

local function build(X, total)
	if lp.host then llog("already built - /fdlate hide first"); return end
	local combat = InCombatLockdown()
	llog("[run] X=%g total=%s combat=%s", X, tostring(total), tostring(combat))
	if combat and not total then llog("in combat the DoT's duration cannot be read: pass it, e.g. /fdlate %g 15", X); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local set = {}
	for _, id in ipairs(IDS) do set[id] = true end
	local seen, seenId
	if not combat then seen, seenId = targetDotDuration(set) end
	if seen then llog("target has your DoT %s with duration %g s", show(seenId), seen) end
	total = total or seen
	if not total then llog("no own DoT on the target and no total given: /fdlate %g <total seconds>", X); return end
	if X >= total then llog("X (%g) must be below the total duration (%g)", X, total); return end
	local SIZE = 40
	local host = CreateFrame("Frame", "FDILateHost", UIParent)
	host:SetSize(SIZE, SIZE)
	host:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	lp.host = host
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("BOTTOM", host, "TOP", 0, MARGIN + 4)
	cap:SetText(("late probe: X = %g s of %g s"):format(X, total))

	local ok, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not ok or not c then llog("container -> ERROR %s", show(c)); return end
	c:SetAllPoints(host)
	ltry("SetUnit(target)", c.SetUnit, c, "target")
	lp.container = c

	local okS, button = pcall(c.AddAuraSlot, c, "late", "HARMFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = set },
		initializeFrame = function(b)
			b:ClearAllPoints()
			b:SetAllPoints(host)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); fs:SetPoint("TOP", b, "BOTTOM", 0, -MARGIN - 2)
			ltry("SetIcon", b.SetIcon, b, icon)
			ltry("SetDurationText", b.SetDurationText, b, fs, nil)

			-- the wide, invisible bar: K px per second, its left edge X*K px left of the clip's fixed right edge
			local W = total * K
			local bar = CreateFrame("StatusBar", nil, b)
			bar:SetSize(W, SIZE + 2 * MARGIN)
			bar:SetPoint("LEFT", b, "RIGHT", MARGIN - X * K, 0)
			bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			bar:SetStatusBarColor(0, 0, 0, 0)
			bar:SetFrameLevel(b:GetFrameLevel() + 1)
			local dirs = Enum and Enum.StatusBarTimerDirection
			ltry("SetDurationBar(RemainingTime)", b.SetDurationBar, b, bar, { direction = dirs and dirs.RemainingTime })
			local fill = bar:GetStatusBarTexture()

			-- the clip: from the fill's right edge to the fixed point (icon right + margin)
			local clip = CreateFrame("Frame", nil, b)
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(b:GetFrameLevel() + 2)
			ltry("clip TOPLEFT -> fill TOPRIGHT", clip.SetPoint, clip, "TOPLEFT", fill, "TOPRIGHT")
			ltry("clip BOTTOMRIGHT -> bar BOTTOMLEFT + X*K", clip.SetPoint, clip, "BOTTOMRIGHT", bar, "BOTTOMLEFT", X * K, 0)

			-- contents, anchored to the icon rect so they never move with the clip
			local red = clip:CreateTexture(nil, "BACKGROUND")
			red:SetPoint("TOPLEFT", b, "TOPLEFT", -MARGIN, MARGIN)
			red:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", MARGIN, -MARGIN)
			red:SetColorTexture(1, 0.1, 0.1, 0.45)

			local green = clip:CreateTexture(nil, "ARTWORK")
			green:SetPoint("TOPLEFT", b, "TOPLEFT", -MARGIN / 2, MARGIN / 2)
			green:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", MARGIN / 2, -MARGIN / 2)
			green:SetColorTexture(0.2, 1, 0.2, 0.8)
			local ag = clip:CreateAnimationGroup()
			ag:SetLooping("BOUNCE")
			local alpha = ag:CreateAnimation("Alpha")
			alpha:SetTarget(green)
			alpha:SetFromAlpha(1)
			alpha:SetToAlpha(0.1)
			alpha:SetDuration(0.5)
			ltry("animation group Play", ag.Play, ag)

			local mover = CreateFrame("Frame", nil, clip)
			mover:SetPoint("TOPLEFT", b, "TOPLEFT", -MARGIN, MARGIN)
			mover:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", MARGIN, -MARGIN)
			mover:SetFrameLevel(clip:GetFrameLevel() + 1)
			local dot = mover:CreateTexture(nil, "OVERLAY")
			dot:SetSize(8, 8)
			dot:SetColorTexture(0.2, 0.5, 1, 1)
			dot:SetPoint("CENTER", mover, "TOPLEFT", 0, 0)
			local t, errLogged = 0, false
			mover:SetScript("OnUpdate", function(self, elapsed)
				t = (t + elapsed) % 2
				local okU, err = pcall(function()
					local w, h = self:GetSize()
					local p = t / 2 * 4
					local x, y
					if p < 1 then x, y = p * w, 0
					elseif p < 2 then x, y = w, -(p - 1) * h
					elseif p < 3 then x, y = w - (p - 2) * w, -h
					else x, y = 0, -h + (p - 3) * h end
					dot:SetPoint("CENTER", self, "TOPLEFT", x, y)
				end)
				if not okU and not errLogged then errLogged = true; llog("OnUpdate in the button ERROR: %s", show(err)) end
			end)
			lp.parts = { bar = bar, clip = clip }
		end,
	})
	llog("AddAuraSlot -> %s", okS and "ok" or ("ERROR: " .. show(button)))
	if okS then
		lp.button = button
		llog("built (X = %g s, total = %g s, K = %d px/s). Fight: red box + green pulse + blue dot should appear only below %g s.", X, total, K, X)
	end
end

SLASH_FOREVERDEVLATE1 = "/fdlate"
SlashCmdList["FOREVERDEVLATE"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "hide" then
		if lp.host then lp.host:Hide(); lp.host = nil; lp.container = nil; lp.button = nil end
		llog("removed (a /reload clears it completely)")
		return
	end
	local nums = {}
	for word in msg:gmatch("%d+%.?%d*") do nums[#nums + 1] = tonumber(word) end
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.lateProbe = {}
	build(nums[1] or 10, nums[2])
end

-- /fddesc [spellID|name ...]: what the spell descriptions say about durations (the engine reads "over N sec"
-- etc. from them to know a DoT's total duration before it has ever been seen out of combat).
SLASH_FOREVERDEVDESC1 = "/fddesc"
SlashCmdList["FOREVERDEVDESC"] = function(msg)
	msg = strtrim(msg or "")
	local ids = {}
	for word in msg:gmatch("%S+") do ids[#ids + 1] = tonumber(word) or word end
	if #ids == 0 then ids = { 172, 6222, 348, 707, 980, 1014, 686, 1978, 13549, 17 } end
	for _, id in ipairs(ids) do
		local ok, desc = pcall(C_Spell.GetSpellDescription, id)
		local okN, name = pcall(C_Spell.GetSpellName, id)
		desc = ok and desc or ("ERROR " .. show(desc))
		if issecretvalue(desc) then desc = "<secret>" end
		local found = {}
		for _, pat in ipairs({ "over (%d+%.?%d*) sec", "for (%d+%.?%d*) sec", "lasts (%d+%.?%d*) sec", "over (%d+%.?%d*) min", "for (%d+%.?%d*) min" }) do
			for n in tostring(desc):gmatch(pat) do found[#found + 1] = pat:gsub(" %(.*", "") .. " " .. n end
		end
		llog("%s %s: %s | matches: %s", tostring(id), okN and show(name) or "?", tostring(desc):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 140), #found > 0 and table.concat(found, "; ") or "NONE")
	end
end

--[[ /fdchain [X] [total]: the engine's exact frame chain for the late glow, with OnUpdate counters.
       host (plain) -> present clip (DisableUntrustedLayoutScriptsTemplate, anchored to a 2nd container's
       aura group) -> late clip (same template, anchored to the bar fill inside the late slot's button)
       -> holder -> a moving blue dot (OnUpdate).
     Every second it logs how many OnUpdate ticks each level got, so we see where scripts stop. ]]
local ch = {}
SLASH_FOREVERDEVCHAIN1 = "/fdchain"
SlashCmdList["FOREVERDEVCHAIN"] = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "hide" then
		if ch.host then ch.host:Hide(); ch.host = nil end
		if ch.ticker then ch.ticker:Cancel(); ch.ticker = nil end
		llog("chain removed")
		return
	end
	if ch.host then llog("already built - /fdchain hide first"); return end
	local nums = {}
	for word in msg:gmatch("%d+%.?%d*") do nums[#nums + 1] = tonumber(word) end
	local X, total = nums[1] or 10, nums[2] or 15
	local set = {}
	for _, id in ipairs(IDS) do set[id] = true end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	ForeverDevInfoDB.lateProbe = {}
	local SIZE, M = 40, 24
	local host = CreateFrame("Frame", "FDIChainHost", UIParent)
	host:SetSize(SIZE, SIZE)
	host:SetPoint("CENTER", UIParent, "CENTER", 0, 260)
	ch.host = host
	local counts = { host = 0, present = 0, late = 0, holder = 0, plain = 0 }
	local function tick(name) return function() counts[name] = counts[name] + 1 end end
	host:SetScript("OnUpdate", tick("host"))
	-- a plain frame anchored to the host, never under any clip: the reference
	local plain = CreateFrame("Frame", nil, host)
	plain:SetAllPoints(host)
	plain:SetScript("OnUpdate", tick("plain"))

	-- present clip: container2 + group, as the engine does it
	local c2 = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
	c2:SetPoint("TOPLEFT", host, "TOPLEFT")
	local okG, errG = pcall(c2.AddAuraGroup, c2, "chain", "HARMFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = set }, maxFrameCount = 1,
		layout = { elementWidth = SIZE + 1 + 2 * M, elementHeight = SIZE },
		initializeFrame = function(b) b:SetSize(SIZE + 1 + 2 * M, SIZE) end,
	})
	llog("present group -> %s", okG and "ok" or ("ERROR " .. show(errG)))
	pcall(c2.SetUnit, c2, "target")
	local present = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
	present:SetClipsChildren(true)
	present:SetPoint("TOPRIGHT", c2, "TOPRIGHT", -1 - M, M)
	present:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -M, -M)
	present:SetScript("OnUpdate", tick("present"))

	-- late slot: container1 + slot with the bar inside the button
	local c1 = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
	c1:SetAllPoints(host)
	pcall(c1.SetUnit, c1, "target")
	local parts = {}
	local okS, errS = pcall(c1.AddAuraSlot, c1, "late", "HARMFUL|PLAYER", {
		candidateFilters = { includeSpellIDs = set },
		initializeFrame = function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b); pcall(b.SetIcon, b, icon)
			local bar = CreateFrame("StatusBar", nil, b)
			bar:SetSize(total * 2000, SIZE + 2 * M)
			bar:SetPoint("LEFT", b, "RIGHT", M - X * 2000, 0)
			bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			bar:SetAlpha(0)
			local dirs = Enum and Enum.StatusBarTimerDirection
			pcall(b.SetDurationBar, b, bar, { direction = dirs and dirs.RemainingTime })
			parts.bar = bar
		end,
	})
	llog("late slot -> %s", okS and "ok" or ("ERROR " .. show(errS)))
	if not parts.bar then return end
	local late = CreateFrame("Frame", nil, present, "DisableUntrustedLayoutScriptsTemplate")
	late:SetClipsChildren(true)
	local okA1, e1 = pcall(late.SetPoint, late, "TOPLEFT", parts.bar:GetStatusBarTexture(), "TOPRIGHT")
	local okA2, e2 = pcall(late.SetPoint, late, "BOTTOMRIGHT", parts.bar, "BOTTOMLEFT", X * 2000, 0)
	llog("late clip anchors -> %s / %s", okA1 and "ok" or show(e1), okA2 and "ok" or show(e2))
	late:SetScript("OnUpdate", tick("late"))
	local holder = CreateFrame("Frame", nil, late)
	holder:SetAllPoints(host)
	local red = holder:CreateTexture(nil, "BACKGROUND")
	red:SetPoint("TOPLEFT", host, "TOPLEFT", -M, M); red:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", M, -M)
	red:SetColorTexture(1, 0.1, 0.1, 0.4)
	local dot = holder:CreateTexture(nil, "OVERLAY"); dot:SetSize(8, 8); dot:SetColorTexture(0.2, 0.5, 1, 1)
	local t = 0
	holder:SetScript("OnUpdate", function(self, elapsed)
		counts.holder = counts.holder + 1
		t = (t + elapsed) % 2
		local p = t / 2 * 4
		local x, y
		if p < 1 then x, y = p * SIZE, 0 elseif p < 2 then x, y = SIZE, -(p - 1) * SIZE
		elseif p < 3 then x, y = SIZE - (p - 2) * SIZE, -SIZE else x, y = 0, -SIZE + (p - 3) * SIZE end
		dot:ClearAllPoints(); dot:SetPoint("CENTER", host, "TOPLEFT", x, y)
	end)
	pcall(c1.UpdateAllAuras, c1); pcall(c2.UpdateAllAuras, c2)
	ch.ticker = C_Timer.NewTicker(1, function()
		llog("ticks/s host=%d plain=%d present=%d late=%d holder=%d combat=%s", counts.host, counts.plain, counts.present, counts.late, counts.holder, tostring(InCombatLockdown()))
		for k in pairs(counts) do counts[k] = 0 end
	end)
	llog("chain built (X=%g total=%g). DoT a mob; watch the tick counts and the red box / blue dot below %g s.", X, total, X)
end

-- /fdants: is TextureUtil.AnimateTexCoords / AnimateTexCoords available on Forever, and does a plain
-- SetTexCoord flipbook of the IconAlertAnts texture animate in a normal frame?
SLASH_FOREVERDEVANTS1 = "/fdants"
SlashCmdList["FOREVERDEVANTS"] = function()
	llog("TextureUtil=%s TextureUtil.AnimateTexCoords=%s _G.AnimateTexCoords=%s",
		tostring(type(_G.TextureUtil)), tostring(type(_G.TextureUtil and _G.TextureUtil.AnimateTexCoords)), tostring(type(_G.AnimateTexCoords)))
	if ch.ants then ch.ants:Hide(); ch.ants = nil; llog("ants removed"); return end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(64, 64)
	f:SetPoint("CENTER", UIParent, "CENTER", 120, 260)
	local tex = f:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints(f)
	tex:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
	local frame, t = 0, 0
	f:SetScript("OnUpdate", function(self, elapsed)
		t = t + elapsed
		if t < 0.05 then return end
		t = 0
		frame = (frame + 1) % 22
		local col, row = frame % 5, math.floor(frame / 5)
		local s = 48 / 256
		tex:SetTexCoord(col * s, col * s + s, row * s, row * s + s)
	end)
	ch.ants = f
	llog("ants flipbook shown right of the chain probe: it should crawl. /fdants again removes it.")
end

-- /fdglow button|pixel|shine|proc: EverAuras' ForeverGlow on a plain 40x40 frame above the screen centre,
-- outside any aura container: do the animation-driven glows move at all? /fdglow alone removes it.
SLASH_FOREVERDEVGLOW1 = "/fdglow"
SlashCmdList["FOREVERDEVGLOW"] = function(msg)
	local kind = (msg or ""):match("%a+")
	local ea = _G.EverAuras or _G.M33kAuras or _G.WeakAuras
	local FG = ea and ea.ForeverGlow
	if ch.glow then
		if FG then pcall(FG.Stop, ch.glow) end
		ch.glow:Hide(); ch.glow = nil
		if not kind then llog("glow removed"); return end
	end
	if not kind then llog("usage: /fdglow button|pixel|shine|proc"); return end
	if not FG then llog("ForeverGlow not found - is EverAuras loaded?"); return end
	local subs = {
		button = { glowType = "buttonOverlay", glowFrequency = 0.125 },
		pixel = { glowType = "Pixel", glowLines = 8, glowFrequency = 0.25, glowLength = 10, glowThickness = 2, glowXOffset = 0, glowYOffset = 0, glowBorder = true },
		shine = { glowType = "ACShine", glowLines = 4, glowFrequency = 0.125, glowScale = 1, glowXOffset = 0, glowYOffset = 0 },
		proc = { glowType = "Proc", glowDuration = 1 },
	}
	local sub = subs[kind:lower()]
	if not sub then llog("unknown glow type %s", kind); return end
	local f = CreateFrame("Frame", nil, UIParent)
	f:SetSize(40, 40)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(f)
	icon:SetTexture(136118)
	local ok, res = pcall(FG.Start, f, sub, 40, 40)
	ch.glow = f
	llog("glow %s -> %s. Above the centre: lines/sparkles should circle the icon, ants crawl, the proc flipbook play.",
		kind, ok and tostring(res) or ("ERROR " .. show(res)))
end
