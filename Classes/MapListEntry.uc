// ====================================================================
//  MapListEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  Pure PerObjectConfig marker class - carries no data of its own, only
//  its section name (= a map filename, no extension) matters.
//  GenerateMapPreviewsCommandlet enumerates every map to process via
//  GetPerObjectNames("KFMapVoteSTMapList", "MapListEntry", 1024) against
//  KFMapVoteSTMapList.ini, rather than via CacheManager.GetMapList().
//
//  Why not CacheManager: confirmed empirically (2026-08-08) - it reads a
//  persisted native cache database (System/CacheRecords.ucl), not a live
//  scan of Maps/, and that database was never populated with any Map=
//  entries in this SDK checkout (dated Dec 2013, contains only 7 stock
//  Announcer/Crosshair/Mutator entries). The usual fix - UnrealEd's
//  Content Browser "recache" action - isn't available in this build
//  either. So this ini + GetPerObjectNames is used purely as a static
//  list of map names to iterate; each map's actual Author/PlayerCount/
//  Screenshot data is then read straight from that map's own
//  LevelSummary object (DynamicLoadObject(MapName$".LevelSummary",
//  class'LevelSummary', true) - see GenerateMapPreviewsCommandlet.uc),
//  not from CacheManager and not from this class's fields.
//
//  Regenerate KFMapVoteSTMapList.ini whenever Maps/ changes - see
//  generate_map_list.sh at the KFMapVoteST package root.
// ====================================================================
class MapListEntry extends Object
	PerObjectConfig
	Config(KFMapVoteSTMapList);
