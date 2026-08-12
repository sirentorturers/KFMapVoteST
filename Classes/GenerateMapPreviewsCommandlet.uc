// ====================================================================
//  GenerateMapPreviewsCommandlet
//  SirenTorturers Edition (KFMapVoteST)
//
//  Offline tool - run from System/ via:
//
//      ucc KFMapVoteST.GenerateMapPreviewsCommandlet
//
//  on a machine whose Maps/ folder actually has every map you want
//  covered - your server itself is the natural choice now that
//  KFMapVotePreviews.ini is read server-side only (see
//  KFMapPreviewEntry.uc); a player's client is never suitable, since a
//  client's own local map cache is exactly the unreliable thing this
//  whole mechanism exists to bypass.
//
//  Before running this, regenerate Configs/KFMapVoteSTMapList.ini via
//  generate_map_list.sh (repo Maps/ folder -> ini) if you've added or
//  removed any maps, and make sure it (and KFMapVotePreviews.ini) are
//  copied into System/ alongside the compiled packages - Config/
//  PerObjectConfig inis are always read from System/, regardless of
//  where the source copy lives in the repo. This commandlet enumerates
//  KFMapVoteSTMapList.ini via GetPerObjectNames() - see MapListEntry.uc
//  for why it does NOT use CacheManager.GetMapList() (confirmed empty on
//  this project's actual SDK checkout: CacheManager reads a persisted
//  native cache database, System/CacheRecords.ucl, that was never
//  populated with any map entries, and this UnrealEd build has no
//  Content Browser to rebuild it). Instead, each map's
//  Author/PlayerCount/Screenshot is read straight from that map's own
//  LevelSummary object, loaded directly by name via DynamicLoadObject -
//  a different, more reliable code path (ordinary package/object
//  loading, not CacheManager's side database).
//
//  Writes/updates one KFMapPreviewEntry PerObjectConfig section per map
//  in KFMapVotePreviews.ini via SaveConfig() - the native
//  PerObjectConfig persistence mechanism, so reruns merge cleanly
//  instead of overwriting the whole file or clobbering entries you've
//  already hand-edited.
//
//  This only handles the metadata half plus a MANIFEST of what the
//  texture half needs. TextureRef is deliberately left untouched by
//  this commandlet (existing values are preserved as-is, new entries
//  are left blank) since it must point into a shared texture package
//  built separately (see KFMapPreviewEntry.uc). For every map still
//  missing a TextureRef, this logs one PREVIEWMANIFEST line to the
//  console (human-readable) AND writes one KFPreviewFrameEntry section
//  per frame to KFMapVoteSTPreviewManifest.ini (machine-readable - the
//  real input to the export/import automation script, see
//  KFPreviewFrameEntry.uc and KFMapVoteST/Tools/) - see
//  ResolveScreenshotFrames() below for what both contain and why a
//  map's raw Screenshot reference isn't always itself an exportable
//  Texture. Reruns only show what's still outstanding.
//
//  EXCLUDING A KNOWN-BAD MAP
//  --------------------------
//  Some maps' screenshot exports crash ucc's importer outright
//  (confirmed: KF-Chthon-SE - a corrupted DDS export, not fixable from
//  this side). List any such map, one per line, as
//  ExcludedMaps=<MapName> in KFMapVoteSTPreviewExcludes.ini under
//  [KFMapVoteST.GenerateMapPreviewsCommandlet] - a map on this list gets
//  no KFPreviewFrameEntry sections written at all, so
//  Tools/Export-PreviewTextures.bat never attempts to export/stage it in
//  the first place. (Author/PlayerCount metadata is still written for
//  an excluded map - only the texture/frame manifest is skipped, since
//  that's the only part that can crash the export/import pipeline.) An
//  EARLIER version of this exclude mechanism lived entirely in the
//  batch script (KFMapVoteSTPreviewExcludes.txt + findstr /x) - moved
//  here after that version silently failed to match on this project's
//  actual Wine cmd.exe runtime (see
//  GenerateMapPreviewsCommandlet-handoff.md for the failure history) -
//  an ordinary UnrealScript string comparison against a config array
//  (see IsMapExcluded() below - array.Find() isn't available in this
//  SDK build) has no equivalent CR/LF or string-op risk.
//
//  If you change ExcludedMaps and want the removal to show up
//  immediately (rather than just not getting any WORSE), delete
//  KFMapVoteSTPreviewManifest.ini before rerunning this commandlet -
//  PerObjectConfig/SaveConfig() merges new writes into an existing ini
//  but never prunes a section this run didn't touch, so a
//  newly-excluded map's old KFPreviewFrameEntry sections would otherwise
//  just sit there unused (harmless, just wasted export time next run
//  until the manifest is regenerated fresh).
// ====================================================================
class GenerateMapPreviewsCommandlet extends Commandlet
	Config(KFMapVoteSTPreviewExcludes);

