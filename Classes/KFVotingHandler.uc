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

// Reserved sentinel MapList entry name for the "RANDOM MAP" vote option (see
// AddRandomMapSentinel() below). Duplicated client-side in
// MVMultiColumnList.uc's LoadList()/DrawItem()/GetSortString() and
// MVCountColumnList.uc's DrawItem() - no shared base class conveniently
// spans client and server here, so this is duplicated the same way this
// package already duplicates its Prefix/SkipList/MapListStyle filtering
// logic between client (LoadList()) and server (IsMapValidForGameConfig())
// for defense-in-depth. Keep both copies in sync if this ever changes.
const RANDOM_MAP_NAME = "RANDOM MAP";

var config bool bShowMapLike;
var config bool bSpectatorsCanVote;

// Playback speed (frames/sec) for any animated preview texture shown in
// the map vote footer's preview panel (see KFMapVoteFooterX.
// UpdateMapPreview()) - admin-configurable in KFMapVote.ini rather than
// baked into the imported texture asset itself, since there's no
// scriptable way to persist an edited Texture property back into an
// already-imported .utx package with this SDK's available ucc tooling
// (BatchImportCommandlet has no per-file property override, and no
// Commandlet-callable SavePackage-equivalent exists - see
// GenerateMapPreviewsCommandlet-handoff.md). Applied client-side to the
// live Texture object in UpdateMapPreview() instead, which needs no
// package edits at all. Mirrors bShowMapLike's existing config -> spawn
// -copy -> replicate pattern exactly (see AddMapVoteReplicationInfo()
// below and KFVotingReplicationInfo.PreviewAnimFrameRate).
var config float PreviewAnimFrameRate;

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

// Per-mode description text, read from KFGameConfigEntry.Description
// (KFMapVoteModes.ini) in BuildGameConfig() below - index-matched with
// GameConfig, same convention as MapPreviewArray/MapList above. Kept as a
// plain parallel array rather than a field on GameConfig itself because
// GameConfig's element type (MapVoteGameConfig/MapVoteGameConfigLite) is
// a base-engine struct we don't own and can't widen. Delivered to clients
// one entry at a time via KFVotingReplicationInfo.ReceiveGameConfigRep()
// - see that class for why (mirrors MapPreviewList's own reasoning).
var array<string> GameConfigDescriptions;

// Per-mode map list restriction, read from KFGameConfigEntry.MapListStyle/
// AllowMap/ExcludeMap - same index-matched-parallel-array convention as
// GameConfigDescriptions above, for the same reason (GameConfig's element
// type is a base-engine struct we can't widen). GameConfigMapListStyle is
// always "All"/"Allow"/"Exclude"; GameConfigMapListValue is a single
// comma-joined string holding whichever of AllowMap/ExcludeMap is active
// for that mode (same comma-list convention Prefix already uses) - built
// by JoinMapList() below. Delivered to clients the same way
// GameConfigDescriptions is - see KFVotingReplicationInfo.
var array<string> GameConfigMapListStyle;
var array<string> GameConfigMapListValue;

// Per-mode difficulty word, derived server-side from GameName (via
// DeriveDifficulty()/EndsWithWord() below) in BuildGameConfig() - same
// index-matched-parallel-array convention as GameConfigDescriptions above,
// delivered to clients the same way (see KFVotingReplicationInfo). This
// used to be derived client-side, independently, in KFMapVotingPageX -
// moved server-side so every client gets one server-computed answer
// instead of each client re-parsing GameName text itself (also removes
// any dependency on exactly which compiled package version a given
// client happens to be running).
var array<string> GameConfigDifficulty;

