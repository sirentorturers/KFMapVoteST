class KFMapVoteFooterX extends MapVoteFooter;

var localized string strLiked, stdDisliked;
var localized string strMapAuthor, strPlayers;

var automated GUIImage i_MapPreview;
var automated GUILabel l_MapPreviewInfo, l_MapPreviewNone;

// Native map cache (screenshot/author/player-count per map, pre-resolved
// at cache-build time) - same source XVoting.MapInfoPage.ReadMapInfo()
// prefers before falling back to a live LevelSummary load. Populated once
// below, same as MapInfoPage.InitComponent() does.
var array<CacheManager.MapRecord> CachedMaps;

// C&P to fix trimming the first typed character
function InitComponent(GUIController InController, GUIComponent InOwner)
{
	local string str;
	local ExtendedConsole C;
	local KFVotingHandler.FMapPreviewData EmptyPreview;

	Super(GUIFooter).InitComponent(InController, InOwner);

	lb_Chat.MyScrollText.SetContent("");
	lb_Chat.MyScrollText.FontScale = FNS_Small;

	C = ExtendedConsole(Controller.ViewportOwner.Console);
	if (C != None) {
		C.OnChatMessage = ReceiveChat;
		if (C.bTyping) {
			str = C.TypedStr;
			C.TypingClose();
			if ( Left(str,4) ~= "say " ) {
				str = Mid(str, 4);
			}
			else if ( Left(str,8) ~= "teamsay " ) {
				str = "." $ Mid(str, 8);
			}
			ed_Chat.SetText(str);
		}
	}
	OnDraw=MyOnDraw;

	class'CacheManager'.static.GetMapList(CachedMaps);

	UpdateMapPreview("", EmptyPreview);
}

final function int FindCachedMapIndex(string MapName)
{
	local int i;

	for (i = 0; i < CachedMaps.Length; i++)
		if (CachedMaps[i].MapName == MapName)
			return i;
	return -1;
}

// Pulls Screenshot/Author/PlayerCount for MapName from three sources, in
// order:
//   1. PreviewOverride - resolved server-side from KFMapVotePreviews.ini
//      (KFMapPreviewEntry) in KFVotingHandler.AddMap() and replicated to
//      every client one map at a time (see KFVotingReplicationInfo -
//      TickedReplication_MapList()/ReceiveMapInfoRep()/MapPreviewList),
//      pointing into a shared texture package shipped with this mod
//      (see KFMapPreviewEntry.uc). This is the only source guaranteed
//      present on every client regardless of whether they've ever
//      downloaded MapName's own map package - it can't be resolved
//      locally here since PerObjectConfig/.ini reads only see whatever
//      is on the machine actually running the code, and a client has no
//      local copy of KFMapVotePreviews.ini at all.
//   2. The native CacheManager map cache (CachedMaps) - built from
//      whatever maps this specific client already has installed
//      locally.
//   3. A live LevelSummary DynamicLoadObject - same as (2), only works
//      for maps already installed locally.
// (2) and (3) were the original implementation and turned out to both
// fail identically ("Can't find file for package") for any map the
// connecting client hasn't played before - confirmed via client log -
// since KF1 only downloads a map's package when actually traveling to
// it, never just for browsing the vote menu. Hence (1).
function UpdateMapPreview(string MapName, KFVotingHandler.FMapPreviewData PreviewOverride)
{
	local LevelSummary LS;
	local Material Screenie;
	local string AuthorLine, PlayersLine;
	local string MapAuthor;
	local int MinPlayers, MaxPlayers, CacheIdx;
	local bool bHavePlayerCount;

	log("UpdateMapPreview: MapName='"$MapName$"' PreviewOverride.TextureRef='"$PreviewOverride.TextureRef$"'", 'MapPreviewST');

	if (MapName != "")
	{
		if (PreviewOverride.TextureRef != "")
		{
			Screenie = Material(DynamicLoadObject(PreviewOverride.TextureRef, class'Material'));
			log("UpdateMapPreview: replicated override DynamicLoadObject result Screenie="$Screenie, 'MapPreviewST');

			MapAuthor = PreviewOverride.Author;
			MinPlayers = PreviewOverride.PlayerCountMin;
			MaxPlayers = PreviewOverride.PlayerCountMax;
			bHavePlayerCount = true;
		}
		else
		{
			CacheIdx = FindCachedMapIndex(MapName);
			log("UpdateMapPreview: CacheIdx="$CacheIdx$" (CachedMaps.Length="$CachedMaps.Length$")", 'MapPreviewST');

			if (CacheIdx != -1)
			{
				log("UpdateMapPreview: cache hit - ScreenshotRef='"$CachedMaps[CacheIdx].ScreenshotRef$"' Author='"$CachedMaps[CacheIdx].Author$"' PlayerCount="$CachedMaps[CacheIdx].PlayerCountMin$"-"$CachedMaps[CacheIdx].PlayerCountMax, 'MapPreviewST');

				if (CachedMaps[CacheIdx].ScreenshotRef != "")
					Screenie = Material(DynamicLoadObject(CachedMaps[CacheIdx].ScreenshotRef, class'Material'));

				log("UpdateMapPreview: cache branch DynamicLoadObject result Screenie="$Screenie, 'MapPreviewST');

				MapAuthor = CachedMaps[CacheIdx].Author;
				MinPlayers = CachedMaps[CacheIdx].PlayerCountMin;
				MaxPlayers = CachedMaps[CacheIdx].PlayerCountMax;
				bHavePlayerCount = true;
			}
			else
			{
				LS = LevelSummary(DynamicLoadObject(MapName $ ".LevelSummary", Class'LevelSummary'));
				log("UpdateMapPreview: cache miss - fallback LevelSummary DynamicLoadObject result LS="$LS, 'MapPreviewST');
				if (LS != None)
				{
					Screenie = LS.Screenshot;
					log("UpdateMapPreview: fallback LS.Screenshot="$Screenie$" LS.Author='"$LS.Author$"' LS.IdealPlayerCount="$LS.IdealPlayerCountMin$"-"$LS.IdealPlayerCountMax, 'MapPreviewST');
					MapAuthor = LS.Author;
					MinPlayers = LS.IdealPlayerCountMin;
					MaxPlayers = LS.IdealPlayerCountMax;
					bHavePlayerCount = true;
				}
			}
		}
	}

	log("UpdateMapPreview: final Screenie="$Screenie, 'MapPreviewST');

	i_MapPreview.Image = Screenie;
	i_MapPreview.SetVisibility(Screenie != None);
	l_MapPreviewNone.SetVisibility(Screenie == None);

	if (MapAuthor != "")
		AuthorLine = strMapAuthor $ ":" @ MapAuthor;

	if (bHavePlayerCount)
		PlayersLine = string(MinPlayers) $ "-" $ string(MaxPlayers) @ strPlayers;

	// Single multi-line label (same "|"-joined-lines convention already
	// used by l_MapPreviewNone's own text and by strHelp elsewhere in this
	// package) instead of two independently-positioned labels - two
	// separately stacked GUILabels were rendering on top of each other
	// regardless of the WinTop gap between them.
	if (AuthorLine != "" && PlayersLine != "")
		l_MapPreviewInfo.Caption = AuthorLine $ "|" $ PlayersLine;
	else
		l_MapPreviewInfo.Caption = AuthorLine $ PlayersLine;
}

