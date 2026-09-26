#!/usr/bin/env python3
"""Check Records scale changes on an explicitly selected Android device (English UI).

Usage: python3 scripts/check-android-records-navigation.py --serial DEVICE --adb /path/to/adb
Exercises the installed app's actual controls, with either free or Plus access.
Only changes navigation; never edits records, salary, or entitlement settings.
"""

import argparse
import re
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb", default="adb")
    args = parser.parse_args()
    names = ("Week", "Month", "Year", "Life")

    def adb(*parts):
        return subprocess.check_output([args.adb, "-s", args.serial, *parts], text=True, timeout=30)

    def picker():
        # Read XML in memory; do not save or print any personal chart contents.
        output = adb("exec-out", "uiautomator", "dump", "/dev/tty")
        start = output.find("<?xml")
        end = output.find("</hierarchy>")
        if start < 0 or end < 0:
            raise RuntimeError("Could not read the active UI")
        root = ET.fromstring(output[start:end + len("</hierarchy>")])
        for node in root.iter("node"):
            buttons = [child for child in node if child.get("checkable") == "true"]
            if len(buttons) == 4:
                labels = {next((e.get("text") for e in button.iter("node") if e.get("text") in names), None): button for button in buttons}
                if set(labels) != set(names):
                    continue
                # Compose moves the checked button last in drawing order.
                buttons = [labels[name] for name in names]
                selected = [i for i, button in enumerate(buttons) if button.get("checked") == "true"]
                if len(selected) == 1:
                    return buttons, selected[0]
        raise RuntimeError("Records scale picker is not visible; finish setup and use the English app UI")

    def select(index):
        buttons, _ = picker()
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", buttons[index].get("bounds")))
        adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
        time.sleep(0.3)
        _, selected = picker()
        if selected != index:
            raise AssertionError(f"Tapped {names[index]}, but {names[selected]} stayed selected")
        print(f"PASS: {names[index]}", flush=True)

    adb("shell", "am", "start", "-n", "com.rainif.doneat/.MainActivity", "--es", "com.rainif.doneat.TAB", "records")
    time.sleep(1)
    for attempt in range(3):
        try:
            _, initial = picker()
            break
        except RuntimeError:
            if attempt == 2:
                raise
            time.sleep(1)
    print(f"Initial scale: {names[initial]}", flush=True)
    # Return to the scale captured when the page first appeared. This catches
    # stale local function references even when the stored preference is Life.
    select((initial + 1) % 4)
    select(initial)
    for index in (1, 0, 1, 2, 1, 3, 1, initial):
        select(index)


if __name__ == "__main__":
    main()
