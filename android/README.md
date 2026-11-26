# Lyrics Widget for Android

A floating synced-lyrics card pinned at the top of the screen, like a music player card. It follows any music app that shows a media notification (Spotify, YouTube Music, browsers). Everything is customized inside the app.

## Download

The new signed app installs alongside the old test app and doesn’t transfer settings or saved timing automatically.

## First run

1. Open the app and tap **Allow** next to Notification access and Display over other apps.
2. If Android says the setting is restricted: App info, three-dot menu, **Allow restricted settings**, then try again.
3. Set battery to **Unrestricted** so the card keeps running. On Xiaomi, also turn on Autostart.
4. Play a song. The card appears at the top.

## Using it

- Drag the top bar to move the card. **X** hides it until the next song.
- Tap the line being sung to fix the timing. It is remembered for that song.
- List button: choose another lyric or search by hand. Reload searches again.
- Quick Settings tile **Lyrics widget** turns the card on and off.

## Settings (all in the app)

- Presets: Lyrics only, Default, Player
- Background colour (or tint from album art) and lyrics colour
- Transparency, text size, corner roundness, width
- Lines shown (1, 3 or 5) and alignment
- Album art, title, progress bar, play buttons on or off
- Position, lock position, hide when paused or when no lyrics
- Import your own `.lrc` file for the current song

## Notes

- Song titles and artists are sent to LRCLIB, Kugou and NetEase to find lyrics. Lyrics you pick are saved on the phone only.
- Build it yourself: `cd android && gradle assembleDebug` (needs the Android SDK and JDK 17).
