// ====================================================================
//  KFVotingReplicationInfo - Modification by Marco
// ====================================================================
class KFVotingReplicationInfo extends VotingReplicationInfo
	DependsOn(KFVotingHandler);

#exec obj load file="KFAnnounc.uax" package="KFMapVoteST"

var array<string> RepArray,SortedArray; // Displayed rep string

// Client-side mirror of KFVotingHandler.MapPreviewArray, kept in sync
// with MapList exactly like RepArray/SortedArray already are - filled in
// by ReceiveMapInfoRep()/TickedReplication_MapList() below, never
// declared in the replication{} block itself since it travels as an
// extra parameter on the already-replicated ReceiveMapInfoRep call
// rather than as its own bulk-replicated property.
var array<KFVotingHandler.FMapPreviewData> MapPreviewList;

// Client-side mirror of KFVotingHandler.GameConfigDescriptions, index-
// matched with the inherited GameConfig array exactly like MapPreviewList
// is matched with MapList above - filled in by the overridden
// TickedReplication_GameConfig()/ReceiveGameConfigRep() below, never
// declared in the replication{} block itself for the same reason
// MapPreviewList isn't (see KFVotingHandler.GameConfigDescriptions and
// CLAUDE.md's replication gotchas).
var array<string> GameConfigDescriptions;

// Client-side mirror of KFVotingHandler.GameConfigMapListStyle/
// GameConfigMapListValue, index-matched with GameConfig the same way
// GameConfigDescriptions is above - filled in by the same overridden
// TickedReplication_GameConfig()/ReceiveGameConfigRep() below (its RPC
// parameter list is widened further rather than adding a new
// bulk-replicated property, for the same reason GameConfigDescriptions
// isn't declared in the replication{} block itself).
var array<string> GameConfigMapListStyle;
var array<string> GameConfigMapListValue;

// Client-side mirror of KFVotingHandler.GameConfigDifficulty, index-matched
// with GameConfig the same way GameConfigDescriptions is above - filled in
// by the same overridden TickedReplication_GameConfig()/
// ReceiveGameConfigRep() below (its RPC parameter list is widened further,
// same reasoning as GameConfigDescriptions/GameConfigMapListStyle/
// GameConfigMapListValue not being declared in the replication{} block
// itself). KFMapVotingPageX reads this directly instead of deriving
// difficulty client-side from GameName text.
var array<string> GameConfigDifficulty;

var sound AnnounceSnds[13];
var byte MapRepVote;
var bool bClientHasInit;
var bool bShowMapLike;

// Server-configured (KFMapVote.ini) preview-animation playback speed -
// see KFVotingHandler.PreviewAnimFrameRate for the full rationale.
// Replicated the same way bShowMapLike already is: a single scalar sent
// once at bNetInitial, not a new replication statement or an array -
// deliberately the lower-risk shape per this package's own crash
// history with new replicated properties (see CLAUDE.md).
var float PreviewAnimFrameRate;

replication
{
	reliable if( Role==ROLE_Authority && bNetInitial )
		bShowMapLike, PreviewAnimFrameRate;
	reliable if( Role==ROLE_Authority )
		ReceiveMapInfoRep, ReceiveGameConfigRep;
	reliable if( Role<ROLE_Authority )
		SendMapRepVote;
}

simulated final function InitClient()
{
	local PlayerController PC;

	bClientHasInit = true;
	PC = Level.GetLocalPlayerController();
	if( PC!=None )
		Class'MVLevelCleanup'.Static.AddVotingReplacement(PC);
}
simulated function Tick(float DeltaTime)
{
	if( !bClientHasInit )
		InitClient();
	Super.Tick(DeltaTime);
}
simulated function PlayCountDown(int Count)
{
	local byte Idx;

	if( PlayerOwner==None )
		return;
	switch( Count )
	{
	case 60:
		Idx = 12;
		break;
	case 30:
		Idx = 11;
		break;
	case 20:
		Idx = 10;
		break;
	default:
		Idx = Min(Count-1,9);
		break;
	}
	PlayerOwner.ClientPlaySound(AnnounceSnds[Idx],true,2.f,SLOT_Talk);
	PlayerOwner.ReceiveLocalizedMessage(Class'KFVoteTimeMessage',Idx);
}
simulated function OpenWindow()
{
	if( GetController().FindMenuByClass(Class'KFMapVotingPageX')==None ) // Only open when aren't already open.
	{
		GetController().OpenMenu(string(Class'KFMapVotingPageX'));
		if (bShowMapLike) {
			GetController().OpenMenu(string(Class'MVLikePage'));
		}
	}
}
// Overrides the base xVoting.VotingReplicationInfo version entirely
// (same approach as TickedReplication_MapList below) so the per-mode
// Description text can ride along with the existing GameConfig entry
// instead of arriving as a separate RPC - mirrors ReceiveMapInfoRep
// widening the base map RPC's parameter list rather than adding a new
// bulk-replicated property. Not simulated, matching the base signature -
// this only ever runs server-side (see VotingReplicationInfo.Tick()).
function TickedReplication_GameConfig(int Index, bool bDedicated)
{
	local VotingHandler.MapVoteGameConfigLite GameConfigItem;
	local string Description,MapListStyle,MapListValue,Difficulty;

	GameConfigItem = VH.GetGameConfig(Index);
	Description = KFVotingHandler(VH).GetGameConfigDescription(Index);
	MapListStyle = KFVotingHandler(VH).GetGameConfigMapListStyle(Index);
	MapListValue = KFVotingHandler(VH).GetGameConfigMapListValue(Index);
	Difficulty = KFVotingHandler(VH).GetGameConfigDifficulty(Index);
	DebugLog("___Sending " $ Index $ " - " $ GameConfigItem.GameName);

	if( bDedicated )
	{
		ReceiveGameConfigRep(GameConfigItem, Description, MapListStyle, MapListValue, Difficulty); // replicate one GameConfig entry each tick.
		bWaitingForReply = True;
	}
	else
	{
		GameConfig[GameConfig.Length] = GameConfigItem;
		GameConfigDescriptions[GameConfigDescriptions.Length] = Description;
		GameConfigMapListStyle[GameConfigMapListStyle.Length] = MapListStyle;
		GameConfigMapListValue[GameConfigMapListValue.Length] = MapListValue;
		GameConfigDifficulty[GameConfigDifficulty.Length] = Difficulty;
	}
}