// Set by PostBeginPlay() when a CurrentGameConfig re-validation is queued
// (see RevalidateCurrentGameConfig() below) - Level.GetLocalURL() reads
// empty this early in the actor lifecycle (confirmed, documented gotcha),
// so the check is deferred to a repeating Timer() poll instead of running
// synchronously. Timer() checks this flag first and consumes/clears it
// before falling into its normal countdown/vote-cycle logic, so this
// early one-shot poll never collides with the several unrelated
// settimer(1,true) calls elsewhere in this file that drive the actual
// vote cycle once voting opens (those all happen well after level start).
var bool bPendingCurrentGameConfigCheck;

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
	local string ResolvedStyle, ResolvedValue;

	GameConfig.Length = 0;

	SectionNames = GetPerObjectNames("KFMapVoteModes", "KFGameConfigEntry", 1024);
	if( SectionNames.Length == 0 )
	{
		log("___BuildGameConfig: no KFGameConfigEntry sections found in KFMapVoteModes.ini!",'MapVote');
		return;
	}

	// Load every entry first so we can sort by SortOrder before copying
	// into GameConfig (GameConfig's final index order is what the vote
	// GUI and every stored vote index are keyed against). Disabled entries
	// (bDisabled=true) are skipped here, before anything is copied into
	// GameConfig - see KFGameConfigEntry.bDisabled. That means a disabled
	// mode never occupies a GameConfig index at all, so nothing downstream
	// needs to filter it out separately.
	for( i=0; i<SectionNames.Length; i++ )
	{
		Entry = new(none, SectionNames[i]) class'KFGameConfigEntry';
		if( Entry == none )
		{
			log("___BuildGameConfig: failed to load section '"$SectionNames[i]$"' - skipping.",'MapVote');
			continue;
		}
		if( Entry.bDisabled )
		{
			log("___BuildGameConfig: '"$SectionNames[i]$"' is disabled - skipping.",'MapVote');
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
	GameConfigDescriptions.Length = Entries.Length;
	GameConfigMapListStyle.Length = Entries.Length;
	GameConfigMapListValue.Length = Entries.Length;
	GameConfigDifficulty.Length = Entries.Length;
	for( i=0; i<Entries.Length; i++ )
	{
		GameConfig[i].GameClass = Entries[i].GameClass;
		GameConfig[i].Prefix    = Entries[i].Prefix;
		GameConfig[i].Acronym   = Entries[i].Acronym;
		GameConfig[i].GameName  = Entries[i].GameName;
		GameConfig[i].Mutators  = Entries[i].Mutators;
		GameConfig[i].Options   = Entries[i].Options;
		GameConfigDescriptions[i] = Entries[i].Description;
		GameConfigDifficulty[i] = DeriveDifficulty(Entries[i].GameName);

		ResolveMapList(Entries, Entries[i], ResolvedStyle, ResolvedValue);
		GameConfigMapListStyle[i] = ResolvedStyle;
		GameConfigMapListValue[i] = ResolvedValue;
	}

	log("___BuildGameConfig: assembled "$GameConfig.Length$" GameConfig entries from KFMapVoteModes.ini.",'MapVote');
}

// Linear scan for the KFGameConfigEntry whose permanent section/instance
// ID (its object Name - see the class comment at the top of
// KFGameConfigEntry.uc) matches ID. Used to resolve MapListStyle="Copy"/
// CopyMapList below. array.Find() isn't available in this SDK, same as
// every other lookup in this package.
final function KFGameConfigEntry FindEntryByID(array<KFGameConfigEntry> Entries, string ID)
{
	local int i;

	for( i=0; i<Entries.Length; i++ )
		if( string(Entries[i].Name) ~= ID )
			return Entries[i];
	return none;
}

// Resolves Entry's effective MapListStyle/map list, following a
// MapListStyle="Copy" chain to whichever mode CopyMapList ultimately
// points at (transitively, if that mode is itself a Copy). The loop is
// capped at Entries.Length hops, so a cycle (A copies B copies A) or a
// dangling/misspelled CopyMapList just falls through to the "All"/""
// default below instead of hanging or crashing. Entries is the already-
// filtered list BuildGameConfig() builds (bDisabled=true sections excluded -
// see KFGameConfigEntry.bDisabled), so CopyMapList pointing at a disabled
// mode's ID hits the same "not found" fallback as a dangling ID.
final function ResolveMapList(array<KFGameConfigEntry> Entries, KFGameConfigEntry Entry, out string OutStyle, out string OutValue)
{
	local KFGameConfigEntry Current;
	local int Depth;

	Current = Entry;
	for( Depth=0; Depth<Entries.Length; Depth++ )
	{
		if( !(Current.MapListStyle ~= "Copy") )
			break;
		Current = FindEntryByID(Entries, Current.CopyMapList);
		if( Current == none )
		{
			OutStyle = "All";
			OutValue = "";
			return;
		}
	}

	if( Current.MapListStyle ~= "Allow" )
	{
		OutStyle = "Allow";
		OutValue = JoinMapList(Current.AllowMap);
	}
	else if( Current.MapListStyle ~= "Exclude" )
	{
		OutStyle = "Exclude";
		OutValue = JoinMapList(Current.ExcludeMap);
	}
	else
	{
		OutStyle = "All";
		OutValue = "";
	}
}

// Manual comma-join - no built-in Join() exists in this SDK (the inverse
// of Split(), which is used throughout this package). Mirrors the
// comma-list convention Prefix's skip-list already uses on the read side.
final function string JoinMapList(array<string> Arr)
{
	local int i;
	local string Result;

	for( i=0; i<Arr.Length; i++ )
	{
		if( i>0 )
			Result = Result $ ",";
		Result = Result $ Arr[i];
	}
	return Result;
}

// Index-bounds-checked accessor for KFVotingReplicationInfo's overridden
// TickedReplication_GameConfig() - see GameConfigDescriptions above.
final function string GetGameConfigDescription(int Index)
{
	if( Index < 0 || Index >= GameConfigDescriptions.Length )
		return "";
	return GameConfigDescriptions[Index];
}

// ------------------------------------------------------------------
// True if Text ends with Suffix (case-insensitive) as a whole trailing
// word - i.e. the character immediately before the match, if any, isn't
// a letter. The boundary check is what stops e.g. "HardBoss: HoE" from
// having "Hard" falsely matched inside "HardBoss" - only the actual
// trailing "HoE" token counts. Ported verbatim from the client-side
// version this replaces (KFMapVotingPageX.EndsWithWord()) - see
// GameConfigDifficulty above for why this moved server-side.
// ------------------------------------------------------------------
final function bool EndsWithWord(string Text, string Suffix)
{
	local int TextLen, SuffixLen, BoundaryIdx;
	local string BoundaryCaps;

	TextLen = Len(Text);
	SuffixLen = Len(Suffix);
	if( SuffixLen == 0 || SuffixLen > TextLen )
		return false;

	if( Right(Text, SuffixLen) ~= Suffix )
	{
		BoundaryIdx = TextLen - SuffixLen - 1;
		if( BoundaryIdx < 0 )
			return true; // Suffix is the entire string.
		BoundaryCaps = Caps(Mid(Text, BoundaryIdx, 1));
		return !( Asc(BoundaryCaps) >= Asc("A") && Asc(BoundaryCaps) <= Asc("Z") );
	}
	return false;
}

// Longest/most specific aliases checked first, so "Hell on Earth" is
// found as a whole trailing phrase before any shorter alias could
// partially match. Returns "" if GameName doesn't end in any recognized
// difficulty word (e.g. "FTG" - a genuine no-difficulty-tiers mode).
// Ported verbatim from KFMapVotingPageX.DeriveDifficulty() - computed
// once here, server-side, in BuildGameConfig(), and replicated directly
// (see GameConfigDifficulty above) instead of every client re-deriving
// its own answer from GameName text.
final function string DeriveDifficulty(string GameName)
{
	if( EndsWithWord(GameName, "Hell on Earth") ) return "Hell on Earth";
	if( EndsWithWord(GameName, "Suicidal") )      return "Suicidal";
	if( EndsWithWord(GameName, "Brutal") )        return "Brutal";
	if( EndsWithWord(GameName, "Beginner") )      return "Beginner";
	if( EndsWithWord(GameName, "Normal") )        return "Normal";
	if( EndsWithWord(GameName, "Hard") )          return "Hard";
	if( EndsWithWord(GameName, "HoE") )           return "Hell on Earth";
	if( EndsWithWord(GameName, "Sui") )           return "Suicidal";
	return "";
}

// Index-bounds-checked accessor - same convention as
// GetGameConfigDescription() above.
final function string GetGameConfigDifficulty(int Index)
{
	if( Index < 0 || Index >= GameConfigDifficulty.Length )
		return "";
	return GameConfigDifficulty[Index];
}

// Index-bounds-checked accessors for the map-list-restriction parallel
// arrays above - same convention as GetGameConfigDescription(). Default to
// "All"/"" out of bounds so a not-yet-populated or malformed index just
// behaves as "no restriction" rather than accidentally excluding everything.
final function string GetGameConfigMapListStyle(int Index)
{
	if( Index < 0 || Index >= GameConfigMapListStyle.Length )
		return "All";
	return GameConfigMapListStyle[Index];
}
final function string GetGameConfigMapListValue(int Index)
{
	if( Index < 0 || Index >= GameConfigMapListValue.Length )
		return "";
	return GameConfigMapListValue[Index];
}

// ------------------------------------------------------------------
// Parses the numeric value out of a "...GameLength=NNN..." token inside a
// string - e.g. a GameConfig Options string like "GameLength=178" or,
// for Objective modes, "Difficulty=4?GameLength=16" - or a full level URL
// string like "KF-Afghanistan-ST?Game=SirenTorturers.G?GameLength=183".
// Returns -1 if not found.
// ------------------------------------------------------------------
final function int ExtractOptionInt(string Options, string Key)
{
	local int Idx, EndIdx, i;
	local string Tail, NumStr;

	Idx = InStr(Options, Key);
	if( Idx == -1 )
		return -1;

	Tail = Mid(Options, Idx + Len(Key));
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

// Kept as a thin wrapper - GameLength is the one option every mode family
// sets (used as a purely synthetic per-entry marker for most modes, and as
// the real wave count for Objective, whose 3 difficulty tiers all share
// GameLength=16 - see ExtractOptionInt(Options, "Difficulty=") below,
// which is what actually disambiguates those three from each other).
final function int ExtractGameLength(string Options)
{
	return ExtractOptionInt(Options, "GameLength=");
}

// ------------------------------------------------------------------
// Reads the live GameLength/Difficulty off Level.GetLocalURL() - a native
// LevelInfo function returning the level's full current URL as a string,
// including options (e.g.
// "KF-Afghanistan-ST?Game=SirenTorturers.G?GameLength=183"). Same native-
// function family as Level.GetURLMap(), which is already proven working
// elsewhere in this project (StMapNameWriter) - this is the sibling call
// that returns the whole URL instead of just the map name.
//
// NOT safe to call from PostBeginPlay() directly - confirmed, documented
// gotcha: Level.GetLocalURL() reads empty that early in the actor
// lifecycle. Only call this from RevalidateCurrentGameConfig() below,
// which is deferred via Timer() specifically to avoid that.
// ------------------------------------------------------------------
final function int GetLiveGameLength()
{
	return ExtractOptionInt(Level.GetLocalURL(), "GameLength=");
}

final function int GetLiveDifficultyOption()
{
	return ExtractOptionInt(Level.GetLocalURL(), "Difficulty=");
}

// ------------------------------------------------------------------
// Re-validates the persisted CurrentGameConfig index against the actual
// live map/game state, and corrects it if it looks stale. Deferred out of
// PostBeginPlay() (see bPendingCurrentGameConfigCheck/Timer() below)
// because Level.GetLocalURL() reads empty that early in the actor
// lifecycle (documented gotcha, confirmed previously in this project).
//
// IMPORTANT - GameLength/Difficulty are NOT used to decide bNeedsResolve
// below, only logged. A first version of this function folded
// GetLiveGameLength()/GetLiveDifficultyOption() into the match check on
// the assumption that Level.GetLocalURL(), once non-empty, would contain
// the same "GameLength=NNN"/"Difficulty=NNN" tokens SetupGameMap() writes
// into the ServerTravel string. That was tested on the live server and
// caused a real regression: mode-matching broke too, landing on
// GameConfig[0] on every map change instead of just the wrong difficulty
// tier. That means GetLocalURL() does NOT contain what was assumed once
// reachable (still unconfirmed exactly what it does contain - the log
// line below captures the raw string so a future session has real
// evidence instead of another guess). Until that's confirmed, matching is
// GameClass-only - the same check xVotingHandler used before any of this
// difficulty-remembering work started, and the one already proven not to
// break mode-selection. Note this also means Objective mode's 3
// difficulty tiers (which share GameLength=16, see BuildGameConfig()'s
// comments) are NOT currently disambiguated by this function - accepted
// as out of scope until GameLength/Difficulty matching can be re-enabled
// with a confirmed-correct read of the live URL.
//
// Diagnostic log() calls use the 'STVoteDiag' category deliberately - this
// server's log filters out the 'MapVote'/'MapVoteDebug' categories
// entirely (confirmed previously), so anything under those never shows up
// no matter how correct the logic is.
// ------------------------------------------------------------------
final function RevalidateCurrentGameConfig()
{
	local int LiveGameLength, LiveDifficulty, i, PreviousGameConfig;
	local bool bNeedsResolve;

	PreviousGameConfig = CurrentGameConfig;
	LiveGameLength = GetLiveGameLength();
	LiveDifficulty = GetLiveDifficultyOption();

	log("___RevalidateCurrentGameConfig: persisted="$PreviousGameConfig
		$" LiveURL="$Level.GetLocalURL()$" LiveGameLength="$LiveGameLength
		$" LiveDifficulty="$LiveDifficulty$" (diagnostic only - not used below)",'STVoteDiag');

	bNeedsResolve = ( CurrentGameConfig < 0 || CurrentGameConfig >= GameConfig.Length );
	if( !bNeedsResolve )
		bNeedsResolve = !(string(Level.Game.Class) ~= GameConfig[CurrentGameConfig].GameClass);

	if( bNeedsResolve )
	{
		// GameClass-only - see the comment above for why this doesn't (yet)
		// also compare GameLength/Difficulty.
		CurrentGameConfig = 0;
		for( i=0; i<GameConfig.Length; i++)
		{
			if( GameConfig[i].GameClass ~= string(Level.Game.Class) )
			{
				CurrentGameConfig = i;
				break;
			}
		}
	}

	log("___RevalidateCurrentGameConfig: resolved CurrentGameConfig="$CurrentGameConfig
		$" GameName="$GameConfig[CurrentGameConfig].GameName$" bNeedsResolve="$bNeedsResolve,'STVoteDiag');
}

function PostBeginPlay()
{
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
			// Re-validating CurrentGameConfig here needs Level.GetLocalURL()
			// (see RevalidateCurrentGameConfig()'s comment), which reads
			// empty this early in PostBeginPlay() - deferred to a Timer()
			// poll instead of running synchronously. Until that poll fires,
			// CurrentGameConfig is left exactly as loaded from config (its
			// value as of the last successful SaveConfig()), which is
			// already correct in the common case (this is only a stale-
			// index safety net, e.g. after a KFMapVoteModes.ini edit shifts
			// array positions - not the primary source of truth).
			bPendingCurrentGameConfigCheck = true;
			SetTimer(0.2, true);
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
	AddRandomMapSentinel();
}

// Appends one synthetic, reserved MapList entry ("RANDOM MAP") so it can be
// voted for like any real map (see IsMapValidForGameConfig()'s carve-out and
// TallyVotesInternal()'s deferred-resolution swap below). Deliberately
// mirrors only the array-growth part of AddMap() below (MapList/RepArray/
// MapPreviewArray kept in lock-step via MapCount) - never calls
// History.GetMapHistory()/History.AddMap() or
// MVMapRepHistory.GetMapHistoryRep(), since this isn't a real map and
// shouldn't pollute the map-history or reputation INIs. Called once from
// LoadMapList() above, after Super.LoadMapList() has fully rebuilt MapList/
// MapCount from the real map pool (including any bEliminationMode reload,
// which happens entirely inside Super.LoadMapList() before it returns here).
final function AddRandomMapSentinel()
{
	local int i;

	for( i=0; i<MapList.Length; i++ )  // dont add duplicate - same guard AddMap() uses
		if( RANDOM_MAP_NAME ~= MapList[i].MapName )
			return;

	RepArray.Length = MapCount + 1;
	RepArray[MapCount].Positive = 0;
	RepArray[MapCount].Negative = 0;

	// TextureRef/Author/PlayerCountMin/Max left at defaults (blank/0) - falls
	// back to KFMapVoteFooterX's existing "No Preview Available" path, same as
	// any real map with no KFMapVotePreviews.ini override.
	MapPreviewArray.Length = MapCount + 1;

	MapList.Length = MapCount + 1;
	MapList[MapCount].MapName = RANDOM_MAP_NAME;
	MapList[MapCount].PlayCount = 0;
	MapList[MapCount].Sequence = 0;
	MapList[MapCount].bEnabled = true;
	MapCount++;
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
		// RANDOM MAP resolution swap (not present upstream) - an admin can
		// force-select the sentinel directly, bypassing TallyVotesInternal()
		// entirely, so this call site needs its own copy of the same swap.
		// GameIndex is passed as the requested mode and only ever rewritten
		// by PickRandomMapForGameConfig() in the fully-degenerate fallback
		// case (no real map qualifies for it at all) - see that function.
		if( MapList[MapIndex].MapName ~= RANDOM_MAP_NAME )
		{
			PickRandomMapForGameConfig(GameIndex, MapIndex);
			SetRandomMapVoteFlag(true);
		}
		else
		{
			SetRandomMapVoteFlag(false); // defensive reset - a real map was chosen directly
		}

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
		TallyVotesInternal(bForceMapSwitch);
	}

	C = Level.Game.NumPlayers;
	Level.Game.NumPlayers+=Level.Game.NumSpectators;
	TallyVotesInternal(bForceMapSwitch);
	Level.Game.NumPlayers = C;
}

// ====================================================================
// Full duplicate of the base engine's xVotingHandler.TallyVotes()
// (XVoting/Classes/xVotingHandler.uc, lines ~546-716 as last verified)
// - same pattern this file already uses for SetupGameMap() above, just a
// larger instance of it. Needed because the winner-resolution logic below
// (ranking, tie-break, win broadcast, History.PlayMap(), SetupGameMap(),
// Level.ServerTravel()) has no override seam between "topmap is finalized"
// and "broadcast/History/travel fire" - SetupGameMap() (already overridden)
// is called too late, after the win broadcast has already rendered the map
// name to every player and after History.PlayMap() has already run. The
// ONLY change from the base version is the swap block immediately after the
// blank-MapName guard below, which resolves a winning "RANDOM MAP" vote
// (see AddRandomMapSentinel()/IsMapValidForGameConfig() above) into a real
// destination map before anything downstream (broadcast, History, travel)
// ever sees the sentinel - everything else is byte-for-byte from upstream.
// If XVoting is ever updated, re-diff this function against the new
// xVotingHandler.TallyVotes() and reapply just that one swap block.
// ====================================================================
final function TallyVotesInternal(bool bForceMapSwitch)
{
	local int        index,x,y,topmap,r,mapidx,gameidx;
	local array<int> VoteCount;
	local array<int> Ranking;
	local int        PlayersThatVoted;
	local int        TieCount;
	local string     CurrentMap;
	local int        Votes;
	local MapHistoryInfo MapInfo;

	if(bLevelSwitchPending)
		return;

	PlayersThatVoted = 0;
	VoteCount.Length = GameConfig.Length * MapCount;
	// note: VoteCount array is a 2 dimension array VoteCount[GameConfigIndex, MapIndex]
	//       Maps ->
	//       0 1 2 3 4 5 6 7 8
	// G     - - - - - - - - -
	// a  0 |0 0 0 0 0 0 0 2 0
	// m  1 |0 0 0 2 0 0 0 0 0
	// e  2 |0 6 0 0 0 5 0 0 0
	// s  3 |0 0 0 3 0 0 0 0 0

	for(x=0;x < MVRI.Length;x++) // for each player
	{
		if(MVRI[x] != none && MVRI[x].MapVote > -1 && MVRI[x].GameVote > -1) // if this player has voted
		{
			PlayersThatVoted++;

			if(bScoreMode)
			{
				if(bAccumulationMode)
					Votes = GetAccVote(MVRI[x].PlayerOwner) + int(GetPlayerScore(MVRI[x].PlayerOwner));
				else
					Votes = int(GetPlayerScore(MVRI[x].PlayerOwner));
			}
			else
			{  // Not Score Mode == Majority (one vote per player)
				if(bAccumulationMode)
					Votes = GetAccVote(MVRI[x].PlayerOwner) + 1;
				else
					Votes = 1;
			}
			VoteCount[MVRI[x].GameVote * MapCount + MVRI[x].MapVote] = VoteCount[MVRI[x].GameVote * MapCount + MVRI[x].MapVote] + Votes;

			if(!bScoreMode)
			{
				// If more then half the players voted for the same map as this player then force a winner
				if(Level.Game.NumPlayers > 2 && float(VoteCount[MVRI[x].GameVote * MapCount + MVRI[x].MapVote]) / float(Level.Game.NumPlayers) > 0.5 && Level.Game.bGameEnded)
					bForceMapSwitch = true;
			}
		}
	}
	log("___Voted - " $ PlayersThatVoted,'MapVoteDebug');

	if(Level.Game.NumPlayers > 2 && !Level.Game.bGameEnded && !bMidGameVote && (float(PlayersThatVoted) / float(Level.Game.NumPlayers)) * 100 >= MidGameVotePercent) // Mid game vote initiated
	{
		Level.Game.Broadcast(self,lmsgMidGameVote);
		bMidGameVote = true;
		// Start voting count-down timer
		TimeLeft = VoteTimeLimit;
		ScoreBoardTime = 1;
		settimer(1,true);
	}

	index = 0;
	for(x=0;x < VoteCount.Length;x++) // for each map
	{
		if(VoteCount[x] > 0)
		{
			Ranking.Insert(index,1);
			Ranking[index++] = x; // copy all vote indexes to the ranking list if someone has voted for it.
		}
	}

	if(PlayersThatVoted > 1)
	{
		// bubble sort ranking list by vote count
		for(x=0; x<index-1; x++)
		{
			for(y=x+1; y<index; y++)
			{
				if(VoteCount[Ranking[x]] < VoteCount[Ranking[y]])
				{
				topmap = Ranking[x];
				Ranking[x] = Ranking[y];
				Ranking[y] = topmap;
				}
			}
		}
	}
	else
	{
		if(PlayersThatVoted == 0)
		{
			GetDefaultMap(mapidx, gameidx);
			topmap = gameidx * MapCount + mapidx;
		}
		else
			topmap = Ranking[0];  // only one player voted
	}

	//Check for a tie
	if(PlayersThatVoted > 1) // need more than one player vote for a tie
	{
		if(index > 1 && VoteCount[Ranking[0]] == VoteCount[Ranking[1]] && VoteCount[Ranking[0]] != 0)
		{
			TieCount = 1;
			for(x=1; x<index; x++)
			{
				if(VoteCount[Ranking[0]] == VoteCount[Ranking[x]])
				TieCount++;
			}
			//reminder ---> int Rand( int Max ); Returns a random number from 0 to Max-1.
			topmap = Ranking[Rand(TieCount)];

			// Don't allow same map to be choosen
			CurrentMap = GetURLMap();

			r = 0;
			while(MapList[topmap - (topmap/MapCount) * MapCount].MapName ~= CurrentMap)
			{
				topmap = Ranking[Rand(TieCount)];
				if(r++>100)
					break;  // just incase
			}
		}
		else
		{
			topmap = Ranking[0];
		}
	}

	// if everyone has voted go ahead and change map
	if(bForceMapSwitch || (Level.Game.NumPlayers == PlayersThatVoted && Level.Game.NumPlayers > 0) )
	{
		if(MapList[topmap - topmap/MapCount * MapCount].MapName == "")
			return;

		// ---- RANDOM MAP resolution swap (not present upstream) ----
		// If the winning bucket is the "RANDOM MAP" sentinel, resolve it to a
		// real, valid map for the winning mode now - the only point where
		// this is safe to do, since everything below this line (broadcast
		// text, History.PlayMap(), SetupGameMap()) must see the REAL
		// destination map, not the sentinel. See PickRandomMapForGameConfig()
		// and SetRandomMapVoteFlag() above.
		mapidx  = topmap - topmap/MapCount * MapCount;
		gameidx = topmap/MapCount;

		if( MapList[mapidx].MapName ~= RANDOM_MAP_NAME )
		{
			PickRandomMapForGameConfig(gameidx, mapidx);
			topmap = gameidx * MapCount + mapidx;
			SetRandomMapVoteFlag(true);
		}
		else
		{
			SetRandomMapVoteFlag(false); // defensive reset - a real map won outright
		}
		// ---- end RANDOM MAP resolution swap ----

		TextMessage = lmsgMapWon;
		TextMessage = repl(TextMessage,"%mapname%",MapList[topmap - topmap/MapCount * MapCount].MapName $ "(" $ GameConfig[topmap/MapCount].Acronym $ ")");
		Level.Game.Broadcast(self,TextMessage);

		CloseAllVoteWindows();

		MapInfo = History.PlayMap(MapList[topmap - topmap/MapCount * MapCount].MapName);

		ServerTravelString = SetupGameMap(MapList[topmap - topmap/MapCount * MapCount], topmap/MapCount, MapInfo);
		log("ServerTravelString = " $ ServerTravelString ,'MapVoteDebug');

		History.Save();

		if(bEliminationMode)
			RepeatLimit++;

		if(bAccumulationMode)
			SaveAccVotes(topmap - topmap/MapCount * MapCount, topmap/MapCount);

		//if(bEliminationMode || bAccumulationMode)
		CurrentGameConfig = topmap/MapCount;
		if( !bAutoDetectMode )
			SaveConfig();

		bLevelSwitchPending = true;
		settimer(Level.TimeDilation,true);  // timer() will monitor the server-travel and detect a failure

		Level.ServerTravel(ServerTravelString, false);    // change the map
	}
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
	M.PreviewAnimFrameRate = PreviewAnimFrameRate;
	MVRI[MVRI.Length] = M;
}

function Timer()
{
	local int mapidx,gameidx,i;
	local MapHistoryInfo MapInfo;

	// Deferred CurrentGameConfig re-validation from PostBeginPlay() - see
	// bPendingCurrentGameConfigCheck's declaration and
	// RevalidateCurrentGameConfig() above. Re-fires every 0.2s (the
	// SetTimer(0.2, true) call in PostBeginPlay() was set to loop) until
	// Level.GetLocalURL() actually returns data, then does the real check
	// once and cancels this timer - a real vote cycle hasn't started yet
	// this early, so nothing else is relying on Timer() firing during this
	// short window.
	if( bPendingCurrentGameConfigCheck )
	{
		if( Level.GetLocalURL() == "" )
			return;
		bPendingCurrentGameConfigCheck = false;
		SetTimer(0, false);
		RevalidateCurrentGameConfig();
		return;
	}

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
				SetRandomMapVoteFlag(false); // defensive reset - a failed-switch recovery is never a deliberate random-map outcome
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
	return IsMapValidForGameConfig(MapIndex, GameIndex);
}

// Server-side authority check: does MapList[MapListIdx] belong to
// GameConfig[GCIdx]'s map list? Combines the original Prefix/skip-list
// match (unchanged from before this field existed) with the new
// MapListStyle Allow/Exclude restriction, so a modified client can't
// submit a vote for a map the mode disallows even if the client-side GUI
// filtering in MVMultiColumnList.LoadList() is bypassed - same
// defense-in-depth already relied on for Prefix.
final function bool IsMapValidForGameConfig(int MapListIdx, int GCIdx)
{
	local string A,B,MapListStyle,MapName;
	local array<string> PL,ModeMapList;
	local int i;
	local bool bInList;

	MapName = MapList[MapListIdx].MapName;

	// "RANDOM MAP" is valid for every mode by design - see
	// AddRandomMapSentinel() above. It's never actually traveled to directly;
	// TallyVotesInternal()'s deferred-resolution swap (and SubmitMapVote()'s
	// bAdminForce branch) are the only places it's turned into a real
	// destination map.
	if( MapName ~= RANDOM_MAP_NAME )
		return true;

	A = GameConfig[GCIdx].Prefix;
	Divide(A,"|",A,B);
	Split(A, ",", PL);

	for( i=(PL.Length-1); i>=0; --i )
		if( Left(MapName, len(PL[i]))~=PL[i] )
			break;
	if( i==-1 )
		return false;

	if( B!="" )
	{
		Split(B, ",", PL);
		for( i=(PL.Length-1); i>=0; --i )
			if( Left(MapName, len(PL[i]))~=PL[i] )
				return false;
	}

	MapListStyle = GetGameConfigMapListStyle(GCIdx);
	if( MapListStyle != "All" )
	{
		Split(GetGameConfigMapListValue(GCIdx), ",", ModeMapList);
		bInList = false;
		for( i=(ModeMapList.Length-1); i>=0; --i )
		{
			if( ModeMapList[i] ~= MapName )
			{
				bInList = true;
				break;
			}
		}
		if( (MapListStyle ~= "Allow" && !bInList) || (MapListStyle ~= "Exclude" && bInList) )
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

// Picks a real, enabled, Prefix/MapListStyle-valid map for a SPECIFIC
// GameConfig index (unlike GetDefaultMap() above, which always targets
// CurrentGameConfig/DefaultGameConfig) - used to resolve a winning "RANDOM
// MAP" vote (see AddRandomMapSentinel()/IsMapValidForGameConfig() above) into
// a real destination map. GCIdx/mapidx are both out/inout: GCIdx is read as
// the requested mode and only ever rewritten in the fully-degenerate fallback
// case described below. Mirrors GetDefaultMap()'s own random-draw /
// 100-attempt-retry / linear-scan-fallback structure, but driven by
// IsMapValidForGameConfig() instead of raw Prefix matching, so it also
// respects MapListStyle Allow/Exclude (GetDefaultMap() itself predates
// MapListStyle and doesn't check it - a separate, pre-existing gap, not
// addressed here).
//
// IMPORTANT: because IsMapValidForGameConfig() deliberately returns true for
// the sentinel's own index under EVERY GCIdx, this function must explicitly
// exclude the sentinel's own index at every stage of its search - relying on
// IsMapValidForGameConfig() alone would let it pick itself right back, which
// would attempt Level.ServerTravel("RANDOM MAP?...") in the fully-degenerate
// case of a mode with zero real qualifying maps. If no real candidate exists
// at all for GCIdx, falls back to the existing GetDefaultMap() (sentinel-safe
// by construction, since raw Prefix matching can never match "RANDOM MAP"),
// accepting it may resolve to a different mode than GCIdx in that
// fully-degenerate case - mirroring GetDefaultMap()'s own last-resort
// behavior when nothing matches the requested mode either.
final function PickRandomMapForGameConfig(out int GCIdx, out int mapidx)
{
	local int i,r,SentinelIdx;
	local bool bLoop;

	SentinelIdx = -1;
	for( i=0; i<MapList.Length; i++ )
		if( RANDOM_MAP_NAME ~= MapList[i].MapName )
		{
			SentinelIdx = i;
			break;
		}

	if( MapCount <= 0 )
	{
		mapidx = 0;
		return;
	}

	r = 0;
	bLoop = true;
	while( bLoop )
	{
		i = Rand(MapCount);
		if( i != SentinelIdx && MapList[i].bEnabled && IsMapValidForGameConfig(i, GCIdx) )
			bLoop = false;

		if( bLoop && r++ > 100 )
		{
			// give up after 100 unsuccessful attempts - linear scan for the
			// first qualifying map instead (mirrors GetDefaultMap()'s own
			// fallback tier).
			for( i=0; i<MapCount; ++i )
			{
				if( i != SentinelIdx && MapList[i].bEnabled && IsMapValidForGameConfig(i, GCIdx) )
				{
					bLoop = false;
					break;
				}
			}
			break;
		}
	}

	if( !bLoop && i<MapCount && i!=SentinelIdx )
	{
		mapidx = i;
		log("Random Map Choosen = " $ MapList[mapidx].MapName $ "(" $ GameConfig[GCIdx].Acronym $ ")",'MapVoteDebug');
		return;
	}

	// Fully degenerate case: no real map qualifies for GCIdx at all.
	log("___PickRandomMapForGameConfig: no real map qualifies for GameConfig "$GCIdx$" - falling back to GetDefaultMap().",'MapVote');
	GetDefaultMap(mapidx, GCIdx);
}

// Writes a small, standalone signal (see KFRandomMapVoteFlag.uc) that a
// completely separate mod - ScrnBalanceST - can optionally read after the
// map change to apply its own "random map" stat bonus, the same way it
// already does for its own unrelated `mvote map random` chat-vote feature.
// KFMapVoteST itself has zero awareness of ScrnBalanceST/ScrnBalance - this
// class and this function work identically whether or not that mod is even
// installed. Called at every Level.ServerTravel() call site tied to vote
// resolution (see TallyVotesInternal()'s winner block, SubmitMapVote()'s
// bAdminForce branch, and Timer()'s failed-switch-recovery branch) so the
// flag never lingers stale from an earlier round.
final function SetRandomMapVoteFlag(bool bValue)
{
	local KFRandomMapVoteFlag F;

	F = new class'KFRandomMapVoteFlag';
	F.bWasRandomMapVote = bValue;
	F.SaveConfig();
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
	PreviewAnimFrameRate=1.0
}