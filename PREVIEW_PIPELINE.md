# Map Vote Preview Image Pipeline

How to build/update the shared preview texture package that powers the
map vote footer's image panel (author, player count, screenshot). This
covers every map in your `Maps/` folder in one pass - no per-map manual
UnrealEd work required for the common case.

**Status: confirmed working end-to-end** (all 6 steps below, against this
server's real ~214-map pool - a 117MB staged / 135MB-uncompressed-package
run down to ~35MB staged after compression, imported cleanly). If a step
below doesn't match what you see, trust your own run over this doc and
open an issue/update it - this note just means it's been proven at least
once, not that every edge case is covered.

If you just want to understand *why* this exists, see the "Broader
context" section in `GenerateMapPreviewsCommandlet-handoff.md`. This
doc is the how-to; that one is the dev history/rationale, worth reading
if something below doesn't behave the way it's described here (it also
records everything that was tried and didn't work, so you don't repeat
it).

## What you get

- `KFMapVotePreviews.ini` - `Author`/`PlayerCountMin`/`PlayerCountMax`
  filled in for every map that has them, `TextureRef` pointing into a
  shared package for every map with a resolvable screenshot.
- `KFMapVoteST_Previews.utx` - the shared texture package itself,
  bundled with the mod like `KFAnnounc.uax` already is, so every
  connecting client has every map's preview image regardless of their
  own local map cache.

## Prerequisites

- `ucc.exe` on your PATH (or run from the same directory it lives in -
  every command below assumes you're running from `System/`, same as
  normal `ucc make`).
- A `Maps/` folder (sibling of `System/`) with every map you want
  covered.

## Step by step

### 1. Keep the map list current

```
KFMapVoteST\generate_map_list.sh
```

This is a `sh` script, not a `.bat` - run it from a Mac/Linux checkout of
this repo, or WSL/Git Bash on Windows. It scans
`Maps/*.rom` and writes `KFMapVoteST/Configs/KFMapVoteSTMapList.ini`,
which is what tells the next step which maps exist at all. Only needs
rerunning when you add or remove map files.

### 2. Compile and resolve every map's screenshot

From `System/`:

```
ucc make
ucc KFMapVoteST.GenerateMapPreviewsCommandlet
```

This reads every map's `LevelSummary` directly (not `CacheManager` -
see the handoff doc for why that doesn't work in this SDK build) and:

- Writes `Author`/`PlayerCountMin`/`PlayerCountMax` into
  `KFMapVotePreviews.ini` for every map that has them.
- Resolves each map's `Screenshot` down to the actual exportable
  `Texture` frame(s) - handling both the classic `AnimNext` flipbook
  chain and `MaterialSequence` slideshows, and walking through any
  `TexRotator`/`TexOscillator`/etc. wrapper - and writes the result to
  `KFMapVoteSTPreviewManifest.ini`, one section per map still missing a
  `TextureRef`.

**Console output also logs a human-readable `PREVIEWMANIFEST` line per
map** - skim it (or `KFMapVoteSTPreviewManifest.ini` directly) for any
`Status` that isn't `OK`/`OK+ANIMATED(n)`:

| Status | Meaning | What to do |
|---|---|---|
| `PROCEDURAL` | Screenshot is a `FireTexture`/`WaterTexture`/etc. - real pixels, but generated at runtime, not an authored image | Pick or author a real screenshot for that map, set it as the map's `Screenshot`, recompile the map |
| `UNSUPPORTED(...)` | No static bitmap exists at all (wrong Material type, broken modifier chain, missing reference) | Same as above - needs a human to fix at the source |
| `MISSING` | No `Screenshot` set on the map at all | Same as above |

These maps are **not** touched by step 3 - there's nothing automatable
to do for them.

**Excluding a map you already know is bad:** if a map's screenshot export
is confirmed to crash `ucc`'s importer (confirmed for `KF-Chthon-SE`), add
it to `ExcludedMaps` in `KFMapVoteSTPreviewExcludes.ini`, under
`[KFMapVoteST.GenerateMapPreviewsCommandlet]`:

```
[KFMapVoteST.GenerateMapPreviewsCommandlet]
ExcludedMaps=KF-Chthon-SE
```

This file has to actually exist under `System/` for this to take effect -
`KFMapVoteST/Configs/KFMapVoteSTPreviewExcludes.ini` is the repo-tracked
source copy, same convention as `KFMapVote.ini`/`KFMapVotePreviews.ini`
(see "Config files" note below). A listed map gets no manifest entries
written at all on the next Phase-1 run, so step 3 never attempts to
export/stage/import it. Delete `KFMapVoteSTPreviewManifest.ini` before
rerunning this step if you want a just-excluded map's stale manifest
entries gone immediately (harmless to leave otherwise, just wasted
export time next run for a map you already know is bad).

Config files (`KFMapVoteSTMapList.ini`, `KFMapVotePreviews.ini`,
`KFMapVoteSTPreviewManifest.ini`, `KFMapVoteSTPreviewExcludes.ini`) are
always read/written in `System/`, regardless of where the source copies
live in the repo - if you're working from a version-controlled checkout,
copy `KFMapVoteST/Configs/*` into `System/` before running this (and copy
`KFMapVotePreviews.ini` back out afterward if you want the update
tracked in the repo).

### 3. Build the package - three separate scripts

This step used to be one monolithic script. It's now three, each doing
one job, run in order - splitting it up turned out to be more efficient,
not just tidier: see `Export-PreviewTextures.bat`'s header comment for
why the old single-script design (a per-map "validate then import"
safety net, plus a "skipexport" flag to avoid re-exporting) was actually
working against itself.

**3a. Export (Windows, `ucc`).** From `System/`:

```
..\KFMapVoteST\Tools\Export-PreviewTextures.bat
```

