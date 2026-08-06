//-----------------------------------------------------------
// KFMapVotingPageX - Modification by Marco
//-----------------------------------------------------------
class KFMapVotingPageX extends ROMapVotingPage;

var automated moEditBox SearchEdit;
var automated moComboBox co_Difficulty;
var localized string strHelp;

// Tracks the difficulty currently selected in co_Difficulty, so
// OnDifficultyChanged() can tell whether a change actually happened and
// so we always know what to compare candidate modes' distance against.
var string CurrentDifficulty;

function InternalOnOpen()
{
	local KFVotingReplicationInfo KVRI;

	super.InternalOnOpen();

	if (!bHasFocus) {
		// fixes PreDraw errors
		lb_MapListBox.SetVisibility(false);
		lb_VoteCountListBox.SetVisibility(false);
		return;
	}

	lb_MapListBox.SetVisibility(true);
	lb_VoteCountListBox.SetVisibility(true);

	// MVRI's declared type (from the base engine VotingPage class, an
	// ancestor we don't have source for) is plain VotingReplicationInfo,
	// which knows nothing about GameDifficulty/GameModeGroup/DifficultyOrder
	// - those only exist on our KFVotingReplicationInfo subclass. MVRI is
	// always actually a KFVotingReplicationInfo instance at runtime
	// (KFVotingHandler.AddMapVoteReplicationInfo only ever spawns that
	// class), so this cast just satisfies the compiler - same downcast
	// pattern already used elsewhere in this file (see OnSearchChange's
	// MVMultiColumnList(lb_MapListBox.List)).
	KVRI = KFVotingReplicationInfo(MVRI);

	// KVRI can be none (or still mid-replication) if super.InternalOnOpen()
	// bailed out to one of its "disabled"/"still loading" question pages -
	// don't touch difficulty filtering in that case, there's nothing to filter.
	if( KVRI != none && KVRI.bMapVote
		&& KVRI.GameDifficulty.Length == KVRI.GameConfig.Length
		&& KVRI.GameModeGroup.Length == KVRI.GameConfig.Length )
	{
		BuildDifficultyList();

		// Default to whatever difficulty the currently-selected mode (the
		// server's live game type, per the base class's own selection
		// logic above) actually is, so the vote screen opens already
		// filtered to what's live right now instead of showing everything.
		CurrentDifficulty = "";
		if( CurrentGameConfig() > -1 && CurrentGameConfig() < KVRI.GameDifficulty.Length )
			CurrentDifficulty = KVRI.GameDifficulty[CurrentGameConfig()];

		if( CurrentDifficulty != "" )
		{
			SelectDifficultyItem(CurrentDifficulty);
			RebuildGameTypeList(CurrentDifficulty, "", CurrentGameConfig());
		}
	}

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
// ------------------------------------------------------------------

// Populates co_Difficulty with every distinct, non-blank value found in
// GameDifficulty, ordered per DifficultyOrder first, then any leftover
// values (not listed in DifficultyOrder) appended alphabetically.
// Deliberately never calls List.SortList() on this combo - that's what
// silently re-alphabetizes co_GameType regardless of GameConfig's own
// SortOrder (see KFVotingHandler.BuildGameConfig()'s comments) - here we
// want our own explicit order to actually stick.
final function BuildDifficultyList()
{
	local KFVotingReplicationInfo KVRI;
	local array<string> Distinct, Leftover;
	local int i, j;
	local bool bFound;
	local string D;

	KVRI = KFVotingReplicationInfo(MVRI);
	if( KVRI == none )
		return;

	for( i=0; i<KVRI.GameDifficulty.Length; i++ )
	{
		D = KVRI.GameDifficulty[i];
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
	for( i=0; i<KVRI.DifficultyOrder.Length; i++ )
	{
		for( j=0; j<Distinct.Length; j++ )
		{
			if( Distinct[j] ~= KVRI.DifficultyOrder[i] )
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
// there (e.g. a Difficulty value someone forgot to add to the order list -
// it still shows in the dropdown, appended alphabetically, but it has no
// defined ordinal position for "closest available" purposes).
final function int FindDifficultyOrderIndex(string D)
{
	local KFVotingReplicationInfo KVRI;
	local int i;

	KVRI = KFVotingReplicationInfo(MVRI);
	if( KVRI == none )
		return -1;

	for( i=0; i<KVRI.DifficultyOrder.Length; i++ )
		if( KVRI.DifficultyOrder[i] ~= D )
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
	local KFVotingReplicationInfo KVRI;
	local int i, C;

	KVRI = KFVotingReplicationInfo(MVRI);
	if( KVRI == none )
		return 0;

	for( i=0; i<KVRI.GameModeGroup.Length; i++ )
		if( KVRI.GameModeGroup[i] ~= Group )
			C++;
	return C;
}

// Rebuilds co_GameType's item list to only the entries that belong at
// Difficulty (plus anything opted out of filtering - blank Difficulty, or
// a mode family of one). Tries to keep PreviousIdx selected if it's still
// in the filtered list; otherwise, if PreferredGroup is known, falls back
// to the closest available difficulty within that same mode family
// (nearest first, ties broken toward the easier/lower tier); otherwise
// just selects whatever ends up first in the filtered list.
// Returns the GameConfig index that ends up selected, or -1 if the list
// came up empty (shouldn't normally happen - every mode is either matched
// or exempted from filtering).
final function int RebuildGameTypeList(string Difficulty, string PreferredGroup, int PreviousIdx)
{
	local KFVotingReplicationInfo KVRI;
	local array<int> VisibleIndices;
	local int i, d, BestIdx, BestDist, BestOrderIdx, Dist, CandOrderIdx;
	local bool bMatchesFilter;

	KVRI = KFVotingReplicationInfo(MVRI);
	if( KVRI == none )
		return -1;

	co_GameType.MyComboBox.List.Clear();

	// NOTE: MVRI.GameConfig (used below via KVRI, same array either way) is
	// declared on the base engine VotingReplicationInfo class, so it works
	// through the plain MVRI reference too - only GameDifficulty and
	// GameModeGroup, added on our KFVotingReplicationInfo subclass, need
	// the downcast.
	for( i=0; i<KVRI.GameConfig.Length; i++ )
	{
		bMatchesFilter = ( KVRI.GameDifficulty[i]=="" )
			|| ( KVRI.GameDifficulty[i]~=Difficulty )
			|| ( FamilyCount(KVRI.GameModeGroup[i])==1 );

		if( bMatchesFilter )
		{
			co_GameType.AddItem(KVRI.GameConfig[i].GameName, none, string(i));
			VisibleIndices[VisibleIndices.Length] = i;
		}
	}
	// Existing display-order limitation (not something this change
	// addresses): this re-alphabetizes the filtered list the same way the
	// base class does for the unfiltered one - see BuildGameConfig()'s and
	// BuildDifficultyList()'s comments. Drop this line later if/when
	// SortOrder's client-side display bug gets fixed.
	co_GameType.MyComboBox.List.SortList();

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
			if( KVRI.GameModeGroup[VisibleIndices[i]] ~= PreferredGroup )
			{
				Dist = OrdinalDistance(Difficulty, KVRI.GameDifficulty[VisibleIndices[i]]);
				if( Dist == -1 )
					continue;
				CandOrderIdx = FindDifficultyOrderIndex(KVRI.GameDifficulty[VisibleIndices[i]]);
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
	local KFVotingReplicationInfo KVRI;
	local string NewDifficulty, PreferredGroup;
	local int PreviousIdx, ResolvedIdx;

	NewDifficulty = co_Difficulty.GetExtra();
	if( NewDifficulty == "" || NewDifficulty == CurrentDifficulty )
		return;

	KVRI = KFVotingReplicationInfo(MVRI);
	if( KVRI == none )
		return;

	PreviousIdx = CurrentGameConfig();
	if( PreviousIdx > -1 && PreviousIdx < KVRI.GameModeGroup.Length )
		PreferredGroup = KVRI.GameModeGroup[PreviousIdx];

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
		WinLeft=0.20
		WinWidth=0.36
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
		WinLeft=0.58
		WinWidth=0.22
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
		WinLeft=0.20
		WinWidth=0.60
		WinTop=0.315
		WinHeight=0.0375
		Caption="F3 Map Search:"
		CaptionWidth=0.35
		bScaleToParent=True
		bBoundToParent=True
		OnChange=OnSearchChange
		OnKeyEvent=OnSearchKey
		OnKeyType=OnSearchKeyType
	End Object
	SearchEdit=SearchEditbox

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