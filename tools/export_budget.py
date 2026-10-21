#!/usr/bin/env python3
"""Report what the Android build actually carries, without needing Godot.

WHY THIS EXISTS
---------------
The APK is dominated by the engine's arm64 library, which this repository does
not build. Everything we do control - the piece meshes, the audio, the scripts
and (historically) a 7.6 MB source GLB that sat in `assets/` and went straight
into the package - is what this script measures. It exists so a size regression
is caught in the pull request that causes it, instead of on a phone.

WHAT IT COUNTS
--------------
* Meshes. Godot imports every `assets/models/**/*.obj` into an ArrayMesh: 12
  bytes of position and 12 bytes of normal per vertex plus 4 bytes per triangle
  of index. That is the size that lands in the PCK, not the size of the OBJ
  text, which is why the thousands of ASCII decimals in the source files are
  not what the player downloads.
* Audio. A `.wav` is stored as 16-bit PCM and an `.ogg` is stored as the Vorbis
  stream it already is, so the file size is the shipped size.
* Scripts. Exported in compressed binary-token form, which measures at roughly
  half the source size.
* Everything else under the export filter - the icon, the scene, the project
  settings - is a rounding error and is reported as a fixed allowance.

A file under `assets/` whose extension has no importer - a stray `.glb`, `.zip`
or `.blend` - is reported as SHIPPED AS-IS rather than ignored, because
`export_filter="all_resources"` plus a file Godot does not import is exactly how
the 7.6 MB king export would have reached the package.

USAGE
-----
    python3 tools/export_budget.py            # report, non-zero if over budget
    python3 tools/export_budget.py -v         # per-file breakdown
"""

import glob
import os
import sys

# What the packaged content may weigh. The engine library is not counted here;
# this is the part this repository decides, and it is only about a sixth of the
# APK - the arm64 template is the rest.
#
# Before the cleanup this was 5.1 MB: 3.87 MB of mesh, 0.61 MB of audio (the
# 12-second music loop was raw PCM) and a preview material script that shipped
# from src/. It is 4.34 MB now. The mesh is deliberately not decimated to make
# the number prettier: the two sculpted sets were already reduced from 420k
# triangles to 10k, and the faceting is visible at that size on a phone.
BUDGET_BYTES = 4_600_000

# Extensions Godot imports into something smaller or different. Anything else
# under assets/ is copied verbatim or, if it has no importer, ignored - but the
# projection below is deliberately pessimistic and counts it.
IMPORTED = {".obj", ".wav", ".ogg", ".svg", ".tscn", ".tres", ".gd", ".glb", ".gltf"}
# glTF is *imported*, not ignored: Godot turns a .glb into a PackedScene with an
# ArrayMesh in it, and the imported resource is in the package whether or not a
# script ever loads it. The six-piece upload that arrived this way weighed 36 MB
# as source and would have added roughly that to the APK. A .glb under assets/
# is never a source file - sources belong in tools/sources/.
SOURCE_FORMATS = {".glb", ".gltf", ".blend", ".fbx", ".zip"}
# Extensions that are pure documentation and are never exported.
IGNORED = {".md", ".txt"}


def mesh_bytes(path):
    vertices = 0
    triangles = 0
    with open(path, "r", errors="ignore") as handle:
        for line in handle:
            if line.startswith("v "):
                vertices += 1
            elif line.startswith("f "):
                triangles += 1
    return vertices * 24 + triangles * 12, vertices, triangles


def collect():
    rows = []
    for path in sorted(glob.glob("assets/**/*", recursive=True)):
        if os.path.isdir(path):
            continue
        extension = os.path.splitext(path)[1].lower()
        if extension in IGNORED:
            continue
        size = os.path.getsize(path)
        note = ""
        vertices = triangles = 0
        if extension == ".obj":
            size, vertices, triangles = mesh_bytes(path)
            note = f"{vertices} verts, {triangles} tris"
        elif extension in SOURCE_FORMATS:
            # Imported into a mesh and shipped with the package. Counted at 60%
            # of the source file, which is what a decimated glTF export measured
            # against its OBJ at the same triangle count.
            size = int(size * 0.6)
            note = "SOURCE EXPORT - importable, so it ships; move it to tools/sources/"
        elif extension not in IMPORTED:
            note = "SHIPPED AS-IS - no importer"
        rows.append({"path": path, "bytes": size, "note": note})

    for path in sorted(glob.glob("src/**/*.gd", recursive=True)):
        rows.append({"path": path, "bytes": os.path.getsize(path) // 2,
                     "note": "compiled to binary tokens, estimated at half the source"})

    # The scene, the icon (already counted above), and the project settings.
    rows.append({"path": "project.godot + main.tscn", "bytes": 40_000, "note": "allowance"})
    return rows


def main(argv):
    verbose = "-v" in argv or "--verbose" in argv
    rows = collect()
    total = sum(row["bytes"] for row in rows)
    for row in sorted(rows, key=lambda item: -item["bytes"]):
        if verbose or row["bytes"] >= 100_000:
            print(f"  {row['bytes'] / 1024:8.1f} KB  {row['path']:<46s} {row['note']}")
    shipped = [row for row in rows if "SHIPPED AS-IS" in row["note"]
               or "SOURCE EXPORT" in row["note"]]
    print(f"\n  packaged content estimate: {total / 1e6:.2f} MB "
          f"(budget {BUDGET_BYTES / 1e6:.2f} MB)")
    for row in shipped:
        print(f"  WARNING: {row['path']} - {row['note']} "
              f"({row['bytes'] / 1e6:.2f} MB)", file=sys.stderr)
    if shipped:
        print("  A raw export under assets/ reaches the package. Sources belong in "
              "tools/sources/, which the export presets exclude.", file=sys.stderr)
    if total > BUDGET_BYTES:
        print(f"  OVER BUDGET by {(total - BUDGET_BYTES) / 1e6:.2f} MB", file=sys.stderr)
        return 1
    print("  within budget")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
