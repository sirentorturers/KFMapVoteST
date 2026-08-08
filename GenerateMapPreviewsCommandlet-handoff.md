# Handoff: GenerateMapPreviewsCommandlet (metadata scaffolding tool)

## What it is

`KFMapVoteST/Classes/GenerateMapPreviewsCommandlet.uc` - an offline `ucc`
commandlet that scaffolds `KFMapVoteST/Configs/KFMapVotePreviews.ini` by
reading `Author`/`PlayerCountMin`/`PlayerCountMax` for every locally
installed map via `CacheManager.GetMapList()` (the same native map cache
`KFMapVoteFooterX.UpdateMapPreview()` already uses as a fallback), and
writing/updating one `KFMapPreviewEntry` `PerObjectConfig` section per map
via `SaveConfig()`.

It deliberately does **not** touch `TextureRef` (new entries are left
blank, existing ones are preserved untouched) - that field has to point
into a separate shared texture package (see "Broader context" below), which
this commandlet has no way to build. Instead, for every map missing a
`TextureRef`, it logs a checklist line naming that map's own native
`ScreenshotRef`, so you know what to go export/re-import next. Reruns only
show what's still outstanding.

## How to run it

From the game's `System/` folder, on a machine whose `Maps/` folder
actually has the maps you want covered (your own dev machine - **not** a
player's client; that's the whole point, see below):

```
ucc make
ucc KFMapVoteST.GenerateMapPreviewsCommandlet
```

Console output shows a summary count plus one `NEEDS TEXTURE - <map> ->
export '<ScreenshotRef>' ...` line per map still missing a `TextureRef`.
`KFMapVoteST/Configs/KFMapVotePreviews.ini` gets updated in place.

## Status as of this handoff

Written and believed syntactically correct (mirrors proven patterns
elsewhere in this codebase - `KFGameConfigEntry`'s `PerObjectConfig`
usage, `CacheManager.GetMapList()` calls already live in
`KFMapVoteFooterX.uc`) but **not yet actually run/compiled** - no `ucc`
available in the environment that built it. Next step for whoever picks
this up: compile (`ucc make`), run it, and confirm:
- It finds/writes entries at all (sanity check the resulting ini).
- `SaveConfig()` actually merges rather than clobbering pre-existing
  hand-edited entries (e.g. a `TextureRef` set by hand) - re-run it twice
  in a row on the same map set and diff the ini to be sure.

## Broader context (why this exists)

KF1 only downloads a map's package when a client actually travels to it -
never just for browsing the vote menu - so a map's own embedded
screenshot/author/player-count (via `LevelSummary`, or via
`CacheManager`'s cache, which is itself built from locally installed
files) is only readable for maps a given client has already played.
Confirmed via client log: both lookups fail identically
(`Can't find file for package '<MapName>'`) for any never-played map.

The fix in progress: `KFMapPreviewEntry` (`PerObjectConfig`,
`KFMapVotePreviews.ini`) lets an admin override the screenshot/author/
player-count per map with a reference into a **shared texture package**
bundled with the mod itself (like `KFAnnounc.uax` already is), so every
connecting client has it regardless of their own local map cache.
`KFMapVoteFooterX.UpdateMapPreview()` tries this override first, before
falling back to the two client-local sources.

This commandlet only automates the metadata half (Author/PlayerCount,
which don't need the shared package at all - they're just numbers/text).
The texture half - actually exporting each map's screenshot image and
importing it into the shared package - was going to use UE2's
`ucc batchexport`/`batchimport` commandlets, not yet drafted/tested.

**As of this handoff, an end-to-end test of the whole override mechanism
(hand-built ini entry + hand-imported texture) failed in-game** - see the
active conversation for log-based diagnosis in progress. That's a
separate, more urgent thread than this commandlet - this file exists so
the commandlet work specifically isn't lost track of while that gets
sorted out.
