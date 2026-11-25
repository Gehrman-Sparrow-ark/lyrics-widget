# Lyrics Widget for Windows

A floating synced-lyrics pill that follows whatever you play (Spotify, YouTube Music in a browser, and any app that reports to Windows' media controls). It checks your own `.lrc` folder first, then LRCLIB, Kugou and NetEase.

## Requirements

- Windows 10 1809 or newer, or Windows 11, on x64.
- x64 CPython 3.11 or 3.12 from [python.org](https://www.python.org/downloads/) with the `py` launcher. Installation tries 3.12 first and then 3.11. Python installed for ARM64 or 32-bit Windows is not covered by this dependency lock.

## Install

Download the ZIP of a release (it never changes after publishing):
[v1.3.2-1](https://github.com/Gehrman-Sparrow-ark/lyrics-widget/archive/refs/tags/v1.3.2-1.zip).
Or clone the repository: `git clone https://github.com/Gehrman-Sparrow-ark/lyrics-widget.git`. Extract or clone to a normal local folder and open its `windows` subfolder.

Double-click `install.bat` or run it in Command Prompt. It uses a private `.venv` in this copy, installs only the pinned and hash-checked wheels, runs dependency and import checks, and then asks whether to start the widget with Windows. If you say Yes, it saves a shortcut in your per-user Startup folder and reads back the target, working directory and arguments. To skip that prompt and never change Startup, run:

```bat
.venv\Scripts\python.exe -I -m ensurepip --upgrade
install.bat --no-autostart
```

If Windows or your organization blocks the installer, stop. Verify the ZIP source and record the exact Windows warning. Do not change SmartScreen, Smart App Control or administrator policy for this app.

## Run

Double-click `run.bat`, or run it from Command Prompt. It uses this copy's virtual environment and keeps a console available to show startup errors. Play a song in an app that reports to Windows media controls. If the widget starts, its tray icon gives access to the picker and Quit.

```bat
.venv\Scripts\python.exe lyricswidget.py
```

## Update

Quit with the widget's tray menu before updating. For a ZIP, extract the newer release into a separate folder and run its `install.bat`, then re-enable autostart from that copy only if desired. For a Git clone, run `git pull` and rerun `install.bat` if `requirements.txt` changed. Do not overwrite an existing virtual environment or copy one between folders.

## Hotkeys

| Keys | Action |
| --- | --- |
| Ctrl+Alt+L | Show or hide the widget |
| Ctrl+Alt+P | Open the lyrics picker |
| Ctrl+Alt+R | Reload the search |
| Ctrl+Alt+= | Lyrics half a second earlier |
| Ctrl+Alt+- | Lyrics half a second later |

You can change them in the `HOTKEYS` table in `lyricswidget.py`.

## Using it

- Drag the grip bar at the top to move it, and drag any corner to resize it.
- Click the line being sung to fix the timing. The offset is saved in the `.lrc` file.
- The list button opens the picker. Type artist and title in the search box, or click a result to use it. Your choice is saved to `Music\Lyrics`.
- After a typed search an **Auto** button appears next to Search. Press it, or clear the box and press Enter, to go back to automatic matching. Reload and a new song also reset to automatic.
- The reload button redoes the search. The Aa button opens the style panel (background colour, line colour, transparency, text size).
- Right-click the tray icon for show/hide, choose lyrics, reload, search by hand, open the lyrics folder and quit.

## Files

- Lyrics you pick or adjust: `%USERPROFILE%\Music\Lyrics`
- Style settings: `%LOCALAPPDATA%\lyrics-widget\style.json`
- Log: `%LOCALAPPDATA%\lyrics-widget\lyrics-widget.log`

## Privacy

Song titles and artists are sent to LRCLIB, Kugou and NetEase to find lyrics. Kugou and NetEase are unofficial endpoints and may change or stop working.

## Troubleshooting

- **Black box instead of a see-through pill:** report your Windows build, GPU and the exact error or log; do not change Windows security settings.
- **Nothing appears:** read the log: `type %LOCALAPPDATA%\lyrics-widget\lyrics-widget.log`
- **A hotkey does nothing:** another program already uses it, and the log says so. Change it in `HOTKEYS`.
- **No lyrics for a song:** use the picker's search box, or open `Music\Lyrics` and add an `.lrc` file named like the song.
- **Chinese, Japanese or Korean lyrics show as boxes:** install a CJK font such as Noto Sans CJK.

## Uninstall

Quit the widget, open `shell:startup` and remove the Lyrics Widget shortcut if you created one, then remove the widget folder if no longer needed. This removes only this copy's `.venv`; do not uninstall packages from your global Python. Your lyrics in `Music\Lyrics` and local preferences are stored separately.
