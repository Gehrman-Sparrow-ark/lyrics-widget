"""Provider-free regression tests for both lyric search entry points."""
import ast
import contextlib
import io
import json
from pathlib import Path
import subprocess
import os
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
HELPERS = (ROOT / "lyrsearch", ROOT / "windows" / "lyrsearch.py")


def load_helper(path):
    tree = ast.parse(path.read_text())
    # The existing standalone CLI invokes main() in its final exception guard.
    if not isinstance(tree.body[-1], ast.Try):
        raise AssertionError("Recheck the CLI entry point")
    tree.body.pop()
    env = {"__name__": "test_search"}
    exec(compile(tree, str(path), "exec"), env)
    return env


def hit(title, artist, duration, text):
    return {"source": "LRCLIB", "title": title, "artist": artist,
            "duration": duration, "album": "",
            "_fetch": lambda: "\n".join(f"[00:0{i}.00]{text}{i}" for i in range(1, 4))}


def run_provider_fixture(env, args, hits):
    env["src_lrclib"] = lambda *_: hits
    env["src_kugou"] = env["src_netease"] = lambda *_: []
    stdout = io.StringIO()
    with patch.object(sys, "argv", ["lyrsearch", "--online-only", *args]), contextlib.redirect_stdout(stdout):
        env["main"]()
    return json.loads(stdout.getvalue())["candidates"]


class SearchRegressionTests(unittest.TestCase):
    def test_original_artist_short_title_passes(self):
        for path in HELPERS:
            with self.subTest(path=path):
                m = load_helper(path)
                self.assertEqual(m["query_score"]("The Smashing Pumpkins", "1979", "The Smashing Pumpkins 1979"), 1.0)

    def test_manual_exact_match_outweighs_unrelated_playing_length(self):
        for path in HELPERS:
            with self.subTest(path=path):
                hits = [hit("Long Song", "Test Band", 240, "exact"),
                        hit("Long Song", "Another Band", 140, "near")]
                matches = run_provider_fixture(load_helper(path), ["--length=140", "--query=Test Band Long Song"], hits)
                self.assertEqual(matches[0]["artist"], "Test Band")
                self.assertEqual(matches[0]["score"], 1.0)

    def test_playing_length_breaks_manual_relevance_tie(self):
        for path in HELPERS:
            with self.subTest(path=path):
                hits = [hit("Song", "Test Band", 240, "different"),
                        hit("Song", "Test Band", 140, "near")]
                matches = run_provider_fixture(load_helper(path), ["--length=140", "--query=Test Band Song"], hits)
                self.assertEqual([m["duration"] for m in matches], [140, 240])

    def test_automatic_lookup_still_weights_duration(self):
        for path in HELPERS:
            with self.subTest(path=path):
                hits = [hit("Song", "Test Band", 240, "different"),
                        hit("Song", "Test Band", 140, "near")]
                matches = run_provider_fixture(load_helper(path), ["--length=140", "--title=Song", "--artist=Test Band"], hits)
                self.assertEqual([m["score"] for m in matches], [1.0, 0.5])

    def test_local_cli_accepts_dash_leading_query(self):
        for path in HELPERS:
            with self.subTest(path=path), tempfile.TemporaryDirectory() as home:
                cmd = [sys.executable, str(path), "--local-only", "--query=-M-"]
                proc = subprocess.run(cmd, env={**os.environ, "HOME": home, "USERPROFILE": home}, check=True, capture_output=True, text=True)
                self.assertEqual(json.loads(proc.stdout)["candidates"], [])


if __name__ == "__main__":
    unittest.main()
