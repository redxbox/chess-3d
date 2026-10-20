#!/usr/bin/env python3
"""Generate the knight mesh: assets/models/staunton/knight.obj.

WHY THIS EXISTS
---------------
The other five bodies in `assets/models/staunton/` come from the MIT-licensed
Staunton-Pieces set. The knight that shipped with that set is a thin slab of a
head on a straight neck: 0.23 wide, no brow, no cheek and no muzzle volume. From
the game camera - which looks up the board from 42 degrees above - that reads as
a lump. The previous rebuild of it in `main.gd` assembled a head from a sphere,
a cone and two ear cones, which read as a ball on a stick. Turning either
version sideways only turned a lump into a flat plate seen edge on.

A horse head cannot be built from horizontal slices or from a swept tube,
because its defining feature is an *overhang*: the muzzle juts out above the
throat, and the throat is a concave notch under it. This script therefore
builds the piece as a signed distance field - the foot as a surface of
revolution read off the shipped knight, the neck and head as soft-unioned
capsules and ellipsoids - and extracts the surface with marching cubes. The
result is one watertight, smooth, closed body with a real jaw and a real muzzle.

The muzzle points down the board (-Z), i.e. at the opponent, which is how every
real set orients a knight: both armies therefore face each other with no yaw
applied at all, and b1 maps onto g8 under the half turn of the board the way a
symmetric set must.

DEPENDENCIES (build-time only; the generated OBJ is committed)
-------------------------------------------------------------
    pip install numpy scikit-image fast-simplification trimesh

Run:  python3 tools/build_knight.py [output.obj]
"""

from __future__ import annotations

import sys

import numpy as np
import trimesh
from fast_simplification import simplify
from skimage import measure

# ---------------------------------------------------------------------------
# Units are the shipped set's: foot radius 0.326, king 1.62 tall. Every height
# below was measured off `assets/models/staunton/knight.obj` before it was
# replaced, so the new body stands on exactly the same foot.
# ---------------------------------------------------------------------------

# The turned foot and stem, as (height, radius). This is the part of the piece
# that really is a surface of revolution, and reusing the old numbers keeps the
# knight's base identical to the five pieces beside it.
REVOLVE = [
    (0.000, 0.326),
    (0.020, 0.326),
    (0.045, 0.320),
    (0.075, 0.306),
    (0.100, 0.316),   # bead
    (0.128, 0.310),
    (0.160, 0.292),
    (0.196, 0.254),
    (0.232, 0.203),
    (0.272, 0.174),
    (0.310, 0.164),
    (0.350, 0.160),
    (0.395, 0.166),
    (0.440, 0.180),
]

# The neck and head. Everything is a capsule (two radii along a segment) or an
# ellipsoid, which is enough vocabulary for a horse: a chest, a neck, a skull,
# a jaw and a muzzle that overhangs the throat.
# Each capsule: (p0, r0, p1, r1, flatten_x)
CAPSULES = [
    # Chest, widening out of the turned stem.
    ((0.0, 0.430, 0.000), 0.190, (0.0, 0.545, -0.015), 0.200, 1.00),
    # Neck: rises and leans forward, thinning as it goes.
    ((0.0, 0.545, -0.015), 0.200, (0.0, 0.760, -0.060), 0.174, 1.00),
    ((0.0, 0.760, -0.060), 0.174, (0.0, 0.950, -0.105), 0.152, 0.98),
    ((0.0, 0.950, -0.105), 0.150, (0.0, 1.070, -0.140), 0.138, 0.96),
    # The jaw and the muzzle, a long tapered bar hanging out over the throat.
    # This overhang is the whole point: without it the piece is a crook.
    ((0.0, 1.055, -0.100), 0.146, (0.0, 1.035, -0.420), 0.082, 0.98),
    # The lower jaw, thinner and tucked under the upper one.
    ((0.0, 1.000, -0.120), 0.116, (0.0, 0.990, -0.370), 0.062, 0.96),
    # The bridge of the nose, from the muzzle back up to the brow.
    ((0.0, 1.075, -0.390), 0.072, (0.0, 1.225, -0.180), 0.108, 0.90),
]

