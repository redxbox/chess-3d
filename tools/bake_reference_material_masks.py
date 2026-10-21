#!/usr/bin/env python3
"""Bake user-supplied finish references into mobile GLB vertex masks.

COLOR.r preserves the existing curvature bake. COLOR.g stores polished gold and
COLOR.b stores dark engraved/inlay coverage. The runtime shader consumes these
semantic masks without UVs, texture fetches, or bundled reference photographs.

Run from the repository root with Pillow, NumPy, and trimesh installed:
  python tools/bake_reference_material_masks.py /path/to/reference-images
"""
from __future__ import annotations

import colorsys
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
import trimesh

ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "assets/models/persian/candidate2/optimized"
REFERENCES = {
    "rook": ("rook.png", (0.16, 0.87, 0.09, 0.90), "x"),
    "king": ("king.png", (0.16, 0.85, 0.01, 0.96), "x"),
    "queen": ("وزیر.png", (0.17, 0.84, 0.01, 0.97), "x"),
    "knight": ("اسب.png", (0.18, 0.84, 0.01, 0.94), "z"),
    "bishop": ("فیل.png", (0.21, 0.79, 0.01, 0.95), "x"),
    "pawn": ("سرباز.png", (0.22, 0.78, 0.02, 0.94), "x"),
}


def smoothstep(a: float, b: float, value: np.ndarray) -> np.ndarray:
    t = np.clip((value - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def sample_masks(image: Image.Image, u: np.ndarray, v: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    image = image.convert("RGB").filter(ImageFilter.GaussianBlur(radius=2.0))
    pixels = np.asarray(image, dtype=np.float32) / 255.0
    x = np.clip(np.rint(u * (image.width - 1)).astype(np.int32), 0, image.width - 1)
    y = np.clip(np.rint(v * (image.height - 1)).astype(np.int32), 0, image.height - 1)
    rgb = pixels[y, x]
    maximum = rgb.max(axis=1)
    minimum = rgb.min(axis=1)
    saturation = (maximum - minimum) / np.maximum(maximum, 1e-5)
    luminance = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)

    # Warm saturation distinguishes gold trim from warm ivory marble.
    warm = smoothstep(0.03, 0.16, rgb[:, 0] - rgb[:, 2])
    yellow = smoothstep(-0.03, 0.10, rgb[:, 1] - rgb[:, 2])
    gold = smoothstep(0.52, 0.82, saturation) * warm * yellow
    gold *= smoothstep(0.18, 0.42, luminance) * (1.0 - smoothstep(0.73, 0.86, luminance))

    # Engraved bronze/charcoal is substantially darker than shaded ivory.
    dark = 1.0 - smoothstep(0.10, 0.27, luminance)
    # Reject the nearly black photographic backdrop; it is not model material.
    dark *= smoothstep(0.060, 0.115, luminance)
    return np.clip(gold, 0.0, 1.0), np.clip(dark, 0.0, 1.0)


def smooth_on_surface(mesh: trimesh.Trimesh, values: np.ndarray, iterations: int = 5) -> np.ndarray:
    """Diffuse projected masks across adjacent vertices to remove photo noise."""
    result = values.astype(np.float32, copy=True)
    neighbors = mesh.vertex_neighbors
    for _ in range(iterations):
        updated = result.copy()
        for index, adjacent in enumerate(neighbors):
            if len(adjacent):
                updated[index] = result[index] * 0.38 + result[np.asarray(adjacent)].mean() * 0.62
        result = updated
    return np.clip(result, 0.0, 1.0)


def bake(role: str, reference_dir: Path) -> None:
    filename, crop, horizontal_axis = REFERENCES[role]
    image = Image.open(reference_dir / filename)
    mesh_path = MODEL_DIR / f"{role}.glb"
    loaded = trimesh.load(mesh_path, force="scene")
    mesh = loaded.to_geometry() if hasattr(loaded, "to_geometry") else loaded
    vertices = np.asarray(mesh.vertices)
    axis = 0 if horizontal_axis == "x" else 2
    horizontal = vertices[:, axis]
    nx = (horizontal - horizontal.min()) / max(np.ptp(horizontal), 1e-6)
    ny = (vertices[:, 1] - vertices[:, 1].min()) / max(np.ptp(vertices[:, 1]), 1e-6)
    left, right, top, bottom = crop
    u = left + nx * (right - left)
    v = bottom - ny * (bottom - top)
    gold, dark = sample_masks(image, u, v)
    gold = smooth_on_surface(mesh, gold)
    dark = smooth_on_surface(mesh, dark)

    old = np.asarray(mesh.visual.vertex_colors)
    curvature = old[:, 0] if len(old) == len(vertices) else np.full(len(vertices), 128, dtype=np.uint8)
    colors = np.empty((len(vertices), 4), dtype=np.uint8)
    colors[:, 0] = curvature
    colors[:, 1] = np.rint(gold * 255.0).astype(np.uint8)
    colors[:, 2] = np.rint(dark * 255.0).astype(np.uint8)
    colors[:, 3] = 255
    mesh.visual.vertex_colors = colors
    mesh.export(mesh_path, include_normals=True)
    print(f"{role:6s}: gold={gold.mean():.3f}, dark={dark.mean():.3f}, vertices={len(vertices)}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: bake_reference_material_masks.py REFERENCE_DIRECTORY")
    reference_dir = Path(sys.argv[1])
    for role in REFERENCES:
        bake(role, reference_dir)


if __name__ == "__main__":
    main()
