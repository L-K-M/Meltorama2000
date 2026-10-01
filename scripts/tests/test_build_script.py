"""Exercise the public build CLI without compiling or modifying host apps.

Run with: python3 -m unittest discover -s scripts/tests -v
"""

import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


BUILD_SCRIPT = Path(__file__).resolve().parents[1] / "build.sh"

MOCK_TOOL = r'''#!__PYTHON__
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["MELTORAMA_TEST_ROOT"])
failure = os.environ.get("MELTORAMA_TEST_FAILURE", "")
with Path(os.environ["MELTORAMA_TEST_LOG"]).open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")

def within_fixture(path):
    try:
        Path(path).resolve().relative_to(root.resolve())
    except ValueError:
        sys.exit("Mock refuses to modify a path outside its fixture")

if name == "uname":
    print("Darwin")
elif name == "swift":
    pass
elif name == "ditto":
    source, destination = args[-2:]
    within_fixture(destination)
    if failure == "copy":
        Path(destination).mkdir(parents=True, exist_ok=True)
        (Path(destination) / "incomplete-copy").write_text("partial")
        sys.exit(23)
    shutil.copytree(source, destination, symlinks=True, dirs_exist_ok=True)
elif name == "codesign":
    if failure == "signature":
        sys.exit(24)
    if not (Path(args[-1]) / "Contents" / "Info.plist").is_file():
        sys.exit("Missing bundle metadata")
elif name == "python3":
    if len(args) < 4 or args[0] != "-c" or "os.rename" not in args[1]:
        sys.exit(subprocess.call([sys.executable, *args]))
    source, destination = args[-2:]
    within_fixture(source)
    within_fixture(destination)
    installed = Path(os.environ["MELTORAMA_INSTALL_DIR"]) / "Meltorama.app"
    replacing = Path(destination) == installed and Path(source).name != "Previous.app"
    if replacing:
        if failure in ("replace", "rollback"):
            sys.exit(25)
        if failure == "interrupt":
            os.kill(os.getppid(), signal.SIGTERM)
            sys.exit(27)
        if failure == "race":
            installed.mkdir()
            (installed / "concurrent-install.txt").write_text("another installation")
    elif failure == "rollback" and Path(source).name == "Previous.app":
        sys.exit(28)
    sys.exit(subprocess.call([sys.executable, *args]))
elif name == "rm":
    for path in args:
        if not path.startswith("-"):
            within_fixture(path)
    sys.exit(subprocess.call(["/bin/rm", *args]))
elif name == "open":
    if failure == "launch" and "-R" not in args:
        sys.exit(26)
else:
    sys.exit("Unexpected mock tool: " + name)
'''

MOCK_BUILD = r'''#!__PYTHON__
import json
import os
from pathlib import Path
import plistlib
import sys

with Path(os.environ["MELTORAMA_TEST_LOG"]).open("a") as log:
    log.write(json.dumps(["build-macos.sh", *sys.argv[1:]]) + "\n")
bundle = Path("dist/Meltorama.app/Contents")
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
(bundle / "Resources").mkdir(exist_ok=True)
with (bundle / "Info.plist").open("wb") as metadata:
    plistlib.dump({"CFBundleIdentifier": "ch.lkmc.goo.macos",
                  "CFBundleExecutable": "Meltorama",
                  "CFBundlePackageType": "APPL"}, metadata)
executable = bundle / "MacOS/Meltorama"
executable.write_text("#!/bin/sh\nexit 0\n")
executable.chmod(0o755)
(bundle / "Resources/version.txt").write_text("new version")
'''


class BuildScriptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="Meltorama build CLI ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / "Repository with spaces"
        self.script = self.repository / "scripts/build.sh"
        self.script.parent.mkdir(parents=True)
        self.install_dir = self.root / "Installed Applications"
        self.default_dir = self.root / "Default Applications"
        self.install_dir.mkdir()
        self.installed = self.install_dir / "Meltorama.app"
        contents = self.installed / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as metadata:
            plistlib.dump({"CFBundleIdentifier": "ch.lkmc.goo.macos",
                          "CFBundleExecutable": "Meltorama",
                          "CFBundlePackageType": "APPL"}, metadata)
        (contents / "MacOS/Meltorama").write_text("previous executable")
        (self.installed / "old-document.txt").write_text("previous version")
        self.previous_bundle = self.bundle_contents(self.installed)

        # Even a regressed script that ignores MELTORAMA_INSTALL_DIR must not
        # touch /Applications. Keep the fallback separate from the override so
        # the tests still catch an ignored installation destination.
        script = BUILD_SCRIPT.read_text().replace("/Applications", str(self.default_dir))
        self.script.write_text(script)
        self.script.chmod(0o755)
        build = self.repository / "scripts/build-macos.sh"
        build.write_text(MOCK_BUILD.replace("__PYTHON__", sys.executable))
        build.chmod(0o755)
        version_file = self.repository / "app/build.gradle.kts"
        version_file.parent.mkdir()
        version_file.write_text('versionName = "2.0.4"\n')

        tools = self.root / "Mock tools"
        tools.mkdir()
        for name in ("uname", "swift", "ditto", "codesign", "open", "python3", "rm"):
            tool = tools / name
            tool.write_text(MOCK_TOOL.replace("__PYTHON__", sys.executable))
            tool.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.environment = dict(os.environ)
        self.environment.update({
            "PATH": str(tools) + os.pathsep + os.environ["PATH"],
            "MELTORAMA_TEST_ROOT": str(self.root),
            "MELTORAMA_TEST_LOG": str(self.log),
            "MELTORAMA_INSTALL_DIR": str(self.install_dir),
            "MELTORAMA_TEST_FAILURE": "",
        })
        self.outside_cwd = self.root / "Unrelated working directory"
        self.outside_cwd.mkdir()

    @staticmethod
    def bundle_contents(bundle):
        return {str(path.relative_to(bundle)): path.read_bytes()
                for path in bundle.rglob("*") if path.is_file()}

    def invoke(self, *arguments, failure=""):
        environment = dict(self.environment, MELTORAMA_TEST_FAILURE=failure)
        return subprocess.run(["/bin/bash", str(self.script), *arguments],
                              cwd=self.outside_cwd, env=environment,
                              text=True, capture_output=True, timeout=15)

    def calls(self, tool):
        if not self.log.exists():
            return []
        return [call[1:] for line in self.log.read_text().splitlines()
                if (call := json.loads(line))[0] == tool]

    def assert_previous_bundle_preserved(self):
        self.assertTrue(self.installed.is_dir())
        self.assertEqual(self.bundle_contents(self.installed), self.previous_bundle)
        self.assertFalse(self.default_dir.exists(), "Installation override was ignored")

    def test_plain_install_succeeds_and_replaces_existing_app(self):
        result = self.invoke("--install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.installed / "Contents/Resources/version.txt").read_text(),
                         "new version")
        self.assertFalse((self.installed / "old-document.txt").exists())
        self.assertEqual(self.calls("build-macos.sh"), [[]])
        self.assertTrue(self.calls("codesign"), "Installed bundle was not verified")
        self.assertTrue(any("--verify" in call and "--strict" in call
                            for call in self.calls("codesign")))
        self.assertEqual(self.calls("open"), [["-R", str(self.installed)]])
        self.assertFalse(self.default_dir.exists(), "Installation override was ignored")

    def test_first_install_succeeds_without_existing_app(self):
        shutil.rmtree(self.installed)
        result = self.invoke("--install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.installed / "Contents/Resources/version.txt").read_text(),
                         "new version")
        self.assertEqual(self.calls("open"), [["-R", str(self.installed)]])

    def test_incomplete_copy_preserves_existing_app(self):
        result = self.invoke("--install", failure="copy")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.calls("ditto"), "Copy failure was not exercised")
        self.assert_previous_bundle_preserved()
        self.assertEqual(self.calls("open"), [])

    def test_signature_failure_preserves_existing_app(self):
        result = self.invoke("--install", failure="signature")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.calls("codesign"), "Verification failure was not exercised")
        self.assert_previous_bundle_preserved()
        self.assertEqual(self.calls("open"), [])

    def test_failed_replacement_restores_existing_app(self):
        result = self.invoke("--install", failure="replace")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_previous_bundle_preserved()
        moves = self.calls("python3")
        self.assertTrue(any(Path(call[-2]).name == "Previous.app" for call in moves),
                        "Replacement failure did not exercise rollback")
        self.assertEqual(self.calls("open"), [])

    def test_concurrent_destination_is_not_nested_or_deleted(self):
        result = self.invoke("--install", failure="race")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.bundle_contents(self.installed),
                         {"concurrent-install.txt": b"another installation"})
        backups = list(self.install_dir.rglob("Previous.app"))
        self.assertEqual(len(backups), 1, "Previous app was not retained for recovery")
        self.assertEqual(self.bundle_contents(backups[0]), self.previous_bundle)
        self.assertIn(str(backups[0]), result.stderr + result.stdout,
                      "Recovery location was not reported")
        self.assertEqual(self.calls("open"), [])

    def test_interrupted_replacement_restores_existing_app(self):
        result = self.invoke("--install", failure="interrupt")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_previous_bundle_preserved()
        self.assertEqual(list(self.install_dir.rglob("Previous.app")), [])
        self.assertEqual(self.calls("open"), [])

    def test_failed_rollback_keeps_previous_app_for_recovery(self):
        result = self.invoke("--install", failure="rollback")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.installed.exists())
        backups = list(self.install_dir.rglob("Previous.app"))
        self.assertEqual(len(backups), 1, "Previous app was not retained for recovery")
        self.assertEqual(self.bundle_contents(backups[0]), self.previous_bundle)
        self.assertIn(str(backups[0]), result.stderr + result.stdout,
                      "Recovery location was not reported")
        self.assertEqual(self.calls("open"), [])

    def test_install_and_run_propagates_launch_failure(self):
        result = self.invoke("--install", "--run", failure="launch")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.installed / "Contents/Resources/version.txt").is_file(),
                        result.stdout + result.stderr)
        self.assertEqual((self.installed / "Contents/Resources/version.txt").read_text(),
                         "new version")
        self.assertEqual(self.calls("open"), [[str(self.installed)]])

    def test_check_builds_and_installs_nothing(self):
        result = self.invoke("--install", "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls("build-macos.sh"), [])
        self.assertEqual(self.calls("ditto"), [])
        self.assertEqual(self.calls("codesign"), [])
        self.assertEqual(self.calls("python3"), [])
        self.assertEqual(self.calls("open"), [])
        self.assertFalse((self.repository / "dist").exists())
        self.assert_previous_bundle_preserved()
        self.assertIn(str(self.installed), result.stdout)

    def test_debug_install_forwards_profile_from_unrelated_cwd(self):
        result = self.invoke("app", "--debug", "--install")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls("build-macos.sh"), [["--debug"]])
        self.assertEqual((self.installed / "Contents/Resources/version.txt").read_text(),
                         "new version")
        self.assertFalse((self.outside_cwd / "dist").exists())


if __name__ == "__main__":
    unittest.main()
