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
       /fddyn chain    rows 1 and 2, plus rows 3 and 4 built the way EverAuras would pack its own displays:
                         every icon keeps its OWN aura slot in its own frame (as an engine-driven display
                         does), and only its POSITION comes from the game: a chain of invisible containers,
                         one per spell, each 1 px wide plus one icon while that spell's aura is up. Icon k
                         hangs on the end of link k-1, so the icons pack.
                         row 3 grows to the RIGHT from a red mark
                         row 4 grows from the CENTER around a red mark (a container of all the spells,
                         anchored by its TOP, measures the row)
                       Rows 3 and 4 should look exactly like rows 1 and 2, in combat too.
       /fddyn chain player   the same for buffs on you
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

-- Frames anchored to a container that owns an aura group must carry its layout-script ban themselves
-- (Blizzard_CustomAuraContainer.lua AddAuraGroup); frames CREATED inside such a frame inherit it.
local LAYOUT_SAFE = "DisableUntrustedLayoutScriptsTemplate"

local function ChainIcon(button, letter)
	button:SetSize(SIZE, SIZE)
	pcall(button.SetMouseClickEnabled, button, false)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	pcall(cd.SetDrawBling, cd, false)
	local tag = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tag:SetPoint("BOTTOM", button, "TOP", 0, 1)
	tag:SetText(letter)
	button:SetIcon(icon)
	button:SetDurationCooldown(cd)
end

-- An invisible group of at most one button on one spell: the container is 1 px (its left padding)
-- plus 'w' wide while the aura is up, 1 px while it is not (AnchorUtil.ApplyFlowLayout: max(size, 1)).
local function AddMeasure(c, key, filter, set, w)
	return pcall(c.AddAuraGroup, c, key, filter, {
		candidateFilters = { includeSpellIDs = set },
		maxFrameCount = 1,
		layout = { elementWidth = w, elementHeight = SIZE, groupSpacing = SPACING },
		initializeFrame = function(button)
			button:SetSize(w, SIZE)
			pcall(button.SetMouseClickEnabled, button, false)
		end,
	})
end

