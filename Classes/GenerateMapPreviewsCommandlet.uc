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
//  console - see ResolveScreenshotFrames() below for what it contains
//  and why a map's raw Screenshot reference isn't always itself an
//  exportable Texture. Reruns only show what's still outstanding.
// ====================================================================
class GenerateMapPreviewsCommandlet extends Commandlet;

event int Main(string Parms)
{
	local array<string> MapNames;
	local LevelSummary Summary;
	local KFMapPreviewEntry Entry;
	local int i, j, WrittenCount, ChecklistCount, SkippedCount;
	local array<Texture> Frames;
	local string FrameList, Status;

	MapNames = GetPerObjectNames("KFMapVoteSTMapList", "MapListEntry", 1024);
	log("GenerateMapPreviews: found "$MapNames.Length$" maps listed in KFMapVoteSTMapList.ini (regenerate via generate_map_list.sh if this looks stale).");

	for (i = 0; i < MapNames.Length; i++)
	{
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

		if (Entry.TextureRef == "" && Summary.Screenshot != None)
		{
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

			// Pipe-delimited so an external script can split on "|"
			// without worrying about ucc's console prefixing/spacing.
			// FrameList is empty whenever Status isn't OK/OK+ - the raw
			// src= ref is always included so a human can go look at the
			// map manually for anything flagged PROCEDURAL/UNSUPPORTED.
			log("PREVIEWMANIFEST|"$MapNames[i]$"|"$Status$"|"$FrameList$"|src="$string(Summary.Screenshot));
			ChecklistCount++;
		}
	}

	log("GenerateMapPreviews: wrote/updated "$WrittenCount$" entries in KFMapVotePreviews.ini; "$ChecklistCount$" still need a TextureRef (see PREVIEWMANIFEST lines above); "$SkippedCount$" map(s) failed to load entirely.");

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

defaultproperties
{
	HelpCmd="GenerateMapPreviews"
	HelpOneLiner="Scaffolds KFMapVotePreviews.ini (Author/PlayerCount) and logs a PREVIEWMANIFEST checklist for the texture package."
	HelpUsage="ucc GenerateMapPreviews"
	LogToStdout=true
}
