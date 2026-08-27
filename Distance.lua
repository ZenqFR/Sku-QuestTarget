-- SkuQuestTarget/Distance.lua -- [2026-08-21] resolves a rough "how far is
-- this creature" distance for a quest-target npcId, using Sku's own bundled
-- spawn data + geo API (SkuNav.Geo). This is the SAME mechanism the sibling
-- addon SkuQuestNearby already proved works well for "nearby quest
-- objectives" (its own Proximity.lua: GetPlayerContext/GetSpawnDistance),
-- duplicated here rather than depended on, so this addon keeps working
-- standalone (its .toc only ever declares a dependency on Sku itself, not
-- on SkuQuestNearby being installed).
--
-- Why this exists: the macro this addon builds can only safely hold a
-- limited amount of text (see Targeting.lua's own "LIKELY REAL ROOT CAUSE"
-- comment) -- with a long quest log, the full candidate list can run past
-- that budget. Rather than an arbitrary cutoff (whatever order Lua's pairs()
-- happens to produce, which is what silently dropped "Déboiseur de la
-- KapitalRisk" from every real macro despite it being logged as "tried"),
-- candidates are now sorted CLOSEST FIRST -- the creature actually worth
-- targeting right now should never lose its spot in the macro to one the
-- player isn't even near.
local ADDON_NAME, NS = ...
if NS.SkuMissing then return end

-- Same convention as SkuQuestNearby/Proximity.lua's own UNKNOWN_DISTANCE --
-- a creature SkuDB has no usable spawn coordinates for isn't hidden, just
-- sorted behind every creature with a real, resolved distance.
local UNKNOWN_DISTANCE = 999999
NS.QUEST_TARGET_UNKNOWN_DISTANCE = UNKNOWN_DISTANCE

-- Player position + the "area id" Sku's own quest code uses to index SkuDB
-- spawn tables -- field-for-field the same shape SkuQuestNearby's own
-- GetPlayerContext produces, kept independent here on purpose (see file
-- banner above).
local function GetPlayerContext()
	local tOkMap, tRawUiMapId = pcall(SkuNav.Geo.GetBestMapForUnit, SkuNav.Geo, "player")
	if not tOkMap or not tRawUiMapId then return nil end
	local tOkArea, tAreaId = pcall(SkuNav.Geo.GetAreaIdFromUiMapId, SkuNav.Geo, tRawUiMapId)
	local tPlayerX, tPlayerY = UnitPosition("player")
	if not tOkArea or not tAreaId or not tPlayerX then return nil end
	local tOkUiMap, tUiMapId = pcall(SkuNav.Geo.GetUiMapIdFromAreaId, SkuNav.Geo, tAreaId)
	if not tOkUiMap or not tUiMapId then return nil end
	local tOkContinent, _, _, tContinentId = pcall(SkuNav.Geo.GetAreaData, SkuNav.Geo, tAreaId)
	return { areaId = tAreaId, uiMapId = tUiMapId, playerX = tPlayerX, playerY = tPlayerY, continentId = tOkContinent and tContinentId or nil }
end
NS.GetPlayerContext = GetPlayerContext

-- Closest recorded spawn distance for a creature npcId, searching every zone
-- SkuDB has a spawn recorded in, on the SAME continent as the player (a
-- different continent's coordinates aren't a real distance at all, not just
-- an imprecise one). Returns nil when unresolvable -- callers must treat
-- that as "unknown", never as "0 yards away" or "infinitely far".
local function GetNpcDistance(aCtx, aNpcId)
	if not aCtx or not aNpcId then return nil end
	local tData = SkuDB.NpcData.Data[aNpcId]
	local tSpawns = tData and tData[SkuDB.NpcData.Keys["spawns"]]
	if not tSpawns then return nil end

	local tBest
	for tAreaId, tAreaSpawns in pairs(tSpawns) do
		local tSpawnX = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][1]
		local tSpawnY = tAreaSpawns and tAreaSpawns[1] and tAreaSpawns[1][2]
		if tSpawnX and tSpawnX ~= -1 and tSpawnY and tSpawnY ~= -1 then
			local tOkArea, _, _, tAreaContinentId = pcall(SkuNav.Geo.GetAreaData, SkuNav.Geo, tAreaId)
			if tOkArea and aCtx.continentId and tAreaContinentId == aCtx.continentId then
				local tOkUiMap, tUiMapId = pcall(SkuNav.Geo.GetUiMapIdFromAreaId, SkuNav.Geo, tAreaId)
				if tOkUiMap and tUiMapId then
					local tOkPos, _, tWorldPos = pcall(C_Map.GetWorldPosFromMapPos, tUiMapId,
						CreateVector2D(tonumber(tSpawnX) / 100, tonumber(tSpawnY) / 100))
					if tOkPos and tWorldPos then
						local tX, tY = tWorldPos:GetXY()
						if tX then
							local tOkDist, tDist = pcall(SkuNav.Geo.Distance, SkuNav.Geo, aCtx.playerX, aCtx.playerY, tX, tY)
							if tOkDist and tDist and (not tBest or tDist < tBest) then tBest = tDist end
						end
					end
				end
			end
		end
	end
	return tBest
end
NS.GetNpcDistance = GetNpcDistance