local function BuildChainRow(rowName, unit, filter, list, centred, x, y)
	local function step(what, ok, err)
		if not ok then dlog("%s: %s failed: %s", rowName, what, tostring(err)) end
		return ok
	end
	local root = CreateFrame("Frame", nil, UIParent, LAYOUT_SAFE)
	root:SetPoint("CENTER")
	root:SetSize(1, 1)
	local mark = Mark(UIParent, { x, y })
	local title = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("BOTTOM", UIParent, "CENTER", x, y + SIZE + 14)
	title:SetText(("FDI dyn %s (%s, chain, %s)"):format(rowName, unit, centred and "grows from the centre" or "grows right"))
	local row = { mark = mark, title = title, frames = { root }, containers = {} }

	-- where the chain starts: the mark, or (centred) 1 px in from the left edge of a container that
	-- holds every spell, is 2 px plus the row wide, and hangs from the mark by its TOP
	local startFrame, startPoint, startX, startY = UIParent, "CENTER", x - 1, y
	if centred then
		local total = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
		row.containers[#row.containers + 1] = total
		step("total padding", pcall(total.SetFlowLayoutPadding, total, 1, 1, 0, 0))
		for i, entry in ipairs(list) do
			step("total group " .. entry[1], AddMeasure(total, "t" .. i, filter, (IdSet(entry)), SIZE))
		end
		step("total anchor", pcall(total.SetPoint, total, "TOP", UIParent, "CENTER", x, y))
		pcall(total.SetUnit, total, unit)
		pcall(total.UpdateAllAuras, total)
		startFrame, startPoint, startX, startY = total, "TOPLEFT", 0, 0
	end

	local prev, made = nil, 0
	for i, entry in ipairs(list) do
		local set = IdSet(entry)
		-- the link: as wide as this icon plus the gap while its aura is up
		local link = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
		row.containers[#row.containers + 1] = link
		step("link padding " .. entry[1], pcall(link.SetFlowLayoutPadding, link, 1, 0, 0, 0))
		local okL = step("link group " .. entry[1], AddMeasure(link, "l", filter, set, SIZE + SPACING))
		if prev then
			step("link anchor " .. entry[1], pcall(link.SetPoint, link, "TOPLEFT", prev, "TOPRIGHT", -1, 0))
		else
			step("link anchor " .. entry[1], pcall(link.SetPoint, link, "TOPLEFT", startFrame, startPoint, startX, startY))
		end
		pcall(link.SetUnit, link, unit)
		-- the icon: its own frame and its own slot, as an engine-driven display has; it hangs 1 px into
		-- its link, i.e. right after every icon before it that is up
		local host = CreateFrame("Frame", nil, UIParent, LAYOUT_SAFE)
		host:SetSize(SIZE, SIZE)
		host:SetFrameStrata("HIGH")
		local okH = step("host anchor " .. entry[1], pcall(host.SetPoint, host, "TOPLEFT", link, "TOPLEFT", 1, 0))
		local slot = CreateFrame("AuraContainer", nil, host, "CustomAuraContainerTemplate")
		slot:SetPoint("TOPLEFT", host, "TOPLEFT")
		local okS = step("slot " .. entry[1], pcall(slot.AddAuraSlot, slot, "s", filter, {
			candidateFilters = { includeSpellIDs = set },
			initializeFrame = function(button)
				button:ClearAllPoints()
				button:SetAllPoints(host)
				ChainIcon(button, entry[1])
			end,
		}))
		pcall(slot.SetUnit, slot, unit)
		pcall(slot.UpdateAllAuras, slot)
		pcall(link.UpdateAllAuras, link)
		row.frames[#row.frames + 1] = host
		row.containers[#row.containers + 1] = slot
		if okL and okH and okS then made = made + 1 end
		prev = link
	end
	-- can a plain frame (like a WeakAuras region) hang on a frame anchored to the chain? (expected: no)
	local plain = CreateFrame("Frame", nil, UIParent)
	local okP, errP = pcall(plain.SetPoint, plain, "CENTER", row.frames[2] or root, "CENTER")
	dlog("%s: plain frame on a chained icon frame: %s", rowName, okP and "allowed" or ("refused: " .. tostring(errP)))
	plain:Hide()
	dlog("%s: %d of %d icons chained on %s (%s)", rowName, made, #list, unit, filter)
	return row
end

local function Remove()
	for _, row in ipairs(probe.built) do
		if row.container then row.container:Hide(); pcall(row.container.SetUnit, row.container, nil) end
		for _, c in ipairs(row.containers or {}) do c:Hide(); pcall(c.SetUnit, c, nil) end
		for _, f in ipairs(row.frames or {}) do f:Hide() end
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
	local chain = msg:find("^chain") ~= nil
	local player = msg == "player" or msg == "chain player"
	local unit = player and "player" or "target"
	local filter = player and "HELPFUL|PLAYER" or "HARMFUL|PLAYER"
	local list = player and PLAYER or TARGET
	local order = {}
	for _, e in ipairs(list) do order[#order + 1] = e[1] .. "=" .. e[2] end
	dlog("priority: %s", table.concat(order, " > "))
	probe.built[#probe.built + 1] = BuildRow("row 1", unit, filter, list, "TOPLEFT", -300, 180)
	probe.built[#probe.built + 1] = BuildRow("row 2", unit, filter, list, "TOP", 0, 100)
	if chain then
		probe.built[#probe.built + 1] = BuildChainRow("row 3", unit, filter, list, false, -300, 260)
		probe.built[#probe.built + 1] = BuildChainRow("row 4", unit, filter, list, true, 0, 340)
		dlog("built. Rows 3 and 4 (chain) should match rows 1 and 2, in combat too, holes included.")
		return
	end
	dlog("built. Cast in different orders (in combat too): packed, no holes, priority order? row 2 centred?")
end
