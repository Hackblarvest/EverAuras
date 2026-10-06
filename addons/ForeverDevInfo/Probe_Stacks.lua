--[[ Forever Dev Info - /fdstack [buff name]: can a buff's STACK count drive geometry, like its time left?

     CustomAuraButton:SetApplicationBar(statusBar, { minApplications, maxApplications }) makes the engine
     call statusBar:SetMinMaxValues(min, max(max, 1)), SetValue(applications) and
     SetShown(applications >= min) (Blizzard_CustomAuraButton.lua ApplyApplicationBar). A clip anchored to
     that bar's fill edge would then open or close with the stack count, also in combat. Run it OUT OF
     COMBAT with a buff on you that does not stack (it has 0 stacks), default "Demon Armor". Six boxes
     appear above the middle of the screen; each caption says what should be visible:

       B  bar min 0, max 3         a white strip: the engine shows the bar at 0 stacks (min -1 is refused:
                                   'outside of expected range 0 to 4294967295')
       C  bar min 1                NOTHING (red box on the bar): the engine hides the bar below min
       D  clip on an EMPTY fill    a green box: a clip can hang on a zero-width fill (inside the button)
       E  same, aura ABSENT        a blue box: ... also with the button hidden (clip outside the button)
       F1 gate on the time bar     the icon, nearly whole: a frame AROUND the container may hang on a
                                   bar inside the aura button and clip it
       F2 gate "0 stacks or less"  the icon, whole: the same gate driven by the stack bar, empty fill

     Then fight something: the boxes must stay the same in combat. Results are also logged to
     ForeverDevInfoDB.stackProbe. /fdstack hide removes it.
]]

local sp = {}
local SIZE, GAP = 40, 74

local function slog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.stackProbe = ForeverDevInfoDB.stackProbe or {}
	local l = ForeverDevInfoDB.stackProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI stack|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function stry(label, fn, ...)
	local ok, res = pcall(fn, ...)
	slog("%s -> %s", label, ok and "ok" or ("ERROR: " .. show(res)))
	return ok, res
end

local function rect(r)
	if not r then return "nil" end
	local ok, l, b, w, h = pcall(r.GetRect, r)
	if not ok then return "ERROR " .. show(l) end
	if l == nil then return "no rect" end
	local function f(v) return issecretvalue(v) and "<secret>" or ("%.1f"):format(v) end
	return ("x=%s y=%s w=%s h=%s"):format(f(l), f(b), f(w), f(h))
end

local function playerBuff(name)
	for i = 1, 40 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or type(a) ~= "table" then break end
		if not issecretvalue(a.name) and a.name == name then return a.spellId, a.applications end
	end
end

