# PotionTracker Classic Era Issue Log

This report captures functional and structural problems that will surface when running PotionTracker inside the World of Warcraft Classic Era client. Each finding calls out the affected subsystem, why it is a problem specifically for the Classic sandbox, and where the issue lives in the code base.

## 1. Namespace and API hygiene
> **Status:** Resolved — logging and utility helpers are scoped as locals so the addon no longer leaks `Print`, `GetTableSize`, or `ExportCSV` into the shared Lua namespace.
- The addon leaks helper functions such as `Print`, `GetTableSize`, and `ExportCSV` into the global namespace instead of keeping them local to the addon. In the Classic Era client every addon shares the same Lua environment, so these definitions are prone to be clobbered or to clobber similarly named utilities shipped by other raid tools.【F:PotionTracker.lua†L52-L147】 Classic-era raid packs still depend heavily on the legacy global API, so minimizing global pollution is critical.

## 2. Consumable catalogue correctness
> **Status:** Resolved — the Classic consumable list now omits Burning Crusade entries and includes staples such as Major Mana Potions, Major Healing Potions, and Demonic Runes so raid leaders see authentic Era options.
- `availableBuffs` includes at least one Outland-only consumable (`Elixir of Major Firepower`, spell ID 28511) that does not exist in Classic Era. Trying to track it wastes UI space and can confuse raid leaders who never see the buff fire in logs.【F:PotionTracker.lua†L779-L802】
- Conversely, several high-impact Classic consumables are missing (for example Major Mana Potions, Demonic Runes, or Restorative Potions) even though the UI implies "PotionTracker" should cover them. The hard-coded list means Classic-only consumables must be added by hand, so raids cannot rely on the addon to surface the full set of pre-raid requirements.【F:PotionTracker.lua†L779-L812】

## 3. Startup state produces false positives
> **Status:** Resolved — baseline buffs are cached without emitting synthetic `BUFF_GAINED` events when tracking toggles or players zone in.
- `InitializeUnitBuffs` emits a `BUFF_GAINED` history entry for every tracked aura already on the player or raid member whenever tracking is toggled on or a roster slot is (re)initialized.【F:PotionTracker.lua†L1557-L1581】 In Classic Era raids this translates into dozens of synthetic "gains" the moment the addon loads or a player zones in, polluting exports and hiding genuine pre-pot usage.

## 4. Missing aura removal coverage when units are out of range
> **Status:** Resolved — the combat-log listener now records `SPELL_AURA_REMOVED` events with duplicate suppression so expirations are captured even when units leave aura range.
- The combat-log backstop only listens to `SPELL_AURA_APPLIED` and `SPELL_AURA_REFRESH`. There is no handler for `SPELL_AURA_REMOVED`, so if a raid member drops off the 40-yard unit aura radar (common on Classic Era's sprawling raids) the addon never records the aura expiration.【F:PotionTracker.lua†L2049-L2057】 The history then shows buffs being gained but never falling off, making duration analytics impossible.

## 5. Group roster churn leaks stale state
> **Status:** Resolved — roster updates prune `previousBuffs` and throttling caches for departed unit tokens, preventing stale data reuse.
- `GROUP_ROSTER_UPDATE` only seeds `previousBuffs` for new members; it never clears entries for unit tokens that disappear.【F:PotionTracker.lua†L1991-L2006】 In Classic Era raids where players frequently leave and rejoin between pulls, this leaves behind orphaned tables keyed by the old unit token, inflating memory use and risking misattribution if Blizzard reuses the same slot for a different player later in the session.

## 6. Classic encounter coverage gaps
> **Status:** Resolved — encounter tracking no longer hinges on a static whitelist; bosses are recognised dynamically via unit classification/level heuristics while retaining the legacy fallback list.
- The `trackedMobs` whitelist is frozen to the original 1.12 raid roster and omits Classic Era-specific content such as Season of Mastery world bosses or the Season of Discovery encounters. Combat tracking will therefore never assign encounter IDs for the newer raid targets Classic players actively fight.【F:PotionTracker.lua†L1422-L1530】

## 7. UI scalability and performance concerns
> **Status:** Partially resolved — the spreadsheet view reuses pooled rows/cells instead of rebuilding the scroll child every refresh, eliminating large allocations; dropdown templating continues to rely on Blizzard's `UIDropDownMenuTemplate` compatibility helper.
- Every call to `UI.Spreadsheet:UpdateData` destroys and recreates the entire scroll child, allocating dozens of textures and font strings on each refresh.【F:PotionTracker.lua†L1296-L1396】 On Classic Era's constrained 32-bit client this causes noticeable hitches when exporting large histories compared to reusing pooled rows.
- The minimap dropdown creates its own copy of the legacy `LibUIDropDownMenu` template each time it is shown, but Classic's dropdown API is sensitive to backdrops. The helper tries to append `BackdropTemplate` dynamically; if Blizzard adjusts the template name the addon will regress with the classic-era secure dropdown taint errors.【F:PotionTracker.lua†L66-L101】【F:PotionTracker.lua†L401-L432】

## 8. Slash command ergonomics
> **Status:** Resolved — `/pt showcsv` and `/pt showdetailed` now open a copy-friendly export window instead of spamming the chat log.
- `/pt showcsv` and `/pt showdetailed` dump the entire CSV straight to the chat frame via the addon prefix printer.【F:PotionTracker.lua†L2085-L2142】 Classic Era's chat buffer truncates long lines and rate-limits output, so exporting anything beyond a short raid quickly hits the 255-character limit, corrupting the copy/paste workflow the instructions recommend.

## 9. Dead code paths
> **Status:** Resolved — the undocumented `/pt hidetest` command has been removed to avoid confusing feedback about a non-existent frame.
- The slash command advertises `/pt hidetest`, yet the addon never creates the referenced `PotionTrackerTestFrame`. Users who try the command encounter a confusing "Test frame hidden" message without any prior cue that a test frame exists.【F:PotionTracker.lua†L2066-L2099】 Dead commands clutter the Classic UI and invite bug reports.

Addressing these issues will make PotionTracker more reliable for Classic Era raids and reduce the amount of manual babysitting raid leaders must perform to trust the collected data.
