// ====================================================================
//  Modified by Marco
// ====================================================================
class MVMultiColumnList extends MapVoteMultiColumnList;

var array<int> UnfilteredData;
var string OldFilter;
var eFontScale MyFontScale;  // soomebody is messing up with the self.FontScale

// W/S/Up/Down held-repeat state - see InternalOnKeyEvent()/Timer() below.
// RepeatNavKey is only meaningful while bRepeatNavActive is true.
var bool bRepeatNavActive;
var Interactions.EInputKey RepeatNavKey;
var float RepeatNavInitialDelay;
var float RepeatNavInterval;

// Must match KFVotingHandler.RANDOM_MAP_NAME exactly (server-side source of
// truth) - duplicated here since no shared base class conveniently spans
// client and server; same duplication convention this file already uses for
// Prefix/SkipList/MapListStyle filtering logic (server-side counterpart:
// KFVotingHandler.IsMapValidForGameConfig()).
const RANDOM_MAP_NAME = "RANDOM MAP";


function InitComponent(GUIController MyController, GUIComponent MyOwner)
{
	Super.InitComponent(MyController, MyOwner);
	ScaleToResolution(MyController.ResX, MyController.ResY);
}

function ResolutionChanged(int ResX, int ResY)
{
	ScaleToResolution(ResX, ResY);
	Super.ResolutionChanged(ResX,ResY);
}

function ScaleToResolution(int ResX, int ResY)
{
	if (ResY < 1000) {
		MyFontScale = FNS_Small;
	}
	else {
		MyFontScale = FNS_Medium;
	}
}

// Manual linear scan against a comma-split Allow/Exclude list - dynamic
// array .Find() isn't available in this SDK (confirmed elsewhere in this
// package, e.g. GenerateMapPreviewsCommandlet.IsMapExcluded()).
function bool IsMapInList(string MapName, array<string> List)
{
	local int i;

	for( i=0; i<List.Length; i++ )
		if( List[i] ~= MapName )
			return true;
	return false;
}

function LoadList(VotingReplicationInfo LoadVRI, int GameTypeIndex)
{
	local int m,p,l;
	local array<string> PrefixList,SkipList,ModeMapList;
	local string A,B,MP,MapListStyle;
	local KFVotingReplicationInfo KFVRI;

	// Suppresses OnChange (NotifySelectionChanged, see below) while
	// AddedItem() bulk-populates this list - GUIListBase.bInitializeList
	// ("set index to 0 when adding first item") can silently auto-select
	// during this loop and fire a premature selection-change notification
	// before PageOwner is even valid yet (this object isn't attached to the
	// component tree until after LoadList() returns - see
	// MVMultiColumnListBox.LoadList()). bNotify is the engine's own native
	// suppression mechanism (already used internally by SilentSetIndex()),
	// reused here rather than inventing a new flag.
	bNotify = False;

	VRI = LoadVRI;
	KFVRI = KFVotingReplicationInfo(VRI); // base VotingReplicationInfo doesn't expose the MapListStyle/Value mirrors below

	A = VRI.GameConfig[GameTypeIndex].Prefix;
	if( Divide(A,"|",A,B) )
		Split(B, ",", SkipList);
	Split(A, ",", PrefixList);

	MapListStyle = "All";
	if( KFVRI != none && GameTypeIndex < KFVRI.GameConfigMapListStyle.Length )
	{
		MapListStyle = KFVRI.GameConfigMapListStyle[GameTypeIndex];
		if( MapListStyle != "All" && GameTypeIndex < KFVRI.GameConfigMapListValue.Length )
			Split(KFVRI.GameConfigMapListValue[GameTypeIndex], ",", ModeMapList);
	}

	// "RANDOM MAP" (see KFVotingHandler.AddRandomMapSentinel()) is force-
	// included first in every mode's list, ignoring Prefix/MapListStyle
	// entirely - it deliberately never matches any real mode's Prefix list,
	// so the ordinary matching loop below would otherwise never include it.
	for( m=0; m<VRI.MapList.Length; m++ )
	{
		if( RANDOM_MAP_NAME ~= VRI.MapList[m].MapName )
		{
			UnfilteredData.Insert(0,1);
			UnfilteredData[0] = m;
			AddedItem();
			break;
		}
	}

	for( m=0; m<VRI.MapList.Length; m++)
	{
		MP = VRI.MapList[m].MapName;
		for( p=0; p<PreFixList.Length; p++)
		{
			if( left(MP, len(PrefixList[p])) ~= PrefixList[p] )
			{
				for( l=(SkipList.Length-1); l>=0; --l )
					if( left(MP, len(SkipList[l])) ~= SkipList[l] )
						break;
				if( l!=-1 )
					continue;

				if( MapListStyle != "All" )
				{
					if( MapListStyle ~= "Allow" && !IsMapInList(MP, ModeMapList) )
						continue;
					if( MapListStyle ~= "Exclude" && IsMapInList(MP, ModeMapList) )
						continue;
				}

				l = UnfilteredData.Length;
				UnfilteredData.Insert(l,1);
				UnfilteredData[l] = m;
				AddedItem();
				break;
			}
		} // p
	} // m
	MapVoteData = UnfilteredData;
	OldFilter = "";
	OnDrawItem  = DrawItem;
	bNotify = True;
}

