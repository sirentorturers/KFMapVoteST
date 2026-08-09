@echo off
setlocal EnableDelayedExpansion
REM ====================================================================
REM  Cleanup-PreviewIntermediates.bat
REM  SirenTorturers Edition (KFMapVoteST) - map vote preview pipeline
REM
REM  Deletes the bulky intermediate folders the 3-stage preview pipeline
REM  (Export-PreviewTextures.bat -> compress_previews.sh ->
REM  Import-PreviewPackage.bat) leaves behind once you've confirmed
REM  KFMapVoteST_Previews.utx built correctly and don't need to re-run
REM  any stage:
REM
REM    - PreviewExport\        raw ucc batchexport output, one folder per
REM                             map - by far the biggest one, since
REM                             batchexport dumps EVERY Texture in each
REM                             map's package, not just the preview.
REM    - ..\PreviewStaged\     filtered/renamed originals staged by
REM                             Export-PreviewTextures.bat before
REM                             compression.
REM    - ..\PreviewCompressed\ DXT1-compressed output from
REM                             compress_previews.sh, already imported
REM                             into KFMapVoteST_Previews.utx by the time
REM                             you'd run this.
REM
REM  Does NOT touch anything you'd need to re-run without starting the
REM  whole pipeline over: KFMapVoteST_Previews.utx (the real output),
REM  KFMapVotePreviews.ini, KFMapVoteSTPreviewManifest.ini,
REM  KFMapVoteSTStagedResults.ini, or KFMapVoteSTPreviewExcludes.ini. If
REM  you genuinely want a from-scratch rerun later, Export-PreviewTextures.bat
REM  and compress_previews.sh both recreate whatever folders they need on
REM  their own - there's nothing to restore by hand.
REM
REM  HOW TO RUN
REM  -----------
REM  From System/, after Import-PreviewPackage.bat has finished and
REM  you've spot-checked the package in the editor:
REM
REM      ..\KFMapVoteST\Tools\Cleanup-PreviewIntermediates.bat
REM
REM  Prompts for confirmation before deleting anything (add /y as the
REM  first argument to skip the prompt, e.g. for scripting).
REM ====================================================================

set "EXPORTROOT=PreviewExport"
set "STAGEDDIR=..\PreviewStaged"
set "COMPRESSEDDIR=..\PreviewCompressed"

set "SKIPCONFIRM=0"
if /i "%~1"=="/y" set "SKIPCONFIRM=1"

echo This will permanently delete, if present:
echo   %EXPORTROOT%\
echo   %STAGEDDIR%\
echo   %COMPRESSEDDIR%\
echo.
echo These are all regenerable by re-running the pipeline from
echo Export-PreviewTextures.bat onward - KFMapVoteST_Previews.utx and
echo every .ini are left untouched.
echo.

if "%SKIPCONFIRM%"=="0" (
	set /p "CONFIRM=Proceed? [y/N] "
	if /i not "!CONFIRM!"=="y" (
		echo Cancelled - nothing deleted.
		goto :End
	)
)

if exist "%EXPORTROOT%" (
	echo Deleting %EXPORTROOT%\ ...
	rmdir /s /q "%EXPORTROOT%"
) else (
	echo %EXPORTROOT%\ not present - skipping.
)

if exist "%STAGEDDIR%" (
	echo Deleting %STAGEDDIR%\ ...
	rmdir /s /q "%STAGEDDIR%"
) else (
	echo %STAGEDDIR%\ not present - skipping.
)

if exist "%COMPRESSEDDIR%" (
	echo Deleting %COMPRESSEDDIR%\ ...
	rmdir /s /q "%COMPRESSEDDIR%"
) else (
	echo %COMPRESSEDDIR%\ not present - skipping.
)

echo.
echo Done.

:End
endlocal