# Each ellipsoid: (centre, radii)
ELLIPSOIDS = [
    # Skull, the mass behind the brow.
    ((0.0, 1.170, -0.060), (0.134, 0.140, 0.150)),
    # Brow ridge, over the eye.
    ((0.0, 1.235, -0.170), (0.120, 0.080, 0.096)),
    # Nose: a blunt end cap so the muzzle is not a cone.
    ((0.0, 1.036, -0.418), (0.082, 0.084, 0.048)),
    # Chin, under the lip.
    ((0.0, 0.996, -0.320), (0.066, 0.058, 0.082)),
]

# Carved detail: the eye, the nostril and the cheek crease. Each entry is
# (centre, radii, sign) in the same ellipsoid form as ELLIPSOIDS; a negative
# sign carves a groove instead of raising a bump.
DETAILS = [
    # Eye: a shallow almond on each flank, just under the brow ridge.
    ((0.108, 1.192, -0.208), (0.030, 0.024, 0.045), 1.0),
    ((-0.108, 1.192, -0.208), (0.030, 0.024, 0.045), 1.0),
    # A crease behind the eye, which is what stops the head reading as a toy.
    ((0.112, 1.152, -0.150), (0.024, 0.018, 0.038), -1.0),
    ((-0.112, 1.152, -0.150), (0.024, 0.018, 0.038), -1.0),
    # Nostril flare, either side of the nose.
    ((0.070, 1.052, -0.392), (0.026, 0.024, 0.030), 1.0),
    ((-0.070, 1.052, -0.392), (0.026, 0.024, 0.030), 1.0),
    # The mouth line, a shallow groove along the side of the muzzle.
    ((0.072, 0.998, -0.360), (0.014, 0.014, 0.070), -1.0),
    ((-0.072, 0.998, -0.360), (0.014, 0.014, 0.070), -1.0),
]

# The mane: shallow locks along the crest of the neck, from the withers to
# between the ears. The crest surface is found from the field itself (see
# `_crest_z`), so the locks always sit exactly on the back of the neck.
MANE_HEIGHTS = [0.575, 0.625, 0.675, 0.725, 0.775, 0.825, 0.875, 0.925,
                0.975, 1.025, 1.075, 1.125, 1.175]

# Ears: two flattened blades on the crown, leaning out and forward.
EARS = [
    ((0.062, 1.276, -0.100), 0.052, (0.096, 1.452, -0.150), 0.020),
    ((-0.062, 1.276, -0.100), 0.052, (-0.096, 1.452, -0.150), 0.020),
]

# Smooth-union radius. Small enough that the jaw notch stays sharp, large
# enough that the capsules do not show as a string of sausages.
BLEND = 0.038

# Voxel size and the triangle budget the mesh is decimated to. The other five
# bodies are 5-15k triangles; this one is held to the same order so the whole
# set stays inside the Android budget on a mid-range phone.
VOXEL = 0.0038
TARGET_TRIANGLES = 16000


