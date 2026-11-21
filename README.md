# lyrics-widget

A floating synced-lyrics widget for [Quickshell](https://quickshell.org) on Wayland.
Reads the current song from any MPRIS player, checks your own `.lrc` folder first,
then searches LRCLIB, Kugou and NetEase. Theme colors follow end-4's
`colors.json` if it exists, otherwise a built-in palette is used.

## Install (Arch)

    git clone https://github.com/Gehrman-Sparrow-ark/lyrics-widget.git
    cd lyrics-widget
    makepkg -si
    lyrics-widget-setup
    setsid -f qs -c lyrics

Requires a Wayland compositor with layer-shell support (Hyprland, Sway, niri, ...),
Quickshell and Python 3.

## Hyprland keybinds (Lua config)

    hl.bind("SUPER + CTRL + L", hl.dsp.exec_cmd("sh -c 'qs -c lyrics ipc call lyrics toggle || qs -c lyrics'"))
    hl.bind("SUPER + CTRL + equal", hl.dsp.exec_cmd("qs -c lyrics ipc call lyrics nudge 0.5"))
    hl.bind("SUPER + CTRL + minus", hl.dsp.exec_cmd("qs -c lyrics ipc call lyrics nudge -0.5"))
    hl.on("hyprland.start", function () hl.exec_cmd("qs -c lyrics") end)

Classic `hyprland.conf`: `bind = SUPER CTRL, L, exec, ...` and `exec-once = qs -c lyrics`.

## Using it

- Drag the grip bar at the top of the pill to move it. The X hides it.
- Click the line being sung to fix timing. The offset is saved in the .lrc file.
- The list button opens a picker. Your choice is saved to `~/Music/Lyrics`.
- The reload button redoes the search.
- Search by hand: `qs -c lyrics ipc call lyrics search "artist title"`

## Troubleshooting

- **Keybind does nothing or shows a Hyprland error:** that key is probably already used. Check with
  `grep -rn -i 'SUPER.*CTRL.*L"' ~/.config/hypr/` and pick a free key.
- **Chinese, Japanese or Korean lyrics show as boxes:** install a CJK font (`noto-fonts-cjk`).
- **`qs -c lyrics` says the config can't be found:** run `lyrics-widget-setup` again, or start it with
  `qs -p /usr/share/lyrics-widget/shell.qml`.
- **Colors look plain:** the widget follows end-4's `colors.json` when it exists, otherwise it uses a built-in palette.
- After upgrading the package, run `lyrics-widget-setup` again so the copied `shell.qml` updates.

## Notes

Lyrics are not included and are not stored in this repo. Kugou and NetEase are
unofficial endpoints and may change or stop working. Song titles and artists are
sent to the selected lyric services. Tested on Arch Linux with Hyprland.

## License

MIT