function bool MyOnDraw(canvas C)
{
	local float l,t,w,xl,yl;
	local float ImgW, ImgH, ImgBottom;
	// Reposition everything

	// Keep the preview image at its true 512x256 (2:1) source aspect ratio.
	// WinWidth (0.28, set in defaultproperties) is left alone; WinHeight is
	// derived from the resulting actual pixel width every frame instead of
	// being an independent fraction of the (wide, short) footer's height -
	// that mismatch between the two axes is what was stretching the image.
	ImgW = i_MapPreview.ActualWidth();
	ImgH = ImgW * 0.5; // 256/512
	i_MapPreview.WinHeight = ActualHeight(ImgH);
	l_MapPreviewNone.WinHeight = i_MapPreview.WinHeight;

	// Position the combined Author/Player-count label directly beneath the
	// image, using whatever vertical room the (now correctly short) image
	// leaves free.
	ImgBottom = i_MapPreview.WinTop + i_MapPreview.WinHeight;
	l_MapPreviewInfo.WinTop = ImgBottom + 0.02;

	t = sb_Background.ActualTop() + sb_Background.ActualHeight() + 5;
	l = sb_Background.ActualLeft() + sb_Background.ActualWidth() - sb_Background.ImageOffset[3];

	b_Close.Style.TextSize(C,MSAT_Blurry,b_Close.Caption, XL,YL, b_Close.FontScale);
	w = XL;
	b_Submit.Style.TextSize(C,MSAT_Blurry,b_Close.Caption, XL,YL, b_Submit.FontScale);
	if (XL>w)
		w = XL;
	b_Accept.Style.TextSize(C,MSAT_Blurry,b_Close.Caption, XL,YL, b_Accept.FontScale);
	if (XL>w)
		w = XL;

	w = w*2.4;
	w = ActualWidth(w);

	l -= w;
	b_Close.WinWidth = w;
	b_Close.WinTop = t;
	b_Close.WinLeft = l;

	l -= w;
	b_Submit.WinWidth = w;
	b_Submit.WinTop = t;
	b_Submit.WinLeft = l;

	l -= w;
	b_Accept.WinWidth = w;
	b_Accept.WinTop = t;
	b_Accept.WinLeft = l;


	ed_Chat.WinLeft   = sb_Background.ActualLeft() + sb_Background.ImageOffset[0];
	ed_Chat.WinWidth  = L - ed_Chat.WinLeft;
	ed_Chat.WinHeight = 25;
	ed_Chat.WinTop    = t;

 	return false;
}

