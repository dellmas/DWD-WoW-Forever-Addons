DWD Party Highlight - Forever
Version 2.0.0-forever.1 | WoW Forever 1.60.1 (interface 16001)
Author: dellmas / Dog Water Development

Install the DWD_PartyHighlight-Forever folder in _forever_/Interface/AddOns.
Restart WoW if it was running when this new addon folder was installed.

/dwdph          Open settings (also accepts the old /dwdpth alias).
/dwdph preview  Show the settings panel with two live sample nameplates.
/dwdph status   Print party / decorated-plate / skipped-plate counts.
/dwdph on|off   Enable or disable both types of decoration.
/dwdph refresh  Recheck the visible nameplates.

Target Markers: five arrow designs, separate markers for every member targeting
the same unit, P1-P4 colors, customizable labels, offsets, sizes, glow and pulse.

Party Members: Corners, Brackets, Frame, Diamond, Chevron, or None. Choose a
custom color, each party slot's color, or class color. Adjust width, height,
padding, line thickness, position, opacity and optional pulse.

Labels / Colors: add text above a party member's plate. Use {slot}, {name}, and
{role} in the default label or an individual P1-P4 override. Overrides and slot
colors follow the CURRENT party order, not a permanent character identity.
These are additional labels; they do not replace the player's original name.

Enable friendly PLAYER nameplates in WoW (normally Shift+V) to see party member
decorations. Plates must be visible and within the game's nameplate range.
An addon cannot show plates for a party member in another phase, or decorate
forbidden friendly plates in areas where Blizzard restricts them. Secret unit
identities are never compared, indexed or converted into ordinary values.

Supports standard nameplates and reads Plater's existing health bar region as
an anchor when available. Does not alter nameplate names, health bars, colors,
size, CVar settings, click behavior, unit targets, or other addons' functions.
Only this addon needs installing to view your party's markers; party members
do not need it installed to provide their targets.

Settings use the new SavedVariables name DWD_PartyHighlightForeverDB. The
Anniversary addon and its settings are left in place. No character data or
saved profiles are included in this ZIP. Settings are account-wide within
this WoW installation and use the Forever early-SavedVariables loading flag.
