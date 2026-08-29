# Changelog



## [1.1.0]

### Removed
- **The Shift variant of the targeting key (`Ctrl+Shift+K` by default), which targeted the nearest enemy.** It ran `/cleartarget` + `/targetenemy`, and `/targetenemy` is literally what the Tab key already does — the `/cleartarget` prefix only suppressed the *cycling*, it did not make the search any different from Blizzard's own. Verdict after real use: "ce que tu m'as fait fait juste un tab", then "je crois qu'elle est nul[le], à supprimer". Removed in full — secure button, macro, spoken result, menu row, keybind arming, teardown entry and the `.toc` Notes sentence in all three languages — rather than left in place unused. `Ctrl+Shift+K` is released back to the player. The quest-targeting key itself is untouched.

### Fixed
- **Disabling this addon from Sku's Features menu now actually stops it.** `OnDisable` was a no-op, so turning "Cible de quête" off left the override binding armed and the key kept targeting. Verified in Sku's own `SkuCore/ModuleManager.lua` that `SkuCore:SetModuleEnabled` really does call `tModule:Disable()`, so the teardown just had to be written: it now releases the override binding via `ClearOverrideBindings`. That call is combat-protected exactly like the one that armed it, so a mid-combat toggle is logged and deferred to the next out-of-combat cycle instead of throwing.
## [1.0.1]

### Fixed
- **`Bindings.xml` was listed in the `.toc`.** WoW loads a file called `Bindings.xml` automatically, by name — listing it as well made the client parse it a second time as a regular UI file, where `<Binding>` isn't a valid element, producing a burst of "Unrecognized XML" errors on every login. Confirmed against every other addon on the test install that ships a `Bindings.xml`: none of them list it either.
- **Illegal `--` inside XML comments** (SkuBeastLore, SkuQuestTarget). A double hyphen may not appear inside an XML comment; it is a fatal parse error, so the entire `Bindings.xml` was discarded and the keybind it declared never existed at all.
- **SkuBeastLore only:** stopped hijacking Sku's shared scanning tooltip. It reassigned that shared frame's owner and never restored it, and cleared no lines afterwards — leaving the frame in a modified state for every other Sku module that reads tooltips (bags, auction house, quest text). The owner is now restored exactly as Sku sets it, and the frame is cleared before and after use.
## [1.0.0] — first public release

First stable release. Previous versions were developed and published iteratively; this is the consolidated 1.0.0.

### Features
- One dedicated keybind (Ctrl+K by default) that targets the creature tied to your current quest objective — including creatures that merely drop a needed item — with no need to see it on screen.
- Candidates are resolved from Sku's own quest database and sorted closest-first, so the nearest valid target wins.
- The same key plus Shift (Ctrl+Shift+K) targets the nearest enemy, no name needed.
- A short sound instead of speech when nothing matches, so the key stays usable while moving.
- Fully translated: English, French, German.
