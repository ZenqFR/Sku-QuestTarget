-- SkuQuestTarget/OnEnable.lua -- final wiring.
local ADDON_NAME, NS = ...
if NS.SkuMissing then return end
local Log, SkuQuestTarget = NS.Log, NS.SkuQuestTarget

function SkuQuestTarget:OnEnable()
	Log("OnEnable start.")

	local tOk, tErr = pcall(NS.InstallMenu)
	if not tOk then Log("InstallMenu THREW: %s", tostring(tErr)) end

	local tOkKb, tErrKb = pcall(NS.InstallDefaultKeybind)
	if not tOkKb then Log("InstallDefaultKeybind THREW: %s", tostring(tErrKb)) end

	self:RegisterChatCommand("sqt", "SlashCommand")

	-- [2026-08-22] "assure-toi qu'une version anglaise de chaquns des
	-- addons est disponible" -- this activation line hardcoded the FRENCH
	-- menu path ("Cible de quête -> Raccourci clavier") into ALL THREE
	-- language branches, including the English and German ones -- an
	-- English- or German-client player would have read/heard their own
	-- language's sentence with a French menu name stitched into the
	-- middle of it. Now built from the SAME per-language menu/submenu
	-- labels Menu.lua's own `InstallMenu`/"Tastenkombination" entries
	-- already use, instead of a second, independently-hardcoded copy.
	local tMenuName = Sku.deEn and Sku.deEn("Questziel anvisieren", "Quest target", "Cible de quête") or "Cible de quête"
	local tSubName = Sku.deEn and Sku.deEn("Tastenkombination", "Keyboard shortcut", "Raccourci clavier") or "Raccourci clavier"
	print("|cff00ff00SkuQuestTarget|r: " ..
		(Sku.deEn and Sku.deEn(
			"aktiv. Taste: Shift+F1 -> " .. tMenuName .. " -> " .. tSubName .. ".",
			"active. Key: Shift+F1 -> " .. tMenuName .. " -> " .. tSubName .. ".",
			"actif. Touche : Shift+F1 -> " .. tMenuName .. " -> " .. tSubName .. ".")
		or "actif. Touche : Shift+F1 -> " .. tMenuName .. " -> " .. tSubName .. "."))
	Log("OnEnable end.")
end

-- /sqt -- for testing/diagnostics: dumps the resolved quest-target name set
-- to chat without needing an actual nameplate nearby.
-- [2026-08-22] Was hardcoded French-only with no Sku.deEn wrapper at all --
-- a real localization gap (an English/German client's /sqt would have
-- printed French text regardless), found during the same audit as
-- OnEnable's activation-message bug above. Localized like every other
-- user-facing string in this addon family.
function SkuQuestTarget:SlashCommand(aMsg)
	local tNames = NS.GetQuestTargetNames()
	local tParts = {}
	for tName in pairs(tNames) do tParts[#tParts + 1] = tName end
	table.sort(tParts)
	if #tParts == 0 then
		print("|cff80c0ffSkuQuestTarget|r: " .. (Sku.deEn and Sku.deEn(
			"kein Questziel im aktuellen Questlog.",
			"no quest target in the current quest log.",
			"aucune cible de quête dans le journal actuel.") or "aucune cible de quête dans le journal actuel."))
		return
	end
	local tList = table.concat(tParts, ", ")
	print("|cff80c0ffSkuQuestTarget|r: " .. (Sku.deEn and Sku.deEn(
		string.format("%d Questziel(e): %s", #tParts, tList),
		string.format("%d quest target(s): %s", #tParts, tList),
		string.format("%d cible(s) de quête : %s", #tParts, tList))
	or string.format("%d cible(s) de quête : %s", #tParts, tList)))
end

-- [2026-08-27] OnDisable used to be a no-op, which made Sku's Features
-- toggle one-way: turning "Cible de quête" OFF left both override bindings
-- armed, so the key kept targeting. AceAddon really does call this (Sku's
-- SkuCore:SetModuleEnabled -> tModule:Disable(), ModuleManager.lua), so the
-- teardown just had to be written.
--
-- ClearOverrideBindings is combat-protected, exactly like the SetOverrideBindingClick
-- that armed them -- if the player toggles the feature off mid-combat we
-- cannot release the keys right then, so it is logged and left to the next
-- OnEnable/OnDisable cycle rather than throwing.
function SkuQuestTarget:OnDisable()
	if InCombatLockdown and InCombatLockdown() then
		Log("OnDisable: in combat, override bindings left armed until the next out-of-combat toggle.")
		return
	end
	-- [2026-08-29] Was a loop over two button names; the second
	-- (NEAREST_ENEMY_BUTTON_NAME) no longer exists -- see Targeting.lua's
	-- own REMOVED note. Left as a single explicit release rather than a
	-- one-element loop.
	local tBtn = NS.SECURE_BUTTON_NAME and _G[NS.SECURE_BUTTON_NAME]
	if tBtn then
		local tOk, tErr = pcall(ClearOverrideBindings, tBtn)
		if not tOk then Log("OnDisable: ClearOverrideBindings(%s) THREW: %s", tostring(NS.SECURE_BUTTON_NAME), tostring(tErr)) end
	end
	Log("OnDisable: override bindings released.")
end
