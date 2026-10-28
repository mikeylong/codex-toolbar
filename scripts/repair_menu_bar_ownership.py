#!/usr/bin/env python3
"""Preview or repair CodexToolbar's cached macOS menu bar ownership."""

import argparse
import copy
import datetime
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess


BUNDLE_ID = "com.mikelong.codextoolbar"
TOOLBAR_LOCATION = {"bundle": {"_0": BUNDLE_ID}}
PREFERENCES_DOMAIN = (
    Path.home()
    / "Library/Group Containers/group.com.apple.controlcenter/Library/Preferences"
    / "group.com.apple.controlcenter"
)


def repair_ownership(data):
    """Move only the toolbar's signed bundle reference to its own record.

    Control Center encodes this dictionary as alternating location/record pairs.
    Its format is undocumented; refuse unfamiliar data rather than resetting it.
    """
    entries = plistlib.loads(data)
    if not isinstance(entries, list) or len(entries) % 2:
        raise ValueError("Unrecognized trackedApplications format; nothing changed.")

    repaired = copy.deepcopy(entries)
    toolbar_records = []
    changes = []
    for index in range(0, len(repaired), 2):
        location, record = repaired[index : index + 2]
        if (
            not isinstance(location, dict)
            or not isinstance(record, dict)
            or record.get("location") != location
            or not isinstance(record.get("menuItemLocations"), list)
            or not isinstance(record.get("isAllowed"), bool)
        ):
            raise ValueError("Unrecognized application record; nothing changed.")
        if location == TOOLBAR_LOCATION:
            toolbar_records.append(record)
            continue

        references = record["menuItemLocations"]
        filtered = [reference for reference in references if reference != TOOLBAR_LOCATION]
        if filtered != references:
            record["menuItemLocations"] = filtered
            changes.append({"removeToolbarReferenceFrom": location})

    if len(toolbar_records) != 1:
        raise ValueError("Expected one CodexToolbar record; launch the installed app first.")

    references = toolbar_records[0]["menuItemLocations"]
    if TOOLBAR_LOCATION not in references:
        references.append(copy.deepcopy(TOOLBAR_LOCATION))
        changes.append({"addToolbarReferenceTo": TOOLBAR_LOCATION})

    if not changes:
        return data, changes
    return plistlib.dumps(repaired, fmt=plistlib.FMT_BINARY, sort_keys=False), changes


def read_preferences():
    # The bare group domain resolves to a different file for the defaults CLI.
    result = subprocess.run(
        ["/usr/bin/defaults", "export", str(PREFERENCES_DOMAIN), "-"],
        check=True,
        capture_output=True,
    )
    preferences = plistlib.loads(result.stdout)
    if not isinstance(preferences.get("trackedApplications"), bytes):
        raise ValueError("Control Center's trackedApplications data was not found.")
    return preferences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Back up and apply the previewed repair")
    parser.add_argument("--backup-dir", type=Path, help="New local directory for the preference backup")
    args = parser.parse_args()

    preferences = read_preferences()
    before = preferences["trackedApplications"]
    after, changes = repair_ownership(before)
    print(json.dumps(changes, indent=2))
    if not changes:
        print("CodexToolbar already owns its menu bar item. Nothing changed.")
        return
    if not args.apply:
        print("Preview only. Use --apply to back up and repair these references.")
        return

    backup_dir = args.backup_dir or (
        Path(__file__).resolve().parent.parent
        / "dist/menu-bar-ownership"
        / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    )
    backup_dir = backup_dir.resolve()
    backup_dir.mkdir(parents=True, exist_ok=False, mode=0o700)
    for name, contents in (
        ("preferences.before.plist", plistlib.dumps(preferences)),
        ("trackedApplications.before.plist", before),
        ("trackedApplications.after.plist", after),
    ):
        with (backup_dir / name).open("xb") as output:
            os.fchmod(output.fileno(), 0o600)
            output.write(contents)
    print(f"Backup: {backup_dir}")

    if read_preferences() != preferences:
        raise RuntimeError("Menu bar preferences changed during the preview; rerun the repair.")
    subprocess.run(
        ["/usr/bin/defaults", "write", str(PREFERENCES_DOMAIN), "trackedApplications", "-data", after.hex()],
        check=True,
    )
    expected = {**preferences, "trackedApplications": after}
    if read_preferences() != expected:
        raise RuntimeError(f"Preference verification failed. Backup retained at {backup_dir}.")

    subprocess.run(["/usr/bin/killall", "ControlCenter"], check=True)
    if int(platform.mac_ver()[0].split(".")[0]) >= 27:
        # macOS 27 hosts status items here. Its cached catalog can otherwise
        # write the old ownership back when System Settings opens again.
        subprocess.run(["/usr/bin/killall", "MenuBarAgent"], check=True)
    print("Ownership repaired and verified. Menu bar hosts are restarting to reload the records.")


if __name__ == "__main__":
    main()
