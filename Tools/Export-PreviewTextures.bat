@echo off
setlocal EnableDelayedExpansion
REM ====================================================================
REM  Export-PreviewTextures.bat
REM  SirenTorturers Edition (KFMapVoteST) - map vote preview pipeline,
REM  STAGE 1 of 3 (export)
REM
REM  This is one third of a 3-stage pipeline that replaced a single
REM  monolithic script (Build-PreviewPackage.bat, deleted - see
REM  GenerateMapPreviewsCommandlet-handoff.md for why):
REM
REM      1. Export-PreviewTextures.bat  (this script, Windows/ucc)
REM      2. compress_previews.sh         (Mac, ImageMagick)
REM      3. Import-PreviewPackage.bat    (Windows/ucc)
REM
REM  Splitting it up this way was a deliberate simplification, not just
REM  a reorganization: the old single script also tried to validate each
REM  map's import in-line (one extra ucc.exe launch per map to catch a
REM  crash-causing corrupt export before the real bulk import) and
REM  offered a "skipexport" flag to avoid re-exporting on every re-run.
REM  Both existed to work around the same underlying problem - ucc's own
REM  batchexport DDS writer produces non-spec-conformant, occasionally
REM  outright corrupt files (see compress_previews.sh's header comment) -
REM  and both turned out to be the wrong fix: the per-map validation
REM  import dominated the whole run's wall-clock time (a fresh ucc.exe
REM  launch per map costs about the same whether it's doing a real
REM  export or a validation import, so "skipexport" barely saved any
REM  time - confirmed the hard way, not guessed), and "skipexport" itself
REM  turned out to be silently ignored besides (see below). Now that
REM  compress_previews.sh re-encodes every texture through ImageMagick
REM  before import - fixing the corrupt-header problem at its actual
REM  source instead of catching the crash after the fact - neither
REM  workaround is needed: this script ONLY exports, so "skipping the
REM  export" is just "don't run this script again."
REM
REM  WHAT THIS DOES
REM  ---------------
REM  Reads KFMapVoteSTPreviewManifest.ini (written by
REM  GenerateMapPreviewsCommandlet - see that class's header comment and
REM  the handoff doc) and, for each map it lists:
REM    1. `ucc batchexport`s the map's screenshot texture(s) as DDS,
REM       falling back to PCX then BMP for any texture whose DDS export
REM       comes back empty (some source textures aren't DXT-compressed;
REM       ucc's DDS exporter silently writes a 0-byte file for those
REM       instead of erroring - the mirror image of PCX export silently
REM       failing for DXT-compressed sources, which is why DDS is tried
REM       first).
REM    2. Filters that export down to just the frame(s) the manifest
REM       wants (batchexport dumps EVERY Texture in the map package, not
REM       just the preview) and renames them into one shared staging
REM       folder with a <MapName>-prefixed name, so two different maps
REM       that both name their screenshot "Screenshot" don't collide.
REM       Animated maps (FrameCount > 1) get the _a01/_a02/... suffix
REM       convention - compress_previews.sh preserves these basenames
REM       exactly (just normalizing the extension to .dds), and that
REM       naming is what triggers automatic Texture.AnimNext chain-
REM       linking on import.
REM    3. Once a map's frames are all staged, writes one
REM       KFStagedResultEntry section to KFMapVoteSTStagedResults.ini -
REM       consumed later by Import-PreviewPackage.bat's
REM       UpdateTextureRefsCommandlet step to know which basename is
REM       each map's TextureRef.
REM
REM  This script does NOT import anything and does NOT touch
REM  KFMapVotePreviews.ini - see compress_previews.sh and
REM  Import-PreviewPackage.bat for the rest of the pipeline.
REM
REM  REQUIRED FIRST STEP (do this before running this script)
REM  ----------------------------------------------------------
REM      ucc make
REM      ucc KFMapVoteST.GenerateMapPreviewsCommandlet
REM
REM  That's what actually writes KFMapVoteSTPreviewManifest.ini in the
REM  first place - this script only reads it. Also regenerate
REM  Configs/KFMapVoteSTMapList.ini via generate_map_list.sh first if
REM  your Maps/ folder has changed - see MapListEntry.uc for why that
REM  step exists. A map confirmed to crash the pipeline (e.g.
REM  KF-Chthon-SE) should go in ExcludedMaps in
REM  KFMapVoteSTPreviewExcludes.ini (read by GenerateMapPreviewsCommandlet
REM  itself) so it's never exported at all - see that class's header
REM  comment.
REM
REM  HOW TO RUN
REM  -----------
REM  From System/, the same place every other ucc command in this
REM  project is run from:
REM
REM      ..\KFMapVoteST\Tools\Export-PreviewTextures.bat
REM
REM  Then run compress_previews.sh on the Mac side against
REM  ..\PreviewStaged, then Import-PreviewPackage.bat back here.
REM
REM  To customize package/file names, edit the SET lines right below
REM  this header instead of passing command-line flags.
REM
REM  WHY THIS LOOKS THE WAY IT DOES - cmd.exe BUGS, CONFIRMED THE HARD WAY
REM  ---------------------------------------------------------------------
REM  This project's actual runtime is CrossOver (a Wine-based Windows
REM  compatibility layer on macOS), not real Windows - ucc.exe and this
REM  script both run under Wine's OWN reimplementation of cmd.exe, which
REM  turned out to have real, narrow bugs real Windows cmd.exe doesn't,
REM  confirmed via a series of dedicated diagnostic scripts run against
REM  the actual environment (not assumed):
REM    - %VAR:~start,length% (substring) and %VAR:search=replace%
REM      (search-replace) both silently return the literal modifier text
REM      instead of doing the operation, instead of erroring. Not used
REM      anywhere in this script as a result.
REM    - `tokens=1,2,*` (three-plus token positions with a trailing
REM      wildcard) - the wildcard position came back empty. Only ever
REM      use `tokens=1,*` (exactly one explicit position plus wildcard)
REM      below.
REM    - A `for /f` loop with a "delims==" option string silently fails
REM      to split anything - and, worse, appears to corrupt parsing of
REM      the REST of the enclosing loop's iterations too - specifically
REM      when that `for /f` is lexically nested inside another `for`
REM      loop's body. The IDENTICAL options string works perfectly at
REM      the top level. Fixed by moving it into a `call`ed subroutine
REM      (:ParseKV below) instead of inlining it.
REM    - A variable set OUTSIDE a loop (e.g. a command-line-argument-
REM      derived flag) and only ever READ (never re-set) inside it can
REM      STILL come back wrong/ignored when read via %VAR% several
REM      "if"/"for" levels deep inside that loop's body - confirmed on
REM      this exact script's predecessor's "skipexport" flag: a
REM      shallow (1-level-deep) check of it worked fine, but the same
REM      check 4-5 levels deep inside the main loop was silently
REM      ignored. Whatever the precise cause, it's depth-of-nesting
REM      related, not specific to for/f - same fix as above (move it to
REM      a called subroutine, not lexically nested). This script keeps
REM      every per-map decision inside :ExportFrame/:ExportFallback-style
REM      subroutines as a result, even though it no longer has a
REM      skipexport-style flag to gate.
REM    - `findstr /x` (exact whole-line match) against a plain .txt
REM      exclude list, comparing against a map name read out of an ini
REM      via `for /f`, silently never matched even a confirmed-listed
REM      map. Never conclusively diagnosed, leading theory is a trailing
REM      \r surviving into the parsed value that real Windows' `for /f`
REM      would strip but this Wine build may not. Exclude-list matching
REM      now lives in UnrealScript (GenerateMapPreviewsCommandlet's
REM      ExcludedMaps) instead, not in batch, as a result.
REM  Confirmed working regardless of nesting: `tokens=1,* delims==`
REM  reading a STRING (not a file), default space/tab tokenizing, plain
REM  `if "%%a%%"=="%%b%%"` literal string comparison, and `findstr` (a
REM  separate spawned process, not a batch-language for/f construct at
REM  all).
REM
REM  PATH QUIRKS - CONFIRMED THE HARD WAY, DO NOT "FIX" THESE
REM  -----------------------------------------------------------
REM  `ucc batchexport`'s own output-path argument is resolved relative
REM  to System/ (where ucc.exe actually runs from) - this is native,
REM  closed-source in this SDK checkout (no .uc source to read); if a
REM  future ucc/engine update changes this behavior, this is the spot to
REM  re-verify.
REM ====================================================================

