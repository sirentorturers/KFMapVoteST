# Voting Handler Fix ST

A fork of KFMapVoteV3SE that resolves bugs and adds several new features. Most of the following is thanks to the conversion from arrays to PerObjectConfigs. We have far more flexibility now as a result.

- Unlimited game modes. 
- Custom sort order (1, 2, etc, setting 0 for anything after sorts those alphabetically after the other numbers)
- Difficulty drop down selector to clean up the mode list.
- Map preview images (requires creating an image package, batch creation scripts provided in Tools folder)
- Game mode descriptions.
- Per mode map lists via Allow/Exclude map list styles. Use Copy style to match other mode map lists.
- Proper Map List Downloading In Progress refresh without you needing to click out several times. No more pop up window, it just loads as soon as it is done downloading, no additional clicks required.
- Random Map vote option at the top of map lists and in yellow text. ScrnBalance Hardcore Level bonuses link in via a few extra lines of code added in to ScrnBalance (I will send the code over to PooSH to see if he wants to officially integrate it, since it does not create a hard dependency on KFMapVoteST).


To install, you must completely remove all previous KFMapVote files from your system folder. Ensure you have your voting handler updated in your KillingFloor.ini to KFMapVoteST. Then, you must reconfigure your inis to work with our new methods for defining game modes. Please check the Configs folder for example inis. In short, GameConfig arrays are no longer defined in KFMapVote.ini, but in KFMapVoteModes.ini and using PerObjectConfigs instead of Arrays. If you run ScrnBalance and have edited ScrnGames, ScrnZeds, or any other inis like that, you should instantly be familiar with these.

Map preview images (screenshot, author, player count) shown in the map vote footer are built by a separate pipeline - see `PREVIEW_PIPELINE.md` for the full how-to.
