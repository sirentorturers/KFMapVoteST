# Voting Handler Fix ST

A proper KFMapVote fork that resolves the biggest 2 bugs and also will provie additional features in the coming weeks.

Immediate benefit of running this will be you will now have unlimited game modes and difficulties you can make available on your servers.

To install, you must completely remove all previous KFMapVote files from your system folder, especially V3, as ScrnBalance will try to override to V3 regardless of what you edit in ScrnBalanceSrv.ini to stop the override. Ensure you have your voting handler updated in your KillingFloor.ini to KFMapVoteST. Then, you must reconfigure your inis to work with our new methods for defining game modes. Please check the Configs folder for example inis. In short, GameConfig arrays are no longer defined in KFMapVote.ini, but in KFMapVoteModes.ini and using PerObjectConfigs instead of Arrays. If you run ScrnBalance and have edited ScrnGames, ScrnZeds, or any other inis like that, you should instantly be familiar with these.

The limited modes issue was previously limited by 2 major bugs:

Resolved Bug 1: The use of a single array introduced a character limit of 4095. If you exceeded that in your KFMapVote.ini GameConfig= lines, your server would crash on map change. In KFMapVoteST, that was completely resolved by moving away from arrays to PerObjectConfigs. This however, does mean you need to reconfigure your inis, please make sure you check the configs folder for example inis.

Resolved Bug 2: After resolving the array issue, another bug was discovered in that the WebAdmin appears to have been limited in how much it could display under the game config sections, which led to the same exact crashes on map change unless the WebAdmin was disabled. Since I do use the WebAdmin but not for KFMapVote editing, I did not spend the time to research the issue, and opted to strip WebAdmin support out entirely for game config sections. Any self-respecting admin is editing the raw ini files anyways, so it felt unnecessary to waste any further time on this. 

Future features planned: Separate difficulty drop down, map preview image with author, and game mode descriptions.