var config array<string> ExcludedMaps;

event int Main(string Parms)
{
	local array<string> MapNames;
	local LevelSummary Summary;
	local KFMapPreviewEntry Entry;
	local KFPreviewFrameEntry FrameEntry;
	local int i, j, WrittenCount, ChecklistCount, SkippedCount, ExcludedCount;
	local array<Texture> Frames;
	local string FrameList, Status, FullRef, RelRef, MapPrefix, TargetMap;

	// Optional single-map scope, passed as Parms (e.g.
	// "ucc KFMapVoteST.GenerateMapPreviewsCommandlet KF-SomeMap") - see
	// Tools/Setup-SingleMapPreview.bat. Empty Parms (the bulk-run
	// invocation above) leaves every check below a no-op, so bulk
	// behavior is unchanged.
	TargetMap = Parms;

	MapNames = GetPerObjectNames("KFMapVoteSTMapList", "MapListEntry", 1024);
	if (TargetMap != "")
		log("GenerateMapPreviews: found "$MapNames.Length$" maps listed in KFMapVoteSTMapList.ini - scoped to single map '"$TargetMap$"' (regenerate via generate_map_list.sh if this looks stale).");
	else
		log("GenerateMapPreviews: found "$MapNames.Length$" maps listed in KFMapVoteSTMapList.ini (regenerate via generate_map_list.sh if this looks stale).");

	for (i = 0; i < MapNames.Length; i++)
	{
		if (TargetMap != "" && MapNames[i] != TargetMap)
			continue;

		// LevelSummary is always named exactly "<MapPackage>.LevelSummary"
		// at package root (no numeric suffix, confirmed via a real t3d
		// export showing Summary=LevelSummary'myLevel.LevelSummary') -
		// unlike LevelInfo0/etc, which vary per-actor, this name is
		// predictable enough to load directly without opening the level.
		Summary = LevelSummary(DynamicLoadObject(MapNames[i] $ ".LevelSummary", class'LevelSummary', true));
		if (Summary == None)
		{
			log("GenerateMapPreviews: SKIP "$MapNames[i]$" - couldn't load its LevelSummary (missing/renamed map file?).");
			SkippedCount++;
			continue;
		}

		if (Summary.Author == "" && Summary.IdealPlayerCountMin == 0 && Summary.IdealPlayerCountMax == 0 && Summary.Screenshot == None)
			continue; // nothing usable for this map - skip

		// Constructing by exact name first loads whatever's already in
		// KFMapVotePreviews.ini for this map (including a hand-set
		// TextureRef) - we only touch Author/PlayerCount below, so any
		// existing TextureRef survives the SaveConfig() call unchanged.
		Entry = new(none, MapNames[i]) class'KFMapPreviewEntry';

		Entry.Author = Summary.Author;
		Entry.PlayerCountMin = Summary.IdealPlayerCountMin;
		Entry.PlayerCountMax = Summary.IdealPlayerCountMax;
		Entry.SaveConfig();
		WrittenCount++;

		// The TextureRef=="" gate normally skips a map that's already been
		// through the pipeline once. When TargetMap explicitly names this
		// map, that gate is bypassed so a re-run can refresh an
		// already-textured map's manifest entry too (Setup-SingleMapPreview.bat's
		// "refresh" case), not just cover brand-new maps.
		if ((TargetMap != "" || Entry.TextureRef == "") && Summary.Screenshot != None)
		{
			if (IsMapExcluded(MapNames[i]))
			{
				log("GenerateMapPreviews: SKIP "$MapNames[i]$" - listed in ExcludedMaps (KFMapVoteSTPreviewExcludes.ini), not added to the manifest.");
				ExcludedCount++;
				continue;
			}

			Frames.Length = 0;
			ResolveScreenshotFrames(Summary.Screenshot, Frames, Status);

			FrameList = "";
			for (j = 0; j < Frames.Length; j++)
			{
				if (FrameList != "")
					FrameList = FrameList $ ";";
				FrameList = FrameList $ string(Frames[j]);
			}
			if (Frames.Length > 1)
				Status = Status $ "+ANIMATED("$Frames.Length$")";

			// Pipe-delimited so a human can skim console/log output for
			// PROCEDURAL/UNSUPPORTED entries needing manual attention -
			// the raw src= ref is always included for that purpose. Not
			// meant as a script's parse target though (ucc's own log
			// wraps long lines mid-content, breaking naive line-based
			// scraping); KFPreviewFrameEntry below is the real
			// structured hand-off to the export/import automation.
			log("PREVIEWMANIFEST|"$MapNames[i]$"|"$Status$"|"$FrameList$"|src="$string(Summary.Screenshot));
			ChecklistCount++;

			// One KFPreviewFrameEntry per frame, not one per map - see
			// that class's own doc comment for why (cmd.exe on this
			// project's actual runtime - Wine/CrossOver, not real
			// Windows - turned out not to reliably support the string
			// splitting/stripping a single semicolon-joined field would
			// have needed). RelRef strips the "<MapName>." prefix here,
			// in UnrealScript (Left()/Mid()/Len(), all proven reliable),
			// rather than asking the batch script to do it.
			if (Frames.Length > 0)
			{
				MapPrefix = MapNames[i] $ ".";
				for (j = 0; j < Frames.Length; j++)
				{
					FullRef = string(Frames[j]);
					if (Left(FullRef, Len(MapPrefix)) == MapPrefix)
						RelRef = Mid(FullRef, Len(MapPrefix));
					else
						RelRef = FullRef; // shouldn't happen - ref didn't start with the expected map package prefix

					FrameEntry = new(none, MapNames[i] $ "_" $ (j + 1)) class'KFPreviewFrameEntry';
					FrameEntry.MapName = MapNames[i];
					FrameEntry.FrameCount = Frames.Length;
					FrameEntry.FrameIndex = j + 1;
					FrameEntry.RelRef = RelRef;
					FrameEntry.SaveConfig();
				}
			}
		}
	}

	log("GenerateMapPreviews: wrote/updated "$WrittenCount$" entries in KFMapVotePreviews.ini; "$ChecklistCount$" still need a TextureRef (see PREVIEWMANIFEST lines above); "$SkippedCount$" map(s) failed to load entirely; "$ExcludedCount$" map(s) skipped via ExcludedMaps.");

	return 0;
}

