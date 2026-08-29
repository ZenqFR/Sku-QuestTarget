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
-- [2026-08-27] Moved from "CTRL-SHIFT-K" to "CTRL-K" so a Shift variant
-- could exist for the (since-removed, see below) nearest-enemy binding.
-- Kept at CTRL-K: it is re-verified free against Sku's own SkuKeyBinds.lua
-- and all sibling addon defaults, and moving it back now would silently
-- change the key under anyone who has been using it. Players who picked
-- their own key are unaffected -- this only applies when
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
-- [2026-08-29, REMOVED] The Shift variant of the base key used to arm a
-- second secure button that ran "/cleartarget" + "/targetenemy" ("Cibler
-- l'ennemi le plus proche"). It was requested as "target the closest thing
-- to me", but /targetenemy is precisely what the Tab key already does --
-- the user's own verdict after trying it was "ce que tu m'as fait fait
-- juste un tab", then "je crois qu'elle est nul[le], à supprimer". Spending
-- a reserved keybind, a secure button, a persistent teardown path and a
-- menu row on a duplicate of a key WoW binds by default is a net cost, so
-- the whole feature is gone rather than left in place unused. The base key
-- (quest targeting) is untouched, and CTRL-SHIFT-K is released back for the
-- player to use for anything else.
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
