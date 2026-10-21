--[[ Probe_ManaShield.lua - Mana Shield in combat: can addon code know, or at least DRAW, how much of it is left?

     Written for the ForeverDevInfo dev addon (Probe_ManaShield.lua in both TOCs; copy the addon folder into the
     client's Interface\AddOns\ForeverDevInfo, then /reload); it logs into
     ForeverDevInfoDB.msProbe (max 1500 lines). Mana Shield (aura 97; ranks 1463, 8494, 8495, 10191, 10192,
     10193 absorb 120/210/300/390/480/570, PHYSICAL damage only, 2 mana per point, 1 min) is not a school
     absorb, so UnitGetTotalAbsorbs leaves it out, and in combat the aura getters are closed to addon code. This
     probe tries every route the research found at the same time and gives each one its own row on a panel.
     Nothing here reads, compares or does arithmetic on a secret: secret values only ever go to widget setters
     the documentation marks AllowedWhenTainted (FontString:SetText, StatusBar:SetValue, SetAlphaFromBoolean,
     Texture:SetTexture), every call sits in a pcall, and each refusal is logged once per combat state. Each
     route is read in its own pcall, so one route that breaks in combat does not blank the rows after it.
     Known dead ends kept for completeness: the buff tooltip text has no $w1 in this client (no amount in
     it), and C_Spell.IsActiveSpell is meant for toggled spells.

     Round 1 (local server, rank 2) found: the aura's points are {} even out of combat (Mana Shield lacks the
     "aura points on client" attribute every other shield has), so every points[] row is dead; in combat every
     aura getter and C_TooltipInfo refuse; UnitGetTotalAbsorbs is 0; the combat log and combat text stay
     silent; UNIT_COMBAT stays plain ("WOUND ABSORB amount 0" = a fully absorbed hit). What works is the damage
     meter (even with damageMeterEnabled 0): your own row of the Current session's Absorbs (isLocalPlayer is
     NeverSecret) is secret in combat but drawable, and plain again after the fight. So round 2 does the
     arithmetic where it is allowed, on plain values between fights, and the rest by geometry:
       - bookkeeping: each shield's full size F, instance id and expirationTime (read plainly right after an
         out of combat cast) and its remaining amount, lowered after every fight by what the meter credits
         Mana Shield with (plain once the fight is over). That remaining amount is R0 of the next fight. After
         each fight 2-3 chat lines say what was absorbed, what is left, and whether the shield is still up,
         BROKE or EXPIRED.
       - "Meter: R0 - absorbed": R0 minus your meter total since the pull, drawn by a driver bar's geometry.
       - "Meter: F-(now-cast)": for a shield cast IN combat the meter's value at the cast is frozen in a
         hidden driver bar and the live value drives a second one; the frame between their fill ends (+F px)
         is what is left, again by geometry only. Its text is not clamped: below 0 = more absorbed since the
         cast than the shield holds (a Ward counted after it broke); its bar stops at 0.
       - break watch (UNIT_COMBAT): fully absorbed hits, a partly absorbed hit (the one that broke the shield)
         and the first hit that got through after absorbed ones, each with its time in the fight. With the
         time a shield was seen removed, they tell BROKE from EXPIRED when the meter alone cannot.
       - the meter's sessions: the plain state before each pull and after each fight (session ids, names,
         durations, your totals), to show whether Current restarts at 0 for each fight or keeps running.
     Both meter rows count ALL your absorbs (Fire/Frost Ward, Ice Barrier too), not only Mana Shield.

       /fdms             one-shot report in chat + the panel (the shield's ids and time left, the bookkeeping,
                         the meter's sessions)
       /fdms watch [s]   event log for fights, default 600 s: hits, aura updates, absorb/power/meter/combat text
                         events, restriction changes. Details go to the log only; in chat one line at the pull,
                         a count line every 15 s of combat, and 2-3 lines when the fight is settled.
       /fdms raid        group check: restriction states, per member aura access, an aura container per member
                         filtered to Mana Shield and UnitGetTotalAbsorbs drawn above the panel
       /fdms fct         (out of combat) switches on floating combat text and its absorb/aura options (CVars)
       /fdms hide        stops the watch and removes the panel

     The panel: green text = a live secret value drawn by the game, white = plain, grey = nil, orange = refused,
     yellow = the "R0 - absorbed" row after a recast (it then describes the replaced shield). The "R0 - absorbed"
     bar is blue for what should be left and dark for what was absorbed; the "F-(now-cast)" bar's fill is what
     is left.

     The bookkeeping needs the watch running from before the pull: a fight it did not see begin is not settled,
     and the shield's amount is unknown after it (the next pull then takes the full size, and says so).

     Suggested run for round 2 (level 30 mage, Mana Shield rank 2 = 210; no Fire/Frost Ward, so the meter is
     Mana Shield only): /fdms watch 900, then
     (1) out of combat cast Mana Shield, pull a level 20-25 melee mob, take 2-3 hits, kill it; read the chat.
     (2) right away, while the shield is still up, pull the next one and let the shield BREAK (keep taking hits
         until they get through), kill it.
     (3) pull with no shield, take a hit, cast Mana Shield IN combat, take hits (watch "F-(now-cast)"),
         kill it.
     Wait for the 3 chat lines after each fight (up to ~5 s) before the next pull, or that fight is not settled.
     (4) /reload so the log lands in SavedVariables.
]]

local P = {
	fs = {}, fs2 = {}, bars = {}, icons = {}, sq = {},
	st = { ooc = {}, combat = {} }, cnt = {}, fight = {}, errSeen = {}, bugSeen = {}, descSeen = {}, raid = {},
}
local Refresh, SetR0, Count, Bug          -- defined further down

local PREFIX = "|cff66ccffms|r "
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CAP = 1500
local W, ROW, VX, BX = 560, 16, 196, 346   -- panel width, row height, value column, bar column
local DUR = 60              -- every rank lasts 1 min (client data): the end of a shield cast in combat is estimated with it
local M_PX = 4096           -- the "at cast"/"now" driver bars: 1 px per meter point, this many points wide (more if needed)
local SETTLE_TRIES = 10     -- after a fight: wait up to 10 x 0.5 s for the meter and the auras to turn plain

-- client data (Spell.db2 / SpellEffect.db2, build 70450): flat absorb per rank, no level or spell power scaling
local RANKS = { [1463] = 120, [8494] = 210, [8495] = 300, [10191] = 390, [10192] = 480, [10193] = 570 }
-- leftover Season of Discovery "Advanced Warding" copies: aura 69 (a normal absorb), counted by UnitGetTotalAbsorbs
local WARDING = { [412116] = 240, [412118] = 420, [412120] = 600, [412121] = 780, [412122] = 960, [412123] = 1140 }
local ORDER = { 10193, 10192, 10191, 8495, 8494, 1463, 412123, 412122, 412121, 412120, 412118, 412116 }
local FULL, INCLUDE = {}, {}
for id, n in pairs(RANKS) do FULL[id], INCLUDE[id] = n, true end
for id, n in pairs(WARDING) do FULL[id], INCLUDE[id] = n, true end
local SECRECY = { [0] = "NeverSecret", [1] = "AlwaysSecret", [2] = "ContextuallySecret" }

local E = Enum or {}
local MANA = E.PowerType and E.PowerType.Mana or 0
local DMT = E.DamageMeterType or {}
local M_ABS, M_HEAL, M_TAKEN = DMT.Absorbs or 4, DMT.HealingDone or 2, DMT.DamageTaken or 7
local M_CUR = E.DamageMeterSessionType and E.DamageMeterSessionType.Current or 1
local RT = E.AddOnRestrictionType or {}
local R_COMBAT, R_ENC, R_MAP, R_CHAT = RT.Combat or 0, RT.Encounter or 1, RT.Map or 4, RT.Chat or 5
local RS = E.AddOnRestrictionState or {}
local S_ACTIVATING = RS.Activating or 1
local RT_NAME = { [0] = "Combat", [1] = "Encounter", [2] = "ChallengeMode", [3] = "PvPMatch", [4] = "Map", [5] = "Chat" }
local RS_NAME = { [0] = "Inactive", [1] = "Activating", [2] = "Active" }
for k, v in pairs(RT) do RT_NAME[v] = k end
for k, v in pairs(RS) do RS_NAME[v] = k end
local CDM_CATS = { (E.CooldownViewerCategory and E.CooldownViewerCategory.TrackedBuff) or 2,
	(E.CooldownViewerCategory and E.CooldownViewerCategory.TrackedBar) or 3 }
local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer" }

-- every route = one row on the panel and one verdict at the end of a fight
-- kinds: bar = text + bar, text = wide text, text2 = two texts, rem = readout + remaining bar,
--        square = alpha square + text, cont = an aura container slot, none = verdict only
local CANDS = {
	{ "abs",     "UnitGetTotalAbsorbs",              "bar" },
	{ "cdm",     "Cooldown Manager points[1]",       "bar" },
	{ "inst",    "AuraByInstanceID points[1]",       "bar" },
	{ "spell",   "PlayerAuraBySpellID points[1]",    "bar" },
	{ "uspell",  "UnitAuraBySpellID points[1]",      "bar" },
	{ "name",    "AuraDataBySpellName points[1]",    "bar" },
	{ "index",   "AuraDataByIndex(i) points[1]",     "bar", icon = true },
	{ "units",   "GetUnitAuras[i] points[1]",        "bar", icon = true },
	{ "dur",     "GetAuraDuration(inst)",            "text" },
	-- the buff text in this client has no $w1 ("Absorbs physical damage, draining mana instead."), so the
	-- two tooltip rows can only show presence/text, never the amount
	{ "tipinfo", "C_TooltipInfo line 2 (text)",      "text" },
	{ "tip",     "own GameTooltip line 2 (text)",    "text" },
	-- the meter rows count ALL your absorbs (Wards, Ice Barrier), not only Mana Shield
	{ "mabs",    "Meter Absorbs (you, all absorbs)", "bar" },
	{ "mrem",    "Meter: R0 - absorbed (all absorbs)", "rem" },
	{ "mcast",   "Meter: F-(now-cast) (all absorbs)", "bar" },
	{ "mheal",   "Meter HealingDone (you)",          "text" },
	{ "mtaken",  "Meter DamageTaken (you)",          "text" },
	{ "mspell",  "Meter Absorbs: spell 1 / amount",  "text2", icon = true },
	{ "ctabs",   "Combat text ABSORB data / arg3",   "text2" },
	{ "ctend",   "Combat text AURA_START/END",       "text", icon = true },
	{ "ucomb",   "UNIT_COMBAT (last)",               "text" },
	{ "uaura",   "UNIT_AURA updates",                "text" },
	{ "oracle",  "ShouldUnitAura...BeSecret",        "text" },
	{ "rsnap",   "Restriction snapshot points[1]",   "bar" },
	{ "power",   "UnitPower mana",                   "bar" },
	{ "clog",    "COMBAT_LOG_MESSAGE (last)",        "text" },
	{ "clint",   "combat log callbacks",             "text" },
	{ "active",  "C_Spell.IsActiveSpell",            "square" },
	{ "cont",    "AuraContainer slot (presence)",    "cont" },
	{ "desc",    "description $s1 (full size)",      "text" },
	{ "raid",    "group UnitGetTotalAbsorbs",        "none" },
}

---------------------------------------------------------------------------- helpers
local function S(v)                    -- printable form; never compares, tests or converts a secret
	if issecretvalue and issecretvalue(v) then return "<secret " .. type(v) .. ">" end
	if v == nil then return "nil" end
	local ok, s = pcall(tostring, v)
	return ok and s or "<unprintable>"
end

local function Short(err)              -- an error text without its "file:line: " prefix
	return (S(err):gsub("^[^:]*:%d+: ", ""))
end

local function PlainNum(v)             -- v if it is a plain number, else nil
	if issecretvalue(v) or type(v) ~= "number" then return nil end
	return v
end

local function Num(v)                  -- a plain number as text (whole numbers without decimals); anything else via S()
	if not PlainNum(v) then return S(v) end
	if v == math.floor(v) and v > -1e15 and v < 1e15 then return ("%d"):format(v) end
	return ("%.1f"):format(v)
end

