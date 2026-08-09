//-----------------------------------------------------------
// KFMapVotingPageX - Modification by Marco
//-----------------------------------------------------------
class KFMapVotingPageX extends ROMapVotingPage;

var automated moEditBox SearchEdit;
var automated moComboBox co_Difficulty;
var automated GUILabel lbl_Description;
var localized string strHelp;

// Tracks the difficulty currently selected in co_Difficulty, so
// OnDifficultyChanged() can tell whether a change actually happened and
// so we always know what to compare candidate modes' distance against.
var string CurrentDifficulty;

// Display order for the difficulty dropdown's distinct values. Hardcoded
// (edit + recompile to change) rather than ini-configurable - see the
// note above DeriveDifficulty() for why: this used to be a replicated
// array sourced from an ini, and that turned out to be what was crashing
// the server on map change. Not worth the risk for a ~4-item list that
// rarely changes.
var string DifficultyOrder[4];

function InternalOnOpen()
{
	super.InternalOnOpen();

	if (!bHasFocus) {
		// fixes PreDraw errors
		lb_MapListBox.SetVisibility(false);
		lb_VoteCountListBox.SetVisibility(false);
		return;
	}

	lb_MapListBox.SetVisibility(true);
	lb_VoteCountListBox.SetVisibility(true);

	// Difficulty and mode-family are derived entirely from
	// MVRI.GameConfig[i].GameName text (see DeriveDifficulty()/
	// DeriveModeGroup() below) rather than any dedicated replicated
	// property, so all we need here is confirmation GameConfig itself is
	// populated - which super.InternalOnOpen() already guarantees before
	// returning normally (it bails to a separate "still loading" page
	// otherwise). No extra replication-readiness guard needed.
	//
	// The default difficulty is whatever CurrentGameConfig() (MVRI's
	// CurrentGameConfig, set server-side in KFVotingHandler.PostBeginPlay())
	// actually is right now - i.e. the true live mode/difficulty, computed
	// from GameClass+GameLength server-side rather than any per-player
	// preference. That naturally tracks "the last thing voted for and
	// traveled to" without needing to persist anything client-side at all.
	if( MVRI != none && MVRI.bMapVote && MVRI.GameConfig.Length > 0 )
	{
		BuildDifficultyList();

		CurrentDifficulty = "";
		if( CurrentGameConfig() > -1 && CurrentGameConfig() < MVRI.GameConfig.Length )
			CurrentDifficulty = DeriveDifficulty(MVRI.GameConfig[CurrentGameConfig()].GameName);

		if( CurrentDifficulty != "" )
		{
			SelectDifficultyItem(CurrentDifficulty);
			RebuildGameTypeList(CurrentDifficulty, DeriveModeGroup(MVRI.GameConfig[CurrentGameConfig()].GameName), CurrentGameConfig());
		}
	}

	// Covers both branches above (filtered and not) - GameTypeChanged()
	// keeps this in sync from here on for every subsequent mode/difficulty
	// change.
	UpdateDescriptionLabel(CurrentGameConfig());

	if (f_Chat.ed_Chat.GetText() != "") {
		f_Chat.ed_Chat.SetFocus(none);
		SetFocus(f_Chat.ed_Chat);
		// move the cursor to the end of the text
		f_Chat.ed_Chat.MyEditBox.CaretPos = len(f_Chat.ed_Chat.GetText());
		f_Chat.ed_Chat.MyEditBox.bAllSelected = false;
	}
	else {
		Controller.PlayInterfaceSound(CS_Edit);
		SearchEdit.SetFocus(none);
	}
	f_Chat.ReceiveChat(strHelp);
}

// Small helper - the currently selected GameConfig index, straight off the
// mode combo's Extra field, same way GameTypeChanged/SendVote already read it.
final function int CurrentGameConfig()
{
	return int(co_GameType.GetExtra());
}