function ReceiveChat(string Msg)
{
	lb_Chat.AddText(Msg);
	lb_Chat.MyScrollText.End();
}

delegate bool OnSendChat( string Text )
{
	local string c;

	if (Text == "")
		return false;


	if (RecallQueue.Length == 0 || RecallQueue[RecallQueue.Length - 1] != Text) {
		RecallIdx = RecallQueue.Length;
		RecallQueue[RecallIdx] = Text;
	}

	c = Left(Text, 1);

	if (Text == "+") {
		if (KFVotingReplicationInfo(PlayerOwner().VoteReplicationInfo).SetMapLike(true)) {
			PlayerOwner().ClientMessage(strLiked);
		}
	}
	else if (Text == "-") {
		if (KFVotingReplicationInfo(PlayerOwner().VoteReplicationInfo).SetMapLike(false)) {
			PlayerOwner().ClientMessage(stdDisliked);
		}
	}
	else if (c == ".") {
		PlayerOwner().TeamSay(Mid(Text, 1));
	}
	else if (c == "/") {
		PlayerOwner().ConsoleCommand(Mid(Text, 1));
	}
	else if (c ~= "c" && Left(Text, 4) ~= "cmd ") {
		// legacy cmd
		PlayerOwner().ConsoleCommand(Mid(Text, 4));
	}
	else {
		PlayerOwner().Say(Text);
	}
	return true;
}

defaultproperties
{
	strLiked="Liked the current map"
	stdDisliked="Disliked the current map"
	strMapAuthor="Author"
	strPlayers="players"

	Begin Object Class=AltSectionBackground Name=MapvoteFooterBackground
		bFillClient=True
		bNoCaption=True
		bAltCaption=False
		LeftPadding=0.010000
		RightPadding=0.010000
		WinLeft=0.32
		WinWidth=0.66
		WinHeight=0.81
		bBoundToParent=True
		bScaleToParent=True
		OnPreDraw=MapvoteFooterBackground.InternalPreDraw
	End Object
	sb_Background=MapvoteFooterBackground

	Begin Object Class=GUIScrollTextBox Name=ChatScrollBox
		bNoTeletype=True
		CharDelay=0.002500
		EOLDelay=0.000000
		bVisibleWhenEmpty=True
		OnCreateComponent=ChatScrollBox.InternalOnCreateComponent
		StyleName="ServerBrowserGrid"
		WinLeft=0.335
		WinWidth=0.645
		WinTop=0.02
		WinHeight=0.76
		TabOrder=2
		bBoundToParent=True
		bScaleToParent=True
		bNeverFocus=True
	End Object
	lb_Chat=ChatScrollBox

	Begin Object Class=GUIImage Name=MapPreviewImage
		ImageStyle=ISTY_Scaled
		ImageRenderStyle=MSTY_Normal
		WinLeft=0.02
		WinTop=0.02
		WinWidth=0.28
		WinHeight=0.58
		bBoundToParent=True
		bScaleToParent=True
	End Object
	i_MapPreview=MapPreviewImage

	Begin Object Class=GUILabel Name=MapPreviewNoneLabel
		Caption="No Preview Available"
		TextAlign=TXTA_Center
		VertAlign=TXTA_Center
		TextColor=(B=0,G=255,R=247)
		TextFont="UT2HeaderFont"
		bTransparent=False
		bMultiLine=True
		WinLeft=0.02
		WinTop=0.02
		WinWidth=0.28
		WinHeight=0.58
		bBoundToParent=True
		bScaleToParent=True
	End Object
	l_MapPreviewNone=MapPreviewNoneLabel

	Begin Object Class=GUILabel Name=MapPreviewInfoLabel
		Caption=""
		TextAlign=TXTA_Center
		TextColor=(B=255,G=255,R=255)
		TextFont="UT2ServerListFont"
		bMultiLine=True
		WinLeft=0.02
		WinTop=0.61
		WinWidth=0.28
		WinHeight=0.15
		bBoundToParent=True
		bScaleToParent=True
	End Object
	l_MapPreviewInfo=MapPreviewInfoLabel

	Begin Object Class=moEditBox Name=ChatEditbox
		CaptionWidth=0.150000
		Caption="F2 Say"
		OnCreateComponent=ChatEditbox.InternalOnCreateComponent
		WinTop=0.868598
		WinLeft=0.007235
		WinWidth=0.700243
		WinHeight=0.106609
		TabOrder=0
		OnKeyEvent=MapVoteFooter.InternalOnKeyEvent
	End Object
	ed_Chat=ChatEditbox
}