-- #t of a table an API returned, as a plain number, or nil. A table whose contents are flagged secret
-- (issecrettable) may answer # with a secret, which must not reach a compare or a string.format.
local function Len(t)
	local ok, n = pcall(function() return #t end)
	if ok and not issecretvalue(n) and type(n) == "number" then return n end
	return nil
end

local function Pack(...) return select("#", ...), { ... } end

local function State() return InCombatLockdown() and "combat" or "ooc" end
local function T() return GetTime() - (P.t0 or GetTime()) end

local function push(line, loud)
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	ForeverDevInfoDB.msProbe = ForeverDevInfoDB.msProbe or {}
	local l = ForeverDevInfoDB.msProbe
	l[#l + 1] = date("%H:%M:%S ") .. line
	while #l > CAP do table.remove(l, 1) end
	if loud then print(PREFIX .. line) end
end
local function log(fmt, ...) push(select("#", ...) > 0 and fmt:format(...) or fmt, true) end    -- chat + log
local function qlog(fmt, ...) push(select("#", ...) > 0 and fmt:format(...) or fmt, false) end  -- log only

Bug = function(where, err)            -- an error in the probe itself (not a refused API call)
	if P.bugSeen[where] then return end
	P.bugSeen[where] = true
	log("PROBE BUG in %s: %s", where, S(err))
end

-- the verdict counters: kind = secret | plain | nil | err | opaque (secret but not drawable) | ev (event seen)
local function Mark(cand, kind, why)
	local bucket = P.st[P.bucket or State()]
	local t = bucket[cand]
	if not t then t = {}; bucket[cand] = t end
	t[kind] = (t[kind] or 0) + 1
	if why ~= nil and t[kind .. "Why"] == nil then t[kind .. "Why"] = why end
end

local function try(label, fn, ...)          -- each refusal is logged once per combat state
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then
		local key = label .. "/" .. State()
		if not P.errSeen[key] then P.errSeen[key] = true; qlog("%s -> ERROR %s", key, Short(a)) end
	end
	return ok, a, b, c, d
end

local function call(cand, label, fn, ...)   -- try() + the verdict counter of a route
	if type(fn) ~= "function" then
		Mark(cand, "err", label .. " does not exist")
		return false, "missing"
	end
	local ok, a, b, c, d = try(label, fn, ...)
	if not ok then Mark(cand, "err", label .. ": " .. Short(a)) end
	return ok, a, b, c, d
end

Count = function(key, n)
	n = n or 1
	P.cnt[key] = (P.cnt[key] or 0) + n
	P.fight[key] = (P.fight[key] or 0) + n
end

local function CountLine(tbl)
	local keys, out = {}, {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tbl[k] end
	return table.concat(out, ", ")
end

local function CVar(name)
	local fn = C_CVar and C_CVar.GetCVar
	if type(fn) ~= "function" then return "?" end
	local ok, v = pcall(fn, name)
	return ok and S(v) or "ERR"
end

local function RState(rtype)
	local fn = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
	if type(fn) ~= "function" then return "?" end
	local ok, s = pcall(fn, rtype)
	if not ok then return "ERR" end
	if issecretvalue(s) then return "<secret>" end
	return RS_NAME[s] or S(s)
end

local function AurasSecret()
	local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(fn) ~= "function" then return "?" end
	local ok, v = pcall(fn)
	return ok and S(v) or "ERR"
end

local function AurasOpen()      -- true only when aura queries plainly answer right now (so "no aura" means none)
	if InCombatLockdown() then return false end
	local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(fn) ~= "function" then return true end
	local ok, v = pcall(fn)
	return ok and not issecretvalue(v) and v == false
end

---------------------------------------------------------------------------- drawing
local function Txt(cand, s, r, g, b)        -- plain text only
	local fs = P.fs[cand]
	if not fs then return end
	fs:SetText(s)
	fs:SetTextColor(r or 1, g or 1, b or 1)
end

-- classify v without comparing it, draw it, count it. second = the row's second text (no bar, not counted)
local function Draw(cand, v, max, second)
	local fs = P.fs[cand]
	if second then fs = P.fs2[cand] end
	if not fs then return end
	local bar = nil
	if not second then bar = P.bars[cand] end
	if issecretvalue(v) then
		local ok, err = pcall(fs.SetText, fs, v)
		pcall(fs.SetTextColor, fs, 0.4, 1, 0.4)
		if bar then
			pcall(bar.SetMinMaxValues, bar, 0, max or P.full or 1)
			pcall(bar.SetValue, bar, v)
		end
		if not ok then Mark(cand, "err", "SetText(secret): " .. Short(err))
		elseif not second then Mark(cand, "secret") end
	elseif v == nil then
		fs:SetText("nil")
		fs:SetTextColor(0.6, 0.6, 0.6)
		if bar then bar:SetValue(0) end
		if not second then Mark(cand, "nil") end
	else
		fs:SetText(S(v))
		fs:SetTextColor(1, 1, 1)
		if bar and type(v) == "number" then bar:SetMinMaxValues(0, max or P.full or 1); bar:SetValue(v) end
		if not second then Mark(cand, "plain") end
	end
end

-- points[1] of an aura getter's result: returns p1 (maybe secret), "ok" | "nil" | "opaque" | "err", why
local function PointsFrom(d)
	if issecretvalue(d) then return nil, "opaque", "the aura table itself is secret" end
	if d == nil then return nil, "nil" end
	if type(d) ~= "table" then return nil, "err", "returned a " .. type(d) end
	local pts = d.points
	if issecretvalue(pts) then return nil, "opaque", "points is a secret table" end
	if type(pts) ~= "table" then return nil, "nil", "no points" end
	return pts[1], "ok"
end

local function AuraPoints(cand, d)
	local p1, st, why = PointsFrom(d)
	if st == "ok" then
		if P.icons[cand] then pcall(P.icons[cand].SetTexture, P.icons[cand], d.icon) end
		Draw(cand, p1)
		return
	end
	if P.bars[cand] then P.bars[cand]:SetValue(0) end
	if P.icons[cand] then P.icons[cand]:SetTexture(nil) end
	if st == "nil" then Txt(cand, why or "nil", 0.6, 0.6, 0.6)
	elseif st == "opaque" then Txt(cand, "<secret table>", 1, 0.6, 0.2)
	else Txt(cand, "ERROR " .. (why or ""), 1, 0.5, 0.3) end
	Mark(cand, st, why)
end

---------------------------------------------------------------------------- spell data
local function DescFull(id)     -- the full size from the spell description: n, "plain" | "secret" | "err" | "nil", extra
	local fn = C_Spell and C_Spell.GetSpellDescription
	if type(fn) ~= "function" then return nil, "err", "C_Spell.GetSpellDescription missing" end
	local ok, desc = pcall(fn, id)
	if not ok then return nil, "err", Short(desc) end
	if issecretvalue(desc) then return nil, "secret", desc end
	if type(desc) ~= "string" then return nil, "nil", "no description" end
	return tonumber(desc:match("(%d+)")), "plain", desc
end

local function KnownRank()
	local fn = C_SpellBook and C_SpellBook.IsSpellKnown
	if type(fn) ~= "function" then return nil end
	local bank = E.SpellBookSpellBank and E.SpellBookSpellBank.Player or 0
	for _, id in ipairs({ 10193, 10192, 10191, 8495, 8494, 1463 }) do
		local ok, k = pcall(fn, id, bank)
		if ok and not issecretvalue(k) and k == true then return id end
	end
end

local function SetFull(n, src)          -- the plain full size (bar maximum); n must be a plain number
	if issecretvalue(n) or type(n) ~= "number" or n <= 0 then return end
	P.full, P.fullSrc = n, src
end

local function GuessFull()
	if P.knownRank == nil then P.knownRank = KnownRank() end
	if P.full then return end
	local id = P.castId or P.auraId or P.knownRank or 8494
	local n = DescFull(id)
	if n then SetFull(n, "description of " .. id) else SetFull(FULL[id], "client data for " .. id) end
end

---------------------------------------------------------------------------- bookkeeping: the shield's life (plain values only)
-- P.life = the Mana Shield being tracked: id, F (full size), inst / exp / dur (plain, read out of combat; exp of
-- a shield cast in combat is estimated until it can be read: expEst), rem (what is left: plain, lowered after
-- each fight by what the meter credits Mana Shield with; nil = unknown), remHi (upper end when only a range is
-- known), remSrc, castAt, inCombat, fights, absorbed, goneAt (seen gone by a plain read), removedAt (seen in
-- UNIT_AURA's removedAuraInstanceIDs)
local function FullOf(id)
	local n = DescFull(id)
	return n or FULL[id] or P.full
end

local function NewLife(id, src)
	local F = FullOf(id)
	P.life = { id = id, F = F, rem = F, remSrc = src, castAt = GetTime(), fights = 0, absorbed = 0 }
	return P.life
end

local function LifeLine()
	local l = P.life
	if not l then return "bookkeeping: no shield tracked" end
	local left = l.exp and (l.exp - GetTime())
	local when = l.goneAt and "GONE" or (left and ("%.0f s to go%s"):format(left, l.expEst and " (est.)" or "") or "end time ?")
	return ("bookkeeping: shield %s  F %s  left %s%s (%s)  instance %s  %s"):format(S(l.id), Num(l.F), Num(l.rem),
		l.remHi and (".." .. Num(l.remHi)) or "", l.remSrc or "-", S(l.inst), when)
end

-- an out of combat read of the aura (d is a plain table): adopt the instance id and end time of the shield
-- just cast, or start tracking one whose cast was not seen
local function NoteLife(d)
	if issecretvalue(d) or type(d) ~= "table" then return end
	local sid, inst = PlainNum(d.spellId), PlainNum(d.auraInstanceID)
	if not (sid and inst and RANKS[sid]) then return end
	local exp, dur = PlainNum(d.expirationTime), PlainNum(d.duration)
	if exp and exp <= 0 then exp = nil end
	local life = P.life
	-- the same shield under a new instance id (a loading screen can hand out new ids): same spell, same end time
	if life and life.inst ~= nil and life.inst ~= inst and life.id == sid and exp and life.exp and not life.expEst
		and math.abs(exp - life.exp) < 0.5 then
		qlog("bookkeeping: shield %d now has instance %d (was %d), same expirationTime: the same shield, left %s kept",
			sid, inst, life.inst, Num(life.rem))
		life.inst, life.goneAt = inst, nil
	end
	if life and life.inst == nil and life.id == sid then
		life.inst, life.dur, life.goneAt = inst, dur, nil
		if exp then life.exp, life.expEst = exp, nil end
		qlog("bookkeeping: shield %d has instance %d, expirationTime %s (%s s left), F %s, left %s (%s)", sid, inst, Num(exp),
			exp and ("%.1f"):format(exp - GetTime()) or "?", Num(life.F), Num(life.rem), life.remSrc or "-")
	elseif not life or life.inst ~= inst then
		local fresh = exp and dur and dur - (exp - GetTime()) < 2
		life = NewLife(sid, fresh and "fresh shield (full size)" or "full size assumed (shield seen, its cast not seen)")
		life.inst, life.exp, life.dur, life.seenOnly = inst, exp, dur, true
		qlog("bookkeeping: new shield %d instance %d (%s), F %s, expirationTime %s", sid, inst, life.remSrc, Num(life.F), Num(exp))
	else
		if exp then life.exp, life.expEst = exp, nil end
		life.goneAt = nil
	end
end

---------------------------------------------------------------------------- reading the shield (works out of combat)
local function IndexOfMS()      -- plain index of Mana Shield among your buffs, and its data; 3rd: refused or secret
	local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(fn) ~= "function" then return nil end
	for i = 1, 40 do
		local ok, d = pcall(fn, "player", i, "HELPFUL")
		if not ok or issecretvalue(d) then return nil, nil, true end
		if d == nil then return nil end
		local sid = d.spellId
		if not issecretvalue(sid) and sid ~= nil and FULL[sid] then return i, d end
	end
end

local function UnitsIndexOfMS() -- position of Mana Shield in C_UnitAuras.GetUnitAuras("player", "HELPFUL")
	local fn = C_UnitAuras and C_UnitAuras.GetUnitAuras
	if type(fn) ~= "function" then return nil end
	local ok, list = pcall(fn, "player", "HELPFUL")
	if not ok or issecretvalue(list) or type(list) ~= "table" then return nil end
	for k, d in ipairs(list) do
		if not issecretvalue(d) and type(d) == "table" then
			local sid = d.spellId
			if not issecretvalue(sid) and sid ~= nil and FULL[sid] then return k end
		end
	end
end

-- reads the shield the way that works out of combat and remembers its plain ids and amount.
-- returns d, points[1] (plain or nil), seconds left (plain or nil)
local function ReadAura(reason, loud)
	local say = loud and log or qlog
	local d, how
	local unclear = false           -- a getter refused or answered with a secret: "no aura" would not be a fact
	local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
	if type(fn) == "function" then
		for _, id in ipairs(ORDER) do
			local ok, a = pcall(fn, id)
			if not ok or issecretvalue(a) then unclear = true
			elseif type(a) == "table" then d, how = a, "GetPlayerAuraBySpellID(" .. id .. ")"; break end
		end
	end
	local idx, dIdx, idxUnclear = IndexOfMS()
	if idx then P.msIndex = idx end
	if not d and dIdx then d, how = dIdx, "GetAuraDataByIndex(" .. idx .. ")" end
	local uidx = UnitsIndexOfMS()
	if uidx then P.msUnitsIdx = uidx end
	local combat = InCombatLockdown()
	unclear = unclear or idxUnclear or false
	P.auraUnclear = (not d) and unclear
	if not d then
		-- only a plain "no aura" while auras are open means the shield is gone: forget its amount and ids,
		-- so the next pull does not arm "R0 - absorbed" for a shield that is not there. A refused or secret
		-- answer (the moment around a pull or a fight end) says nothing
		if AurasOpen() and not unclear then
			P.lastPoints, P.shieldUp, P.inst, P.msIndex, P.msUnitsIdx = nil, false, nil, nil, nil
			-- the tracked shield is gone; the bookkeeping of the fight that just ended still needs it, so it is
			-- only marked here (a shield cast a moment ago may not be applied yet)
			local life = P.life
			if life and not life.goneAt and GetTime() - life.castAt > 1 then
				life.goneAt = GetTime()
				qlog("bookkeeping: shield %d gone (plain read%s)", life.id, life.exp and
					((GetTime() >= life.exp - 0.5) and ", its time ran out" or ", before its expirationTime") or "")
			end
		end
		local sig = "none/" .. tostring(combat) .. "/" .. tostring(unclear)
		if loud or sig ~= P.lastSig then
			say("[%s] no Mana Shield aura readable (combat %s, aurasSecret %s%s)", reason, S(combat), AurasSecret(),
				unclear and ", a getter refused or answered secret: not taken as gone" or "")
		end
		P.lastSig = sig
		return nil
	end
	local pts, p1 = {}, nil
	local raw = d.points
	if not issecretvalue(raw) and type(raw) == "table" then
		for k = 1, 4 do
			local v = raw[k]
			if issecretvalue(v) or v ~= nil then pts[#pts + 1] = S(v) end
		end
		p1 = raw[1]
	else
		pts[1] = S(raw)
	end
	local sid, inst, dur, exp = d.spellId, d.auraInstanceID, d.duration, d.expirationTime
	local left
	if not issecretvalue(exp) and type(exp) == "number" and exp > 0 then left = exp - GetTime() end
	if not issecretvalue(inst) and type(inst) == "number" then P.inst = inst end
	if not issecretvalue(sid) and type(sid) == "number" then P.auraId = sid end
	local p1plain = not issecretvalue(p1) and type(p1) == "number"
	if not combat then
		P.shieldUp = true
		P.lastPoints = p1plain and p1 or nil        -- the latest read: no stale amount once points[] is empty
		NoteLife(d)
	end
	local sig = table.concat(pts, ",") .. "/" .. S(inst) .. "/" .. S(sid)
	if loud or sig ~= P.lastSig then
		say("[%s] Mana Shield %s %s via %s: points={%s} duration=%s expirationTime=%s (%s s left) auraInstanceID=%s index=%s GetUnitAuras#%s",
			reason, S(sid), S(d.name), how, table.concat(pts, ","), S(dur), S(exp), left and ("%.1f"):format(left) or "?",
			S(inst), S(idx), S(uidx))
		if not issecretvalue(sid) and type(sid) == "number" and not P.descSeen[sid] then
			P.descSeen[sid] = true
			local _, st, desc = DescFull(sid)
			say("   description(%s): %s", S(sid), st == "plain" and S(desc) or (st .. " " .. S(desc)))
		end
	end
	P.lastSig = sig
	if p1plain then return d, p1, left end
	return d, nil, left
end

-- the shield's points[1] right now, any way that answers (for the restriction snapshot): p1, how
local function SnapshotPoints()
	local tried = {}
	local A = C_UnitAuras or {}
	if P.inst and type(A.GetAuraDataByAuraInstanceID) == "function" then
		local ok, d = pcall(A.GetAuraDataByAuraInstanceID, "player", P.inst)
		if ok then
			local p1, st, why = PointsFrom(d)
			if st == "ok" then return p1, "instance " .. P.inst end
			tried[#tried + 1] = "instance: " .. st .. (why and (" " .. why) or "")
		else
			tried[#tried + 1] = "instance: ERROR " .. Short(d)
		end
	end
	if type(A.GetPlayerAuraBySpellID) == "function" then
		for _, id in ipairs(ORDER) do
			local ok, d = pcall(A.GetPlayerAuraBySpellID, id)
			if not ok then tried[#tried + 1] = "by spell: ERROR " .. Short(d); break end
			local p1, st = PointsFrom(d)
			if st == "ok" then return p1, "spell " .. id end
			if st ~= "nil" then tried[#tried + 1] = "spell " .. id .. ": " .. st; break end
		end
	end
	return nil, #tried > 0 and table.concat(tried, "; ") or "no aura found"
end

---------------------------------------------------------------------------- R0: the shield's amount when the fight began
-- the hidden driver is R0 + 1 px wide for the meter values base-1 .. base+R0 (1 px per point; base = your
-- meter total before the pull if Current keeps running across fights, else 0): the frame from its fill's right
-- end to its own right end is R0 - (now - base) px wide, so its width IS the remaining amount (geometry, no Lua
-- arithmetic). The extra point keeps the fill at least 1 px wide, so its right end exists before the first absorb.
local function R0Geometry()
	local v, b = P.r0, P.r0Base or 0
	if not v then return end
	if P.remDrv then
		pcall(P.remDrv.SetWidth, P.remDrv, v + 1)
		pcall(P.remDrv.SetMinMaxValues, P.remDrv, b - 1, b + v)
	end
	if P.bars.mrem then pcall(P.bars.mrem.SetMinMaxValues, P.bars.mrem, b, b + v) end
end

SetR0 = function(v, src)
	if issecretvalue(v) or type(v) ~= "number" or v <= 0 then return end
	-- stays armed through a recast in combat (then drawn yellow: it describes the replaced shield)
	P.r0, P.r0Src, P.remArmed, P.remWhy = v, src, true, nil
	R0Geometry()
end

---------------------------------------------------------------------------- F - (now - at cast): a shield cast in combat
-- two invisible driver bars of the same width (m + 1 px for the meter values -1..m, 1 px per point) at the same
-- spot: P.drvCast holds the meter's value at the cast, P.drvNow follows the meter. The frame from drvNow's fill
-- end to drvCast's fill end + F px is (at cast + F) - now = F - (now - at cast) px wide: what is left of a shield
-- cast in this fight, by geometry only (a secret only ever goes to SetValue).
local function CastRange(m)
	P.castM = m
	for _, b in ipairs({ P.drvCast, P.drvNow }) do
		pcall(b.SetWidth, b, m + 1)
		pcall(b.SetMinMaxValues, b, -1, m)
	end
end

local function CastAnchors(F)
	local fr = P.cmFrame
	fr:ClearAllPoints()
	fr:SetPoint("TOPLEFT", P.drvNow:GetStatusBarTexture(), "TOPRIGHT")
	fr:SetPoint("BOTTOMRIGHT", P.drvCast:GetStatusBarTexture(), "BOTTOMRIGHT", F, 0)
	if P.bars.mcast and F > 0 then P.bars.mcast:SetMinMaxValues(0, F) end
end

-- the width is float geometry (e.g. 119.99997 for 120), so round it; TruncateWhenZero would floor to 119
local function SetRemText(fs, w)
	local SU = C_StringUtil
	local fmt = SU and (SU.RoundToNearestString or SU.TruncateWhenZero)
	fs:SetText(fmt(w))
end
local function Readout()                      -- every frame: the remaining widths -> text (and the cast row's bar)
	if not (P.panel and P.panel:IsShown()) then return end
	if P.remArmed and P.remFrame then
		local ok, w = pcall(P.remFrame.GetWidth, P.remFrame)
		if ok then pcall(SetRemText, P.fs.mrem, w) end
	end
	if P.castArmed and P.cmFrame then
		local ok, w = pcall(P.cmFrame.GetWidth, P.cmFrame)
		if ok then
			pcall(SetRemText, P.fs.mcast, w)
			pcall(P.bars.mcast.SetValue, P.bars.mcast, w)
		end
	end
end

---------------------------------------------------------------------------- aura containers
local function MakeContainer(host, unit, decorate)
	if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end
	local okC, c = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
	if not okC or not c then return nil, nil, "CreateFrame(AuraContainer): " .. Short(c) end
	c:SetPoint("TOPLEFT", host, "TOPLEFT")
	pcall(c.SetUnit, c, unit)
	local okS, b = pcall(c.AddAuraSlot, c, "fdms", "HELPFUL", {
		candidateFilters = { includeSpellIDs = INCLUDE },
		initializeFrame = function(btn)
			-- runs inside AddAuraSlot, before the button is closed to tainted code
			btn:ClearAllPoints()
			btn:SetAllPoints(host)
			pcall(btn.SetMouseClickEnabled, btn, false)
			pcall(btn.SetHideTooltipInCombat, btn, false)      -- hover it: Blizzard's own buff tooltip
			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints(btn)
			pcall(btn.SetIcon, btn, icon)
			local t = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", btn, "RIGHT", 3, 0)
			pcall(btn.SetDurationText, btn, t, nil)
			if decorate then decorate(btn) end
		end,
	})
	if not okS or not b then return c, nil, "AddAuraSlot: " .. Short(b) end
	return c, b
end

local function NewHost(parent)
	local ok, h = pcall(CreateFrame, "Frame", nil, parent, "DisableUntrustedLayoutScriptsTemplate")
	if not ok then h = CreateFrame("Frame", nil, parent) end
	return h
end

---------------------------------------------------------------------------- the panel
local function Row(c, y)
	local key, caption, kind = c[1], c[2], c[3]
	local f = P.panel
	local cap = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	cap:SetPoint("TOPLEFT", f, "TOPLEFT", 6, y)
	cap:SetText(caption)
	local x = VX
	if c.icon then
		local ic = f:CreateTexture(nil, "ARTWORK")
		ic:SetSize(13, 13)
		ic:SetPoint("TOPLEFT", f, "TOPLEFT", x, y + 1)
		P.icons[key] = ic
		x = x + 16
	end
	if kind == "square" or kind == "cont" then
		if kind == "cont" then P.contY = y; x = BX end      -- the container's icon, time and name sit left of it
		local sq = f:CreateTexture(nil, "ARTWORK")
		sq:SetColorTexture(0.4, 0.8, 1, 1)
		sq:SetSize(13, 13)
		sq:SetPoint("TOPLEFT", f, "TOPLEFT", x, y + 1)
		sq:SetAlpha(0.15)
		P.sq[key] = sq
		x = x + 18
	end
	local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
	fs:SetJustifyH("LEFT")
	fs:SetWordWrap(false)
	local wide = kind == "text" or kind == "square" or kind == "cont"
	fs:SetWidth(wide and (W - x - 6) or (BX - x - 6))
	fs:SetText("-")
	P.fs[key] = fs
	if kind == "bar" or kind == "rem" then
		local bg = f:CreateTexture(nil, "BACKGROUND")
		bg:SetPoint("TOPLEFT", f, "TOPLEFT", BX, y - 1)
		bg:SetSize(W - BX - 8, 10)
		local bar = CreateFrame("StatusBar", nil, f)
		bar:SetAllPoints(bg)
		bar:SetStatusBarTexture(WHITE)
		if kind == "rem" then
			bg:SetColorTexture(0.3, 0.6, 1, 1)            -- blue = what should be left
			bar:SetStatusBarColor(0.22, 0.22, 0.22, 1)    -- dark = absorbed this fight
		else
			bg:SetColorTexture(0.15, 0.15, 0.15, 1)
			bar:SetStatusBarColor(0.4, 0.8, 1, 1)
		end
		bar:SetMinMaxValues(0, 1)
		bar:SetValue(0)
		P.bars[key] = bar
	elseif kind == "text2" then
		local fs2 = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs2:SetPoint("TOPLEFT", f, "TOPLEFT", BX, y)
		fs2:SetJustifyH("LEFT")
		fs2:SetWordWrap(false)
		fs2:SetWidth(W - BX - 8)
		fs2:SetText("-")
		P.fs2[key] = fs2
	end
end

local function BuildPanel()
	if P.panel then
		P.panel:Show()
		if P.cont then pcall(P.cont.SetUnit, P.cont, "player") end
		if P.upd then P.upd:SetScript("OnUpdate", Readout) end
		return
	end
	local f = CreateFrame("Frame", "FDMSProbePanel", UIParent)
	f:SetSize(W, 100)
	f:SetPoint("CENTER", UIParent, "CENTER", 330, 40)
	f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f.bgTex = f:CreateTexture(nil, "BACKGROUND", nil, -8)
	f.bgTex:SetAllPoints(); f.bgTex:SetColorTexture(0, 0, 0, 0.75)
	P.panel = f
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
	title:SetText("/fdms Mana Shield   green = live secret, white = plain, grey = nil, orange = refused")
	local function hdr(y)
		local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", f, "TOPLEFT", 6, y)
		fs:SetWidth(W - 12)
		fs:SetJustifyH("LEFT")
		fs:SetWordWrap(false)
		return fs
	end
	P.hdr1, P.hdr2, P.hdr3, P.hdr4 = hdr(-24), hdr(-38), hdr(-52), hdr(-66)
	local y = -84
	for _, c in ipairs(CANDS) do
		if c[3] ~= "none" then
			Row(c, y)
			y = y - (c[3] == "cont" and 30 or ROW)
		end
	end
	f:SetHeight(-y + 6)

	-- the driver bars are invisible (alpha 0) but shown, so the game lays them out and their widths resolve
	local function driver()
		local b = CreateFrame("StatusBar", nil, f)
		b:SetStatusBarTexture(WHITE)
		b:SetStatusBarColor(1, 1, 1, 0)
		b:SetSize(1, 1)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
		b:SetMinMaxValues(0, 1)
		b:SetValue(0)
		return b
	end
	-- "R0 - absorbed": a driver bar R0 + 1 px wide and the frame right of its fill (see R0Geometry)
	local drv = driver()
	local rem = CreateFrame("Frame", nil, f)
	rem:SetPoint("TOPLEFT", drv:GetStatusBarTexture(), "TOPRIGHT")
	rem:SetPoint("BOTTOMRIGHT", drv, "BOTTOMRIGHT")
	P.remDrv, P.remFrame = drv, rem
	R0Geometry()
	-- "F - (now - at cast)": two driver bars and the frame between their fill ends (see CastRange)
	P.drvCast, P.drvNow = driver(), driver()
	P.cmFrame = CreateFrame("Frame", nil, f)
	CastRange(P.castM or M_PX)
	CastAnchors(P.castF or 0)

	-- an aura container slot filtered to every Mana Shield id (icon, time text, name, duration bar)
	local host = NewHost(f)
	host:SetSize(18, 18)
	host:SetPoint("TOPLEFT", f, "TOPLEFT", VX, (P.contY or y) + 3)
	local c, b, err = MakeContainer(host, "player", function(btn)
		local name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		name:SetPoint("LEFT", btn, "RIGHT", 34, 0)
		pcall(btn.SetSpellName, btn, name)
		local bar = CreateFrame("StatusBar", nil, btn)
		bar:SetSize(BX - VX - 10, 6)
		bar:SetPoint("TOPLEFT", f, "TOPLEFT", VX, (P.contY or y) - 17)
		bar:SetStatusBarTexture(WHITE)
		bar:SetStatusBarColor(0.6, 0.4, 1, 1)
		local dirs = Enum and Enum.StatusBarTimerDirection
		pcall(btn.SetDurationBar, btn, bar, { direction = dirs and dirs.RemainingTime })
	end)
	P.cont, P.contBtn, P.contErr = c, b, err
	qlog("aura container slot: %s", err or "ok")

	P.upd = P.upd or CreateFrame("Frame", nil, UIParent)
	P.upd:SetScript("OnUpdate", Readout)
end

local function Header()
	P.hdr1:SetText(("full %s (%s)   R0 %s (%s)   instance %s   index %s"):format(S(P.full), P.fullSrc or "-",
		S(P.r0), P.r0Src or "-", S(P.inst), S(P.msIndex)))
	P.hdr2:SetText(("combat %s  aurasSecret %s  | restrictions: Combat %s  Encounter %s  Map %s  Chat %s"):format(
		S(InCombatLockdown()), AurasSecret(), RState(R_COMBAT), RState(R_ENC), RState(R_MAP), RState(R_CHAT)))
	local f = P.fight
	P.hdr3:SetText(("fight: melee hits %d (absorbed full %d, part %d)  shield updates %d  absorb ev %d  ctext %d  meter %d"):format(
		f["phys hits"] or 0, f["phys full absorbs"] or 0, f["phys partial absorbs"] or 0, f["UNIT_AURA ms updated"] or 0,
		f.UNIT_ABSORB_AMOUNT_CHANGED or 0, f.COMBAT_TEXT_UPDATE or 0, f.meter or 0))
	P.hdr4:SetText(LifeLine() .. "   | meter rows = ALL your absorbs")
end

---------------------------------------------------------------------------- the routes (Refresh)
local function InfoIsMS(info)       -- a Cooldown Manager entry for Mana Shield? (plain ids only)
	if issecretvalue(info) or type(info) ~= "table" then return false end
	for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID" }) do
		local v = info[k]
		if not issecretvalue(v) and v ~= nil and FULL[v] then return true end
	end
	local linked = info.linkedSpellIDs
	if not issecretvalue(linked) and type(linked) == "table" then
		for _, v in ipairs(linked) do
			if not issecretvalue(v) and FULL[v] then return true end
		end
	end
	return false
end

local function ItemIsMS(it)
	if issecretvalue(it) or type(it) ~= "table" or type(it.GetCooldownInfo) ~= "function" then return false end
	local ok, info = pcall(it.GetCooldownInfo, it)
	return ok and InfoIsMS(info)
end

local function FindCDMItem()        -- read only: never write to Cooldown Manager frames or tables
	for _, vname in ipairs(VIEWERS) do
		local v = _G[vname]
		if type(v) == "table" and type(v.GetItemFrames) == "function" then
			local ok, kids = pcall(v.GetItemFrames, v)
			if ok and not issecretvalue(kids) and type(kids) == "table" then
				for _, it in ipairs(kids) do
					if ItemIsMS(it) then return it, vname end
				end
			end
		end
	end
end

local function ReadCDM()
	if not (P.cdmItem and ItemIsMS(P.cdmItem)) then P.cdmItem, P.cdmViewer = FindCDMItem() end
	local it = P.cdmItem
	if not it then
		Txt("cdm", "not tracked (Cooldown Manager: add it to Tracked Buffs)", 0.6, 0.6, 0.6)
		if P.bars.cdm then P.bars.cdm:SetValue(0) end
		Mark("cdm", "nil", "Mana Shield is not in the Cooldown Manager")
		return
	end
	-- the item keeps the AuraData that Blizzard's secure code read with GetUnitAuras (points included)
	local ok, d = call("cdm", "CDM item:GetAuraDataCached", it.GetAuraDataCached, it)
	if ok then AuraPoints("cdm", d) end
end

local function BySpell(cand, label, fn, withUnit)
	if type(fn) ~= "function" then Mark(cand, "err", label .. " does not exist"); return end
	local ids = ORDER
	if P.castId then
		ids = { P.castId }
		for _, id in ipairs(ORDER) do if id ~= P.castId then ids[#ids + 1] = id end end
	end
	for _, id in ipairs(ids) do
		local ok, d
		if withUnit then ok, d = try(label, fn, "player", id) else ok, d = try(label, fn, id) end
		if not ok then
			Mark(cand, "err", label .. ": " .. Short(d))
			Txt(cand, "ERROR", 1, 0.5, 0.3)
			return
		end
		if issecretvalue(d) or d ~= nil then AuraPoints(cand, d); return end
	end
	AuraPoints(cand, nil)
end

local function ReadByInstance()
	local A = C_UnitAuras or {}
	if P.inst then
		local ok, d = call("inst", "GetAuraDataByAuraInstanceID", A.GetAuraDataByAuraInstanceID, "player", P.inst)
		if ok then AuraPoints("inst", d) else Txt("inst", "ERROR", 1, 0.5, 0.3) end
		local okD, dur = call("dur", "GetAuraDuration", A.GetAuraDuration, "player", P.inst)
		if okD then
			if issecretvalue(dur) then Txt("dur", "<secret " .. type(dur) .. ">", 1, 0.6, 0.2); Mark("dur", "opaque", "duration object is secret")
			elseif dur == nil then Txt("dur", "nil", 0.6, 0.6, 0.6); Mark("dur", "nil")
			else Txt("dur", type(dur) .. " (time only, no amount)"); Mark("dur", "plain") end
		else
			Txt("dur", "ERROR", 1, 0.5, 0.3)
		end
	else
		Txt("inst", "no instance id yet (cast it out of combat)", 0.6, 0.6, 0.6)
		Mark("inst", "nil", "no instance id known")
		Txt("dur", "no instance id", 0.6, 0.6, 0.6)
		Mark("dur", "nil", "no instance id known")
	end
end

local function ReadBySpell()
	local A = C_UnitAuras or {}
	BySpell("spell", "GetPlayerAuraBySpellID", A.GetPlayerAuraBySpellID, false)
	BySpell("uspell", "GetUnitAuraBySpellID", A.GetUnitAuraBySpellID, true)
end

local function ReadByName()
	local A = C_UnitAuras or {}
	local okN, name = false, nil
	if C_Spell and type(C_Spell.GetSpellName) == "function" then okN, name = pcall(C_Spell.GetSpellName, P.castId or P.auraId or 1463) end
	if okN and not issecretvalue(name) and type(name) == "string" then
		local ok, d = call("name", "GetAuraDataBySpellName", A.GetAuraDataBySpellName, "player", name, "HELPFUL")
		if ok then AuraPoints("name", d) else Txt("name", "ERROR", 1, 0.5, 0.3) end
	else
		Txt("name", "spell name not plain", 1, 0.5, 0.3)
		Mark("name", "err", "C_Spell.GetSpellName gave no plain name")
	end
end

local function ReadByPosition()
	local A = C_UnitAuras or {}
	if P.msIndex then
		local ok, d = call("index", "GetAuraDataByIndex", A.GetAuraDataByIndex, "player", P.msIndex, "HELPFUL")
		if ok then AuraPoints("index", d) else Txt("index", "ERROR", 1, 0.5, 0.3) end
	else
		Txt("index", "index unknown (read it out of combat)", 0.6, 0.6, 0.6)
		Mark("index", "nil", "index unknown")
	end
	local ok, list = call("units", "GetUnitAuras", A.GetUnitAuras, "player", "HELPFUL")
	if not ok then
		Txt("units", "ERROR", 1, 0.5, 0.3)
	elseif issecretvalue(list) then
		Txt("units", "<secret list>", 1, 0.6, 0.2); Mark("units", "opaque", "the list is secret")
	elseif type(list) ~= "table" then
		Txt("units", "nil", 0.6, 0.6, 0.6); Mark("units", "nil")
	elseif P.msUnitsIdx then
		AuraPoints("units", list[P.msUnitsIdx])
	else
		Txt("units", ("%s auras, Mana Shield position unknown"):format(S(Len(list))), 0.6, 0.6, 0.6)
		Mark("units", "nil", "position unknown")
	end
end

local function TipLine(cand, data)  -- line 2 of a TooltipData (the buff's description)
	if issecretvalue(data) then Txt(cand, "<secret table>", 1, 0.6, 0.2); Mark(cand, "opaque", "TooltipData is secret"); return end
	if data == nil then Txt(cand, "nil", 0.6, 0.6, 0.6); Mark(cand, "nil"); return end
	if type(data) ~= "table" then Txt(cand, type(data)); Mark(cand, "err", "returned a " .. type(data)); return end
	local lines = data.lines
	if issecretvalue(lines) then Txt(cand, "<secret lines>", 1, 0.6, 0.2); Mark(cand, "opaque", "lines is secret"); return end
	if type(lines) ~= "table" then Txt(cand, "no lines", 0.6, 0.6, 0.6); Mark(cand, "nil", "no lines"); return end
	local line = lines[2]
	if issecretvalue(line) then Txt(cand, "<secret line>", 1, 0.6, 0.2); Mark(cand, "opaque", "line 2 is secret"); return end
	if type(line) ~= "table" then Txt(cand, ("%s line(s)"):format(S(Len(lines))), 0.6, 0.6, 0.6); Mark(cand, "nil", "no line 2"); return end
	Draw(cand, line.leftText)
	if not InCombatLockdown() and P.tipLogged ~= P.inst then
		P.tipLogged = P.inst
		for i, l in ipairs(lines) do
			if not issecretvalue(l) and type(l) == "table" then qlog("   buff tooltip line %d: %s | %s", i, S(l.leftText), S(l.rightText)) end
		end
	end
end

local function ReadTipInfo()
	local TI = C_TooltipInfo or {}
	if P.inst then
		local ok, data = call("tipinfo", "C_TooltipInfo.GetUnitBuffByAuraInstanceID", TI.GetUnitBuffByAuraInstanceID, "player", P.inst, "HELPFUL")
		if ok then TipLine("tipinfo", data) else Txt("tipinfo", "ERROR", 1, 0.5, 0.3) end
	elseif P.msIndex then
		local ok, data = call("tipinfo", "C_TooltipInfo.GetUnitBuff", TI.GetUnitBuff, "player", P.msIndex, "HELPFUL")
		if ok then TipLine("tipinfo", data) else Txt("tipinfo", "ERROR", 1, 0.5, 0.3) end
	else
		Txt("tipinfo", "no instance id or index", 0.6, 0.6, 0.6)
		Mark("tipinfo", "nil", "no instance id or index")
	end
end

local function ReadOwnTip()
	-- our own GameTooltip below the panel, filled by its SetUnitBuff* accessor (once a second)
	if GetTime() - (P.tipT or 0) < 1 then return end
	P.tipT = GetTime()
	if not P.tip then
		local ok, tip = pcall(CreateFrame, "GameTooltip", "FDMSProbeTip", UIParent, "GameTooltipTemplate")
		if not ok then Mark("tip", "err", "CreateFrame(GameTooltip): " .. Short(tip)); return end
		P.tip = tip
	end
	local tip = P.tip
	pcall(tip.SetOwner, tip, P.panel, "ANCHOR_NONE")
	pcall(tip.ClearAllPoints, tip)
	pcall(tip.SetPoint, tip, "TOPLEFT", P.panel, "BOTTOMLEFT", 0, -2)
	local ok, r
	if P.inst then
		ok, r = call("tip", "GameTooltip:SetUnitBuffByAuraInstanceID", tip.SetUnitBuffByAuraInstanceID, tip, "player", P.inst, "HELPFUL")
	elseif P.msIndex then
		ok, r = call("tip", "GameTooltip:SetUnitBuff", tip.SetUnitBuff, tip, "player", P.msIndex, "HELPFUL")
	else
		Txt("tip", "no instance id or index", 0.6, 0.6, 0.6)
		Mark("tip", "nil", "no instance id or index")
		return
	end
	if not ok then Txt("tip", "ERROR", 1, 0.5, 0.3); return end
	local okN, n = pcall(tip.NumLines, tip)
	local fsl = _G["FDMSProbeTipTextLeft2"]
	if type(fsl) == "table" and type(fsl.GetText) == "function" then
		local okT, txt = call("tip", "TextLeft2:GetText", fsl.GetText, fsl)
		if okT then Draw("tip", txt) end
	else
		Txt("tip", "no line 2", 0.6, 0.6, 0.6)
		Mark("tip", "nil", "no line 2")
	end
	local sig = State() .. "/" .. S(r) .. "/" .. (okN and S(n) or "ERR")
	if sig ~= P.tipSig then
		P.tipSig = sig
		qlog("own tooltip (%s): set returned %s, NumLines %s", State(), S(r), okN and S(n) or "ERR")
	end
end

-- your row in a damage meter session (the results of a pcall'd GetCombatSession*): "ok", totalAmount (maybe
-- secret), #sources | other status, why
local function LocalRow(ok, s)
	if not ok then return "err", Short(s) end
	if issecretvalue(s) then return "opaque", "the session table is secret" end
	if type(s) ~= "table" then return "nil", "no session" end
	local list = s.combatSources
	if issecretvalue(list) then return "opaque", "combatSources is secret" end
	if type(list) ~= "table" then return "nil", "no combatSources" end
	for _, src in ipairs(list) do
		if not issecretvalue(src) and type(src) == "table" then
			local me = src.isLocalPlayer                   -- NeverSecret
			if not issecretvalue(me) and me == true then return "ok", src.totalAmount, Len(list) end
		end
	end
	return "nil", ("you are not among %s source(s)"):format(S(Len(list)))
end

-- your row in the Current session
local function MeterLocal(mtype)
	local fn = C_DamageMeter and C_DamageMeter.GetCombatSessionFromType
	if type(fn) ~= "function" then return "err", "C_DamageMeter.GetCombatSessionFromType missing" end
	return LocalRow(pcall(fn, M_CUR, mtype))
end

local function SessionTotal(id)    -- your Absorbs total in the session with this id, as text
	local fn = C_DamageMeter and C_DamageMeter.GetCombatSessionFromID
	if type(fn) ~= "function" then return "?" end
	local st, v = LocalRow(pcall(fn, id, M_ABS))
	if st == "ok" then return Num(v) end
	return st == "nil" and "0" or st
end

-- the damage meter's state with plain values only (a secret anywhere: plain = false): your Absorbs total in
-- the Current session, the Mana Shield part of it (all ranks, per spell), the session list (ids, names,
-- durations) and Current's duration; deep = also your total in each listed session
local function MeterStateRaw(deep)
	local m = { t = GetTime(), inCombat = InCombatLockdown(), secret = false }
	local DM = C_DamageMeter or {}
	local st, A = MeterLocal(M_ABS)
	if st == "ok" then
		if issecretvalue(A) then m.secret = true
		elseif type(A) == "number" then m.total = A
		else m.why = "total " .. S(A) end
	elseif st == "nil" then
		m.total, m.ms, m.noRow = 0, 0, true      -- no row of yours = nothing absorbed in this session yet
	else
		m.secret, m.why = st == "opaque", st .. ": " .. S(A)
	end
	local okG, guid = pcall(UnitGUID, "player")     -- UnitGUID is SecretWhenUnitIdentityRestricted: test it first
	if okG and not issecretvalue(guid) and guid ~= nil and type(DM.GetCombatSessionSourceFromType) == "function" then
		local ok, src = pcall(DM.GetCombatSessionSourceFromType, M_CUR, M_ABS, guid)
		local spells
		if ok and issecretvalue(src) then m.secret = true
		elseif ok and type(src) == "table" then spells = src.combatSpells
		elseif not ok then m.srcWhy = Short(src) end
		if issecretvalue(spells) then
			m.secret = true
		elseif type(spells) == "table" then
			local ms, ids, parts, sec = 0, {}, {}, false
			for _, x in ipairs(spells) do
				local id, n
				if issecretvalue(x) then sec = true
				elseif type(x) == "table" then id, n = x.spellID, x.totalAmount end
				if issecretvalue(id) or issecretvalue(n) then
					sec = true
				elseif type(id) == "number" and type(n) == "number" then
					parts[#parts + 1] = ("%d=%s"):format(id, Num(n))
					if RANKS[id] then ms = ms + n; ids[#ids + 1] = tostring(id) end
				end
			end
			if sec then
				m.secret, m.ms = true, nil
			else
				m.ms, m.spells = ms, table.concat(parts, " ")
				m.msIdTxt = #ids > 0 and table.concat(ids, "+") or "no Mana Shield entry"
			end
		end
	end
	if type(DM.GetAvailableCombatSessions) == "function" then
		local ok, list = pcall(DM.GetAvailableCombatSessions)
		if ok and not issecretvalue(list) and type(list) == "table" then
			local rows = {}
			m.ids = {}
			for _, s in ipairs(list) do
				if issecretvalue(s) or type(s) ~= "table" then
					rows[#rows + 1] = { txt = S(s) }
				else
					local id, nm, du = s.sessionID, s.name, s.durationSeconds
					local r = { txt = ("%s '%s' %s s"):format(S(id), S(nm), PlainNum(du) and ("%.0f"):format(du) or S(du)) }
					if PlainNum(id) then
						m.ids[id] = true
						if not m.maxId or id > m.maxId then m.maxId = id end
						r.id = id
					end
					rows[#rows + 1] = r
				end
			end
			-- the text (and the per-session reads) for the newest 6 only: the list may keep a long history
			local parts, first = {}, math.max(1, #rows - 5)
			if first > 1 then parts[1] = ("+%d older"):format(first - 1) end
			for i = first, #rows do
				local r = rows[i]
				parts[#parts + 1] = (deep and r.id) and (r.txt .. " you " .. SessionTotal(r.id)) or r.txt
			end
			m.n, m.list = #rows, #rows > 0 and table.concat(parts, ", ") or "none"
		else
			m.list = ok and ("not a plain list: " .. S(list)) or ("ERROR " .. Short(list))
		end
	end
	if type(DM.GetSessionDurationSeconds) == "function" then
		local ok, du = pcall(DM.GetSessionDurationSeconds, M_CUR)
		if ok then m.curDur = PlainNum(du) end
	end
	m.plain = not m.secret and m.total ~= nil
	return m
end

local function MeterState(deep)     -- MeterStateRaw in a pcall: an unexpected shape only makes it "not plain"
	local ok, m = try("MeterState", MeterStateRaw, deep)
	if ok and type(m) == "table" then return m end
	return { t = GetTime(), inCombat = InCombatLockdown(), secret = true, plain = false, why = "probe: " .. Short(m) }
end

local function MeterLine(m)
	if not m then return "-" end
	return ("you %s%s, Mana Shield %s, spells [%s], Current %s s, sessions [%s]"):format(
		m.total ~= nil and Num(m.total) or (m.secret and "<secret>" or S(m.why)), m.noRow and " (no row)" or "",
		Num(m.ms), m.spells or "-", Num(m.curDur), m.list or "?")
end

local function PreShort(m)
	return ("you %s, Mana Shield %s, %s session(s), newest id %s"):format(Num(m.total), Num(m.ms), Num(m.n), Num(m.maxId))
end

local function DrawMeter(cand, mtype)
	local st, v = MeterLocal(mtype)
	if st == "ok" then Draw(cand, v); return st, v end
	if P.bars[cand] then P.bars[cand]:SetValue(0) end
	if st == "opaque" then Txt(cand, "<secret table>", 1, 0.6, 0.2)
	elseif st == "err" then Txt(cand, "ERROR " .. S(v), 1, 0.5, 0.3)
	else Txt(cand, S(v), 0.6, 0.6, 0.6) end
	Mark(cand, st, S(v))
	return st, v
end

local function ReadMeter()
	local st, A = DrawMeter("mabs", M_ABS)
	DrawMeter("mheal", M_HEAL)
	DrawMeter("mtaken", M_TAKEN)
	-- your total now; no row of yours in the session = nothing absorbed in it yet. haveNow is worked out
	-- without "now ~= nil": now is secret in combat, and a secret must not be compared, not even with nil
	local now, haveNow
	if st == "ok" then
		if issecretvalue(A) or type(A) == "number" then now, haveNow = A, true end
	elseif st == "nil" then
		now, haveNow = 0, true
	end
	local fi = P.fi
	if fi and InCombatLockdown() and not fi.firstMeter then
		fi.firstMeter = true
		qlog("%6.1f first meter read of fight %d: %s %s%s", T(), fi.n, st, S(A), st == "nil" and " (no row of yours: Current started empty for this fight)"
			or st == "ok" and " (your row is there already: a running session, or an absorb before this read)" or "")
	end
	-- R0 - absorbed: the blue part of the bar, and the readout (driver width) drawn every frame by Readout()
	if not P.remArmed then
		local why = P.remWhy or (P.r0 == nil and P.r0Src) or "no R0 yet"
		Txt("mrem", why, 0.6, 0.6, 0.6)
		if P.bars.mrem then P.bars.mrem:SetValue(0) end
		Mark("mrem", "nil", why)
	elseif haveNow then
		pcall(P.remDrv.SetValue, P.remDrv, now)
		pcall(P.bars.mrem.SetValue, P.bars.mrem, now)
		if P.recast then pcall(P.fs.mrem.SetTextColor, P.fs.mrem, 1, 0.85, 0.3)
		else pcall(P.fs.mrem.SetTextColor, P.fs.mrem, 0.4, 1, 0.4) end
		Mark("mrem", issecretvalue(now) and "secret" or "plain")
	else
		Mark("mrem", "nil", "no meter value")
	end
	-- F - (now - at cast): the "now" driver follows the meter, the readout and the bar are drawn by Readout()
	if not P.castArmed then
		local why = P.castWhy or "no Mana Shield cast in combat yet"
		Txt("mcast", why, 0.6, 0.6, 0.6)
		if P.bars.mcast then P.bars.mcast:SetValue(0) end
		Mark("mcast", "nil", why)
	elseif haveNow then
		pcall(P.drvNow.SetValue, P.drvNow, now)
		pcall(P.fs.mcast.SetTextColor, P.fs.mcast, 0.4, 1, 0.4)
		Mark("mcast", issecretvalue(now) and "secret" or "plain")
	else
		Mark("mcast", "nil", "no meter value")
	end
end

local function ReadMeterSpell()
	-- which spell gets the credit (and how much), from your source entry
	local fn = C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType
	local okG, guid = pcall(UnitGUID, "player")
	if not okG or issecretvalue(guid) then Txt("mspell", "player GUID not plain", 1, 0.5, 0.3); Mark("mspell", "err", "UnitGUID not plain"); return end
	local ok, src = call("mspell", "GetCombatSessionSourceFromType", fn, M_CUR, M_ABS, guid)
	if not ok then Txt("mspell", "ERROR", 1, 0.5, 0.3); return end
	if issecretvalue(src) then Txt("mspell", "<secret table>", 1, 0.6, 0.2); Mark("mspell", "opaque", "source table is secret"); return end
	if type(src) ~= "table" then Txt("mspell", "nil", 0.6, 0.6, 0.6); Mark("mspell", "nil"); return end
	local spells = src.combatSpells
	if issecretvalue(spells) then Txt("mspell", "<secret list>", 1, 0.6, 0.2); Mark("mspell", "opaque", "combatSpells is secret"); return end
	if type(spells) ~= "table" then Txt("mspell", "no spells", 0.6, 0.6, 0.6); Mark("mspell", "nil", "no spells"); return end
	local sp = spells[1]       -- no "#spells == 0": a flagged list can answer # with a secret
	if issecretvalue(sp) then Txt("mspell", "<secret entry>", 1, 0.6, 0.2); Mark("mspell", "opaque", "spell entry is secret"); return end
	if type(sp) ~= "table" then Txt("mspell", "no spells", 0.6, 0.6, 0.6); Mark("mspell", "nil", "no spells"); return end
	Draw("mspell", sp.spellID)
	Draw("mspell", sp.totalAmount, nil, true)
	if P.icons.mspell and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
		local okT, tex = pcall(C_Spell.GetSpellTexture, sp.spellID)
		if okT then pcall(P.icons.mspell.SetTexture, P.icons.mspell, tex) end
	end
	if not InCombatLockdown() then
		local parts = {}
		for _, x in ipairs(spells) do
			if not issecretvalue(x) and type(x) == "table" then parts[#parts + 1] = S(x.spellID) .. "=" .. S(x.totalAmount) end
		end
		local sig = table.concat(parts, " ")
		if sig ~= P.meterSig then P.meterSig = sig; qlog("meter Absorbs, your spells: %s", sig) end
	end
end

local function ReadOracle()
	local fnI = C_Secrets and C_Secrets.ShouldUnitAuraInstanceBeSecret
	local fnX = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
	local anySecret = false
	local function one(fn, label, ...)
		local ok, v = call("oracle", label, fn, ...)
		if not ok then return "ERR" end
		if issecretvalue(v) then anySecret = true end
		return S(v)
	end
	local a, b = "-", "-"
	if P.inst then
		a = one(fnI, "ShouldUnitAuraInstanceBeSecret", "player", P.inst)
		b = one(fnI, "ShouldUnitAuraInstanceBeSecret(bogus id)", "player", P.inst + 1000000)
	end
	local c = one(fnX, "ShouldUnitAuraIndexBeSecret", "player", P.msIndex or 1, "HELPFUL")
	local d = one(fnX, "ShouldUnitAuraIndexBeSecret(40)", "player", 40, "HELPFUL")
	-- "would this spell's aura be secret right now": if this says false in combat, the by-spell getters should answer
	local e = one(C_Secrets and C_Secrets.ShouldSpellAuraBeSecret, "ShouldSpellAuraBeSecret",
		P.castId or P.auraId or P.knownRank or 8494)
	local txt = ("inst %s  bogus %s  idx %s  idx40 %s  spell %s"):format(a, b, c, d, e)
	Txt("oracle", txt)
	if anySecret then Mark("oracle", "opaque", "the answer is secret") else Mark("oracle", "plain") end
	if txt ~= P.oracleSig then P.oracleSig = txt; qlog("%6.1f oracle (%s): %s", T(), State(), txt) end
end

local function DrawPower()
	if not P.panel then return end
	local okM, mx = pcall(UnitPowerMax, "player", MANA)
	local max = 1
	if okM and not issecretvalue(mx) and type(mx) == "number" and mx > 0 then max = mx end
	local ok, v = call("power", "UnitPower", UnitPower, "player", MANA)
	if ok then Draw("power", v, max) else Txt("power", "ERROR", 1, 0.5, 0.3) end
end

local function ReadActive()
	local ok, v = call("active", "C_Spell.IsActiveSpell", C_Spell and C_Spell.IsActiveSpell, P.castId or P.auraId or 8494)
	if not ok then Txt("active", "ERROR", 1, 0.5, 0.3); return end
	local sq = P.sq.active
	if issecretvalue(v) then
		local okA, err = pcall(sq.SetAlphaFromBoolean, sq, v, 1, 0.15)
		Txt("active", "<secret boolean> -> square")
		if okA then Mark("active", "secret") else Mark("active", "err", "SetAlphaFromBoolean: " .. Short(err)) end
	elseif v == nil then
		sq:SetAlpha(0.15); Txt("active", "nil", 0.6, 0.6, 0.6); Mark("active", "nil")
	else
		-- IsActiveSpell is for toggled spells; plain false while the shield is up means it is no signal
		local note = (v == false and P.shieldUp and not InCombatLockdown()) and "   (false while the shield is up: no signal)" or ""
		sq:SetAlpha(v and 1 or 0.15); Txt("active", S(v) .. note); Mark("active", "plain")
	end
end

local function ReadContainer()
	local b = P.contBtn
	if not b then Txt("cont", P.contErr or "not built", 1, 0.5, 0.3); Mark("cont", "err", P.contErr or "not built"); return end
	local ok, shown = call("cont", "slot button:IsShown", b.IsShown, b)
	if not ok then Txt("cont", "IsShown: ERROR", 1, 0.5, 0.3); return end
	if issecretvalue(shown) then
		pcall(P.sq.cont.SetAlphaFromBoolean, P.sq.cont, shown, 1, 0.15)
		Txt("cont", "IsShown <secret> -> square")
		Mark("cont", "secret")
	else
		P.sq.cont:SetAlpha(shown and 1 or 0.15)
		Txt("cont", "IsShown " .. S(shown))
		Mark("cont", "plain")
	end
end

local function ReadDesc()
	local id = P.castId or P.auraId or P.knownRank or 8494
	local n, st, x = DescFull(id)
	if st == "plain" then
		Txt("desc", ("%s for %s   (bar max %s from %s)"):format(S(n), S(id), S(P.full), P.fullSrc or "-"))
		Mark("desc", "plain")
	elseif st == "secret" then
		Draw("desc", x)
	else
		Txt("desc", st .. " " .. S(x), 1, 0.5, 0.3)
		Mark("desc", st == "err" and "err" or "nil", S(x))
	end
end

local function ReadRaid()
	for _, r in ipairs(P.raid) do
		local ok, ab = call("raid", "UnitGetTotalAbsorbs(" .. r.unit .. ")", UnitGetTotalAbsorbs, r.unit)
		if ok then
			local okT = pcall(r.abs.SetText, r.abs, ab)
			if not okT then Mark("raid", "err", "SetText")
			elseif issecretvalue(ab) then Mark("raid", "secret")
			else Mark("raid", "plain") end
		end
	end
end

local function ReadAbs()
	local ok, a = call("abs", "UnitGetTotalAbsorbs", UnitGetTotalAbsorbs, "player")
	if ok then Draw("abs", a) else Txt("abs", "ERROR", 1, 0.5, 0.3) end
end

-- each route runs in its own pcall: an unexpected error in one (say a secret where the probe expected a
-- plain value) must not stop the rows after it from being read in combat. The route's first candidate
-- gets the error in its verdict, and chat gets one PROBE BUG line per route and combat state.
local ROUTES = {
	{ "header", Header }, { "abs", ReadAbs }, { "cdm", ReadCDM }, { "inst", ReadByInstance },
	{ "spell", ReadBySpell }, { "name", ReadByName }, { "index", ReadByPosition }, { "tipinfo", ReadTipInfo },
	{ "tip", ReadOwnTip }, { "mabs", ReadMeter }, { "mspell", ReadMeterSpell }, { "oracle", ReadOracle },
	{ "power", DrawPower }, { "active", ReadActive }, { "cont", ReadContainer }, { "desc", ReadDesc },
	{ "raid", ReadRaid },
}

Refresh = function(reason)
	if not (P.panel and P.panel:IsShown()) then return end
	for _, r in ipairs(ROUTES) do
		local ok, err = pcall(r[2])
		if not ok then
			if r[1] ~= "header" then Mark(r[1], "err", "probe: " .. Short(err)) end
			Bug("Refresh/" .. r[1] .. "/" .. State(), S(err) .. " (refresh on " .. S(reason) .. ")")
		end
	end
end

---------------------------------------------------------------------------- verdicts
local function Verdict(t)
	if not t then return "no events" end
	local out = {}
	if t.secret then out[#out + 1] = ("OK (secret, drawn) x%d"):format(t.secret) end
	if t.plain then out[#out + 1] = ("OK (plain) x%d"):format(t.plain) end
	if t.opaque then out[#out + 1] = ("secret but not drawable x%d: %s"):format(t.opaque, t.opaqueWhy or "?") end
	if t["nil"] then out[#out + 1] = ("nil x%d%s"):format(t["nil"], t.nilWhy and (": " .. t.nilWhy) or "") end
	if t.err then out[#out + 1] = ("ERROR x%d: %s"):format(t.err, (t.errWhy or "?"):sub(1, 90)) end
	if t.ev then out[#out + 1] = ("events x%d"):format(t.ev) end
	return #out > 0 and table.concat(out, ", ") or "no events"
end

local function Brief(t)
	if not t then return "|cff888888no events|r" end
	local out = {}
	if t.secret then out[#out + 1] = "|cff44ff44OK (secret, drawn)|r" end
	if t.plain then out[#out + 1] = "|cffffffffOK (plain)|r" end
	if t.opaque then out[#out + 1] = "|cffff9933secret, not drawable|r" end
	if t["nil"] then out[#out + 1] = "|cff888888nil|r" end
	if t.err then out[#out + 1] = "|cffff5544ERROR|r" end
	if t.ev then out[#out + 1] = ("events %d"):format(t.ev) end
	return #out > 0 and table.concat(out, "/") or "|cff888888no events|r"
end

local function PrintVerdicts(state, loud, label)
	local bucket = P.st[state] or {}
	label = label or state
	qlog("---- verdicts (%s) ----", label)
	if loud then print(PREFIX .. "verdicts (" .. label .. "):") end
	local line = {}
	for _, c in ipairs(CANDS) do
		qlog("[%s] %-34s %s", label, c[2], Verdict(bucket[c[1]]))
		if loud then
			line[#line + 1] = c[1] .. " " .. Brief(bucket[c[1]])
			if #line == 5 then print(PREFIX .. table.concat(line, "  ")); line = {} end
		end
	end
	if loud and #line > 0 then print(PREFIX .. table.concat(line, "  ")) end
	if loud then print(PREFIX .. "(reasons per route: ForeverDevInfoDB.msProbe after /reload)") end
end

local function RowsState()          -- the two meter rows, plain facts only (their values are secret in combat)
	local a, b = "off", "off"
	if P.remArmed then
		a = ("on (R0 %s %s, base %s%s)"):format(Num(P.r0), P.r0Src or "-", Num(P.r0Base or 0), P.recast and ", stale since the recast" or "")
	end
	if P.castArmed then b = ("on (F %s, cast at %.1f s)"):format(Num(P.castF), (P.castT or 0) - (P.fightT0 or 0)) end
	return ("meter rows: R0-abs %s, F-(now-cast) %s%s"):format(a, b,
		(P.fi and P.fi.secretCast) and ", a cast had a SECRET spell id" or "")
end

local function FightLine(prefix, say)
	local f = P.fight
	say = say or log
	say("%s: melee hits %d (fully absorbed %d, partly %d), UNIT_AURA %d (shield updated %d, secret ids %d), ABSORB_CHANGED %d, combat text %d (absorb %d), meter %d, power %d, combat log %d | %s",
		prefix, f["phys hits"] or 0, f["phys full absorbs"] or 0, f["phys partial absorbs"] or 0, f.UNIT_AURA or 0, f["UNIT_AURA ms updated"] or 0,
		f["UNIT_AURA secret ids"] or 0, f.UNIT_ABSORB_AMOUNT_CHANGED or 0, f.COMBAT_TEXT_UPDATE or 0, f["CT absorb"] or 0,
		f.meter or 0, (f.UNIT_POWER_UPDATE or 0) + (f.UNIT_POWER_FREQUENT or 0), f.combatlog or 0, RowsState())
end

---------------------------------------------------------------------------- events
-- a Mana Shield cast in combat: freeze the meter's value now (secret) in drvCast and arm the cast row.
-- returns armed, the frozen value (maybe secret)
local function ArmCast(F)
	if not (P.drvCast and P.watching) then
		P.castArmed, P.castWhy = false, "cast in combat without a running watch: no at-cast snapshot"
		return false
	end
	local st, A = MeterLocal(M_ABS)
	local v
	if st == "ok" then v = A elseif st == "nil" then v = 0 end   -- no row of yours yet = nothing absorbed yet
	if not (issecretvalue(v) or type(v) == "number") then        -- no "v == nil": v is secret in combat
		P.castArmed, P.castWhy = false, "meter not readable at the cast: " .. st .. " " .. S(A)
		return false
	end
	pcall(P.drvCast.SetValue, P.drvCast, v)
	pcall(P.drvNow.SetValue, P.drvNow, v)
	CastAnchors(F)
	P.castArmed, P.castF, P.castT, P.castWhy = true, F, GetTime(), nil
	return true, v
end

local function OnCast(spellID)
	if issecretvalue(spellID) then
		if P.watching then
			qlog("%6.1f own cast with a <secret> spell id (if it was Mana Shield, no snapshot and no bookkeeping)", T())
			if InCombatLockdown() and P.fi then P.fi.secretCast = true end
		end
		return
	end
	if spellID == nil or not FULL[spellID] then return end
	local combat = InCombatLockdown()
	P.castId = spellID
	local n = DescFull(spellID)
	if n then SetFull(n, "description of " .. spellID) else SetFull(FULL[spellID], "client data for " .. spellID) end
	if WARDING[spellID] then qlog("cast %d is an Advanced Warding copy (aura 69): UnitGetTotalAbsorbs counts it", spellID) end
	local isMS = RANKS[spellID] ~= nil
	if combat then
		if P.watching then Count("cast in combat") end
		if not isMS then Refresh("cast"); return end
		-- the cast listener is always on, but only a watch settles fights; in chat only the 15 s line during a fight
		local fi = P.fi
		-- the shield this cast replaces: the one up at the pull, or one cast earlier in this fight
		local old = fi and ((#fi.casts > 0 and fi.casts[#fi.casts].life) or fi.life)
		if old then P.recast = true end
		local life = NewLife(spellID, "cast in combat (full size until the fight is settled)")
		life.inCombat, life.exp, life.expEst = true, GetTime() + DUR, true
		local armed, v = ArmCast(life.F)
		local snap = armed and (issecretvalue(v) and "secret" or ("plain " .. Num(v))) or P.castWhy
		if fi and P.watching then
			fi.casts[#fi.casts + 1] = { id = spellID, F = life.F, t = GetTime() - fi.t0, armed = armed, life = life }
			fi.snapPlain = (armed and not issecretvalue(v)) and v or nil
			-- the break watch's "first" markers start over: they are about the new shield from here on
			local b = fi.brk
			if b.partT or b.throughT then
				qlog("%6.1f break watch before this cast: partly absorbed hit at %s s, first hit through at %s s", T(), Num(b.partT), Num(b.throughT))
			end
			b.partT, b.partAmt, b.throughT, b.absorbing, b.run = nil, nil, nil, false, 0
		end
		qlog("%6.1f Mana Shield %d cast IN combat: F %s (%s), %s; at-cast snapshot of your meter total: %s", T(), spellID,
			Num(life.F), P.fullSrc or "-", old and ("it replaces shield %s"):format(S(old.id)) or "no shield before it in this fight", snap)
		Refresh("cast")
	else
		P.castArmed, P.castWhy = false, "cast out of combat: the R0 row takes this shield at the pull"
		if isMS then
			local life = NewLife(spellID, "fresh cast (full size)")
			-- R0 - meter would mix this fresh shield with the last fight's total: the row waits for the pull
			P.remArmed, P.remWhy = false, ("fresh shield: R0 = %s at the pull"):format(Num(life.F))
		end
		C_Timer.After(0.2, function()
			local ok, err = pcall(function()
				local _, p1 = ReadAura("cast", P.watching or (P.panel ~= nil and P.panel:IsShown()))
				if p1 then SetFull(p1, "points[1] right after the cast"); SetR0(p1, "points[1] right after the cast") end
				Refresh("cast")
			end)
			if not ok then Bug("after cast", err) end
		end)
	end
end

local function OnUnitAura(info)
	Count("UNIT_AURA")
	if issecretvalue(info) then
		Count("UNIT_AURA secret updateInfo")
		Mark("uaura", "opaque", "updateInfo is secret")
		return
	end
	if type(info) ~= "table" then Count("UNIT_AURA without updateInfo"); return end
	local full = info.isFullUpdate
	if not issecretvalue(full) and full == true then Count("UNIT_AURA full update") end
	local secretIds, msUpd, msRem = 0, 0, 0
	for _, tag in ipairs({ "updatedAuraInstanceIDs", "removedAuraInstanceIDs" }) do
		local list = info[tag]
		if issecretvalue(list) then
			Count("UNIT_AURA " .. tag .. " is secret")
		elseif type(list) == "table" then
			for _, x in ipairs(list) do
				if issecretvalue(x) then
					secretIds = secretIds + 1
				elseif P.inst and x == P.inst then
					if tag == "updatedAuraInstanceIDs" then msUpd = msUpd + 1 else msRem = msRem + 1 end
				end
			end
		end
	end
	local added = info.addedAuras
	if issecretvalue(added) then
		Count("UNIT_AURA addedAuras is secret")
	elseif type(added) == "table" then
		for _, d in ipairs(added) do
			if issecretvalue(d) then
				secretIds = secretIds + 1
			elseif type(d) == "table" then
				local sid, inst = d.spellId, d.auraInstanceID
				if issecretvalue(sid) then
					secretIds = secretIds + 1
				elseif sid ~= nil and FULL[sid] then
					Count("UNIT_AURA shield added (plain)")
					if not issecretvalue(inst) and type(inst) == "number" then P.inst = inst end
				end
			end
		end
	end
	if secretIds > 0 then Count("UNIT_AURA secret ids", secretIds) end
	if msUpd > 0 then Count("UNIT_AURA ms updated") end
	if msRem > 0 then
		Count("UNIT_AURA ms removed")
		-- the moment it went (break or expiry): for the verdict after the fight
		if P.life and P.life.inst == P.inst and not P.life.removedAt then P.life.removedAt = GetTime() end
		local say = InCombatLockdown() and qlog or log         -- in chat only out of combat
		say("%6.1f Mana Shield REMOVED (plain instance id in removedAuraInstanceIDs) = an end signal", T())
	end
	local f = P.fight
	Txt("uaura", ("events %d  shield updated %d  shield removed %d  secret ids %d"):format(f.UNIT_AURA or 0,
		f["UNIT_AURA ms updated"] or 0, f["UNIT_AURA ms removed"] or 0, f["UNIT_AURA secret ids"] or 0))
	if msUpd + msRem > 0 then Mark("uaura", "plain") else Mark("uaura", "ev") end
	if InCombatLockdown() or msUpd + msRem > 0 then
		qlog("%6.1f UNIT_AURA full=%s shieldUpdated=%d shieldRemoved=%d secretIds=%d", T(), S(full), msUpd, msRem, secretIds)
	end
	if not InCombatLockdown() then ReadAura("aura", false) end
end

-- the break watch (plain UNIT_COMBAT payload only): a fully absorbed hit, a partly absorbed one (the hit that
-- broke the shield) and the first hit that got through after absorbed ones, with their time in the fight
local function BreakWatch(flag, amount)
	local fi = P.fi
	if not (fi and InCombatLockdown()) then return end
	local b = fi.brk
	local t = GetTime() - fi.t0
	if flag == "ABSORB" then
		b.absorbing, b.run = true, (b.run or 0) + 1
		if amount == 0 then
			b.full = b.full + 1
		else
			b.part = b.part + 1
			if not b.partT then b.partT, b.partAmt = t, amount end
			qlog("%6.1f PARTIAL absorb at t=%.1f s into fight %d: %s got through = the hit that broke the shield", T(), t, fi.n, Num(amount))
		end
	elseif type(amount) == "number" and amount > 0 then
		b.through = b.through + 1
		if b.absorbing then
			if not b.throughT then b.throughT = t end
			qlog("%6.1f first hit that got through at t=%.1f s into fight %d (%s%s, after %d absorbed)", T(), t, fi.n, Num(amount),
				(flag ~= nil and flag ~= "") and (" " .. S(flag)) or "", b.run or 0)
			b.absorbing, b.run = false, 0
		end
	end
end

local function OnUnitCombat(unit, ev, flag, amount, school)
	Count("UNIT_COMBAT")
	local plain = not (issecretvalue(ev) or issecretvalue(flag) or issecretvalue(amount) or issecretvalue(school))
	if plain then
		Count("UNIT_COMBAT " .. S(ev) .. "/" .. S(flag))
		if ev == "WOUND" and school == 1 then
			Count("phys hits")
			-- CombatFeedback: WOUND + "ABSORB" with amount 0 = fully absorbed, with an amount = partly
			if flag == "ABSORB" then Count(amount == 0 and "phys full absorbs" or "phys partial absorbs") end
			BreakWatch(flag, amount)
		end
		Txt("ucomb", ("%s %s amount %s school %s"):format(S(ev), S(flag), S(amount), S(school)))
		Mark("ucomb", "plain")
	else
		Count("UNIT_COMBAT secret payload")
		if P.fs.ucomb then pcall(P.fs.ucomb.SetText, P.fs.ucomb, amount) end
		Mark("ucomb", "secret")
	end
	qlog("%6.1f UNIT_COMBAT %s %s %s amount %s school %s", T(), S(unit), S(ev), S(flag), S(amount), S(school))
end

local function OnCombatText(kind)
	Count("COMBAT_TEXT_UPDATE")
	if issecretvalue(kind) then
		Count("CT <secret type>")
		Mark("ctabs", "opaque", "combatTextType is secret")
		return
	end
	Count("CT " .. S(kind))
	local fn = C_CombatText and C_CombatText.GetCurrentEventInfo
	if kind == "ABSORB" or kind == "SPELL_ABSORB" or kind == "ABSORB_ADDED" then
		Count("CT absorb")
		local ok, data, arg3, arg4 = call("ctabs", "C_CombatText.GetCurrentEventInfo", fn)
		if ok then
			-- Blizzard_CombatText (70450): ABSORB/SPELL_ABSORB data = damage taken, arg3 = the absorbed part;
			-- ABSORB_ADDED data = the caster's name, arg3 = the shield's amount
			Draw("ctabs", data)
			Draw("ctabs", arg3, nil, true)
		end
		qlog("%6.1f COMBAT_TEXT %s data=%s arg3=%s arg4=%s", T(), kind, ok and S(data) or "ERR", ok and S(arg3) or "-", ok and S(arg4) or "-")
	elseif kind == "SPELL_AURA_END" or kind == "SPELL_AURA_START" or kind == "SPELL_AURA_END_HARMFUL" then
		local ok, data = call("ctend", "C_CombatText.GetCurrentEventInfo", fn)
		if ok then
			Draw("ctend", data)                -- the aura's name: drawable, not comparable
			if P.icons.ctend and C_Spell and type(C_Spell.GetSpellTexture) == "function" then
				local okT, tex = pcall(C_Spell.GetSpellTexture, data)
				if okT then pcall(P.icons.ctend.SetTexture, P.icons.ctend, tex) end
			end
		end
		qlog("%6.1f COMBAT_TEXT %s data=%s", T(), kind, ok and S(data) or "ERR")
	else
		qlog("%6.1f COMBAT_TEXT %s", T(), kind)
	end
end

local function OnRestriction(rtype, state)
	if issecretvalue(rtype) or issecretvalue(state) then qlog("%6.1f ADDON_RESTRICTION_STATE_CHANGED <secret payload>", T()); return end
	local tn, sn = S(RT_NAME[rtype] or rtype), S(RS_NAME[state] or state)
	Count("restriction " .. tn .. " " .. sn)
	local line = ("%6.1f restriction %s -> %s (InCombatLockdown %s, aurasSecret %s)"):format(T(), tn, sn, S(InCombatLockdown()), AurasSecret())
	if rtype == R_COMBAT or rtype == R_ENC then
		-- "always fired before a restriction becomes active, or after it is deactivated": the last/first
		-- moment the shield may still be readable as a plain number
		local p1, how = SnapshotPoints()
		qlog("%s: Mana Shield points[1] = %s (%s)", line, S(p1), how)
		if issecretvalue(p1) or p1 ~= nil then
			Draw("rsnap", p1)
		else
			Txt("rsnap", tn .. " " .. sn .. ": " .. how, 0.6, 0.6, 0.6)
			if P.bars.rsnap then P.bars.rsnap:SetValue(0) end
			Mark("rsnap", "nil", how)
		end
		if rtype == R_COMBAT and state == S_ACTIVATING and not issecretvalue(p1) and type(p1) == "number" then
			SetR0(p1, "restriction snapshot")
			P.snapAt = GetTime()
		end
	else
		qlog("%s", line)
	end
end

-- the tracked shield if it should still be up at the pull, else nil (and forgotten)
local function LifeAtPull()
	local life = P.life
	if not life then return nil end
	if life.goneAt then P.life = nil; return nil end
	if life.exp and GetTime() >= life.exp then
		qlog("bookkeeping: shield %s ran out %.1f s before the pull", S(life.id), GetTime() - life.exp)
		P.life = nil
		return nil
	end
	if AurasOpen() then                 -- still plain at the pull: check that it is really there
		ReadAura("pull", false)
		life = P.life
		if not life or life.goneAt then P.life = nil; return nil end
	end
	return life
end

local function OnCombatStart()
	P.fight, P.st.combat = {}, {}
	for k in pairs(P.errSeen) do
		if k:find("/combat$") then P.errSeen[k] = nil end
	end
	P.fightT0, P.lastSum, P.recast = GetTime(), GetTime(), false
	P.clN, P.clogN = 0, 0         -- the combat log lines in the SV log are capped per fight, so the fight gets its own
	P.fightNo = (P.fightNo or 0) + 1
	if P.settling then
		-- the last fight's values never turned plain before this pull: its bookkeeping is lost
		P.settleGen, P.settling = (P.settleGen or 0) + 1, nil
		if P.life then P.life.rem, P.life.remHi, P.life.remSrc = nil, nil, "unknown: the last fight was never settled" end
		qlog("fight %d began before fight %d was settled (values still secret): its bookkeeping is skipped", P.fightNo, P.fightNo - 1)
	end
	-- the meter's plain state just before the pull: the last out-of-combat read (Tick, every 2 s; nothing is
	-- absorbed out of combat), else a read now. A read now may already hold the fight's first hit (the meter can
	-- start the new session before PLAYER_REGEN_DISABLED), which would make a new session look like a running one
	local fresh = MeterState(false)
	local pre, preHow = nil, "no plain meter read before the pull"
	if P.pre then
		pre, preHow = P.pre, ("last out-of-combat read, %.1f s before the pull"):format(GetTime() - P.pre.t)
	elseif fresh.plain and not fresh.inCombat then
		pre, preHow = fresh, "read at the pull"
	end
	local life = LifeAtPull()
	P.fi = { n = P.fightNo, t0 = P.fightT0, pre = pre, life = life, casts = {}, brk = { full = 0, part = 0, through = 0 } }
	P.remWhy = nil
	if P.snapAt and GetTime() - P.snapAt < 3 then
		P.remArmed = true
	elseif P.lastPoints and P.shieldUp then
		SetR0(P.lastPoints, "last out-of-combat read")
	elseif life and life.rem and life.rem > 0 then
		SetR0(life.rem, life.remSrc or "bookkeeping")      -- a shield already partly used: R0 from the bookkeeping
	elseif life and life.rem then
		P.remArmed, P.r0, P.r0Src = false, nil, "the bookkeeping says the shield is used up"
	elseif life then
		SetR0(life.F or P.full, "full size (no bookkeeping)")
	elseif P.full and P.shieldUp and P.auraId and WARDING[P.auraId] then
		SetR0(P.full, "full size (no fresher read)")
	else
		-- no shield was seen before the pull: "R0 - absorbed" would describe a shield that is not there
		P.remArmed, P.r0, P.r0Src = false, nil, "no shield seen before the pull"
	end
	-- the R0 row's meter base: your total before the pull if Current kept running at the last fight end, else
	-- 0; the first meter event of this fight can still correct it (OnMeterSession)
	P.r0Base = (P.meterRuns and pre and pre.total) or 0
	R0Geometry()
	if P.remDrv then pcall(P.remDrv.SetValue, P.remDrv, P.r0Base) end
	-- the cast row starts over (wider drivers if your total is already large)
	P.castArmed, P.castWhy = false, "no Mana Shield cast in this fight yet"
	if P.drvCast then
		local m, tot = M_PX, pre and pre.total or 0
		if tot > M_PX / 2 then m = M_PX * math.ceil((tot + M_PX / 2) / M_PX) end
		CastRange(m)
		pcall(P.drvCast.SetValue, P.drvCast, 0)
		pcall(P.drvNow.SetValue, P.drvNow, 0)
	end
	log("%6.1f COMBAT START (fight %d)  R0 %s (%s)  full %s  instance %s | meter before: %s", T(), P.fightNo, S(P.r0),
		P.r0Src or "-", S(P.full), S(P.inst), pre and PreShort(pre) or preHow)
	qlog("   meter before the pull (%s): %s", preHow, pre and MeterLine(pre) or "-")
	if pre ~= fresh then
		local moved = fresh.plain and pre and ((fresh.maxId and pre.maxId and fresh.maxId ~= pre.maxId) or fresh.total ~= pre.total)
		qlog("   meter at the pull itself: %s%s", MeterLine(fresh), moved and "  (it had moved already: the fight began before this event)" or "")
	end
	qlog("   at the pull: %s", LifeLine())
end

-- was Current a NEW session for this fight, or one that kept running from before the pull?
-- -> isNew, reason, decisive (false: an assumption, or both readings give the same amount)
local function SessionVerdict(pre, e, fi)
	if fi.reset then return true, "DAMAGE_METER_RESET during the fight", true end
	if not pre then return true, "assumed new: no plain meter state from before the pull", false end
	if e.maxId and pre.maxId and e.maxId > pre.maxId then
		return true, ("new session id %d, the newest before the pull was %d"):format(e.maxId, pre.maxId), true
	end
	if fi.evSess and pre.ids and not pre.ids[fi.evSess] then
		return true, ("the meter events named session %d, unknown before the pull"):format(fi.evSess), true
	end
	if pre.total and e.total and e.total < pre.total then
		return true, ("your total went down from %s to %s: it restarted"):format(Num(pre.total), Num(e.total)), true
	end
	if (pre.total or 0) == 0 then
		return true, "Current was empty before the pull, so new or running gives the same amount", false
	end
	if fi.evSess and pre.ids and pre.ids[fi.evSess] then
		return false, ("the meter events named session %d, which existed before the pull"):format(fi.evSess), true
	end
	if e.curDur and pre.curDur and fi.dur then
		-- each test has 3 s of slack, so a short session before the pull (under ~6 s) fits both: then no evidence
		local runs = e.curDur >= pre.curDur + fi.dur - 3
		local fresh = e.curDur <= fi.dur + 3
		if runs and not fresh then
			return false, ("Current lasted %.0f s = %.0f s before the pull + %.0f s of this fight"):format(e.curDur, pre.curDur, fi.dur), true
		end
		if fresh and not runs then
			return true, ("Current lasted %.0f s, this fight %.0f s"):format(e.curDur, fi.dur), true
		end
	end
	if e.maxId and pre.maxId then
		return false, ("no new session id (newest %d before and after the fight)"):format(e.maxId), true
	end
	return true, "assumed new: no evidence either way", false
end

local function WidthTxt(fr, expect)  -- a readout frame's width now: plain (and vs the bookkeeping) or secret
	if not fr then return "off" end
	local ok, w = pcall(fr.GetWidth, fr)
	if not ok then return "ERROR " .. Short(w) end
	if issecretvalue(w) then return "secret (drawn only)" end
	if type(w) ~= "number" then return S(w) end
	local s = ("%.0f plain"):format(w)
	if PlainNum(expect) then s = s .. (math.abs(w - expect) < 0.6 and ", MATCH" or (", bookkeeping says " .. Num(expect))) end
	return s
end

-- after a fight, all arithmetic on plain values: what the meter credits Mana Shield with, what is left of the
-- shield, is it still up? e = the plain meter state (nil: it stayed secret), d = the aura read just now (nil:
-- none, or auras not open)
local function Bookkeep(e, d)
	local fi = P.fi
	if not fi or fi.settled then
		-- a fight whose pull the watch did not see (/fdms watch typed in combat): what it took from the shield is
		-- unknown, and settling it with an older fight's data would count that fight twice
		local life = P.life
		if life then life.rem, life.remHi, life.remSrc = nil, nil, "unknown: a fight was not watched from its pull" end
		log("Mana Shield: this fight was not watched from its pull, nothing settled%s", life and "; the shield's amount is now unknown" or "")
		return
	end
	fi.settled = true
	local pull, nCast = fi.life, #fi.casts
	-- the shield this fight is about: the last one cast in it, else the one up at the pull (a shield cast
	-- after the fight, before it was settled, is not it)
	local life = nCast > 0 and fi.casts[nCast].life or pull
	-- 1. what the meter credits Mana Shield with in this fight
	local X, isNew, why, decisive
	if e then
		isNew, why, decisive = SessionVerdict(fi.pre, e, fi)
		-- Mana Shield's per-spell amount at both ends, or your whole total at both ends (never one of each)
		local useMs = e.ms ~= nil and (isNew or fi.pre.ms ~= nil)
		local msEnd, msPre = useMs and e.ms or e.total, 0
		if not isNew then msPre = (useMs and fi.pre.ms or fi.pre.total) or 0 end
		X = msEnd - msPre
		if X < 0 then
			X, isNew, decisive = msEnd, true, true
			why = why .. "; but Mana Shield's amount went down, so it restarted after all"
		end
		if decisive then P.meterRuns = not isNew end
		qlog("bookkeeping, fight %d: Current is %s session (%s). Mana Shield absorbed %s in this fight (%s at the end%s)%s", fi.n,
			isNew and "a NEW" or "a RUNNING", why, Num(X), Num(msEnd), isNew and "" or (" - " .. Num(msPre) .. " before the pull"),
			useMs and "" or "; the per-spell list was not readable: your whole total was used")
		qlog("   meter after the fight: %s", MeterLine(e))
	else
		qlog("bookkeeping, fight %d: the meter stayed secret, nothing to settle", fi.n)
	end
	-- 2. what is left of the shield
	local tag = ("(meter, %s)"):format(e and e.msIdTxt or "?")
	local rem, hi, n, line1, assumed
	if nCast == 0 then
		if not pull then
			line1 = ("Mana Shield: none up at the pull, none cast in combat (meter: Mana Shield %s)"):format(X and Num(X) or "?")
		elseif not X then
			line1 = ("Mana Shield: R0 %s, the meter stayed secret: nothing settled"):format(Num(pull.rem or pull.F))
		elseif pull.rem then
			n, rem = X, pull.rem - X
			if pull.remHi then             -- only a range was known (a recast): it stays a range
				hi = pull.remHi - X
				line1 = ("Mana Shield: R0 %s..%s - absorbed %s %s = %s..%s left"):format(Num(pull.rem), Num(pull.remHi), Num(X), tag,
					Num(rem), Num(hi))
			else
				line1 = ("Mana Shield: R0 %s - absorbed %s %s = %s left"):format(Num(pull.rem), Num(X), tag, Num(rem))
			end
		elseif pull.F then
			-- an earlier fight was never settled: the pull took the full size, so does this
			n, rem, assumed = X, pull.F - X, true
			line1 = ("Mana Shield: R0 %s (full size assumed) - absorbed %s %s = %s left"):format(Num(pull.F), Num(X), tag, Num(rem))
		else
			line1 = ("Mana Shield: R0 unknown - absorbed %s %s"):format(Num(X), tag)
		end
	else
		local c = fi.casts[nCast]
		local label = (pull or nCast > 1) and "recast" or "cast"
		local snap, snapHow = fi.snapPlain, "plain at the cast"
		if snap == nil and c.armed and P.drvCast then
			local ok, v = pcall(P.drvCast.GetValue, P.drvCast)
			qlog("   at-cast snapshot read back after the fight: %s", ok and S(v) or "ERROR")
			if ok and PlainNum(v) then snap, snapHow = v, "read back plainly after the fight" end
		end
		local lo
		if X then
			if snap and e.total then
				n = e.total - snap
				qlog("   cast in combat: your total %s now - %s at the cast (%s) = %s since the cast (all your absorbs)",
					Num(e.total), Num(snap), snapHow, Num(n))
			elseif not pull and nCast == 1 then
				n = X
			else
				-- the earlier shield(s) of this fight took an unknown part of X, at most what they had
				local before = pull and (pull.rem or pull.F) or 0
				for i = 1, nCast - 1 do before = before + fi.casts[i].F end
				lo = math.max(0, X - before)
			end
		end
		if n then
			rem = c.F - n
			line1 = ("Mana Shield %s in combat at %.1f s: F %s - absorbed %s %s = %s left"):format(label, c.t, Num(c.F), Num(n), tag, Num(rem))
		elseif lo then
			rem, hi = c.F - X, c.F - lo
			line1 = ("Mana Shield %s in combat at %.1f s: F %s - absorbed %s..%s %s = %s..%s left (the old shield's part is unknown)"):format(
				label, c.t, Num(c.F), Num(lo), Num(X), tag, Num(rem), Num(hi))
		else
			line1 = ("Mana Shield %s in combat at %.1f s: F %s, the meter stayed secret: nothing settled"):format(label, c.t, Num(c.F))
		end
	end
	-- 3. is it still up? (the aura is plain again out of combat)
	local now, state = GetTime(), nil
	-- a refused or secret aura answer (P.auraUnclear) is no "it is gone"
	local open = AurasOpen() and not (d == nil and P.auraUnclear)
	if d ~= nil and open then
		if life and P.life == life then
			if rem then
				life.rem, life.remHi = rem, hi
				life.remSrc = ("bookkeeping after fight %d%s%s"):format(fi.n, hi and ", lower end" or "",
					assumed and ", from an assumed full size" or "")
			elseif not X then
				life.rem, life.remHi, life.remSrc = nil, nil, ("unknown: fight %d was never settled"):format(fi.n)
			end
			life.fights, life.absorbed = (life.fights or 0) + 1, (life.absorbed or 0) + (n or X or 0)
			local left = life.exp and (life.exp - now)
			state = ("shield still up (%s s to go)"):format(left and ("%.0f"):format(left) or "?")
		elseif P.life and not P.life.seenOnly and P.life.castAt >= fi.t0 + (fi.dur or 0) then
			state = "Mana Shield was cast again after the fight: the new one starts at full size"
		else
			state = "a shield is up that was not tracked (its cast not seen?): taken as full size"
		end
	elseif open then
		if not life then
			state = "no Mana Shield on you"
		else
			local F = life.F or P.full or 0
			local exp = life.exp
			local expired = exp and now >= exp - 0.5
			local usedUp = rem and rem <= math.max(1, 0.02 * F)
			local remTxt = rem and (Num(rem) .. (hi and (".." .. Num(hi)) or "")) or "an unknown amount"
			-- the earliest moment it is known to have been gone (plain times only): its removal seen in UNIT_AURA,
			-- the partly absorbed hit (the one that broke it), or the first hit that got through after absorbed ones
			local b, endAt, endHow = fi.brk, nil, nil
			if life.removedAt and life.removedAt >= fi.t0 then endAt, endHow = life.removedAt, "its removal (UNIT_AURA)"
			elseif b.partT then endAt, endHow = fi.t0 + b.partT, "the partly absorbed hit"
			elseif b.throughT then endAt, endHow = fi.t0 + b.throughT, "the first hit that got through"
			end
			local early = exp and endAt and endAt < exp - 0.5          -- gone before its time ran out
			local fightEnd = fi.t0 + (fi.dur or 0)
			local v
			if usedUp then
				local at = endAt or ((not expired) and now) or nil
				v = ("BROKE: the meter says it was used up%s"):format((exp and at) and (", %.0f s before it would have expired"):format(exp - at)
					or (expired and " (its time is over by now too)" or ""))
			elseif early then
				v = ("BROKE: gone by %s at %.1f s, %.0f s before its expirationTime%s"):format(endHow, endAt - fi.t0, exp - endAt,
					rem and (", although the meter says %s left (the meter short, or out of mana?)"):format(remTxt) or "")
			elseif exp and not expired then
				v = ("BROKE: it went %.0f s before its expirationTime%s"):format(exp - now,
					rem and (", although the meter says %s left (the meter short, or out of mana?)"):format(remTxt) or "")
			elseif expired then
				local when = exp <= fightEnd + 0.5 and ("%.0f s into the fight"):format(exp - fi.t0)
					or ("%.0f s after the fight"):format(exp - fightEnd)
				v = ("EXPIRED with %s unused (its time ran out %s%s)"):format(remTxt, when, life.expEst and ", estimated" or "")
			else
				v = "gone (no expirationTime known)"
			end
			local ev = {}
			if b.partT then ev[#ev + 1] = ("a partly absorbed hit at %.1f s (%s got through)"):format(b.partT, Num(b.partAmt)) end
			if b.throughT then ev[#ev + 1] = ("first hit through at %.1f s"):format(b.throughT) end
			state = "shield gone: " .. v .. (#ev > 0 and ("; " .. table.concat(ev, ", ")) or "")
			qlog("   shield %s gone: F %s, left by the meter %s, expirationTime %s (now %s)", S(life.id), Num(F), Num(rem), Num(exp), Num(now))
		end
		if P.life == life then P.life = nil end
	else
		state = "shield state unknown (auras still secret)"
		if life and rem then
			life.rem, life.remHi, life.remSrc = rem, hi, ("bookkeeping after fight %d (aura not checked)"):format(fi.n)
		elseif life and not X and (pull or nCast > 0) then
			life.rem, life.remHi, life.remSrc = nil, nil, ("unknown: fight %d was never settled"):format(fi.n)
		end
	end
	-- chat: 3 lines
	log("%s; %s", line1, state)
	local b = fi.brk
	local hits = ("melee: %d fully absorbed, %d partly%s, %d got through%s"):format(b.full, b.part,
		b.partT and (" (at %.1f s)"):format(b.partT) or "", b.through,
		b.throughT and (" (the first after absorbed ones at %.1f s)"):format(b.throughT) or "")
	if e then
		local youX = isNew and e.total or (e.total - ((fi.pre and fi.pre.total) or 0))
		log("meter: Current is %s session (%s)%s | you absorbed %s in this fight, Mana Shield %s | %s", isNew and "a NEW" or "a RUNNING",
			why, fi.sidChanged and "; it changed mid-fight, so part of the fight may be in another session" or "", Num(youX), Num(X), hits)
	else
		log("meter: still secret after the fight, nothing settled | %s", hits)
	end
	log("panel now: R0-abs %s, F-(now-cast) %s (both count all your absorbs) | details: log after /reload",
		WidthTxt(P.remArmed and P.remFrame, (nCast == 0 and pull) and rem or nil),
		WidthTxt(P.castArmed and P.cmFrame, (nCast > 0 and n) and rem or nil))
	qlog("   after fight %d: %s", fi.n, LifeLine())
end

local function AfterFight(e, tries)
	P.settling = nil
	Refresh("after combat")
	local d, p1, left = ReadAura("after combat", false)
	-- points[1] is empty on this client (round 1); kept for a client that sends it
	if d and p1 then qlog("after combat: points[1] = %s of %s, %s s to go", S(p1), S(P.full), left and ("%.0f"):format(left) or "?") end
	if tries > 1 then qlog("after combat: plain on try %d", tries) end
	local ok, err = pcall(Bookkeep, e, d)
	if not ok then Bug("Bookkeep", err) end
	if e then P.pre, P.preT = e, GetTime() end
	FightLine("fight counts", qlog)
	qlog("all counts this fight: %s", CountLine(P.fight))
	PrintVerdicts("combat", false, "this fight, in combat")
end

local function OnCombatEnd()
	P.fightDur = GetTime() - (P.fightT0 or GetTime())
	if P.fi then P.fi.dur = P.fightDur end
	qlog("%6.1f COMBAT END after %.1f s", T(), P.fightDur)
	-- the meter and the auras turn plain again shortly after the fight: retry until then (a new pull cancels it)
	P.settleGen = (P.settleGen or 0) + 1
	P.settling = true
	local gen, tries = P.settleGen, 0
	local step
	step = function()
		if gen ~= P.settleGen then return end
		tries = tries + 1
		local ok, err = pcall(function()
			local e = MeterState(true)
			local open = AurasOpen()
			if not (e.plain and open) and tries < SETTLE_TRIES then
				if tries == 1 then
					qlog("%6.1f after combat: still secret (meter %s, auras %s), waiting for plain values", T(),
						e.plain and "plain" or "secret", open and "open" or "secret")
				end
				C_Timer.After(0.5, step)
				return
			end
			if not e.plain then qlog("after combat: the meter is still secret after %d tries (%s)", tries, S(e.why)) end
			AfterFight(e.plain and e or nil, tries)
		end)
		if not ok then P.settling = nil; Bug("AfterFight", err) end
	end
	C_Timer.After(0.3, step)
end

local function OnCombatLogMessage(msg)
	Count("combatlog")
	Count("COMBAT_LOG_MESSAGE")
	if P.fs.clog then
		local ok = pcall(P.fs.clog.SetText, P.fs.clog, msg)
		if not ok then Mark("clog", "err", "SetText refused")
		elseif issecretvalue(msg) then Mark("clog", "secret")
		else Mark("clog", "plain") end
	end
	P.clogN = (P.clogN or 0) + 1
	if P.clogN <= 25 then qlog("%6.1f COMBAT_LOG_MESSAGE %s", T(), S(msg)) end
end

-- the event-info getters a combat log callback may answer through (each one tried, in a pcall)
local CL_GETTERS = {
	{ "C_CombatLogInternal", function() return C_CombatLogInternal and C_CombatLogInternal.GetCurrentEventInfo end },
	{ "C_CombatLogSecure", function() return C_CombatLogSecure and C_CombatLogSecure.GetCurrentEventInfo end },
	{ "CombatLogGetCurrentEventInfo", function() return CombatLogGetCurrentEventInfo end },
}

local function OnCombatLogCallback(ev, route, ...)
	Count("combatlog")
	Count("CL " .. route .. " " .. ev)
	Mark("clint", "ev")
	P.clN = (P.clN or 0) + 1
	local logIt = P.clN <= 40
	local npay = select("#", ...)
	local any = false
	for _, g in ipairs(CL_GETTERS) do
		local fn = g[2]()
		if type(fn) == "function" then
			any = true
			local n, r = Pack(pcall(fn))
			if not r[1] then
				Mark("clint", "err", g[1] .. ": " .. Short(r[2]))
				if logIt then qlog("%6.1f CL %s via %s, %s: ERROR %s", T(), ev, route, g[1], Short(r[2])) end
			elseif n <= 1 then
				Mark("clint", "nil", g[1] .. " returned nothing")
			else
				-- 1 timestamp 2 subevent ... 12+ params (SWING_DAMAGE 17 = absorbed, SPELL_ABSORBED 19/22 = amount)
				local secret = issecretvalue(r[2]) or issecretvalue(r[3])
				Mark("clint", secret and "opaque" or "plain", secret and (g[1] .. ": event info is secret") or nil)
				if not secret then Txt("clint", ("%s via %s/%s: %s, %s values"):format(ev, route, g[1], S(r[3]), S(n - 1))) end
				if logIt then
					local parts = {}
					for i = 2, math.min(n, 26) do parts[#parts + 1] = S(r[i]) end
					qlog("%6.1f CL %s via %s, %s: %s (payload %d)", T(), ev, route, g[1], table.concat(parts, " | "), npay)
				end
			end
		end
	end
	if not any and logIt then qlog("%6.1f CL %s via %s (payload %d values, no event-info getter)", T(), ev, route, npay) end
end

local function SafeCL(ev, route, ...)       -- callbacks run outside any pcall of ours
	local ok, err = pcall(OnCombatLogCallback, ev, route, ...)
	if not ok then Bug("combat log " .. route, err) end
end

local function HookCombatLog()
	if P.clRegs then return end
	P.clRegs = {}
	P.clFrame = P.clFrame or CreateFrame("Frame")
	local f = P.clFrame
	local res = {}
	for _, ev in ipairs({ "COMBAT_LOG_EVENT_INTERNAL_UNFILTERED", "COMBAT_LOG_EVENT_UNFILTERED" }) do
		local short = ev == "COMBAT_LOG_EVENT_UNFILTERED" and "CLEU" or "CLEU-internal"
		if type(f.RegisterEventCallback) == "function" then
			local ok, r = pcall(f.RegisterEventCallback, f, ev, function(...) SafeCL(ev, "frame", ...) end)
			res[#res + 1] = ("%s frame cb %s"):format(short, ok and S(r) or "ERR")
			qlog("frame:RegisterEventCallback(%s) -> %s", ev, ok and ("ok " .. S(r)) or ("ERROR " .. Short(r)))
			if ok then P.clRegs[#P.clRegs + 1] = { kind = "frame", ev = ev } end
		end
		local CFC = C_FunctionContainers
		if type(RegisterEventCallback) == "function" and CFC and type(CFC.CreateCallback) == "function" then
			local okC, cb = pcall(CFC.CreateCallback, function(_, ...) SafeCL(ev, "global", ...) end)
			if okC and cb then
				local okG, errG = pcall(RegisterEventCallback, ev, cb)
				res[#res + 1] = ("%s global cb %s"):format(short, okG and "ok" or "ERR")
				qlog("RegisterEventCallback(%s) -> %s", ev, okG and "ok" or ("ERROR " .. Short(errG)))
				if okG then P.clRegs[#P.clRegs + 1] = { kind = "global", ev = ev, cb = cb } end
			end
		end
		local okR, errR = pcall(f.RegisterEvent, f, ev)
		res[#res + 1] = ("%s event %s"):format(short, okR and "ok" or "ERR")
		qlog("frame:RegisterEvent(%s) -> %s", ev, okR and "ok" or ("ERROR " .. Short(errR)))
		if okR then P.clRegs[#P.clRegs + 1] = { kind = "event", ev = ev } end
	end
	f:SetScript("OnEvent", function(_, ev, ...) SafeCL(ev, "event", ...) end)
	Txt("clint", table.concat(res, ", "))
	qlog("C_CombatLogInternal: %s, C_CombatLog.IsCombatLogRestricted %s", type(C_CombatLogInternal),
		S(C_CombatLog and type(C_CombatLog.IsCombatLogRestricted) == "function" and select(2, pcall(C_CombatLog.IsCombatLogRestricted))))
end

local function UnhookCombatLog()
	local f = P.clFrame
	for _, r in ipairs(P.clRegs or {}) do
		if r.kind == "frame" then pcall(f.UnregisterEventCallback, f, r.ev)
		elseif r.kind == "global" then pcall(UnregisterEventCallback, r.ev, r.cb)
		else pcall(f.UnregisterEvent, f, r.ev) end
	end
	P.clRegs = nil
end

-- DAMAGE_METER_COMBAT_SESSION_UPDATED (type, sessionID): the first plain session id of a fight tells whether
-- Current is a new session or the one from before the pull, and so the base of the R0 row
local function OnMeterSession(mtype, sid)
	if not PlainNum(sid) then
		if not P.sidSaid then P.sidSaid = true; qlog("%6.1f meter event session id is %s (type %s)", T(), S(sid), S(mtype)) end
		return
	end
	P.lastSid = sid
	local fi = P.fi
	if fi and fi.evSess and sid ~= fi.evSess and InCombatLockdown() and not fi.sidChanged then
		-- Current moved to another session mid-fight: a value frozen before (the at-cast snapshot) is then off
		fi.sidChanged = true
		qlog("%6.1f the meter events now name session %d (first in fight %d: %d): Current changed mid-fight%s", T(), sid, fi.n,
			fi.evSess, P.castArmed and "; the F-(now-cast) row's frozen value is from the other session" or "")
	end
	if not (fi and InCombatLockdown()) or fi.evSess then return end
	fi.evSess = sid
	local pre = fi.pre
	if not (pre and pre.ids) then
		qlog("%6.1f first meter update of fight %d: session %d (type %s); no plain session list from before the pull", T(), fi.n, sid, S(mtype))
		return
	end
	local known = pre.ids[sid] == true
	local base = known and (pre.total or 0) or 0
	qlog("%6.1f first meter update of fight %d: session %d (type %s), which %s before the pull -> %s; the R0 row counts from %s",
		T(), fi.n, sid, S(mtype), known and "existed" or "did NOT exist", known and "Current kept running" or "a NEW session", Num(base))
	if base ~= (P.r0Base or 0) then
		P.r0Base = base
		R0Geometry()
	end
end

local function OnMeterReset()
	local fi = P.fi
	local combat = InCombatLockdown()
	if combat and fi then
		fi.reset = true
		P.r0Base = 0
		R0Geometry()
	else
		P.pre = nil                       -- the next tick reads it again
	end
	local say = combat and qlog or log
	say("%6.1f DAMAGE_METER_RESET: all meter sessions cleared", T())
end

local REFRESH_ON = {
	UNIT_AURA = true, UNIT_ABSORB_AMOUNT_CHANGED = true, UNIT_COMBAT = true, COMBAT_TEXT_UPDATE = true,
	ADDON_RESTRICTION_STATE_CHANGED = true, PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true,
	DAMAGE_METER_COMBAT_SESSION_UPDATED = true, DAMAGE_METER_CURRENT_SESSION_UPDATED = true, DAMAGE_METER_RESET = true,
}

local function OnWatchEvent(_, event, a1, a2, a3, a4, a5)
	if not P.watching then return end
	if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
		Count(event)
		DrawPower()
		return
	end
	if event == "UNIT_AURA" then OnUnitAura(a2)
	elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then Count(event); qlog("%6.1f UNIT_ABSORB_AMOUNT_CHANGED", T())
	elseif event == "UNIT_COMBAT" then OnUnitCombat(a1, a2, a3, a4, a5)
	elseif event == "COMBAT_TEXT_UPDATE" then OnCombatText(a1)
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then OnRestriction(a1, a2)
	elseif event == "PLAYER_REGEN_DISABLED" then OnCombatStart()
	elseif event == "PLAYER_REGEN_ENABLED" then OnCombatEnd()
	elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
		Count("meter")
		Count(event .. ((not issecretvalue(a1) and a1 ~= nil) and (" type " .. S(a1)) or ""))
		if event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
			OnMeterSession(a1, a2)
		elseif (P.fight[event] or 0) <= 3 then
			qlog("%6.1f %s (%s, fight %s)", T(), event, State(), S(P.fi and P.fi.n))
		end
	elseif event == "DAMAGE_METER_RESET" then
		Count(event)
		OnMeterReset()
	elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" then
		Count(event)
		log("%6.1f %s %s %s (Encounter restriction %s)", T(), event, S(a1), S(a2), RState(R_ENC))
	elseif event == "COMBAT_LOG_MESSAGE" then OnCombatLogMessage(a1)
	else Count(event) end
	if REFRESH_ON[event] then Refresh(event) end
end

local function StopWatch(reason)
	if not P.watching then return end
	P.watching = false
	if P.watchFrame then P.watchFrame:UnregisterAllEvents() end
	if P.ticker then P.ticker:Cancel(); P.ticker = nil end
	UnhookCombatLog()
	log("watch stopped (%s). /reload writes the log (ForeverDevInfoDB.msProbe) to disk.", reason)
end

local function Tick()
	if not P.watching then return end
	Refresh("tick")
	local now = GetTime()
	if InCombatLockdown() and now - (P.lastSum or now) >= 15 then
		P.lastSum = now
		FightLine(("%6.1f in combat %.0f s"):format(T(), now - (P.fightT0 or now)), log)
	end
	-- between fights: the plain meter state, "before the pull" of the next fight
	if not InCombatLockdown() and not P.settling and now - (P.preT or 0) >= 2 then
		P.preT = now
		local m = MeterState(false)
		if m.plain then P.pre = m end
	end
	if now >= (P.watchEnd or 0) and not InCombatLockdown() and not P.settling then StopWatch("time is up") end
end

local function Watch(secs)
	P.cnt, P.fight = {}, {}
	P.t0 = GetTime()
	-- an older watch's last fight and meter read must not stand in for a fight this watch did not see begin
	-- (kept while a fight this watch saw is running or still being settled: /fdms watch typed again)
	if not (P.settling or (P.watching and InCombatLockdown())) then P.fi, P.pre = nil, nil end
	if not InCombatLockdown() then
		-- refresh what the pull relies on (shield up? its amount and ids) instead of trusting an old /fdms read
		local _, p1 = ReadAura("watch", false)
		if p1 then SetR0(p1, "points[1] at /fdms watch") end
		local m = MeterState(false)
		if m.plain then P.pre, P.preT = m, GetTime() end
		qlog("watch start: meter %s | %s", MeterLine(m), LifeLine())
	end
	P.watchEnd = GetTime() + secs
	P.clN, P.clogN = 0, 0
	P.watching = true
	P.watchFrame = P.watchFrame or CreateFrame("Frame")
	local w = P.watchFrame
	w:UnregisterAllEvents()
	local failed = {}
	for _, ev in ipairs({ "UNIT_AURA", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_COMBAT", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT" }) do
		local ok, err = pcall(w.RegisterUnitEvent, w, ev, "player")
		if not ok then failed[#failed + 1] = ev .. ": " .. Short(err) end
	end
	for _, ev in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED", "COMBAT_TEXT_UPDATE",
		"DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET", "ENCOUNTER_START",
		"ENCOUNTER_END", "COMBAT_LOG_MESSAGE" }) do
		local ok, err = pcall(w.RegisterEvent, w, ev)
		if not ok then failed[#failed + 1] = ev .. ": " .. Short(err) end
	end
	w:SetScript("OnEvent", function(...)
		local ok, err = pcall(OnWatchEvent, ...)
		if not ok then Bug("event " .. S(select(2, ...)), err) end
	end)
	if #failed > 0 then log("could not register: %s", table.concat(failed, "; ")) end
	HookCombatLog()
	if P.ticker then P.ticker:Cancel() end
	P.ticker = C_Timer.NewTicker(0.25, function()
		local ok, err = pcall(Tick)
		if not ok then Bug("Tick", err) end
	end)
	log("watching %d s. Cast Mana Shield, pull ONE melee mob at a time (the shield takes physical damage only), take hits. After each fight 3 chat lines settle the shield; /fdms hide stops.", secs)
end

---------------------------------------------------------------------------- report
local function ReportCDM()
	local okA, avail, why = false, nil, nil
	if C_CooldownViewer and type(C_CooldownViewer.IsCooldownViewerAvailable) == "function" then
		okA, avail, why = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
	end
	local it, vname = FindCDMItem()
	P.cdmItem, P.cdmViewer = it, vname
	local shown = "-"
	if vname then
		local v = _G[vname]
		local okS, s = pcall(v.IsShown, v)
		shown = okS and S(s) or "ERR"
	end
	local sets = {}
	local CV = C_CooldownViewer or {}
	if type(CV.GetCooldownViewerCategorySet) == "function" and type(CV.GetCooldownViewerCooldownInfo) == "function" then
		for _, cat in ipairs(CDM_CATS) do
			local okC, ids = pcall(CV.GetCooldownViewerCategorySet, cat, true)
			if okC and not issecretvalue(ids) and type(ids) == "table" then
				for _, cid in ipairs(ids) do
					local okI, info = pcall(CV.GetCooldownViewerCooldownInfo, cid)
					if okI and InfoIsMS(info) then sets[#sets + 1] = ("category %s cooldownID %s"):format(S(cat), S(cid)) end
				end
			end
		end
	end
	log("Cooldown Manager: cooldownViewerEnabled=%s available=%s %s | Mana Shield item %s (%s, shown %s) | in sets: %s",
		CVar("cooldownViewerEnabled"), okA and S(avail) or "ERR", S(why), it and "found" or "NOT found", S(vname), shown,
		#sets > 0 and table.concat(sets, ", ") or "none")
end

local function ReportMeter()
	local okA, avail, why = false, nil, nil
	if C_DamageMeter and type(C_DamageMeter.IsDamageMeterAvailable) == "function" then okA, avail, why = pcall(C_DamageMeter.IsDamageMeterAvailable) end
	local st1, v1 = MeterLocal(M_ABS)
	local st2, v2 = MeterLocal(M_HEAL)
	local st3, v3 = MeterLocal(M_TAKEN)
	log("damage meter: available %s %s, damageMeterEnabled=%s | you: Absorbs %s %s, HealingDone %s %s, DamageTaken %s %s",
		okA and S(avail) or "ERR", S(why), CVar("damageMeterEnabled"), st1, S(v1), st2, S(v2), st3, S(v3))
	log("damage meter Absorbs: %s", MeterLine(MeterState(true)))
end

local function Report()
	BuildPanel()
	local _, build = GetBuildInfo()
	log("---- /fdms  build %s  combat %s  aurasSecret %s  restrictions: Combat %s Encounter %s Map %s Chat %s", S(build),
		S(InCombatLockdown()), AurasSecret(), RState(R_COMBAT), RState(R_ENC), RState(R_MAP), RState(R_CHAT))
	P.knownRank = KnownRank()
	local secrecy, ranks = {}, {}
	for _, id in ipairs({ 1463, 8494, 8495, 10191, 10192, 10193 }) do
		local k = "ERR"
		if C_Secrets and type(C_Secrets.GetSpellAuraSecrecy) == "function" then
			local okS, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, id)
			if okS and not issecretvalue(lvl) then k = SECRECY[lvl] or S(lvl) end
		end
		secrecy[k] = (secrecy[k] or 0) + 1
		local n, st = DescFull(id)
		ranks[#ranks + 1] = ("%d=%s"):format(id, st == "plain" and S(n) or st)
	end
	local sec = {}
	for k, n in pairs(secrecy) do sec[#sec + 1] = k .. " x" .. n end
	local adv = "?"
	if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
		local okK, k = pcall(C_SpellBook.IsSpellKnown, 412115, E.SpellBookSpellBank and E.SpellBookSpellBank.Player or 0)
		adv = okK and S(k) or "ERR"
	end
	log("ranks (description $s1): %s | highest known %s | aura secrecy: %s | Advanced Warding rune known %s",
		table.concat(ranks, " "), S(P.knownRank), table.concat(sec, " "), adv)
	GuessFull()
	local _, p1 = ReadAura("report", true)
	if p1 and not InCombatLockdown() then SetR0(p1, "points[1] at /fdms") end
	log("%s", LifeLine())
	ReportCDM()
	ReportMeter()
	log("combat text: enableFloatingCombatText=%s floatingCombatTextDamageReduction_v2=%s floatingCombatTextAuras_v2=%s (/fdms fct turns them on)",
		CVar("enableFloatingCombatText"), CVar("floatingCombatTextDamageReduction_v2"), CVar("floatingCombatTextAuras_v2"))
	-- this report's verdicts get a bucket of their own, so a watch's fight counts stay intact
	local label = "this /fdms, " .. (InCombatLockdown() and "in combat" or "out of combat")
	P.st.report, P.bucket, P.tipT = {}, "report", 0
	Refresh("report")
	P.bucket = nil
	PrintVerdicts("report", true, label)
	log("full size for the bars: %s (%s). Next: /fdms watch, then pull a melee mob.", S(P.full), P.fullSrc or "-")
end

---------------------------------------------------------------------------- raid check
local function GroupUnits()
	local units = {}
	local okR, inRaid = pcall(IsInRaid)
	inRaid = okR and not issecretvalue(inRaid) and inRaid == true
	local okN, n = pcall(GetNumGroupMembers)
	if not okN or issecretvalue(n) or type(n) ~= "number" then n = 0 end
	if inRaid then
		for i = 1, math.min(n, 40) do units[#units + 1] = "raid" .. i end
	else
		units[1] = "player"
		for i = 1, math.min(math.max(n - 1, 0), 4) do units[#units + 1] = "party" .. i end
	end
	return units, inRaid, n
end

local function BuildRaidRow(units)
	P.raid = {}
	P.raidPool = P.raidPool or {}     -- up to 8 slots, made once and reused (a new AuraContainer per /fdms raid leaked)
	if not P.raidHost then
		local h = CreateFrame("Frame", nil, P.panel)
		h:SetSize(W, 56)
		h:SetPoint("BOTTOMLEFT", P.panel, "TOPLEFT", 0, 2)
		local bg = h:CreateTexture(nil, "BACKGROUND", nil, -8)
		bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.75)
		local cap = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		cap:SetPoint("TOPLEFT", h, "TOPLEFT", 6, -2)
		cap:SetText("/fdms raid: Mana Shield container per member + UnitGetTotalAbsorbs")
		P.raidHost = h
	end
	P.raidHost:Show()
	for i = 1, 8 do
		local u, r = units[i], P.raidPool[i]
		if u then
			if not r then
				local x = 6 + (i - 1) * 68
				local host = NewHost(P.raidHost)
				host:SetSize(18, 18)
				host:SetPoint("TOPLEFT", P.raidHost, "TOPLEFT", x, -16)
				local name = P.raidHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				name:SetPoint("TOPLEFT", P.raidHost, "TOPLEFT", x, -36)
				name:SetWidth(64); name:SetJustifyH("LEFT"); name:SetWordWrap(false)
				local abs = P.raidHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
				abs:SetPoint("TOPLEFT", P.raidHost, "TOPLEFT", x, -46)
				abs:SetTextColor(0.4, 1, 0.4)
				local c, b, err = MakeContainer(host, u)
				if err then qlog("raid container %s: %s", u, err) end
				r = { host = host, c = c, b = b, abs = abs, name = name }
				P.raidPool[i] = r
			elseif r.c then
				pcall(r.c.SetUnit, r.c, u)
			end
			r.unit = u
			r.host:Show(); r.name:Show(); r.abs:Show()
			r.abs:SetText("")
			local okN, nm = pcall(UnitName, u)
			if okN then pcall(r.name.SetText, r.name, nm) else r.name:SetText(u) end
			P.raid[#P.raid + 1] = r
		elseif r then
			if r.c then pcall(r.c.SetUnit, r.c, nil) end
			r.host:Hide(); r.name:Hide(); r.abs:Hide()
		end
	end
end

local function RaidReport()
	BuildPanel()
	local units, inRaid, n = GroupUnits()
	local okI, iname, itype, diff, diffName, maxP = pcall(GetInstanceInfo)
	log("---- /fdms raid  raid %s  members %s  instance %s (%s, difficulty %s %s, max %s)  combat %s  restrictions: Combat %s Encounter %s Map %s Chat %s",
		S(inRaid), S(n), okI and S(iname) or "ERR", okI and S(itype) or "-", okI and S(diff) or "-", okI and S(diffName) or "-",
		okI and S(maxP) or "-", S(InCombatLockdown()), RState(R_COMBAT), RState(R_ENC), RState(R_MAP), RState(R_CHAT))
	local A = C_UnitAuras or {}
	for i, u in ipairs(units) do
		local okE, ex = pcall(UnitExists, u)
		local okN, nm = pcall(UnitName, u)
		local first
		local okA, d = false, "missing"
		if type(A.GetAuraDataByIndex) == "function" then okA, d = pcall(A.GetAuraDataByIndex, u, 1, "HELPFUL") end
		if not okA then first = "ERROR " .. Short(d)
		elseif issecretvalue(d) then first = "secret table"
		elseif d == nil then first = "nil"
		elseif type(d) ~= "table" then first = type(d)
		else first = "spell " .. S(d.spellId) end
		local okX, sec = false, nil
		if C_Secrets and type(C_Secrets.ShouldUnitAuraIndexBeSecret) == "function" then
			okX, sec = pcall(C_Secrets.ShouldUnitAuraIndexBeSecret, u, 1, "HELPFUL")
		end
		local ms = "none"
		if type(A.GetUnitAuraBySpellID) == "function" then
			for _, id in ipairs(ORDER) do
				local okB, b = pcall(A.GetUnitAuraBySpellID, u, id)
				if not okB then ms = "ERROR " .. Short(b); break end
				if issecretvalue(b) then ms = id .. " <secret table>"; break end
				if b ~= nil then ms = id .. " points[1]=" .. S((PointsFrom(b))); break end
			end
		end
		local okAb, ab = pcall(UnitGetTotalAbsorbs, u)
		local line = ("%s exists %s name %s | aura #1 %s | index 1 secret %s | Mana Shield %s | absorbs %s"):format(u,
			okE and S(ex) or "ERR", okN and S(nm) or "ERR", first, okX and S(sec) or "ERR", ms, okAb and S(ab) or "ERR")
		if i <= 8 then log("%s", line) else qlog("%s", line) end
	end
	BuildRaidRow(units)
	Refresh("raid")
	log("raid row above the panel: a Mana Shield icon + time per member, their total absorbs (secret, drawn). Mages: cast Mana Shield.")
end

---------------------------------------------------------------------------- always on: your own Mana Shield casts
P.castFrame = CreateFrame("Frame")
pcall(P.castFrame.RegisterUnitEvent, P.castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
P.castFrame:SetScript("OnEvent", function(_, _, _, _, spellID)
	local ok, err = pcall(OnCast, spellID)
	if not ok then Bug("OnCast", err) end
end)

SLASH_FDMSPROBE1 = "/fdms"
SlashCmdList["FDMSPROBE"] = function(msg)
	msg = strtrim(msg or ""):lower()
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	local ok, err = pcall(function()
		if cmd == "hide" then
			StopWatch("hide")
			if P.panel then P.panel:Hide() end
			if P.upd then P.upd:SetScript("OnUpdate", nil) end
			if P.tip then P.tip:Hide() end
			if P.cont then pcall(P.cont.SetUnit, P.cont, nil) end
			for _, r in ipairs(P.raid) do if r.c then pcall(r.c.SetUnit, r.c, nil) end end
			P.raid = {}
			if P.raidHost then P.raidHost:Hide() end
		elseif cmd == "watch" then
			BuildPanel()
			GuessFull()
			Watch(math.floor(tonumber(arg) or 600))
			Refresh("watch")
		elseif cmd == "raid" then
			RaidReport()
		elseif cmd == "fct" then
			if InCombatLockdown() then log("/fdms fct only out of combat"); return end
			for _, cv in ipairs({ "enableFloatingCombatText", "floatingCombatTextDamageReduction_v2", "floatingCombatTextAuras_v2" }) do
				local okS, r = false, "C_CVar.SetCVar missing"
				if C_CVar and type(C_CVar.SetCVar) == "function" then okS, r = pcall(C_CVar.SetCVar, cv, "1") end
				log("SetCVar %s 1 -> %s (now %s)", cv, okS and S(r) or ("ERROR " .. Short(r)), CVar(cv))
			end
		else
			Report()
		end
	end)
	if not ok then Bug("/fdms " .. msg, err) end
end
