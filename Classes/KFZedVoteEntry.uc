// ====================================================================
//  KFZedVoteEntry
//  SirenTorturers Edition (KFMapVoteST)
//
//  One instance per zed vote name (object name = the same Vote key
//  ScrnZedInfo.Zeds[].Vote/ScrnGameLength.ZedVotes already use, e.g.
//  "BRUTE"). Written server-side by ScrnBalanceST.ScrnZedVoting.
//  PublishZedVoteStates() and read server-side by KFVotingHandler.
//  RefreshZedVotes(), then replicated to clients - see
//  KFVotingReplicationInfo.ReceiveZedVoteRep()/TickedReplication_ZedVotes()
//  for the per-item RPC that carries it the rest of the way to the lobby
//  GUI (KFMapVotingPageX).
//
//  This class has zero awareness of ScrnBalanceST - KFMapVoteST compiles
//  and runs identically whether anything ever writes to
//  KFMapVoteSTZedVotes.ini or not (RefreshZedVotes() just finds no
//  sections and the zed panel stays empty). Same isolation as
//  KFRandomMapVoteFlag; the read/write plumbing is one-directional via
//  DynamicLoadObject on the ScrnBalanceST side, since a hard class
//  reference between these two packages doesn't compile in either
//  direction (see CLAUDE.md).
// ====================================================================
class KFZedVoteEntry extends Object
	PerObjectConfig
	Config(KFMapVoteSTZedVotes);

// 0=Off (red), 1=On (green), 2=Mixed (yellow) - matches
// ScrnZedVoting.VoteState()'s return value and its own SendGroupHelp()
// color convention exactly, so no re-mapping is needed on either side.
var config byte State;
