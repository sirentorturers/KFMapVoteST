// ====================================================================
//  KFRandomMapVoteFlag
//  SirenTorturers Edition (KFMapVoteST)
//
//  Tiny, standalone signal written by KFVotingHandler.SetRandomMapVoteFlag()
//  right before every vote-resolution Level.ServerTravel() call, recording
//  whether the map just chosen came from a winning "RANDOM MAP" vote (see
//  KFVotingHandler.AddRandomMapSentinel()/TallyVotesInternal()).
//
//  This class has zero awareness of any other mod - KFMapVoteST compiles
//  and runs identically whether anything ever reads KFMapVoteSTRandomFlag.ini
//  or not. A separate mod (ScrnBalanceST) may optionally read this value
//  after the map change to drive its own "random map" stat bonus, the same
//  way it already does for its own unrelated `mvote map random` chat-vote
//  feature - see that mod's ScrnBalance.uc for the reader side. The
//  dependency, if any, runs only that direction (reader depends on this
//  class's name/section), never the other way.
// ====================================================================
class KFRandomMapVoteFlag extends Object
	Config(KFMapVoteSTRandomFlag);

var config bool bWasRandomMapVote;