-- one test cell: a plain frame (with the layout ban, like EverAuras' hosts) holding a container
local function cell(index, caption)
	local host = CreateFrame("Frame", nil, UIParent, "DisableUntrustedLayoutScriptsTemplate")
	host:SetSize(SIZE, SIZE)
	host:SetPoint("CENTER", UIParent, "CENTER", (index - 3.5) * GAP, 250)
	local frameBox = host:CreateTexture(nil, "BACKGROUND")
	frameBox:SetPoint("TOPLEFT", -1, 1)
	frameBox:SetPoint("BOTTOMRIGHT", 1, -1)
	frameBox:SetColorTexture(0.3, 0.3, 0.3, 0.35)
	local cap = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("TOP", host, "BOTTOM", 0, -14)
	cap:SetWidth(GAP - 4)
	cap:SetText(caption)
	sp.hosts[#sp.hosts + 1] = host
	return host
end

local function container(parent, anchor)
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, parent, "CustomAuraContainerTemplate")
	if not ok or not c then slog("container -> ERROR %s", show(c)); return nil end
	c:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	pcall(c.SetUnit, c, "player")
	return c
end

local function slot(c, key, filter, id, init)
	local ok, b = pcall(c.AddAuraSlot, c, key, filter, {
		candidateFilters = { includeSpellIDs = { [id] = true } },   -- a SET of ids
		initializeFrame = init,
	})
	if not ok then slog("%s AddAuraSlot -> ERROR %s", key, show(b)) end
	return ok and b or nil
end

local function bar(b, h)
	local sb = CreateFrame("StatusBar", nil, b)
	sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	sb:SetStatusBarColor(1, 1, 1, 0.8)
	sb:SetFrameLevel(b:GetFrameLevel() + 1)
	if h then sb:SetHeight(h) end
	return sb
end

local function build(name)
	if sp.hosts then slog("already built - /fdstack hide first"); return end
	if InCombatLockdown() then slog("build it OUT OF COMBAT (the buff must be readable once)"); return end
	if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
	local id, apps = playerBuff(name)
	if not id then slog("'%s' is not on you: cast it, or name another buff: /fdstack <buff name>", name); return end
	slog("[run] buff %s = spell %s with %s stack(s)", name, show(id), show(apps))
	sp.hosts, sp.parts = {}, {}

	-- B: negative minimum
	do
		local host = cell(1, "B: white strip")
		local c = container(host, host)
		slot(c, "B", "HELPFUL", id, function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local sb = bar(b, 10); sb:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); sb:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
			local strip = sb:CreateTexture(nil, "BACKGROUND"); strip:SetAllPoints(sb); strip:SetColorTexture(1, 1, 1, 0.8)
			stry("B SetApplicationBar(min 0, max 3)", b.SetApplicationBar, b, sb, { minApplications = 0, maxApplications = 3 })
			sp.parts.B = sb
		end)
	end
	-- C: hidden below the minimum
	do
		local host = cell(2, "C: nothing")
		local c = container(host, host)
		slot(c, "C", "HELPFUL", id, function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local sb = bar(b); sb:SetAllPoints(b)
			local red = sb:CreateTexture(nil, "OVERLAY"); red:SetAllPoints(sb); red:SetColorTexture(1, 0.1, 0.1, 0.8)
			stry("C SetApplicationBar(min 1, max 3)", b.SetApplicationBar, b, sb, { minApplications = 1, maxApplications = 3 })
			sp.parts.C = sb
		end)
	end
	-- D: clip on an empty fill, inside the button
	do
		local host = cell(3, "D: green")
		local c = container(host, host)
		slot(c, "D", "HELPFUL", id, function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local sb = bar(b); sb:SetAllPoints(b); sb:SetStatusBarColor(0, 0, 0, 0)
			stry("D SetApplicationBar(min 0, max 3)", b.SetApplicationBar, b, sb, { minApplications = 0, maxApplications = 3 })
			local clip = CreateFrame("Frame", nil, b)
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(b:GetFrameLevel() + 2)
			stry("D clip TOPLEFT -> fill TOPRIGHT", clip.SetPoint, clip, "TOPLEFT", sb:GetStatusBarTexture(), "TOPRIGHT")
			stry("D clip BOTTOMRIGHT -> bar BOTTOMRIGHT", clip.SetPoint, clip, "BOTTOMRIGHT", sb, "BOTTOMRIGHT")
			local green = clip:CreateTexture(nil, "ARTWORK"); green:SetAllPoints(b); green:SetColorTexture(0.2, 1, 0.2, 0.9)
			sp.parts.D, sp.parts.Dclip = sb, clip
		end)
	end
	-- E: the same with the aura absent (a HARMFUL filter never finds the buff): the button is hidden, the
	-- clip lives outside it (as EverAuras' late clip does)
	do
		local host = cell(4, "E: blue")
		local c = container(host, host)
		slot(c, "E", "HARMFUL", id, function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local sb = bar(b); sb:SetAllPoints(b); sb:SetStatusBarColor(0, 0, 0, 0)
			stry("E SetApplicationBar(min 0, max 3)", b.SetApplicationBar, b, sb, { minApplications = 0, maxApplications = 3 })
			local clip = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
			clip:SetClipsChildren(true)
			clip:SetFrameLevel(host:GetFrameLevel() + 3)
			stry("E clip TOPLEFT -> fill TOPRIGHT", clip.SetPoint, clip, "TOPLEFT", sb:GetStatusBarTexture(), "TOPRIGHT")
			stry("E clip BOTTOMRIGHT -> bar BOTTOMRIGHT", clip.SetPoint, clip, "BOTTOMRIGHT", sb, "BOTTOMRIGHT")
			local blue = clip:CreateTexture(nil, "ARTWORK"); blue:SetAllPoints(host); blue:SetColorTexture(0.2, 0.5, 1, 0.9)
			sp.parts.E, sp.parts.Eclip, sp.parts.Ebutton = sb, clip, b
		end)
	end
	-- F1 / F2: a gate frame AROUND the container, clipping the aura button; its edges hang on a bar
	-- inside that button (the button itself hangs on the host, so there is no loop)
	for i, kind in ipairs({ "F1", "F2" }) do
		local host = cell(4 + i, kind == "F1" and "F1: icon (time bar)" or "F2: icon (0 stacks)")
		local gate = CreateFrame("Frame", nil, host, "DisableUntrustedLayoutScriptsTemplate")
		gate:SetClipsChildren(true)
		gate:SetFrameLevel(host:GetFrameLevel() + 1)
		local c = container(gate, host)
		slot(c, kind, "HELPFUL", id, function(b)
			b:ClearAllPoints(); b:SetAllPoints(host)
			local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b)
			stry(kind .. " SetIcon", b.SetIcon, b, icon)
			local sb = bar(b); sb:SetAllPoints(b); sb:SetStatusBarColor(0, 0, 0, 0)
			local fill = sb:GetStatusBarTexture()
			if kind == "F1" then   -- gate = the fill: the icon minus the time gone
				local dirs = Enum and Enum.StatusBarTimerDirection
				stry("F1 SetDurationBar(RemainingTime)", b.SetDurationBar, b, sb, { direction = dirs and dirs.RemainingTime })
				stry("F1 gate TOPLEFT -> bar TOPLEFT", gate.SetPoint, gate, "TOPLEFT", sb, "TOPLEFT")
				stry("F1 gate BOTTOMRIGHT -> fill BOTTOMRIGHT", gate.SetPoint, gate, "BOTTOMRIGHT", fill, "BOTTOMRIGHT")
			else                   -- gate = from the fill's edge to the bar's end: all of it at 0 stacks
				stry("F2 SetApplicationBar(min 0, max 1)", b.SetApplicationBar, b, sb, { minApplications = 0, maxApplications = 1 })
				stry("F2 gate TOPLEFT -> fill TOPRIGHT", gate.SetPoint, gate, "TOPLEFT", fill, "TOPRIGHT")
				stry("F2 gate BOTTOMRIGHT -> bar BOTTOMRIGHT", gate.SetPoint, gate, "BOTTOMRIGHT", sb, "BOTTOMRIGHT")
			end
			sp.parts[kind], sp.parts[kind .. "gate"] = sb, gate
		end)
	end

	C_Timer.After(0.3, function()
		if not sp.parts then return end
		local P = sp.parts
		local function minmax(sb)
			local ok, lo, hi = pcall(sb.GetMinMaxValues, sb)
			local okV, v = pcall(sb.GetValue, sb)
			return ("min/max %s/%s value %s"):format(ok and show(lo) or "ERR", ok and show(hi) or "ERR", okV and show(v) or "ERR")
		end
		if P.B then slog("B %s | fill %s | bar %s", minmax(P.B), rect(P.B:GetStatusBarTexture()), rect(P.B)) end
		if P.C then slog("C %s | bar shown %s (want false)", minmax(P.C), show(P.C:IsShown())) end
		if P.D then slog("D %s | fill %s | clip %s (want the whole box)", minmax(P.D), rect(P.D:GetStatusBarTexture()), rect(P.Dclip)) end
		if P.E then slog("E %s | button shown %s | fill %s | clip %s (want the whole box)", minmax(P.E), show(P.Ebutton:IsShown()), rect(P.E:GetStatusBarTexture()), rect(P.Eclip)) end
		if P.F1 then slog("F1 fill %s | gate %s (want nearly the whole box)", rect(P.F1:GetStatusBarTexture()), rect(P.F1gate)) end
		if P.F2 then slog("F2 %s | gate %s (want the whole box)", minmax(P.F2), rect(P.F2gate)) end
		slog("Now compare the boxes with their captions, then fight something and look again. /fdstack hide removes it.")
	end)
end

SLASH_FDISTACK1 = "/fdstack"
SlashCmdList.FDISTACK = function(msg)
	msg = strtrim(msg or "")
	if msg == "hide" then
		for _, h in ipairs(sp.hosts or {}) do h:Hide() end
		sp.hosts, sp.parts = nil, nil
		slog("removed")
		return
	end
	build(msg ~= "" and msg or "Demon Armor")
end
