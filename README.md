# SkuQuestTarget

Optional companion addon for **[Sku](https://github.com/ZenqFR/Sku-WoW-Addon-TBC)** (a screen-reader/accessibility addon for World of Warcraft, TBC Classic) that adds one dedicated keybind: press it, and whichever creature relevant to your current quest log's kill objective happens to be nearby gets targeted — no need to see it on screen to click it.

## What it does

- **One keybind** (`Shift+F1 → Cible de quête → Raccourci clavier` to set/change it, `Ctrl+K` by default): resolves the creature(s) relevant to your **current, in-progress** quest log entries — including creatures that merely *drop* an item a quest wants, not just direct kill targets — and runs the built-in `/target <name>` command against each candidate, the exact same thing typing it yourself does. Speaks the creature's name once targeted, or says plainly that nothing matched nearby.
- **"Cibler maintenant"** — the same action from Sku's own accessible menu, for testing without a keybind (out of combat only — see *How it works*).
- **Same key + Shift = target nearest enemy, no name needed.** Runs Blizzard's own built-in "target nearest enemy" (the same thing the default Tab keybind does) — for when there's no specific quest mob in mind, just "whatever's closest and hostile". Shares Tab's own reach: it needs a unit the game already has ready in its nearby list, so something directly behind you that's never been on-screen can still come up empty — a WoW engine boundary, not a bug here.
- Built on the exact same `SkuQuest`/`SkuDB` foundation as the sibling addon **[SkuQuestNearby](https://github.com/ZenqFR/Sku-QuestNearby)**: `SkuQuest:GetQuestTargetIds` resolves each quest's real kill targets, `SkuDB.NpcData.Names` gives their in-game names — no guessing, no separate database.

## What it deliberately does NOT do

- Doesn't track threat, doesn't auto-attack, doesn't cast anything, doesn't pick a target based on health or combat-log state. It only ever does what you could already do yourself by typing `/target <name>`.
- Doesn't help with **object** objectives (world objects to interact with, not creatures) — those aren't meaningfully "/target"-able the same way. **Item** objectives ("collect N of X") ARE covered, though: X's drop source(s) are resolved and targeted, since practically that's still "go kill a creature" for the vast majority of these quests.
- Can only find something the game's own `/target` search can find nearby. If nothing's nearby, it says so.

## How it works

- Toggle from Sku's own **Features** menu (Local → Settings → Module → Features → "Cible de quête"). Inert with zero effect if disabled.
- Two earlier mechanisms were tried and disproven by real testing before landing on this one: (1) scanning nameplates + `TargetUnit` — unreliable, since a nameplate only exists for a unit that's your current target or already in combat by default; (2) calling `SlashCmdList["TARGET"]` directly — doesn't exist on this client. The keybind now fires a **secure button** whose macro text is built fresh each press (one `/target <name>` line per candidate, computed in `PreClick` — the same combat-safe mechanism Sku's own keybinds use internally), bound to the physical key via `SetOverrideBindingClick`. The chosen key is stored in this addon's own `SkuQuestTargetKeyDB` SavedVariable and re-applied on every login/reload (override bindings, unlike normal ones, don't persist on their own).
- Blizzard's macro command text has a real length limit, so with a long quest log the candidate list can't all fit in one macro. Candidates are resolved to a rough distance first (`Distance.lua`, same spawn-coordinate math the sibling addon SkuQuestNearby uses) and sorted **closest first** — a creature within 500 yards always wins a spot in the macro over one that's merely earlier in list order, so the length limit can only ever cost a candidate that's far away or has no known position, never the one you're actually standing next to.
- Ships a self-diagnostic log (`/sqtlog`) and a `SkuQuestTargetLog` SavedVariable, plus `/sqt` to print the currently-resolved quest-target creature names to chat without needing one nearby.

## Requirements

- [Sku](https://github.com/ZenqFR/Sku-WoW-Addon-TBC)

## Status

Built and syntax-validated for a single user's own setup (TBC Classic Anniversary realms). Published at v0.1.1; the keybind's targeting mechanism has gone through several in-game test rounds since and is still being tightened (see CHANGELOG.md) — those fixes aren't published yet.

---

Built with [Claude Code](https://claude.com/claude-code).
