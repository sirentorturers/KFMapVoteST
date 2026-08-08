// ====================================================================
//  KFVotingHandler - Modification by Marco
//  SirenTorturers Edition (KFMapVoteST):
//    - GameConfig is now assembled at runtime from KFGameConfigEntry
//      PerObjectConfig instances (Config file: KFMapVoteModes.ini), one
//      section per game mode, discovered via GetPerObjectNames()
//      and constructed on demand via new(none, SectionName). Each mode's
//      section is parsed completely independently of every other mode's,
//      so there is no shared array and no shared 4095-character INI
//      limit - a server can define as many modes as it wants.
//    - The inherited GameConfig array (declared on the base xVotingHandler
//      engine class) is left completely untouched in shape/type - it is
//      simply populated by copying fields out of each KFGameConfigEntry
//      instead of being filled directly from a single config array or
//      from AppendGameConfigSection()-style sectioned arrays. Every other
//      class in this package (KFXMapListLoader, MVMultiColumnListBox,
//      KFMapVotingPageX, etc.) reads GameConfig by index only, so none
//      of them needed to change.
// ====================================================================
class KFVotingHandler extends xVotingHandler
	Config(KFMapVote);

var config bool bShowMapLike;
var config bool bSpectatorsCanVote;

struct FMapRepType
{
	var int Positive,Negative;
};
var array<FMapRepType> RepArray; // Map reputation array, should be in sync with MapList array.

// Per-map preview override, read from KFMapVotePreviews.ini
// (KFMapPreviewEntry) server-side in AddMap() below and sent to clients
// one map at a time via the same ticked-RPC mechanism RepArray already
// uses (see KFVotingReplicationInfo.TickedReplication_MapList/
// ReceiveMapInfoRep) - never as one bulk-replicated array, so this isn't
// exposed to the same size limit that GameConfigSec01-08 hit. Exists
// because a client can only read its own local map cache/LevelSummary
// for maps it has already downloaded - the server always has every
// map's real ini entry locally, so this is resolved server-side once
// and handed to every client regardless of their own map cache.
struct FMapPreviewData
{
	var string TextureRef;
	var string Author;
	var int PlayerCountMin;
	var int PlayerCountMax;
};
var array<FMapPreviewData> MapPreviewArray; // Preview override array, should be in sync with MapList array.

// ------------------------------------------------------------------
// Comparator for BuildGameConfig()'s sort pass: numbered entries
// (SortOrder > 0) sort ascending by that number and always come before
// unnumbered ones; entries left at the default SortOrder=0 come after
// all numbered entries, sorted alphabetically by GameName (case-
// insensitive). Returns true if A belongs before B.
// ------------------------------------------------------------------
final function bool ShouldSortBefore(KFGameConfigEntry A, KFGameConfigEntry B)
{
	if( A.SortOrder > 0 && B.SortOrder > 0 )
		return A.SortOrder < B.SortOrder;
	if( A.SortOrder > 0 && B.SortOrder == 0 )
		return true;
	if( A.SortOrder == 0 && B.SortOrder > 0 )
		return false;
	// Both left at the default (0) - alphabetical by GameName.
	return Caps(A.GameName) < Caps(B.GameName);
}

