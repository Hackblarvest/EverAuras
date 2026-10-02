--[[ Forever Dev Info - /fdtext: what is drawn by an engine-driven Text display, and why it shows.

     A Missing Text display ("NO DEMON SKIN!") stayed visible with the aura up (2026-10-01/02, OUTLINE|SLUG
     font, size 32, animations). Two texts can be on screen: WeakAuras' own (hidden by the engine) and the
     engine's copy in the Missing clip. This tells them apart.

       /fdtext [name]  state of that Text display (default: the first engine-driven Text display)
       /fdtext wa      hide / show WeakAuras' own text of that display
       /fdtext ours    hide / show the engine's copy (the Missing clip text and the Found label)
       /fdtext clip    hide / show the engine's whole Missing clip

     Try it with the aura UP (the text should be gone): run /fdtext, then /fdtext wa, then /fdtext ours,
     and see which one makes the text disappear. Logs to ForeverDevInfoDB.textProbe.
]]

local targetId

local function tlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.textProbe = ForeverDevInfoDB.textProbe or {}
	local l = ForeverDevInfoDB.textProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 300 do table.remove(l, 1) end
	print("|cff33ff99FDI text|r " .. line)
end

local function show(v)
	if issecretvalue and issecretvalue(v) then return "<secret>" end
	if type(v) == "number" then return ("%.1f"):format(v) end
	return tostring(v)
end

local function call(obj, method, ...)
	if not obj or not obj[method] then return "n/a" end
	local r = { pcall(obj[method], obj, ...) }
	if not r[1] then return "err" end
	local out = {}
	for i = 2, #r do out[#out + 1] = show(r[i]) end
	return table.concat(out, ",")
end

local function rect(f)
	if not f then return "nil" end
	return call(f, "GetRect")
end

local function addon() return _G.EverAuras end

local function pick(name)
	local EA = addon()
	if not (EA and EA.GetRegion) then return end
	if name and name ~= "" then return name, EA.GetRegion(name) end
	if targetId then return targetId, EA.GetRegion(targetId) end
	local saved = _G.EverAurasSaved
	for id, d in pairs(saved and saved.displays or {}) do
		if d.regionType == "text" and d.foreverEngine ~= false then return id, EA.GetRegion(id) end
	end
end

local function report(id, region)
	local EA = addon()
	tlog("== %s (%s)", tostring(id), date("%H:%M:%S"))
	if not region then tlog("no region"); return end
	local data = EA.GetData and EA.GetData(id)
	tlog("display: shown=%s alpha=%s rect=%s outline=%s size=%s justify=%s width=%s",
		call(region, "IsShown"), call(region, "GetAlpha"), rect(region),
		tostring(data and data.outline), tostring(data and data.fontSize), tostring(data and data.justify),
		tostring(data and data.automaticWidth))
	local t = region.text
	tlog("WA text: shown=%s visible=%s alpha=%s font=%s strW=%s rect=%s text=%s",
		call(t, "IsShown"), call(t, "IsVisible"), call(t, "GetAlpha"), call(t, "GetFont"), call(t, "GetStringWidth"),
		rect(t), call(t, "GetText"))
	local att = EA.ForeverEngineDebug and EA.ForeverEngineDebug(region)
	if not att then tlog("engine: no attachment (not engine-driven here)"); return end
	tlog("engine: active=%s mode=%s kind=%s broken=%s textW=%s textH=%s groupBuilt=%s groupW=%s groupH=%s groupM=%s",
		tostring(att.active), tostring(att.mode), tostring(att.kind), tostring(att.broken), tostring(att.textW),
		tostring(att.textH), tostring(att.groupBuilt), tostring(att.groupW), tostring(att.groupH), tostring(att.groupM))
	tlog("host: shown=%s rect=%s | container: rect=%s", call(att.host, "IsShown"), rect(att.host), rect(att.container))
	local s = att.shadows or {}
	tlog("clip: shown=%s visible=%s clips=%s rect=%s", call(s.clip, "IsShown"), call(s.clip, "IsVisible"),
		call(s.clip, "DoesClipChildren"), rect(s.clip))
	tlog("engine text (Missing): shown=%s visible=%s alpha=%s font=%s strW=%s rect=%s text=%s parentIsClip=%s",
		call(s.underText, "IsShown"), call(s.underText, "IsVisible"), call(s.underText, "GetAlpha"),
		call(s.underText, "GetFont"), call(s.underText, "GetStringWidth"), rect(s.underText), call(s.underText, "GetText"),
		tostring(s.underText and s.clip and s.underText:GetParent() == s.clip))
	tlog("animations: start=%s main=%s finish=%s", tostring(data and data.animation and data.animation.start and data.animation.start.preset),
		tostring(data and data.animation and data.animation.main and data.animation.main.preset),
		tostring(data and data.animation and data.animation.finish and data.animation.finish.preset))
	if s.label then
		tlog("engine text (Found): shown=%s visible=%s text=%s", call(s.label, "IsShown"), call(s.label, "IsVisible"),
			call(s.label, "GetText"))
	end
	local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 696)
	local ok2, b = pcall(C_UnitAuras.GetPlayerAuraBySpellID, 687)
	tlog("Demon Skin on you (out of combat readable): 696=%s 687=%s", ok and show(a ~= nil) or "err", ok2 and show(b ~= nil) or "err")