// Single-click handler inherited from XVoting.MapVotingPage, already wired
// as OnClick for both lb_VoteCountListBox and lb_MapListBox in
// MapVotingPage.InternalOnOpen(). Overridden here purely to also drive the
// inline map preview panel (image + author + player count) in the footer -
// preserves the base selection/highlight behavior via Super first.
function bool MapListClick(GUIComponent Sender)
{
	local bool bResult;
	local string MapName;
	local int MapIndex;
	local KFVotingHandler.FMapPreviewData PreviewOverride;

	bResult = Super.MapListClick(Sender);

	if( Sender == lb_VoteCountListBox.List )
		MapIndex = MapVoteCountMultiColumnList(Sender).GetSelectedMapIndex();
	else if( Sender == lb_MapListBox.List )
		MapIndex = MapVoteMultiColumnList(Sender).GetSelectedMapIndex();
	else
		MapIndex = -1;

	if( MapIndex > -1 && MapIndex < MVRI.MapList.Length )
	{
		MapName = MVRI.MapList[MapIndex].MapName;

		// MVRI is declared as base VotingReplicationInfo in XVoting -
		// MapPreviewList only exists on our KFVotingReplicationInfo
		// subclass, so an explicit downcast is required (base-typed refs
		// don't expose subclass-only members in this engine). Bounds-
		// checked separately since MapPreviewList fills in one map at a
		// time over several ticks and may briefly be shorter than
		// MapList while that's still in progress.
		if( MapIndex < KFVotingReplicationInfo(MVRI).MapPreviewList.Length )
			PreviewOverride = KFVotingReplicationInfo(MVRI).MapPreviewList[MapIndex];
	}

	// f_Chat is declared as base MapVoteFooter in XVoting.VotingPage -
	// UpdateMapPreview only exists on our KFMapVoteFooterX subclass, so an
	// explicit downcast is required (base-typed refs don't expose
	// subclass-only members in this engine).
	KFMapVoteFooterX(f_Chat).UpdateMapPreview(MapName, PreviewOverride);

	return bResult;
}

// Also allow admins force mapswitch.
final function SendAdminSwitch(GUIComponent Sender)
{
	local int MapIndex,GameConfigIndex;

	if( Sender == lb_VoteCountListBox.List )
	{
		MapIndex = MapVoteCountMultiColumnList(lb_VoteCountListBox.List).GetSelectedMapIndex();
		if( MapIndex>=0 )
			GameConfigIndex = MapVoteCountMultiColumnList(lb_VoteCountListBox.List).GetSelectedGameConfigIndex();
	}
	else
	{
		MapIndex = MapVoteMultiColumnList(lb_MapListBox.List).GetSelectedMapIndex();
		if( MapIndex>=0 )
			GameConfigIndex = int(co_GameType.GetExtra());
	}
	if( MapIndex>=0 )
		MVRI.SendMapVote(MapIndex,-(GameConfigIndex+1)); // Send with negative game index to indicate admin switch.
}

// Allow admins vote like all other players.
function SendVote(GUIComponent Sender)
{
	local int MapIndex,GameConfigIndex;

	if( Sender == lb_VoteCountListBox.List )
	{
		MapIndex = MapVoteCountMultiColumnList(lb_VoteCountListBox.List).GetSelectedMapIndex();
		if( MapIndex>=0 )
			GameConfigIndex = MapVoteCountMultiColumnList(lb_VoteCountListBox.List).GetSelectedGameConfigIndex();
	}
	else
	{
		MapIndex = MapVoteMultiColumnList(lb_MapListBox.List).GetSelectedMapIndex();
		if( MapIndex>=0 )
			GameConfigIndex = int(co_GameType.GetExtra());
	}
	if( MapIndex>=0 )
	{
		if( MVRI.MapList[MapIndex].bEnabled )
			MVRI.SendMapVote(MapIndex,GameConfigIndex);
		else PlayerOwner().ClientMessage(lmsgMapDisabled);
	}
}

function GameTypeChanged(GUIComponent Sender)
{
	super.GameTypeChanged(Sender);
	SearchEdit.SetText("");
	UpdateDescriptionLabel(CurrentGameConfig());
}

