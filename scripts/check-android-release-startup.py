#!/usr/bin/env python3
"""Cold-start the installed, non-debuggable DoneAt build on an explicit device.

Does not clear app data. Run on an emulator/test device after installing a signed
Release APK; a Debug launch cannot catch constructors removed by R8.
"""

import argparse
import subprocess
import time
import xml.etree.ElementTree as ET


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--adb", default="adb")
    args = parser.parse_args()
    package = "com.rainif.doneat"

    def adb(*parts):
        return subprocess.check_output(
            [args.adb, "-s", args.serial, *parts], text=True, timeout=30
        )

    if "DEBUGGABLE" in adb("shell", "dumpsys", "package", package):
        raise RuntimeError("Install a non-debuggable Release APK before this check")
    adb("shell", "am", "force-stop", package)
    result = adb("shell", "am", "start", "-W", "-n", package + "/.MainActivity")
    if "Status: ok" not in result:
        raise RuntimeError("Activity launch failed")
    time.sleep(2)
    output = adb("exec-out", "uiautomator", "dump", "/dev/tty")
    start, end = output.find("<?xml"), output.find("</hierarchy>")
    if start < 0 or end < 0:
        raise RuntimeError("Could not read the active UI")
    root = ET.fromstring(output[start:end + len("</hierarchy>")])
    if not any(node.get("package") == package for node in root.iter("node")):
        raise RuntimeError("DoneAt has no visible UI after cold start; inspect crash logcat")
    if not adb("shell", "pidof", package).strip():
        raise RuntimeError("DoneAt exited after launch")
    print("PASS: non-debuggable Release survived cold start and rendered its UI")


if __name__ == "__main__":
    main()
