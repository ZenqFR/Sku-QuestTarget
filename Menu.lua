-- SkuQuestTarget/Menu.lua -- Shift+F1 root entry ("Cible de quête"),
-- appended at the end of Sku's own root menu via SkuMenu:RegisterModule +
-- SkuMenu.rootLayout, the exact same declarative pattern SkuGatherRoute
-- uses (additive only -- never calls SkuMenu:SetRootLayout, which would
-- replace the whole list and wipe every one of Sku's own root entries).
local ADDON_NAME, NS = ...
if NS.SkuMissing then return end
local Log, Announce = NS.Log, NS.Announce

---------------------------------------------------------------------------------------------------------------------------------------
-- [2026-08-20, REWRITTEN] The keybind no longer uses plain Blizzard
-- SetBinding/SaveBindings at all -- see Targeting.lua's EnsureSecureButton
-- comment for the full story (two earlier mechanisms tried and disproven:
-- nameplate scanning, then SlashCmdList["TARGET"], neither of which needed
-- a secure button at all). The real keybind now has to be bound directly
-- to the secure button via SetOverrideBindingClick -- the SAME "combat-
-- protected, must be armed OUT of combat" binding layer Sku's own
-- SKU_KEY_* keybinds use (confirmed via SkuCore/combatMenuKeys.lua/
-- DialTargeting.lua) -- which is NOT queryable via GetBindingKey/
-- GetBindingAction (those only see plain SetBinding-based bindings), and
-- does NOT persist across reload/relogin on its own the way SetBinding+
-- SaveBindings does. The chosen key is now tracked in this addon's own
-- SavedVariable (SkuQuestTargetKeyDB) and re-applied via
-- SetOverrideBindingClick on every OnEnable instead.
local tKeyCaptureFrame

local tModifierOnlyKeys = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
	UNKNOWN = true,
}

local function tModifierPrefix()
	local tPrefix = ""
	-- [2026-08-27] ALT, then CTRL, then SHIFT -- WoW's canonical binding
	-- string is "ALT-CTRL-SHIFT-<KEY>" and Sku's own capture routine
	-- (SkuZOptions/Core.lua:3559-3562) uses this order. CTRL-before-ALT
	-- only diverges when both are held, producing a string WoW never
	-- matches. Worse here than in the sibling addons: this addon PERSISTS
	-- the captured string to SkuQuestTargetKeyDB, so a bad one survives
	-- relogs.
	if IsAltKeyDown() then tPrefix = tPrefix .. "ALT-" end
	if IsControlKeyDown() then tPrefix = tPrefix .. "CTRL-" end
	if IsShiftKeyDown() then tPrefix = tPrefix .. "SHIFT-" end
	return tPrefix
end

-- Sku's OWN keybinds (SKU_KEY_*) apply via SetOverrideBindingClick on
-- secure buttons -- a SEPARATE binding layer WoW always checks BEFORE
-- normal SetBinding-based bindings for the same physical key, invisible to
-- GetBindingKey/GetBindingAction. Checked defensively so a key the player
-- picks here can never silently collide with one of Sku's own (same
-- precedent as SkuGatherRoute's own tSkuOwnBindingOwner).
local function tSkuOwnBindingOwner(aKey)
	if not SkuOptions or not SkuOptions.SkuKeyBindsCheckBound then return nil end
	local tOk, tResult = pcall(SkuOptions.SkuKeyBindsCheckBound, SkuOptions, aKey)
	if tOk then return tResult end
	return nil
end

-- [2026-08-20] CTRL-SHIFT-Q collided with Sku's own SKU_KEY_TOGGLEREACHRANGE
-- on first release (correctly detected and left unbound rather than
-- silently breaking, but still meant a fresh install needed a manual
-- rebind). CTRL-SHIFT-K, the replacement, is cross-checked against every
-- default in Sku's own SkuKeyBinds.lua AND both sibling addons' own
-- defaults (SkuGatherRoute's CTRL-SHIFT-N, SkuBagnonBridge's
-- CTRL-SHIFT-H/-J) -- free on all three lists.
--
-- [2026-08-27] Moved from "CTRL-SHIFT-K" to "CTRL-K" so that a Shift
-- variant actually EXISTS for the nearest-enemy binding -- see
-- ShiftVariantOf's own comment below for the full story. The pair is now
-- CTRL-K (quest target) + CTRL-SHIFT-K (nearest enemy), i.e. exactly the
-- two keys this addon already occupied. CTRL-K re-verified free against
-- Sku's own SkuKeyBinds.lua and all sibling addon defaults. Players who
-- already picked their own key are unaffected -- this only applies when
-- SkuQuestTargetKeyDB holds nothing yet.
local DEFAULT_KEY = "CTRL-K"

