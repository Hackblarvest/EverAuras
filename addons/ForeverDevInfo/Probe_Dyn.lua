--[[ Forever Dev Info - /fddyn: can the game's aura container BE a dynamic group?

     A WeakAuras Dynamic Group closes the gap when a child hides. Engine-driven children never hide for
     WeakAuras (their trigger is handed to the game and reports "always on"), so a dynamic group of them
     keeps holes where an aura is missing. Blizzard's CustomAuraContainer has its own flow layout: every
     aura GROUP adds only the buttons of auras that exist, in registration order, and an empty group
     takes no room (Blizzard_CustomAuraContainer.lua GetFlowLayoutGroupDescriptions). If that holds in
     combat, one container with one group per spell is a dynamic group the game lays out itself.

       /fddyn          two rows for your DoTs on the target, priority Corruption > Immolate > Curse of
                       Agony > Curse of Weakness > Serpent Sting > Hunter's Mark:
                         row 1 grows to the RIGHT from a red mark (container anchored by its TOPLEFT)
                         row 2 grows from the CENTER around a red mark (container anchored by its TOP)
       /fddyn player   the same for buffs on you (Demon Skin, Demon Armor, Aspects)
       /fddyn hide     removes the rows

     Build OUT OF COMBAT with a target. Then cast your DoTs in different orders on fresh mobs, in combat:
     do the icons stay packed (no holes) and in priority order, whatever you cast first? Does row 2
     stay centred? Each icon has its spell's initial on top. Logs to ForeverDevInfoDB.dynProbe.
]]

local probe = { built = {} }

local function dlog(fmt, ...)
	local line = select("#", ...) > 0 and fmt:format(...) or fmt
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.dynProbe = ForeverDevInfoDB.dynProbe or {}
	local l = ForeverDevInfoDB.dynProbe
	l[#l + 1] = date("%H:%M:%S") .. " " .. line
	while #l > 200 do table.remove(l, 1) end
	print("|cff33ff99FDI dyn|r " .. line)
end

-- priority order = registration order
local TARGET = {
	{ "C", "Corruption", { 172, 6222, 6223, 7648, 11671, 11672, 25311, 27216 } },
	{ "I", "Immolate", { 348, 707, 1094, 2941, 11665, 11667, 11668, 25309, 27215 } },
	{ "A", "Curse of Agony", { 980, 1014, 6217, 11711, 11712, 11713, 27218 } },
	{ "W", "Curse of Weakness", { 702, 1108, 6205, 7646, 11707, 11708, 27224 } },
	{ "S", "Serpent Sting", { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 27016 } },
	{ "M", "Hunter's Mark", { 1130, 14323, 14324, 14325 } },
}
local PLAYER = {
	{ "S", "Demon Skin", { 687, 696 } },
	{ "A", "Demon Armor", { 706, 1086, 11733, 11734, 11735, 27260 } },
	{ "H", "Aspect of the Hawk", { 13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044 } },
	{ "M", "Aspect of the Monkey", { 13163 } },
	{ "C", "Aspect of the Cheetah", { 5118 } },
}

local SIZE, SPACING = 36, 4

-- every rank listed, plus whatever the spellbook resolves the name to on this client
local function IdSet(entry)
	local set, n = {}, 0
	for _, id in ipairs(entry[3]) do set[id] = true; n = n + 1 end
	local ok, info = pcall(C_Spell.GetSpellInfo, entry[2])
	if ok and info and info.spellID and not (issecretvalue and issecretvalue(info.spellID)) and not set[info.spellID] then
		set[info.spellID] = true; n = n + 1
	end
	return set, n
end

local function Mark(parent, point)
	local m = UIParent:CreateTexture(nil, "OVERLAY")
	m:SetColorTexture(1, 0.1, 0.1, 0.9)
	m:SetSize(6, 6)
	m:SetPoint("CENTER", UIParent, "CENTER", point[1], point[2])
	return m
end

local function BuildRow(rowName, unit, filter, list, anchorPoint, x, y)
	if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	if not ok or not c then dlog("%s: container failed: %s", rowName, tostring(c)); return end
	-- the container's own anchor point decides how it grows: TOPLEFT -> right, TOP -> both ways (centred)
	c:SetPoint(anchorPoint, UIParent, "CENTER", x, y)
	c:SetFrameStrata("HIGH")
	local mark = Mark(UIParent, { x, y })
	local title = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("BOTTOM", UIParent, "CENTER", x, y + SIZE + 14)
	title:SetText(("FDI dyn %s (%s, %s)"):format(rowName, unit, anchorPoint == "TOP" and "grows from the centre" or "grows right"))
	local made = 0
	for i, entry in ipairs(list) do
		local set, n = IdSet(entry)
		local key = "fddyn" .. i
		local okG, err = pcall(c.AddAuraGroup, c, key, filter, {
			candidateFilters = { includeSpellIDs = set },
			maxFrameCount = 1,
			layout = { elementWidth = SIZE, elementHeight = SIZE, groupSpacing = SPACING, elementSpacing = SPACING },
			initializeFrame = function(button)
				button:SetSize(SIZE, SIZE)
				pcall(button.SetMouseClickEnabled, button, false)
				local icon = button:CreateTexture(nil, "ARTWORK")
				icon:SetAllPoints(button)
				local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
				cd:SetAllPoints(icon)
				pcall(cd.SetDrawBling, cd, false)
				local tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
				tag:SetPoint("BOTTOM", button, "TOP", 0, 1)
				tag:SetText(entry[1])
				button:SetIcon(icon)
				button:SetDurationCooldown(cd)
			end,
		})
		if okG then made = made + 1 else dlog("%s: group %s (%s) failed: %s", rowName, entry[1], entry[2], tostring(err)) end
		if okG and i == 1 then dlog("%s: group %s = %s, %d ids", rowName, entry[1], entry[2], n) end
	end
	pcall(c.SetUnit, c, unit)
	pcall(c.UpdateAllAuras, c)
	dlog("%s: %d groups on %s (%s), container anchored by its %s", rowName, made, unit, filter, anchorPoint)
	return { container = c, mark = mark, title = title }
end

local function Remove()
	for _, row in ipairs(probe.built) do
		if row.container then row.container:Hide(); pcall(row.container.SetUnit, row.container, nil) end
		if row.mark then row.mark:Hide() end
		if row.title then row.title:Hide() end
	end
	probe.built = {}
end

SLASH_FDDYN1 = "/fddyn"
SlashCmdList.FDDYN = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "hide" then Remove(); dlog("removed"); return end
	if InCombatLockdown() then dlog("leave combat first: the rows are built out of combat"); return end
	Remove()
	local player = msg == "player"
	local unit = player and "player" or "target"
	local filter = player and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
	local list = player and PLAYER or TARGET
	local order = {}
	for _, e in ipairs(list) do order[#order + 1] = e[1] .. "=" .. e[2] end
	dlog("priority: %s", table.concat(order, " > "))
	probe.built[#probe.built + 1] = BuildRow("row 1", unit, filter, list, "TOPLEFT", -300, 180)
	probe.built[#probe.built + 1] = BuildRow("row 2", unit, filter, list, "TOP", 0, 100)
	dlog("built. Cast in different orders (in combat too): packed, no holes, priority order? row 2 centred?")
end
