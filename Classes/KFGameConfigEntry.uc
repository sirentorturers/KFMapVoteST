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

// Optional explicit ordering. Sections are read back via
// GetPerObjectNames() in whatever order the engine returns them
// (typically file order, but not guaranteed) - if you need the vote list
// in a specific order regardless of file layout/edits, set SortOrder on
// each entry and KFVotingHandler.BuildGameConfig() will sort by it.
// Leave at the default (0) on every entry to just take file order as-is.
var config int SortOrder;

// Free-text difficulty label for the difficulty dropdown filter, e.g.
// "Hard", "Suicidal", "Hell on Earth", "Brutal". Not tied to ScrnGames.ini's
// MinDifficulty/MaxDifficulty in any way - those numbers can't distinguish
// e.g. Brutal from Hell on Earth (both are MinDifficulty=MaxDifficulty=7 in
// ScrnGames.ini), so this is a purely independent, admin-controlled label.
// Leave blank to exclude this entry from difficulty filtering entirely
// (it will always show, regardless of the selected difficulty).
var config string Difficulty;

// Optional override for which "mode family" this entry belongs to, used
// to find a same-mode fallback when the player changes difficulty and this
// exact entry doesn't exist at the new tier (e.g. "Standard: Hard" and
// "Standard: Suicidal" should be recognized as the same family).
// Leave blank and KFVotingHandler.BuildGameConfig() will derive it
// automatically from the section's own instance ID by stripping a leading
// "NN_" index and a trailing recognized difficulty token - e.g.
// "Classic_Sui" -> "Classic". Only set this explicitly if the automatic
// derivation guesses wrong for a particular section name.
var config string ModeGroup;

defaultproperties
{
	SortOrder=0
}