// Shows the selected mode's Description (KFMapVoteModes.ini,
// KFGameConfigEntry.Description) in the panel that used to be occupied by
// the map search box - see KFVotingHandler.GameConfigDescriptions /
// KFVotingReplicationInfo.ReceiveGameConfigRep() for how this reaches the
// client. Downcast to KFVotingReplicationInfo mirrors the same pattern
// MapListClick() already uses for MapPreviewList - GameConfigDescriptions
// only exists on our subclass, not the base VotingReplicationInfo type
// MVRI is declared as.
final function UpdateDescriptionLabel(int GameConfigIndex)
{
	local string Description;
	local KFVotingReplicationInfo KFMVRI;

	KFMVRI = KFVotingReplicationInfo(MVRI);
	if( KFMVRI != none && GameConfigIndex > -1 && GameConfigIndex < KFMVRI.GameConfigDescriptions.Length )
		Description = KFMVRI.GameConfigDescriptions[GameConfigIndex];

	if( Description != "" )
		lbl_Description.Caption = "Description: " $ Description;
	else
		lbl_Description.Caption = "";
}

function bool InternalOnKeyEvent(out byte Key, out byte State, float delta)
{
	local Interactions.EInputKey iKey;
	if (State != 3)
		return false;

	iKey = EInputKey(Key);
	if (iKey >= IK_F1 && iKey < IK_F12) {
		// F keys
		switch (iKey) {
			case IK_F1:
				Controller.PlayInterfaceSound(CS_Edit);
				f_Chat.ReceiveChat(strHelp);
				return true;
			case IK_F2:
				Controller.PlayInterfaceSound(CS_Edit);
				f_Chat.ed_Chat.SetFocus(none);
				SetFocus(f_Chat.ed_Chat);
				return true;
			case IK_F3:
				Controller.PlayInterfaceSound(CS_Edit);
				SearchEdit.SetFocus(none);
				SetFocus(SearchEdit);
				return true;
			case IK_F4:
				Controller.PlayInterfaceSound(CS_Edit);
				co_GameType.SetFocus(none);
				SetFocus(co_GameType);
				co_GameType.MyComboBox.ShowListBox(co_GameType.MyComboBox);
				return true;
		}
	}
	return false;
}

function bool OnGameTypeKey(out byte Key, out byte State, float delta)
{
	local Interactions.EInputKey iKey;

	if (State != 3)
		return false;

	iKey = EInputKey(Key);
	if (iKey == IK_Enter) {
		Controller.PlayInterfaceSound(CS_Edit);
		co_GameType.MyComboBox.ShowListBox(co_GameType.MyComboBox);
		if (!co_GameType.MyComboBox.MyListBox.bVisible) {
			SearchEdit.SetFocus(none);
			SetFocus(SearchEdit);
		}
		return true;
	}
	return false;
}


function bool OnSearchKey(out byte Key, out byte st, float delta)
{
	// PlayerOwner().ClientMessage("OnSearchKeyType Key="$Key @ "State="$State);
	if (st != 3)
		return false;  // not a key press

	// redirect Fn keys to BuyMenuTab
	if (Key >= 0x70 && Key < 0x7C) {
		return InternalOnKeyEvent(Key, st, delta);
	}

	switch (Key) {
		case 0x08: // IK_Backspace
			if (Controller.CtrlPressed) {
				SearchEdit.SetText("");
				Key = 0;
				st = 0;
				return true;
			}
			break;
		case 0x0D: // IK_Enter
			SendVote(lb_MapListBox.List);
			return true;
		case 0x26: // IK_Up
			lb_MapListBox.List.Up();
			return true;
		case 0x28: // IK_Down
			lb_MapListBox.List.Down();
			return true;
	}
	return SearchEdit.MyEditBox.InternalOnKeyEvent(Key, st, delta);
}