Reads `KFMapVoteSTPreviewManifest.ini` and, for every map listed there
(a map on `ExcludedMaps` - see step 2 above - never appears in the
manifest at all, so it's skipped before this even starts): `ucc
batchexport`s the map's screenshot texture(s) as `.dds` (falling back to
PCX then BMP for any texture whose DDS export comes back empty - some
source textures aren't DXT-compressed, and `ucc`'s DDS exporter silently
writes a 0-byte file for those instead of erroring), then stages each
one into `PreviewStaged/` with a `<MapName>`-prefixed name so two
different maps' identically-named textures don't collide. Animated maps
get the `_a01`/`_a02`/... suffix convention. Writes
`KFMapVoteSTStagedResults.ini` (which map, `TextureRef` basename) for
step 3c to use later. Does **not** import or touch `KFMapVotePreviews.ini`
at all - only run this again if you've changed which maps/textures are
involved; there's no flag needed to "skip" it otherwise, since it's a
separate script now.

**3b. Compress (Mac, ImageMagick).** From anywhere (or `cd` into
`KFMapVoteST/Tools` first):

```
./compress_previews.sh
```

Needs ImageMagick 7+ (`brew install imagemagick` if `magick` isn't on
your PATH). Reads every file `PreviewStaged/`, re-encodes it to a single
DXT1-compressed `.dds` capped at 512x256, and writes it to
`PreviewCompressed/` under the same basename. This is also where the
actual package-size problem gets fixed: raw exports are a mix of
uncompressed PCX and DXT3/DXT5 DDS (twice DXT1's size), and forcing
everything to a uniform, capped DXT1 cut a real run's staged output from
117MB to 35MB. It also incidentally works around a non-spec-conformant
header `ucc batchexport`'s own DDS writer produces (see the script's own
header comment) - likely the same root cause behind the `KF-Chthon-SE`
import crash from earlier versions of this pipeline. Non-destructive -
safe to re-run, `PreviewStaged/` is only ever read.

**3c. Import (Windows, `ucc`).** From `System/`, after 3b has populated
`..\PreviewCompressed`:

```
..\KFMapVoteST\Tools\Import-PreviewPackage.bat
```

Runs `ucc Editor.BatchImportCommandlet` **once**, bulk-importing
everything in `PreviewCompressed/` into `KFMapVoteST_Previews.utx`, then
runs `ucc KFMapVoteST.UpdateTextureRefsCommandlet` to set `TextureRef=`
for every staged map in `KFMapVotePreviews.ini` (reading
`KFMapVoteSTStagedResults.ini` from step 3a).

Full details and the known-unverified risks (package reruns, whether
`ucc`'s importer preserves ImageMagick's DXT1 encoding as-is) are
documented in each script's own header comment - read them before your
first real run. In particular: **don't re-run Import-PreviewPackage.bat
against an already-populated `KFMapVoteST_Previews.utx`** if it reports
an error - repeated separate `ucc.exe` calls against the same existing,
growing package were confirmed to trigger an interactive
overwrite-confirmation dialog that risks silently losing earlier maps'
textures. Start from a fresh (deleted) package for a clean run instead.

### 4. Verify before deploying

Open `KFMapVoteST_Previews.utx` in the editor and spot-check:

- A few animated maps actually play back as a slideshow, not a single
  static frame stuck on frame 1.
- A texture's **Format** property reads `TEXF_DXT1` - every texture
  should be DXT1 now regardless of source (`compress_previews.sh` forces
  it), but it's **not yet confirmed whether `ucc`'s importer preserves
  that encoding as-is vs. silently recompressing/converting on import**.
  If it doesn't read DXT1, do one manual "Compress All Textures" pass
  over the whole package before shipping it - a single one-time step
  regardless of map count, since `Texture.Format` can't be set from a
  script (it's `const`).

Playback speed for animated previews is a **server admin setting**, not
baked into the package - see `PreviewAnimFrameRate` in
`Configs/KFMapVote.ini`.

### 5. Deploy

Copy `KFMapVoteST_Previews.utx` next to `KFAnnounc.uax` so it ships to
clients the normal server-package way, and copy the updated
`KFMapVotePreviews.ini` to your live server's `System/` folder (this ini
is server-side only - see its own header comment for why - clients never
need a copy).

### 6. Clean up

Once you're happy with the deployed package, `PreviewExport\`/
`..\PreviewStaged\`/`..\PreviewCompressed\` are just bulky intermediate
output you don't need anymore:

```
..\KFMapVoteST\Tools\Cleanup-PreviewIntermediates.bat
```

Prompts for confirmation first (`/y` to skip it). Deliberately run this
*after* verifying/deploying, not right after step 3c - if verification
turns up a problem, having the staged/exported intermediates still
around lets you retry steps 3b/3c without redoing the (slow) export in
3a. Nothing it deletes is needed for a future rerun regardless - every
script recreates its own folders from scratch.

## Redistributing this to other server admins

Every step above works against whatever `Maps/`/`Textures`/etc. content
*you* have installed - there's nothing chris-specific baked into any of
these scripts. Another admin standing up their own SirenTorturers-based
server can run the same steps against their own map pool, though step 3
now assumes a Mac (or other machine with ImageMagick) sitting between
two Windows/`ucc` steps - an admin without that available would need to
adapt `compress_previews.sh`'s logic to whatever's on hand, or skip it
and accept a much larger, uncompressed package.
`Export-PreviewTextures.bat`/`Import-PreviewPackage.bat`'s file/folder
names (package name, manifest/output paths) all have sensible defaults
but can be overridden - edit the `SET` lines near the top of each
script. `compress_previews.sh` takes `INPUT_DIR`/`OUTPUT_DIR` as
optional positional arguments instead.