end

local function toggle(obj, label)
	if not obj then tlog("%s: not there", label); return end
	local ok, shown = pcall(obj.IsShown, obj)
	if not ok or (issecretvalue and issecretvalue(shown)) then tlog("%s: shown state not readable", label); return end
	local ok2, err = pcall(obj.SetShown, obj, not shown)
	tlog("%s: %s%s", label, shown and "hidden" or "shown again", ok2 and "" or (" (refused: " .. tostring(err) .. ")"))
end

SLASH_FDTEXT1 = "/fdtext"
SlashCmdList.FDTEXT = function(msg)
	msg = strtrim(msg or "")
	local cmd = msg:lower()
	if cmd == "alpha" then
		-- does WA's own text take SetAlpha / Hide? (a SLUG font may not)
		local id, region = pick()
		if not (region and region.text) then tlog("no Text display found"); return end
		targetId = id
		local t = region.text
		local before = call(t, "GetAlpha")
		pcall(t.SetAlpha, t, 0)
		tlog("WA text SetAlpha(0): alpha %s -> %s", before, call(t, "GetAlpha"))
		local shownBefore = call(t, "IsShown")
		pcall(t.Hide, t)
		tlog("WA text Hide(): shown %s -> %s (visible %s). Is the text gone now? /fdtext wa brings it back", shownBefore,
			call(t, "IsShown"), call(t, "IsVisible"))
		return
	end
	if cmd == "mark" then
		-- give every text that could be on screen its own name: whatever still reads NO DEMON SKIN! is none of them
		local id, region = pick()
		if not region then tlog("no Text display found"); return end
		targetId = id
		local function mark(fs, label)
			if not fs then return end
			pcall(fs.SetText, fs, label)
			tlog("%s: shown=%s visible=%s alpha=%s rect=%s", label, call(fs, "IsShown"), call(fs, "IsVisible"),
				call(fs, "GetAlpha"), rect(fs))
		end
		mark(region.text, "[WA]")
		local all = addon().ForeverEngineDebug and addon().ForeverEngineDebug() or {}
		local n = 0
		for r, att in pairs(all) do
			if r == region or (type(r) == "table" and r.id == id) then
				n = n + 1
				local tag = r == region and "" or (" ORPHAN" .. n)
				tlog("attachment%s: active=%s mode=%s kind=%s", tag, tostring(att.active), tostring(att.mode), tostring(att.kind))
				if r ~= region then mark(r.text, "[WA" .. tag .. "]") end
				local s = att.shadows or {}
				mark(s.underText, "[CLIP" .. tag .. "]")
				mark(s.measure, "[MEASURE" .. tag .. "]")
				mark(s.label, "[LABEL" .. tag .. "]")
				mark(s.duration, "[DURATION" .. tag .. "]")
				mark(s.count, "[COUNT" .. tag .. "]")
				mark(s.name, "[NAME" .. tag .. "]")
			end
		end
		tlog("marked %d attachment(s). Screenshot now; /reload restores the texts.", n)
		return
	end
	if cmd == "both" then
		local id, region = pick()
		if not region then tlog("no Text display found"); return end
		targetId = id
		local att = addon().ForeverEngineDebug and addon().ForeverEngineDebug(region)
		local s = att and att.shadows or {}
		toggle(region.text, "WeakAuras' own text")
		toggle(s.underText, "engine text (Missing)")
		return
	end
	if cmd == "wa" or cmd == "ours" or cmd == "clip" then
		local id, region = pick()
		if not region then tlog("no Text display found"); return end
		targetId = id
		if cmd == "wa" then toggle(region.text, "WeakAuras' own text"); return end
		local att = addon().ForeverEngineDebug and addon().ForeverEngineDebug(region)
		local s = att and att.shadows or {}
		if cmd == "ours" then
			toggle(s.underText, "engine text (Missing)")
			if s.label then toggle(s.label, "engine text (Found)") end
		else
			toggle(s.clip, "engine Missing clip")
		end
		return
	end
	local id, region = pick(msg)
	if region then targetId = id end
	report(id, region)
end
