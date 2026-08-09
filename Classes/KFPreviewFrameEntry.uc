// ====================================================================
//  KFPreviewFrameEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  Machine-readable hand-off between GenerateMapPreviewsCommandlet
//  ("Phase 1") and Tools/Export-PreviewTextures.bat ("Phase 2", the
//  export stage of the 3-script Tools/ pipeline). Replaces
//  KFPreviewExportEntry (one section per MAP, with a semicolon-joined
//  Frames field) - that shape required the batch script to split on
//  ";" and strip a "<MapName>." prefix from each entry, both of which
//  turned out to need cmd.exe string features
//  (%VAR:~start,length%/%VAR:search=replace%, and even plain
//  "tokens=1,*"-with-wildcard splitting on "." specifically) that don't
//  work under this project's actual runtime environment - Wine/
//  CrossOver's cmd.exe reimplementation, not real Windows cmd.exe.
//  Confirmed via a dedicated diagnostic script run against the real
//  environment, not assumed.
//
//  This shape instead writes ONE section per FRAME (so an animated map
//  with 3 frames gets 3 sections, not 1), with every field the batch
//  script needs already fully resolved by UnrealScript - which has
//  real Left()/Mid()/Len() string functions that work correctly,
//  unlike the cmd.exe features above. The batch script never needs to
//  parse a section header, split on ";", or strip a prefix - it just
//  reads four flat KEY=VALUE lines per frame via the one splitting
//  operation confirmed to work reliably (tokens=1,* delims==).
//
//  RelRef is the frame's Package.Group.Name reference with the
//  "<MapName>." prefix already stripped by GenerateMapPreviewsCommandlet,
//  giving exactly the filename ucc batchexport will have produced for
//  that frame ("<Group>.<Name>.dds" / "<Name>.dds" - append ".dds" and
//  nothing else needs doing).
// ====================================================================
class KFPreviewFrameEntry extends Object
	PerObjectConfig
	Config(KFMapVoteSTPreviewManifest);

var config string MapName;
var config int FrameCount;
var config int FrameIndex;
var config string RelRef;
