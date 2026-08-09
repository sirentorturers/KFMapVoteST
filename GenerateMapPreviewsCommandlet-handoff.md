# Handoff: GenerateMapPreviewsCommandlet (metadata + texture-manifest tool)

**Status: Phase 1 (this commandlet) and Phase 2 (export/import
automation) are both built.** For the admin-facing how-to, see
`PREVIEW_PIPELINE.md` - that's the doc to follow for actually running
this end-to-end. Everything below is the dev history/rationale: why
things are built the way they are, and a record of what was tried and
didn't work, kept so nobody re-treads the same dead ends (`CacheManager`,
`PkgCommandlet` - both covered in detail further down).

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

**Confirmed working** - compiled and tested in-game; the user confirmed
playback speed now tracks `PreviewAnimFrameRate`.

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

This commandlet automates the metadata half (Author/PlayerCount, which
don't need the shared package at all - they're just numbers/text) and
resolves what the texture half needs. The texture half itself - actually
exporting each map's screenshot image(s) and importing them into the
shared package - is `Tools/Build-PreviewPackage.bat` (Phase 2, see below
and `PREVIEW_PIPELINE.md`).

## Phase 2 built: export/import automation + admin docs

**Environment discovery that shaped everything below: this project's
actual runtime is CrossOver** (a Wine-based Windows compatibility layer
on macOS - confirmed from the ConEmu prompt reading
`crossover@MACBOOK-PRO Z:\...`), not real Windows. `ucc.exe` and every
script here run under Wine's own reimplementation of `cmd.exe`, which is
missing/broken for several batch features real Windows `cmd.exe` has -
discovered the hard way, not anticipated in advance.

**Originally written as PowerShell** (`Build-PreviewPackage.ps1`) - the
user's first real attempt to run it
(`powershell -ExecutionPolicy Bypass -File ...`) silently returned to a
blank prompt with zero output, not even the script's own first
`Write-Host` line. Never conclusively root-caused (no `pwsh` available
in this dev environment to reproduce against; a local install was
offered and declined) but consistent with a parse-time error PowerShell
under Wine failed to surface. Switched to a plain `.bat` - no
execution-policy gate, nothing to unblock, and one less moving part to
debug blind.

**First `.bat` version also failed** - ran, but reported "No maps found"
despite the manifest existing and being freshly regenerated. Built a
diagnostic script (`DiagTest.bat`, since removed) to isolate the cause
rather than keep guessing, and confirmed directly against the real
environment:
- `%VAR:~start,length%` (substring) and `%VAR:search=replace%` - both
  silently return the literal modifier text instead of erroring, instead
  of doing the operation. This broke the original design's bracket-
  detection (`!LINE:~0,1!=="["`) completely - it never matched anything,
  so no section was ever recognized as a map header.
- `tokens=1,2,*` (three-plus token positions with a trailing wildcard) -
  the wildcard position came back empty.
- `tokens=1,*` with `.` as the delimiter specifically - came back empty,
  even though the *identical* pattern worked fine with `=` as the
  delimiter. Confirmed inconsistent per-delimiter-character, never fully
  root-caused beyond that.
- Confirmed working: `tokens=1,* delims==`, default space/tab
  tokenizing, `call set "x=%%name_!key!%%"` indirect/associative-array-
  style variable lookup, and plain `if "%%a%%"=="%%b%%"` literal string
  comparison.