// Resolves a map's Screenshot (LevelSummary.Screenshot, typed Material -
// see KFMapPreviewEntry.uc) down to an ordered list of exportable
// Texture frames, and reports what it found via OutStatus:
//
//   OK           - one or more frames resolved cleanly.
//   PROCEDURAL   - resolved to a single FractalTexture-family object
//                  (FireTexture/WaterTexture/IceTexture/WaveTexture/
//                  WetTexture/FluidTexture). Still a Texture with real
//                  Mips (batchexport-able), but the pixels are painted
//                  procedurally at runtime rather than authored as a
//                  screenshot - almost certainly not what you want to
//                  ship as a static preview image. Needs a human to
//                  pick/author a real one instead.
//   UNSUPPORTED  - resolved to something with no static bitmap at all
//                  (Shader/Combiner/FinalBlend/Cubemap/ScriptedTexture),
//                  a Modifier chain was broken (a .Material link was
//                  None), a MaterialSequence had no resolvable slides,
//                  or the chain was too deep/cyclic to be a real design.
//   MISSING      - Screenshot was None to begin with.
//
// Two distinct animation mechanisms exist in the wild and both are
// handled here:
//   1. Texture.AnimNext - the classic flipbook chain (a linked list of
//      separate Texture objects). Walked per leaf Texture below, with
//      cycle detection (chains aren't guaranteed to terminate in None).
//   2. MaterialSequence (Engine/Classes/MaterialSequence.uc) - a
//      slideshow/crossfade list. It extends Modifier but does NOT
//      populate the inherited .Material field - its own SequenceItems
//      array holds each slide's Material instead. Confirmed via source
//      after KF-Aperture/KF-AbusementPark (and most other animated
//      screenshots in this map pool) came back "broken modifier chain"
//      under a naive Modifier.Material-only walk - MaterialSequence,
//      not AnimNext, turned out to be the common case, not the rare one.
// A map author can also point Screenshot straight at a
// TexRotator/TexOscillator/TexPanner/TexScaler for a spinning/panning
// (but not multi-image) preview; those wrap a single real Texture via
// the same Modifier.Material field and are handled by the generic
// Modifier walk below.
function bool ResolveScreenshotFrames(Material ScreenshotMat, out array<Texture> OutFrames, out string OutStatus)
{
	local int Guard;

	Guard = 0;
	return ResolveMaterialFrames(ScreenshotMat, OutFrames, OutStatus, Guard);
}