function bool OnSearchKeyType(out byte Key, optional string Unicode)
{
    // PlayerOwner().ClientMessage("OnSearchKeyType Key="$Key @ "Unicode="$Unicode);
    if (Key == 127) {
        return true;  // control characters
    }
    if (Unicode == "`" || Unicode == "~") {
        // ignore console key input
        return true;
    }
    return SearchEdit.MyEditBox.InternalOnKeyType(Key, Unicode);
}

function OnSearchChange(GUIComponent Sender)
{
    local string s;

    s = SearchEdit.GetText();
	MVMultiColumnList(lb_MapListBox.List).ApplyFilter(s);
}

// ------------------------------------------------------------------
// Difficulty dropdown - population, selection, and filtering
//
// Difficulty and mode-family are derived entirely from GameConfig[i].
// GameName text on the client, rather than any dedicated replicated
// property. This is deliberate: GameName is already part of the base-
// engine GameConfig struct and has been replicating reliably in
// production for years (that's what's rendering the mode dropdown
// correctly right now). An earlier version of this feature added
// GameDifficulty/GameModeGroup/DifficultyOrder as brand-new replicated
// arrays on KFVotingReplicationInfo - that version reliably crashed the
// server on every map change; reverting those specific properties, with
// everything else unchanged, fixed it. So: zero new replicated
// properties, derive everything from data already proven to replicate
// safely instead.
// ------------------------------------------------------------------

// True if Text ends with Suffix (case-insensitive) as a whole trailing
// word - i.e. the character immediately before the match, if any, isn't
// a letter. The boundary check is what stops e.g. "HardBoss: HoE" from
// having "Hard" falsely matched inside "HardBoss" - only the actual
// trailing "HoE" token counts.
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
// partially match. Returns "" (unfiltered - always shown) if GameName
// doesn't end in any recognized difficulty word - hand-verified against
// every entry in the current KFMapVoteModes.ini, including the tricky
// ones ("HardBoss: HoE", "LoneGunmen Advanced HOE", the three-word
// "...Hell on Earth").
final function string DeriveDifficulty(string GameName)
{
	if( EndsWithWord(GameName, "Hell on Earth") ) return "Hell on Earth";
	if( EndsWithWord(GameName, "Suicidal") )      return "Suicidal";
	if( EndsWithWord(GameName, "Brutal") )        return "Brutal";
	if( EndsWithWord(GameName, "Hard") )          return "Hard";
	if( EndsWithWord(GameName, "HoE") )           return "Hell on Earth";
	if( EndsWithWord(GameName, "Sui") )           return "Suicidal";
	return "";
}

// Strips a leading "NN. " index (e.g. "00. Standard: Hard") and a
// trailing recognized difficulty word/phrase, leaving the shared "mode
// family" name - e.g. "00. Standard: Hard" -> "Standard", "Chocolate
// Helicopters HoE" -> "Chocolate Helicopters". Entries with no recognized
// trailing difficulty word (e.g. "FTG") come back mostly as-is, which
// correctly makes them a "family of one" that stays visible under any
// difficulty filter.
final function string DeriveModeGroup(string GameName)
{
	local string Remainder;
	local int i, DigitEnd;

	Remainder = GameName;

	// Trim whichever alias actually matched (re-checked in the same
	// priority order as DeriveDifficulty, since we need to know exactly
	// how many characters to cut - "HoE"/"HOE" and "Hell on Earth" both
	// mean the same canonical difficulty but are different lengths).
	if( EndsWithWord(Remainder, "Hell on Earth") )    Remainder = Left(Remainder, Len(Remainder)-Len("Hell on Earth"));
	else if( EndsWithWord(Remainder, "Suicidal") )    Remainder = Left(Remainder, Len(Remainder)-Len("Suicidal"));
	else if( EndsWithWord(Remainder, "Brutal") )      Remainder = Left(Remainder, Len(Remainder)-Len("Brutal"));
	else if( EndsWithWord(Remainder, "Hard") )        Remainder = Left(Remainder, Len(Remainder)-Len("Hard"));
	else if( EndsWithWord(Remainder, "HoE") )         Remainder = Left(Remainder, Len(Remainder)-Len("HoE"));
	else if( EndsWithWord(Remainder, "Sui") )         Remainder = Left(Remainder, Len(Remainder)-Len("Sui"));

	// Trim trailing whitespace, then a single trailing ':' left over from
	// e.g. "Faster Floor: Hard" -> "Faster Floor: " -> "Faster Floor:"
	// -> "Faster Floor".
	while( Len(Remainder) > 0 && Right(Remainder,1) == " " )
		Remainder = Left(Remainder, Len(Remainder)-1);
	if( Len(Remainder) > 0 && Right(Remainder,1) == ":" )
		Remainder = Left(Remainder, Len(Remainder)-1);

	// Strip a leading "NN. " (or "NNN. ", etc.) numeric index, e.g.
	// "00. Standard" -> "Standard".
	DigitEnd = -1;
	for( i=0; i<Len(Remainder); i++ )
	{
		if( Asc(Mid(Remainder,i,1)) >= Asc("0") && Asc(Mid(Remainder,i,1)) <= Asc("9") )
			DigitEnd = i;
		else
			break;
	}
	if( DigitEnd > -1 && DigitEnd+1 < Len(Remainder) && Mid(Remainder,DigitEnd+1,1) == "." )
	{
		Remainder = Mid(Remainder, DigitEnd+2);
		while( Len(Remainder) > 0 && Left(Remainder,1) == " " )
			Remainder = Mid(Remainder, 1);
	}

	return Remainder;
}

