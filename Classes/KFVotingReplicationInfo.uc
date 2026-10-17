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

// Client-side mirror of KFVotingHandler.GameConfigDifficultySort, index-
// matched with GameConfigDifficulty - delivered the same way.
var array<int> GameConfigDifficultySort;

// Client-side accumulators for TickedReplication_GameConfig()'s chunked
// Description/MapListValue send (see GAMECONFIG_TEXT_CHUNK below) - filled
// piecewise by ReceiveGameConfigText(), then consumed and cleared by the
// ReceiveGameConfigRep() call that always follows them for the same entry.
var string PendingDescription;
var string PendingMapListValue;

// Max characters of Description/MapListValue carried per RPC. UE2 can't
// split a single function call across packets - one whose parameters
// don't fit in a packet (~500 bytes) is silently dropped ("Call bunch
// overflowed", DevNetTraffic only), so ReplicationReply() never comes back
// and the client sits on "Downloading Map List" forever. Previously both
// strings rode inside ReceiveGameConfigRep() itself, so any mode with a
// long Description or a long AllowMap=/ExcludeMap= list stalled the whole
// download. 150 chars stays under the limit even if the text is non-ANSI
// (sent as 2 bytes/char).
const GAMECONFIG_TEXT_CHUNK = 150;

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

// Client-side mirror of KFVotingHandler.ZedVoteNames/ZedVoteStates -
// unlike MapPreviewList/GameConfigDescriptions above, this data can change
// value at an already-delivered index (a zed vote resolving mid-map), which
// the base engine's per-item "deliver index 0..Count-1 once" catch-up
// machinery (TickedReplication_MapList/GameConfig) has no facility for -
// so this pair is a plain on-demand request/response RPC round trip
// instead, driven by KFMapVotingPageX when the zed panel actually needs to
// show something, not a continuous background sync. Both a client-facing
// request that only ever executes server-side once network-routed
// (RequestZedVoteRefresh, same shape as SendMapRepVote below) and a
// server-facing response that only ever executes client-side
// (ReceiveZedVoteCount/ReceiveZedVoteItem, same shape as ReceiveMapInfoRep/
// ReceiveGameConfigRep above) - not a new bulk-replicated property in
// either direction.
var array<string> ZedVoteNames;
var array<byte> ZedVoteStates;

replication
{
	reliable if( Role==ROLE_Authority && bNetInitial )
		bShowMapLike, PreviewAnimFrameRate;
	reliable if( Role==ROLE_Authority )
		ReceiveMapInfoRep, ReceiveGameConfigRep, ReceiveGameConfigText, ReceiveZedVoteCount, ReceiveZedVoteItem;
	reliable if( Role<ROLE_Authority )
		SendMapRepVote, RequestZedVoteRefresh;
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
	local int DifficultySort;

	GameConfigItem = VH.GetGameConfig(Index);
	Description = KFVotingHandler(VH).GetGameConfigDescription(Index);
	MapListStyle = KFVotingHandler(VH).GetGameConfigMapListStyle(Index);
	MapListValue = KFVotingHandler(VH).GetGameConfigMapListValue(Index);
	Difficulty = KFVotingHandler(VH).GetGameConfigDifficulty(Index);
	DifficultySort = KFVotingHandler(VH).GetGameConfigDifficultySort(Index);
	DebugLog("___Sending " $ Index $ " - " $ GameConfigItem.GameName);

	if( bDedicated )
	{
		// Unbounded text first, in packet-sized pieces (see
		// GAMECONFIG_TEXT_CHUNK) - reliable RPCs arrive in order, so these
		// are always fully delivered before the ReceiveGameConfigRep() below.
		SendGameConfigText(0, Description);
		SendGameConfigText(1, MapListValue);
		ReceiveGameConfigRep(GameConfigItem, MapListStyle, Difficulty, DifficultySort); // replicate one GameConfig entry each tick.
		bWaitingForReply = True;
	}
	else
	{
		GameConfig[GameConfig.Length] = GameConfigItem;
		GameConfigDescriptions[GameConfigDescriptions.Length] = Description;
		GameConfigMapListStyle[GameConfigMapListStyle.Length] = MapListStyle;
		GameConfigMapListValue[GameConfigMapListValue.Length] = MapListValue;
		GameConfigDifficulty[GameConfigDifficulty.Length] = Difficulty;
		GameConfigDifficultySort[GameConfigDifficultySort.Length] = DifficultySort;
	}
}

