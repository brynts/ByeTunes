This is a pretty big update for ByeTunes.
A lot of things got added, improved and fixed in this version, especially for iOS 26.4 and newer.

Main thing to know first:

iOS 26.4 and newer now need a new type of pairing file called an RP Pairing File.
Regular pairing files still work for iOS 26.3.x and lower, but iOS 26.4+ is different now.

ByeTunes now handles that properly.
If you are on iOS 26.4 or newer, the app will ask you to import an RP Pairing File.
That popup will stay there until you import the correct file.

The app also validates pairing files now.
So if somebody imports the wrong file, ByeTunes should reject it instead of accepting it and crashing later.

RP Pairing Files are now saved separately as:

rpPairingFile.plist

Regular pairing files still save as:

pairingFile.plist

Now for the artwork stuff.

iOS 26.4 changed how Apple Music displays artwork and background colors.
Because of that, older injected songs could show artwork in some places but still have a gray background or missing display artwork in the newer Apple Music views.

This update adds the new iOS 26.4+ artwork database support.
Injected songs on iOS 26.4 and newer now get the new artwork rows they need.
iOS 26.3.x and lower keep the older database behavior, so they do not get the new iOS 26.4-only changes.

Apple Music artwork colors are now used too.
When ByeTunes fetches Apple Music metadata, it now reads the artwork color data Apple provides and uses that for the new iOS 26.4 background colors.
If Apple does not provide colors, ByeTunes falls back to local artwork color sampling.

Added Fix Artwork in Settings.
This is only visible on iOS 26.4 and newer.
It is meant for songs you injected before updating to iOS 26.4.

Fix Artwork will try to repair the artwork and colors for those older injected songs.
Internet is required because it fetches the colors from Apple Music.
It now shows a popup with progress instead of just spinning forever with no context.

Backup and restore got a big improvement too.

There is now a Full Backup option in Settings.

If Full Backup is off:
ByeTunes makes the smaller database-only backup like before.

If Full Backup is on:
ByeTunes saves a full local copy of the database and media files.
This is useful if a PC sync or external sync deletes the songs from the device, because a database-only backup cannot restore files that are gone.

Full Backup can take more time and use more space, but it is way safer.
I also removed the zip/unzip process because it was too slow.
It now stores the full copy directly, which is faster.

Backup and restore now show proper progress popups.
So instead of just seeing a spinner, you can see what step ByeTunes is working on.

The backup snapshots folder is hidden now too.
Existing old backup folders should migrate automatically.

Added an update checker.
ByeTunes now checks the GitHub releases page when opening the app.
If a newer version is available, it shows a popup with a link to download the latest release.

You can also tap the Version row in Settings to check for updates manually.

Added a downloader server chooser in Settings.
You can now choose:

Auto
Yoinkify
HiFi One
HiFi Two

Auto keeps the normal fallback behavior.
Choosing one server forces that backend.

The downloader fallback behavior was improved too.
Yoinkify now uses the updated server URL.
If the first mapped Tidal result fails, ByeTunes can now search for other possible Tidal matches and try those.
Some backend redirect and manifest responses are handled better too.

Lyrics got a big improvement.

ByeTunes now supports more lyrics sources:

LRCLIB
Musixmatch
NetEase

The manual lyrics search now lets you choose the lyrics service.
Automatic lyrics fetching can also use fallback services when Apple subscription lyrics are disabled.

Added support for choosing a custom downloaded songs folder.
If you keep downloaded songs locally, ByeTunes can now use a saved folder bookmark instead of always using the default app folder.

Improved logs.
You can now copy logs from the log viewer.
Exported logs now use a stable Logs/MusicManager_Logs.txt file instead of making a new timestamped file every time.

Improved injection reliability for iOS 26.4 RP Pairing.
There was a race where injection could start right before the RP tunnel was actually ready.
That caused AFC to be nil and the injection would fail.

That should be fixed now.
ByeTunes now waits for the actual RP tunnel handles before injection continues.
AFC also retries briefly if it catches the tunnel right at the setup edge.

Injection on RP Pairing should also be a little faster now because ByeTunes reuses the AFC connection during the main upload pass instead of reconnecting for every song, artwork file and database upload.

Small disclaimer for iOS 26.4 and newer:
Injection can still be slower than it was on older iOS versions.
That is because Apple now requires the new RP Pairing method for this path, and RP Pairing goes through a heavier tunnel/RSD/AFC route than the old regular pairing file method.
ByeTunes reduces extra reconnects and round trips where it can, but the new Apple-required method is still slower by nature.

Fixed Music app killing on iOS 26.4+.
The pre-injection Music app kill now uses the RP tunnel path when needed.

Fixed full backup saving artwork twice.
If Full Backup is enabled, ByeTunes now skips the separate artwork side backup because the full iTunes copy already includes artwork.

Fixed full backup restore detection.
If a backup was created as a Full Backup, ByeTunes restores it as a full backup even if the toggle is currently off.

Improved duplicate review UI.
The duplicate review screen should be clearer now when choosing which detected duplicates to keep or skip.

Updated ByeTunes to version 2.1 across the app, project settings, update checker, build logs and user agents.

Downloads are still one by one for now.
I tested multiple downloads at the same time, but it did not actually improve the backend download behavior enough and the UI became misleading.
So I rolled it back to the reliable linear download queue for now.

Thanks again to everybody testing ByeTunes, sending logs, databases, pairing files and feedback.
This update touches a lot of sensitive iOS 26.4 stuff, so that testing helped a lot.
Hope you guys enjoy this update.