// Fires on every real selection-change reason - mouse click (via
// GUIVertList's own InternalOnClick), keyboard Up/Down/Home/End/PgUp/PgDn
// (via GUIListBase's inherited InternalOnKeyEvent), our own new W/S
// handling below, and ApplyFilter()'s own Home() call - since all of them
// ultimately call SetIndex(), which always fires OnChange. Bound via
// defaultproperties (OnChange=NotifySelectionChanged) rather than a one-time
// runtime List.OnChange=... assignment in the page, since
// MVMultiColumnListBox.LoadList() constructs a brand NEW MVMultiColumnList
// instance per game mode (new class'MVMultiColumnList') on every mode
// switch - only a defaultproperties binding applies automatically to every
// one of those. PageOwner (not MenuOwner - that resolves to the ListBox
// wrapper one level up from here) is the accessor that reaches the actual
// GUIPage from a component at this nesting depth.
function NotifySelectionChanged(GUIComponent Sender)
{
	if( KFMapVotingPageX(PageOwner) != none )
		KFMapVotingPageX(PageOwner).UpdateMapPreviewForSelection(self);
}

// Steps one item in NavKey's direction. IK_Down's !Controller.ShiftPressed
// guard mirrors GUIListBase's own "case IK_Down" (Shift+Down is reserved
// elsewhere in the engine for multi-select range-extension) - applied to
// IK_S too for consistency, even though this list is single-select in
// practice, rather than silently dropping the guard for the new key.
final function bool StepNav(Interactions.EInputKey NavKey)
{
	if( NavKey == IK_W || NavKey == IK_Up )
		return Up();
	if( (NavKey == IK_S || NavKey == IK_Down) && !Controller.ShiftPressed )
		return Down();
	return false;
}