function TickedReplication_MapList(int Index, bool bDedicated)
{
 	local VotingHandler.MapVoteMapList MapInfo;

	MapInfo = VH.GetMapList(Index);
	DebugLog("___Sending " $ Index $ " - " $ MapInfo.MapName);

	if( bDedicated )
	{
		ReceiveMapInfoRep(MapInfo,KFVotingHandler(VH).RepArray[Index],KFVotingHandler(VH).MapPreviewArray[Index]); // replicate one map each tick until all maps are replicated.
		bWaitingForReply = True;
	}
	else
	{
		MapList[MapList.Length] = MapInfo;
		InitRepStr(MapList.Length-1,KFVotingHandler(VH).RepArray[Index]);
		MapPreviewList[MapPreviewList.Length] = KFVotingHandler(VH).MapPreviewArray[Index];
	}
}

simulated function ReceiveMapInfoRep( VotingHandler.MapVoteMapList MapInfo, KFVotingHandler.FMapRepType Rep, KFVotingHandler.FMapPreviewData Preview )
{
	MapList[MapList.Length] = MapInfo;
	InitRepStr(MapList.Length-1,Rep);
	MapPreviewList[MapPreviewList.Length] = Preview;
	ReplicationReply();
}

// Client-side receiver for TickedReplication_GameConfig()'s widened send
// above - stores into GameConfig exactly like the base engine's own
// ReceiveGameConfig() would, plus the extra Description text into
// GameConfigDescriptions at the same (matching) index.
simulated function ReceiveGameConfigRep( VotingHandler.MapVoteGameConfigLite p_GameConfig, string Description, string MapListStyle, string MapListValue, string Difficulty )
{
	GameConfig[GameConfig.Length] = p_GameConfig;
	GameConfigDescriptions[GameConfigDescriptions.Length] = Description;
	GameConfigMapListStyle[GameConfigMapListStyle.Length] = MapListStyle;
	GameConfigMapListValue[GameConfigMapListValue.Length] = MapListValue;
	GameConfigDifficulty[GameConfigDifficulty.Length] = Difficulty;
	ReplicationReply();
}

simulated final function InitRepStr( int i, KFVotingHandler.FMapRepType Rep )
{
	local float Rating;
	local byte R,G;

	RepArray.Length = i+1;
	SortedArray.Length = i+1;

	// Map not yet rated.
	if( Rep.Positive==0 && Rep.Negative==0 )
	{
		SortedArray[i] = "0000";

		// Map never played.
		if( MapList[i].PlayCount==0 )
			RepArray[i] = "**NEW**";
		else RepArray[i] = "N/A";
	}
	else
	{
		Rating = float(Rep.Positive) / float(Rep.Positive + Rep.Negative); // Scaled 0-1 (0 = negative, 1 = positive)

		if( Rating<0.5f )
		{
			R = 255;
			G = 510.f*Rating;
			if( G==0 || G==10 )
				++G;
		}
		else
		{
			R = 510.f*(1.f-Rating);
			G = 255;
			if( R==0 || R==10 )
				++R;
		}
		RepArray[i] = Chr(0x1B)$Chr(R)$Chr(G)$Chr(1)$(Rating*100.f)@"% ("$Rep.Positive$"/"$(Rep.Positive+Rep.Negative)@"likes)";
		SortedArray[i] = string(int(Rating*100.f));
		SortedArray[i] = Right("0000"$SortedArray[i],4);
	}
}

simulated function bool SetMapLike(bool bLiked)
{
	local byte NewValue;

	NewValue = 2 - byte(bLiked);
	if (NewValue == MapRepVote)
		return false;


	MapRepVote = NewValue;
	SendMapRepVote(MapRepVote);
	return true;
}

function SendMapRepVote(byte value) {
	MapRepVote = value;
}


defaultproperties
{
	bShowMapLike=false

	AnnounceSnds(0)=one
	AnnounceSnds(1)=two
	AnnounceSnds(2)=three
	AnnounceSnds(3)=four
	AnnounceSnds(4)=five
	AnnounceSnds(5)=six
	AnnounceSnds(6)=seven
	AnnounceSnds(7)=eight
	AnnounceSnds(8)=nine
	AnnounceSnds(9)=ten
	AnnounceSnds(10)=20_seconds
	AnnounceSnds(11)=30_seconds_remain
	AnnounceSnds(12)=1_minute_remains
}