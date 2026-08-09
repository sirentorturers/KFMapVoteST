// ====================================================================
//  UpdateTextureRefsCommandlet
//  SirenTorturers Edition (KFMapVoteST)
//
//  Offline tool - run from System/ via:
//
//      ucc KFMapVoteST.UpdateTextureRefsCommandlet [PackageBaseName]
//
//  as the final step of Tools/Import-PreviewPackage.bat (the import
//  stage of the 3-script Tools/ pipeline - see that script's header
//  comment), after that script's single bulk
//  ucc Editor.BatchImportCommandlet call finishes (successfully or not -
//  see that script's own comments on what a partial/crashed import
//  means for the results this reads).
//
//  Reads KFMapVoteSTStagedResults.ini (KFStagedResultEntry - written by
//  Tools/Export-PreviewTextures.bat during export/staging, one section
//  per map it successfully got a frame staged for) and sets TextureRef
//  on the matching KFMapPreviewEntry for every one, exactly the same way
//  GenerateMapPreviewsCommandlet already writes Author/PlayerCount -
//  constructing by exact map name and calling SaveConfig(), so this
//  only ever touches the TextureRef= line for maps actually present in
//  the staged-results ini, leaving every other field and every other
//  map's section untouched.
//
//  PackageBaseName defaults to "KFMapVoteST_Previews" (matching
//  Import-PreviewPackage.bat's own default PACKAGEFILE) if not passed -
//  pass it explicitly if that script's PACKAGEFILE was customized.
// ====================================================================
class UpdateTextureRefsCommandlet extends Commandlet;

event int Main(string Parms)
{
	local array<string> MapNames;
	local KFStagedResultEntry Result;
	local KFMapPreviewEntry Entry;
	local string PackageBaseName;
	local int i, UpdatedCount, SkippedCount;

	PackageBaseName = Parms;
	if (PackageBaseName == "")
		PackageBaseName = "KFMapVoteST_Previews";

	MapNames = GetPerObjectNames("KFMapVoteSTStagedResults", "KFStagedResultEntry", 1024);
	log("UpdateTextureRefs: found "$MapNames.Length$" staged result(s) - package base name '"$PackageBaseName$"'.");

	for (i = 0; i < MapNames.Length; i++)
	{
		Result = new(none, MapNames[i]) class'KFStagedResultEntry';
		if (Result.HeadName == "")
		{
			log("UpdateTextureRefs: SKIP "$MapNames[i]$" - no HeadName recorded in KFMapVoteSTStagedResults.ini.");
			SkippedCount++;
			continue;
		}

		Entry = new(none, MapNames[i]) class'KFMapPreviewEntry';
		Entry.TextureRef = PackageBaseName $ "." $ Result.HeadName;
		Entry.SaveConfig();
		UpdatedCount++;
	}

	log("UpdateTextureRefs: updated "$UpdatedCount$" TextureRef entries in KFMapVotePreviews.ini; "$SkippedCount$" skipped.");

	return 0;
}

defaultproperties
{
	HelpCmd="UpdateTextureRefs"
	HelpOneLiner="Sets TextureRef in KFMapVotePreviews.ini from KFMapVoteSTStagedResults.ini (written by Export-PreviewTextures.bat)."
	HelpUsage="ucc UpdateTextureRefs [PackageBaseName]"
	LogToStdout=true
}
