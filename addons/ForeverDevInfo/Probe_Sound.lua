--[[ Probe_Sound.lua - /fdsnd: how do the game's own aura sounds (C_UnitAuras.AddAuraSound) behave on party and
     raid tokens? EverAuras' sounds for group triggers (raid plan, stage 3) depend on the answers.

     Written for the ForeverDevInfo dev addon (Probe_Sound.lua in both TOCs, after Probe_ManaShield.lua; copy the
     addon folder into the client's Interface\AddOns\ForeverDevInfo while the client is closed). It logs into
     ForeverDevInfoDB.sndProbe (max 800 lines), keeps its counters in ForeverDevInfoDB.sndProbeStats and the
     sounds it registered in ForeverDevInfoDB.sndProbeReg: should the game keep aura sounds over a /reload (it
     seemed to on 2026-09-30; on 2026-10-22 it cleared them), their ids must outlive the UI to be removed again.
     The sound files are EverAuras' own (Interface\AddOns\EverAuras\Media\Sounds), so EverAuras must be installed.

     Every call has the engine's shape (ForeverEngineAura.lua, ApplySounds): one registration per (trigger,
     token, spell id) and one info table reused for the whole run,
         C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added | .Removed,
             { unitToken = u, spellID = id, soundFileName = file, outputChannel = "Master", throttleSeconds = 0.5 })
     Each token gets sounds of its own, so you can hear which registration played: a spoken WORD when the aura
     is ADDED, a NOISE when it is REMOVED. None of them is used by the raid test exports (horns, animals, bells):

         token   added     removed                token   added     removed
         player  Focus     Applause               raid1   Star      Shotgun
         party1  Left      CartoonVoiceBaritone   raid2   Circle    BananaPeelSlip
         party2  Right     SynthChord             raid3   Diamond   HeartbeatSingle
         party3  Next      CartoonWalking         raid4   Triangle  SquishFart
         party4  Switch    BoxingArenaSound       raid5   Moon      ErrorBeep
         party   Stack     BatmanPunch            raid    Boss      Blast
         group   Spread    AcousticGuitar         (/fdsnd same: SharpPunch on every token)

     Questions (raid plan, stage 3 "Probes first"):
       G5   can sounds be registered in combat and inside an instance, also on "raid2"? (the answer or the error
            of each call, ADDON_ACTION_BLOCKED / _FORBIDDEN fired during it, the restriction states)
       G6   one person under two tokens (player and your own raidN): one sound or two?
       G7   throttle: per registration, or shared by every registration of the same sound?
       G8   does a death fire Removed?
       G9   do "party", "raid" and "group" work as tokens?
       G10  does a registration follow the token, or the player the token named when it was made?
       and: do registrations survive a /reload; does RemoveAuraSound by id work (in combat, on ids from before a
       /reload); does a display that EverAuras unloaded still play its game sound (the load-state question)?

       /fdsnd                  the current step and what to do (the step is kept over /reload)
       /fdsnd next | back | step <n> | steps
       /fdsnd reg [spellID] [tokens]   a word on Added and a noise on Removed for each token (default spell 1245,
                               Power Word: Fortitude r3; default tokens: all 13 of the legend; "me" = your raidN)
       /fdsnd same [spellID] [throttle] [tokens]   one sound (SharpPunch) on Added for every token, throttle 5 s;
                               default tokens: raid1-5 in a raid, player + party1-4 otherwise
       /fdsnd clear            removes every sound the probe registered (RemoveAuraSound by id)
       /fdsnd who              who has which token now, and which sounds each person should give
       /fdsnd legend           the legend in chat
       /fdsnd ea [display]     load state and sounds of an EverAuras display (default "EA RU Fort raid1")
       /fdsnd arm              on / off (kept over /reload): at each moment a fight starts or ends (UNIT_FLAGS on
                               you as your combat flag changes, PLAYER_REGEN_DISABLED / _ENABLED, the Combat
                               restriction's state changes) one throwaway registration that never plays, removed at
                               once; the chat says whether the game took it, with the lockdown, the Combat
                               restriction and whether auras are secret at that moment (EverAuras' load scan runs there)
       /fdsnd note <text>      what you heard, into the log
       /fdsnd log              a summary of the counters;  /fdsnd reset  empties the log and the counters

     While sounds are registered and auras are readable (out of combat), each UNIT_AURA on a watched token reads
     the registered spells there, and one chat line says who gained or lost the aura and which sounds should play
     now; after a roster change it also names the sounds a registration bound to the player would give. In
     combat the aura getters are closed, so the probe only counts UNIT_AURA events and compares after the fight.
     Nothing here compares, tests, formats or does arithmetic on a possibly secret value: every API result passes
     issecretvalue first, and every call sits in a pcall.
]]

local ADDON = ...
local P = {
	reg = {},          -- the probe's live registrations: { id, u = token, s = spell, trig, f = file, m = mode }
	snap = {},         -- spell -> the roster when it was registered (token -> { n = name, g = guid })
	byTok = {}, watch = {}, spells = {}, auraN = {},
	has = {},          -- GUID (or "token <u>") -> spell -> true/false: what the person had at the last plain look
	pend = {}, pendOrder = {}, errSeen = {}, bugSeen = {}, blockSeen = {},
}
local Rebuild, Check, Flush                -- defined further down

local PREFIX = "|cff66ccffsnd|r "
local CAP = 800
local SND = "Interface\\AddOns\\EverAuras\\Media\\Sounds\\"
local SPELL = 1245            -- Power Word: Fortitude r3 (the raid test's priest)
local THROTTLE = 0.5          -- the engine's value
local SAME_THROTTLE = 5       -- /fdsnd same: the longest the game allows, so three buffs by hand fit into it
local SAME = "SharpPunch"
local LOAD_DISPLAY = "EA RU Fort raid1"

local TOKENS = { "player", "party1", "party2", "party3", "party4", "raid1", "raid2", "raid3", "raid4", "raid5",
	"party", "raid", "group" }
local GROUPTOK = { party = true, raid = true, group = true }    -- not unit tokens: G9 asks whether the game takes them
local ADDED = {
	player = "Focus", party1 = "Left", party2 = "Right", party3 = "Next", party4 = "Switch",
	raid1 = "Star", raid2 = "Circle", raid3 = "Diamond", raid4 = "Triangle", raid5 = "Moon",   -- raid marker order
	party = "Stack", raid = "Boss", group = "Spread",
}
local REMOVED = {
	player = "Applause", party1 = "CartoonVoiceBaritone", party2 = "SynthChord", party3 = "CartoonWalking",
	party4 = "BoxingArenaSound", raid1 = "Shotgun", raid2 = "BananaPeelSlip", raid3 = "HeartbeatSingle",
	raid4 = "SquishFart", raid5 = "ErrorBeep", party = "BatmanPunch", raid = "Blast", group = "AcousticGuitar",
}
local VALID = {}
for _, u in ipairs(TOKENS) do VALID[u] = true end

local E = Enum or {}
local RT = E.AddOnRestrictionType or {}
local R_COMBAT, R_ENC, R_MAP = RT.Combat or 0, RT.Encounter or 1, RT.Map or 4
local RT_NAME = { [0] = "Combat", [1] = "Encounter", [2] = "ChallengeMode", [3] = "PvPMatch", [4] = "Map", [5] = "Chat" }
local RS_NAME = { [0] = "Inactive", [1] = "Activating", [2] = "Active" }
for k, v in pairs(RT) do RT_NAME[v] = k end
for k, v in pairs(E.AddOnRestrictionState or {}) do RS_NAME[v] = k end

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

local function Plain(v)                -- v, or nil when it is secret: only plain values reach a test
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

local function State() return InCombatLockdown() and "combat" or "ooc" end

local function DB()
	ForeverDevInfoDB = ForeverDevInfoDB or {}
	return ForeverDevInfoDB
end

local function Stats()                 -- the counters /fdsnd log sums up (kept over /reload)
	local db = DB()
	local st = db.sndProbeStats
	if type(st) ~= "table" then st = {}; db.sndProbeStats = st end
	for _, k in ipairs({ "reg", "tok", "rem", "reload", "aura", "notes" }) do
		if type(st[k]) ~= "table" then st[k] = {} end
	end
	return st
end

local function push(line, loud)
	local db = DB()
	db.sndProbe = db.sndProbe or {}
	local l = db.sndProbe
	l[#l + 1] = date("%H:%M:%S ") .. line
	while #l > CAP do table.remove(l, 1) end
	if loud then print(PREFIX .. line) end
end
local function log(fmt, ...) push(select("#", ...) > 0 and fmt:format(...) or fmt, true) end    -- chat + log
local function qlog(fmt, ...) push(select("#", ...) > 0 and fmt:format(...) or fmt, false) end  -- log only
local function say(line) print(PREFIX .. line) end                                               -- chat only

local function Bug(where, err)         -- an error in the probe itself (not a refused API call)
	if P.bugSeen[where] then return end
	P.bugSeen[where] = true
	log("PROBE BUG in %s: %s", where, S(err))
end

local function Later(sec, where, fn)   -- C_Timer.After with the probe's error guard
	C_Timer.After(sec, function()
		local ok, err = pcall(fn)
		if not ok then Bug(where, err) end
	end)
end

local function RState(rtype)
	local fn = C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState
	if type(fn) ~= "function" then return "?" end
	local ok, s = pcall(fn, rtype)
	if not ok then return "ERR" end
	if issecretvalue(s) then return "<secret>" end
	return RS_NAME[s] or S(s)
end

local function Where()                 -- "world" or "instance <type> <name>", and the counters' key
	local ok, inInst, kind = pcall(IsInInstance)
	if not ok then return "where: ERROR " .. Short(inInst), "where?" end
	if issecretvalue(inInst) or issecretvalue(kind) then return "instance <secret>", "instance" end
	if not inInst then return "world", "world" end
	local okN, name = pcall(GetInstanceInfo)
	return ("instance %s %s"):format(S(kind), okN and S(name) or "?"), "instance"
end

local function Ctx()                   -- the circumstances of a call: text, and the counters' key
	local where, wkey = Where()
	local st = State()
	return ("%s, %s, restrictions Combat %s Encounter %s Map %s"):format(st, where, RState(R_COMBAT), RState(R_ENC),
		RState(R_MAP)), st .. "/" .. wkey
end

local function AurasOpen()             -- true only when aura queries plainly answer right now (so "no aura" means none)
	if InCombatLockdown() then return false end
	local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(fn) ~= "function" then return true end
	local ok, v = pcall(fn)
	return ok and not issecretvalue(v) and v == false
end

local function SpellName(id)
	local fn = C_Spell and C_Spell.GetSpellName
	if type(fn) == "function" then
		local ok, n = pcall(fn, id)
		if ok and not issecretvalue(n) and n ~= nil then return S(n) end
	end
	return "spell " .. S(id)
end

local function CountLine(tbl)
	local keys, out = {}, {}
	for k in pairs(tbl) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do out[#out + 1] = k .. " x" .. tbl[k] end
	return table.concat(out, ", ")
end

---------------------------------------------------------------------------- who is who
local function Who(u)                  -- plain name and GUID of a unit token, or nil when it names nobody
	if GROUPTOK[u] then return nil end
	local okE, ex = pcall(UnitExists, u)
	if not okE or Plain(ex) ~= true then return nil end
	local okN, n = pcall(UnitName, u)
	local okG, g = pcall(UnitGUID, u)
	n = okN and Plain(n) or nil
	g = okG and Plain(g) or nil
	return n or "?", g
end

local function Roster()                -- token -> { n = name, g = guid } for every real token of the legend
	local r = {}
	for _, u in ipairs(TOKENS) do
		local n, g = Who(u)
		if n then r[u] = { n = n, g = g } end
	end
	return r
end

local function InRaid()
	local ok, v = pcall(IsInRaid)
	return ok and Plain(v) == true
end

local function MyRaidToken()           -- your own raidN, by GUID (UnitIsUnit may turn secret in instances)
	if not InRaid() then return nil end
	local okP, me = pcall(UnitGUID, "player")
	me = okP and Plain(me) or nil
	if not me then return nil end
	for i = 1, 40 do
		local ok, g = pcall(UnitGUID, "raid" .. i)
		g = ok and Plain(g) or nil
		if g and g == me then return "raid" .. i end
	end
	return nil
end

local function TokensOf(roster, g)     -- the real tokens that named this GUID in a roster, in legend order
	local out = {}
	if not (roster and g) then return out end
	for _, u in ipairs(TOKENS) do
		local e = roster[u]
		if e and e.g == g then out[#out + 1] = u end
	end
	return out
end

local function Sounds(tokens, trig)    -- the files the probe registered on these tokens for one trigger
	local out = {}
	for _, u in ipairs(tokens) do
		local t = P.byTok[u]
		for _, f in ipairs(t and t[trig] or {}) do out[#out + 1] = f end
	end
	return out
end

local function GroupSounds(trig)       -- the group tokens' files: they play only if the game takes those tokens
	local out = {}
	for _, u in ipairs({ "party", "raid", "group" }) do
		local t = P.byTok[u]
		for _, f in ipairs(t and t[trig] or {}) do out[#out + 1] = f end
	end
	return out
end

local function Join(list) return #list > 0 and table.concat(list, " + ") or "silence" end

local function FirstSnap()             -- the roster of the oldest registration (for /fdsnd who)
	local r = P.reg[1]
	return r and P.snap[r.s] or nil
end

-- One person's sounds for a trigger: what the tokens they have now give, and (when it differs) what the tokens
-- they had when the spell was registered give - that is what a registration bound to the player would play.
local function PersonSounds(roster, snap, e, u, trig)
	local now = (e and e.g) and TokensOf(roster, e.g) or { u }
	local a = Join(Sounds(now, trig))
	local b
	if snap and e and e.g then
		local was = TokensOf(snap, e.g)
		local bj = Join(Sounds(was, trig))
		if bj ~= a then b = bj end
	end
	return a, b, now
end

---------------------------------------------------------------------------- legend, who
local function Legend(tokens)
	local a, r = {}, {}
	for _, u in ipairs(tokens or TOKENS) do
		a[#a + 1] = u .. " " .. ADDED[u]
		r[#r + 1] = u .. " " .. REMOVED[u]
	end
	say("ADDED = a word: " .. table.concat(a, ", "))
	say("REMOVED = a noise: " .. table.concat(r, ", "))
end

local function WhoLines()
	local roster = Roster()
	local snap = FirstSnap()
	local seen, n = {}, 0
	for _, u in ipairs(TOKENS) do
		local e = roster[u]
		local key = e and (e.g or u)
		if e and not seen[key] then
			seen[key] = true
			n = n + 1
			local a, b, now = PersonSounds(roster, snap, e, u, "Added")
			local line = ("%s: %s"):format(e.n, table.concat(now, ", "))
			if #P.reg > 0 then
				line = line .. " -> added: " .. a
				if b then line = line .. " | if bound to the player (tokens at /fdsnd reg: "
					.. table.concat(TokensOf(snap, e.g), ", ") .. "): " .. b end
			end
			log("%s", line)
		end
	end
	if n == 0 then log("who: no unit token of the legend names anybody") end
	local gs = GroupSounds("Added")
	if #gs > 0 then say("(the group tokens' words " .. table.concat(gs, "/") .. " come on top if the game takes them)") end
end

---------------------------------------------------------------------------- registry
P.ev = CreateFrame("Frame")

local function SaveReg()
	if #P.reg == 0 then DB().sndProbeReg = nil; return end
	local hi = 0
	for _, r in ipairs(P.reg) do if r.id > hi then hi = r.id end end
	DB().sndProbeReg = { list = P.reg, max = hi, snap = P.snap, at = date("%Y-%m-%d %H:%M:%S") }
end

Rebuild = function()                   -- the per-token sound lists, the watched tokens and spells, UNIT_AURA on or off
	P.byTok, P.watch, P.spells = {}, {}, {}
	for _, r in ipairs(P.reg) do
		local t = P.byTok[r.u]
		if not t then t = { Added = {}, Removed = {} }; P.byTok[r.u] = t end
		local list = t[r.trig]
		if list then
			local dup = false
			for _, f in ipairs(list) do if f == r.f then dup = true end end
			if not dup then list[#list + 1] = r.f end
		end
		if not GROUPTOK[r.u] then P.watch[r.u] = true end
		P.spells[r.s] = true
	end
	if #P.reg > 0 then pcall(P.ev.RegisterEvent, P.ev, "UNIT_AURA")
	else pcall(P.ev.UnregisterEvent, P.ev, "UNIT_AURA") end
end

local function Baseline()              -- what the watched tokens have now, without reporting it
	if not AurasOpen() then return end
	for u in pairs(P.watch) do Check(u, nil, true) end
end

local function Register(mode, spell, tokens, throttle)
	local A = C_UnitAuras
	local TRIG = E.UnitAuraSoundTrigger
	if not (A and type(A.AddAuraSound) == "function" and TRIG) then
		log("C_UnitAuras.AddAuraSound or Enum.UnitAuraSoundTrigger is missing"); return
	end
	for _, r in ipairs(P.reg) do
		if r.s == spell then log("%s (%d) is registered already - /fdsnd clear first", SpellName(spell), spell); return end
	end
	local ctx, key = Ctx()
	local st = Stats()
	local rs = st.reg[key] or { ok = 0, fail = 0 }
	st.reg[key] = rs
	local trigs = mode == "same" and { "Added" } or { "Added", "Removed" }
	-- one table for the whole run, as the engine does (the game copies what it needs)
	local info = { spellID = spell, outputChannel = "Master", throttleSeconds = throttle }
	local okN, failN, lo, hi, fails, groupRes = 0, 0, nil, nil, {}, {}
	local t0 = debugprofilestop()
	for _, u in ipairs(tokens) do
		local per = {}
		for _, trig in ipairs(trigs) do
			local file = mode == "same" and SAME or (trig == "Added" and ADDED[u] or REMOVED[u])
			info.unitToken, info.soundFileName = u, SND .. file .. ".ogg"
			P.calling = ("AddAuraSound %s %s (%s)"):format(u, trig, State())
			local ok, sid = pcall(A.AddAuraSound, TRIG[trig], info)
			P.lastCall, P.lastCallAt, P.calling = P.calling, GetTime(), nil
			local res, got = nil, false
			if not ok then res = "ERROR " .. Short(sid)
			elseif issecretvalue(sid) then res = "<secret>"
			elseif type(sid) == "number" then
				res, got = "id " .. sid, true
				P.reg[#P.reg + 1] = { id = sid, u = u, s = spell, trig = trig, f = file, m = mode }
				if lo == nil or sid < lo then lo = sid end
				if hi == nil or sid > hi then hi = sid end
			else res = S(sid) end
			if got then okN = okN + 1
			else failN = failN + 1; fails[#fails + 1] = u .. " " .. trig .. " -> " .. res end
			per[#per + 1] = trig .. " " .. res
			local tk = st.tok[u] or {}
			st.tok[u] = tk
			tk[key] = res                  -- the last answer per circumstance
			if GROUPTOK[u] and trig == "Added" then groupRes[#groupRes + 1] = u .. " -> " .. res end
		end
		qlog("  %s: %s", u, table.concat(per, ", "))
	end
	local ms = debugprofilestop() - t0
	rs.ok, rs.fail = rs.ok + okN, rs.fail + failN
	if failN > 0 and not rs.firstErr then rs.firstErr = fails[1] end
	if okN > 0 then P.snap[spell] = Roster() end
	SaveReg()
	Rebuild()
	Baseline()
	log("%s %s (%d), throttle %s s: %d of %d registered%s in %.1f ms | %s", mode, SpellName(spell), spell, S(throttle),
		okN, okN + failN, lo and (" (ids %d-%d)"):format(lo, hi) or "", ms, ctx)
	if failN > 0 then
		local shown = {}
		for i = 1, math.min(#fails, 6) do shown[i] = fails[i] end
		log("not registered: %s%s", table.concat(shown, ", "), #fails > 6 and (" (+%d more in the log)"):format(#fails - 6) or "")
	end
	if #groupRes > 0 then log("G9 group tokens: %s", table.concat(groupRes, ", ")) end
	if okN == 0 then return end
	if mode == "same" then
		say(("every token: %s when the aura is ADDED, throttle %s s. Buff three people within %s s and count the punches.")
			:format(SAME, S(throttle), S(throttle)))
	else
		Legend(tokens)
	end
	WhoLines()
end

local function Clear()
	if #P.reg == 0 then log("clear: the probe has no sounds registered"); return end
	local A = C_UnitAuras
	if not (A and type(A.RemoveAuraSound) == "function") then log("C_UnitAuras.RemoveAuraSound is missing"); return end
	local ctx, key = Ctx()
	local st = Stats()
	local rm = st.rem[key] or { ok = 0, err = 0 }
	st.rem[key] = rm
	local okN, errN, first = 0, 0, nil
	for _, r in ipairs(P.reg) do
		P.calling = ("RemoveAuraSound %s %s (%s)"):format(r.u, r.trig, State())
		local ok, e = pcall(A.RemoveAuraSound, r.id)
		P.lastCall, P.lastCallAt, P.calling = P.calling, GetTime(), nil
		if ok then okN = okN + 1 else errN = errN + 1; first = first or Short(e) end
	end
	-- an id the game no longer has, once more: does it mind? (the engine's ClearSounds pcalls it anyway)
	local id1 = P.reg[1].id
	local ok2, e2 = pcall(A.RemoveAuraSound, id1)
	rm.ok, rm.err = rm.ok + okN, rm.err + errN
	rm.again = ok2 and "ok" or ("ERROR " .. Short(e2))
	log("clear: RemoveAuraSound ok for %d of %d%s; id %d a second time -> %s | %s", okN, #P.reg,
		first and (", first error: " .. first) or "", id1, rm.again, ctx)
	say("Buff someone now: silence = removing by id works.")
	P.reg, P.snap, P.has = {}, {}, {}
	SaveReg()
	Rebuild()
end

---------------------------------------------------------------------------- watching the auras
local function Has(u, spell)           -- true / false, or nil when the game does not say plainly
	local fn = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
	if type(fn) ~= "function" then return nil end
	-- the getter also answers nil for a member it cannot see (another map): that is not "the aura is gone"
	local okV, vis = pcall(UnitIsVisible, u)
	if okV and Plain(vis) == false then return nil end
	local ok, d = pcall(fn, u, spell)
	if not ok then
		local key = "aura/" .. State()
		if not P.errSeen[key] then P.errSeen[key] = true; qlog("GetUnitAuraBySpellID(%s) -> ERROR %s", u, Short(d)) end
		return nil
	end
	if issecretvalue(d) then return nil end
	return d ~= nil
end

local function Queue(u, spell, added, tag)
	local key = spell .. (added and "+" or "-") .. tag
	local q = P.pend[key]
	if not q then
		q = { spell = spell, added = added, tag = tag, toks = {} }
		P.pend[key] = q
		P.pendOrder[#P.pendOrder + 1] = key
	end
	q.toks[#q.toks + 1] = u
	if not P.flushing then
		P.flushing = true
		Later(0.3, "flush", Flush)     -- player and raidN of one person arrive as separate events: one line for both
	end
end

-- Read the registered spells on one token; a change is queued for the chat. What a person has is kept per
-- GUID, not per token: tokens move to other people when the roster changes, and one person has several tokens.
Check = function(u, tag, silent)
	local _, g = Who(u)
	local key = g or ("token " .. u)   -- no plain GUID (nobody there, or secret): by token
	local h = P.has[key]
	if not h then                      -- first look at this person: a baseline, no report
		h = {}
		P.has[key] = h
		silent = true
	end
	for spell in pairs(P.spells) do
		local v = Has(u, spell)
		if v ~= nil then
			if not silent and h[spell] ~= nil and h[spell] ~= v then Queue(u, spell, v, tag or "") end
			h[spell] = v
		end
	end
end

Flush = function()
	P.flushing = false
	local st = Stats()
	local roster = Roster()
	for _, key in ipairs(P.pendOrder) do
		local q = P.pend[key]
		local trig = q.added and "Added" or "Removed"
		local snap = P.snap[q.spell]
		local people, seen, alt = {}, {}, false
		local sounds, bound = {}, {}
		for _, u in ipairs(q.toks) do
			local e = roster[u]
			local pk = e and (e.g or u) or u
			if not seen[pk] then
				seen[pk] = true
				local who = e and e.n or u
				local a = st.aura[who] or {}
				st.aura[who] = a
				a[trig] = (a[trig] or 0) + 1
				local s, b, now = PersonSounds(roster, snap, e, u, trig)
				local okD, dead = pcall(UnitIsDeadOrGhost, u)
				people[#people + 1] = ("%s (%s)%s"):format(e and e.n or u, table.concat(now, ", "),
					(okD and Plain(dead) == true) and " DEAD" or "")
				sounds[#sounds + 1] = s
				bound[#bound + 1] = b or s
				if b then alt = true end
			end
		end
		local line = ("%s%s %s on %s -> %s"):format(q.tag, SpellName(q.spell), q.added and "ADDED" or "REMOVED",
			table.concat(people, ", "), table.concat(sounds, ", "))
		if alt then line = line .. " | if bound to the player: " .. table.concat(bound, ", ") end
		local gs = GroupSounds(trig)
		if #gs > 0 then line = line .. " (+ " .. table.concat(gs, "/") .. " if the group tokens work)" end
		log("%s", line)
	end
	P.pend, P.pendOrder = {}, {}
end

local function AfterCombat()
	if next(P.auraN) then qlog("combat: UNIT_AURA on watched tokens %s (aura contents closed)", CountLine(P.auraN)) end
	P.auraN = {}
	if #P.reg == 0 then return end
	if not AurasOpen() then qlog("after combat: auras still closed, no comparison"); return end
	for u in pairs(P.watch) do Check(u, "after combat: ") end
end

---------------------------------------------------------------------------- roster changes, reload
local function RosterChanged()
	local now = Roster()
	local old = P.lastRoster or {}
	local ch = {}
	for _, u in ipairs(TOKENS) do
		local a, b = old[u], now[u]
		local ka, kb = a and (a.g or a.n), b and (b.g or b.n)
		if ka ~= kb then ch[#ch + 1] = ("%s %s->%s"):format(u, a and a.n or "-", b and b.n or "-") end
	end
	P.lastRoster = now
	if #ch == 0 then return end
	local st = Stats()
	st.roster = (st.roster or 0) + 1
	if #P.reg > 0 then
		log("roster: %s (%s) - /fdsnd who: the sounds each person should give now", table.concat(ch, ", "), State())
	else
		qlog("roster: %s", table.concat(ch, ", "))
	end
end

-- The probe's sounds after this /reload (or login). One throwaway registration reads the game's sound id
-- counter, which only tells whether the old NUMBERS can be someone else's now: past the old ids = the counter
-- went on, so they are nobody else's and the probe keeps them (/fdsnd clear removes them; removing an id the game
-- already cleared does no harm); below = the counter started again, so they may be other addons' new sounds and
-- are forgotten, not removed. Whether the game kept the sounds themselves no counter tells (on 2026-10-22 it went
-- on, and the game had cleared them all the same): only listening does, so the chat line asks for that.
-- Read as the probe's own addon loads (ADDON_LOADED, before any addon's displays register sounds at login:
-- EverAuras' would push the counter past the old ids after a fresh start too), else at PLAYER_ENTERING_WORLD.
local function SavedReg()
	local saved = DB().sndProbeReg
	if type(saved) ~= "table" or type(saved.list) ~= "table" or #saved.list == 0 or type(saved.max) ~= "number" then return nil end
	return saved
end

local function ReadCounter(spell)
	local A = C_UnitAuras
	local TRIG = E.UnitAuraSoundTrigger
	if not (A and type(A.AddAuraSound) == "function" and TRIG) then return nil, "no AddAuraSound" end
	-- "stacks increased" on a buff that does not stack: it never plays, and it is removed at once anyway
	local ok, sid = pcall(A.AddAuraSound, TRIG.ApplicationsIncreased or 1, { unitToken = "player",
		spellID = spell, soundFileName = SND .. SAME .. ".ogg", outputChannel = "Master", throttleSeconds = THROTTLE })
	if ok and not issecretvalue(sid) and type(sid) == "number" then
		pcall(A.RemoveAuraSound, sid)
		return sid
	end
	return nil, ok and S(sid) or ("ERROR " .. Short(sid))
end

local function EarlyCounter()
	local saved = SavedReg()
	if not saved then return end
	local id, why = ReadCounter(saved.list[1].s)
	P.early = { id = id, why = why }
end

local function ReloadCheck(isLogin, isReload)
	local saved = SavedReg()
	if not saved then return end
	local how = isReload and "/reload" or (isLogin and "login" or "loading screen")
	local newId, why, when = nil, nil, "as the addon loaded"
	if P.early and P.early.id then
		newId = P.early.id
	else
		newId, why = ReadCounter(saved.list[1].s)
		when = "at the loading screen's end" .. (P.early and (" (as the addon loaded: " .. S(P.early.why) .. ")") or "")
	end
	P.early = nil
	local keepIds, verdict         -- whether the probe keeps the old IDS (to remove them), not whether the game kept the sounds
	if newId then
		keepIds = newId > saved.max
		verdict = ("the game's sound id counter %s (first new id %d %s, the probe's highest old id %d)")
			:format(keepIds and "went on" or "started again", newId, when, saved.max)
	else
		keepIds = false                -- no counter: the old numbers may be someone else's now
		verdict = ("the id counter could not be read (%s)"):format(S(why))
	end
	local st = Stats()
	st.reload[#st.reload + 1] = { at = date("%H:%M:%S"), how = how, n = #saved.list, newId = newId, max = saved.max, kept = keepIds }
	while #st.reload > 20 do table.remove(st.reload, 1) end
	local words, seen = {}, {}     -- what your own 'player' registration plays, should the game still have it
	for _, r in ipairs(saved.list) do
		if type(r) == "table" and r.u == "player" and r.trig == "Added" and type(r.f) == "string" and not seen[r.f] then
			seen[r.f] = true
			words[#words + 1] = r.f
		end
	end
	local listen = ("That does not tell whether the game kept the sounds. Listen: buff yourself: %s = kept, silence = cleared by the game.")
		:format(#words > 0 and table.concat(words, " + ") or "a word")
	if keepIds then
		P.reg, P.snap = saved.list, type(saved.snap) == "table" and saved.snap or {}
		Rebuild()
		Baseline()
		log("after the %s: %d probe sounds from %s: %s. %s The old ids are nobody else's: /fdsnd clear removes them either way.",
			how, #saved.list, S(saved.at), verdict, listen)
	else
		DB().sndProbeReg = nil
		log("after the %s: %d probe sounds from %s: %s. %s Their ids are forgotten, not removed (they may belong to other addons' new sounds now).",
			how, #saved.list, S(saved.at), verdict, listen)
	end
end

---------------------------------------------------------------------------- EverAuras load state
local function EaInfo(name)
	name = (name and name ~= "") and name or LOAD_DISPLAY
	local EA = _G.EverAuras
	local db = _G.EverAurasSaved
	local d = type(db) == "table" and type(db.displays) == "table" and db.displays[name]
	if type(d) ~= "table" then
		log("ea: no EverAuras display '%s'%s", name, EA and "" or " (EverAuras is not loaded)"); return
	end
	local loaded = "?"
	if EA and type(EA.IsAuraLoaded) == "function" then
		local ok, v = pcall(EA.IsAuraLoaded, name)
		if not ok then loaded = "ERROR " .. Short(v)
		elseif Plain(v) == true then loaded = "LOADED"
		else loaded = "NOT loaded (" .. S(v) .. ")" end
	end
	local function snd(a)
		if type(a) ~= "table" or not a.do_sound or type(a.sound) ~= "string" then return "-" end
		return (a.sound:match("([^\\]+)%.%a+$")) or a.sound
	end
	local acts = type(d.actions) == "table" and d.actions or {}
	local load = type(d.load) == "table" and d.load or {}
	local trig = type(d.triggers) == "table" and type(d.triggers[1]) == "table" and d.triggers[1].trigger or {}
	log("ea '%s': %s, Load 'Never' %s | unit %s | On Show sound %s, On Hide sound %s", name, loaded,
		load.use_never and "ticked" or "not ticked", S(trig.specificUnit or trig.unit), snd(acts.start), snd(acts.finish))
	if loaded ~= "LOADED" then
		say("Not loaded: make its sound happen (e.g. remove Fort from that unit and buff again). Its sound now = the game still plays the sound of an unloaded display.")
	end
end

---------------------------------------------------------------------------- /fdsnd arm: as a fight starts and ends
-- Can an addon still register a sound at the moments a fight starts or ends? EverAuras' load scan runs as your
-- combat flag changes (UNIT_FLAGS) and at PLAYER_REGEN_DISABLED, and it waits for the Combat restriction's end
-- before it registers. Once armed, each of those moments makes one throwaway registration ("stacks increased" on
-- player: it never plays) that is removed at once, and says whether the game took it.
local function ArmProbe(event, detail)
	local A = C_UnitAuras
	local TRIG = E.UnitAuraSoundTrigger
	if not (A and type(A.AddAuraSound) == "function" and TRIG) then return end
	local okL, lock = pcall(InCombatLockdown)
	local okS, sec = false, nil
	local fn = C_Secrets and C_Secrets.ShouldAurasBeSecret
	if type(fn) == "function" then okS, sec = pcall(fn) end
	local ctx = ("lockdown %s, Combat %s, auras secret %s"):format(okL and S(lock) or "?", RState(R_COMBAT),
		okS and S(sec) or "?")
	P.calling = ("arm %s (%s)"):format(event, State())
	local ok, sid = pcall(A.AddAuraSound, TRIG.ApplicationsIncreased or 1, { unitToken = "player", spellID = SPELL,
		soundFileName = SND .. SAME .. ".ogg", outputChannel = "Master", throttleSeconds = THROTTLE })
	P.lastCall, P.lastCallAt, P.calling = P.calling, GetTime(), nil
	local res
	if not ok then res = "ERROR " .. Short(sid)
	elseif issecretvalue(sid) then res = "<secret>"
	elseif type(sid) == "number" then
		res = "taken (id " .. sid .. ")"
		pcall(A.RemoveAuraSound, sid)
	else res = "refused (" .. S(sid) .. ")" end
	local line = ("%s%s: %s | %s"):format(event, detail or "", res, ctx)
	local st = Stats()
	st.arm = type(st.arm) == "table" and st.arm or {}
	st.arm[#st.arm + 1] = date("%H:%M:%S ") .. line
	while #st.arm > 40 do table.remove(st.arm, 1) end
	log("arm: %s", line)
end

local function ArmEvents(on)
	if on then pcall(P.ev.RegisterUnitEvent, P.ev, "UNIT_FLAGS", "player")
	else pcall(P.ev.UnregisterEvent, P.ev, "UNIT_FLAGS") end
end

local function ArmToggle()
	local db = DB()
	db.sndProbeArm = (not db.sndProbeArm) or nil
	ArmEvents(db.sndProbeArm)
	P.lastFlag = nil
	if db.sndProbeArm then
		log("arm: ON - pull a mob and let the fight end; each moment says whether a registration was taken. /fdsnd arm again turns it off.")
	else
		log("arm: off")
	end
end

---------------------------------------------------------------------------- the steps
local STEPS = {
	{ "Setup and the legend (G9)", {
		"On the priest, with Centrius and Anvelore in a party, out of combat (.gm off). Mute the other two clients or turn off their sound in the background: you should hear only this one.",
		"EverAuras' own displays play sounds on Fortitude and Renew too: for steps 1-8 select the groups EA Raid Units, EA Raid Group, EA Raid Clone and EA Raid Clone Next in /ea and tick Load: Never (it ticks it for every display in the group). Untick EA Raid Units again before step 9.",
		"/fdsnd reg - Fortitude r3 (1245) gets a WORD per token when it is ADDED and a NOISE when it is REMOVED (/fdsnd legend). A horn, an animal or a bell is one of EverAuras' displays that is still loaded.",
		"G9: the line 'G9 group tokens' says whether 'party', 'raid' and 'group' got an id. Buff a party member: Stack / Spread on top of Left / Right = that group token works.",
		"Write down what you hear with /fdsnd note <text>. Then /fdsnd next.",
	} },
	{ "One person, two tokens (G6)", {
		"Make it a raid (/run C_PartyInfo.ConvertToRaid()). /fdsnd who shows the tokens. Buff yourself: you are 'player' and %ME%.",
		"Two words (Focus + %MEWORD%) = every token plays; one word = the game plays a person only once.",
		"For a clean check: /fdsnd clear, /fdsnd reg 1245 player me (only those two), buff yourself again. Then /fdsnd clear, /fdsnd reg, /fdsnd next.",
	} },
	{ "Throttle (G7)", {
		"a) /fdsnd clear, /fdsnd same - ONE sound (SharpPunch) on every raid token, throttle 5 s. Buff three people within 5 s: 3 punches = the throttle is per registration; 1 punch = shared by all registrations of that sound.",
		"b) Optional, many at once: /fdsnd clear, .learn 21562, /fdsnd reg 21562 raid1 raid2 raid3, one Prayer of Fortitude: Star + Circle + Diamond together?",
		"Then /fdsnd clear, /fdsnd reg, /fdsnd next.",
	} },
	{ "Death (G8)", {
		"Buff raid2 (%RAID2%), target them and .die. A noise = a death fires Removed (raid2 = BananaPeelSlip, plus their party noise). The chat line says DEAD.",
		".revive and buff again. Optional: the same while the others are in combat (then the chat cannot see the aura; just listen). /fdsnd next.",
	} },
	{ "Token or player (G10)", {
		"/fdsnd who. Let %RAID2% (raid2) leave the raid and invite them again, so the raid tokens move (the chat prints the roster change). LISTEN as they leave and as they join again: a word or a noise at that moment = a token changing hands makes the game play aura sounds.",
		"/fdsnd who again: per person the sound if a registration follows the TOKEN, and after '|' the sound if it stays with the PLAYER. Buff each person: which word comes?",
		"A token nobody stood behind (3 clients are enough): let Anvelore leave the raid (a raid of 2), /fdsnd clear, /fdsnd reg 1245 raid1 raid2 raid3, invite her again (she becomes raid3) and buff her: Diamond = a registration made on an empty token works later; silence = it does not. Then /fdsnd clear, /fdsnd reg, /fdsnd next.",
	} },
	{ "Registering in combat (G5)", {
		"/fdsnd clear. Attack a mob. In combat: /fdsnd reg - the chat says per token what the game answered (also ADDON_ACTION_BLOCKED, if it fires; a window saying ForeverDevInfo was blocked: press Ignore).",
		"Still in combat, buff someone: words = registering in combat works. If it registered some: /fdsnd clear in combat and buff again: silence = removing in combat works.",
		"If 0 were registered in combat: leave combat, /fdsnd reg, pull a mob, /fdsnd clear in combat, buff someone: silence = removing in combat works (EverAuras removes sounds in combat).",
		"The start of a fight: /fdsnd arm, pull a mob, let the fight end, /fdsnd arm again. The 'arm:' lines say whether a registration was taken as your combat flag changed, at PLAYER_REGEN_DISABLED / _ENABLED and as the Combat restriction changed. /fdsnd next.",
	} },
	{ "In an instance (G5)", {
		"Port the group into a dungeon (.tele, .summon). Out of combat: /fdsnd clear, /fdsnd reg, buff someone.",
		"Pull a mob there: /fdsnd clear, /fdsnd reg in combat, buff someone. The reg line shows the Encounter/Map restriction states. /fdsnd next.",
	} },
	{ "Over a /reload (and removing by id)", {
		"Out of combat: /fdsnd clear, /fdsnd reg, then /reload. After it, the chat reads the sound id counter: that only says whether the probe keeps the old ids, not whether the game kept the sounds.",
		"Listen: buff yourself: Focus = kept, silence = cleared by the game (/fdsnd note what you heard). If kept and the probe kept the old ids: /fdsnd clear (removes them) and buff again: silence = removing by id works after a /reload. /fdsnd next.",
	} },
	{ "EverAuras load state", {
		"/fdsnd clear. Untick Load: Never on the group EA Raid Units. EA RU Fort raid1 plays BikeHorn when Fort lands on raid1: check it once. /fdsnd ea shows its load state and sounds.",
		"/ea > EA RU Fort raid1 > Load: tick 'Never', close the options, /fdsnd ea must say NOT loaded. Remove Fort from raid1 and buff again: BikeHorn = an unloaded display still plays its game sound (the bug). Untick 'Never' afterwards.",
		"Done: /fdsnd log, then /reload so the log reaches the disk.",
	} },
}

local function StepNo()
	local n = tonumber(DB().sndProbeStep) or 1
	if n < 1 then n = 1 elseif n > #STEPS then n = #STEPS end
	return n
end

local function Fill(text)
	return (text:gsub("%%(%u+%d*)%%", function(k)
		if k == "ME" then return MyRaidToken() or "your raidN" end
		if k == "MEWORD" then
			local me = MyRaidToken()
			return me and ADDED[me] or "the word of your raidN"
		end
		if k == "RAID2" then return (Who("raid2")) or "nobody yet" end
		return nil
	end))
end

local function ShowStep()
	local n = StepNo()
	local s = STEPS[n]
	say(("step %d/%d: %s"):format(n, #STEPS, s[1]))
	for _, line in ipairs(s[2]) do say("  " .. Fill(line)) end
	local spells = {}
	for spell in pairs(P.spells) do spells[#spells + 1] = SpellName(spell) .. " " .. spell end
	table.sort(spells)
	say(("now: %d probe sounds registered%s | %s | you: %s | /fdsnd next, back, steps, who, log"):format(#P.reg,
		#spells > 0 and (" (" .. table.concat(spells, ", ") .. ")") or "", InRaid() and "raid" or "no raid",
		MyRaidToken() or "player"))
end

---------------------------------------------------------------------------- /fdsnd log
local function Summary()
	local st = Stats()
	log("---- /fdsnd log (%d lines in ForeverDevInfoDB.sndProbe) | step %d/%d | now %s", #(DB().sndProbe or {}),
		StepNo(), #STEPS, (Ctx()))
	local parts = {}
	for key, rs in pairs(st.reg) do
		parts[#parts + 1] = ("%s %d ok, %d not%s"):format(key, rs.ok or 0, rs.fail or 0,
			rs.firstErr and (" (first: " .. rs.firstErr .. ")") or "")
	end
	table.sort(parts)
	log("G5 registrations by circumstance: %s", #parts > 0 and table.concat(parts, "; ") or "none yet")
	log("G5 ADDON_ACTION_BLOCKED/FORBIDDEN during the probe's calls: %d%s", st.blocked or 0,
		st.blockedLast and (" (last: " .. st.blockedLast .. ")") or "")
	for _, u in ipairs({ "player", "raid2", "party", "raid", "group" }) do
		local tk = st.tok[u]
		if tk then
			local a = {}
			for key, res in pairs(tk) do a[#a + 1] = key .. " " .. res end
			table.sort(a)
			log("%s %s: %s", GROUPTOK[u] and "G9" or "G5", u, table.concat(a, "; "))
		end
	end
	parts = {}
	for key, rm in pairs(st.rem) do
		parts[#parts + 1] = ("%s %d ok, %d errors, twice: %s"):format(key, rm.ok or 0, rm.err or 0, S(rm.again))
	end
	table.sort(parts)
	log("RemoveAuraSound: %s", #parts > 0 and table.concat(parts, "; ") or "not used yet")
	for _, r in ipairs(st.reload) do
		log("reload check %s after a %s: %d old sounds, new id %s, old max %s -> their ids %s (whether the game kept the sounds: by ear, see the notes)",
			S(r.at), S(r.how), r.n or 0, S(r.newId), S(r.max), r.kept and "kept" or "forgotten")
	end
	local arm = type(st.arm) == "table" and st.arm or {}
	for i = math.max(1, #arm - 7), #arm do log("arm %s", arm[i]) end
	parts = {}
	for u, a in pairs(st.aura) do parts[#parts + 1] = ("%s +%d/-%d"):format(u, a.Added or 0, a.Removed or 0) end
	table.sort(parts)
	log("aura changes seen out of combat, per person (added/removed): %s | roster changes: %d", #parts > 0 and table.concat(parts, ", ")
		or "none", st.roster or 0)
	for i = math.max(1, #st.notes - 4), #st.notes do log("note %s", st.notes[i]) end
	log("now registered: %d probe sounds", #P.reg)
end

---------------------------------------------------------------------------- events
local function OnEvent(event, ...)
	if event == "UNIT_AURA" then
		local u = ...
		if issecretvalue(u) or not P.watch[u] then return end
		if not AurasOpen() then
			P.auraN[u] = (P.auraN[u] or 0) + 1      -- counted; compared after the fight
			return
		end
		Check(u)
	elseif event == "GROUP_ROSTER_UPDATE" then
		if P.rosterPending then return end
		P.rosterPending = true
		Later(0.5, "roster", function() P.rosterPending = false; RosterChanged() end)
	elseif event == "PLAYER_ENTERING_WORLD" then
		local isLogin, isReload = ...
		if not P.lastRoster then P.lastRoster = Roster() end
		if not P.loaded then
			P.loaded = true
			ReloadCheck(Plain(isLogin) == true, Plain(isReload) == true)
		else
			qlog("loading screen: %s", (Ctx()))
		end
	elseif event == "ADDON_LOADED" then
		local name = ...
		if issecretvalue(name) or name ~= ADDON then return end
		pcall(P.ev.UnregisterEvent, P.ev, "ADDON_LOADED")
		EarlyCounter()
		if DB().sndProbeArm then ArmEvents(true) end
	elseif event == "UNIT_FLAGS" then
		if not DB().sndProbeArm then return end
		local okC, c = pcall(UnitAffectingCombat, "player")
		c = okC and Plain(c)
		if c == P.lastFlag then return end         -- only as your combat flag changes
		P.lastFlag = c
		ArmProbe(event, " (in combat " .. S(c) .. ")")
	elseif event == "PLAYER_REGEN_DISABLED" then
		P.auraN = {}
		if #P.reg > 0 then qlog("combat starts: %s", (Ctx())) end
		if DB().sndProbeArm then ArmProbe(event) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if #P.reg > 0 then qlog("combat ends") end
		if DB().sndProbeArm then ArmProbe(event) end
		Later(1, "after combat", AfterCombat)
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local who, fn = ...
		-- fired inside the call (the event is synchronous), or at least within 2 s of the probe's last call
		local during = P.calling or ((P.lastCallAt and GetTime() - P.lastCallAt < 2) and ("2 s after " .. P.lastCall))
		if during then
			local st = Stats()
			st.blocked = (st.blocked or 0) + 1
			st.blockedLast = ("%s %s %s during %s"):format(event, S(who), S(fn), during)
			local seenKey = event .. "/" .. State()
			if P.blockSeen[seenKey] then qlog("%s", st.blockedLast)
			else P.blockSeen[seenKey] = true; log("%s (more go to the log only)", st.blockedLast) end
		else
			qlog("%s %s %s (not during a probe call)", event, S(who), S(fn))
		end
	elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
		local rtype, state = ...
		if issecretvalue(rtype) or issecretvalue(state) then qlog("restriction <secret>"); return end
		qlog("restriction %s -> %s", RT_NAME[rtype] or S(rtype), RS_NAME[state] or S(state))
		if rtype == R_COMBAT and DB().sndProbeArm then ArmProbe(event, " Combat -> " .. (RS_NAME[state] or S(state))) end
	end
end

for _, ev in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "ADDON_RESTRICTION_STATE_CHANGED" }) do
	pcall(P.ev.RegisterEvent, P.ev, ev)
end
P.ev:SetScript("OnEvent", function(_, event, ...)
	local ok, err = pcall(OnEvent, event, ...)
	if not ok then Bug(event, err) end
end)

---------------------------------------------------------------------------- /fdsnd
local function ParseTokens(words, default)
	if #words == 0 then return default, {} end
	local out, bad = {}, {}
	for _, w in ipairs(words) do
		local u = w == "me" and MyRaidToken() or w
		if u and VALID[u] then out[#out + 1] = u else bad[#bad + 1] = w end
	end
	return out, bad
end

local function DefaultSame()           -- the active set, as the engine would use it: raid tokens in a raid
	if InRaid() then return { "raid1", "raid2", "raid3", "raid4", "raid5" } end
	return { "player", "party1", "party2", "party3", "party4" }
end

local function RegCommand(mode, rest)
	local words = {}
	for w in rest:lower():gmatch("%S+") do words[#words + 1] = w end
	local spell = tonumber(words[1])
	if spell then table.remove(words, 1) else spell = SPELL end
	local throttle = THROTTLE
	if mode == "same" then
		throttle = SAME_THROTTLE
		local t = tonumber(words[1])
		if t then throttle = t; table.remove(words, 1) end   -- not checked: the game's answer to a bad value is a result too
	end
	local tokens, bad = ParseTokens(words, mode == "same" and DefaultSame() or TOKENS)
	if #bad > 0 then
		log("unknown token(s): %s (the legend has: %s; 'me' = your raidN, only in a raid)", table.concat(bad, ", "),
			table.concat(TOKENS, " "))
		return
	end
	if #tokens == 0 then log("no tokens to register"); return end
	Register(mode, spell, tokens, throttle)
end

SLASH_FDSNDPROBE1 = "/fdsnd"
SlashCmdList["FDSNDPROBE"] = function(msg)
	msg = strtrim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	local ok, err = pcall(function()
		if cmd == "" then ShowStep()
		elseif cmd == "next" or cmd == "back" then
			DB().sndProbeStep = StepNo() + (cmd == "next" and 1 or -1)
			ShowStep()
		elseif cmd == "step" then
			DB().sndProbeStep = tonumber(rest) or StepNo()
			ShowStep()
		elseif cmd == "steps" then
			for i, s in ipairs(STEPS) do say(("%s%d. %s"):format(i == StepNo() and "> " or "  ", i, s[1])) end
		elseif cmd == "reg" or cmd == "same" then RegCommand(cmd, rest)
		elseif cmd == "clear" then Clear()
		elseif cmd == "who" then WhoLines()
		elseif cmd == "legend" then Legend()
		elseif cmd == "ea" then EaInfo(rest)
		elseif cmd == "arm" then ArmToggle()
		elseif cmd == "note" then
			local st = Stats()
			st.notes[#st.notes + 1] = ("%s step %d: %s"):format(date("%H:%M:%S"), StepNo(), rest)
			while #st.notes > 60 do table.remove(st.notes, 1) end
			log("NOTE (step %d): %s", StepNo(), rest)
		elseif cmd == "log" then Summary()
		elseif cmd == "reset" then
			DB().sndProbe, DB().sndProbeStats = {}, nil
			say("log and counters emptied (the registered sounds stay; /fdsnd clear removes them)")
		else
			-- (no "|" in chat text: "|r" would be read as a colour code)
			say("/fdsnd [next, back, step n, steps, reg [spell] [tokens], same [spell] [throttle] [tokens], clear, who, legend, ea [display], arm, note <text>, log, reset]")
		end
	end)
	if not ok then Bug("/fdsnd " .. msg, err) end
end
