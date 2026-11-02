#!/usr/bin/env python3
"""Refuse to ship anything that is not a runtime asset.

The package grew past 70 MB at one point, and the reason was not the engine: six
raw GLB sculpts (36 MB) had been uploaded straight into `assets/models/` next to
the OBJs the game actually loads, and the export filter packs everything under
`assets/`. They were never read by a single line of code.

This is the guard against that happening again. It fails when a file under
`assets/` is

  * a modelling source (.glb, .gltf, .blend, .fbx, .dae, .obj.bak, .psd), or
  * larger than a per-file ceiling that no runtime asset needs.

Run it from the workflow before the export, and locally before a commit.

    python3 tools/check_shipped_assets.py
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")

SOURCE_SUFFIXES = (".glb", ".gltf", ".blend", ".fbx", ".dae", ".psd", ".max", ".ma", ".mb")
# A piece mesh is 300 KB and a texture map is generated at runtime, so nothing
# legitimate in this project is close to 2 MB.
MAX_BYTES = 2 * 1024 * 1024
# The one exception, because it is the soundtrack and it is packed on purpose.
ALLOWED = {"assets/audio/ambient.ogg"}


def main() -> int:
    problems = []
    biggest = (0, "")
    for directory, _, files in os.walk(ASSETS):
        for name in files:
            path = os.path.join(directory, name)
            relative = os.path.relpath(path, ROOT)
            size = os.path.getsize(path)
            if size > biggest[0]:
                biggest = (size, relative)
            if relative in ALLOWED:
                continue
            if name.lower().endswith(SOURCE_SUFFIXES):
                problems.append(f"{relative}: modelling source inside assets/ ({size / 1e6:.1f} MB)")
            elif size > MAX_BYTES:
                problems.append(f"{relative}: {size / 1e6:.1f} MB is over the 2 MB per-asset ceiling")
    print(f"largest asset: {biggest[1]} - {biggest[0] / 1e6:.2f} MB")
    if problems:
        print("\nThese would be packed into the APK:", file=sys.stderr)
        for problem in problems:
            print("  " + problem, file=sys.stderr)
        print("\nMove sources to tools/sources/ (excluded from the export).", file=sys.stderr)
        return 1
    print("no modelling sources or oversized files under assets/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
