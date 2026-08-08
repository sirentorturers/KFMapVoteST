# Handoff: GenerateMapPreviewsCommandlet (metadata + texture-manifest tool)

## What it is

`KFMapVoteST/Classes/GenerateMapPreviewsCommandlet.uc` - an offline `ucc`
commandlet that scaffolds `KFMapVoteST/Configs/KFMapVotePreviews.ini` by
reading `Author`/`IdealPlayerCountMin`/`IdealPlayerCountMax`/`Screenshot`
straight off each map's own `LevelSummary` object (loaded directly by name
via `DynamicLoadObject(MapName$".LevelSummary", class'LevelSummary',
true)`), and writing/updating one `KFMapPreviewEntry` `PerObjectConfig`
section per map via `SaveConfig()`.

**2026-08-08 update: switched off `CacheManager.GetMapList()` entirely.**
First real test run (`ucc KFMapVoteST.GenerateMapPreviewsCommandlet`)
returned "found 0 locally cached maps" even with maps correctly sitting in
`Maps/` and `Paths=../Maps/*.rom` correctly registered in
`System/KillingFloor.ini`'s `[Core.System]` section (verified directly -
that was not the bug). Root cause, found by reading
`System/CacheRecords.ucl` directly: `CacheManager` reads a *persisted
native cache database*, not a live directory scan, and that file - dated
Dec 8 2013, 1.3KB - contains exactly 7 stock `Announcer=`/`Crosshair=`/
`Mutator=` entries and **zero `Map=` entries**, ever. The usual fix
(UnrealEd's Content Browser "recache" action) doesn't exist in this
project's UnrealEd build either (confirmed by the user). So this
commandlet now bypasses `CacheManager` completely for its own map
enumeration - see "How it enumerates maps now" below. Whether
`CacheManager` works correctly for `KFMapVoteFooterX`'s client-side
fallback on an actual live client (a separate, already-shipped code path,
not touched here) is unrelated and unconfirmed either way.

## How it enumerates maps now

`MapListEntry.uc` is a bare `PerObjectConfig` marker class
(`Config(KFMapVoteSTMapList)`) with no fields - only its section name (a
map filename, no extension) matters. `generate_map_list.sh` (at the
`KFMapVoteST/` package root) lists `../Maps/*.rom` and regenerates
`Configs/KFMapVoteSTMapList.ini` with one `[<MapName> MapListEntry]`
section per file. The commandlet then calls
`GetPerObjectNames("KFMapVoteSTMapList", "MapListEntry", 1024)` to get the
map name list - the same proven `GetPerObjectNames` pattern
`KFVotingHandler.BuildGameConfig()` already uses for `KFMapVoteModes.ini`.

**Run `generate_map_list.sh` again any time `Maps/` changes** (already run
once against this repo's current 214-map `Maps/` folder as of this
handoff - `Configs/KFMapVoteSTMapList.ini` is current). It's a plain shell
script (`sh`, no bash-only features), safe to run on macOS/Linux; if the
commandlet itself only ever runs on Windows/Wine, just re-run this script
from a Mac/Linux checkout of the same repo before copying `Configs/` over,
or port the one-liner loop to PowerShell/batch if you'd rather generate it
directly on the Windows box.

It deliberately does **not** touch `TextureRef` (new entries are left
blank, existing ones are preserved untouched) - that field has to point
into a separate shared texture package (see "Broader context" below), which
this commandlet has no way to build (no native "export object to image
file" call exists in UnrealScript at all - see "Texture pipeline design"
below). Instead, for every map missing a `TextureRef`, it now resolves and
logs a `PREVIEWMANIFEST` line naming the actual exportable Texture
object(s) for that map - not just the raw `ScreenshotRef`, which is typed
`Material` and is very often *not* itself a `Texture` (see
`ResolveScreenshotTexture()`'s doc comment in the .uc for why). Reruns
only show what's still outstanding.

## How to run it

From the game's `System/` folder, on a machine whose `Maps/` folder
actually has the maps you want covered (your own dev machine - **not** a
player's client; that's the whole point, see below):

```
./generate_map_list.sh   # only if Maps/ changed since the last run
ucc make
ucc KFMapVoteST.GenerateMapPreviewsCommandlet
```

Console output shows a summary count plus one line per map still missing a
`TextureRef`, in this format:

```
PREVIEWMANIFEST|<MapName>|<Status>|<Frame1>;<Frame2>;...|src=<raw Screenshot reference>
```

- `Status` is `OK`, `OK+ANIMATED(n)` (an `n`-frame `AnimNext` flipbook
  chain), `PROCEDURAL` (resolved to a `FireTexture`/`WaterTexture`/etc. -
  no fixed image, needs a human to pick a real screenshot instead), or
  `UNSUPPORTED(...)` (no exportable bitmap at all, or the reference didn't
  load - the parenthesized detail says which).
- The frame list (when `Status` starts with `OK`) is the fully-qualified
  `Package.Group.Name` of every frame, in `AnimNext` order - this is what
  Phase 2 (see below) will hand to `ucc batchexport`.

`KFMapVoteST/Configs/KFMapVotePreviews.ini` gets updated in place as
before.

## 2026-08-08: first successful run, MaterialSequence discovery

First real run against all 214 maps: 202 metadata entries written, 185
still needing a `TextureRef`, 12 maps failed to load entirely (all 12 are
genuine missing-dependency content problems, not commandlet bugs - e.g.
`Warning: Failed to load 'BoardwalkVehicles': Can't find file for package
'BoardwalkVehicles'` for `KF-Boardwalk` - some referenced package isn't
present in this checkout's `Maps`/`Textures`/etc; nothing to fix here,
just missing content).

Of the 185 `TextureRef`-needed maps, the large majority came back
`UNSUPPORTED(broken modifier chain)` - including `KF-Aperture` and
`KF-AbusementPark`, both known to have animated previews. Root cause: a
second, distinct animation mechanism neither of us had accounted for.
Confirmed from source (`Engine/Classes/MaterialSequence.uc`):
`MaterialSequence extends Modifier` but never populates the inherited
`.Material` field - its frames live in a separate `SequenceItems` array
(`array<MaterialSequenceItem>`, each with its own `.Material`, `.Time`,
`.Action`) - a slideshow/crossfade mechanism, not the `AnimNext` flipbook
chain `KF-Corruption-nmm`/`KF-ThelongDarkRoad` correctly resolved as
`OK+ANIMATED(n)` on the first run. It turned out to be the *common* case
in this map pool, not a rare one.

Fixed by replacing the single-`Texture`-returning `ResolveScreenshotTexture()`
with `ResolveScreenshotFrames()`/`ResolveMaterialFrames()` (recursive,
`array<Texture>` out param), which now handles both mechanisms - and
recurses into each `MaterialSequence` slide's own `Material` in case a
slide is itself `TexModifier`-wrapped or an `AnimNext` chain.

**Re-run confirmed the fix**: all 185 `TextureRef`-needed maps now resolve
`OK`/`OK+ANIMATED(n)` - zero `UNSUPPORTED`/`PROCEDURAL`/`MISSING` results
left anywhere in the 214-map pool. The only non-`OK` outcomes are the same
12 genuinely-missing-content `SKIP`s from the first run (unrelated to
resolution logic).

That same run surfaced one more bug, also fixed: `MaterialSequence` slides
are very commonly authored as a `(FadeToMaterial, ShowMaterial)` pair
referencing the *same* `Material` back-to-back (a fade transition into a
hold) - e.g. `KF-Barzakh`'s real 4-image loop came back as 8 frames, each
one adjacent-duplicated (`0;1;1;2;2;3;3;0`). Dedup previously only
happened within one `Texture`'s own `AnimNext` walk; now
`ResolveMaterialFrames()`'s leaf-`Texture` branch checks the whole map's
`OutFrames` list (not just its own local chain) before appending, so
repeated slides collapse to one frame.

**Re-run confirmed this fix too**: same totals (202/185/12), but every
`OK+ANIMATED(n)` frame list is now clean - `KF-Barzakh` -> `0;1;2;3` (was
`0;1;1;2;2;3;3;0`), `KF-ScrapHeap-ST` -> `OK+ANIMATED(6)` (was `(12)`),
`KF-Aperture`/`KF-AbusementPark` -> `OK+ANIMATED(3)` with unique frames.
Plain-`AnimNext` maps like `KF-ThelongDarkRoad` were unaffected as
expected. **Phase 1 (metadata + manifest) is done and verified
end-to-end.** Next up is Phase 2 - a real `ucc batchexport` test against
a single map (see "Texture pipeline design" below).

Also confirmed the hard way: `Config`/`PerObjectConfig` ini files
(`KFMapVoteSTMapList.ini`, `KFMapVotePreviews.ini`) are **always** read
from `System/`, never from `KFMapVoteST/Configs/` directly - the `Configs/`
copies in the repo are source-of-truth for version control only and must
be copied into `System/` before running `ucc`. Same for `.ucl` cache
records, per the `CacheManager` investigation above.

## Status as of this handoff

**Metadata half + manifest resolution are written, grounded in real SDK
source** (`Engine/Classes/Texture.uc`, `Material.uc`, `Modifier.uc`,
`TexModifier.uc`, `MaterialSequence.uc`, `LevelSummary.uc`,
`Core/Classes/Object.uc`, `Core/Classes/Commandlet.uc` - all pulled and
read directly, not guessed), **and confirmed working end-to-end against
real `ucc` runs** (three iterations - `CacheManager` dead end ->
`LevelSummary`-based rewrite -> `MaterialSequence` discovery -> dedup fix
- each verified against actual console/log output, not assumed). Final
state: 202/214 maps get metadata written, 185 need a `TextureRef` and all
185 resolve a clean `PREVIEWMANIFEST` line (`OK` or `OK+ANIMATED(n)`,
zero `UNSUPPORTED`/`PROCEDURAL`/`MISSING`), 12 fail to load due to
genuine missing-content dependencies unrelated to this commandlet.

Still worth spot-checking if picked back up later:
- `SaveConfig()` actually merges rather than clobbering pre-existing
  hand-edited entries (e.g. a `TextureRef` set by hand) - re-run twice in
  a row on the same map set and diff the ini to be sure (not yet
  explicitly tested, though the `KFGameConfigEntry` pattern this mirrors
  is already proven in production for `KFMapVoteModes.ini`).

## Texture pipeline design (Phases 2-3, not yet built)

Deliberately **not written yet** - picked up 2026-08-08, paused here on
purpose pending real `ucc` access (this dev environment has no
`ucc.exe`/Wine, so none of this can be tested/iterated blind). Two open
questions to resolve with real `ucc` output before writing Phase 2/3:

1. **`ucc batchexport`/`batchimport` exact syntax and behavior** - output
   file naming convention, whether the trailing `Package.Group` filter
   arg actually scopes to one object instead of exporting every `Texture`
   in the whole map package, and whether animated `AnimNext` frames (each
   a separate named `Texture` object per the manifest above) export as
   separate files individually addressable by name. Plan: run one manual
   `ucc batchexport <MapPackage> Texture pcx <dir>` against a single map
   and inspect the real output before scripting this.
2. **DXT1 compression.** Confirmed from source: `Texture.Format`
   (`BitmapMaterial.uc`) is declared `const editconst` - **UnrealScript
   cannot set it at runtime**, so our commandlet can never force DXT1
   compression itself. Two candidate routes, in preference order:
   - Pre-compress with ImageMagick (`magick`/`convert`, available in this
     dev environment) into a real DXT1-compressed `.dds` (BC1 block
     data - the same on-disk format UE's internal DXT1 Mips use) *before*
     import, then see whether this SDK's `ucc batchimport`/UnrealEd
     texture import recognizes `.dds` and imports it already-compressed
     (native import code setting `Format`, not UnrealScript - this would
     sidestep the `const` restriction entirely). Unverified whether this
     specific KF1 SDK build's import path supports DDS at all.
   - Fallback: import everything uncompressed via `batchimport`, then do
     **one manual** "Compress All Textures" pass over the whole finished
     `KFMapVoteST_Previews.utx` package in UnrealEd before shipping it -
     simple, low-risk, a single one-time step regardless of map count.
3. **Resize to \<=512x256.** ImageMagick handles this fine once frames are
   exported (maintain aspect ratio, land on a power-of-two size like
   512x256/256x256/512x128/etc. - UE2 textures expect power-of-two
   dimensions). Not blocked on `ucc` access, just sequenced after export
   since it operates on `ucc batchexport`'s output.

Once real `ucc batchexport` output from a single test map is available,
the next step is writing the Phase 2 script (export -> resize/DXT1-prep -
most likely a bash script per this project's existing Pi-automation
convention of preferring shell scripts) and the Phase 3 `batchimport` +
compression step.

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
