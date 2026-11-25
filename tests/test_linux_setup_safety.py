"""Isolated Linux setup checks; never touch the real home or system package."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "lyrics-widget-setup"


@unittest.skipUnless(os.name == "posix" and shutil.which("bash"), "requires a POSIX host with Bash")
class SetupSafetyTests(unittest.TestCase):
    def test_rejects_non_letter_and_multiline_keys_before_writing_config(self):
        for key in ("LL", "A\nB", "1", "?"):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as tmp:
                result = subprocess.run(["bash", str(SCRIPT), "--key", key],
                                        env={**os.environ, "HOME": tmp},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse((Path(tmp) / ".config").exists())

    def test_repeated_upgrades_keep_edited_configs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "package-shell.qml"
            source.write_text("packaged content")
            script = root / "setup-fixture.sh"
            # Replace only the installed system source path with our fixture.
            script.write_text(SCRIPT.read_text().replace(
                "/usr/share/lyrics-widget/shell.qml", str(source), 1))
            target = root / ".config/quickshell/lyrics/shell.qml"
            target.parent.mkdir(parents=True)
            for content in ("user edit one", "user edit two"):
                target.write_text(content)
                result = subprocess.run(["bash", str(script)], env={**os.environ, "HOME": tmp},
                                        check=True, capture_output=True, text=True)
                self.assertIn("Saved the previous widget configuration", result.stdout)
                self.assertEqual(target.read_text(), "packaged content")
            self.assertCountEqual([p.read_text() for p in target.parent.glob("shell.qml.bak.*")],
                                  ["user edit one", "user edit two"])


if __name__ == "__main__":
    unittest.main()
