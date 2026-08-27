-- SkuQuestTarget/Core.lua -- foundation file: creates the addon object and
-- the primitives every other file needs. Loaded right after Log.lua.
--
-- Optional companion addon for Sku (screen-reader accessibility addon).
-- Adds ONE dedicated keybind: press it, and whichever creature relevant to
-- your CURRENT quest log's kill/interact objectives happens to be nearby
-- (already rendered as a nameplate) gets targeted via /targetexact,
-- exactly as if you'd typed "/target <name>" yourself -- without needing
-- to see the mob to pick it out among everything else around you.
--
-- Built on the SAME SkuQuest/SkuDB foundation as SkuQuestNearby (a
-- sibling addon, same author): SkuQuest:GetQuestTargetIds(questID, aList)
-- resolves a quest's own objectives sub-table into (targetIds, targetType)
-- -- reused as-is here too, filtered to targetType=="creature" only (v1
-- scope: object/item objectives aren't meaningfully "/target"-able the same
-- way, and are left for a future addon rather than guessed at). Creature
-- names come from Sku's own bundled SkuDB.NpcData.Names[locale][npcId]
-- table (the same source Sku's own quest-detail menu uses to show a
-- creature's name).
--
-- Deliberately narrow scope: this addon does NOT track threat, does not
-- auto-attack, does not cast anything, does not select based on health/
-- combat-log state -- it only ever does what a sighted player could already
-- do by clicking a visible mob's name: point the game at a specific unit
-- that is ALREADY there. Nothing here decides who to fight or when.
local ADDON_NAME, NS = ...
local Log = NS.Log

Log("Core.lua executing. Sku=%s SkuCore=%s SkuQuest=%s SkuDB=%s SkuNav=%s",
	tostring(Sku ~= nil), tostring(SkuCore ~= nil), tostring(SkuQuest ~= nil), tostring(SkuDB ~= nil), tostring(SkuNav ~= nil))

if not Sku or not SkuCore or not SkuQuest or not SkuDB or not SkuNav then
	-- Sku is a hard TOC dependency and SkuQuest/SkuDB/SkuNav are Sku's own
	-- always-loaded modules, so this should be unreachable -- bail cleanly
	-- instead of erroring if load order is ever wrong. NS.SkuMissing is
	-- checked at the top of every other file (a bare `return` here only
	-- aborts THIS file, not the whole addon, since the code is split across
	-- several separately-loaded chunks).
	Log("ABORT: Sku/SkuCore/SkuQuest/SkuDB/SkuNav missing at file-load time -- addon inert this session.")
	NS.SkuMissing = true
	return
end

-- Labels for the dedicated keybind (Bindings.xml) -- read by Blizzard's own
-- Key Bindings panel to show a category header and binding name instead of
-- the raw internal name. Set unconditionally, before anything else, since
-- Blizzard's UI expects these globals to simply exist. Same one-shot-at-
-- load characteristic as every other addon in this family's own binding
-- labels (resolved in the client's language at first load, not live-
-- relocalized if the language changes mid-session).
local function tBindLabel(aDe, aEn, aFr)
	return (Sku and Sku.deEn and Sku.deEn(aDe, aEn, aFr)) or aFr
end
BINDING_HEADER_SKUQUESTTARGET = tBindLabel("Sku - Questziel anvisieren", "Sku - Quest target", "Sku - Cible de quête")
BINDING_NAME_SKUQUESTTARGET_FIRE = tBindLabel(
	"Naechstes Questziel anvisieren", "Target nearest quest mob", "Cibler le monstre de quête le plus proche")

---------------------------------------------------------------------------------------------------------------------------------------
local SkuQuestTarget = LibStub("AceAddon-3.0"):NewAddon("SkuQuestTarget", "AceConsole-3.0")
Log("AceAddon object created.")

-- [Same root-cause fix as every other addon in this family] AceAddon:NewAddon
-- does not expose the created object as a global -- publish it explicitly so
-- Bindings.xml and any future cross-file reference via _G both work.
_G.SkuQuestTarget = SkuQuestTarget
NS.SkuQuestTarget = SkuQuestTarget

-- Shows up as "Cible de quête" in Sku's Features on/off menu (Local -> ... ->
-- Features, same list MinimapScanner/Pont Bagnon/Quêtes proches register into).
SkuCore:RegisterToggleableAddon("SkuQuestTarget", function()
	return Sku.deEn and Sku.deEn("Questziel anvisieren", "Quest target", "Cible de quête") or "Cible de quête"
end)
Log("Registered as toggleable addon with SkuCore.")

---------------------------------------------------------------------------------------------------------------------------------------
-- Speaks through the SAME voice path Sku itself uses.
local function Announce(aText)
	if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
		SkuOptions.Voice:OutputStringBTtts(aText, true, true, 0.2)
	else
		print(aText)
	end
end
NS.Announce = Announce
