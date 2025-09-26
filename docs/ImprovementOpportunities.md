# PotionTracker Improvement Opportunities

This backlog captures concrete, low-risk improvements discovered while reviewing the current PotionTracker implementation. Items are grouped by priority, with a short explanation of the user-facing benefit and the minimally invasive change that would unlock it.

## Completed High Priority Items

| Theme | Fix Implemented | Change Surface |
| --- | --- | --- |
| Event coverage | Combat log handler now forwards `SPELL_AURA_REFRESH` events to `RecordBuffEvent`, emitting a `BUFF_REFRESHED` history entry so pre-pots and refreshes are captured. | `PotionTracker.lua` (combat log dispatch + `RecordBuffEvent`) |
| Data correctness | Active-buff caches are keyed by `spellId` instead of localized names, preventing overwrites when two buffs share text and ensuring removals map to the correct history rows. | `PotionTracker.lua` (buff cache helpers + consumers) |
| Performance & scalability | `EnforceHistoryLimit` trims overflow entries in a single pass, avoiding the \(O(n^2)\) cost of repeated `table.remove` calls during large cleanups. | `PotionTracker.lua` (history management helper) |

## Completed Medium Priority Items

| Theme | Fix Implemented | Change Surface |
| --- | --- | --- |
| Startup cost | `InitializeUnitBuffs` now reuses the `GetUnitBuffs` snapshot captured for the unit, eliminating the redundant `AuraUtil.FindAuraByName` scan during login or roster swaps. | `PotionTracker.lua` (unit initialization flow) |

## High Priority

| Theme | Problem & Impact | Proposed Fix | Change Surface |
| --- | --- | --- | --- |
| _None currently outstanding_ |  |  |  |

## Medium Priority

| Theme | Problem & Impact | Proposed Fix | Change Surface |
| --- | --- | --- | --- |
| API hygiene | Helpers such as `Print`, `GetTableSize`, and `ExportCSV` are exported as globals, increasing the chance of clobbering by other addons. | Namespace these utilities under the existing `UI`/`PotionTracker` tables and retain backward compatibility by creating local aliases where they are consumed. | `PotionTracker.lua` (top-level utility definitions) |

## Low Priority

| Theme | Problem & Impact | Proposed Fix | Change Surface |
| --- | --- | --- | --- |
| UX consistency | The slash command handler and the minimap menu both implement their own history-clearing logic; they occasionally drift and miss auxiliary resets (e.g., cached exports).【F:PotionTracker.lua†L366-L433】【F:PotionTracker.lua†L2000-L2042】 | Centralize “reset addon state” into a shared helper that both entry points call. This keeps new fields from being forgotten in future tweaks. | `PotionTracker.lua` (command handling + minimap menu) |

### Next Steps

A practical sequencing is to start with the high-priority items—each one removes blind spots or jank that affects every raid—and then fold in the medium items during routine refactors. The low-priority UX change can ride alongside any future menu updates.