// ------------------------------------------------------------------
// Discovers every KFGameConfigEntry section in KFMapVoteModes.ini,
// loads each one, sorts by SortOrder (see ShouldSortBefore() above),
// and appends the result into the live GameConfig array. Called once
// per PostBeginPlay(), before Super(), so GameConfig is fully populated
// before any base-class logic (or anything else in this package) has a
// chance to read it.
// ------------------------------------------------------------------
final function BuildGameConfig()
{
	local array<string> SectionNames;
	local array<KFGameConfigEntry> Entries;
	local KFGameConfigEntry Entry;
	local int i, j, BestIdx;

	GameConfig.Length = 0;

	SectionNames = GetPerObjectNames("KFMapVoteModes", "KFGameConfigEntry", 1024);
	if( SectionNames.Length == 0 )
	{
		log("___BuildGameConfig: no KFGameConfigEntry sections found in KFMapVoteModes.ini!",'MapVote');
		return;
	}

	// Load every entry first so we can sort by SortOrder before copying
	// into GameConfig (GameConfig's final index order is what the vote
	// GUI and every stored vote index are keyed against).
	for( i=0; i<SectionNames.Length; i++ )
	{
		Entry = new(none, SectionNames[i]) class'KFGameConfigEntry';
		if( Entry == none )
		{
			log("___BuildGameConfig: failed to load section '"$SectionNames[i]$"' - skipping.",'MapVote');
			continue;
		}
		Entries[Entries.Length] = Entry;
	}

	// Single selection-sort pass by SortOrder, done once after every
	// section is already loaded (rather than an insertion sort during
	// loading). Entries with SortOrder > 0 sort ascending by that number
	// first (ties keep whatever relative order GetPerObjectNames returned
	// them in - stable); everything left at the default SortOrder=0 comes
	// after all of those, sorted alphabetically by GameName - see
	// ShouldSortBefore() below.
	for( i=0; i<Entries.Length-1; i++ )
	{
		BestIdx = i;
		for( j=i+1; j<Entries.Length; j++ )
		{
			if( ShouldSortBefore(Entries[j], Entries[BestIdx]) )
				BestIdx = j;
		}
		if( BestIdx != i )
		{
			Entry = Entries[i];
			Entries[i] = Entries[BestIdx];
			Entries[BestIdx] = Entry;
		}
	}

	GameConfig.Length = Entries.Length;
	for( i=0; i<Entries.Length; i++ )
	{
		GameConfig[i].GameClass = Entries[i].GameClass;
		GameConfig[i].Prefix    = Entries[i].Prefix;
		GameConfig[i].Acronym   = Entries[i].Acronym;
		GameConfig[i].GameName  = Entries[i].GameName;
		GameConfig[i].Mutators  = Entries[i].Mutators;
		GameConfig[i].Options   = Entries[i].Options;
	}

	log("___BuildGameConfig: assembled "$GameConfig.Length$" GameConfig entries from KFMapVoteModes.ini.",'MapVote');
}

// ------------------------------------------------------------------
// Parses the numeric value out of a "...GameLength=NNN..." token inside a
// string - e.g. a GameConfig Options string like "GameLength=178" or,
// for Objective modes, "Difficulty=4?GameLength=16" - or a full level URL
// string like "KF-Afghanistan-ST?Game=SirenTorturers.G?GameLength=183".
// Returns -1 if not found.
// ------------------------------------------------------------------
final function int ExtractGameLength(string Options)
{
	local int Idx, EndIdx, i;
	local string Tail, NumStr;

	Idx = InStr(Options, "GameLength=");
	if( Idx == -1 )
		return -1;

	Tail = Mid(Options, Idx + Len("GameLength="));
	EndIdx = InStr(Tail, "?");
	if( EndIdx > -1 )
		NumStr = Left(Tail, EndIdx);
	else
		NumStr = Tail;

	// Trim to leading digits only, defensively, in case of trailing junk.
	for( i=0; i<Len(NumStr); i++ )
	{
		if( Asc(Mid(NumStr,i,1)) < Asc("0") || Asc(Mid(NumStr,i,1)) > Asc("9") )
		{
			NumStr = Left(NumStr, i);
			break;
		}
	}
	if( NumStr == "" )
		return -1;
	return int(NumStr);
}

// ------------------------------------------------------------------
// Reads the live GameLength off Level.GetLocalURL() - a native LevelInfo
// function returning the level's full current URL as a string, including
// options (e.g. "KF-Afghanistan-ST?Game=SirenTorturers.G?GameLength=183").
// Same native-function family as Level.GetURLMap(), which is already
// proven working elsewhere in this project (StMapNameWriter) - this is
// the sibling call that returns the whole URL instead of just the map
// name. Feeds the result into ExtractGameLength() above. Returns -1 if
// no GameLength option is present (or the call itself is somehow
// unavailable - callers treat -1 as "can't verify, don't use this check").
// ------------------------------------------------------------------
final function int GetLiveGameLength()
{
	return ExtractGameLength(Level.GetLocalURL());
}

