# World of Warcraft Classic Era Addon Architecture

## File & Folder Layout
- Each addon resides in its own folder within `Interface/AddOns/` and is named after the addon (e.g., `PotionTracker`).
- A `.toc` (Table of Contents) file is required and lists metadata (Interface version, Title, Notes, Author, SavedVariables, Dependencies) followed by the Lua/XML file load order.
- Lua files contain the executable addon code. XML files are optional and typically used for declarative UI layouts, but Classic Era allows creating frames entirely from Lua, as PotionTracker does.
- Bundled libraries (e.g., LibStub, LibUIDropDownMenu) live within subfolders and are referenced from the `.toc` so they load before dependent code.

## Loading & Execution Model
- Addons are loaded when the client starts or when logging into a character if they are enabled. Files listed in the `.toc` are executed sequentially in a single Lua environment shared by all addons.
- Execution is sandboxed: addons cannot access the operating system directly, perform arbitrary file I/O, or issue network requests. They can only use APIs exposed by Blizzard's UI environment.
- Event-driven programming is central. Addons create frames, register for events (e.g., `PLAYER_LOGIN`, `UNIT_AURA`, `COMBAT_LOG_EVENT_UNFILTERED`), and implement `OnEvent` handlers to react to game state changes.
- Secure code paths (taint system) restrict protected actions during combat; Classic Era addons must avoid insecure UI modifications while in combat lockdown unless using secure templates.

## Saved Variables & Persistence
- The `.toc` `## SavedVariables` line declares global tables that are serialized to disk on logout/reload (`WTF/Account/.../SavedVariables`).
- Addons initialize these tables during `PLAYER_LOGIN` (or `ADDON_LOADED` in modern patterns) and update them as the player interacts with the addon.
- Saved variables persist across sessions and can store configuration, historical data, and export payloads, as PotionTracker does.

## User Interaction Patterns
- Slash commands are registered by assigning handler functions to `SlashCmdList` entries, and the `SLASH_<NAME>1` constants declare command strings (e.g., `/pt`).
- UI can be built dynamically via `CreateFrame`, textures, font strings, and templates. Classic Era provides premade templates like `UIDropDownMenuTemplate`, `OptionsSliderTemplate`, and `UIPanelButtonTemplate`.
- Minimap buttons are commonly implemented by creating a draggable frame anchored to the minimap and persisting a polar position (angle) in saved variables.
- Interface options panels are registered via `InterfaceOptions_AddCategory` (Classic) or `Settings.OpenToCategory` (Dragonflight+ clients). Classic Era clients still support the former API.

## Combat Log & Aura APIs
- `UNIT_AURA` events fire when a unit's buffs/debuffs change; Classic Era exposes `AuraUtil.FindAuraByName` / `UnitBuff` to inspect them.
- `COMBAT_LOG_EVENT_UNFILTERED` returns structured combat log entries; addons call `CombatLogGetCurrentEventInfo()` to unpack details and filter for relevant events (e.g., `SPELL_AURA_APPLIED`).
- Addons must guard against performance issues by throttling scans, caching state, and filtering units/spell IDs.

## Distribution & Packaging
- To distribute, authors zip the addon folder (maintaining folder structure) and upload to addon repositories (e.g., CurseForge, Wago). Users extract into `Interface/AddOns/` and enable via the in-game AddOns panel.
- Interface version numbers in the `.toc` should match the client build to avoid being flagged as out-of-date; Classic Era currently uses `114xx` numbers for Season of Discovery.

## Testing & Debugging Tips
- `/reload` reloads the UI to pick up code changes and flush saved variables.
- Use `DEFAULT_CHAT_FRAME:AddMessage`, custom logging utilities, or external tools like BugSack/BugGrabber to monitor errors.
- Because addons share the global namespace, namespacing (tables, local variables) helps avoid collisions. Libraries like Ace3 provide structured addon frameworks if desired.