REM ---- edit these if your setup differs from the defaults ----
set "MANIFESTINI=KFMapVoteSTPreviewManifest.ini"
set "EXPORTROOT=PreviewExport"
set "STAGEDDIR=..\PreviewStaged"
set "STAGEDRESULTSINI=KFMapVoteSTStagedResults.ini"
REM --------------------------------------------------------------

where ucc >nul 2>nul
if errorlevel 1 (
	echo ERROR: "ucc" isn't on PATH or resolvable from this directory.
	echo Run this from the same place you'd normally run "ucc make" from.
	exit /b 1
)

if not exist "%MANIFESTINI%" (
	echo ERROR: %MANIFESTINI% not found in the current directory.
	echo Run this from System/, after 'ucc KFMapVoteST.GenerateMapPreviewsCommandlet' has actually written it.
	exit /b 1
)

if not exist "%EXPORTROOT%" mkdir "%EXPORTROOT%"
if not exist "%STAGEDDIR%" mkdir "%STAGEDDIR%"

if exist "%STAGEDRESULTSINI%" del "%STAGEDRESULTSINI%"

REM --------------------------------------------------------------------
REM Single pass: read KFMapVoteSTPreviewManifest.ini, one flat
REM KEY=VALUE line at a time (MapName/FrameCount/FrameIndex/RelRef per
REM frame - see KFPreviewFrameEntry.uc; a map on ExcludedMaps never gets
REM any frame lines written here at all - see
REM GenerateMapPreviewsCommandlet.uc), split via :ParseKV (must be a
REM called subroutine, not inlined - see header comment). On the first
REM frame of a map, batchexport it (DDS, with lazy PCX/BMP fallback per
REM map if DDS comes back empty); on every frame, stage the wanted file;
REM on the last frame, write this map's KFStagedResultEntry section to
REM KFMapVoteSTStagedResults.ini if nothing was missing.
REM --------------------------------------------------------------------
echo === Processing %MANIFESTINI% ===

