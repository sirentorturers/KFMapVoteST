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
// "Copy" mirrors another mode's MapListStyle/AllowMap/ExcludeMap instead
// of duplicating them here - set CopyMapList to the target mode's section
// ID (the permanent instance ID described at the top of this file, e.g.
// "00_Standard_Hard" - NOT its GameName), useful for keeping every
// difficulty tier of the same mode in sync without hand-copying the list
// to each one. Resolved once, server-side, in KFVotingHandler.
// BuildGameConfig() (see ResolveMapList()) - copying a mode that itself
// uses Copy is followed transitively; a cycle or a missing/misspelled
// target ID falls back to "All" rather than failing.
// AllowMap/ExcludeMap/CopyMapList are only read when MapListStyle selects
// them - like Description, none of this is part of the base engine's
// MapVoteGameConfigLite struct, so it can't ride along with GameConfig's
// existing replication - see KFVotingHandler.GameConfigMapListStyle/
// GameConfigMapListValue and KFVotingReplicationInfo.ReceiveGameConfigRep()
// for how the resolved result reaches the client (same per-item RPC
// pattern already proven safe for Description).
var config string MapListStyle;
var config array<string> AllowMap;
var config array<string> ExcludeMap;
var config string CopyMapList;

// Optional kill-switch for a mode. Default false (mode behaves exactly as
// before this field existed). Set true to hide this mode from the vote GUI
// entirely without deleting/commenting out its section - useful for
// temporarily pulling a mode without losing its config. Entries with
// bDisabled=true are dropped in KFVotingHandler.BuildGameConfig() before
// they ever reach the live GameConfig array, so nothing downstream (GUI
// list, vote submission, IsMapValidForGameConfig, WebAdmin blocking) needs
// to know this field exists - a disabled mode simply isn't there, same as
// if its section had been deleted. Named bDisabled, not Disable - a real
// ucc compile warning ('Disable' obscures 'Disable' defined in base class
// 'Object') caught that Object already declares a native Disable(name)
// function; same class of reserved-name collision as the Style/Actor.Style
// lesson elsewhere in this package - verify against real compiler output,
// don't assume a plain-English field name is free to use.
var config bool bDisabled;

defaultproperties
{
	SortOrder=0
	MapListStyle="All"
	bDisabled=false
}
