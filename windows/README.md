# Lyrics Widget for Windows

A floating synced-lyrics pill that follows whatever you play (Spotify, YouTube Music in a browser, and any app that reports to Windows' media controls). It checks your own `.lrc` folder first, then LRCLIB, Kugou and NetEase.

## Requirements

- Windows 10 or 11
- Python 3.11 or 3.12 from [python.org](https://www.python.org/downloads/) (tick "Add python.exe to PATH")

## Download

**Option A, no git needed:** download
[the ZIP](https://github.com/Gehrman-Sparrow-ark/lyrics-widget/archive/refs/heads/main.zip),
right-click it, choose Extract All, then open the `windows` folder inside.

**Option B, with git:**

    git clone https://github.com/Gehrman-Sparrow-ark/lyrics-widget.git
    cd lyrics-widget\windows

## Install

Double-click `install.bat`. It installs the Python packages and asks whether to start the widget with Windows. If Windows shows a "protected your PC" warning, choose More info, then Run anyway.

Manual install instead:

    py -m pip install -r requirements.txt

## Run

Double-click `run.bat`, or run `py lyricswidget.py` to keep a console open and see errors. Play a song and the pill appears at the bottom of the screen, with a tray icon.

## Update

Open cmd or powershell from lyrics-widget\windows or run.bat file location

    git pull

Then quit from the shortcut and again Double-click `run.bat`, or run `py lyricswidget.py`

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
- The reload button redoes the search. The Aa button opens the style panel (background colour, line colour, transparency, text size).
- Right-click the tray icon for show/hide, choose lyrics, reload, search by hand, open the lyrics folder and quit.

## Files

- Lyrics you pick or adjust: `%USERPROFILE%\Music\Lyrics`
- Style settings: `%LOCALAPPDATA%\lyrics-widget\style.json`
- Log: `%LOCALAPPDATA%\lyrics-widget\lyrics-widget.log`

## Privacy

Song titles and artists are sent to LRCLIB, Kugou and NetEase to find lyrics. Kugou and NetEase are unofficial endpoints and may change or stop working.

## Troubleshooting

- **Black box instead of a see-through pill:** open `lyricswidget.py` and delete the `QT_QUICK_BACKEND` line near the top.
- **Nothing appears:** read the log: `type %LOCALAPPDATA%\lyrics-widget\lyrics-widget.log`
- **A hotkey does nothing:** another program already uses it, and the log says so. Change it in `HOTKEYS`.
- **No lyrics for a song:** use the picker's search box, or open `Music\Lyrics` and add an `.lrc` file named like the song.
- **Chinese, Japanese or Korean lyrics show as boxes:** install a CJK font such as Noto Sans CJK.

## Uninstall

Delete the folder, delete `Lyrics Widget` from `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`, and optionally `py -m pip uninstall PySide6`. Your lyrics in `Music\Lyrics` stay.
