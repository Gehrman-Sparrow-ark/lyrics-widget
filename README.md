# lyrics-widget

A floating synced-lyrics widget for Quickshell on Wayland. Reads the current song from any MPRIS player, checks your own `.lrc` folder first, then searches LRCLIB, Kugou and NetEase. Theme colors follow end-4's `colors.json` if it exists, otherwise a built-in palette is used.

## Install (Arch)

### From the pacman feed

Add the feed once per machine:

    printf '\n[lyrics-widget]\nSigLevel = Optional TrustAll\nServer = https://github.com/Gehrman-Sparrow-ark/lyrics-widget/releases/download/repo\n' | sudo tee -a /etc/pacman.conf

Then install and set up as your normal user:

    sudo pacman -Syu lyrics-widget
    lyrics-widget-setup --hyprland
    setsid -f qs -p ~/.config/quickshell/lyrics

`SigLevel = Optional TrustAll` means pacman does not check a signature for this feed. Use it only on machines you trust, or build from source below.

### From source

    git clone https://github.com/Gehrman-Sparrow-ark/lyrics-widget.git
    cd lyrics-widget
    makepkg -si
    lyrics-widget-setup
    setsid -f qs -p ~/.config/quickshell/lyrics

Requires a Wayland compositor with layer-shell support (Hyprland, Sway, niri, ...), Quickshell and Python 3. Run setup as a normal user. If you edited the copied widget, setup saves the previous file next to it as `shell.qml.bak.*` before replacing it.

`lyrics-widget-setup --hyprland` also adds autostart and a `SUPER+CTRL+L` toggle to your Hyprland config (Lua or classic), with a backup, and changes nothing if the key is taken. Use `--key Y` to pick another letter.

## Releasing (maintainers)

1. Edit the files. If you changed any file the package installs (`lyrsearch`, `lyrsave`, `shell.qml`, `lyrics-widget-setup`, `LICENSE`), run `updpkgsums` (from `pacman-contrib`) so the checksums in `PKGBUILD` match.
2. Raise `pkgver` or `pkgrel` in `PKGBUILD`, commit and `git push`.
3. `bash release.sh` builds and stages the package under `dist/`. It publishes nothing.
4. `bash publish.sh` uploads it: an immutable versioned release first, then the package to the `repo` feed, then the feed database, checking each download. It refuses to run from uncommitted or unpushed work.
5. Update machines with `sudo pacman -Syu`, then run `lyrics-widget-setup` again so the copied `shell.qml` refreshes.

The staged `SHA256SUMS` and `PROVENANCE.txt` record what was built. They are not a digital signature.

Tests: `python -m unittest discover -s tests -p "test_*.py"` needs only Python. The two `*_smoke.py` files in `tests/` need PySide6 and run offscreen.

## Hyprland keybinds (Lua config)

    hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("sh -c 'qs -p ~/.config/quickshell/lyrics ipc call lyrics toggle || qs -p ~/.config/quickshell/lyrics'"))
    hl.bind("SUPER + CTRL + equal", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/lyrics ipc call lyrics nudge 0.5"))
    hl.bind("SUPER + CTRL + minus", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/lyrics ipc call lyrics nudge -0.5"))
    hl.on("hyprland.start", function () hl.exec_cmd("qs -p ~/.config/quickshell/lyrics") end)

Classic `hyprland.conf`: `bind = SUPER CTRL, L, exec, ...` and `exec-once = qs -p ~/.config/quickshell/lyrics`.

## Using it

- Drag the grip bar at the top of the pill to move it, and drag any corner to resize it. The X hides it.
- Click the line being sung to fix timing. The offset is saved in the `.lrc` file.
- The list button opens a picker. Your choice is saved to `~/Music/Lyrics`.
- The picker has a search box for typing artist and title yourself. After a typed search, **Auto** returns to automatic matching.
- The reload button redoes the search.
- The "Aa" button opens the style panel: background colour, line colour, transparency and text size (saved automatically).
- Search by hand from a terminal: `qs -p ~/.config/quickshell/lyrics ipc call lyrics search "artist title"`

## Troubleshooting

- Keybind does nothing or shows a Hyprland error: that key is probably already used. Check with `grep -rn -i 'SUPER.*CTRL.*L"' ~/.config/hypr/` and pick a free key.
- Chinese, Japanese or Korean lyrics show as boxes: install a CJK font (`noto-fonts-cjk`).
- `qs -p ~/.config/quickshell/lyrics` says the config can't be found: run `lyrics-widget-setup` again, or start it with `qs -p /usr/share/lyrics-widget/shell.qml`.
- Colors look plain: the widget follows end-4's `colors.json` when it exists, otherwise it uses a built-in palette.
- After upgrading the package, run `lyrics-widget-setup` again so the copied `shell.qml` updates.

## Notes

Lyrics are not included and are not stored in this repo. Kugou and NetEase are unofficial endpoints and may change or stop working. Song titles and artists are sent to the selected lyric services. The automated tests cover the search logic, the setup script and the interface offscreen. Native Wayland compositors and a real Windows PC (global hotkeys, window focus) are verified by hand.

## Windows

A Windows version lives in the [windows](windows/) folder. See [windows/README.md](windows/README.md) for download and install steps.

## License

MIT
