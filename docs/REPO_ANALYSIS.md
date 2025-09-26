# PotionTracker Addon Code Walkthrough

## Repository Overview
PotionTracker is a World of Warcraft Classic Era addon that tracks raid buff and potion usage, records encounter context, and surfaces the collected data through exports and in-game UI panels. The addon is implemented primarily in `PotionTracker.lua`, with a `.toc` manifest describing metadata and embedded libraries for dropdown menus.

## File Structure
- `PotionTracker.toc` — Addon manifest declaring interface version, metadata, saved variable table, embedded library files, and the main Lua file.
- `PotionTracker.lua` — Monolithic Lua module that defines the addon frame, event handling, configuration UI, tracking logic, history exports, and slash commands.
- `Libs/` — Bundled dependencies (LibStub, LibUIDropDownMenu) required for dropdown UI widgets.

## Initialization Flow
1. A frame is created and subscribes to character login, aura changes, group roster changes, combat state transitions, target updates, and combat log events (`CreateFrame` & `RegisterEvent`).
2. On `PLAYER_LOGIN`, saved variables are initialized, tracked buff defaults are seeded, logging preferences restored, and the minimap, options, and configuration UIs are created. If tracking was enabled previously, it scans current units immediately (`PLAYER_LOGIN` handler).

## Logging Facilities
- Log levels (`ERROR`, `WARN`, `INFO`, `DEBUG`) gate chat output. The selected level is stored in `PotionTrackerDB` and reflected in the options UI. `Print`, `Debug`, and `ShouldLog` implement level-aware messaging.

## History Management & Export
- `buffHistory` retains chronological buff events with throttled retention enforced by a configurable limit.
- `ExportCSV` builds both a summary CSV (player vs. buff counts) and a detailed CSV (timestamped events, encounter metadata, target snapshots) and stores the strings in saved variables for later retrieval or slash command display.

## Tracking Workflow
- `ToggleTracking` flips the tracking state, resets caches, and initializes units. Event handlers bail out early when disabled.
- `InitializeUnitBuffs` scans units to establish baseline buff states to avoid double-counting existing auras when tracking begins.
- `CheckNewBuffs` compares current buff snapshots against cached state, logging gained/lost events and updating history.
- Combat detection (`PLAYER_REGEN_DISABLED/ENABLED`) wraps tracked encounters with `COMBAT_START`/`COMBAT_END` records, tracking boss targets defined in `trackedMobs` and storing encounter IDs.

## UI Components
- **Minimap Button**: A draggable icon toggles tracking and exposes an options dropdown for configuration, exports, and statistics.
- **Options Panel**: Provides checkboxes, sliders, dropdowns for tracking enablement, history retention, and log level selection. Registered with Interface Options (or new Settings panel when available).
- **Buff Configuration**: Dialog listing tracked spell IDs grouped by category, allowing players to enable/disable buffs and persist frame position.
- **Spreadsheet View**: Scrollable table summarizing player buff counts built from saved history and rendered in-game.

## Slash Commands
`/pt` includes subcommands to toggle tracking, open configuration, export data, clear history, report stats, adjust logging, dump CSV buffers, and open the spreadsheet view.

## Key Data Tables
- `availableBuffs`: Spell metadata used to seed tracked buffs grouped by categories (e.g., protection potions, world buffs, consumables).
- `trackedBuffs`: Runtime map of spell IDs to localized names, filtered by user selection and used to map combat log spell IDs to display strings.
- `trackedMobs`: Lookup table of raid bosses used to enrich combat events and encounter tracking.

## Extensibility Considerations
- The addon currently stores exports as strings in saved variables; future improvements could include direct file export via Companion apps.
- UI frames are created programmatically; splitting logic into multiple Lua files or modules would improve maintainability.
- Additional analytics (uptime percentages, potion cooldown detection) could be derived from existing history data.