**Redesigned the manifest format around only the confirmed-safe
primitives**, rather than trying to route around cmd.exe's gaps entirely
in batch:
- `KFPreviewFrameEntry.uc` replaces `KFPreviewExportEntry.uc` - one
  `PerObjectConfig` section per **frame** now (not per map), with flat
  `MapName`/`FrameCount`/`FrameIndex`/`RelRef` fields instead of a
  semicolon-joined `Frames` list. `RelRef` has the `"<MapName>."` prefix
  already stripped **in UnrealScript** (`Left()`/`Mid()`/`Len()`, all
  confirmed reliable - unlike cmd.exe's equivalents) via
  `GenerateMapPreviewsCommandlet`, so the batch script never needs to
  split on `.` or strip anything - every field it needs arrives already
  fully resolved, parseable with the single confirmed-safe
  `tokens=1,* delims==` split.
- `Tools/Build-PreviewPackage.bat` rewritten around this: single pass
  over the manifest (batchexport on each map's first frame, stage every
  frame, record success on the last frame), then the same bulk
  `BatchImportCommandlet` call as before, then a `TextureRef=` rewrite
  pass that matches each `KFMapVotePreviews.ini` section by
  *reconstructing* the expected `"[MapName KFMapPreviewEntry]"` header
  text from a known map name and comparing whole-line equality - rather
  than trying to extract the map name back out of a header line, which
  would have hit the same substring/bracket-delimiter problems again.

Full technical detail (including the "if this project ever moves to
real Windows" caveat - none of this is OS-conditional, the workarounds
just also happen to be harmless on real Windows) is in the script's own
header comment.

**First real run of this version (after recompiling and regenerating
the manifest, confirmed correctly in the new per-frame format - 446
`KFPreviewFrameEntry` sections) still reported "0 map(s) found."** The
manifest was fine; the bug was in the script. Root-caused with one more
targeted diagnostic rather than guessing: a `for /f "delims=="` split
that worked perfectly at the top level failed - and appeared to corrupt
parsing of the *rest* of the enclosing loop's iterations too - the
moment it was moved to be lexically nested inside another `for` loop's
body. Confirmed by direct A/B test (inlined vs. moved into a `call`ed
subroutine, otherwise identical) that a called subroutine sidesteps it
completely, even though it's still invoked from inside the outer loop.
Rewrote the script so every `KEY=VALUE` split goes through
`:ParseKV`/`:FindStagedMatch` subroutines instead of being inlined -
not a style choice, required for correctness in this environment. Full
detail in the script's own header comment.

**First real run against the full 185-map manifest: found all 185 maps,
export/staging worked, most textures imported cleanly - real progress,
but two new problems surfaced that only show up at this scale:**

1. **Some source textures export as 0-byte DDS files** - same root
   cause identified way earlier for PCX (a texture whose source isn't
   DXT-compressed silently produces an empty file instead of erroring),
   just showing up on the DDS side this time for a different subset of
   textures. These passed the script's `if not exist` check (the file
   *exists*, it's just empty) and then failed import with "Bad image
   format"/"Can't find file". Fixed: added a `:GetFileSize` check,
   0-byte exports are now skipped before staging with a clear warning.
2. **One texture (`KF-Chthon-SE`'s screenshot) crashed ucc outright** -
   `Assertion failed: MipmapSize <= Length`. Inspected the actual
   exported file directly (same Wine `Z:` filesystem access used
   throughout this project): 87520 bytes against an expected 87528 for
   a clean 512x256/10-mip DXT1 export - short by exactly one DXT1 block
   (8 bytes), meaning the header still claims 10 mips but the smallest
   mip's data is missing. Looks like a genuine `ucc batchexport` bug for
   certain textures, not something fixable on this project's side. The
   real problem this exposed: the script was calling
   `BatchImportCommandlet` **once for the whole 185-map batch**, so this
   one crash aborted ucc's own internal loop over the rest of the
   wildcard match list - every map that would have sorted alphabetically
   after `KF-Chthon-SE` silently never got imported at all, which is
   also why `TextureRef` updates initially came back as 0 for maps that
   *should* have succeeded.

Also fixed in the same pass, found by re-auditing rather than by another
failed run: `:FindStagedMatch` referenced its `%~1` parameter directly
inside a `for /f` loop body - a different, untested pattern from the one
actually confirmed safe (parameter used as the loop's *input*, not
referenced *inside* the loop). Changed to copy `%~1` into a
delayed-expansion variable before the loop, matching every other
comparison in the script, rather than assume an untested pattern is
fine given how many narrow cmd.exe surprises this script has already
turned up.

**First attempted fix (per-map imports) made things worse, not better.**
To confine the `KF-Chthon-SE` crash to just that one map, the script was
changed to call `BatchImportCommandlet` once per map (185 separate
`ucc.exe` invocations) instead of once for the whole batch. In practice,
nearly every invocation after the first popped an interactive "The file
on the disk (X) is larger than the file in memory (Y). Are you sure you
want to overwrite it?" dialog - Y consistently matched roughly just that
invocation's own new content, not everything imported by prior calls.
This is strong evidence `BatchImportCommandlet` does **not** reliably
reload existing on-disk package content into memory before saving again
in a fresh process - meaning repeated separate calls against the same
package don't just block automation with a prompt, they risk *silently
losing* earlier maps' textures if someone clicks through. Reverted back
to a single `BatchImportCommandlet` call for the whole batch as a
result - the crash-isolation benefit wasn't worth this risk.

**Both original problems are instead handled without touching the
call-count:**
- 0-byte exports: `GenerateMapPreviewsCommandlet`'s DDS-first choice was
  never wrong, but for the subset of source textures that turn out not
  to be DXT-compressed, the script now lazily falls back to `ucc
  batchexport ... Texture pcx` and then `... bmp` for that whole map
  (once each, not once per frame) whenever DDS comes back empty, per the
  user's suggestion. The final bulk import wildcard widened from `*.dds`
  to `*.*` to cover whatever mix of extensions ends up staged.
- The rare crash-on-import case (confirmed once, no batch-side fix
  possible - no binary DDS parsing available in cmd.exe): accepted as a
  residual risk. The import step now checks the bulk call's exit code
  and, on failure, explicitly warns that `TextureRef` may get set for
  some maps that never actually finished importing, and - importantly -
  tells the admin **not** to just re-run the script (that would
  reintroduce the exact repeated-call problem above), pointing instead
  at either a full from-scratch rebuild or a manual single-texture
  import via the editor for whatever's missing.

**Ran that version for real: DDS->PCX->BMP fallback worked (staging
succeeded for many more maps than before), but two problems remained -
one expected, one not:**

1. `KF-Chthon-SE` crashed ucc again, identically, deterministically -
   confirms it's a real, reproducible bad export, not a fluke. Since the
   whole batch is one `ucc.exe` call, this again silently dropped every
   map alphabetically after it. **Fix: an exclude list**
   (`Tools/KFMapVoteSTPreviewExcludes.txt`, one map name per line,
   checked via `findstr /x` before exporting each map) - a known-bad map
   is now skipped cleanly and logged, instead of taking the rest of the
   run down with it. Pre-populated with `KF-Chthon-SE`.
2. **`TextureRef` was still 0 updated, for every map, including ones
   confirmed imported successfully well before the crash point** (spot-
   checked `GG-VR_Ramps` directly in `System/KFMapVotePreviews.ini` -
   `TextureRef=` still empty). The `:FindStagedMatch` fix from the
   previous round (copying `%~1` into a delayed-expansion variable) did
   **not** fix this - it was addressing a real but different risk, not
   the actual bug. Root cause, reasoned through rather than re-diagnosed
   with another diagnostic script (given how many round trips this
   pipeline has already cost): the batch-based rewrite has an OUTER
   `for /f` actively reading `KFMapVotePreviews.ini` line by line, and
   for every `TextureRef=` line, calls a subroutine whose OWN `for /f`
   reads a *different* file (the staged-results list) to completion.
   Even routed through a subroutine (which fixed the earlier, simpler
   lexical-nesting bug), this is apparently a distinct, deeper problem:
   two `for /f` loops each actively iterating a *different* file, one
   nested inside the other via a call. `:ParseKV`'s inner `for /f` never
   hit this because it reads a STRING, not a file - no second open file
   handle involved.

   **Fix: stopped trying to make batch rewrite ini files at all for this
   step.** `KFStagedResultEntry.uc` (new) + `UpdateTextureRefsCommandlet.uc`
   (new) - the batch script now writes `KFMapVoteSTStagedResults.ini` as
   plain PerObjectConfig output during staging (pure output, no parsing,
   so none of this risk applies), and a small new commandlet reads it
   and sets `TextureRef=` via ordinary `SaveConfig()` - the exact same
   proven-reliable mechanism used everywhere else in this project. This
   trades one `ucc` call (cheap, already proven reliable) for an entire
   class of batch-parsing risk.

**This exact version (exclude list + UnrealScript-side TextureRef
rewrite) has not itself been run yet.** Still open: whether DXT1
compression survives the DDS import path at all.

**Ran that version for real: the batch-side exclude list did not work -
`KF-Chthon-SE` crashed the import again exactly as before, despite being
listed in `Tools/KFMapVoteSTPreviewExcludes.txt`.** Also, per the user's
explicit feedback, sitting through the ~185-map export every single time
just to reach the same crash again (or to iterate on anything
downstream of export) was no longer acceptable - two changes requested:
make the import fault-tolerant per map (log a failure, keep going)
instead of one giant all-or-nothing call, and add a way to skip
re-running export on repeat runs.

1. **Exclude-list root cause, not conclusively diagnosed (no way to
   inspect a batch variable's raw bytes in this environment), but a
   confident leading theory**: `findstr /x` (exact whole-line match)
   comparing `CURMAPNAME` (parsed out of `KFMapVoteSTPreviewManifest.ini`,
   which is `SaveConfig()`-written and therefore CRLF) against a plain-LF
   `.txt` line. If this Wine `cmd.exe`'s `for /f` doesn't strip the
   trailing `\r` the way real Windows' does - plausible, given how many
   other narrow `for /f`/string-op bugs this exact runtime has already
   turned up (see `Build-PreviewPackage.bat`'s own header comment) -
   `CURMAPNAME` would actually be `KF-Chthon-SE<CR>`, which can never
   exact-match a line that has no trailing CR. Chose **not** to spend a
   fourth diagnostic-script round trip confirming this guess. Instead,
   applied the exact same reasoning already used for the `TextureRef`
   bug above: batch string-matching against ini-sourced text has now
   failed twice in this project in two different, narrow ways; moving
   the check onto UnrealScript `config`/`SaveConfig()` sidesteps the
   whole category rather than chasing the next instance of it.

   **Fix:** `ExcludedMaps` is now a `var config array<string>` on
   `GenerateMapPreviewsCommandlet` itself (`Config(KFMapVoteSTPreviewExcludes)`,
   read from `KFMapVoteSTPreviewExcludes.ini`). A map on the list gets no
   `KFPreviewFrameEntry` sections written at all during Phase 1, so
   `Build-PreviewPackage.bat` never even attempts to export/stage/import
   it - the old `Tools/KFMapVoteSTPreviewExcludes.txt` + `findstr /x`
   block was deleted from the batch script entirely rather than debugged
   further.

2. **Per-map validated import, to satisfy "log and continue" without
   reintroducing the already-confirmed repeated-call dialog bug.** The
   constraint that made this non-trivial: an earlier round already
   confirmed that calling `BatchImportCommandlet` repeatedly against the
   SAME EXISTING, growing package pops an interactive "file on disk is
   larger than file in memory" overwrite dialog almost every time after
   the first call - which is exactly what a naive "import each map
   separately into the real package" loop would do. The fix keeps that
   constraint in mind: each map, immediately after its own frames are
   staged, gets ONE `BatchImportCommandlet` call into a package name
   that's unique to that map and has never existed before
   (`_ImportValidate_<MapName>.utx`) - every one of these calls hits the
   "package doesn't exist yet" case, not the "existing package" case
   that triggers the dialog, so the known failure mode doesn't apply
   here. A failure (checked via `errorlevel`, which also catches an
   assertion-abort crash like Chthon's) logs the map name to a new
   `KFMapVoteSTImportFailures.txt` and moves that map's staged files out
   of the way, and the script - still just one big loop, one
   `ucc.exe` subprocess per map - carries straight on to the next map,
   exactly the way a bad `ucc batchexport` call already didn't take down
   the rest of the run. The real, final bulk import (unchanged in
   mechanism - still one call, still safe per the existing "one call
   against a possibly-pre-existing package is fine, only REPEATED calls
   against one are the problem" finding) now only ever sees maps that
   already individually validated clean, so it should no longer be the
   thing that hits Chthon-style crashes at all.

   Best-effort cleanup of the `_ImportValidate_*.utx` scratch packages
   runs at the very end of the script, but nothing depends on it
   succeeding - flagged as an open question whether a crashed validation
   `ucc.exe` can leave one locked under CrossOver, mitigated (not
   guaranteed) by giving every map's scratch package a unique,
   never-reused name so a stuck lock on one can't block any other map.

3. **`skipexport` argument.** `Build-PreviewPackage.bat skipexport` skips
   every `ucc batchexport` call (primary DDS and both PCX/BMP fallbacks)
   and reuses whatever's already sitting under `PreviewExport\` from an
   earlier run. A frame with nothing already exported just degrades
   through the same DDS->PCX->BMP->WARN-and-skip path that already
   existed for a genuinely-empty export - no new code path, just gating
   the three `ucc batchexport` calls behind `if "%SKIPEXPORT%"=="0"`.

**None of this round's changes (UnrealScript-side `ExcludedMaps`,
per-map validation import, `skipexport`) have been run for real yet.**
Needs: `ucc make` to pick up the new `ExcludedMaps` var and recompile,
then a fresh Phase 1 run (delete the stale manifest first so Chthon's old
frame entries don't linger), then a fresh Phase 2 run to confirm Chthon
is skipped entirely and that any other map's validation failure (if one
turns up) gets logged and skipped cleanly rather than aborting the batch.
Still open from before: whether DXT1 compression survives the DDS import
path at all.

**Ran that version for real. Three separate problems surfaced, and the
pipeline design changed significantly as a result - this section covers
all of it.**

1. **`GenerateMapPreviewsCommandlet` failed to compile**: `Error, Invalid
   property or function call on a dynamica[l] array` on
   `ExcludedMaps.Find(MapNames[i])`. `array.Find()` isn't available in
   this SDK build - a later-UnrealScript-only feature, same category of
   API-assumption mistake this project has hit before
   (`GetPerObjectConfigSections`, `GUIList.Empty()`, etc. - see
   CLAUDE.md). **Fix:** replaced with `IsMapExcluded()`, a plain linear
   scan over `ExcludedMaps`, same pattern as this same file's own
   `IsTextureVisited()`.

2. **A huge number of maps started failing with native `Missing
   Package`/`Failed to load '<name>': Can't find file for package
   '<name>'` errors, then `SKIP <map> - couldn't load its LevelSummary`.**
   Investigated directly (no `ucc` needed for this one - just filesystem
   access via the Wine `Z:` mapping): every one of those maps' `.rom`
   files genuinely exists in `Maps/`, but the companion
   texture/sound/vehicle/staticmesh packages their `LevelSummary`/level
   actors reference (`MilitaryBase`, `boardwalk_snd`,
   `BoardwalkVehicles`, `RoadChaseT`, `KF_PalaceTextures1`, `jka`,
   `SourceTextures`, `KFCharPuppeST`, `KF-JK_MALL-Statics`,
   `KF_Gladdos_anim`, etc.) don't exist anywhere in this checkout at
   all - confirmed by searching the whole tree. **Not a regression, not
   caused by anything in this pipeline** - some community maps ship as
   multiple files and only the primary `.rom` made it into `Maps/` for
   these specific maps. `GenerateMapPreviewsCommandlet` already treats a
   failed `LevelSummary` load as a `continue`, not an abort, so the
   commandlet keeps running; the console is just much louder for a
   broken map (8-12 native log lines) than a successful one (silent
   `SaveConfig()`, no output at all unless it also needs a manifest
   entry), which made a normally-running commandlet look hung/broken.

3. **`skipexport` looked like it took effect (banner printed) but every
   map still re-exported anyway.** Root cause: the banner check is only
   1 level of nesting deep (a bare top-level `if`); the actual per-map
   gate was 4-5 `if`/`for` levels deep inside the main loop - and a
   *read-only* variable (never re-set inside the loop, set once before
   it) being silently wrong/ignored at that depth is a new variant of
   the same category of bug already fixed twice in this script (the
   `for /f "delims=="` nesting bug, and the `findstr /x` exclude-list
   bug). Notably this wasn't even a delayed-vs-plain-expansion issue in
   the classic sense - `%SKIPEXPORT%` should be valid via ordinary
   parse-time substitution here since it never changes after being set,
   even on real Windows. Whatever the precise mechanism, depth of
   *lexical* nesting is now confirmed (three separate times) to be the
   actual variable, not the specific construct. **Fix applied at the
   time:** extracted all three export-gating checks into called
   subroutines (`:MaybeExportPrimary`/`:MaybeExportPCX`/`:MaybeExportBMP`),
   matching the same fix already proven for `:ParseKV`. This fix was
   correct as far as it went, but got superseded almost immediately by
   point 5 below.

4. Separately, **the user was running a stale copy** -
   `System/Build-PreviewPackage.bat` existed as a leftover from before
   `skipexport`/the validation pass existed (0 matches for `SKIPEXPORT`
   in it), and was shadowing the real, edited copy under
   `KFMapVoteST/Tools/`. This wasn't the actual bug (fix #3 above was
   real and necessary too), but it delayed noticing it, and is a
   trap this project hadn't hit before: `.bat` scripts, unlike `.uc`
   classes (compiled directly from `Classes/` by `ucc`), apparently get
   manually copied into `System/` at some point and can silently drift
   out of sync with the source under `KFMapVoteST/Tools/`. Worth
   remembering for any FUTURE `.bat`/`.ini` edit in this project too.

5. **A real import finally completed - and came back 135MB.** Most
   staged textures were either uncompressed PCX (~393KB each for a
   512x256 24-bit image) or already-compressed DDS in DXT3/DXT5 (8
   bits/pixel, twice DXT1's 4 bits/pixel) - confirmed by census across
   all 338 staged `.dds` files at the time: 233 DXT1, 25 DXT3, 80 DXT5,
   plus 85 PCX. User asked for an ImageMagick-based Mac-side batch
   compression script (force DXT1, convert PCX too), and separately
   reported `skipexport`'s fix (#3) wasn't actually saving meaningful
   time - a fresh `ucc.exe` launch costs about the same whether it's
   doing a real export or the per-map *validation* import added the
   round before, so skipping export alone barely moved total run time.
   Combined with the user's explicit preference ("I am fine with having
   separate scripts... other server admins can figure out how to adapt
   the stuff on their own... it'd be more efficient to just have 3
   different scripts"), **the whole pipeline was redesigned from one
   monolithic script into three**:
   - `Export-PreviewTextures.bat` (Windows/`ucc`) - export + stage only,
     no import, no validation, no `skipexport` flag (moot - it's a
     separate script now, just don't run it again).
   - `compress_previews.sh` (Mac, new) - forces every staged file to a
     single DXT1 `.dds` capped at 512x256, same basename, written to a
     separate `PreviewCompressed/` (non-destructive).
   - `Import-PreviewPackage.bat` (Windows/`ucc`) - ONE bulk import +
     `UpdateTextureRefsCommandlet`, **no per-map validation anymore**.
   - `Build-PreviewPackage.bat` (both the `Tools/` and stale `System/`
     copies) deleted.

   **While building `compress_previews.sh`, found the likely root cause
   of the original `KF-Chthon-SE` crash, and verified the whole new
   pipeline for real** (this Mac has `ucc`... no it doesn't, but it does
   have Bash and a real filesystem view of every file `ucc` touches via
   the Wine `Z:` mapping, and it does have ImageMagick - both used
   directly, not just written blind):
   - Read the raw bytes of a real `ucc batchexport`-produced DDS file.
     `ddspf.dwSize` (offset 76) and `ddspf.dwFlags` (offset 80) are both
     0; per the DDS spec they must be 32 and `DDPF_FOURCC` (0x4)
     respectively. Everything else in the header (top-level flags,
     width/height, mip count, the actual "DXT1"/"DXT5" fourCC bytes) is
     correct. ImageMagick's DDS reader refuses the file outright
     (`identify: improper image header`) until exactly those two 4-byte
     fields are patched - confirmed directly, not inferred. This is
     very likely the same non-spec-conformance behind
     `KF-Chthon-SE`'s `Assertion failed: MipmapSize <= Length` crash in
     `ucc`'s own importer, though that exact assertion wasn't
     separately reproduced here (no `ucc` access) - re-encoding through
     ImageMagick's own DDS writer, which `compress_previews.sh` does
     for every file regardless of source format, should fix the
     category of problem at its source rather than isolating it after
     the fact.
   - Ran `compress_previews.sh` for real against this repo's actual
     `PreviewStaged/` (423 files - 338 `.dds`, 85 `.pcx`, left over from
     the run that produced the 135MB package): **423 compressed, 0
     failed, 117MB -> 35MB, ~44 seconds.** Spot-checked several outputs
     via `magick identify` - all DXT1, all capped at 512x256, animated
     sequences' `_a01`/`_a02`/... basenames preserved exactly. Rendered
     one back to PNG as a non-corruption sanity check (125KB, real image
     content, not blank/garbage).

   **Still open, needs a real `ucc` run to confirm:** whether
   `Import-PreviewPackage.bat`'s single bulk import actually succeeds
   end-to-end against `PreviewCompressed/` (in particular whether
   `KF-Chthon-SE`, if not yet added to `ExcludedMaps`, still crashes it -
   the ImageMagick fix is a strong hypothesis, not a confirmed fix for
   that exact assertion), and whether `ucc`'s importer preserves the
   DXT1 encoding as-is on import rather than silently
   recompressing/converting it (same open question as before, just
   carried forward - not yet checked in the editor).
