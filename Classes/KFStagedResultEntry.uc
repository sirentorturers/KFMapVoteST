// ====================================================================
//  KFStagedResultEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  Machine-readable hand-off from Tools/Export-PreviewTextures.bat (the
//  export stage of the 3-script Tools/ pipeline - see that script's
//  header comment) back into the engine: one
//  [<MapName> KFStagedResultEntry] section per map that was successfully
//  exported and staged, holding just the head frame's object name.
//  Read back later by UpdateTextureRefsCommandlet.uc, called from
//  Tools/Import-PreviewPackage.bat after that script's bulk import.
//
//  This exists because rewriting KFMapVotePreviews.ini's TextureRef=
//  lines directly in batch turned out to be unreliable in this
//  project's actual runtime (Wine/CrossOver's cmd.exe) - repeated
//  "TextureRef updated for 0 map(s)" results even for maps confirmed
//  imported successfully, traced to a for/f loop reading one file while
//  another for/f loop (even via a called subroutine) is still actively
//  reading a DIFFERENT file - a different, deeper problem than the
//  lexical-nesting bug fixed earlier (see
//  GenerateMapPreviewsCommandlet-handoff.md). Writing this file is pure
//  batch OUTPUT (no parsing involved, so none of the same risk), and
//  UpdateTextureRefsCommandlet.uc does the actual TextureRef= write via
//  ordinary UnrealScript SaveConfig() - proven reliable everywhere else
//  in this project.
// ====================================================================
class KFStagedResultEntry extends Object
	PerObjectConfig
	Config(KFMapVoteSTStagedResults);

var config string HeadName;