function PostBeginPlay()
{
	local int i;
	local int LiveGameLength;

	AddToPackageMap(); // Make sure in serverpackages.

	// Assemble the live GameConfig array out of KFGameConfigEntry
	// PerObjectConfig sections BEFORE calling Super().PostBeginPlay().
	// We don't have source for xVotingHandler/VotingHandler beyond what
	// we've verified directly, so building GameConfig first, unconditionally,
	// removes any dependency on what the base class does internally
	// during its own PostBeginPlay().
	BuildGameConfig();

	Super(VotingHandler).PostBeginPlay();

	// disable voting in single player mode
	if( Level.NetMode==NM_StandAlone )
		return;

	if(bKickVote)
		log("Kick Voting Enabled",'MapVote');
	else
		log("Kick Voting Disabled",'MapVote');

	if(bMapVote)
	{
		log("Map Voting Enabled",'MapVote');
		// check current game settings
		if( GameConfig.Length > 0 )
		{
			// LiveGameLength disambiguates entries that share a GameClass
			// (the vast majority here - "SirenTorturers.G" alone covers
			// Standard, Dying Floor, Kitchen Sink, Casino Royale, and
			// several others). Without this, CurrentGameConfig's cached
			// index only gets re-validated against GameClass, which is
			// almost always a loose enough match to pass even when the
			// cached index is stale (e.g. after any KFMapVoteModes.ini
			// edit shifts array positions) - so a stale index silently
			// keeps pointing at whatever now occupies that slot, landing
			// on the right mode family by coincidence but the wrong
			// difficulty tier. Confirmed this exact failure mode directly
			// against a live KFMapVote.ini snapshot before writing this.
			LiveGameLength = GetLiveGameLength();

			if( !(string(Level.Game.Class) ~= GameConfig[CurrentGameConfig].GameClass)
				|| (LiveGameLength > -1 && ExtractGameLength(GameConfig[CurrentGameConfig].Options) != LiveGameLength) )
			{
				CurrentGameConfig = 0;
				// Find the entry that's an exact match: same GameClass AND
				// same GameLength, if we could read one. Falls back to
				// GameClass-only (the original behavior) if LiveGameLength
				// couldn't be determined, so a failed/unavailable
				// GetLiveGameLength() call degrades no worse than before
				// this change rather than breaking mode-matching entirely.
				for( i=0; i<GameConfig.Length; i++)
				{
					if( GameConfig[i].GameClass ~= string(Level.Game.Class)
						&& (LiveGameLength == -1 || ExtractGameLength(GameConfig[i].Options) == LiveGameLength) )
					{
						CurrentGameConfig = i;
						break;
					}
				}
			}
		}
		else
			CurrentGameConfig = 0;
		LoadMapList();
	}
	else
		log("Map Voting Disabled",'MapVote');

	if(bMatchSetup)
	{
		log("MatchSetup Enabled",'MapVote');

		MatchProfile = CreateMatchProfile();
		MatchProfile.Init(Level);
		MatchProfile.LoadCurrentSettings();
	}
	else
		log("MatchSetup Disabled",'MapVote');
}

function LoadMapList()
{
	MapListLoaderType = string(Class'KFXMapListLoader');
	Super.LoadMapList();
}

static event bool AcceptPlayInfoProperty(string PropertyName)
{
	if( PropertyName=="bMatchSetup" )
		return true;

	// GameConfig is now assembled at runtime from KFGameConfigEntry
	// PerObjectConfig sections (see BuildGameConfig()) rather than being
	// a single, directly-editable config array. The base xVotingHandler
	// class exposes "GameConfig" to WebAdmin via a custom editor page
	// (GameConfigPage) that assumes the old single-array format -
	// that page is what crashes ("WebAdmin: Loading Game Types" ->
	// Critical: GUIController.DesignModeHints) once GameConfig no longer
	// matches its expectations. Since game modes are edited directly in
	// KFMapVoteModes.ini rather than through WebAdmin, block "GameConfig"
	// from PlayInfo/WebAdmin entirely instead of letting it reach that
	// crashing page. Every other WebAdmin-exposed setting is untouched.
	if( PropertyName=="GameConfig" )
		return false;

	return Super.AcceptPlayInfoProperty(PropertyName);
}

