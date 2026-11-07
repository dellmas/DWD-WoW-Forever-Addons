DWD RankUp - Forever
Version 1.3.0-forever.2 | WoW Forever 1.60.1 (interface 16001)
Author: dellmas / Dog Water Development

Install DWD_RankUp-Forever in _forever_/Interface/AddOns, then restart WoW if
this new addon folder was installed while the game was running.

WHAT IT DOES
1. Upgrades lower-rank spell actions to the highest learned rank of that spell.
2. Adds brand-new active abilities to the first empty visible action button when learned.
   Auto-add defaults to ON. A new rank of an existing ability is not treated as
   a brand-new ability, so it does not add duplicate buttons.

Login and manual scans only upgrade ranks. They do not fill the bars with your
already-known spells. Passive abilities, future/unlearned spells, off-spec
spellbook entries, macros and items are not auto-added or rewritten.

Works through WoW action slots, including slots displayed by Bartender. New
abilities now use empty visible action buttons by default, resolving the button's
current stance/bar page instead of assuming that visual button 3 means raw slot 3.
Warrior stance pages can display a different set of underlying action slots.
Rank upgrades still scan action slots 1-120. The optional slots FIRST LAST command
uses an explicit raw-slot range, which can include hidden bars; use visible to
return to automatic visible-button placement. Previously narrowed ranges are
retained. The old default range 1-120 becomes visible placement.

If an earlier version placed a learned ability on a hidden page, use:
/dwdrank place Battle Shout
This copies that learned active ability onto an empty visible button. It leaves
other pages alone, never fills all your bars, and works with automatic add turned
off. Existing visible copies are not duplicated. An unavailable visible slot
queues the request; show a bar or free a button, then use /dwdrank update.

COMMANDS
/dwdrank                  Show help.
/dwdrank status           Show version, settings, pending count and API status.
/dwdrank add on           Automatically add newly learned active abilities.
/dwdrank add off          Upgrade ranks without adding new buttons.
/dwdrank update           Upgrade existing spell actions now; no new add jobs.
/dwdrank on               Enable automatic behavior.
/dwdrank off              Disable it and cancel pending additions.
/dwdrank visible          Use empty visible buttons, following stance/bar paging.
/dwdrank slots FIRST LAST Use an explicit raw action-slot range (1-120).
/dwdrank place SPELL NAME Place one already learned active ability on a visible bar.
/dwdrank debug            Toggle diagnostic scan messages.

The addon waits until combat ends and your cursor is empty. It rebuilds plans
from the current spellbook and rechecks slots before changing them. If bars
are full, learned abilities wait until a slot is freed during this session.
If the client blocks placement, it stops retrying and reports the reason;
use /dwdrank update to retry out of combat with an empty cursor.

Only spell ranks that can be identified safely are upgraded. Missing spell
data or secret/restricted values are not guessed. An incomplete initial
spellbook never becomes an empty baseline that would cause mass auto-fill.

Preferences are saved separately for each character in an account-level
Forever store, avoiding unreliable physical per-character SavedVariables
restoration. The original Classic Era addon and its settings are unchanged.
The ZIP includes no character data or saved settings. Disable any other copy
of RankUp in the same game instance to avoid overlapping automation.