// Server-side: splits Text into GAMECONFIG_TEXT_CHUNK-sized pieces and
// sends each via ReceiveGameConfigText(). Field 0 = Description,
// 1 = MapListValue. Empty text sends nothing.
function SendGameConfigText(byte Field, string Text)
{
	local int i;

	for( i=0; i<Len(Text); i+=GAMECONFIG_TEXT_CHUNK )
		ReceiveGameConfigText(Field, Mid(Text, i, GAMECONFIG_TEXT_CHUNK));
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

// Client-side receiver for SendGameConfigText()'s chunks above - appends
// to the pending buffer for the GameConfig entry about to arrive.
simulated function ReceiveGameConfigText( byte Field, string Chunk )
{
	if( Field == 0 )
		PendingDescription = PendingDescription $ Chunk;
	else
		PendingMapListValue = PendingMapListValue $ Chunk;
}

// Client-side receiver for TickedReplication_GameConfig()'s widened send
// above - stores into GameConfig exactly like the base engine's own
// ReceiveGameConfig() would, plus the extra Description text into
// GameConfigDescriptions at the same (matching) index. Description/
// MapListValue were already delivered piecewise by ReceiveGameConfigText()
// just before this call - consumed here and cleared for the next entry.
simulated function ReceiveGameConfigRep( VotingHandler.MapVoteGameConfigLite p_GameConfig, string MapListStyle, string Difficulty, int DifficultySort )
{
	GameConfig[GameConfig.Length] = p_GameConfig;
	GameConfigDescriptions[GameConfigDescriptions.Length] = PendingDescription;
	GameConfigMapListStyle[GameConfigMapListStyle.Length] = MapListStyle;
	GameConfigMapListValue[GameConfigMapListValue.Length] = PendingMapListValue;
	GameConfigDifficulty[GameConfigDifficulty.Length] = Difficulty;
	GameConfigDifficultySort[GameConfigDifficultySort.Length] = DifficultySort;
	PendingDescription = "";
	PendingMapListValue = "";
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

// Called BY the client (see KFMapVotingPageX) - routed to the server by
// the "Role<ROLE_Authority" replication statement above, same as
// SetMapLike()/SendMapRepVote() already do. Not simulated, so the body
// only actually runs server-side.
function RequestZedVoteRefresh()
{
	local KFVotingHandler KVH;
	local int i;

	KVH = KFVotingHandler(VH);
	if ( KVH == none )
		return;

	KVH.RefreshZedVotes();
	ReceiveZedVoteCount(KVH.ZedVoteNames.Length);
	for( i=0; i<KVH.ZedVoteNames.Length; i++ )
		ReceiveZedVoteItem(i, KVH.ZedVoteNames[i], KVH.ZedVoteStates[i]);
}

// Server-authoritative response to RequestZedVoteRefresh() above - routed
// to the requesting client by the "Role==ROLE_Authority" replication
// statement above, same as ReceiveMapInfoRep/ReceiveGameConfigRep. Sent as
// a count followed by one call per entry rather than whole arrays: UE2
// can't replicate dynamic arrays (as properties OR function parameters),
// and one call carrying every entry could also exceed a single packet.
// The count resizes (and so can shrink) the client mirror, since unlike
// MapList/GameConfig this snapshot can legitimately change between
// requests; each item then overwrites its own index.
simulated function ReceiveZedVoteCount( int Count )
{
	ZedVoteNames.Length = Count;
	ZedVoteStates.Length = Count;
}

simulated function ReceiveZedVoteItem( int Index, string ZedName, byte ZedState )
{
	if( Index < 0 || Index >= ZedVoteNames.Length )
		return;
	ZedVoteNames[Index] = ZedName;
	ZedVoteStates[Index] = ZedState;
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