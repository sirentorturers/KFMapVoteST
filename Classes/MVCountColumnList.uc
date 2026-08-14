// ====================================================================
//  Modified by Marco
// ====================================================================
class MVCountColumnList extends MapVoteCountMultiColumnList;

var eFontScale MyFontScale;  // soomebody is messing up with the self.FontScale

// Must match KFVotingHandler.RANDOM_MAP_NAME exactly (server-side source of
// truth) - duplicated here (and in MVMultiColumnList.uc) since no shared
// base class conveniently spans client and server.
const RANDOM_MAP_NAME = "RANDOM MAP";

// W/S/Up/Down held-repeat state - see InternalOnKeyEvent()/Timer() below.
// RepeatNavKey is only meaningful while bRepeatNavActive is true.
var bool bRepeatNavActive;
var Interactions.EInputKey RepeatNavKey;
var float RepeatNavInitialDelay;
var float RepeatNavInterval;


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

function float MyItemHeight(Canvas c)
{
	local float XL, YL;

	SelectedStyle.TextSize(C, MSAT_Blurry, "XXX,", XL, YL, MyFontScale);
	return YL + 2;
}

// Thin wrapper purely to bracket the inherited MapVoteCountMultiColumnList.
// LoadList()'s bulk population with the same bNotify suppression
// MVMultiColumnList.LoadList() uses - see that file's comment for why
// (GUIListBase.bInitializeList can auto-select and fire a premature
// NotifySelectionChanged() before this object is attached to the component
// tree).
function LoadList(VotingReplicationInfo LoadVRI)
{
	bNotify = False;
	Super.LoadList(LoadVRI);
	bNotify = True;
}

// See MVMultiColumnList.NotifySelectionChanged()/InternalOnKeyEvent()/
// InternalOnRightClick() for the full rationale - identical bodies here for
// the bottom "vote count" panel's list.
function NotifySelectionChanged(GUIComponent Sender)
{
	if( KFMapVotingPageX(PageOwner) != none )
		KFMapVotingPageX(PageOwner).UpdateMapPreviewForSelection(self);
}

// See MVMultiColumnList.StepNav()/InternalOnKeyEvent()/Timer() for the full
// rationale (held-repeat via this component's own SetTimer/Timer rather
// than relying on unverified OS/native key-repeat delivery) - identical
// bodies here for the bottom "vote count" panel's list.
final function bool StepNav(Interactions.EInputKey NavKey)
{
	if( NavKey == IK_W || NavKey == IK_Up )
		return Up();
	if( (NavKey == IK_S || NavKey == IK_Down) && !Controller.ShiftPressed )
		return Down();
	return false;
}