// Recursive worker for ResolveScreenshotFrames(). Guard is threaded
// through every recursive call (including each MaterialSequence slide)
// so total chain depth across the whole call tree is capped - not just
// depth along one branch - protecting against absurd/cyclic authoring
// without needing a full visited-object graph.
function bool ResolveMaterialFrames(Material Mat, out array<Texture> OutFrames, out string OutStatus, out int Guard)
{
	local int i;
	local MaterialSequence Seq;
	local Texture Tex, FrameTex;
	local string SlideStatus;

	if (Mat == None)
	{
		OutStatus = "MISSING";
		return false;
	}

	if (Guard >= 32)
	{
		OutStatus = "UNSUPPORTED(chain too deep or cyclic)";
		return false;
	}
	Guard++;

	Seq = MaterialSequence(Mat);
	if (Seq != None)
	{
		if (Seq.SequenceItems.Length == 0)
		{
			OutStatus = "UNSUPPORTED(empty MaterialSequence)";
			return false;
		}
		for (i = 0; i < Seq.SequenceItems.Length; i++)
		{
			// Each slide is resolved independently (it may itself be a
			// plain Texture, a TexRotator-wrapped one, etc.) - a single
			// bad slide is logged and skipped rather than failing the
			// whole map.
			if (!ResolveMaterialFrames(Seq.SequenceItems[i].Material, OutFrames, SlideStatus, Guard))
				log("GenerateMapPreviews: MaterialSequence slide "$i$" of "$string(Mat)$" unresolved ("$SlideStatus$") - skipped.");
		}
		if (OutFrames.Length == 0)
		{
			OutStatus = "UNSUPPORTED(MaterialSequence - no resolvable slides)";
			return false;
		}
		OutStatus = "OK";
		return true;
	}

	if (Modifier(Mat) != None)
	{
		if (Modifier(Mat).Material == None)
		{
			OutStatus = "UNSUPPORTED(broken modifier chain)";
			return false;
		}
		return ResolveMaterialFrames(Modifier(Mat).Material, OutFrames, OutStatus, Guard);
	}

	Tex = Texture(Mat);
	if (Tex == None)
	{
		OutStatus = "UNSUPPORTED("$string(Mat.Class)$")";
		return false;
	}

	// Walk this Texture's own AnimNext flipbook chain too - a
	// MaterialSequence slide could itself be an animated Texture,
	// however unlikely in practice. Dedupes (and stops) against the
	// map's whole OutFrames list, not just this one chain-walk -
	// MaterialSequence slides are very commonly authored as a
	// (FadeToMaterial, ShowMaterial) pair referencing the *same*
	// Material back-to-back (a fade transition into a hold), so without
	// a global check a "3-image" sequence would list each image twice
	// (confirmed against real output - KF-Barzakh's 4-image loop came
	// back as 8 frames, each one adjacent-duplicated, before this fix).
	FrameTex = Tex;
	while (FrameTex != None && OutFrames.Length < 64)
	{
		if (IsTextureVisited(OutFrames, FrameTex))
			break;
		OutFrames[OutFrames.Length] = FrameTex;
		FrameTex = FrameTex.AnimNext;
	}

	if (Tex.IsA('FractalTexture'))
		OutStatus = "PROCEDURAL";
	else
		OutStatus = "OK";

	return true;
}

function bool IsTextureVisited(array<Texture> List, Texture Tex)
{
	local int i;

	for (i = 0; i < List.Length; i++)
		if (List[i] == Tex)
			return true;

	return false;
}

// Dynamic array .Find() isn't available in this SDK build (confirmed via
// compile error - a later-UnrealScript-only feature this KF1 checkout
// doesn't have) - plain linear scan instead, same pattern as
// IsTextureVisited() above.
function bool IsMapExcluded(string MapName)
{
	local int i;

	for (i = 0; i < ExcludedMaps.Length; i++)
		if (ExcludedMaps[i] == MapName)
			return true;

	return false;
}

defaultproperties
{
	HelpCmd="GenerateMapPreviews"
	HelpOneLiner="Scaffolds KFMapVotePreviews.ini (Author/PlayerCount) and writes KFMapVoteSTPreviewManifest.ini for the texture export/import pipeline. Optional MapName arg scopes the run to just that one map (see Tools/Setup-SingleMapPreview.bat)."
	HelpUsage="ucc GenerateMapPreviews [MapName]"
	LogToStdout=true
}
