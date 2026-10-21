#!/usr/bin/env python3
"""Import a hand-made sculpted piece set into assets/models/<set>/.

WHY THIS EXISTS
---------------
Two sets of six GLB files were supplied by the project author - "medieval" (the
one uploaded to the repository root, one file per piece, 200-320k vertices and
about 10 MB each) and "persian" (the older set recovered from the
assets/models/persian/ folder of an earlier branch). Neither can be used as it
is: 56 MB for the first set is more than a mobile game can afford for its
pieces, and a Godot import of half a million triangles per piece would stall
startup on a phone.

Both sets arrive the same way: geometry only, no materials, no UVs, and every
piece exactly 1.0 unit tall - so a pawn would stand as tall as a king.

This script does the three conversions that turn them into a usable set:

1. Decimate. Every piece is reduced to TARGET_TRIANGLES with
   fast-simplification, which keeps the silhouette and the carved surface but
   drops the triangle count by roughly 60x. The other bodies in this project are
   5-16k triangles; this set lands in the same band.

2. Put it on the board's scale. The uploaded models are all exactly 1.0 unit
   tall, whatever the piece, so they cannot simply be dropped in: a pawn would
   be as tall as a king. Each one is scaled to the height the shipped set uses
   (pawn 0.91 up to king 1.62), so the two sets can stand on the same board and
   in the same squares.

3. Write OBJ with vertex normals. The project loads its bodies as OBJ meshes
   with `preload`; OBJ also keeps the file readable in the diff. Normals are
   area-weighted and averaged so the carving shades smoothly instead of
   faceting - the uploaded meshes arrive without any normal data.

The set is stored the way the game expects: +Y up, standing on y = 0, centred on
the origin in X/Z. Fragments are not merged or repaired: the source sculptures
have a couple of open shells (the rook, the knight and the king are not
watertight), and decimation of an open shell is still a correct render - it is
only shadows from inside that would care, and chess pieces are lit from outside.

DEPENDENCIES (build-time only; the generated OBJs are committed)
----------------------------------------------------------------
    pip install numpy trimesh fast-simplification

Run:  python3 tools/prepare_sculpt_set.py [source_dir] [output_dir]

    python3 tools/prepare_sculpt_set.py /tmp/uploaded_glb   assets/models/medieval
    python3 tools/prepare_sculpt_set.py /tmp/persian_glb    assets/models/persian
"""

from __future__ import annotations

import os
import sys

import numpy as np
import trimesh
from fast_simplification import simplify

KINDS = ["pawn", "rook", "knight", "bishop", "queen", "king"]

# The height ladder of the shipped Staunton set, in board units. The squares are
# 1.0 across, so these are also the numbers the rest of the game is tuned
# against - the ornate trim layer, the camera framing and the piece sprites.
TARGET_HEIGHT = {
    "pawn": 0.91,
    "rook": 1.18,
    "knight": 1.33,
    "bishop": 1.34,
    "queen": 1.49,
    "king": 1.62,
}

# Roughly the triangle budget of the Staunton knight, which is generous for a
# piece that is fully sculpted rather than assembled from a lathe and a crown.
TARGET_TRIANGLES = 10000


def load(path: str) -> tuple[np.ndarray, np.ndarray]:
    mesh = trimesh.load(path, force="mesh")
    return (np.asarray(mesh.vertices, dtype=np.float32),
            np.asarray(mesh.faces, dtype=np.int64))


def prepare(kind: str, path: str) -> tuple[np.ndarray, np.ndarray]:
    vertices, faces = load(path)
    # The two sets are not equally dense: the persian pieces arrive already
    # decimated (6k-26k triangles) while the medieval ones arrive at 370k-650k.
    # Only decimate downwards, never upwards, and never re-simplify a piece
    # that is already under budget - it would only cost detail.
    if len(faces) <= TARGET_TRIANGLES:
        return _normalise(kind, vertices, faces)
    reduction = 1.0 - TARGET_TRIANGLES / float(len(faces))
    vertices, faces = simplify(vertices, faces, target_reduction=max(0.0, reduction))
    vertices = np.asarray(vertices, dtype=np.float64)
    faces = np.asarray(faces, dtype=np.int64)
    return _normalise(kind, vertices, faces)


def _normalise(kind: str, vertices: np.ndarray, faces: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Put a piece on the board's scale: target height, feet on y = 0, centred."""
    low = vertices.min(axis=0)
    high = vertices.max(axis=0)
    # Uniform scale, from the model's own height, so the carving keeps its
    # proportions. Height is the only thing normalised - the foot ends up
    # between 0.31 and 0.43 across, which is wider than the Staunton set's 0.326
    # and is exactly what makes this set look carved rather than turned. Two
    # neighbouring squares are 1.0 apart, so even the widest pair (0.43 + 0.43)
    # cannot touch.
    scale = TARGET_HEIGHT[kind] / float(high[1] - low[1])
    vertices *= scale
    # Stand it on y = 0 and put its own centre over the square's centre.
    vertices[:, 0] -= (low[0] + high[0]) * 0.5 * scale
    vertices[:, 2] -= (low[2] + high[2]) * 0.5 * scale
    vertices[:, 1] -= vertices[:, 1].min()
    return vertices, faces


def write_obj(path: str, kind: str, vertices: np.ndarray, faces: np.ndarray) -> None:
    # Positions and faces only, exactly like the Staunton OBJs: _piece_mesh()
    # welds the export's duplicated vertices and generates one smooth normal per
    # corner plus a cylindrical UV set. Writing normals here as well would add
    # 45% to the file for data that is thrown away and recomputed at load.
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(f"# Medieval {kind}, decimated by tools/prepare_medieval_set.py\n")
        handle.write("# Source: user-supplied GLB, see assets/models/<set>/README.md\n")
        handle.write(f"o {kind}\n")
        for point in vertices:
            handle.write(f"v {point[0]:.5f} {point[1]:.5f} {point[2]:.5f}\n")
        for face in faces:
            a, b, c = face + 1
            handle.write(f"f {a} {b} {c}\n")


def main() -> int:
    source = sys.argv[1] if len(sys.argv) > 1 else "."
    output = sys.argv[2] if len(sys.argv) > 2 else "assets/models/medieval"
    os.makedirs(output, exist_ok=True)
    for kind in KINDS:
        # A piece may arrive under a slightly different file name - the
        # replacement king that was uploaded for the Persian set is kinge.glb -
        # so both spellings are accepted rather than making the author rename
        # their export.
        candidates = [os.path.join(source, f"{kind}.glb"), os.path.join(source, f"{kind}e.glb")]
        path = next((candidate for candidate in candidates if os.path.exists(candidate)), "")
        if path == "":
            print(f"missing {candidates[0]}", file=sys.stderr)
            return 1
        vertices, faces = prepare(kind, path)
        target = os.path.join(output, f"{kind}.obj")
        write_obj(target, kind, vertices, faces)
        low, high = vertices.min(axis=0), vertices.max(axis=0)
        print(f"{kind:7s} {len(faces):6d} tris  height {high[1]:.3f}  "
              f"width {high[0] - low[0]:.3f}  depth {high[2] - low[2]:.3f}  "
              f"{os.path.getsize(target) // 1024} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
