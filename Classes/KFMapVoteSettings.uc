// ====================================================================
//  KFMapVoteSettings - SirenTorturers Edition (KFMapVoteST)
//
//  Exists purely to hold DifficultyOrder in KFMapVoteModes.ini alongside
//  the mode entries themselves, while KFVotingHandler's other settings
//  stay in KFMapVote.ini as before. This engine's UnrealScript does NOT
//  support per-variable config-file overrides (var config(OtherIni) ...)
//  - only whole-class Config() targets - confirmed via compile error
//  ("Missing variable type") when that syntax was tried directly on
//  KFVotingHandler. This class is never instantiated; its config values
//  are read straight off the class default object, e.g.
//  class'KFMapVoteSettings'.default.DifficultyOrder.
// ====================================================================
class KFMapVoteSettings extends Object
	Config(KFMapVoteModes);

// Display order for the difficulty dropdown's distinct values, e.g.
// "Hard","Suicidal","Hell on Earth","Brutal". Any Difficulty value found on
// a KFGameConfigEntry that isn't listed here still shows up in the dropdown -
// it's just appended alphabetically after everything listed here.
var config array<string> DifficultyOrder;

defaultproperties
{
}
