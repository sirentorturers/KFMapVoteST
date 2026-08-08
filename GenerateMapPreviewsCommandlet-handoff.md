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

## Texture pipeline: confirmed findings (2026-08-08, real ucc testing)

Tested live against real `ucc` on the user's Windows/Wine box (this dev
environment still has no `ucc.exe` itself - every finding below came from
the user running a command and pasting/attaching `UCC.log`, not from
guessing). Using `KF-Aperture` as the test map throughout
(`kfportal_preview` -> `MaterialSequence` -> 3 slides).

**Export - `ucc batchexport` works, DDS is the format to use.**
`ucc batchexport KF-Aperture Texture pcx exported` (run from `System/`)
exports every `Texture` in the whole map package (not just the ones named
in a `PREVIEWMANIFEST` line - a Phase 2 script needs to filter the output
down to the wanted filenames) as `<Group>.<Name>.<ext>` flat files. PCX
export **silently produces empty (0-byte) files** for any texture whose
source is already DXT-compressed (which is nearly all of them) - only
succeeded for the one uncompressed source texture in the test package.
Re-running with `dds` as the export extension instead worked for
everything: `ucc batchexport KF-Aperture Texture dds exported`. Manually
parsed the resulting `.dds` headers (`identify`/ImageMagick can't read
them - see below) and confirmed the actual screenshot textures
(`kfportalpreview01/02/03`) come out already **512x256, DXT1, 10 mips** -
already meeting spec, no resize/recompress needed for these at least. The
other files `batchexport` swept up incidentally ranged up to 1024x1024 in
DXT3/DXT5 - unrelated level-ambient textures, not preview images, to be
filtered out.

**ucc's DDS writer is non-spec-conformant.** Parsed the raw header bytes:
`ddspf.dwSize` and `ddspf.dwFlags` are both left `0` instead of the
required `32`/`DDPF_FOURCC`, even though the `DXT1`/`DXT3`/`DXT5` fourCC
bytes themselves are present and correct at the right offset. This is why
ImageMagick's `identify`/`dds:` coder rejects these files
("improper image header") even though the pixel data is intact -
patching those two fields would very likely fix that if ImageMagick ever
needs to read one (not required for the working pipeline below, but
worth remembering if DXT1 compression of an *oversized* texture is ever
needed and ImageMagick has to decode/resize/re-encode a `.dds`).

**Import - `ucc batchimport` does not exist in this SDK build**
(`ucc batchimport ...` -> "Commandlet batchimport not found"). Nothing
registered under that name in `Editor.int`'s `[Public]` section.
`Editor.int` *does* register `PkgCommandlet`
(`HelpUsage="pkg [import/export] [texture/sound] [packagename]
[directory]"`), which looked promising but turned out to be dead/broken
in this specific compiled build (Apr 2016) - every variant tried (DDS,
PCX, flat files, nested group folders, `System/`-relative,
repo-root-relative) produced the byte-identical failure
(`ExecWarning: Missing filename`, no package ever written), regardless of
source format or directory layout. **Do not spend more time on
`PkgCommandlet` in this build.**

**What actually works: `Editor.BatchImportCommandlet`, fully qualified.**
Not listed in `Editor.int`'s `[Public]` section either (hence the
`batchimport` short-name failure), but it's a real native class
compiled into `Editor.dll`, callable by its fully-qualified name per
`Commandlet.uc`'s own doc comment (unlisted commandlets still work via
`ucc Package.ClassName`). Confirmed working syntax, run from `System/`:

```
ucc Editor.BatchImportCommandlet .\KFPreviewTest.utx Texture ..\exported_test\*.dds
```

Two things this needed to actually work, both confirmed the hard way:
- The **package filename must include a path component** (`.\Name.utx`,
  not a bare `Name.utx`) - a bare filename fails with
  "Package should contain a path reference".
