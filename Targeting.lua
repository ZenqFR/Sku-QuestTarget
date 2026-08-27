-- SkuQuestTarget/Targeting.lua -- the actual feature: resolve which
-- creature names matter for the player's CURRENT quest log, and run the
-- built-in /target command against each candidate name via a secure
-- macro-attribute button (see EnsureSecureButton's own comment for why --
-- two earlier, simpler mechanisms were tried and empirically disproven
-- first: nameplate scanning, then SlashCmdList["TARGET"]).
local ADDON_NAME, NS = ...
if NS.SkuMissing then return end
local Log, Announce = NS.Log, NS.Announce
local GetPlayerContext, GetNpcDistance = NS.GetPlayerContext, NS.GetNpcDistance
local UNKNOWN_DISTANCE = NS.QUEST_TARGET_UNKNOWN_DISTANCE

-- [2026-08-21] "limité à 500m seulement sur la base de distance de Sku" --
-- creatures resolved within this many yards (Sku's own SkuNav.Geo:Distance
-- unit, same one SkuQuestNearby's own distances are shown in) are always
-- tried FIRST, before anything farther or unresolved -- see
-- Distance.lua's own file banner for why this matters for the macro-length
-- budget below.
local NEARBY_RANGE = 500

---------------------------------------------------------------------------------------------------------------------------------------
-- [2026-08-19] "Souvent j'ai rien alors que je devrais" -- ROOT-CAUSED via
-- SkuQuestTargetLog: every single press, across dozens of tries over
-- several play sessions, logged "no creature-type kill objective found",
-- never once a real match. Two real causes found, both fixed below:
--
-- 1) SCOPE GAP (the main one): v1 only ever looked at targetType=="creature"
--    objectives -- but the very common WoW pattern "collect N of item X"
--    (X drops from a creature you still have to go kill) is tracked in
--    SkuDB as targetType=="item", not "creature" -- confirmed by cross-
--    checking this exact player's own SkuQuestNearby log from the same
--    session, where every one of their then-active, not-yet-ready quests
--    was either 'item' or had no targetType at all, literally zero were
--    'creature'. A player would naturally expect "target my quest mob" to
--    work for this everyday case too. Fixed: item-type objectives are now
--    also resolved, via the SAME item-drop-source lookup (npcDrops)
--    the sibling addon SkuQuestNearby's own ResolveItemDistance already uses for
--    distance -- the creature(s) that drop the needed item get added to
--    the target-name set exactly like a direct kill target would.
--
-- 2) DATA GAP, found by reading SkuDB's own ChunkLoader.lua comment
--    directly: SkuDB.NpcData.Names["frFR"] -- this client's own locale --
--    is DELIBERATELY EMPTY ("frFR until the generated set lands", Sku's
--    own words). The enUS fallback already in place should paper over this
--    on its own, but a name lookup should never depend on ONLY the
--    locale-keyed override table when Sku's own base NpcData.Data entry
--    (index 1, SkuDB.NpcData.Keys['name']) already carries a name in
--    SOME language regardless of locale coverage -- added as a third,
--    final fallback tier for robustness against exactly this kind of
--    per-locale data gap.
--
-- Every creature name relevant to an IN-PROGRESS (not yet complete) quest
-- log entry's kill/interact objective, whether the objective is a direct
-- creature target or an item that drops from one. Deliberately only
-- `objectives`, not `startedBy`/`finishedBy` -- a quest-giver or turn-in
-- NPC isn't something you fight, and a quest already flagged complete has
-- nothing left to kill for it. Object-type objectives (world objects, not
-- creatures) stay out of scope -- not meaningfully targetable via /target.
--
-- Returns a plain set: tNames[creatureName] = { questId = ..., npcId = ... }
-- (the extra fields are for logging only, not used to pick a target).
local function ResolveNpcName(aNpcId)
	local tEntry = (SkuDB.NpcData.Names[Sku.Loc] and SkuDB.NpcData.Names[Sku.Loc][aNpcId])
		or (SkuDB.NpcData.Names["enUS"] and SkuDB.NpcData.Names["enUS"][aNpcId])
	if tEntry and tEntry[1] then return tEntry[1] end
	local tData = SkuDB.NpcData.Data[aNpcId]
	return tData and tData[SkuDB.NpcData.Keys["name"]]