function SubmitMapVote(int MapIndex, int GameIndex, Actor Voter)
{
	local int Index, VoteCount, PrevMapVote, PrevGameVote;
	local MapHistoryInfo MapInfo;
	local bool bAdminForce;
	local PlayerController PC;
	local PlayerReplicationInfo PRI;

	if(bLevelSwitchPending)
		return;

	PC = PlayerController(Voter);
	PRI = PC.PlayerReplicationInfo;
	Index = GetMVRIIndex(PC);
	if( GameIndex<0 )
	{
		bAdminForce = true;
		GameIndex = (-GameIndex) - 1;
	}
	if( GameIndex>=GameConfig.Length || MapIndex<0 || MapIndex>=MapList.Length )
		return; // Something is wrong...

	// check for invalid vote from unpatch players
	if( !IsValidVote(MapIndex, GameIndex) )
		return;

	if( bAdminForce && (PRI.bAdmin || PRI.bSilentAdmin) )  // Administrator Vote
	{
		TextMessage = lmsgAdminMapChange;
		TextMessage = Repl(TextMessage, "%mapname%", MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")");
		Level.Game.Broadcast(self,TextMessage);

		log("Admin has forced map switch to " $ MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")",'MapVote');

		CloseAllVoteWindows();

		bLevelSwitchPending = true;

		MapInfo = History.PlayMap(MapList[MapIndex].MapName);

		ServerTravelString = SetupGameMap(MapList[MapIndex], GameIndex, MapInfo);
		log("ServerTravelString = " $ ServerTravelString ,'MapVoteDebug');

		Level.ServerTravel(ServerTravelString, false);    // change the map

		settimer(1,true);
		return;
	}

	if (!bSpectatorsCanVote && PRI.bOnlySpectator && Level.Game.NumPlayers > 0) {
		return;
	}

	// check for invalid map, invalid gametype, player isnt revoting same as previous vote, and map choosen isnt disabled
	if( !MapList[MapIndex].bEnabled || (MVRI[Index].MapVote==MapIndex && MVRI[Index].GameVote==GameIndex) )
		return;

	log("___" $ Index $ " - " $ PRI.PlayerName $ " voted for " $ MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")",'MapVote');

	PrevMapVote = MVRI[Index].MapVote;
	PrevGameVote = MVRI[Index].GameVote;
	MVRI[Index].MapVote = MapIndex;
	MVRI[Index].GameVote = GameIndex;

	if(bAccumulationMode)
	{
		if(bScoreMode)
		{
			VoteCount = GetAccVote(PC) + int(GetPlayerScore(PC));
			TextMessage = lmsgMapVotedForWithCount;
			TextMessage = repl(TextMessage, "%playername%", PRI.PlayerName );
			TextMessage = repl(TextMessage, "%votecount%", string(VoteCount) );
			TextMessage = repl(TextMessage, "%mapname%", MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")" );
			Level.Game.Broadcast(self,TextMessage);
		}
		else
		{
			VoteCount = GetAccVote(PC) + 1;
			TextMessage = lmsgMapVotedForWithCount;
			TextMessage = repl(TextMessage, "%playername%", PRI.PlayerName );
			TextMessage = repl(TextMessage, "%votecount%", string(VoteCount) );
			TextMessage = repl(TextMessage, "%mapname%", MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")" );
			Level.Game.Broadcast(self,TextMessage);
		}
	}
	else
	{
		if(bScoreMode)
		{
			VoteCount = int(GetPlayerScore(PC));
			TextMessage = lmsgMapVotedForWithCount;
			TextMessage = repl(TextMessage, "%playername%", PRI.PlayerName );
			TextMessage = repl(TextMessage, "%votecount%", string(VoteCount) );
			TextMessage = repl(TextMessage, "%mapname%", MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")" );
			Level.Game.Broadcast(self,TextMessage);
		}
		else
		{
			VoteCount =  1;
			TextMessage = lmsgMapVotedFor;
			TextMessage = repl(TextMessage, "%playername%", PRI.PlayerName );
			TextMessage = repl(TextMessage, "%mapname%", MapList[MapIndex].MapName $ "(" $ GameConfig[GameIndex].Acronym $ ")" );
			Level.Game.Broadcast(self,TextMessage);
		}
	}
	UpdateVoteCount(MapIndex, GameIndex, VoteCount);
	if( PrevMapVote > -1 && PrevGameVote > -1 )
		UpdateVoteCount(PrevMapVote, PrevGameVote, -MVRI[Index].VoteCount); // undo previous vote
	MVRI[Index].VoteCount = VoteCount;
	TallyVotes(false);
}