// Populates co_Difficulty with every distinct, non-blank difficulty found
// across GameConfig's GameName values, ordered per DifficultyOrder first,
// then any leftover values (not listed in DifficultyOrder) appended
// alphabetically. Deliberately never calls List.SortList() on this combo
// - that's what silently re-alphabetizes co_GameType regardless of
// GameConfig's own SortOrder (see KFVotingHandler.BuildGameConfig()'s
// comments) - here we want our own explicit order to actually stick.
final function BuildDifficultyList()
{
	local array<string> Distinct, Leftover;
	local int i, j;
	local bool bFound;
	local string D;

	for( i=0; i<MVRI.GameConfig.Length; i++ )
	{
		D = DeriveDifficulty(MVRI.GameConfig[i].GameName);
		if( D == "" )
			continue;
		bFound = false;
		for( j=0; j<Distinct.Length; j++ )
		{
			if( Distinct[j] ~= D )
			{
				bFound = true;
				break;
			}
		}
		if( !bFound )
			Distinct[Distinct.Length] = D;
	}

	co_Difficulty.MyComboBox.List.Clear();

	// Ordered entries first, removing each from Distinct as it's placed so
	// whatever's left afterward is genuinely "not in DifficultyOrder".
	for( i=0; i<ArrayCount(DifficultyOrder); i++ )
	{
		for( j=0; j<Distinct.Length; j++ )
		{
			if( Distinct[j] ~= DifficultyOrder[i] )
			{
				co_Difficulty.AddItem(Distinct[j], none, Distinct[j]);
				Distinct.Remove(j,1);
				break;
			}
		}
	}

	// Whatever's left: simple selection sort, alphabetical, case-insensitive.
	Leftover = Distinct;
	for( i=0; i<Leftover.Length-1; i++ )
	{
		BestIdx_ForSort(Leftover, i);
	}
	for( i=0; i<Leftover.Length; i++ )
		co_Difficulty.AddItem(Leftover[i], none, Leftover[i]);
}

// In-place selection-sort step (alphabetical, case-insensitive) - swaps the
// smallest remaining element into position i. Split out only to keep
// BuildDifficultyList() readable.
final function BestIdx_ForSort(out array<string> Arr, int i)
{
	local int j, BestIdx;
	local string Tmp;

	BestIdx = i;
	for( j=i+1; j<Arr.Length; j++ )
	{
		if( Caps(Arr[j]) < Caps(Arr[BestIdx]) )
			BestIdx = j;
	}
	if( BestIdx != i )
	{
		Tmp = Arr[i];
		Arr[i] = Arr[BestIdx];
		Arr[BestIdx] = Tmp;
	}
}