set "CURMAPNAME="
set "CURFRAMECOUNT="
set "CURFRAMEINDEX="
set "MISSING=0"
set "HEADNAME="
set "PCXTRIED=0"
set "BMPTRIED=0"
set /a MAPCOUNT=0
set /a STAGEDCOUNT=0

for /f "usebackq delims=" %%L in ("%MANIFESTINI%") do (
	set "LINE=%%L"
	call :ParseKV "!LINE!"

	if "!KEY!"=="MapName" set "CURMAPNAME=!VAL!"
	if "!KEY!"=="FrameCount" set "CURFRAMECOUNT=!VAL!"

	if "!KEY!"=="FrameIndex" (
		set "CURFRAMEINDEX=!VAL!"
		if "!VAL!"=="1" (
			set /a MAPCOUNT+=1
			set "HEADNAME="
			set "PCXTRIED=0"
			set "BMPTRIED=0"
			set "MISSING=0"

			call :ExportPrimary "!CURMAPNAME!"
		)
	)

	if "!KEY!"=="RelRef" if "!MISSING!"=="0" (
		REM Try DDS first, then lazily fall back to PCX and then BMP for
		REM this WHOLE map if DDS comes back 0 bytes - some source
		REM textures aren't DXT-compressed, and ucc's DDS batchexport
		REM silently writes an empty file for those instead of erroring.
		REM Each fallback format is only exported once per map
		REM (PCXTRIED/BMPTRIED), not once per frame.
		set "SRCFILE=%EXPORTROOT%\!CURMAPNAME!\!VAL!.dds"
		set "SRCEXT=dds"
		call :GetFileSize "!SRCFILE!"

		if "!FSIZE!"=="0" (
			if "!PCXTRIED!"=="0" (
				call :ExportPCX "!CURMAPNAME!"
				set "PCXTRIED=1"
			)
			set "SRCFILE=%EXPORTROOT%\!CURMAPNAME!_pcx\!VAL!.pcx"
			set "SRCEXT=pcx"
			call :GetFileSize "!SRCFILE!"
		)

		if "!FSIZE!"=="0" (
			if "!BMPTRIED!"=="0" (
				call :ExportBMP "!CURMAPNAME!"
				set "BMPTRIED=1"
			)
			set "SRCFILE=%EXPORTROOT%\!CURMAPNAME!_bmp\!VAL!.bmp"
			set "SRCEXT=bmp"
			call :GetFileSize "!SRCFILE!"
		)

		if "!FSIZE!"=="0" (
			echo     WARN "!VAL!" has no usable export in DDS/PCX/BMP for !CURMAPNAME! - skipping this map.
			set "MISSING=1"
		) else (
			if "!CURFRAMECOUNT!"=="1" (
				set "DESTBASE=!CURMAPNAME!_Preview"
			) else (
				if !CURFRAMEINDEX! LSS 10 (set "PADIDX=0!CURFRAMEINDEX!") else (set "PADIDX=!CURFRAMEINDEX!")
				set "DESTBASE=!CURMAPNAME!_Preview_a!PADIDX!"
			)
			copy /y "!SRCFILE!" "%STAGEDDIR%\!DESTBASE!.!SRCEXT!" >nul
			if "!CURFRAMEINDEX!"=="1" set "HEADNAME=!DESTBASE!"
		)

		if "!CURFRAMEINDEX!"=="!CURFRAMECOUNT!" (
			if "!MISSING!"=="0" (
				echo [!CURMAPNAME! KFStagedResultEntry]>>"%STAGEDRESULTSINI%"
				echo HeadName=!HEADNAME!>>"%STAGEDRESULTSINI%"
				echo.>>"%STAGEDRESULTSINI%"
				set /a STAGEDCOUNT+=1
				echo     staged !CURFRAMECOUNT! frame(s) for !CURMAPNAME!, head = !HEADNAME!
			)
		)
	)
)