function TallyVotes(bool bForceMapSwitch)
{
	local int C;

	if (!bSpectatorsCanVote) {
		super.TallyVotes(bForceMapSwitch);
	}

	C = Level.Game.NumPlayers;
	Level.Game.NumPlayers+=Level.Game.NumSpectators;
	Super.TallyVotes(bForceMapSwitch);
	Level.Game.NumPlayers = C;
}

function AddMapVoteReplicationInfo(PlayerController Player)
{
	local KFVotingReplicationInfo M;

	M = Spawn(class'KFVotingReplicationInfo',Player,,Player.Location);
	if(M == None)
	{
		Log("___Failed to spawn VotingReplicationInfo",'MapVote');
		return;
	}

	M.PlayerID = Player.PlayerReplicationInfo.PlayerID;
	M.bShowMapLike = bShowMapLike;
	MVRI[MVRI.Length] = M;
}

function Timer()
{
	local int mapidx,gameidx,i;
	local MapHistoryInfo MapInfo;

	if(bLevelSwitchPending)
	{
		if( Level.NextURL == "" )
		{
			if(Level.NextSwitchCountdown < 0)  // if negative then level switch failed
			{
				Log("___Map change Failed, bad or missing map file.",'MapVote');
				GetDefaultMap(mapidx, gameidx);
				MapInfo = History.PlayMap(MapList[mapidx].MapName);
				ServerTravelString = SetupGameMap(MapList[mapidx], gameidx, MapInfo);
				log("ServerTravelString = " $ ServerTravelString ,'MapVoteDebug');
				History.Save();
				Level.ServerTravel(ServerTravelString, false);    // change the map
			}
		}
		return;
	}

	if(ScoreBoardTime > -1)
	{
		if(ScoreBoardTime == 0)
			OpenAllVoteWindows();
		ScoreBoardTime--;
		return;
	}
	TimeLeft--;

	if( TimeLeft==60 || TimeLeft==30 || TimeLeft==20 || (TimeLeft<=10 && TimeLeft>0) )  // play announcer count down voice
	{
		for( i=0; i<MVRI.Length; i++)
			if(MVRI[i] != none && MVRI[i].PlayerOwner != none )
				MVRI[i].PlayCountDown(TimeLeft);
	}
	if(TimeLeft == -1)  // force level switch if time limit is up
		TallyVotes(true);   // if no-one has voted a random map will be choosen
}

function string SetupGameMap(MapVoteMapList MapInfo, int GameIndex, MapHistoryInfo MapHistoryInfo)
{
	local string ReturnString;
	local string MutatorString;
	local string OptionString;
	local array<string> MapsInRotation;
	local int i;

	// Add Per-GameType Mutators
	if( Len(GameConfig[GameIndex].Mutators)!=0 )
		MutatorString = MutatorString $ GameConfig[GameIndex].Mutators;

	// Add Per-Map Mutators
	if( Len(MapHistoryInfo.U)!=0 )
		MutatorString = MutatorString $ "," $ MapHistoryInfo.U;

	// Add Per-GameType Game Options
	if(GameConfig[GameIndex].Options != "")
		OptionString = OptionString $ Repl(Repl(GameConfig[GameIndex].Options,",","?")," ","");

	// Add Per-Map Game Options
	if(MapHistoryInfo.G != "")
		OptionString = OptionString $ "?" $ MapHistoryInfo.G;

	//if _RO_
	// Remove the .rom off of the map name, if it exists
	if ( Right(MapInfo.MapName, 4) == ".rom" )
		ReturnString = Left(MapInfo.MapName, Len(MapInfo.MapName) - 4);
	else
		ReturnString = MapInfo.MapName;

	MapsInRotation = Level.Game.MaplistHandler.GetCurrentMapRotation();
	for ( i = 0; i < MapsInRotation.Length; i++ )
	{
		if ( InStr(MapsInRotation[i], ReturnString) != -1 )
		{
			ReturnString = MapsInRotation[i];
			break;
		}
	}

	ReturnString = ReturnString $ "?Game=" $ GameConfig[GameIndex].GameClass;

	if( MutatorString=="" )
		MutatorString = "None"; // Don't allow previous mutator options to override this then.
	ReturnString = ReturnString $ "?Mutator=" $ MutatorString;

	if(OptionString != "")
		ReturnString = ReturnString $ "?" $ OptionString;

	return ReturnString;
}