final function SelectDifficultyItem(string Difficulty)
{
	local int d;

	d = co_Difficulty.MyComboBox.List.FindExtra(Difficulty);
	if( d > -1 )
		co_Difficulty.SetIndex(d);
	CurrentDifficulty = Difficulty;
}

// Index of a difficulty within DifficultyOrder, or -1 if it isn't listed
// there (e.g. a difficulty word someone forgot to add to the order list -
// it still shows in the dropdown, appended alphabetically, but it has no
// defined ordinal position for "closest available" purposes).
final function int FindDifficultyOrderIndex(string D)
{
	local int i;

	for( i=0; i<ArrayCount(DifficultyOrder); i++ )
		if( DifficultyOrder[i] ~= D )
			return i;
	return -1;
}

// -1 if either side has no defined ordinal position.
final function int OrdinalDistance(string A, string B)
{
	local int ia, ib;

	ia = FindDifficultyOrderIndex(A);
	ib = FindDifficultyOrderIndex(B);
	if( ia == -1 || ib == -1 )
		return -1;
	return Abs(ia-ib);
}

// How many GameConfig entries (across ALL difficulties) share this mode
// family. A family of 1 means this mode has no sibling at any other
// difficulty, so it should stay visible no matter what's selected in
// co_Difficulty rather than disappearing.
final function int FamilyCount(string Group)
{
	local int i, C;

	for( i=0; i<MVRI.GameConfig.Length; i++ )
		if( DeriveModeGroup(MVRI.GameConfig[i].GameName) ~= Group )
			C++;
	return C;
}

// Rebuilds co_GameType's item list to only the entries that belong at
// Difficulty (plus anything opted out of filtering - no recognized
// trailing difficulty word, or a mode family of one). Tries to keep
// PreviousIdx selected if it's still in the filtered list; otherwise, if
// PreferredGroup is known, falls back to the closest available difficulty
// within that same mode family (nearest first, ties broken toward the
// easier/lower tier); otherwise just selects whatever ends up first in
// the filtered list.
// Returns the GameConfig index that ends up selected, or -1 if the list
// came up empty (shouldn't normally happen - every mode is either matched
// or exempted from filtering).
final function int RebuildGameTypeList(string Difficulty, string PreferredGroup, int PreviousIdx)
{
	local array<int> VisibleIndices;
	local int i, d, BestIdx, BestDist, BestOrderIdx, Dist, CandOrderIdx;
	local bool bMatchesFilter;
	local string EntryDifficulty;

	co_GameType.MyComboBox.List.Clear();

	// Loop runs i=0..GameConfig.Length-1 in index order, and GameConfig's
	// index order already IS the final display order the server intends -
	// KFVotingHandler.BuildGameConfig() sorts entries by SortOrder (see
	// ShouldSortBefore()) before ever copying them into GameConfig. So the
	// items land in co_GameType's list, via AddItem() below, in exactly
	// that order for free - nothing else to do here.
	for( i=0; i<MVRI.GameConfig.Length; i++ )
	{
		EntryDifficulty = DeriveDifficulty(MVRI.GameConfig[i].GameName);
		bMatchesFilter = ( EntryDifficulty=="" )
			|| ( EntryDifficulty~=Difficulty )
			|| ( FamilyCount(DeriveModeGroup(MVRI.GameConfig[i].GameName))==1 );

		if( bMatchesFilter )
		{
			co_GameType.AddItem(MVRI.GameConfig[i].GameName, none, string(i));
			VisibleIndices[VisibleIndices.Length] = i;
		}
	}
	// Deliberately NOT calling co_GameType.MyComboBox.List.SortList() here
	// (the base class's own InternalOnOpen() does call it, on its own
	// initial population of co_GameType - harmless, since this function
	// unconditionally rebuilds and replaces that population immediately
	// afterward on every menu open). SortList() is exactly what was
	// silently re-alphabetizing this list regardless of SortOrder before -
	// see KFVotingHandler.BuildGameConfig()'s ShouldSortBefore() comments.

	// Prefer keeping the exact same mode selected, if it survived the filter.
	d = co_GameType.MyComboBox.List.FindExtra(string(PreviousIdx));
	if( d > -1 )
	{
		co_GameType.SetIndex(d);
		return PreviousIdx;
	}

	// Otherwise, find the closest available difficulty within the same
	// mode family.
	BestIdx = -1;
	BestDist = 9999;
	BestOrderIdx = 9999;
	if( PreferredGroup != "" )
	{
		for( i=0; i<VisibleIndices.Length; i++ )
		{
			if( DeriveModeGroup(MVRI.GameConfig[VisibleIndices[i]].GameName) ~= PreferredGroup )
			{
				EntryDifficulty = DeriveDifficulty(MVRI.GameConfig[VisibleIndices[i]].GameName);
				Dist = OrdinalDistance(Difficulty, EntryDifficulty);
				if( Dist == -1 )
					continue;
				CandOrderIdx = FindDifficultyOrderIndex(EntryDifficulty);
				if( Dist < BestDist || (Dist == BestDist && CandOrderIdx < BestOrderIdx) )
				{
					BestDist = Dist;
					BestOrderIdx = CandOrderIdx;
					BestIdx = VisibleIndices[i];
				}
			}
		}
	}

	if( BestIdx == -1 && VisibleIndices.Length > 0 )
		BestIdx = VisibleIndices[0]; // last resort - just pick something so nothing is left unselected

	if( BestIdx > -1 )
	{
		d = co_GameType.MyComboBox.List.FindExtra(string(BestIdx));
		if( d > -1 )
			co_GameType.SetIndex(d);
	}
	return BestIdx;
}

