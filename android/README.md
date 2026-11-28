# Lyrics Widget for Android

A floating synced-lyrics card pinned at the top of the screen, like a music player card. It follows any music app that shows a media notification (Spotify, YouTube Music, browsers). Everything is customized inside the app.

## Download

[Download Lyrics Widget for Android 1.0.1](https://github.com/Gehrman-Sparrow-ark/lyrics-widget/releases/tag/android-v1.0.3)

The new signed app installs alongside the old test app and doesn’t transfer settings or saved timing automatically.

## First run

1. Open the app and tap **Allow** next to Notification access and Display over other apps.
2. Android may restrict notification access for apps installed outside Google Play. If Play Protect blocks installation, keep it enabled. Developers can test in the Android Studio emulator and consult [Google’s Play Protect guidance](https://developers.google.com/android/play-protect/warning-dev-guidance).
3. Set battery to **Unrestricted** so the card keeps running. On Xiaomi, also turn on Autostart.
4. Leave Lyrics Widget settings and press Play in your music app. The card can appear while the player is still sending song info or while lyrics are loading.

## Using it

- Drag the top handle or swipe across the lyrics to move the card. Turn off **Lock position** first. **X** closes it until you tap **Show widget now** or turn the widget back on.
- Tap the line being sung to fix the timing. It is remembered for that song.
- List button: choose another lyric or search by hand. Reload searches again.
- **Widget → Show widget now** sends settings to the background and opens the card even if nothing is playing. Leave both automatic hide settings off to keep the card open until you press **X**.
- **Widget → Lyrics on the lock screen** shows the current line in a notification. Turn on app notifications and allow lock-screen notification content in Android settings. The floating card itself stays behind the secure lock screen. Anyone looking at the lock screen may see the song and lyric.
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

- The most recent automatic lyric match is cached on this phone for up to seven days so it can be restored without searching again. Reload still searches again.
- Song titles and artists are sent to LRCLIB, Kugou and NetEase to find lyrics. Lyrics you pick are saved on the phone only.
- Build it yourself: `cd android && gradle assembleDebug` (needs the Android SDK and JDK 17).
