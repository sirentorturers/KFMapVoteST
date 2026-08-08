// ====================================================================
//  KFMapPreviewEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  One instance = one map's preview override, keyed by the section name,
//  which must be the exact map filename with no extension (e.g.
//  "KF-Boardwalk"). PerObjectConfig, so KFMapVotePreviews.ini looks like:
//
//      [KF-Boardwalk KFMapPreviewEntry]
//      TextureRef=KFMapVoteST_Previews.KF-Boardwalk_Preview
//      Author={ST}WaffleTime | {ST}Broski
//      PlayerCountMin=6
//      PlayerCountMax=12
//
//  Why this exists: the in-game map vote preview panel (see
//  KFMapVoteFooterX.UpdateMapPreview()) can only read a map's own
//  embedded screenshot/author/player-count if the connecting client
//  already has that map's full package downloaded locally - true only
//  for maps they've already played (confirmed via client log: both the
//  native map cache and a live LevelSummary load fail with the exact
//  same "Can't find file for package" error for any map the client
//  hasn't loaded before). TextureRef should point into a small shared
//  texture package (e.g. KFMapVoteST_Previews.utx) that ships alongside
//  this mod - same as KFAnnounc.uax already does - so it reaches every
//  client regardless of their local map cache.
//
//  IMPORTANT: this class (and KFMapVotePreviews.ini) is only ever
//  constructed SERVER-SIDE, in KFVotingHandler.AddMap(). Config/
//  PerObjectConfig reads only see whatever ini exists on the machine
//  actually running the code - a client has no local copy of this ini
//  at all, so an earlier version that constructed this client-side in
//  KFMapVoteFooterX always came back empty. The resolved data is instead
//  read here once per map on the server and replicated to every client
//  one map at a time (see KFVotingHandler.FMapPreviewData/
//  MapPreviewArray and KFVotingReplicationInfo.MapPreviewList) - the
//  same proven mechanism the map-rating data already uses, not a new
//  bulk-replicated property.
//
//  Constructed directly by exact map name (new(none, MapName)) rather
//  than discovered via GetPerObjectNames() - the server already knows
//  the map name it's looking up and just needs to know whether a
//  section for it exists, which an empty TextureRef after construction
//  already tells it (PerObjectConfig falls back to defaultproperties -
//  "" - when no matching section exists).
// ====================================================================
class KFMapPreviewEntry extends Object
	PerObjectConfig
	Config(KFMapVotePreviews);

var config string TextureRef;
var config string Author;
var config int PlayerCountMin;
var config int PlayerCountMax;

defaultproperties
{
	TextureRef=""
	Author=""
	PlayerCountMin=0
	PlayerCountMax=0
}
