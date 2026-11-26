# Lyrics Widget for Android

A floating synced-lyrics card pinned at the top of the screen, in the same place as your music player card. Works with any music app that shows a media notification (Spotify, YouTube Music, browsers...). All customization is in the app.

## Get the APK
1. Copy this `android/` folder and `.github/workflows/android.yml` into the repo, commit and push.
2. Tag a release to get a download link for your phone:
   `git tag android-v1.0.0 && git push origin android-v1.0.0`
   (or open Actions, Android APK, and download the `lyrics-widget-apk` artifact).
3. Open the release page on your phone, download `lyrics-widget.apk`, install it.

## First run
1. Open the app, tap **Allow** for Notification access and Display over other apps.
2. If Android says the setting is restricted: App info, three-dot menu, **Allow restricted settings**, then try again.
3. Battery settings: set the app to **Unrestricted**. On Xiaomi also enable Autostart.
4. Play a song. The card appears at the top.

## Using it
- Drag the top bar to move it. X hides it for the current song only.
- Tap the line being sung to fix timing (saved per song).
- List button: pick another lyric or search by hand. Reload redoes the search.
- Settings app: presets, colours (or tint from album art), transparency, text size, corners, width, lines shown, art/title/progress/buttons, position, lock.
- Quick Settings tile "Lyrics widget" turns it on and off.
- Lyrics are saved in the app's private storage. Use **Import .lrc file** to add your own.

Build locally: `cd android && gradle assembleDebug` (Android SDK + JDK 17).
