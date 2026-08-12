@echo off
setlocal EnableDelayedExpansion
REM ====================================================================
REM  Setup-SingleMapPreview.bat
REM  SirenTorturers Edition (KFMapVoteST) - map vote preview pipeline,
REM  SINGLE-MAP convenience wrapper.
REM
REM  Generates or refreshes the map-vote preview texture for ONE map,
REM  instead of the full bulk run (Export-PreviewTextures.bat ->
REM  compress_previews.sh -> Import-PreviewPackage.bat - see
REM  PREVIEW_PIPELINE.md and each stage script's own header comments).
REM  This script does NOT reimplement any of that pipeline - it only
REM  CALLs the existing, unmodified stage scripts, scoped to one map,
REM  plus safety steps specific to updating the SAME shared
REM  KFMapVoteST_Previews.utx the bulk pipeline also writes to.
REM
REM  WHY STEP 0 DELETES THE MANIFEST FIRST
REM  --------------------------------------
REM  GenerateMapPreviewsCommandlet's PerObjectConfig writes MERGE into an
REM  existing KFMapVoteSTPreviewManifest.ini and never prune stale
REM  sections (see that class's own header comment). Without deleting it
REM  first, any OTHER map's leftover manifest entries from an earlier
REM  bulk or single-map run would still be present, and
REM  Export-PreviewTextures.bat (which has no map-awareness of its own -
REM  it just processes whatever the manifest contains) would
REM  re-export/re-stage ALL of them, not just this one map. Safe to
REM  delete: the manifest is a derived worklist recomputed fresh from
REM  each map's LevelSummary/TextureRef state every run, not read back
REM  from its own prior content - KFMapVotePreviews.ini is unaffected.
REM
REM  WHY A BACKUP BEFORE IMPORT - KNOWN, ACCEPTED RISK
REM  --------------------------------------------------
REM  Import-PreviewPackage.bat's own header documents that ucc's
REM  BatchImportCommandlet does not reliably reload an existing on-disk
REM  package before saving again in a fresh process - a REPEATED call
REM  against the SAME, ALREADY-POPULATED package risks an interactive
REM  "file on disk is larger than file in memory" dialog and possible
REM  silent loss of earlier maps' textures. Every single-map update via
REM  this script IS that repeated-call case by design. This is a known,
REM  accepted risk this script cannot eliminate - only mitigate: back up
REM  the package first, and manually spot-check a few OTHER maps'
REM  previews afterward (see the final reminder below). Note that
REM  Import-PreviewPackage.bat does not propagate an import failure into
REM  its own exit code past its final UpdateTextureRefsCommandlet call,
REM  so this script's own errorlevel check after it is a weaker signal
REM  than it looks - always glance at the console output too.
REM
REM  LIMITATION
REM  ----------
REM  This targets one map already listed in KFMapVoteSTMapList.ini. If
REM  you just added a brand-new map's .rom file, run generate_map_list.sh
REM  and copy the regenerated ini into System/ first.
REM
REM  HOW TO RUN
REM  -----------
REM  From System/ (same as every other script in this pipeline), with
REM  this script copied there alongside its siblings:
REM
REM      Setup-SingleMapPreview.bat KF-SomeMap
REM ====================================================================

set "MAPNAME=%~1"
set "MAPLISTINI=KFMapVoteSTMapList.ini"
set "MANIFESTINI=KFMapVoteSTPreviewManifest.ini"
set "MAPVOTEPREVIEWSINI=KFMapVotePreviews.ini"
set "STAGEDRESULTSINI=KFMapVoteSTStagedResults.ini"
set "PACKAGEFILE=KFMapVoteST_Previews.utx"

if "%MAPNAME%"=="" (
	echo ERROR: no map name given.
	echo Usage: Setup-SingleMapPreview.bat KF-SomeMap
	exit /b 1
)

where ucc >nul 2>nul
if errorlevel 1 (
	echo ERROR: "ucc" isn't on PATH from this directory.
	echo Run this from System/, same as every other script in this pipeline.
	exit /b 1
)

if not exist "%MAPLISTINI%" (
	echo ERROR: %MAPLISTINI% not found in the current directory.
	echo Copy it from KFMapVoteST\Configs\ into System\ first.
	exit /b 1
)

findstr /c:"[%MAPNAME% MapListEntry]" "%MAPLISTINI%" >nul 2>nul
if errorlevel 1 (
	echo ERROR: no [%MAPNAME% MapListEntry] section found in %MAPLISTINI%.
	echo Check the map name matches its .rom filename exactly ^(no
	echo extension^). If you just added this map, rerun
	echo generate_map_list.sh and copy the ini back into System\ first.
	exit /b 1
)

echo ============================================================
echo  Setup-SingleMapPreview: %MAPNAME%
echo ============================================================

if exist "%MANIFESTINI%" del "%MANIFESTINI%"

echo.
echo === Step 1/4: resolving %MAPNAME%'s Author/PlayerCount/Screenshot ===
ucc KFMapVoteST.GenerateMapPreviewsCommandlet %MAPNAME%
if errorlevel 1 (
	echo ERROR: GenerateMapPreviewsCommandlet reported an error above.
	exit /b 1
)

findstr /c:"[%MAPNAME% KFMapPreviewEntry]" "%MAPVOTEPREVIEWSINI%" >nul 2>nul
if errorlevel 1 (
	echo ERROR: no [%MAPNAME% KFMapPreviewEntry] section in %MAPVOTEPREVIEWSINI%.
	echo Check the console output above for a SKIP line.
	exit /b 1
)

echo.
echo === Step 2/4: exporting/staging preview texture^(s^) ===
call Export-PreviewTextures.bat
if errorlevel 1 (
	echo ERROR: Export-PreviewTextures.bat reported an error above.
	exit /b 1
)

if not exist "%STAGEDRESULTSINI%" (
	echo ERROR: %STAGEDRESULTSINI% wasn't created - nothing was staged.
	echo Check %MAPNAME% has a resolvable Screenshot ^(see the
	echo PREVIEWMANIFEST line logged above^) and isn't listed in
	echo KFMapVoteSTPreviewExcludes.ini.
	exit /b 1
)

findstr /c:"[%MAPNAME% KFStagedResultEntry]" "%STAGEDRESULTSINI%" >nul 2>nul
if errorlevel 1 (
	echo ERROR: no [%MAPNAME% KFStagedResultEntry] section in %STAGEDRESULTSINI%.
	echo Check the WARN lines logged above by Step 2 for why.
	exit /b 1
)

echo.
echo ============================================================
echo  Step 3/4: MANUAL - compress on the Mac side
echo ============================================================
echo.
echo On your Mac, from this repo checkout, run:
echo.
echo     KFMapVoteST/Tools/compress_previews.sh
echo.
echo Only %MAPNAME%'s file^(s^) will be in PreviewStaged, since Step 2
echo only staged this one map.
echo.
echo Once compress_previews.sh finishes, come back to this window and
echo press any key to continue.
echo.
pause

echo.
echo === Step 4/4: backing up and importing into %PACKAGEFILE% ===
if exist "%PACKAGEFILE%" (
	echo Backing up %PACKAGEFILE% to %PACKAGEFILE%.bak ...
	copy /y "%PACKAGEFILE%" "%PACKAGEFILE%.bak" >nul
) else (
	echo NOTE: %PACKAGEFILE% doesn't exist yet - nothing to back up.
)

call Import-PreviewPackage.bat
if errorlevel 1 (
	echo ERROR: Import-PreviewPackage.bat reported an error above.
	echo Restore %PACKAGEFILE%.bak over %PACKAGEFILE% if you suspect the
	echo package got corrupted.
	exit /b 1
)

echo.
echo ============================================================
echo  Done: %MAPNAME%
echo ============================================================
echo.
echo IMPORTANT: this imported into the SAME shared %PACKAGEFILE% every
echo other map's preview lives in. Open it in the editor now and
echo spot-check a few OTHER maps' previews still look right, not just
echo %MAPNAME%'s - this is the real safety net, not the errorlevel check
echo above. If anything looks wrong, restore %PACKAGEFILE%.bak.
echo.
echo Don't forget to copy the updated %MAPVOTEPREVIEWSINI% and
echo %PACKAGEFILE% to your live server's System\ folder when ready to
echo deploy ^(see PREVIEW_PIPELINE.md, "Deploy"^).

endlocal