echo.
echo %MAPCOUNT% map(s) found in manifest, %STAGEDCOUNT% staged successfully.
echo.
echo Next: run compress_previews.sh on the Mac side against %STAGEDDIR%,
echo then Import-PreviewPackage.bat back here.

goto :End

REM --------------------------------------------------------------------
REM Subroutines. All MUST be called (via "call :Name"), never inlined
REM directly inside another for loop's body - see the header comment.
REM --------------------------------------------------------------------

REM Splits %~1 on the first "=" into module-level KEY/VAL variables.
REM A line with no "=" (e.g. a "[MapName ClassName]" section header)
REM comes back as KEY=<whole line>, VAL=<empty> - callers distinguish a
REM header from a real field by checking whether KEY matches one of the
REM specific field names they're looking for.
:ParseKV
set "KEY="
set "VAL="
for /f "tokens=1,* delims==" %%X in ("%~1") do (
	set "KEY=%%X"
	set "VAL=%%Y"
)
goto :eof

REM Sets FSIZE to the size in bytes of the file at %~1, or 0 if it
REM doesn't exist.
:GetFileSize
set "FSIZE=0"
for %%Z in ("%~1") do set "FSIZE=%%~zZ"
goto :eof

:ExportPrimary
echo   [%~1] batchexport...
if not exist "%EXPORTROOT%\%~1" mkdir "%EXPORTROOT%\%~1"
ucc batchexport "%~1" Texture dds "%EXPORTROOT%\%~1" >nul
goto :eof

:ExportPCX
echo     DDS export empty for %~1 - trying PCX fallback...
if not exist "%EXPORTROOT%\%~1_pcx" mkdir "%EXPORTROOT%\%~1_pcx"
ucc batchexport "%~1" Texture pcx "%EXPORTROOT%\%~1_pcx" >nul
goto :eof

:ExportBMP
echo     PCX export also empty for %~1 - trying BMP fallback...
if not exist "%EXPORTROOT%\%~1_bmp" mkdir "%EXPORTROOT%\%~1_bmp"
ucc batchexport "%~1" Texture bmp "%EXPORTROOT%\%~1_bmp" >nul
goto :eof

:End
endlocal
