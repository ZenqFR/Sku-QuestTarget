# Changelog


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