// W/S mirror the existing Up/Down arrow-key navigation - deliberately W/S
// only, per design decision: A/D are left unbound since this list type has
// no meaningful Left/Right behavior. Arrow-key Up/Down are now handled
// directly here too (via StepNav() above), rather than deferred to
// GUIListBase's own IK_Up/IK_Down case, so both old and new keys get
// identical repeat-scroll behavior below.
//
// A press steps one item immediately (preserves the existing snappy
// single-press feel), then - if the SAME key is still held past
// RepeatNavInitialDelay - a controlled continuous auto-scroll engages at
// RepeatNavInterval (~0.15s/item by default, covers a ~200-map list in
// about 30 seconds), driven by this component's own native
// SetTimer()/Timer() rather than by however many discrete IST_Press events
// the OS's own keyboard auto-repeat happens to redeliver while held - that
// native repeat timing/delivery isn't something this SDK's UI code ever
// relies on anywhere (confirmed nowhere in this package or the reference
// SDK checks for IST_Hold in an OnKeyEvent handler), so betting the exact
// requested pacing on it would be exactly the kind of unverified native-
// behavior assumption this project's history has repeatedly warned
// against. A repeated Press for a key already being tracked as held is
// therefore treated as (possible) OS auto-repeat noise and ignored, so it
// can't keep restarting RepeatNavInitialDelay and starve the controlled
// continuous rate from ever engaging. This component's own SetTimer/
// KillTimer is already implicitly relied on for this exact class by the
// engine itself - MapVoteMultiColumnListBox.InitBaseList() explicitly
// calls List.SetTimer(0.0, False) before swapping a List out on a
// game-type change, precisely so a still-pending timer like this one
// doesn't fire against an abandoned list.
//
// SetTimer() is called ONCE here, as a genuinely repeating timer
// (bRepeat=true) starting at RepeatNavInitialDelay - not as a one-shot
// re-armed by calling SetTimer() again from inside Timer() itself (an
// earlier version of this feature did that and stopped dead after only two
// steps: no class anywhere in this package or the reference SDK calls
// SetTimer() a second time from inside its own Timer() event, which is a
// strong sign that pattern silently doesn't work here). Timer() instead
// speeds the ALREADY-running repeat up to RepeatNavInterval by directly
// reassigning the inherited TimerInterval field (GUIComponent.uc) once the
// first tick has fired - the actual confirmed-working way to change an
// in-progress repeating timer's pace on this class, per GUIScrollText.uc's
// own identical use of the same field (TimerInterval = CharDelay;) to vary
// its own per-character reveal speed mid-repeat.
//
// Falls through to Super for every other key (Left/Right/Home/End/PgUp/
// PgDn/MouseWheel/Ctrl+A), so nothing else is affected. Because this is a
// scoped per-component key-event delegate (not global input), it
// structurally never fires while SearchEdit/f_Chat.ed_Chat have focus -
// they have their own independently-wired OnKeyEvent delegates.
function bool InternalOnKeyEvent(out byte Key, out byte KeyState, float Delta)
{
	local Interactions.EInputKey iKey;

	iKey = EInputKey(Key);

	if( iKey == IK_W || iKey == IK_S || iKey == IK_Up || iKey == IK_Down )
	{
		if( KeyState == 1 )   // IST_Press
		{
			if( bRepeatNavActive && iKey == RepeatNavKey )
				return true; // likely OS auto-repeat for a key we're already driving - ignore

			StepNav(iKey);
			bRepeatNavActive = true;
			RepeatNavKey = iKey;
			SetTimer(RepeatNavInitialDelay, true);
			return true;
		}
		if( KeyState == 3 && iKey == RepeatNavKey ) // IST_Release
		{
			bRepeatNavActive = false;
			KillTimer();
			return false;
		}
	}

	return Super.InternalOnKeyEvent(Key, KeyState, Delta);
}

// Drives the continuous-scroll phase of the W/S/Up/Down repeat described
// above. The timer itself is already repeating (armed with bRepeat=true in
// InternalOnKeyEvent()) - this only needs to step once per firing and, the
// first time it fires, slow the repeat down from RepeatNavInitialDelay to
// the steady-state RepeatNavInterval by reassigning TimerInterval directly
// (see InternalOnKeyEvent()'s comment for why that's used instead of a
// second SetTimer() call). Reassigning TimerInterval to the same value on
// every subsequent firing is harmless. Falls back to the inherited default
// (OnTimer delegate) if this timer ever fires while a repeat isn't
// actually active - shouldn't happen given KillTimer() is called on
// release, but avoids silently swallowing GUIComponent's own Timer()/
// OnTimer mechanism if it's ever used for something else on this class in
// the future.
event Timer()
{
	if( bRepeatNavActive )
	{
		StepNav(RepeatNavKey);
		TimerInterval = RepeatNavInterval;
		return;
	}
	Super.Timer();
}

