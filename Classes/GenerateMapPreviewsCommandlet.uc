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
//  whole mechanism exists to bypass. Reads every locally installed map
//  via CacheManager (the same native map cache
//  KFMapVoteFooterX.UpdateMapPreview() already falls back to) and
//  writes/updates a KFMapVotePreviews.ini section per map with
//  whatever Author/PlayerCount data it finds, via SaveConfig() - the
//  native PerObjectConfig persistence mechanism, so reruns merge
//  cleanly instead of overwriting the whole file or clobbering entries
//  you've already hand-edited.
//
//  This only handles the metadata half. TextureRef is deliberately left
//  untouched by this commandlet (existing values are preserved as-is,
//  new entries are left blank) since it must point into a shared
//  texture package built separately (see KFMapPreviewEntry.uc) - this
//  commandlet instead logs each map's own native ScreenshotRef to the
//  console as a checklist of what to export into that package next,
//  and skips the checklist line for maps that already have a
//  TextureRef set, so reruns only show what's left to do.
// ====================================================================
class GenerateMapPreviewsCommandlet extends Commandlet;

event int Main(string Parms)
{
	local array<CacheManager.MapRecord> AllMaps;
	local KFMapPreviewEntry Entry;
	local int i, WrittenCount, ChecklistCount;

	class'CacheManager'.static.InitCache();
	class'CacheManager'.static.GetMapList(AllMaps);

	log("GenerateMapPreviews: found "$AllMaps.Length$" locally cached maps.");

	for (i = 0; i < AllMaps.Length; i++)
	{
		if (AllMaps[i].ScreenshotRef == "" && AllMaps[i].Author == "" && AllMaps[i].PlayerCountMin == 0 && AllMaps[i].PlayerCountMax == 0)
			continue; // nothing usable for this map - skip

		// Constructing by exact name first loads whatever's already in
		// KFMapVotePreviews.ini for this map (including a hand-set
		// TextureRef) - we only touch Author/PlayerCount below, so any
		// existing TextureRef survives the SaveConfig() call unchanged.
		Entry = new(none, AllMaps[i].MapName) class'KFMapPreviewEntry';

		Entry.Author = AllMaps[i].Author;
		Entry.PlayerCountMin = AllMaps[i].PlayerCountMin;
		Entry.PlayerCountMax = AllMaps[i].PlayerCountMax;
		Entry.SaveConfig();
		WrittenCount++;

		if (Entry.TextureRef == "" && AllMaps[i].ScreenshotRef != "")
		{
			log("GenerateMapPreviews: NEEDS TEXTURE - "$AllMaps[i].MapName$" -> export '"$AllMaps[i].ScreenshotRef$"' into the shared preview package, then set TextureRef in KFMapVotePreviews.ini.");
			ChecklistCount++;
		}
	}

	log("GenerateMapPreviews: wrote/updated "$WrittenCount$" entries in KFMapVotePreviews.ini; "$ChecklistCount$" still need a TextureRef.");

	return 0;
}

defaultproperties
{
	HelpCmd="GenerateMapPreviews"
	HelpOneLiner="Scaffolds KFMapVotePreviews.ini (Author/PlayerCount) from every locally-installed map."
	HelpUsage="ucc GenerateMapPreviews"
	LogToStdout=true
}