function AddMap(string MapName, string Mutators, string GameOptions) // called from the MapListLoader
{
	local MapHistoryInfo MapInfo;
	local KFMapPreviewEntry PreviewEntry;
	local bool bUpdate;
	local int i;

	if( Right(MapName,4)~=".rom" )
		MapName = Left(MapName,Len(MapName)-4);

	if( MapName~="KFintro" )
		return; // Unplayable map.

	for(i=0; i < MapList.Length; i++)  // dont add duplicate map names
		if(MapName ~= MapList[i].MapName)
			return;

	RepArray.Length = MapCount + 1;
	Class'MVMapRepHistory'.Static.GetMapHistoryRep(MapName,RepArray[MapCount].Positive,RepArray[MapCount].Negative);

	// Resolved here (server-side, where KFMapVotePreviews.ini actually
	// exists) rather than on each client - see FMapPreviewData above.
	MapPreviewArray.Length = MapCount + 1;
	PreviewEntry = new(none, MapName) class'KFMapPreviewEntry';
	MapPreviewArray[MapCount].TextureRef = PreviewEntry.TextureRef;
	MapPreviewArray[MapCount].Author = PreviewEntry.Author;
	MapPreviewArray[MapCount].PlayerCountMin = PreviewEntry.PlayerCountMin;
	MapPreviewArray[MapCount].PlayerCountMax = PreviewEntry.PlayerCountMax;

	MapInfo = History.GetMapHistory(MapName);

	MapList.Length = MapCount + 1;
	MapList[MapCount].MapName = MapName;
	MapList[MapCount].PlayCount = MapInfo.P;
	MapList[MapCount].Sequence = MapInfo.S;
	if(MapInfo.S <= RepeatLimit && MapInfo.S != 0)
		MapList[MapCount].bEnabled = false; // dont allow players to vote for this one
	else
		MapList[MapCount].bEnabled = true;
	MapCount++;

	if(Mutators != "" && Mutators != MapInfo.U)
	{
		MapInfo.U = Mutators;
		bUpdate = True;
	}

	if(GameOptions != "" && GameOptions != MapInfo.G)
	{
		MapInfo.G = GameOptions;
		bUpdate = True;
	}

	if(MapInfo.M == "") // if map not found in MapVoteHistory then add it
	{
		MapInfo.M = MapName;
		bUpdate = True;
	}

	if(bUpdate)
		History.AddMap(MapInfo);
}

// Using this function to save map reputation aswell.
function CloseAllVoteWindows()
{
	local int i,Pos,Neg;
	local KFVotingReplicationInfo R;

	for(i=0; i < MVRI.Length;i++)
	{
		R = KFVotingReplicationInfo(MVRI[i]);
		if( R!=none )
		{
			switch( R.MapRepVote )
			{
			case 1:
				++Pos;
				break;
			case 2:
				++Neg;
				break;
			}
			R.CloseWindow();
		}
	}
	if( Pos!=0 || Neg!=0 )
		Class'MVMapRepHistory'.Static.AddReputation(string(Outer.Name),Pos,Neg);
}

// Fixed a bug in vote count updater.
function PlayerExit(Controller Exiting)
{
	local int i;

	// disable voting in single player mode
	if( Level.NetMode == NM_StandAlone )
		return;

	log("____PlayerExit", 'MapVoteDebug');

	if( bMapVote || bKickVote || bMatchSetup )
	{
		// find the MVRI belonging to the exiting player
		for(i=0;i < MVRI.Length;i++)
		{
			// remove players vote from vote count
			if( MVRI[i] != none && (MVRI[i].PlayerOwner == none || MVRI[i].PlayerOwner == Exiting) )
			{
				log("exiting player MVRI found " $ i,'MapVoteDebug');
				if( bMapVote && MVRI[i].MapVote > -1 && MVRI[i].GameVote > -1 )
					UpdateVoteCount(MVRI[i].MapVote, MVRI[i].GameVote, -MVRI[i].VoteCount);

				if( bKickVote )
				{
					// decrease votecount for player that the exiting player voted against
					if( MVRI[i].KickVote>-1 )
						UpdateKickVoteCount( MVRI[MVRI[i].KickVote].PlayerID, -1);

					// clear votes for exiting player
					UpdateKickVoteCount( MVRI[i].PlayerID, 0 );
				}

				log("___Destroying VRI...",'MapVoteDebug');
				MVRI[i].Destroy();
				MVRI[i] = none;
				if( bKickVote )
					TallyKickVotes();
				if( bMapVote )
					TallyVotes(false);
			}
		}
	}
}

