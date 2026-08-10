// ====================================================================
//  KFGameConfigEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  One instance of this class = one game mode entry in the map vote's
//  game type list (equivalent to one of the old GameConfig=(...) struct
//  literals). PerObjectConfig means each instance gets its own INI
//  section, keyed by the object's name:
//
//      [00_StandardHard KFGameConfigEntry]
//      GameClass=SirenTorturers.G
//      Prefix=KF-
//      Acronym=KF
//      GameName=00. Standard: Hard
//      Options=GameLength=178
//
//  Every section is parsed independently, so there is no shared array
//  and no shared 4095-character budget across modes - a config file
//  can hold as many of these sections as you want.
//
//  Instances are discovered at runtime via GetPerObjectNames()
//  and constructed on demand via new(none, SectionName) - see
//  KFVotingHandler.BuildGameConfig(). The section's leading token
//  (e.g. "00_StandardHard") is a permanent instance ID, not a display
//  name - GameName is what actually shows up in the vote screen.
// ====================================================================
class KFGameConfigEntry extends Object
	PerObjectConfig
	Config(KFMapVoteModes);

var config string GameClass;
var config string Prefix;
var config string Acronym;
var config string GameName;
var config string Mutators;
var config string Options;

// Optional flavor text shown in the map vote GUI's description panel when
// this mode is selected (see KFMapVotingPageX.UpdateDescriptionLabel()).
// Blank is fine - the panel just stays empty for that mode. Not part of
// the base engine's MapVoteGameConfigLite struct, so it can't ride along
// with GameConfig's existing replication - see KFVotingHandler.
// GameConfigDescriptions / KFVotingReplicationInfo.ReceiveGameConfigRep()
// for how it actually reaches the client (same per-item RPC pattern
// already proven safe for MapPreviewList).
var config string Description;

// Optional explicit ordering. Sections are read back via
// GetPerObjectNames() in whatever order the engine returns them
// (typically file order, but not guaranteed) - if you need the vote list
// in a specific order regardless of file layout/edits, set SortOrder on
// each entry and KFVotingHandler.BuildGameConfig() will sort by it.
// Leave at the default (0) on every entry to just take file order as-is.
var config int SortOrder;

// Per-mode map list restriction. "All" (default) offers every map that
// already matches Prefix, same as before this field existed. "Allow"
// restricts this mode to only the maps listed in AllowMap. "Exclude"
// offers every Prefix-matching map except the ones listed in ExcludeMap.
// AllowMap/ExcludeMap are only read when MapListStyle selects them - like
// Description, this isn't part of the base engine's MapVoteGameConfigLite
// struct, so it can't ride along with GameConfig's existing replication -
// see KFVotingHandler.GameConfigMapListStyle/GameConfigMapListValue and
// KFVotingReplicationInfo.ReceiveGameConfigRep() for how it reaches the
// client (same per-item RPC pattern already proven safe for Description).
var config string MapListStyle;
var config array<string> AllowMap;
var config array<string> ExcludeMap;

defaultproperties
{
	SortOrder=0
	MapListStyle="All"
}
