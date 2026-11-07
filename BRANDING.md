# DWD addon branding

All current DWD projects share the existing Dog Water Development logo.
`branding/DogWater.jpg` is the public CurseForge logo; `branding/DWDLogo.tga`
is a pixel-preserving RGB conversion for WoW. Each addon carries an identical
root `DWDLogo.tga` and references it through its TOC `IconTexture` field, so
each addon remains independent of the other DWD addons.

Use these display names in CurseForge and the in-game addon list:

- DWD Mob Kill Counter
- DWD Party Highlight
- DWD RankUp
- DWD Tooltip Mover
- DWD Party XP
- DWD Bagnon Helper

Do not append Bars, a game name or a version to these display names. Release
display names append the version, and upload ZIPs use `DWD-Component-version.zip`.
Keep established addon folder names, SavedVariables names and CurseForge project
IDs stable to preserve recognition, settings, dependencies and update history.
Existing project URL slugs are retained so old links keep working.

Branding changes update TOC metadata and logo assets, without changing Lua code.
Do not restore retired Profiles addons or include personal settings in releases.