def _smooth_min(a, b, k):
    """Polynomial smooth minimum, as in `smin(a, b, k)` of the SDF literature."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def _segment_distance(px, py, pz, p0, p1):
    """Distance from each point to the segment p0-p1, plus the segment `t`."""
    ax, ay, az = p0
    bx, by, bz = p1
    dx, dy, dz = bx - ax, by - ay, bz - az
    length_squared = dx * dx + dy * dy + dz * dz
    if length_squared < 1e-12:
        t = np.zeros_like(px)
    else:
        t = ((px - ax) * dx + (py - ay) * dy + (pz - az) * dz) / length_squared
        t = np.clip(t, 0.0, 1.0)
    cx = ax + dx * t
    cy = ay + dy * t
    cz = az + dz * t
    return np.sqrt((px - cx) ** 2 + (py - cy) ** 2 + (pz - cz) ** 2), t


def _capsule(px, py, pz, p0, r0, p1, r1, flatten_x=1.0):
    """Distance to a tapered capsule, optionally squashed across X.

    Squashing is done by stretching X before the distance is taken, which turns
    a circular cross section into an ellipse that is narrow across the piece -
    the section a neck or an ear actually has. Every capsule here runs in the
    YZ plane, so scaling X cannot distort the segment itself.
    """
    sx = px / flatten_x
    distance, t = _segment_distance(sx, py, pz, p0, p1)
    radius = r0 + (r1 - r0) * t
    return (distance - radius) * min(1.0, flatten_x)


def _ellipsoid(px, py, pz, centre, radii):
    dx = (px - centre[0]) / radii[0]
    dy = (py - centre[1]) / radii[1]
    dz = (pz - centre[2]) / radii[2]
    k0 = np.sqrt(dx * dx + dy * dy + dz * dz)
    k1 = np.sqrt((dx / radii[0]) ** 2 + (dy / radii[1]) ** 2 + (dz / radii[2]) ** 2)
    k1 = np.where(k1 < 1e-9, 1e-9, k1)
    return k0 * (k0 - 1.0) / k1


def _revolve(px, py, pz):
    """Signed distance to the turned foot, from the measured radius table."""
    heights = np.array([row[0] for row in REVOLVE])
    radii = np.array([row[1] for row in REVOLVE])
    radius = np.interp(py, heights, radii, left=radii[0], right=radii[-1])
    radial = np.sqrt(px * px + pz * pz) - radius
    # The solid is {0 <= y <= top, radial <= 0}, so the distance is the largest
    # of the three: outside the radial profile, below the base, above the top.
    below_base = -py
    above_top = py - heights[-1]
    return np.maximum(radial, np.maximum(below_base, above_top))


def _neck_field(px, py, pz):
    """Everything from the stem up, without the mane.

    The mane needs to know where the back of the neck is, and the honest way to
    ask is to evaluate the rest of the body first rather than to keep a second,
    hand-maintained table of crest positions that can silently drift out of
    step with the capsules.
    """
    field = _capsule(px, py, pz, CAPSULES[0][0], CAPSULES[0][1],
                     CAPSULES[0][2], CAPSULES[0][3], CAPSULES[0][4])
    for p0, r0, p1, r1, flatten in CAPSULES[1:]:
        field = _smooth_min(field, _capsule(px, py, pz, p0, r0, p1, r1, flatten), BLEND)
    for centre, radii in ELLIPSOIDS:
        field = _smooth_min(field, _ellipsoid(px, py, pz, centre, radii), BLEND)
    return field


def _crest_z(y: float) -> float:
    """How far back (in +Z) the neck reaches at height `y`, on the centre line."""
    low, high = -0.05, 0.30
    for _ in range(28):
        mid = (low + high) * 0.5
        value = float(_neck_field(np.array([[0.0]]), np.array([[y]]), np.array([[mid]]))[0, 0])
        if value < 0.0:
            low = mid
        else:
            high = mid
    return low


def _mane(px, py, pz):
    """The mane crest: shallow locks along the back of the neck.

    Each lock is a squashed sphere sunk half into the crest and joined to the
    neck with a smooth union, so it reads as carved relief rather than as a row
    of beads. A lock that is narrow in y is a bead, and a row of beads down the
    back of the neck is what the first attempt looked like from behind - which
    is, unfortunately, exactly the view White gets of the black knights. Wide in
    x and y, so neighbouring locks fuse into one continuous band down the crest,
    and the scalloping along its length is what reads as a mane.
    """
    total = None
    for y in MANE_HEIGHTS:
        crest = _crest_z(y)
        dz = (pz - (crest - 0.020)) / 0.036
        dy = (py - y) / 0.042
        dx = px / 0.070
        lock = np.sqrt(dx * dx + dy * dy + dz * dz) - 1.0
        # A wide smooth union, so the locks melt into one raised crest with a
        # gentle scallop along it. Blended tightly they read as a row of beads
        # stuck to the back of the neck, which is worse than a plain ridge.
        total = lock if total is None else _smooth_min(total, lock, 0.055)
    return total


# The piece is modelled on a generous neck and then compressed vertically above
# the withers. A Staunton knight stands about as tall as a bishop (1.34 against
# the king's 1.62) with a foot the same 0.326 as everything else, and squashing
# the neck is what hits both numbers without shrinking the base or the head's
# reach down the board.
COMPRESS_FROM = 0.44
COMPRESS = 0.86


def _unsquash(py):
    """Undo the vertical compression: the field is evaluated on the tall model."""
    return np.where(py > COMPRESS_FROM,
                    COMPRESS_FROM + (py - COMPRESS_FROM) / COMPRESS,
                    py)


def signed_distance(px, py, pz):
    py = _unsquash(py)
    field = _revolve(px, py, pz)
    for p0, r0, p1, r1, flatten in CAPSULES:
        field = _smooth_min(field, _capsule(px, py, pz, p0, r0, p1, r1, flatten), BLEND)
    for centre, radii in ELLIPSOIDS:
        field = _smooth_min(field, _ellipsoid(px, py, pz, centre, radii), BLEND)
    for p0, r0, p1, r1 in EARS:
        field = _smooth_min(field, _capsule(px, py, pz, p0, r0, p1, r1, 0.55), BLEND * 0.6)
    for centre, radii, sign in DETAILS:
        shape = _ellipsoid(px, py, pz, centre, radii)
        if sign > 0.0:
            field = _smooth_min(field, shape, 0.018)
        else:
            field = np.maximum(field, -shape - 0.004)
    field = _smooth_min(field, _mane(px, py, pz), 0.045)
    return field


def build():
    x = np.arange(-0.42, 0.42, VOXEL)
    y = np.arange(-0.02, 1.56, VOXEL)
    z = np.arange(-0.68, 0.40, VOXEL)
    gx, gy, gz = np.meshgrid(x, y, z, indexing="ij", sparse=False)
    field = signed_distance(gx, gy, gz)
    del gx, gy, gz
    vertices, faces, _normals, _values = measure.marching_cubes(
        field, level=0.0, spacing=(VOXEL, VOXEL, VOXEL))
    vertices[:, 0] += x[0]
    vertices[:, 1] += y[0]
    vertices[:, 2] += z[0]
    # Marching cubes yields (y, z) ordering for the field because the grid was
    # built with (x, y, z) indexing; spacing was passed in the same order, so
    # the vertex columns are x, y, z already.
    vertices = vertices.astype(np.float64)
    faces = faces.astype(np.int64)

    # Decimate: the marching-cubes surface is far denser than the other five
    # bodies, and this mesh ships inside an Android APK.
    vertices = vertices.astype(np.float32)
    reduction = 1.0 - TARGET_TRIANGLES / float(len(faces))
    vertices, faces = simplify(vertices, faces, target_reduction=max(0.0, reduction))

    # Clean up. Marching cubes plus decimation can leave degenerate triangles
    # and a handful of pinholes, and an unclosed shell breaks shading and
    # shadow casting in Godot. trimesh does the three repairs that matter:
    # drop the degenerate faces, weld coincident vertices, and fill the pinholes
    # the decimator punched through the surface.
    mesh = trimesh.Trimesh(vertices=vertices, faces=faces, process=True)
    mesh.update_faces(mesh.nondegenerate_faces())
    mesh.update_faces(mesh.unique_faces())
    mesh.remove_unreferenced_vertices()
    trimesh.repair.fill_holes(mesh)
    trimesh.repair.fix_normals(mesh)
    bodies = mesh.split(only_watertight=False)
    if len(bodies) > 1:
        mesh = max(bodies, key=lambda body: len(body.faces))
    return np.asarray(mesh.vertices, dtype=np.float64), np.asarray(mesh.faces, dtype=np.int64)


def write_obj(path, vertices, faces):
    # Area-weighted vertex normals, so the surface shades smoothly.
    normals = np.zeros_like(vertices)
    tri = vertices[faces]
    face_normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for corner in range(3):
        np.add.at(normals, faces[:, corner], face_normals)
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    lengths[lengths < 1e-12] = 1.0
    normals = normals / lengths

    # Sit the foot exactly on y = 0.
    vertices[:, 1] -= vertices[:, 1].min()

    with open(path, "w", encoding="utf-8") as handle:
        handle.write("# Staunton knight, generated by tools/build_knight.py\n")
        handle.write("# Base silhouette follows the MIT-licensed Staunton-Pieces set.\n")
        handle.write("o knight\n")
        for point in vertices:
            handle.write(f"v {point[0]:.6f} {point[1]:.6f} {point[2]:.6f}\n")
        for normal in normals:
            handle.write(f"vn {normal[0]:.6f} {normal[1]:.6f} {normal[2]:.6f}\n")
        for face in faces:
            a, b, c = face + 1
            handle.write(f"f {a}//{a} {b}//{b} {c}//{c}\n")
    return vertices


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "assets/models/staunton/knight.obj"
    vertices, faces = build()
    vertices = write_obj(path, vertices, faces)
    low = vertices.min(axis=0)
    high = vertices.max(axis=0)
    print(f"wrote {path}: {len(vertices)} vertices, {len(faces)} triangles")
    print(f"  height {high[1]:.3f}  width {high[0] - low[0]:.3f}  "
          f"depth {high[2] - low[2]:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
