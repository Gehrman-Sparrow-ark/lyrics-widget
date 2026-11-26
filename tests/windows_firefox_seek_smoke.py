#!/usr/bin/env python3
"""Windows media-position handling: Firefox reporting no position, real seeks, and recovery.

From the project root, run: python tests/windows_firefox_seek_smoke.py
Requires PySide6. Runs offscreen; no WinRT.
"""

import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
sys.dont_write_bytecode = True

from PySide6.QtWidgets import QApplication

WINDOWS = Path(__file__).resolve().parents[1] / "windows"
sys.path.insert(0, str(WINDOWS))


def tl(pos, start, end, updated_ago=None, naive=False):
    stamp = None
    if updated_ago is not None:
        stamp = datetime.now(timezone.utc) - timedelta(seconds=updated_ago)
        if naive:
            stamp = stamp.replace(tzinfo=None)
    return SimpleNamespace(position=timedelta(seconds=pos), start_time=timedelta(seconds=start),
                           end_time=timedelta(seconds=end), last_updated_time=stamp)


def close(a, b, tol=0.25):
    return abs(a - b) <= tol


def run(root):
    os.environ["LOCALAPPDATA"] = str(root)
    import lyricswidget as w
    w.LYR_DIR = root / "Lyrics"
    app = QApplication([])
    unknown = w.UNKNOWN_POSITION

    # --- timeline_sample
    assert w.timeline_sample(tl(0, 0, 0, 1), True) == (unknown, 0.0), "Firefox 'no state' must be unknown"
    assert w.timeline_sample(tl(0, 0, 0), False) == (unknown, 0.0)
    pos, length = w.timeline_sample(tl(0, 0, 200), False)
    assert (pos, length) == (0.0, 200.0), "a real seek to zero with a known duration is valid"
    pos, length = w.timeline_sample(tl(50, 0, 200, 2.0), True)
    assert close(pos, 52.0) and length == 200.0, (pos, length)
    pos, _ = w.timeline_sample(tl(50, 0, 200, 2.0, naive=True), True)
    assert close(pos, 52.0), "naive timestamps are treated as UTC"
    pos, _ = w.timeline_sample(tl(199, 0, 200, 30.0), True)
    assert pos == 200.0, "position is clamped to the track length"
    pos, _ = w.timeline_sample(tl(50, 0, 200, 99999.0), True)
    assert pos == 50.0, "a stale update time is ignored"

    # --- backend behaviour
    b = w.Backend()
    b.spawn = lambda mode, generation: None
    lrc = [{"t": 10.0, "text": "one"}, {"t": 20.0, "text": "two"}, {"t": 30.0, "text": "three"}]
    b.onMedia(True, "Song", "Artist", 12.0, 200.0, True)
    b.times = [x["t"] for x in lrc]
    b.lines = lrc
    b.tick()
    assert b.idx == 0 and b.positionKnown and b.playing

    # Firefox drops its position: the lines freeze, the clock stops, edits are refused.
    b.onMedia(True, "Song", "Artist", unknown, 0.0, True)
    assert not b.positionKnown and not b.playing
    frozen = b.curPos()
    assert b.length == 200.0, "an unknown length must not wipe the known one"
    idx_before = b.idx
    b.tick()
    assert b.idx == idx_before, "tick must not move lines without a position"
    off_before = b.offset
    b.syncTo(2)
    assert b.offset == off_before, "click-to-sync must be refused without a position"
    assert close(b.curPos(), frozen, 0.01), "the clock must not run while the position is unknown"

    # The position comes back: it resumes from the real value.
    b.onMedia(True, "Song", "Artist", 25.0, 200.0, True)
    assert b.positionKnown and b.playing and close(b.curPos(), 25.0)
    assert b.idx == 1, b.idx

    # A new track with no position starts from zero, not from the old song's time.
    b.onMedia(True, "Next", "Artist", unknown, 0.0, True)
    assert not b.positionKnown and b.posRef == 0.0 and b.title == "Next"

    # No player at all.
    b.onMedia(False, "", "", 0.0, 0.0, False)
    assert not b.hasPlayer and not b.positionKnown and not b.playing

    b.flushPendingSaves()
    print("PASS: Firefox unknown position, real seek, recovery and track change")


with tempfile.TemporaryDirectory() as tmp:
    run(Path(tmp))