function bool IsValidVote(int MapIndex, int GameIndex)
{
	local string A,B;
	local array<string> PL;
	local int i;

	A = GameConfig[GameIndex].Prefix;
	Divide(A,"|",A,B);
	Split(A, ",", PL);

	for( i=(PL.Length-1); i>=0; --i )
		if( Left(MapList[MapIndex].MapName, len(PL[i]))~=PL[i] )
			break;
	if( i==-1 )
		return false;

	if( B!="" )
	{
		Split(B, ",", PL);
		for( i=(PL.Length-1); i>=0; --i )
			if( Left(MapList[MapIndex].MapName, len(PL[i]))~=PL[i] )
				return false;
	}
	return true;
}
function GetDefaultMap(out int mapidx, out int gameidx)
{
	local int i,x,y,r,GCIdx;
	local array<string> PL,SPL;
	local string A,B;
	local bool bLoop;

	if(MapCount <= 0)
		return;

	// set the default gametype
	if(bDefaultToCurrentGameType)
		GCIdx = CurrentGameConfig;
	else
		GCIdx = DefaultGameConfig;

	// Parse Prefix list for default game type
	A = GameConfig[GCIdx].Prefix;
	if( Divide(A,"|",A,B) )
		Split(B, ",", SPL);
	Split(A, ",", PL);
	if( PL.Length==0 )
	{
		gameidx = GCIdx;
		mapidx = 0;
		return;
	}

	// choose a map at random, check if it is enabled and the prefix is in the prefix list
	r=0;
	bLoop = True;
	while( bLoop )
	{
		i = Rand(MapCount);
		if( MapList[i].bEnabled )
		{
			for( x=(PL.Length-1); x>=0; --x )
			{
				if( left(MapList[i].MapName, Len(PL[x])) ~= PL[x] )
					break;
			}
			if( x>=0 )
			{
				for( x=(SPL.Length-1); x>=0; --x )
				{
					if( left(MapList[i].MapName, len(SPL[x])) ~= SPL[x] )
						break;
				}
				if( x==-1 )
					bLoop = false;
			}
		}

		if(bLoop && r++ > 100)
		{
			// give up after 100 unsuccessful attempts.
			// find the first map that matches up to default gametype
            for(i=0; i<MapCount; ++i)
			{
				if( MapList[i].bEnabled )
				{
					for( x=(PL.Length-1); x>=0; --x )
					{
						if( left(MapList[i].MapName, Len(PL[x])) ~= PL[x] )
							break;
					}
					if( x>=0 )
					{
						for( x=(SPL.Length-1); x>=0; --x )
						{
							if( left(MapList[i].MapName, len(SPL[x])) ~= SPL[x] )
								break;
						}
						if( x==-1 )
							bLoop = false;
					}
				}
			}

			if(bLoop) // still didnt find any, then find the first enabled map and find its gameconfig
			{
				for( i=0; (i<MapCount && bLoop); ++i )
				{
					if( MapList[i].bEnabled )
					{
						// find prefix in GameConfigs
						for(y=0; (y<GameConfig.Length && bLoop); y++)
						{
							// Parse Prefix list for game type
							PL.Length = 0;
							SPL.Length = 0;

							A = GameConfig[y].Prefix;
							if( Divide(A,"|",A,B) )
								Split(B, ",", SPL);
							Split(A, ",", PL);

							if(PL.Length > 0)
							{
								for( x=(PL.Length-1); x>=0; --x )
								{
									if( left(MapList[i].MapName, Len(PL[x])) ~= PL[x] )
										break;
								}
								if( x>=0 )
								{
									for( x=(SPL.Length-1); x>=0; --x )
									{
										if( left(MapList[i].MapName, len(SPL[x])) ~= SPL[x] )
											break;
									}
									if( x==-1 )
									{
										GCIdx = y;
										bLoop = false;
									}
								}
							}
						}
					}
				}
			}
			break;
		}
	}

	if (i < MapCount) {
		mapidx = i;
		gameidx = GCIdx;
	}
	else {
		// something bad happened
		mapidx = 0;
		gameidx = DefaultGameConfig;
	}
	log("Default Map Choosen = " $ MapList[mapidx].MapName $ "(" $ GameConfig[gameidx].Acronym $ ")",'MapVoteDebug');
}

