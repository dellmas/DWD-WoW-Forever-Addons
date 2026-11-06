# WoW Forever Addon Pack

A CurseForge-recognized addon pack for **World of Warcraft: Forever 1.60.1**
(interface 16001). Version **v1.0.7** contains **27 addon folders from 21
CurseForge projects**, including official Bartender4, Questie, QuestieDB, and
all six DWD addons. Bundled modules appear under their parent project.

**[Download the addon ZIP](https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest/download/DWD-Forever-Addons.zip)**

[Release notes](https://github.com/dellmas/DWD-WoW-Forever-Addons/releases/latest)
| [Installation instructions](INSTALL.txt)
| [Addon versions](ADDON-VERSIONS.json)
| [CurseForge projects and file hashes](CURSEFORGE-PROJECTS.json)

The download is public and requires no GitHub account. Download the release
ZIP above; GitHub's automatic Source code archives do not contain the pack.

## Let CurseForge monitor updates

1. Close WoW and back up your `Interface/AddOns` and `WTF` folders.
2. Replace each included addon folder with its clean copy from `AddOns` in
   the ZIP. Move previous folders into a backup outside `Interface/AddOns`
   first so leftover beta files do not interfere with recognition.
3. If present, also archive `Bartender4_Forever`, `DWD_Profiles_Recovery`, and
   `DWD_UpdaterStatus`. They are not part of this pack. Official `Bartender4`
   replaces the beta port; the beta layout requires a separate settings
   migration before switching. Never enable both Bartender copies.
4. In CurseForge, select **World of Warcraft > Forever**, then open the
   three-dot menu beside Run Game and choose **Scan addons folder > Scan**.
5. Check **My Addons**. This collection was recognized as 21 projects on the
   source installation. Approval/indexing can affect detection elsewhere;
   refresh or rescan after processing completes.

The addon files are unchanged copies of their CurseForge release archives.
Original author and license notices are retained. The version and provenance
manifests identify every packaged file; no local compatibility patches are
applied to third-party addons.

## Current fix: TomTom profile restores

DWD Profiles 1.0.30 and early loader 1.0.8 preserve TomTom's initialized
defaults when restoring sparse saved layouts. This prevents the missing
coordinate-block update interval from causing errors every frame. TomTom's
files and personal saved settings are unchanged. Reload after updating.

## Settings

The ZIP contains no `WTF`, account data, personal saved settings, bundled
Main1/Main2 layouts, filesystem junctions, or error logs. Leave your own `WTF`
folder intact. Existing personal DWD profiles stay in your SavedVariables.
This download does not migrate layouts from the old beta Bartender database.

## DWD addons

- DWD Mob Kill Counter: unit-tooltip kill counts, including the aura-taint fix.
- Party XP Bars: party XP exchange and sync diagnostics.
- DWD Tooltip Mover: configurable tooltip positioning.
- DWD Profiles and its bundled early loader: save and restore your own layouts.
- DWD Party Highlight: party target and friendly nameplate decorations.
- DWD RankUp: rank upgrades and newly learned active abilities on action slots.

Use `/dwdpro`, `/dwdxp`, `/dwdmc`, `/ttmove`, and `/dwdrank` for help.
Enable both Questie and QuestieDB. Restart or reload WoW after an update as
required; a reload cannot discover a newly installed addon folder.

## Older DWD desktop updater

Use CurseForge for this pack. If the old DWD desktop updater is enabled, click
**Disable Auto Updates** before switching so both tools do not replace the
same folders. Disabling startup retains addon settings and backups.

The legacy source and compatibility release assets remain available for
existing installations. That updater has a fixed allowlist and does not manage
all addons in this pack. See [legacy updater notes](updater/README.txt).
