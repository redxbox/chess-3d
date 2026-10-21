#!/usr/bin/env python3
"""Print a package-size table for a built APK or AAB, plus the total.

Used by CI right after the Android build, where the real number exists. Godot's
arm64 template is most of the APK; what this table is for is the entries that
are ours, so a growing asset is visible in the run that introduced it.

    python3 tools/apk_size_report.py build/android/chess-3d.apk
"""

import sys
import zipfile

TOP_ENTRIES = 14


def main(argv):
    if len(argv) != 1:
        print("usage: apk_size_report.py <apk-or-aab>", file=sys.stderr)
        return 2
    with zipfile.ZipFile(argv[0]) as package:
        entries = sorted(((item.file_size, item.filename) for item in package.infolist()),
                         reverse=True)
    packed = sum(size for size, _ in entries)
    print("| entry | size |")
    print("| --- | --- |")
    for size, name in entries[:TOP_ENTRIES]:
        print(f"| `{name}` | {size / 1024:.0f} KB |")
    print(f"| **uncompressed total** | **{packed / 1e6:.2f} MB** |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