function OnDifficultyChanged(GUIComponent Sender)
{
	local string NewDifficulty, PreferredGroup;
	local int PreviousIdx, ResolvedIdx;

	NewDifficulty = co_Difficulty.GetExtra();
	if( NewDifficulty == "" || NewDifficulty == CurrentDifficulty )
		return;

	PreviousIdx = CurrentGameConfig();
	if( PreviousIdx > -1 && PreviousIdx < MVRI.GameConfig.Length )
		PreferredGroup = DeriveModeGroup(MVRI.GameConfig[PreviousIdx].GameName);

	CurrentDifficulty = NewDifficulty;

	ResolvedIdx = RebuildGameTypeList(NewDifficulty, PreferredGroup, PreviousIdx);

	if( ResolvedIdx > -1 )
	{
		// Selection changed programmatically - SetIndex() doesn't fire
		// OnChange on its own (matches the base class's own InternalOnOpen,
		// which calls co_GameType.SetIndex() directly without expecting
		// GameTypeChanged to fire from it) - so drive the map list refresh
		// the same way a manual dropdown click would.
		GameTypeChanged(co_GameType);
	}
}

function bool AlignBK(Canvas C)
{

	if (lb_VoteCountListbox.MyList != none) {
		i_MapCountListBackground.WinWidth  = lb_VoteCountListbox.MyList.ActualWidth();
		i_MapCountListBackground.WinHeight = lb_VoteCountListbox.MyList.ActualHeight();
		i_MapCountListBackground.WinLeft   = lb_VoteCountListbox.MyList.ActualLeft();
		i_MapCountListBackground.WinTop    = lb_VoteCountListbox.MyList.ActualTop();
	}

	if (lb_MapListBox.MyList != none) {
		i_MapListBackground.WinWidth  	= lb_MapListBox.MyList.ActualWidth();
		i_MapListBackground.WinHeight 	= lb_MapListBox.MyList.ActualHeight();
		i_MapListBackground.WinLeft  	= lb_MapListBox.MyList.ActualLeft();
		i_MapListBackground.WinTop	 	= lb_MapListBox.MyList.ActualTop();
	}

	return false;
}