// Forces Index to the actually-right-clicked row before the context menu
// can act on it, regardless of whether the native right-click event
// dispatches to this List directly or to the owning ListBox wrapper - see
// KFMapVotingPageX.SendAdminSwitch()/SendVote() for the "always resolves to
// map 0" bug this fixes. MapVoteMultiColumnListBox's own
// InternalOnRightClick (bound at the WRAPPER level, XVoting/Classes/
// MapVoteMultiColumnListBox.uc) already does this same sync, but
// MapVotingPage.InternalOnOpen() has to manually wire
// lb_MapListBox.List.OnClick = MapListClick for ordinary left-clicks to
// work at all - proving raw mouse events dispatch to this List component
// directly, not to the wrapper - so right-clicks most likely do too, in
// which case the wrapper's own override never runs and Index is left
// wherever bInitializeList seeded it (0), matching the reported symptom
// exactly. This override makes the sync happen here too, so the fix
// doesn't depend on resolving that ambiguity. Calls Super first to
// preserve GUIListBase's own drag-cancel behavior
// (Controller.bIgnoreNextRelease) - this list IS a real bDropSource
// (MapVotingPage.uc sets lb_MapListBox.List.bDropSource = True).
function bool InternalOnRightClick(GUIComponent Sender)
{
	local int NewIndex;

	Super.InternalOnRightClick(Sender);

	NewIndex = Top + ( (Controller.MouseY - ClientBounds[1]) / ItemHeight );
	if( NewIndex >= ItemCount )
		NewIndex = ItemCount - 1;
	SetIndex(NewIndex);

	log("STVoteDiag: MVMultiColumnList.InternalOnRightClick fired NewIndex="$NewIndex
		$" Top="$Top$" ItemHeight="$ItemHeight$" ItemCount="$ItemCount,'STVoteDiag');

	return true;
}

function ApplyFilter(string filter)
{
	local int i, j;

	if (len(filter) < 2 && OldFilter == "") {
		// require at least 2 letter to start filtering
		return;
	}

	filter = caps(filter);
	if (filter == OldFilter)
		return;

	// Since the developers were too retarded to use ItemCount from native code,
	// we cannot simply call Clear(), we need to call AddedItem/UpdatedItem/RemovedItem for each entry instead
	for (i = 0; i < UnfilteredData.Length; ++i) {
		if (filter == "" || InStr(caps(VRI.MapList[UnfilteredData[i]].MapName), filter) >= 0) {
			if (j < MapVoteData.length) {
				MapVoteData[j] = UnfilteredData[i];
				UpdatedItem(j);
			}
			else {
				MapVoteData[j] = UnfilteredData[i];
				AddedItem(j);
			}
			++j;
		}
	}
	for (i = MapVoteData.Length - 1; i >= j; --i) {
		MapVoteData.remove(i, 1);
		RemovedItem(i);
	}
	OldFilter = filter;
	Home();
	log("Map Filter: '"$filter$"'. Filtered map count: " $ MapVoteData.length);
	// Dump();
}

function Home()
{
	if (ItemCount < 1) return;

	SetIndex(0);
	if ( MyScrollBar != None )
		MyScrollBar.AlignThumb();
}

function float MyItemHeight(Canvas c)
{
	local float XL, YL;

	SelectedStyle.TextSize(C, MSAT_Blurry, "XXX,", XL, YL, MyFontScale);
	return YL + 2;
}