- The **source directory must be given relative to the repo root**
  (a sibling of `System/`), not relative to `System/` itself, even
  though `ucc.exe` itself runs from `System/` - e.g. `..\exported_test`
  worked, `exported_test` (meaning `System\exported_test`) did not.
  (`PkgCommandlet`'s failures were *not* explained by this, in hindsight
  - it failed identically regardless of directory location, per above.)

Source doc:
[BatchImportCommandlet](https://beyondunrealwiki.github.io/pages/batchimportcommandlet.html) -
confirms `Texture` accepts PCX/BMP/TGA/DDS, and that imported objects use
"the filename without extension as the object name."

**Animated textures: automatic via filename convention, confirmed
working.** Per
[UnrealWiki: Animated Texture](https://beyondunrealwiki.github.io/pages/animated-texture.html),
naming frame files `<BaseName>_a00.ext`, `<BaseName>_a01.ext`, etc. (the
numbers don't need to start at 0) triggers automatic `Texture.AnimNext`
chain-linking on import - and this **is not GUI-only**, it fired through
`BatchImportCommandlet` too. Renamed the 3 `kfportalpreview*.dds` exports
to `kfportalpreview_a01/02/03.dds` and re-ran the same
`BatchImportCommandlet` invocation above; the user confirmed in the
editor that `AnimNext` was already linked with zero manual setup.

**DXT1 compression is still unresolved/untested** - `BatchImportCommandlet`
imports with "default settings" per its own docs (no per-file property
override, no `.props` companion file support - confirmed by re-checking
the same doc page), so whether it preserves the DDS source's DXT1
compression on import, or decompresses to something else, hasn't been
checked yet. Next step when this is picked back up: inspect an imported
texture's `Format` property in the editor (the user already has
`KFPreviewTest.utx` open) and confirm it reads `TEXF_DXT1`, not something
else.

## Animation frame rate: solved without touching the asset at all

First real in-editor test of the auto-linked `AnimNext` chain played
back far too fast (flickering). `MinFrameRate`/`MaxFrameRate`
(`Texture.uc`) are the relevant fields, and - unlike `Format` - they're
plain `var(Animation) float`, **not** `const`. But the same packaging
problem as DXT1 applies: no scriptable way to edit-then-resave an
already-imported `.utx` with this SDK's tooling (no `Commandlet`-callable
`SavePackage`, no `PkgCommandlet`, `BatchImportCommandlet` has no
property overrides).

The user's idea, which sidesteps the whole problem: make it a
server-admin-configurable **runtime** setting instead of a baked-in
asset property. `MinFrameRate`/`MaxFrameRate` are read live by the
engine's texture-animation tick every frame, so a client can just set
them on the loaded `Texture` object at display time - no package edit,
no re-save, ever. Implemented 2026-08-08, mirroring `bShowMapLike`'s
already-proven config -> spawn-copy -> replicate pattern exactly (a
single scalar replicated once at `bNetInitial` - deliberately *not* the
new-array-property shape that crashed the server previously, see
CLAUDE.md):

- `KFVotingHandler.PreviewAnimFrameRate` (`var config float`, default
  `1.0`, documented in `Configs/KFMapVote.ini`) - admin sets this per
  server.
- Copied into each player's `KFVotingReplicationInfo` in
  `AddMapVoteReplicationInfo()`, replicated once at `bNetInitial`
  alongside `bShowMapLike` (same replication statement, one more
  scalar - not a new statement, not an array).
- `KFMapVoteFooterX.ApplyPreviewAnimRate()` - called from
  `UpdateMapPreview()` right before the resolved `Screenie` is assigned
  to `i_MapPreview.Image`. Walks the texture's `AnimNext` chain (cycle-
  guarded the same way `GenerateMapPreviewsCommandlet`'s own walk is)
  and sets `MinFrameRate`/`MaxFrameRate` on every frame from the
  replicated value, falling back to `1.0` if `VoteReplicationInfo` isn't
  available yet or the replicated value is `<= 0`.

**Not yet compiled/tested** - written this session, needs `ucc make` +
an in-game check that playback speed now tracks `KFMapVote.ini`'s
`PreviewAnimFrameRate` value.

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