DefaultProperties
{
	OnKeyEvent=InternalOnKeyEvent
	strHelp=". TeamSay|/ Console command|+ Like the current map|- Dislike the current map| "

	DifficultyOrder(0)="Hard"
	DifficultyOrder(1)="Suicidal"
	DifficultyOrder(2)="Hell on Earth"
	DifficultyOrder(3)="Brutal"

	Begin Object Class=MVCountColumnListBox Name=VoteCountListBox
		TabOrder=0
		WinLeft=0.02
		WinWidth=0.96
		WinTop=0.05
		WinHeight=0.22
		bVisibleWhenEmpty=true
		bScaleToParent=True
		bBoundToParent=True
		FontScale=Font_Medium
		HeaderColumnPerc(0)=0.3
		HeaderColumnPerc(1)=0.3
		HeaderColumnPerc(2)=0.2
		HeaderColumnPerc(3)=0.2
	End Object
	lb_VoteCountListBox=VoteCountListBox

	Begin Object class=moComboBox Name=GameTypeCombo
		TabOrder=1
		WinLeft=0.02
		WinWidth=0.32
		WinTop=0.275
		WinHeight=0.0375
		Caption="F4 Mode:"
		CaptionWidth=0.28
		bScaleToParent=True
		bBoundToParent=True
		bReadOnly=True
		OnKeyEvent=OnGameTypeKey
	End Object
	co_GameType=GameTypeCombo

	Begin Object class=moComboBox Name=DifficultyCombo
		TabOrder=2
		WinLeft=0.35
		WinWidth=0.20
		WinTop=0.275
		WinHeight=0.0375
		Caption="Diff:"
		CaptionWidth=0.28
		bScaleToParent=True
		bBoundToParent=True
		bReadOnly=True
		OnChange=OnDifficultyChanged
	End Object
	co_Difficulty=DifficultyCombo

	Begin Object Class=moEditBox Name=SearchEditbox
		TabOrder=3
		WinLeft=0.57
		WinWidth=0.41
		WinTop=0.275
		WinHeight=0.0375
		Caption="F3 Search:"
		CaptionWidth=0.32
		bScaleToParent=True
		bBoundToParent=True
		OnChange=OnSearchChange
		OnKeyEvent=OnSearchKey
		OnKeyType=OnSearchKeyType
	End Object
	SearchEdit=SearchEditbox

	// Occupies the row the search box used to sit alone on, now that
	// search shares the row above with the mode/difficulty combos - see
	// UpdateDescriptionLabel().
	Begin Object Class=GUILabel Name=DescriptionLabel
		Caption=""
		TextAlign=TXTA_Left
		TextColor=(B=255,G=255,R=255)
		TextFont="UT2ServerListFont"
		bTransparent=False
		bMultiLine=True
		WinLeft=0.02
		WinWidth=0.96
		WinTop=0.315
		WinHeight=0.0375
		bScaleToParent=True
		bBoundToParent=True
	End Object
	lbl_Description=DescriptionLabel

	Begin Object Class=MVMultiColumnListBox Name=MapListBox
		TabOrder=4
		WinLeft=0.02
		WinWidth=0.96
		WinTop=0.37
		WinHeight=0.33
		bVisibleWhenEmpty=true
		StyleName="ServerBrowserGrid"
		bScaleToParent=True
		bBoundToParent=True
		FontScale=Font_Medium
		HeaderColumnPerc(0)=0.5
		HeaderColumnPerc(1)=0.15
		HeaderColumnPerc(2)=0.15
		HeaderColumnPerc(3)=0.2
	End Object
	lb_MapListBox=MapListBox

	Begin Object Class=GUIImage Name=MapListBackground
		Image=Texture'KF_InterfaceArt_tex.Menu.Thin_border_SlightTransparent'
		ImageStyle=ISTY_Stretched
		OnDraw=AlignBK
	End Object
	i_MapListBackground=MapListBackground

	Begin Object Class=KFMapVoteFooterX Name=ChatFooter
		WinTop=0.705
		WinLeft=0.02
		WinWidth=0.96
		WinHeight=0.275
		TabOrder=10
	End Object
	f_Chat=ChatFooter
}