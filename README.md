# WoW Forever Addon Pack

An addon pack for **World of Warcraft: Forever**, with 25 addon folders, DWD custom
addons, optional Main1/Main2 UI layouts, Questie and QuestieDB, and the DWD/Plater
profile restore fixes. For Forever 1.60.1 (interface 16001).

**[Download the latest WoW Forever addon ZIP](https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest/download/DWD-Forever-Addons.zip)**

[Latest release notes](https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest)

The download is public. No GitHub account or invitation is required.
Download the addon ZIP, rather than GitHub's automatic Source code archives.

## DWD Auto Updater (v1.0.4)

**[Download DWDAddonUpdater.exe](https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest/download/DWDAddonUpdater.exe)**

Run it, choose your `_forever_` folder, then click **Install / Enable Auto Updates**.
**Update Now** installs immediately even while WoW is running. Follow the app's
`/reload` instruction, or restart when files were added/removed. Background checks
run at sign-in and every 30 minutes; automatic installs wait until WoW closes.

Only DWD addons are managed. CurseForge addons, Bartender4_Forever and WTF settings
are left alone. No Python installation or GitHub login is needed.
[Updater instructions and source](updater/README.txt).

## Current addon fix (v1.0.5)

Fix MobCount triggering a secret-aura access error through GameTooltip.RefreshData.

MobCount no longer asks Blizzard to rebuild the shared tooltip after a kill.
The tooltip can switch from a unit to an aura between the kill event and the
deferred callback, causing a protected aura read from tainted addon code.
Kill totals now appear only during Blizzard's natural unit-tooltip processing.
Counts still update immediately in the database; the displayed tooltip total
updates on its next native rebuild or when the unit is hovered again.

DWD MobCount version: 0.0.1-forever.22. The regression test credits a kill with
an aura tooltip present, verifies no forced or deferred rebuild, prevents
duplicate credit, and verifies the next unit tooltip shows the updated total.


## Installation and commands

```text
DWD Forever Addon Pack v1.0.4 - 2026-11-05

For World of Warcraft: Forever 1.60.1 (interface 16001).

INSTALL
1. Fully close World of Warcraft.
2. Back up your existing Interface/AddOns and WTF folders if you use addons.
3. Copy the folders INSIDE this pack's AddOns folder into:
   World of Warcraft/_forever_/Interface/AddOns/
   Example: .../Interface/AddOns/Questie/Questie_Forever.toc
4. Start WoW, open AddOns and enable the included addons and their dependencies.
   Both Questie and QuestieDB are included and must be enabled.
5. Log in and choose one of the included UI layouts:
   /dwdpro load Main1
   /reload
   Or substitute Main2 for Main1.
6. To save your changes under your own named layout:
   /dwdpro save MyLayout

USEFUL COMMANDS
/dwdpro status     - show selected profile and early restore status
/dwdpro audit      - check the active profile against loaded settings
/dwdxp config     - Party XP settings
/dwdxp sync       - request fresh party XP
/dwdxp status     - show party XP send/receive diagnostics
/dwdmc config     - MobCount tooltip settings
/ttmove           - Tooltip Mover commands
/bt4              - custom Bartender settings
/plater           - nameplate settings
/questie          - quest helper settings

NOTES
Party XP 1.4.12 fixes XP matching across different internal realms/phases.
Both players should update, /reload, and run /dwdxp sync.
Includes the DWD profile/Plater-default fixes, QuestieDB, and the fix that
prevents profile restores from replacing Questie settings windows.
After updating existing addon folders, /reload recreates any damaged windows.
The shareable copy uses portable native SavedVariables, without junctions,
the original PC's account folders, WTF files, live kill counts or error logs.
Main1 and Main2 are optional UI layouts; they do not select a character for you.
Party members need the Party XP addon on their own clients to exchange XP data.
Screen size and resolution can affect where the imported windows appear.
Keep the custom Bartender4_Forever folder; do not enable a second Bartender
installation alongside it. Third-party files retain their original notices.

PUBLIC DOWNLOAD
https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest/download/DWD-Forever-Addons.zip
No GitHub sign-in or invitation is required.

DWD AUTO UPDATER (WINDOWS)
Download DWDAddonUpdater.exe from this repository's latest release.
Run it, select the _forever_ folder, and click Install / Enable Auto Updates.
No Python installation or GitHub login is needed.
Update Now installs DWD updates immediately, even with WoW running. Follow
the app's /reload instruction; added/removed files require a full restart.
Automatic checks run at Windows sign-in and every 30 minutes. When playing,
automatic updates are staged until all WoW clients close. Update Now applies
them on request. The updater never closes WoW.
Only DWD addons already installed (plus DWD Updater Status) are managed.
CurseForge addons, Bartender4_Forever and WTF settings are not touched.
Updates include verified checksums, retained backups and interrupted-install
recovery. Windows app/logs: %LOCALAPPDATA%/DWDAddonUpdater.
Backups: _forever_/Interface/DWDUpdaterBackups.
Disable Auto Updates removes the startup shortcuts and stops the background
watcher. Your addons, settings, updater files and backups remain available.
/dwdupdate shows the DWD release loaded in WoW; it cannot download files itself.
```

Original addon author and license notices are retained inside the ZIP.