end

local function GetQuestTargetNames()
	local tNames = {}
	local tCtx = GetPlayerContext and GetPlayerContext() or nil
	local tNum = GetNumQuestLogEntries() or 0
	for tQuestLogID = 1, tNum do
		local tTitle, _, _, tIsHeader, _, tIsComplete, _, tQuestID = GetQuestLogTitle(tQuestLogID)
		if not tIsHeader and tQuestID and tQuestID > 0 and tIsComplete ~= 1 then
			local tOk, tErr = pcall(function()
				local tData = SkuDB.questDataTBC[tQuestID]
				if not tData then return end
				local tSubTable = tData[SkuDB.questKeys["objectives"]]
				if not tSubTable then return end
				local tOkIds, tTargets, tTargetType = pcall(SkuQuest.GetQuestTargetIds, SkuQuest, tQuestID, tSubTable)
				if not tOkIds or not tTargets then return end

				-- [2026-08-21, REVERTED -- see below] a per-objective
				-- "already finished" filter briefly lived here (0.1.7),
				-- meant to stop offering a kill target once its own
				-- objective was individually done even while the rest of
				-- the quest stayed open. Pulled after a real, confirmed
				-- failure: "Ruffian du Totem-sinistre" and "Mercenaire du
				-- Totem-sinistre" are two DIFFERENT creature names sharing
				-- ONE combined kill objective/counter (a common WoW pattern
				-- -- "kill 8 of these several creature types", one shared
				-- progress number) -- SkuQuest:GetQuestTargetIds flattens
				-- every creature id for a quest into ONE array with no
				-- record of which ones shared an objective slot, so there
				-- was no reliable way to know which GetQuestLogLeaderBoard
				-- index actually belonged to which name. Killing the
				-- Ruffian advanced that shared counter enough to look
				-- "finished" from the (wrong) index this code guessed at,
				-- silently hiding Mercenaire too, even though the player
				-- still needed it. Worst case for NOT filtering is a wasted,
				-- harmless /target attempt on something already done --
				-- worst case for filtering wrong is silently blocking a
				-- target the player still needs, which is strictly worse
				-- for an addon whose entire purpose is finding that target.
				-- Only the whole-quest tIsComplete~=1 check above (unambiguous,
				-- always safe) still applies.
				local tNpcIds = {}
				if tTargetType == "creature" then
					for _, tNpcId in ipairs(tTargets) do tNpcIds[#tNpcIds + 1] = tNpcId end
				elseif tTargetType == "item" then
					for _, tItemId in ipairs(tTargets) do
						local tItemData = SkuDB.itemDataTBC and SkuDB.itemDataTBC[tItemId]
						local tDrops = tItemData and tItemData[SkuDB.itemKeys["npcDrops"]]
						if tDrops then
							for _, tNpcId in ipairs(tDrops) do tNpcIds[#tNpcIds + 1] = tNpcId end
						end
					end
				else
					return
				end

				for _, tNpcId in ipairs(tNpcIds) do
					local tName = ResolveNpcName(tNpcId)
					if tName then
						local tDist = (tCtx and GetNpcDistance) and GetNpcDistance(tCtx, tNpcId) or nil
						local tExisting = tNames[tName]
						-- Same name can resolve from more than one npcId (an
						-- item dropping from several creature types, or two
						-- quests sharing a target) -- keep whichever
						-- resolution is actually closer, never just the
						-- first one seen.
						if not tExisting or (tDist and (not tExisting.distance or tDist < tExisting.distance)) then
							tNames[tName] = { questId = tQuestID, npcId = tNpcId, distance = tDist }
						end
					end
				end
			end)
			if not tOk then Log("GetQuestTargetNames: questID=%d ('%s') THREW: %s", tQuestID, tostring(tTitle), tostring(tErr)) end
		end
	end
	return tNames
end
NS.GetQuestTargetNames = GetQuestTargetNames

---------------------------------------------------------------------------------------------------------------------------------------
-- [2026-08-20, SECOND ROOT CAUSE] "J'ai le message ciblage indisponible" --
-- `SlashCmdList["TARGET"]` (the v0.1.3 fix) does NOT exist on this client.
-- Confirmed empirically, not a guess this time. This client's build
-- evidently doesn't expose the built-in /target command as a plain
-- Lua-callable table entry the way many WoW-API references assume --
-- typing it in chat still works (proven by the user's own /tar Baron), but
-- that path apparently isn't reachable by calling SlashCmdList directly.
--
-- Rewritten again, this time onto the mechanism Sku's OWN code actually
-- proves works on this exact client for "run a macro command safely, even
-- in combat": a SecureActionButtonTemplate button with its "macrotext"
-- attribute set to "/target <name>" lines, clicked via a REAL hardware
-- keypress bound with SetOverrideBindingClick -- confirmed by reading
-- SkuCore/combatMenuKeys.lua and SkuCore/DialTargeting.lua directly, both
-- of which use exactly this shape for their own combat-safe actions. This
-- is a different, stronger guarantee than "call an insecure Lua function
-- and hope it's not protected" (the v0.1.1-v0.1.3 approach) -- macro
-- command execution via a secure button's attribute is the mechanism
-- Blizzard actually built FOR this, not a workaround.
--
-- The macro text is built fresh in PreClick (one "/target <name>" line per
-- candidate quest-target name) -- PreClick runs synchronously as part of
-- the SAME secure/hardware-triggered call chain as the click itself, which
-- is specifically why SetAttribute is allowed there even in combat (the
-- whole reason PreClick exists as a concept, distinct from a plain
-- OnClick). A non-matching /target line is a no-op (leaves whatever the
-- previous line in the macro set), so listing every candidate is safe --
-- worst case, nothing changes. Success/failure is told apart in PostClick
-- by comparing the target's GUID before and after the click.
local tSecureButton

local function EnsureSecureButton()
	if tSecureButton then return tSecureButton end
	tSecureButton = CreateFrame("Button", "SkuQuestTargetSecureButton", UIParent, "SecureActionButtonTemplate")
	-- [2026-08-20] "type1"/"macrotext1" (numbered -- the per-button-index
	-- attribute form), NOT the plain "type"/"macrotext" this addon used
	-- through v0.1.4/0.1.5 -- found by reading Sku's OWN two real
	-- "target/focus a unit by name via a secure macro button" call sites
	-- (SkuCore/skuFocus.lua's SkuFocus:SetFocusUnitName, and
	-- SkuCore/Core.lua's nameplate-repo re-target), BOTH of which
	-- consistently use `SetAttribute("type1", "macro")` +
	-- `SetAttribute("macrotext1", "/tar " .. name)`, never the unnumbered
	-- form. This is a real, documented SecureActionButtonTemplate
	-- distinction (attributes can be generic, applying to any click, OR
	-- suffixed by button index to apply only to that specific button) --
	-- switched to match Sku's own proven-working convention exactly rather
	-- than keep guessing at why /target kept silently matching nothing
	-- despite the macro visibly running.
	tSecureButton:SetAttribute("type1", "macro")
	-- [2026-08-21] REAL ROOT CAUSE, found by direct comparison against
	-- Sku's own "focus" buttons (SkuCore/skuFocus.lua's setupHelper) --
	-- the ONE other place in Sku's own code that pairs a bare
	-- SecureActionButtonTemplate button with SetOverrideBindingClick,
	-- exactly this addon's own shape. Sku's version explicitly calls
	-- `RegisterForClicks("AnyUp", "AnyDown")` on that button -- this
	-- addon never called RegisterForClicks at all, leaving whatever the
	-- template's own default click registration is (commonly just
	-- "LeftButtonUp"), which apparently doesn't line up with the click
	-- SetOverrideBindingClick actually synthesizes on this client:
	-- PreClick/PostClick kept firing normally (proving the click WAS
	-- being dispatched and processed as a script callback), but the
	-- protected macro-text execution step inside that same click never
	-- ran -- silently, no error -- exactly the symptom reported even
	-- with a short, correctly-named, confirmed-nearby single candidate.
	-- Confirmed via the user's own side-by-side test: a hand-made
	-- Blizzard macro with the identical resolved name, clicked with the
	-- MOUSE, targeted the mob instantly -- proving the name and the
	-- macro mechanism are both fine, and narrowing the fault to this
	-- button's click registration specifically.
	--
	-- [2026-08-22, REFINED] "ça me fait le bruit alors que j'ai trouvé un
	-- objectif" -- real bug, not another sound preference: registering for
	-- BOTH edges makes a keybind press fire the WHOLE PreClick/Click/
	-- PostClick sequence TWICE (once for the synthesized press, once for
	-- the release) -- the first pass finds and sets the target correctly,
	-- then a SECOND pass runs immediately after with `tOriginalGUID`
	-- re-captured as the target JUST acquired; the macro runs again,
	-- doesn't change anything (already on the right unit), so the "no
	-- match" branch fires and plays the miss sound right after the
	-- success announcement. Exactly the double-fire Sku's OWN code warns
	-- about for a keybind-driven click: `SkuCoreSkuFocusControl` in
	-- SkuCore/skuFocus.lua deliberately registers ONLY "AnyDown" with a
	-- comment explaining that registering both edges made its own OnClick
	-- run twice. Narrowed to "AnyDown" alone here too -- still an
	-- explicit, non-default registration (the part that actually fixed
	-- the original "click never does anything" bug above), just without
	-- doubling the whole sequence per press.
	tSecureButton:RegisterForClicks("AnyDown")
	tSecureButton:Hide()

	-- [2026-08-21] LIKELY REAL ROOT CAUSE, found by direct character-count
	-- math against the user's own logged 25-candidate list: the single
	-- newline-joined macrotext1 string routinely ran past 700+ characters,
	-- while Blizzard's macro command text has a long-standing ~255-
	-- character limit -- and "Déboiseur de la KapitalRisk" (candidate #22
	-- of 25 in that exact log) sat well past that cutoff on every real
	-- test, while the user's manual, unlimited `/tar déb` worked instantly
	-- on the SAME mob seconds earlier. That's exactly the signature this
	-- predicts: names late in the (arbitrary pairs()-order) list never
	-- actually run, no matter how correct the resolved name is, because the
	-- text feeding the macro engine got silently cut before ever reaching
	-- them. Capped here to a conservative budget so the text actually sent
	-- to the engine can never lose candidates to that limit. If this still
	-- doesn't fix it, PostClick now also logs the exact string length and
	-- how many candidates got dropped for budget, so the NEXT log capture
	-- proves or disproves the theory outright instead of leaving it a guess.
	local MACRO_TEXT_BUDGET = 200

	tSecureButton:SetScript("PreClick", function(self)
		self.tOriginalGUID = UnitExists("target") and UnitGUID("target") or nil
		self.tAttemptedNames = nil
		self.tDroppedForBudget = nil
		self.tMacroTextLength = nil
		local tOk, tErr = pcall(function()
			local tQuestNames = GetQuestTargetNames()
			self.tHadCandidates = next(tQuestNames) ~= nil
			if not self.tHadCandidates then
				self:SetAttribute("macrotext1", "")
				return
			end
			-- [2026-08-21] "pousse le truc, un algorithme qui s'adapte, une
			-- limite de distance" -- candidates are sorted CLOSEST FIRST for
			-- INCLUSION (any real, resolved distance under NEARBY_RANGE
			-- always wins a macro slot before anything farther or
			-- unresolved), so the character budget below can only ever cut
			-- candidates that are far away or whose distance couldn't be
			-- resolved at all -- never the mob the player is actually
			-- standing next to. Nothing is EVER hard-excluded by distance
			-- alone, on purpose: SkuDB's spawn coverage has real, known gaps
			-- (see Distance.lua and SkuQuestNearby/Proximity.lua's own
			-- comments on this), and a hard cutoff would just resurrect this
			-- addon's original bug in a new shape -- "unknown distance"
			-- still gets a shot, it's just the LAST thing sacrificed to the
			-- length budget.
			local tSorted = {}
			for tName, tInfo in pairs(tQuestNames) do
				tSorted[#tSorted + 1] = { name = tName, distance = tInfo.distance or UNKNOWN_DISTANCE }
			end
			table.sort(tSorted, function(a, b) return a.distance < b.distance end)

			local tIncluded, tDropped, tRunningLength = {}, 0, 0
			for _, tEntry in ipairs(tSorted) do
				local tLine = "/target " .. tEntry.name
				local tNewLength = tRunningLength + #tLine + 1
				if tNewLength <= MACRO_TEXT_BUDGET then
					tIncluded[#tIncluded + 1] = { line = tLine, distance = tEntry.distance }
					tRunningLength = tNewLength
				else
					tDropped = tDropped + 1
				end
			end

			-- [2026-08-21] "ça me target la dernière /target" -- exactly
			-- right: every matching line in a multi-line macro actually
			-- fires, in order, and each successful match OVERWRITES the
			-- previous one -- so whichever candidate's line happens to be
			-- LAST in the macro text wins the final target, regardless of
			-- how close it actually is. The budget selection above (closest
			-- candidates included first) only decided WHO makes the cut --
			-- it said nothing about execution order. Reversed here so the
			-- CLOSEST included candidate's line is the very last one in the
			-- macro text, guaranteeing it's the one left targeted if more
			-- than one candidate happens to match something nearby.
			local tLines, tNearbyCount = {}, 0
			for i = #tIncluded, 1, -1 do
				local tEntry = tIncluded[i]
				tLines[#tLines + 1] = tEntry.line
				if tEntry.distance <= NEARBY_RANGE then tNearbyCount = tNearbyCount + 1 end
			end
			self.tAttemptedNames = tLines
			self.tDroppedForBudget = tDropped
			self.tNearbyCount = tNearbyCount
			local tMacroText = table.concat(tLines, "\n")
			self.tMacroTextLength = #tMacroText
			self:SetAttribute("macrotext1", tMacroText)
		end)
		if not tOk then
			Log("SkuQuestTargetSecureButton PreClick THREW: %s", tostring(tErr))
			self:SetAttribute("macrotext1", "")
			self.tHadCandidates = false
		end
	end)

	tSecureButton:SetScript("PostClick", function(self)
		if not self.tHadCandidates then
			Announce(Sku.deEn and Sku.deEn("Kein Questziel im Questlog", "No quest target in your log", "Aucune cible de quête dans le journal") or "Aucune cible de quête dans le journal")
			Log("TargetNearestQuestMob: no creature-type kill objective found in the current quest log.")
			return
		end
		if UnitExists("target") and UnitGUID("target") ~= self.tOriginalGUID then
			local tNewName = UnitName("target")
			Announce(tNewName)
			Log("TargetNearestQuestMob: targeted '%s' via secure macro /target. macrotext length=%d, dropped for budget=%d, nearby(<=%dy) candidates tried=%d.",
				tostring(tNewName), self.tMacroTextLength or 0, self.tDroppedForBudget or 0, NEARBY_RANGE, self.tNearbyCount or 0)
		else
			-- [2026-08-22] "supprimer le message automatique... ou juste
			-- mettre un son rapide" -- this key gets pressed often just
			-- while walking around, and a full spoken "Pas de cible de
			-- quête à proximité" on every single miss was more interruption
			-- than signal. Replaced with a quick sound cue instead.
			-- [2026-08-22, SWAPPED TWICE] 882 (SkuGatherRoute's negative
			-- scan cue), then 847 (Sku's disabled quest-button click) --
			-- user asked for yet another. This time: PlaySound(681), which
			-- SkuZOptions/templates.lua plays when moving to the next/prev
			-- menu item hits the END of the list -- Sku's own "you tried to
			-- go further, there's nothing more here" cue. Same meaning as
			-- this key finding nothing nearby, and native Sku behavior on
			-- this exact client.
			pcall(PlaySound, 681)
			-- [2026-08-20, DIAGNOSTIC -- since retired] This used to append
			-- the FULL list of every "/target <name>" line the macro had
			-- just run, to tell "no match" apart from "the candidate set was
			-- wrong". That diagnostic did its job: the real cause turned out
			-- to be the missing RegisterForClicks call, fixed in 0.1.9.
			--
			-- [2026-08-27] The name dump is now removed. It had become the
			-- single biggest source of log noise in the whole addon family --
			-- 245 recorded occurrences, each carrying up to 25 creature
			-- names, which alone accounted for most of a ~99 KB log and
			-- repeatedly rolled the 500-entry cap (Log.lua), destroying older
			-- entries that might have explained a real problem. The counts
			-- kept below still distinguish every case the dump was added for:
			-- zero candidates vs candidates-but-none-nearby vs
			-- candidates-dropped-for-the-macro-length-budget.
			Log("TargetNearestQuestMob: no /target line matched anything (target unchanged). macrotext length=%d, candidates tried=%d, dropped for budget=%d, of which nearby(<=%dy)=%d.",
				self.tMacroTextLength or 0, #(self.tAttemptedNames or {}),
				self.tDroppedForBudget or 0, NEARBY_RANGE, self.tNearbyCount or 0)
		end
	end)

	return tSecureButton
end
NS.EnsureSecureButton = EnsureSecureButton
NS.SECURE_BUTTON_NAME = "SkuQuestTargetSecureButton"

---------------------------------------------------------------------------------------------------------------------------------------
-- [2026-08-21] "la même touche mais avec shift, cible la plus proche de
-- moi sans nom à donner, même si elle est derrière moi" -- a second,
-- much simpler secure button, bound to the SAME physical key plus Shift
-- (see Menu.lua's ArmKeybind, which now arms both). Static macro text --
-- nothing to compute, no candidate list, just Blizzard's own built-in
-- "target nearest enemy" command (the exact same thing the default Tab
-- keybind runs).
--
-- Honest limitation, stated up front rather than found the hard way like
-- the main keybind's: `/targetenemy` uses the SAME underlying search Tab
-- itself does, which only considers units the game currently has ready in
-- its nearby-unit list -- not literally everything hostile within some
-- radius regardless of facing. It's noticeably more reliable than
-- physically turning the camera around, but "directly behind you, never
-- rendered this side" can still come up empty -- a WoW engine boundary
-- this addon has no way to route around, not a bug in this mechanism.
local tNearestEnemyButton

local function EnsureNearestEnemyButton()
	if tNearestEnemyButton then return tNearestEnemyButton end
	tNearestEnemyButton = CreateFrame("Button", "SkuQuestTargetNearestEnemyButton", UIParent, "SecureActionButtonTemplate")
	tNearestEnemyButton:SetAttribute("type1", "macro")
	-- [2026-08-21] "ce que tu m'as fait fait juste un tab" -- exactly
	-- right, and the reason is literal: /targetenemy IS Tab, cycle
	-- behavior included -- with an existing target already in its
	-- candidate set, it moves on to the NEXT nearest instead of
	-- re-picking the closest one every time. /cleartarget first forces a
	-- clean slate on every press, so /targetenemy always has to evaluate
	-- fresh and genuinely picks the closest one, never cycling forward.
	tNearestEnemyButton:SetAttribute("macrotext1", "/cleartarget\n/targetenemy")
	-- [2026-08-22] Same double-fire fix as EnsureSecureButton's own
	-- "AnyDown" comment above -- "AnyUp","AnyDown" together would run this
	-- button's whole PreClick/Click/PostClick sequence TWICE per keypress,
	-- and the second pass would announce "Aucun ennemi à proximité" right
	-- after correctly targeting one on the first pass (its target is
	-- already set by then, so the second pass's own GUID comparison finds
	-- "no change" and reports a miss). "AnyDown" alone still fires
	-- correctly, just once.
	tNearestEnemyButton:RegisterForClicks("AnyDown")
	tNearestEnemyButton:Hide()

	tNearestEnemyButton:SetScript("PreClick", function(self)
		self.tOriginalGUID = UnitExists("target") and UnitGUID("target") or nil
	end)
	tNearestEnemyButton:SetScript("PostClick", function(self)
		if UnitExists("target") and UnitGUID("target") ~= self.tOriginalGUID then
			local tNewName = UnitName("target")
			Announce(tNewName)
			Log("TargetNearestEnemy: targeted '%s' via /targetenemy.", tostring(tNewName))
		else
			Announce(Sku.deEn and Sku.deEn("Kein Gegner in der Naehe", "No enemy nearby", "Aucun ennemi à proximité") or "Aucun ennemi à proximité")
			Log("TargetNearestEnemy: /targetenemy found nothing (target unchanged).")
		end
	end)

	return tNearestEnemyButton
end
NS.EnsureNearestEnemyButton = EnsureNearestEnemyButton
NS.NEAREST_ENEMY_BUTTON_NAME = "SkuQuestTargetNearestEnemyButton"

-- Menu-reachable ("Cibler maintenant"), non-secure fallback -- clicking a
-- secure button via :Click() from plain Lua is NOT a hardware event, so
-- this only reliably works OUT of combat (same limitation already
-- documented for this menu action since v0.1.0). In combat, the real
-- keybind (bound directly to the secure button via SetOverrideBindingClick,
-- see Menu.lua) is the only path guaranteed to work.
local function TargetNearestQuestMob()
	local tBtn = EnsureSecureButton()
	local tOk, tErr = pcall(tBtn.Click, tBtn)
	if not tOk then Log("TargetNearestQuestMob: manual :Click() THREW (expected if in combat): %s", tostring(tErr)) end
end
NS.TargetNearestQuestMob = TargetNearestQuestMob

-- Real method on the addon object (not just an NS field) -- Menu.lua's
-- "Cibler maintenant" action calls SkuQuestTarget:TargetNearestQuestMob()
-- by name. The real KEYBIND no longer goes through this at all (see
-- EnsureSecureButton's own comment) -- it's bound directly to the secure
-- button via SetOverrideBindingClick for combat safety.
function NS.SkuQuestTarget:TargetNearestQuestMob()
	TargetNearestQuestMob()
end

-- Same menu-reachable, out-of-combat-only pattern as TargetNearestQuestMob
-- above, for the Shift-variant nearest-enemy button.
local function TargetNearestEnemy()
	local tBtn = EnsureNearestEnemyButton()
	local tOk, tErr = pcall(tBtn.Click, tBtn)
	if not tOk then Log("TargetNearestEnemy: manual :Click() THREW (expected if in combat): %s", tostring(tErr)) end
end
NS.TargetNearestEnemy = TargetNearestEnemy

function NS.SkuQuestTarget:TargetNearestEnemy()
	TargetNearestEnemy()
end
