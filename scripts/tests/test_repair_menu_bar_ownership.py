import copy
import contextlib
import importlib.util
import io
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "repair_menu_bar_ownership", Path(__file__).parents[1] / "repair_menu_bar_ownership.py"
)
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


def location(bundle_id):
    return {"bundle": {"_0": bundle_id}}


def record(owner, references, allowed=True):
    return {"location": owner, "menuItemLocations": references, "isAllowed": allowed}


class MenuBarOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.toolbar = copy.deepcopy(repair.TOOLBAR_LOCATION)
        self.host = location("com.openai.codex")
        self.other = location("another.app")
        self.adhoc = {"adhocBinary": {"_0": {"relative": "file:///old/CodexToolbar"}}}
        self.entries = [
            self.toolbar, record(self.toolbar, [self.adhoc], allowed=False),
            self.host, record(self.host, [self.other, self.toolbar, self.host]),
            self.other, record(self.other, [self.other], allowed=False),
        ]
        self.entries[3]["futureField"] = {"preserve": True}

    def run_repair(self, entries=None):
        return repair.repair_ownership(plistlib.dumps(entries if entries is not None else self.entries))

    def test_moves_only_toolbar_reference_and_preserves_visibility_choices(self):
        data, changes = self.run_repair()
        result = plistlib.loads(data)
        expected = copy.deepcopy(self.entries)
        expected[1]["menuItemLocations"].append(self.toolbar)
        expected[3]["menuItemLocations"].remove(self.toolbar)
        self.assertEqual(result, expected)
        self.assertEqual(len(changes), 2)

    def test_repeated_repair_is_a_no_op_and_keeps_original_bytes(self):
        once, _ = self.run_repair()
        twice, changes = repair.repair_ownership(once)
        self.assertEqual(twice, once)
        self.assertEqual(changes, [])

    def test_removes_duplicate_foreign_references_without_duplicating_own_reference(self):
        self.entries[1]["menuItemLocations"].append(self.toolbar)
        self.entries[3]["menuItemLocations"].append(self.toolbar)
        result = plistlib.loads(self.run_repair()[0])
        self.assertEqual(result[1]["menuItemLocations"].count(self.toolbar), 1)
        self.assertNotIn(self.toolbar, result[3]["menuItemLocations"])

    def test_refuses_missing_or_duplicate_toolbar_record(self):
        for entries in (self.entries[2:], self.entries + self.entries[:2]):
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.run_repair(entries)

    def test_refuses_unrecognized_formats(self):
        malformed_record = copy.deepcopy(self.entries)
        malformed_record[3]["location"] = self.other
        for entries in ({"different": "format"}, self.entries[:-1], malformed_record):
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.run_repair(entries)

    def test_preview_does_not_write_preferences_or_create_backups(self):
        preferences = {"trackedApplications": plistlib.dumps(self.entries), "showWeather": True}
        with tempfile.TemporaryDirectory() as directory:
            backup_dir = Path(directory) / "backup"
            with (
                mock.patch("sys.argv", ["repair", "--backup-dir", str(backup_dir)]),
                mock.patch.object(repair, "read_preferences", return_value=preferences),
                mock.patch.object(repair.subprocess, "run") as run,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                repair.main()
            run.assert_not_called()
            self.assertFalse(backup_dir.exists())

    def test_apply_backs_up_before_writing_only_the_ownership_key(self):
        before = plistlib.dumps(self.entries)
        after, _ = repair.repair_ownership(before)
        preferences = {"trackedApplications": before, "showWeather": True}
        expected = {**preferences, "trackedApplications": after}
        with tempfile.TemporaryDirectory() as directory:
            backup_dir = Path(directory) / "backup"

            def check_backup_before_mutation(*args, **kwargs):
                self.assertEqual((backup_dir / "trackedApplications.before.plist").read_bytes(), before)
                self.assertEqual(plistlib.loads((backup_dir / "preferences.before.plist").read_bytes()), preferences)
                for path in backup_dir.iterdir():
                    self.assertEqual(path.stat().st_mode & 0o777, 0o600)

            with (
                mock.patch("sys.argv", ["repair", "--apply", "--backup-dir", str(backup_dir)]),
                mock.patch.object(repair, "read_preferences", side_effect=[preferences, preferences, expected]),
                mock.patch.object(repair.subprocess, "run", side_effect=check_backup_before_mutation) as run,
                contextlib.redirect_stdout(io.StringIO()),
            ):
                repair.main()
            self.assertEqual(run.call_args_list, [
                mock.call([
                    "/usr/bin/defaults", "write", str(repair.PREFERENCES_DOMAIN),
                    "trackedApplications", "-data", after.hex(),
                ], check=True),
                mock.call(["/usr/bin/killall", "ControlCenter"], check=True),
            ])
            self.assertEqual((backup_dir / "trackedApplications.after.plist").read_bytes(), after)

    def test_apply_refuses_to_overwrite_a_changed_preference_snapshot(self):
        preferences = {"trackedApplications": plistlib.dumps(self.entries), "showWeather": True}
        changed = {**preferences, "showWeather": False}
        with tempfile.TemporaryDirectory() as directory:
            backup_dir = Path(directory) / "backup"
            with (
                mock.patch("sys.argv", ["repair", "--apply", "--backup-dir", str(backup_dir)]),
                mock.patch.object(repair, "read_preferences", side_effect=[preferences, changed]),
                mock.patch.object(repair.subprocess, "run") as run,
                contextlib.redirect_stdout(io.StringIO()),
                self.assertRaisesRegex(RuntimeError, "preferences changed"),
            ):
                repair.main()
            run.assert_not_called()
            self.assertTrue((backup_dir / "preferences.before.plist").exists())


if __name__ == "__main__":
    unittest.main()
