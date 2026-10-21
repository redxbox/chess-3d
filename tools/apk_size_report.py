#!/usr/bin/env python3
"""Print a package-size table for a built APK or AAB, plus a total.

Used by CI right after the Android build, where the real number exists.

    python3 tools/apk_size_report.py build/android/chess-3d.apk

The `method` column matters. Godot's arm64 library is most of the package, and
a Gradle build stores it uncompressed unless the export preset sets
`gradle_build/compress_native_libraries=true` - so a `STORED` in that column is
the difference between a ~50 MB APK and a ~33 MB one, and it is checkable here
instead of guessed at.
"""

import os
import sys
import zipfile

TOP_ENTRIES = 14
BUDGET_BYTES = 40 * 1024 * 1024


def describe(entry):
    method = "STORED" if entry.compress_type == zipfile.ZIP_STORED else "deflated"
    return entry.file_size, method, entry.filename


def main(argv):
    positional = [item for item in argv if not item.startswith("-")]
    if len(positional) != 1:
        print("usage: apk_size_report.py <apk-or-aab> [--annotate]", file=sys.stderr)
        return 2
    path = positional[0]
    with zipfile.ZipFile(path) as package:
        infos = package.infolist()
        entries = sorted((describe(info) for info in infos), reverse=True)
    uncompressed = sum(size for size, _, _ in entries)
    compressed = sum(info.compress_size for info in infos)
    on_disk = os.path.getsize(path)

    print("| entry | method | size |")
    print("| --- | --- | --- |")
    for size, method, name in entries[:TOP_ENTRIES]:
        print(f"| `{name}` | {method} | {size / 1024:.0f} KB |")
    print(f"| **uncompressed total** | | **{uncompressed / 1e6:.2f} MB** |")
    print(f"| **compressed payload** | | **{compressed / 1e6:.2f} MB** |")
    print(f"| **file on disk** | | **{on_disk / 1e6:.2f} MB** |")

    # CI turns these into step annotations, which the API can read back - the
    # job summary cannot be. The compression method of the engine library is the
    # one number that says whether the preset option took effect.
    if "--annotate" in argv[2:] or "-a" in argv[2:]:
        for info in infos:
            if info.file_size >= 2_000_000:
                method = "STORED" if info.compress_type == zipfile.ZIP_STORED else "deflated"
                # stderr, because CI redirects the table to a file and the log
                # is what the workflow command has to reach.
                print(f"::notice title=Native library::{info.filename} {method}: "
                      f"{info.file_size / 1e6:.2f} MB uncompressed, "
                      f"{info.compress_size / 1e6:.2f} MB in the package", file=sys.stderr)

    stored_libraries = [name for size, method, name in entries
                        if method == "STORED" and name.endswith(".so")]
    if stored_libraries:
        print("\n> The native library is stored uncompressed. Set "
              "`gradle_build/compress_native_libraries=true` in export_presets.cfg.",
              file=sys.stderr)
    if on_disk > BUDGET_BYTES:
        print(f"over the {BUDGET_BYTES / 1048576:.0f} MiB package budget", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