-- SkuQuestTargetKeyDB (SavedVariable, .toc) -- { key = "CTRL-K" }.
-- Read/written as a bare global with a defensive type-check at each access
-- (only ever touched from menu interaction, well after the real saved
-- table has replaced whatever this file's own top-level execution saw),
-- same idiom SkuGatherRoute's own SkuGatherRouteRecentDB/
-- SkuGatherRouteTypeSelectionDB use.
local function GetConfiguredKey()
	if type(SkuQuestTargetKeyDB) == "table" and SkuQuestTargetKeyDB.key and SkuQuestTargetKeyDB.key ~= "" then
		return SkuQuestTargetKeyDB.key
	end
	return nil
end

local function SetConfiguredKey(aKey)
	if type(SkuQuestTargetKeyDB) ~= "table" then SkuQuestTargetKeyDB = {} end
	SkuQuestTargetKeyDB.key = aKey
end

-- Arms (or re-arms) the real keybind: SetOverrideBindingClick, pointed
-- directly at the secure button (Targeting.lua's EnsureSecureButton) --
-- combat-protected itself, so this can only run OUT of combat (called at
-- OnEnable/login, and whenever the user picks a new key from this menu,
-- both of which are always out-of-combat contexts; refuses cleanly with a
-- spoken message if somehow called mid-combat rather than throwing).
-- [2026-08-21] "la même touche mais avec shift, cible la plus proche" --
-- the nearest-enemy button (Targeting.lua's EnsureNearestEnemyButton) is
-- armed on the SAME base key plus Shift -- no separate configuration UI, it
-- always follows whatever the main key is.
--
-- [2026-08-27, TWO REAL BUGS FIXED -- this had never worked on a fresh
-- install] The first cut was `"SHIFT-" .. aKey`, guarded by "skip if the
-- key already contains SHIFT". Both halves were wrong:
--
--  1) DEAD ON THE DEFAULT KEY. The default base key was "CTRL-SHIFT-K",
--     which contains "SHIFT-", so the guard fired and the button was never
--     armed at all -- on every fresh install, for a feature the .toc Notes
--     actively advertise. It only ever worked for a base key without Shift
--     (this developer's own key is "<", which is why it went unnoticed).
--     Fixed by moving the default to "CTRL-K", so the Shift variant is
--     "CTRL-SHIFT-K" -- the exact pair of keys this addon already reserved,
--     both verified free against Sku's own SkuKeyBinds.lua defaults and
--     against the three sibling addons.
--
--  2) WRONG MODIFIER POSITION. Blindly prefixing produced "SHIFT-CTRL-K",
--     but WoW's canonical form is "ALT-CTRL-SHIFT-<KEY>" -- Shift goes
--     LAST, not first. "SHIFT-CTRL-K" is a string the keypress never
--     resolves to, so even when it did arm, it armed something dead.
--     Now rebuilt in canonical order instead of concatenated.
--
-- A base key that genuinely already includes Shift still has no available
-- variant; that case stays skipped and logged, and FriendlyShiftKey reports
-- it as unavailable rather than pretending.
local function ShiftVariantOf(aKey)
	if not aKey or aKey == "" then return nil end
	if aKey:find("SHIFT%-") then return nil end
	local tHasAlt = aKey:find("ALT%-") ~= nil
	local tHasCtrl = aKey:find("CTRL%-") ~= nil
	local tBase = aKey:gsub("ALT%-", ""):gsub("CTRL%-", "")
	return (tHasAlt and "ALT-" or "") .. (tHasCtrl and "CTRL-" or "") .. "SHIFT-" .. tBase
end

local function ArmKeybind()
	local tBtn = NS.EnsureSecureButton and NS.EnsureSecureButton()
	if not tBtn then
		Log("ArmKeybind: EnsureSecureButton unavailable, skipped.")
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		Announce(Sku.deEn and Sku.deEn("Nicht im Kampf moeglich", "Not possible in combat", "Impossible en combat") or "Impossible en combat")
		Log("ArmKeybind: refused, in combat (SetOverrideBindingClick is combat-protected).")
		return false
	end
	pcall(ClearOverrideBindings, tBtn)
	local tKey = GetConfiguredKey() or DEFAULT_KEY
	local tOk, tErr = pcall(SetOverrideBindingClick, tBtn, true, tKey, tBtn:GetName())
	if not tOk then
		Log("ArmKeybind: SetOverrideBindingClick('%s') THREW: %s", tKey, tostring(tErr))
		return false
	end
	Log("ArmKeybind: bound '%s' to %s.", tKey, tBtn:GetName())

	local tEnemyBtn = NS.EnsureNearestEnemyButton and NS.EnsureNearestEnemyButton()
	if tEnemyBtn then
		pcall(ClearOverrideBindings, tEnemyBtn)
		local tShiftKey = ShiftVariantOf(tKey)
		if tShiftKey then
			local tOkShift, tErrShift = pcall(SetOverrideBindingClick, tEnemyBtn, true, tShiftKey, tEnemyBtn:GetName())
			if tOkShift then
				Log("ArmKeybind: bound '%s' to %s.", tShiftKey, tEnemyBtn:GetName())
			else
				Log("ArmKeybind: SetOverrideBindingClick('%s') THREW: %s", tShiftKey, tostring(tErrShift))
			end
		else
			Log("ArmKeybind: base key '%s' already includes Shift, skipped the nearest-enemy Shift-variant.", tKey)
		end
	end

	return true
end
NS.ArmKeybind = ArmKeybind

local function CaptureKeyFor(aOnDone)
	if not tKeyCaptureFrame then
		tKeyCaptureFrame = CreateFrame("Frame", nil, UIParent)
		tKeyCaptureFrame:SetPropagateKeyboardInput(false)
		tKeyCaptureFrame:Hide()
	end
	tKeyCaptureFrame:SetScript("OnKeyDown", function(aSelf, aKey)
		if tModifierOnlyKeys[aKey] then return end
		aSelf:EnableKeyboard(false)
		aSelf:Hide()
		if aKey == "ESCAPE" then
			Log("CaptureKeyFor: cancelled.")
			if aOnDone then aOnDone(nil) end
			return
		end
		local tFullKey = tModifierPrefix() .. aKey

		local tSkuOwner = tSkuOwnBindingOwner(tFullKey)
		if tSkuOwner then
			local tSkuOwnerName = (_G["BINDING_NAME_" .. tSkuOwner]) or tSkuOwner
			Log("CaptureKeyFor: '%s' is already used by Sku's own '%s' (override binding) -- refused.", tFullKey, tSkuOwner)
			Announce((Sku.deEn and Sku.deEn("Bereits von Sku belegt: ", "Already used by Sku: ", "Déjà utilisée par Sku : ") or "Déjà utilisée par Sku : ") .. tSkuOwnerName)
			if aOnDone then aOnDone(nil) end
			return
		end

		SetConfiguredKey(tFullKey)
		ArmKeybind()
		Log("CaptureKeyFor: bound '%s'.", tFullKey)
		if aOnDone then aOnDone(tFullKey) end
	end)
	tKeyCaptureFrame:EnableKeyboard(true)
	tKeyCaptureFrame:Show()
	Announce(Sku.deEn and Sku.deEn("Neue Taste druecken oder Escape zum Abbrechen", "Press a new key, or Escape to cancel", "Appuyez sur une nouvelle touche, ou Echap pour annuler") or "Appuyez sur une nouvelle touche, ou Echap pour annuler")
end

local function FriendlyBoundKeys()
	local tKey = GetConfiguredKey() or DEFAULT_KEY
	return tKey
end

-- [2026-08-21] Read-only info line for the menu -- the Shift-variant key
-- has no configuration of its own (see ArmKeybind's own comment), so this
-- just states what it currently resolves to, for the same reason every
-- other addon in this family always makes its active keybinds visible from
-- the accessible menu, not just spoken once at capture time.
local function FriendlyShiftKey()
	local tKey = GetConfiguredKey() or DEFAULT_KEY
	return ShiftVariantOf(tKey) or (Sku.deEn and Sku.deEn("nicht verfuegbar (Basistaste enthaelt bereits Shift)", "not available (base key already includes Shift)", "indisponible (la touche de base contient déjà Shift)") or "indisponible (la touche de base contient déjà Shift)")
end

-- Called from OnEnable -- arms the keybind using whichever key is
-- configured (the persisted SkuQuestTargetKeyDB.key, or DEFAULT_KEY if the
-- player has never customized it). Unlike the old SetBinding-based
-- InstallDefaultKeybind, this doesn't need to check for a collision every
-- session -- ArmKeybind always (re-)applies cleanly since
-- SetOverrideBindingClick simply overrides for this frame, it doesn't
-- "claim" a key away from anything else the way SetBinding could.
local function InstallDefaultKeybind()
	ArmKeybind()
end
NS.InstallDefaultKeybind = InstallDefaultKeybind

---------------------------------------------------------------------------------------------------------------------------------------
local function InstallMenu()
	if not SkuMenu or not SkuMenu.RegisterModule or not SkuMenu.rootLayout then
		Log("InstallMenu: SkuMenu not available, skipped.")
		return
	end
	SkuMenu:RegisterModule("SkuQuestTarget", {
		label = function() return Sku.deEn and Sku.deEn("Questziel anvisieren", "Quest target", "Cible de quête") or "Cible de quête" end,
		build = function(entry)
			SkuMenu:Build(entry, {
				{ kind = "action",
				  label = function() return Sku.deEn and Sku.deEn("Jetzt anvisieren", "Target now", "Cibler maintenant") or "Cibler maintenant" end,
				  run = function() SkuQuestTarget:TargetNearestQuestMob() end },
				{ kind = "action",
				  label = function() return (Sku.deEn and Sku.deEn("Naechsten Gegner anvisieren", "Target nearest enemy", "Cibler l'ennemi le plus proche") or "Cibler l'ennemi le plus proche")
					.. " (" .. FriendlyShiftKey() .. ")" end,
				  run = function() SkuQuestTarget:TargetNearestEnemy() end },
				{ kind = "list",
				  label = function() return (Sku.deEn and Sku.deEn("Tastenkombination", "Keyboard shortcut", "Raccourci clavier") or "Raccourci clavier")
					.. " : " .. FriendlyBoundKeys() end,
				  build = function(subEntry)
					SkuMenu:Build(subEntry, {
						{ kind = "action",
						  label = function() return Sku.deEn and Sku.deEn("Neu belegen", "Assign new key", "Assigner une nouvelle touche") or "Assigner une nouvelle touche" end,
						  run = function()
							CaptureKeyFor(function(aNewKey)
								if aNewKey then
									Announce((Sku.deEn and Sku.deEn("Neue Taste", "New key", "Nouvelle touche") or "Nouvelle touche") .. " " .. aNewKey)
								end
							end)
						  end },
						{ kind = "action",
						  label = function() return Sku.deEn and Sku.deEn("Standardtaste wiederherstellen", "Reset to default key", "Rétablir la touche par défaut") or "Rétablir la touche par défaut" end,
						  run = function()
							SetConfiguredKey(nil)
							ArmKeybind()
							Log("Menu: reset binding to default (%s).", DEFAULT_KEY)
							Announce((Sku.deEn and Sku.deEn("Standardtaste", "Default key", "Touche par défaut") or "Touche par défaut") .. " " .. DEFAULT_KEY)
						  end },
					})
				  end },
			})
		end,
	})
	local tAlreadyThere = false
	for i = 1, #SkuMenu.rootLayout do
		if SkuMenu.rootLayout[i] == "SkuQuestTarget" then tAlreadyThere = true break end
	end
	if not tAlreadyThere then
		table.insert(SkuMenu.rootLayout, "SkuQuestTarget")
	end
	Log("InstallMenu: root menu entry installed (already present=%s).", tostring(tAlreadyThere))
end
NS.InstallMenu = InstallMenu
