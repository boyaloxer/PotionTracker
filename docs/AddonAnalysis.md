# PotionTracker Addon Analysis

## Overview
PotionTracker is a World of Warcraft Classic Era addon implemented entirely in Lua and designed to run inside the game client. It registers for core in-game events such as `PLAYER_LOGIN`, `UNIT_AURA`, raid roster changes, combat state toggles, target updates, and the combat log in order to observe buff usage and combat context in real time.【F:PotionTracker.lua†L1-L9】【F:PotionTracker.lua†L1865-L1988】 The addon persists configuration and history through the `PotionTrackerDB` saved variable namespace, allowing settings like tracked buffs, log level, minimap position, and export data to survive reloads.【F:PotionTracker.lua†L1867-L1905】

## Data Capture Pipeline
- **Tracked Buff Catalog** – A curated table of Classic-era potion and flask spell IDs feeds configuration UIs and detection logic, with sensible defaults for what is tracked out of the box.【F:PotionTracker.lua†L747-L837】
- **Unit Scanning** – When tracking is toggled on, the addon enumerates the player, party, or raid to capture existing aura states via `UnitBuff`/`AuraUtil`, seeding a cache for future comparisons.【F:PotionTracker.lua†L356-L379】【F:PotionTracker.lua†L1710-L1733】【F:PotionTracker.lua†L1444-L1522】
- **Continuous Monitoring** – Subsequent `UNIT_AURA` events and throttled polling compare previous and current buff states to detect gains and losses, emitting chat notifications and structured history entries for each change.【F:PotionTracker.lua†L1565-L1597】 Combat log events backstop the aura scanning to catch tracked buffs applied from outside direct unit updates.【F:PotionTracker.lua†L1974-L1986】
- **History Maintenance** – Every captured event is stored in an in-memory ring buffer capped by configurable history limits and mirrored to saved variables for persistence and exporting.【F:PotionTracker.lua†L321-L354】【F:PotionTracker.lua†L1524-L1559】

## User Interface Surface
- **Minimap Button & Dropdown** – A custom minimap icon exposes quick actions for configuration, spreadsheet viewing, exporting, clearing history, and checking stats. The icon desaturates when tracking is disabled and supports drag repositioning around the minimap.【F:PotionTracker.lua†L382-L520】【F:PotionTracker.lua†L1899-L1905】
- **Options Panel** – Integrated with the in-game options UI, the panel surfaces enable/disable toggles, history size sliders, and log-level controls, all synchronized with saved settings.【F:PotionTracker.lua†L582-L739】【F:PotionTracker.lua†L1600-L1622】
- **Buff Configuration Window** – A movable dialog groups the tracked buff catalog by category with checkboxes, apply/cancel semantics, and change detection so raid leaders can tailor which consumables to monitor.【F:PotionTracker.lua†L816-L1196】
- **Spreadsheet View & CSV Export** – A scrollable spreadsheet summarises buff usage counts per player, while CSV export routines produce both summary and detailed datasets (including encounter metadata and target snapshots) for offline analysis.【F:PotionTracker.lua†L1202-L1349】【F:PotionTracker.lua†L94-L205】 Slash commands also dump the CSV text directly to chat for copy/paste workflows.【F:PotionTracker.lua†L2001-L2119】

## Combat Context Tracking
Beyond buff auditing, the addon keeps lightweight encounter telemetry. It tracks boss targets of interest, builds encounter IDs, records combat start/end events with duration, and captures the roster of tracked boss targets engaged during a fight.【F:PotionTracker.lua†L1351-L1438】【F:PotionTracker.lua†L1735-L1854】 These events share the same history/export pipeline, enriching downstream reports with encounter framing.【F:PotionTracker.lua†L1786-L1854】【F:PotionTracker.lua†L1957-L1986】

## Integration Boundaries & Limitations
- **Sandboxed Environment** – The addon relies on World of Warcraft’s sandboxed Lua runtime and access to secure API functions such as `UnitBuff`, `CombatLogGetCurrentEventInfo`, `AuraUtil`, and UI creation helpers. None of these can be called from outside the game client.
- **SavedVariables Lifecycle** – Exported CSV content and historical data only flush to disk on logout/reload because saved variables are persisted by the game engine, not immediately accessible by external tools.【F:PotionTracker.lua†L94-L205】【F:PotionTracker.lua†L2001-L2119】
- **Event-Driven Access** – The addon’s view of raid members, buffs, and combat targets is exclusively driven by in-game events; it cannot poll arbitrary players or realms beyond the current group/raid context due to Blizzard’s addon API restrictions.【F:PotionTracker.lua†L1565-L1597】【F:PotionTracker.lua†L1907-L1932】

## Feasibility of an External Companion Application
Creating a standalone program that “connects” to WoW Classic Era to replace this addon would face significant barriers:
1. **Lack of External APIs** – Blizzard does not expose a supported external interface for Classic that would deliver unit aura data, combat logs, or group rosters in real time. All of the information PotionTracker consumes is available only from within the addon sandbox.【F:PotionTracker.lua†L1-L205】【F:PotionTracker.lua†L1565-L1986】
2. **Terms of Service & Security** – Injecting code, reading process memory, or sniffing network packets to obtain the same data would violate the World of Warcraft Terms of Service and risk account penalties. Addons are the sanctioned integration point.
3. **Workflow Coupling** – PotionTracker’s UI is deeply tied to in-game frames (minimap icon, options panel, dialogs) that provide immediate feedback to raid members. Replicating this interactivity externally would still require a presence in the game client for actionable alerts.【F:PotionTracker.lua†L382-L1349】
4. **Saved Variable Synchronization** – Even if an external program parsed saved variable files out-of-game, it would only see data after the player logs out or reloads the UI, eliminating the real-time monitoring that is the addon’s core value proposition.【F:PotionTracker.lua†L94-L205】【F:PotionTracker.lua†L2001-L2119】

## Recommendation
Given the heavy reliance on Blizzard’s protected API surface, event model, and UI subsystem, maintaining PotionTracker as an in-game addon is substantially more practical and policy-compliant than attempting to build an external companion program. Future enhancements are best delivered by iterating on the existing addon codebase—expanding tracked buff lists, refining UI workflows, or integrating with other in-game tools—rather than pursuing an unsanctioned external integration.
