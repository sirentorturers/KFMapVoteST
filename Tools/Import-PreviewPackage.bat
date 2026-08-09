@echo off
setlocal EnableDelayedExpansion
REM ====================================================================
REM  Import-PreviewPackage.bat
REM  SirenTorturers Edition (KFMapVoteST) - map vote preview pipeline,
REM  STAGE 3 of 3 (import)
REM
REM  Final stage of the 3-script pipeline - see Export-PreviewTextures.bat
REM  (stage 1) and compress_previews.sh (stage 2)'s header comments for
REM  the full picture and why this replaced one monolithic script.
REM
REM  WHAT THIS DOES
REM  ---------------
REM    1. Runs ucc Editor.BatchImportCommandlet ONCE against everything
REM       compress_previews.sh wrote to PreviewCompressed, to build/update
REM       the shared KFMapVoteST_Previews.utx.
REM    2. Runs ucc KFMapVoteST.UpdateTextureRefsCommandlet, a small
REM       UnrealScript commandlet that reads KFMapVoteSTStagedResults.ini
REM       (written by Export-PreviewTextures.bat, pure output, one
REM       section per staged map) and sets TextureRef= for each one in
REM       KFMapVotePreviews.ini via ordinary SaveConfig() - proven the
REM       most reliable way to rewrite that ini in this whole project;
REM       see GenerateMapPreviewsCommandlet-handoff.md for why this is
REM       NOT done by re-parsing ini text in batch.
REM
REM  NO PER-MAP VALIDATION HERE ANYMORE
REM  -------------------------------------
REM  An earlier version of this pipeline imported each map into its own
REM  disposable scratch package first, specifically to catch a
REM  corrupted export (confirmed: KF-Chthon-SE, "Assertion failed:
REM  MipmapSize <= Length") before it could crash the real bulk import.
REM  That's no longer needed: compress_previews.sh re-encodes every
REM  texture through ImageMagick's own DDS writer before it ever reaches
REM  this script, which fixes the actual root cause (ucc's own DDS
REM  writer leaves ddspf.dwSize/dwFlags zeroed - see that script's header
REM  comment) instead of catching the crash after the fact. Removing the
REM  per-map validation also removes what turned out to be THE dominant
REM  per-map cost in the old pipeline - confirmed the hard way: a fresh
REM  ucc.exe launch costs about the same whether it's doing a real
REM  export/import or just a validation import, so isolating every map
REM  in its own ucc.exe call multiplied total run time by roughly the
REM  number of maps for no benefit once the root cause is fixed upstream.
REM
REM  If the bulk import below DOES still fail on some file despite
REM  going through compress_previews.sh, that's a genuinely new problem,
REM  not a repeat of the old one - check the console output for the last
REM  successful "Texture import..." line to identify the map, and see
REM  compress_previews.sh's own PreviewCompressFailures.txt in case that
REM  map failed to compress cleanly and left a stale/partial file behind.
REM
REM  HOW TO RUN
REM  -----------
REM  From System/, after compress_previews.sh has populated
REM  ..\PreviewCompressed:
REM
REM      ..\KFMapVoteST\Tools\Import-PreviewPackage.bat
REM
REM  To customize package/file names, edit the SET lines right below
REM  this header instead of passing command-line flags.
REM
REM  PATH QUIRKS - CONFIRMED THE HARD WAY, DO NOT "FIX" THESE
REM  -----------------------------------------------------------
REM  `ucc Editor.BatchImportCommandlet`'s package argument needs an
REM  explicit path component (a bare "Name.utx" fails with "Package
REM  should contain a path reference" - always pass ".\Name.utx"), AND
REM  its source-wildcard argument needs to be given relative to the REPO
REM  ROOT (a sibling of System/), not relative to System/ itself. This
REM  commandlet is native, closed-source in this SDK checkout (no .uc
REM  source to read) - if a future ucc/engine update changes this
REM  behavior, this is the spot to re-verify.
REM
REM  CONFIRMED: BatchImportCommandlet DOES NOT SAFELY HANDLE REPEATED
REM  CALLS AGAINST THE SAME EXISTING, GROWING PACKAGE
REM  -------------------------------------------------------------------
REM  An earlier version of this pipeline called BatchImportCommandlet
REM  once PER MAP, all targeting the SAME real output package, to
REM  confine any single crash to just that one map. In practice, nearly
REM  every one of those calls after the first popped an interactive
REM  Windows dialog: "The file on the disk (X) is larger than the file
REM  in memory (Y). Are you sure you want to overwrite it?" - indicating
REM  BatchImportCommandlet does NOT reliably reload existing on-disk
REM  package content into memory before saving again in a fresh process.
REM  Repeated separate calls against the SAME PRE-EXISTING, ALREADY-
REM  GROWING package risk SILENTLY LOSING earlier maps' textures on top
REM  of blocking all automation with a prompt. This script only ever
REM  calls BatchImportCommandlet ONCE per run as a result - if the
REM  import below reports an error, do NOT just re-run this script; see
REM  the error output it prints for what to do instead.
REM
REM  KNOWN UNVERIFIED RISK
REM  -----------------------
REM  Whether ucc's importer preserves ImageMagick's DXT1 encoding as-is
REM  vs. silently recompressing/converting it on import has not been
REM  confirmed. Check a freshly-imported texture's Format property in
REM  the editor after your first real run; if it isn't TEXF_DXT1, do one
REM  manual "Compress All Textures" pass over the whole package before
REM  shipping it.
REM ====================================================================

REM ---- edit these if your setup differs from the defaults ----
set "PACKAGEFILE=KFMapVoteST_Previews.utx"
set "PREVIEWSINI=..\KFMapVoteST\Configs\KFMapVotePreviews.ini"
set "COMPRESSEDDIR=..\PreviewCompressed"
set "STAGEDRESULTSINI=KFMapVoteSTStagedResults.ini"
REM --------------------------------------------------------------

where ucc >nul 2>nul
if errorlevel 1 (
	echo ERROR: "ucc" isn't on PATH or resolvable from this directory.
	echo Run this from the same place you'd normally run "ucc make" from.
	exit /b 1
)

if not exist "%PREVIEWSINI%" (
	echo ERROR: %PREVIEWSINI% not found - run GenerateMapPreviewsCommandlet first ^(it creates this file^).
	exit /b 1
)

if not exist "%COMPRESSEDDIR%" (
	echo ERROR: %COMPRESSEDDIR% not found.
	echo Run Export-PreviewTextures.bat then compress_previews.sh first.
	exit /b 1
)

if not exist "%STAGEDRESULTSINI%" (
	echo ERROR: %STAGEDRESULTSINI% not found in the current directory.
	echo Run Export-PreviewTextures.bat first ^(it creates this file^).
	exit /b 1
)

echo === Importing into %PACKAGEFILE% ===

if exist "%PACKAGEFILE%" (
	echo NOTE: %PACKAGEFILE% already exists - this run will add to it in
	echo ONE import call, which is the safe case ^(see header comment^);
	echo it's only REPEATED separate calls against an existing package
	echo that are the problem.
)

ucc Editor.BatchImportCommandlet ".\%PACKAGEFILE%" Texture "%COMPRESSEDDIR%\*.dds"
if errorlevel 1 (
	echo.
	echo WARN: import reported an error/crash. Check the console output
	echo above for the last successful "Texture import..." line to see
	echo which map it stopped at, and check PreviewCompressFailures.txt
	echo from compress_previews.sh in case that map's file never
	echo compressed cleanly in the first place.
	echo.
	echo DO NOT just re-run this script to pick up the rest - a second
	echo separate ucc.exe call against this now-existing package hits the
	echo "file on disk is larger than file in memory" problem documented
	echo in the header comment, and clicking through it risks losing what
	echo already imported. If something's missing, either delete
	echo %PACKAGEFILE% and do one completely fresh full run, or import
	echo that one map's staged file^(s^) by hand via the editor's own
	echo texture import.
)

REM --------------------------------------------------------------------
REM TextureRef= rewrite - done in UnrealScript, not batch. See
REM GenerateMapPreviewsCommandlet-handoff.md for why an earlier
REM batch-based version of this step silently updated 0 entries despite
REM correct staged-results data.
REM --------------------------------------------------------------------
echo.
echo === Updating TextureRef via UpdateTextureRefsCommandlet ===

for %%P in ("%PACKAGEFILE%") do set "PACKAGEBASENAME=%%~nP"

ucc KFMapVoteST.UpdateTextureRefsCommandlet !PACKAGEBASENAME!

echo.
echo === Done ===
echo.
echo Before deploying: open %PACKAGEFILE% in the editor and check a
echo freshly-imported texture's Format property reads TEXF_DXT1 - if
echo not, do one manual "Compress All Textures" pass over the whole
echo package first (see the header comment for why).

endlocal