function bool InternalOnKeyEvent(out byte Key, out byte KeyState, float Delta)
{
	local Interactions.EInputKey iKey;

	iKey = EInputKey(Key);

	if( iKey == IK_W || iKey == IK_S || iKey == IK_Up || iKey == IK_Down )
	{
		if( KeyState == 1 ) // IST_Press
		{
			if( bRepeatNavActive && iKey == RepeatNavKey )
				return true; // likely OS auto-repeat for a key we're already driving - ignore

			StepNav(iKey);
			bRepeatNavActive = true;
			RepeatNavKey = iKey;
			// Genuinely repeating timer (bRepeat=true) - see
			// MVMultiColumnList.InternalOnKeyEvent()'s comment for why NOT
			// a one-shot re-armed by a second SetTimer() call from inside
			// Timer() (that pattern has no working precedent anywhere in
			// this SDK and stopped after two steps when tried).
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

// See MVMultiColumnList.Timer() - identical logic. Speeds the already-
// repeating timer up to RepeatNavInterval via direct TimerInterval
// reassignment (GUIComponent.uc) rather than a second SetTimer() call.
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

// This list isn't a bDropSource (only lb_MapListBox.List is, per
// MapVotingPage.uc), so the Super call here is a harmless no-op - kept for
// symmetry with MVMultiColumnList's identical override.
function bool InternalOnRightClick(GUIComponent Sender)
{
	local int NewIndex;

	Super.InternalOnRightClick(Sender);

	NewIndex = Top + ( (Controller.MouseY - ClientBounds[1]) / ItemHeight );
	if( NewIndex >= ItemCount )
		NewIndex = ItemCount - 1;
	SetIndex(NewIndex);

	log("STVoteDiag: MVCountColumnList.InternalOnRightClick fired NewIndex="$NewIndex
		$" Top="$Top$" ItemHeight="$ItemHeight$" ItemCount="$ItemCount,'STVoteDiag');

	return true;
}

function DrawItem(Canvas Canvas, int i, float X, float Y, float W, float H, bool bSelected, bool bPending)
{
	local float CellLeft, CellWidth;
	local GUIStyles DrawStyle;
	local string MapName;

	if( VRI == none )
		return;

	// Draw the selection border
	if( bSelected )
	{
		SelectedStyle.Draw(Canvas,MenuState, X, Y-1, W, H+2 );
		DrawStyle = SelectedStyle;
	}
	else DrawStyle = Style;

	GetCellLeftWidth( 0, CellLeft, CellWidth );
	DrawStyle.DrawText( Canvas, MenuState, CellLeft, Y, CellWidth, H, TXTA_Left,
		VRI.GameConfig[VRI.MapVoteCount[SortData[i].SortItem].GameConfigIndex].GameName, MyFontScale );

	// "RANDOM MAP" renders in yellow here too, mirroring
	// MVMultiColumnList.DrawItem() - applied at draw time only, never baked
	// into the replicated MapName field. Votes for it are expected to
	// visibly accumulate in this leaderboard exactly like a real map (see
	// KFVotingHandler.TallyVotesInternal()'s deferred-resolution swap).
	MapName = VRI.MapList[VRI.MapVoteCount[SortData[i].SortItem].MapIndex].MapName;
	if( MapName ~= RANDOM_MAP_NAME )
		MapName = Chr(0x1B)$Chr(255)$Chr(255)$Chr(1)$MapName;

	GetCellLeftWidth( 1, CellLeft, CellWidth );
	DrawStyle.DrawText( Canvas, MenuState, CellLeft, Y, CellWidth, H, TXTA_Left,
		MapName, MyFontScale );

	GetCellLeftWidth( 2, CellLeft, CellWidth );
	DrawStyle.DrawText( Canvas, MenuState, CellLeft, Y, CellWidth, H, TXTA_Left,
		string(VRI.MapVoteCount[SortData[i].SortItem].VoteCount), MyFontScale );

	GetCellLeftWidth( 3, CellLeft, CellWidth );
	DrawStyle.DrawText( Canvas, MenuState, CellLeft, Y, CellWidth, H, TXTA_Left,
		KFVotingReplicationInfo(VRI).RepArray[VRI.MapVoteCount[SortData[i].SortItem].MapIndex], MyFontScale );
}
//------------------------------------------------------------------------------------------------
function string GetSortString( int i )
{
	local string ColumnData[5];

	ColumnData[0] = left(Caps(VRI.GameConfig[VRI.MapVoteCount[i].GameConfigIndex].GameName),15);
	ColumnData[1] = left(Caps(VRI.MapList[VRI.MapVoteCount[i].MapIndex].MapName),20);
	ColumnData[2] = right("0000" $ VRI.MapVoteCount[i].VoteCount,4);
	ColumnData[3] = KFVotingReplicationInfo(VRI).RepArray[VRI.MapVoteCount[i].MapIndex];
	if( Left(ColumnData[3],1)==Chr(0x1B) )
		ColumnData[3] = Mid(ColumnData[3],4); // Remove color code from sorting.

	return ColumnData[SortColumn] $ ColumnData[PrevSortColumn];
}

defaultproperties
{
	ColumnHeadings(3)="Rating"
	InitColumnPerc(0)=0.3
	InitColumnPerc(1)=0.3
	InitColumnPerc(2)=0.2
	InitColumnPerc(3)=0.2
	ColumnHeadingHints(3)="User rating of the map."

	GetItemHeight=MyItemHeight
	OnChange=NotifySelectionChanged
	MyFontScale=FNS_Medium
	FontScale=FNS_Medium

	// ~0.15s/item covers a ~200-map list in about 30 seconds.
	RepeatNavInitialDelay=0.25
	RepeatNavInterval=0.15
}
