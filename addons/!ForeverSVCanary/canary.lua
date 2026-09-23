--[[ !ForeverSVCanary - does the Forever client read SavedVariables back yet?

The bridge cannot answer this: it assigns every global BEFORE the client restores anything, so
it looks the same whether the client works or not. Two independent tests, no real data touched:

  1. Token   tools/ wrote ForeverSVCanaryDB (with a token) to disk while the client was closed.
             The bridge does not cover this file. Token present at ADDON_LOADED = the client read
             a SavedVariables file itself.
  2. Identity !ForeverSVBridge assigns EverAurasSaved before EverAuras loads. If the client
             restores EverAuras' own file, that global is REPLACED by a new table at
             ADDON_LOADED("EverAuras"); if not, it is still the bridge's table.

Also prints the build and interface (toc) number, because several checks depend on toc 16001.
Results are kept in ForeverSVCanaryDB.last for reading after logout.
]]
local ADDON = ...
local TOKEN = "claude-2026-09-23"
local bridgeTable = rawget(_G, "EverAurasSaved")   -- the bridge's copy (the bridge loads just before us)
local r = {}

local function yes(s) return "|cff00ff00" .. s .. "|r" end
local function no(s) return "|cffff4444" .. s .. "|r" end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		local db, cdb = rawget(_G, "ForeverSVCanaryDB"), rawget(_G, "ForeverSVCanaryCharDB")
		r.token = type(db) == "table" and db.token == TOKEN
		r.accountLogins = type(db) == "table" and db.logins or 0
		r.charLogins = type(cdb) == "table" and cdb.logins or 0
		ForeverSVCanaryDB = type(db) == "table" and db or {}
		ForeverSVCanaryDB.logins = (ForeverSVCanaryDB.logins or 0) + 1
		ForeverSVCanaryCharDB = type(cdb) == "table" and cdb or {}
		ForeverSVCanaryCharDB.logins = (ForeverSVCanaryCharDB.logins or 0) + 1
	elseif event == "ADDON_LOADED" and name == "EverAuras" then
		local now = rawget(_G, "EverAurasSaved")
		if bridgeTable == nil then
			r.identity = "inconclusive (the bridge did not load before the canary)"
		elseif now ~= bridgeTable then
			r.identity = "REPLACED: the client restored EverAuras.lua itself"
			r.identityOk = true
		else
			r.identity = "unchanged: still the bridge's copy (the client did not restore it)"
			r.identityOk = false
		end
	elseif event == "PLAYER_LOGIN" then
		local version, build, _, toc = GetBuildInfo()
		local lines = {
			("build %s (%s), interface %s%s"):format(tostring(build), tostring(version), tostring(toc),
				toc == 16001 and "" or no("  <- NOT 16001: EverAuras' Forever checks need updating")),
			"test 1, token file:   " .. (r.token and yes("READ BACK - the client reads SavedVariables")
				or no("NOT read back")),
			"test 2, EverAuras:    " .. (r.identityOk and yes(r.identity) or no(r.identity or "EverAuras not loaded")),
			("logins seen by this file: account %d, this character %d (a working client counts up)")
				:format(r.accountLogins, r.charLogins),
		}
		for _, l in ipairs(lines) do print("|cff33ff99SV canary|r " .. l) end
		ForeverSVCanaryDB.last = {
			t = date("%Y-%m-%d %H:%M:%S"), build = build, toc = toc, token = r.token and true or false,
			identity = r.identity, accountLoginsBefore = r.accountLogins, charLoginsBefore = r.charLogins,
		}
	end
end)