function DrawItem(Canvas Canvas, int i, float X, float Y, float W, float H, bool bSelected, bool bPending)
{
	local float CellLeft, CellWidth;
	local eMenuState MState;
	local GUIStyles DrawStyle;
	local string MapName;

	if (VRI == none)
		return;

	// Draw the selection border
	MapName = VRI.MapList[MapVoteData[SortData[i].SortItem]].MapName;
	if ( bSelected) {
		SelectedStyle.Draw(Canvas, MenuState, X, Y-1, W, H+2 );
		DrawStyle = SelectedStyle;
		MapName = "> " $ MapName;
		MState = MSAT_Focused;
	}
	else {
		DrawStyle = Style;
		MState = MenuState;
	}

	if (!VRI.MapList[MapVoteData[SortData[i].SortItem]].bEnabled) {
		MState = MSAT_Disabled;
	}

	// "RANDOM MAP" renders in yellow - applied here, at draw time only, never
	// baked into the stored/replicated MapName field itself (which
	// ApplyFilter()'s search, GetSortString(), and the server's own
	// Prefix/tie-break matching all read raw and would break if it carried
	// escape bytes). Same color-escape convention already established in
	// KFVotingReplicationInfo.InitRepStr() for the Rating column
	// (Chr(0x1B)$Chr(R)$Chr(G)$Chr(1)$text) - R=255/G=255 never trips that
	// file's "avoid byte 0/10" guard, so the blue byte is safely hardcoded
	// to Chr(1) matching its existing convention.
	if( VRI.MapList[MapVoteData[SortData[i].SortItem]].MapName ~= RANDOM_MAP_NAME )
		MapName = Chr(0x1B)$Chr(255)$Chr(255)$Chr(1)$MapName;

	GetCellLeftWidth(0, CellLeft, CellWidth);
	DrawStyle.DrawText(Canvas, MState, CellLeft, Y, CellWidth, H, TXTA_Left,
		MapName, MyFontScale);

	GetCellLeftWidth( 1, CellLeft, CellWidth );
	DrawStyle.DrawText(Canvas, MState, CellLeft, Y, CellWidth, H, TXTA_Left,
		string(VRI.MapList[MapVoteData[SortData[i].SortItem]].PlayCount), MyFontScale);

	GetCellLeftWidth( 2, CellLeft, CellWidth );
	DrawStyle.DrawText(Canvas, MState, CellLeft, Y, CellWidth, H, TXTA_Left,
		string(VRI.MapList[MapVoteData[SortData[i].SortItem]].Sequence), MyFontScale);

	GetCellLeftWidth( 3, CellLeft, CellWidth );
	DrawStyle.DrawText(Canvas, MState, CellLeft, Y, CellWidth, H, TXTA_Left,
		KFVotingReplicationInfo(VRI).RepArray[MapVoteData[SortData[i].SortItem]], MyFontScale);
}

function string GetSortString( int i )
{
	local string ColumnData[5];

	if (i >= MapVoteData.Length)
		return "";

	// "RANDOM MAP" gets a fixed low-sorting Name-column key ("1" sorts before
	// any real map's "KF-..." name) so it floats back to the top for free
	// whenever a player sorts by Name ascending, without needing to
	// intercept the native sort mechanism. Descending Name-sort and sorting
	// by the other columns are accepted v1 gaps - no pinned-row concept
	// exists in this list, only this cheap sort-key trick.
	if( VRI.MapList[MapVoteData[i]].MapName ~= RANDOM_MAP_NAME )
		ColumnData[0] = "1";
	else
		ColumnData[0] = Left(Caps(VRI.MapList[MapVoteData[i]].MapName),20);
	ColumnData[1] = Right("000000" $ VRI.MapList[MapVoteData[i]].PlayCount,6);
	ColumnData[2] = Right("000000" $ VRI.MapList[MapVoteData[i]].Sequence,6);
	ColumnData[3] = KFVotingReplicationInfo(VRI).SortedArray[MapVoteData[i]];

	return ColumnData[SortColumn] $ ColumnData[PrevSortColumn];
}


defaultproperties
{
	ColumnHeadings(3)="Rating"

	InitColumnPerc(0)=0.5
	InitColumnPerc(1)=0.15
	InitColumnPerc(2)=0.15
	InitColumnPerc(3)=0.2

	ColumnHeadingHints(3)="User rating for the maps."

	GetItemHeight=MyItemHeight
	OnChange=NotifySelectionChanged
	MyFontScale=FNS_Medium
	FontScale=FNS_Medium

	// ~0.15s/item covers a ~200-map list in about 30 seconds.
	RepeatNavInitialDelay=0.25
	RepeatNavInterval=0.15
}
