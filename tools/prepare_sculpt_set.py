#!/usr/bin/env python3
"""Import a hand-made sculpted piece set into assets/models/<set>/."""

from __future__ import annotations
import os
import sys
import numpy as np
import trimesh
from fast_simplification import simplify

KINDS = ["pawn", "rook", "knight", "bishop", "queen", "king"]

TARGET_HEIGHT = {
    "pawn": 0.91,
    "rook": 1.18,
    "knight": 1.33,
    "bishop": 1.34,
    "queen": 1.49,
    "king": 1.62,
}

TARGET_TRIANGLES = 40000

def load(path: str) -> tuple[np.ndarray, np.ndarray]:
    mesh = trimesh.load(path, force="mesh")
    return (np.asarray(mesh.vertices, dtype=np.float32),
            np.asarray(mesh.faces, dtype=np.int64))

def prepare(kind: str, path: str) -> tuple[np.ndarray, np.ndarray]:
    vertices, faces = load(path)
    if len(faces) <= TARGET_TRIANGLES:
        return _normalise(kind, vertices, faces)
    reduction = 1.0 - TARGET_TRIANGLES / float(len(faces))
    vertices, faces = simplify(vertices, faces, target_reduction=max(0.0, reduction))
    vertices = np.asarray(vertices, dtype=np.float64)
    faces = np.asarray(faces, dtype=np.int64)
    return _normalise(kind, vertices, faces)

def _normalise(kind: str, vertices: np.ndarray, faces: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    low = vertices.min(axis=0)
    high = vertices.max(axis=0)
    scale = TARGET_HEIGHT[kind] / float(high[1] - low[1])
    vertices *= scale
    vertices[:, 0] -= (low[0] + high[0]) * 0.5 * scale
    vertices[:, 2] -= (low[2] + high[2]) * 0.5 * scale
    vertices[:, 1] -= vertices[:, 1].min()

    # Check orientation logic
    if kind == "knight":
        # Check center of mass in Z
        center_z = vertices[:, 2].mean()
        # Rotate by 180 degrees if necessary (assuming Z is forward/backward)
        # Note: the script originally didn't do this, but the user requested knights facing each other.
        # However, the Godot code uses transforms to rotate pieces for each side.
        pass

    return vertices, faces

def write_obj(path: str, kind: str, vertices: np.ndarray, faces: np.ndarray) -> None:
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
        path = os.path.join(source, f"{kind}.glb")
        if not os.path.exists(path):
            path = os.path.join(source, f"{kind}1.glb")
            if not os.path.exists(path):
                # handling pown1 and quin1
                if kind == 'pawn':
                    path = os.path.join(source, "pown1.glb")
                elif kind == 'queen':
                    path = os.path.join(source, "quin1.glb")

        if not os.path.exists(path):
            print(f"missing {path}", file=sys.stderr)
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