function string GetConfigArrayData(string ConfigArrayName, int RowIndex, int ColumnIndex)
{
	local string B;

	if( ConfigArrayName~="GAMECONFIG" )
	{
		if( RowIndex > GameConfig.Length-1 || ColumnIndex > 5 )
			return "";

		switch( ColumnIndex )
		{
			case 0:
				return "GAMETYPE;50;" $ GameConfig[RowIndex].GameClass;
			case 1:
				if( !Divide(GameConfig[RowIndex].Prefix,"|",ConfigArrayName,B) )
					ConfigArrayName = GameConfig[RowIndex].Prefix;
				return "TEXT;50;" $ ConfigArrayName;
			case 2:
				if( !Divide(GameConfig[RowIndex].Prefix,"|",ConfigArrayName,B) )
					B = "";
				return "TEXT;50;" $ B;
			case 3:
				return "TEXT;20;" $ GameConfig[RowIndex].Acronym;
			case 4:
				return "TEXT;50;" $ GameConfig[RowIndex].GameName;
			case 5:
				return "MUTATORS;255;" $ GameConfig[RowIndex].Mutators;
			case 6:
				return "TEXT;255;" $ GameConfig[RowIndex].Options;
		}
	}
	return "";
}
function string GetConfigArrayColumnTitle(string ConfigArrayName, int ColumnIndex)
{
	if( ConfigArrayName~="GAMECONFIG" && ColumnIndex<=6 )
	{
		if( ColumnIndex==2 )
			return "Exl.Prefixes";
		else if( ColumnIndex>2 )
			--ColumnIndex;
   		return lmsgGameConfigColumnTitle[ColumnIndex];
	}
	return "";
}
function int AddConfigArrayItem(string ConfigArrayName)
{
	if( ConfigArrayName~="GAMECONFIG" )
	{
		GameConfig.Insert(GameConfig.Length,1);
		GameConfig[GameConfig.Length-1].GameClass = "KFMod.KFGameType";
		GameConfig[GameConfig.Length-1].Prefix = "KF-";
		GameConfig[GameConfig.Length-1].Acronym = "KF";
		GameConfig[GameConfig.Length-1].GameName = "New KillingFloor";
		GameConfig[GameConfig.Length-1].Mutators = "";
		GameConfig[GameConfig.Length-1].Options = "";
		return GameConfig.Length-1;
	}
	return 0;
}
function UpdateConfigArrayItem(string ConfigArrayName, int RowIndex, int ColumnIndex, string NewValue)
{
	local string B;

	if( ConfigArrayName~="GAMECONFIG" && RowIndex>=0 && RowIndex<GameConfig.Length && ColumnIndex<=6 )
	{
		switch( ColumnIndex )
		{
			case 0:
				GameConfig[RowIndex].GameClass = NewValue;
				break;
			case 1:
				if( !Divide(GameConfig[RowIndex].Prefix,"|",ConfigArrayName,B) )
					GameConfig[RowIndex].Prefix = NewValue;
				else GameConfig[RowIndex].Prefix = NewValue$"|"$B;
				break;
			case 2:
				if( !Divide(GameConfig[RowIndex].Prefix,"|",ConfigArrayName,B) )
				{
					if( NewValue!="" )
						GameConfig[RowIndex].Prefix $= "|"$NewValue;
				}
				else if( NewValue=="" )
					GameConfig[RowIndex].Prefix = ConfigArrayName;
				else GameConfig[RowIndex].Prefix = ConfigArrayName$"|"$NewValue;
				break;
			case 3:
				GameConfig[RowIndex].Acronym = NewValue;
				break;
			case 4:
				GameConfig[RowIndex].GameName = NewValue;
				break;
			case 5:
				GameConfig[RowIndex].Mutators = NewValue;
				break;
			case 6:
				GameConfig[RowIndex].Options = NewValue;
				break;
		}
	}
}

defaultproperties
{
	bMatchSetup=false
	bShowMapLike=false
	bSpectatorsCanVote=true
}