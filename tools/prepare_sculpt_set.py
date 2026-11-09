#!/usr/bin/env python3
"""Import a hand-made sculpted piece set into assets/models/<set>/.

WHY THIS EXISTS
---------------
The project author supplies each piece set as six sculpted files - one GLB per
piece, 280k-500k triangles and 13-21 MB each - uploaded to the repository. The
current set ("pars", an Indo-Persian figured set) is the third in that series;
"bastani" and the retired turned "classic" came the same way.

None of them can be used as uploaded: 110 MB of GLB is not a mobile game's
budget for its pieces, and a Godot import of half a million triangles per piece
would stall startup on a phone.

The uploads now land in tools/sources/incoming/ rather than assets/, because the
export filter packs everything under assets/ into the APK - see
tools/check_shipped_assets.py for the guard that fails the build when one does.

This script does the conversions that turn six uploads into a usable set:

1. Weld, then decimate. The uploads are triangle soups - the pars horse is 282k
   triangles in 21 000 disconnected islands, because the exporter shares no
   vertices between neighbouring faces. A quadric simplifier will not collapse
   across an island boundary, so welding first is what takes the mesh to
   TARGET_TRIANGLES in one pass instead of bottoming out at 18k. The silhouette
   and the carved surface survive; the triangle count drops by roughly 30x, into
   the 5-16k band the rest of the project uses.

2. Put it on the board's scale. The uploads are all exactly 1.0 unit tall,
   whatever the piece, so a pawn would stand as tall as a king. Each one is
   scaled to the height the shipped set uses (pawn 0.91 up to king 1.62).

3. Write OBJ at four decimals. Positions and faces only - the game generates
   smooth normals, a UV set and tangents at load, and a baked normal would be
   thrown away.

4. `--colours`: turn the sculpture's texture atlas into a material map - body,
   gilding, accent - and write it beside the OBJ as `<kind>.tint`, together with
   both armies' palettes. See write_tint() for the layout and material_indices()
   for why the atlas is not sampled per vertex; main.gd's `_read_tint()` is the
   other end.

The set is stored the way the game expects: +Y up, standing on y = 0, centred on
the origin in X/Z. Fragments are not merged or repaired: the source sculptures
have open shells, and decimating one is still a correct render - only shadows
from inside would care, and chess pieces are lit from outside.

DEPENDENCIES (build-time only; the generated OBJs are committed)
----------------------------------------------------------------
    pip install numpy trimesh fast-simplification

Files are found by the piece name inside them (`tools/piece_names.py`), in any
format `trimesh` opens, so an upload does not have to be renamed first.

Run:  python3 tools/prepare_sculpt_set.py [source_dir] [output_dir]

    python3 tools/prepare_sculpt_set.py --colours tools/sources/incoming assets/models/pars
"""

from __future__ import annotations

import os
import sys

import json
import struct

import numpy as np
import trimesh
from fast_simplification import simplify

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from piece_names import MODEL_SUFFIXES, kind_of  # noqa: E402

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


def weld(vertices: np.ndarray, faces: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Merge vertices that sit on the same point, and drop the collapsed faces.

    Quantised to a ten-thousandth of the model's height, which on a piece that
    is later scaled to 1.6 board units is 0.16 mm: far below anything a phone
    screen can show, and far enough apart that genuinely distinct surfaces are
    not fused.
    """
    span = float(np.max(vertices.max(axis=0) - vertices.min(axis=0)))
    quantise = max(1e-6, span / 10000.0)
    keys = np.round(vertices / quantise).astype(np.int64)
    _, inverse, counts = np.unique(keys, axis=0, return_inverse=True, return_counts=True)
    if len(inverse) == len(vertices) and int(counts.max()) == 1:
        return vertices, faces
    merged = np.zeros((len(counts), 3), dtype=np.float64)
    np.add.at(merged, inverse, vertices)
    merged /= counts[:, None].astype(np.float64)
    faces = inverse[faces]
    keep = (faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])
    faces = faces[keep]
    # Vertices no face refers to are dropped, which also drops the ones the
    # atlas sampled for nothing.
    used, faces = np.unique(faces, return_inverse=True)
    return merged[used], faces.reshape(-1, 3)

def load(path: str) -> tuple[np.ndarray, np.ndarray]:
    mesh = trimesh.load(path, force="mesh")
    return (np.asarray(mesh.vertices, dtype=np.float32),
            np.asarray(mesh.faces, dtype=np.int64))


def load_colours(path: str) -> tuple[np.ndarray, np.ndarray]:
    """The mesh's own per-vertex colour, whatever way the upload carries it.

    Kept for the trimesh-friendly formats; GLB goes through baked_colours()
    below, which reads the atlas WebP by hand. Neither is shipped: what the
    material map needs from the colour are the gold and red regions, not the
    colours themselves.
    """
    mesh = trimesh.load(path, force="mesh")
    visual = mesh.visual
    if visual is None or visual.kind is None:
        raise ValueError("no colour")
    colours = visual.to_color().vertex_colors
    if colours is None or len(colours) == 0:
        raise ValueError("no vertex colours")
    colours = np.asarray(colours)
    if colours.dtype != np.uint8:
        colours = np.clip(colours * 255.0, 0, 255).astype(np.uint8)
    return (np.asarray(mesh.vertices, dtype=np.float32), colours[:, :3])


def _glb_json_and_binary(path: str) -> tuple[dict, bytes]:
    """The two chunks of a GLB: the JSON document and the binary buffer."""
    with open(path, "rb") as handle:
        magic, _version, _length = struct.unpack("<4sII", handle.read(12))
        if magic != b"glTF":
            raise ValueError("not a GLB")
        document = b""
        binary = b""
        while True:
            header = handle.read(8)
            if len(header) < 8:
                break
            chunk_length, chunk_type = struct.unpack("<II", header)
            payload = handle.read(chunk_length)
            if chunk_type == 0x4E4F534A:      # 'JSON'
                document = payload
            elif chunk_type == 0x004E4942:    # 'BIN'
                binary = payload
    return json.loads(document.decode("utf-8")), binary


def _accessor(js: dict, binary: bytes, index: int) -> np.ndarray:
    """Read one accessor as a numpy array, honouring its stride if it has one."""
    accessor = js["accessors"][index]
    view = js["bufferViews"][accessor["bufferView"]]
    kind = {5120: "i1", 5121: "u1", 5122: "i2", 5123: "u2",
            5125: "u4", 5126: "f4"}[accessor["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    item = np.dtype(kind).itemsize
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or (item * width)
    count = int(accessor["count"])
    span = stride * (count - 1) + item * width
    raw = np.frombuffer(binary, dtype=np.uint8, count=span, offset=start)
    if stride == item * width:
        return raw.view(np.dtype(kind)).reshape(count, width).astype(np.float32)
    # Interleaved: take a window of one element every `stride` bytes. Kept as a
    # sliding window over the byte buffer rather than a manual offset loop, so a
    # 300 000-vertex accessor costs one copy rather than 300 000.
    windows = np.lib.stride_tricks.sliding_window_view(raw, item * width)[::stride][:count]
    return np.ascontiguousarray(windows).view(np.dtype(kind)).reshape(count, width).astype(np.float32)


def _atlas_image(js: dict, binary: bytes) -> "Image.Image | None":
    """The base-colour texture of the first material, decoded.

    Read by hand rather than through trimesh for a specific reason: these
    uploads carry their atlas as **WebP** under `EXT_texture_webp`, and trimesh
    does not decode that extension - `to_color()` returns black for most of the
    mesh. Measured on the November upload: 85% of the vertices came out (0,0,0),
    which renders as a black chess set. Pillow reads WebP directly, and is
    already a build-time dependency of tools/measure_preview.py.
    """
    try:
        from PIL import Image
    except ImportError:
        return None
    materials = js.get("materials") or []
    if not materials:
        return None
    pbr = materials[0].get("pbrMetallicRoughness", {})
    texture_index = pbr.get("baseColorTexture", {}).get("index")
    if texture_index is None:
        return None
    textures = js.get("textures") or []
    if texture_index >= len(textures):
        return None
    texture = textures[texture_index]
    source = texture.get("source")
    webp = texture.get("extensions", {}).get("EXT_texture_webp", {})
    if "source" in webp:
        source = webp["source"]
    images = js.get("images") or []
    if source is None or source >= len(images):
        return None
    view = js["bufferViews"][images[source]["bufferView"]]
    start = view.get("byteOffset", 0)
    payload = binary[start:start + view["byteLength"]]
    import io
    return Image.open(io.BytesIO(payload)).convert("RGB")


def baked_colours(path: str, count: int) -> "np.ndarray | None":
    """One RGB per vertex of `path`, sampled from its own atlas.

    Handles the two ways a coloured upload arrives: a base-colour texture with
    UVs (sampled here), or per-vertex colour already in the file (taken as-is).
    Returns None when the model has neither, which is the normal case for a
    geometry-only sculpt and is not an error.
    """
    suffix = os.path.splitext(path)[1].lower()
    if suffix in (".glb", ".gltf") and suffix == ".glb":
        try:
            js, binary = _glb_json_and_binary(path)
        except Exception:
            return None
        for mesh in js.get("meshes", []):
            for primitive in mesh.get("primitives", []):
                attributes = primitive.get("attributes", {})
                if "COLOR_0" in attributes:
                    colours = _accessor(js, binary, attributes["COLOR_0"])
                    if colours.max() <= 1.0:
                        colours = colours * 255.0
                    return np.clip(colours[:, :3], 0, 255).astype(np.uint8)
                if "TEXCOORD_0" not in attributes:
                    continue
                image = _atlas_image(js, binary)
                if image is None:
                    continue
                uvs = _accessor(js, binary, attributes["TEXCOORD_0"])
                pixels = np.asarray(image, dtype=np.uint8)
                height, width = pixels.shape[:2]
                u = np.mod(uvs[:, 0], 1.0)
                v = np.mod(uvs[:, 1], 1.0)
                x = np.clip((u * (width - 1)).astype(np.int64), 0, width - 1)
                # glTF puts (0,0) at the top-left of the image.
                y = np.clip((v * (height - 1)).astype(np.int64), 0, height - 1)
                return pixels[y, x]
        return None
    # Any other format: whatever trimesh can read, minus the WebP gap above.
    try:
        return np.asarray(trimesh.load(path, force="mesh").visual.to_color().vertex_colors)[:, :3]
    except Exception:
        return None


class _NearestVertex:
    """Nearest-vertex lookup over the *original* sculpture, without scipy.

    Decimation replaces the vertex list, so the colours sampled on the original
    mesh have to be carried across to whatever vertices the simplified mesh kept.
    A KD-tree would do it, but scipy is another build-time dependency for a
    lookup that a uniform grid answers in constant time: with 31 mm between
    vertices on these meshes, a one-centimetre cell puts the nearest original
    vertex within one cell of any simplified one, and the 3x3x3 neighbourhood is
    a safety margin.
    """

    def __init__(self, points: np.ndarray, cell: float):
        self.points = points
        self.cell = cell
        self.buckets: dict[tuple[int, int, int], list[int]] = {}
        keys = np.floor(points / cell).astype(np.int64)
        for index, key in enumerate(map(tuple, keys)):
            self.buckets.setdefault(key, []).append(index)

    def nearest(self, point: np.ndarray) -> int:
        centre = tuple(np.floor(point / self.cell).astype(np.int64))
        best = -1
        best_distance = float("inf")
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for index in self.buckets.get((centre[0] + dx, centre[1] + dy, centre[2] + dz), ()):
                        delta = self.points[index] - point
                        distance = float(delta @ delta)
                        if distance < best_distance:
                            best_distance = distance
                            best = index
        return best


# The plinth is the bottom tenth of a figure. Centring a piece on its *plinths*
# rather than on its bounding box matters for anything holding a spear, a
# standard or a raised arm: the arm pushes the box sideways, so a box-centred
# piece stands off-centre on its square and its base rings are no longer
# concentric with the foot. Three of the six bastani figures were off by 4-6% of
# their width, which is visible on a 1.0-wide square.
PLINTH_BAND = 0.05


def _plinth_centre(vertices: np.ndarray) -> tuple[float, float]:
    height = float(vertices[:, 1].max() - vertices[:, 1].min())
    base = vertices[vertices[:, 1] < vertices[:, 1].min() + PLINTH_BAND * height]
    if len(base) < 16:
        base = vertices
    return float(base[:, 0].mean()), float(base[:, 2].mean())


def prepare(kind: str, path: str, keep_colour: bool = False):
    vertices, faces = load(path)
    # These uploads are triangle soups: the November horse is 282k triangles in
    # 21 000 disconnected islands, because the exporter did not share vertices
    # between neighbouring faces. A quadric simplifier will not collapse across
    # an island boundary, so decimating the soup directly bottoms out around
    # 18k triangles however hard it is pushed. Welding first - 262k vertices to
    # 138k on that horse - takes the same mesh to 10k in a single pass, and the
    # surface it produces is smoother because the crease is now a crease rather
    # than a seam between two unconnected facets.
    vertices, faces = weld(vertices, faces)
    source_vertices = source_colours = None
    if keep_colour:
        source_vertices = np.asarray(vertices, dtype=np.float64)
        source_colours = baked_colours(path, len(vertices))
        if source_colours is None:
            print(f"{kind}: the model carries no colour of its own", file=sys.stderr)
            source_vertices = None
        elif float(np.asarray(source_colours, dtype=float).mean()) < 4.0:
            # All black is what a failed texture decode looks like, and shipping
            # it would be worse than shipping no colour at all.
            print(f"{kind}: the model's colour reads as black - the atlas probably "
                  f"did not decode; importing it without colour", file=sys.stderr)
            source_vertices = source_colours = None
    # The sets are not equally dense: the older uploads arrive already decimated
    # (6k-26k triangles) while the pars ones arrive at 280k-500k.
    # Only decimate downwards, never upwards, and never re-simplify a piece
    # that is already under budget - it would only cost detail.
    # One pass is not always enough. A sculpture of many disconnected islands -
    # the sample piece uploaded in November is 282k triangles in one mesh - loses
    # far less than the ratio asked for, because the simplifier will not collapse
    # across a boundary. So it is run again on what came out, up to four times,
    # and the result is reported if it still misses the budget.
    # A piece can also arrive as several disconnected shells - a figure plus its
    # plinth plus the spear it holds - and the simplifier will not collapse across
    # the seam, so the last pass is allowed to ask for everything that is left.
    for _attempt in range(6):
        if len(faces) <= TARGET_TRIANGLES:
            break
        reduction = 1.0 - TARGET_TRIANGLES / float(len(faces))
        vertices, faces = simplify(vertices, faces, target_reduction=min(0.99, max(0.001, reduction)))
        vertices = np.asarray(vertices, dtype=np.float64)
        faces = np.asarray(faces, dtype=np.int64)
    if len(faces) > TARGET_TRIANGLES * 1.25:
        print(f"{kind}: still {len(faces)} triangles after six passes "
              f"(budget {TARGET_TRIANGLES}); the source is too fragmented to decimate further",
              file=sys.stderr)
    vertices, faces = _normalise(kind, vertices, faces, extra=source_vertices)
    colours = None
    if source_colours is not None:
        # Carried across *after* decimation, by nearest original vertex: the
        # simplified mesh has its own vertices and no UVs that survive.
        spacing = float(np.linalg.norm(vertices.max(axis=0) - vertices.min(axis=0))) / 60.0
        lookup = _NearestVertex(source_vertices, max(spacing, 0.005))
        colours = np.zeros((len(vertices), 3), dtype=np.uint8)
        for index, point in enumerate(vertices):
            nearest = lookup.nearest(point)
            if nearest >= 0:
                colours[index] = source_colours[nearest]
        # The colours are not what ships: the material map derived from them is.
        # See material_indices() for why, and write_tint() for the file.
        colours = material_indices(colours, faces, vertices)
    return vertices, faces, colours


def _normalise(kind: str, vertices: np.ndarray, faces: np.ndarray, centre_on_plinth: bool = False,
               extra: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Put a piece on the board's scale: target height, feet on y = 0, centred."""
    low = vertices.min(axis=0)
    high = vertices.max(axis=0)
    # Uniform scale, from the model's own height, so the carving keeps its
    # proportions. This is the height pass only: the footprints the models
    # arrived with were 0.20 to 0.43 of a square, which reads as three
    # different-sized sets on one board, so tools/normalise_set_scale.py applies
    # a second, footprint pass that puts every piece on the classic set's foot
    # radius. Run this script first and that one after it.
    scale = TARGET_HEIGHT[kind] / float(high[1] - low[1])
    vertices *= scale
    # Stand it on y = 0 and put its own centre over the square's centre. A
    # plinth-centred piece is centred on the thing that touches the board.
    if centre_on_plinth:
        centre_x, centre_z = _plinth_centre(vertices)
    else:
        centre_x, centre_z = (low[0] + high[0]) * 0.5 * scale, (low[2] + high[2]) * 0.5 * scale
    vertices[:, 0] -= centre_x
    vertices[:, 2] -= centre_z
    vertices[:, 1] -= vertices[:, 1].min()
    if extra is not None:
        # A point set that has to stay aligned with the mesh - the original
        # sculpture's vertices, whose colours are being carried over. It has to
        # see exactly the same scale and the same offsets, or the nearest-vertex
        # lookup afterwards points at the wrong part of the model.
        extra *= scale
        extra[:, 0] -= centre_x
        extra[:, 2] -= centre_z
        extra[:, 1] -= extra[:, 1].min()
    return vertices, faces


## Turning the uploaded colours into the two armies.
##
## WHY THIS IS A PALETTE AND NOT THE ATLAS
## ---------------------------------------
## The uploads carry a 4096-square base-colour atlas per piece, and the first
## version of this block sampled it down to one RGB per vertex. That is right in
## principle and wrong at this vertex count: these atlases are a filigree of gold
## over silver over dark leather, fragmented into thousands of small islands, and
## at 4 800 vertices a piece the sampling lands on a different island almost
## every vertex. What came out was camouflage - a leopard print of gold, silver
## and maroon, and because gold is 50-90% of those atlases, both armies read as
## gold and could not be told apart on a phone. That is the complaint this block
## answers ("they are all gold and white, where are the colours").
##
## Detail cannot survive that sampling, so it is not what gets kept. What gets
## kept is the *division of the sculpture into materials* - which parts are gold
## and which are the body. And for the gilding that division is read from the
## geometry rather than from the atlas: convexity, diffused over the mesh until
## what is left is a region, marks where the sculpture has an edge - the rim of a
## plinth, the band round a tower, the ridge of a mane, the points of a crown -
## which is where a gilded statuette is gilded. The atlas still decides the red
## accents, where a colour is the thing itself rather than a shape.
##
## That also makes the two armies cheap and exact. Both armies are the same
## material indices and two palettes, so a `.tint` is one byte per vertex - 5 KB
## a piece against 15 KB - and the ink army is a palette rather than an
## arithmetic rule that cannot tell gold from the body it sits on.
##
## The bands the two palettes have to land in are enforced by
## tools/check_visual_balance.py: the pale army's median albedo in 0.55-0.78
## linear, the ink army's in 0.28-0.35, and at least 2x apart. Those numbers are
## not taste - they are where the other two sets sit and where a render on a
## phone keeps the armies apart on both square colours.
MATERIALS = ("body", "gold", "accent")

# sRGB, because that is the space the palettes in main.gd are written in and the
# space an artist reads; the shader's albedo is linear and the reader converts.
# The pale army is ivory and gold, the ink army is the same sculpture in black
# armour with the gilding kept - the reference photograph the author supplied.
PALE_PALETTE = {
    "body":   (224, 217, 198),   # ivory    - linear luma 0.696
    "gold":   (226, 190, 116),   # gilding  - linear luma 0.543
    "accent": (168, 32, 36),     # plume and gems
}
INK_PALETTE = {
    "body":   (154, 155, 160),   # black armour in light - linear luma 0.329
    "gold":   (212, 170, 98),    # the gilding keeps its brightness
    "accent": (120, 26, 30),
}

# How much of a piece each material is allowed to be. Gold over 50% stops being
# trim and becomes the piece (the rook's atlas is 87% gold), so the share is
# fixed per piece rather than taken from it: every figure then reads as the same
# set. The values were picked by eye against the reference photograph and then
# checked against the measuring script.
GOLD_SHARE = 0.26
ACCENT_SHARE = 0.05

# How far the convexity is diffused before it is thresholded. This is the number
# that decides whether the gilding has an edge or is a rash of specks: at four
# rounds every facet of the decimated sculpt crosses the threshold somewhere, and
# at twenty-eight what is left is the mouldings, the ridges and the crowns.
GOLD_ROUNDS = 28

# Smoothing rounds over the mesh graph. One round is not enough to close the
# gaps the atlas sampling leaves inside a gilded region; three starts rounding
# off genuinely thin detail like the wire of a crown.
SMOOTH_ROUNDS = 4

# A material island smaller than this share of a piece is noise, not ornament:
# it is reassigned to the body. The atlas sampling is per vertex, so a gilded
# region arrives full of one-vertex holes and the piece renders as a speckle of
# gold flakes. Islands, majority votes and this floor are what turn that back
# into gilded trim with an edge.
MIN_ISLAND = 0.012

# Where a hue has to sit to count, in degrees. Gold is yellow-orange, the
# accents are red; everything else is body. Hues wrap, so red is two windows.
GOLD_HUE = (25.0, 80.0)
ACCENT_HUE = (335.0, 25.0)
MIN_VALUE = 0.22            # below this the atlas is in shadow, not a material


def srgb_to_linear(rgb: np.ndarray) -> np.ndarray:
    rgb = np.asarray(rgb, dtype=np.float64)
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(rgb: np.ndarray) -> np.ndarray:
    rgb = np.clip(np.asarray(rgb, dtype=np.float64), 0.0, 1.0)
    return np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(rgb, 1.0 / 2.4) - 0.055)


def luma(rgb: np.ndarray) -> np.ndarray:
    return 0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2]


def _hsv(colours: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Hue in degrees, saturation and value, from sRGB 0..1 triples."""
    rgb = np.asarray(colours, dtype=np.float64)
    high = rgb.max(axis=1)
    low = rgb.min(axis=1)
    delta = high - low
    saturation = np.where(high > 1e-6, delta / np.maximum(high, 1e-6), 0.0)
    hue = np.zeros(len(rgb))
    coloured = delta > 1e-6
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    index = (high == r) & coloured
    hue[index] = ((g[index] - b[index]) / delta[index]) % 6.0
    index = (high == g) & coloured
    hue[index] = (b[index] - r[index]) / delta[index] + 2.0
    index = (high == b) & coloured
    hue[index] = (r[index] - g[index]) / delta[index] + 4.0
    return np.mod(hue * 60.0, 360.0), saturation, high


def _in_hue(hue: np.ndarray, window: tuple[float, float]) -> np.ndarray:
    low, high = window
    if low <= high:
        return (hue >= low) & (hue <= high)
    return (hue >= low) | (hue <= high)          # the window crosses 0 degrees


def _edges(faces: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Unique mesh edges as two index arrays, for the smoothing passes."""
    edges = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]], axis=0)
    edges = np.concatenate([edges, edges[:, ::-1]], axis=0)
    edges = np.unique(edges, axis=0)
    return edges[:, 0], edges[:, 1]


def smooth(values: np.ndarray, faces: np.ndarray, rounds: int) -> np.ndarray:
    """Average a per-vertex field with its mesh neighbours a few times.

    A plain mean, not a median: the fields being smoothed are scores in 0..1
    and the point is to close gaps, so one pass over the edge list is enough and
    keeps this to a single bincount per round on 10 000 faces.
    """
    values = np.asarray(values, dtype=np.float64).copy()
    a, b = _edges(faces)
    for _ in range(rounds):
        total = values.copy()
        count = np.ones(len(values))
        np.add.at(total, a, values[b])
        np.add.at(total, b, values[a])
        np.add.at(count, a, 1.0)
        np.add.at(count, b, 1.0)
        values = total / count
    return values


def convexity(vertices: np.ndarray, faces: np.ndarray, rounds: int = 3) -> np.ndarray:
    """Mean convexity per vertex: positive on ridges, negative in creases.

    Measured as the Laplacian of the position projected onto the normal. This is
    the same quantity src/main/piece_shading.gd measures to bake occlusion into
    the vertex colours - a ridge catches light, a crease loses it - and it is
    reused here because "where is the edge of the gilding" is the same question
    as "where would the highlight land".
    """
    a, b = _edges(faces)
    triangles = vertices[faces]
    face_normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    normals = np.zeros_like(vertices)
    for corner in range(3):
        np.add.at(normals, faces[:, corner], face_normals)
    normals /= np.maximum(np.linalg.norm(normals, axis=1, keepdims=True), 1e-9)
    lap = np.zeros_like(vertices)
    count = np.zeros(len(vertices))
    np.add.at(lap, a, vertices[b])
    np.add.at(count, a, 1.0)
    np.add.at(lap, b, vertices[a])
    np.add.at(count, b, 1.0)
    lap = lap / np.maximum(count, 1.0)[:, None] - vertices
    values = np.einsum("ij,ij->i", lap, normals)
    for _ in range(rounds):
        total = values.copy()
        weights = np.ones(len(vertices))
        np.add.at(total, a, values[b])
        np.add.at(total, b, values[a])
        np.add.at(weights, a, 1.0)
        np.add.at(weights, b, 1.0)
        values = total / weights
    return values


def material_indices(colours_srgb: np.ndarray, faces: np.ndarray,
                     vertices: np.ndarray | None = None) -> np.ndarray:
    """One material index per vertex: 0 body, 1 gold, 2 accent.

    Two different signals, because the two materials are recognised two
    different ways:

      * **Gilding comes from the geometry.** Convexity, diffused far enough over
        the mesh that what is left is a region and not a per-triangle reading -
        twenty-eight rounds, which on a 10 000-triangle piece is several
        centimetres of surface. What survives that is where the sculpture has
        edges: the rim of a plinth, the band round a tower, the ridge of a mane,
        the points of a crown. That is where a gilded statuette is gilded, and
        the threshold is a fixed share of the piece so every figure ends up with
        the same amount of gold regardless of what its atlas happens to contain.

      * **The accents come from the atlas.** A red plume or a garnet is a
        colour, not a shape, and red is rare enough in these atlases that the
        per-vertex reading is reliable where gold's is not.

    The atlas was tried as the source for the gilding, and it is the reason this
    set shipped twice as camouflage: gold is 50-90% of every one of these
    atlases, spread as filigree over silver and dark leather in thousands of
    islands, so at 4 800 vertices the samples come back as a leopard print
    whichever way they are graded. Geometry does not have that problem - an edge
    is an edge - and the colour of the gold is a palette entry, not a sample.
    """
    rgb = np.asarray(colours_srgb, dtype=np.float64) / 255.0
    hue, saturation, value = _hsv(rgb)
    labels = np.zeros(len(rgb), dtype=np.uint8)

    accent = smooth(saturation * _in_hue(hue, ACCENT_HUE) * (value > MIN_VALUE),
                    faces, SMOOTH_ROUNDS)
    accent_count = int(round(ACCENT_SHARE * len(rgb)))
    accent_order = np.argsort(-accent)[:accent_count]
    labels[accent_order[accent[accent_order] > 0]] = 2

    if vertices is not None:
        ridge = smooth(convexity(vertices, faces), faces, GOLD_ROUNDS)
        threshold = np.percentile(ridge, 100.0 * (1.0 - GOLD_SHARE))
        labels[(ridge > threshold) & (labels == 0)] = 1
    else:
        # No geometry to read (the caller passed labels only): fall back to the
        # atlas, which is what this used to do for both materials.
        gold = smooth(saturation * _in_hue(hue, GOLD_HUE) * (value > MIN_VALUE),
                      faces, SMOOTH_ROUNDS)
        gold_count = int(round(GOLD_SHARE * len(rgb)))
        order = np.flatnonzero(labels == 0)
        order = order[np.argsort(-gold[order])][:gold_count]
        labels[order[gold[order] > 0]] = 1

    return _fill_and_clean(labels, faces)


def _fill_and_clean(labels: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Close pin-holes, then drop islands too small to be ornament.

    A gilded band with a scatter of one-vertex holes renders as a rash, and a few
    gold vertices adrift on an ivory robe renders as the speckle this set shipped
    with. A vertex is filled when most of its neighbours agree it should be, and
    an island smaller than MIN_ISLAND of the piece goes back to the body.
    """
    a, b = _edges(faces)
    for material in (1, 2):
        for _ in range(3):
            agree = np.zeros(len(labels))
            count = np.zeros(len(labels))
            np.add.at(agree, a, (labels[b] == material).astype(np.float64))
            np.add.at(count, a, 1.0)
            np.add.at(agree, b, (labels[a] == material).astype(np.float64))
            np.add.at(count, b, 1.0)
            fill = (labels == 0) & (agree / np.maximum(count, 1.0) > 0.62)
            labels[fill] = material
        labels = _drop_small_islands(labels, faces)
    return labels


def _components(labels: np.ndarray, faces: np.ndarray, material: int) -> tuple[np.ndarray, np.ndarray]:
    """Connected components of one material over the mesh, by union-find."""
    parent = np.arange(len(labels))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    a, b = _edges(faces)
    same = (labels[a] == material) & (labels[b] == material)
    for u, v in zip(a[same], b[same]):
        ru, rv = find(int(u)), find(int(v))
        if ru != rv:
            parent[ru] = rv
    roots = np.array([find(i) for i in range(len(labels))])
    return roots, np.flatnonzero(labels == material)


def _drop_small_islands(labels: np.ndarray, faces: np.ndarray) -> np.ndarray:
    """Fold every material island below MIN_ISLAND of the piece back into the body."""
    labels = labels.copy()
    floor = max(6, int(round(MIN_ISLAND * len(labels))))
    for material in (1, 2):
        roots, members = _components(labels, faces, material)
        if not len(members):
            continue
        values, counts = np.unique(roots[members], return_counts=True)
        small = values[counts < floor]
        if len(small):
            labels[np.isin(roots, small) & (labels == material)] = 0
    return labels


def _majority(labels: np.ndarray, faces: np.ndarray) -> np.ndarray:
    a, b = _edges(faces)
    votes = np.zeros((len(labels), len(MATERIALS)))
    for column, sources, targets in ((0, a, b), (1, b, a)):
        np.add.at(votes, (sources, labels[targets]), 1.0)
    votes[np.arange(len(labels)), labels] += 2.0     # keep the vertex's own vote
    return np.argmax(votes, axis=1).astype(np.uint8)


def palette_bytes(palette: dict[str, tuple[int, int, int]]) -> bytes:
    return b"".join(bytes(palette[name]) for name in MATERIALS)


def palette_luma(palette: dict[str, tuple[int, int, int]]) -> float:
    """The palette's luminance in linear light - what the checker measures."""
    colours = np.asarray([palette[name] for name in MATERIALS], dtype=np.float64) / 255.0
    return float(np.median(luma(srgb_to_linear(colours))))


def write_tint(path: str, labels: np.ndarray) -> None:
    """Write the material map beside the OBJ, in the OBJ's vertex order.

    Layout, all little-endian:

        b"TINT"   uint8 version (4)   uint32 vertex count   uint8 material count
        material count x 3 pale sRGB bytes, then 3 ink sRGB bytes
        vertex count x uint8 material index

    Both armies travel in one file because they are one sculpture in two
    palettes: the body of the pale king is ivory and the body of the ink king is
    black armour, and every other vertex is the same gilded trim in both. One
    byte per vertex, 5 KB a piece, and no arithmetic between the two armies that
    could turn gilding into the colour of the body it sits on - which is what
    the previous version, a gamma-and-gain rule over sampled atlas colours, did
    on the phone.

    main.gd's `_read_tint()` is the other end; tools/check_visual_balance.py
    reads the same palettes to measure the armies.
    """
    labels = np.asarray(labels, dtype=np.uint8)
    with open(path, "wb") as handle:
        handle.write(b"TINT")
        handle.write(bytes([4]))
        handle.write(len(labels).to_bytes(4, "little"))
        handle.write(bytes([len(MATERIALS)]))
        handle.write(palette_bytes(PALE_PALETTE))
        handle.write(palette_bytes(INK_PALETTE))
        handle.write(labels.tobytes())


def write_obj(path: str, kind: str, vertices: np.ndarray, faces: np.ndarray) -> None:
    # Four decimals, not six: on a king that is 1.62 board units tall, the last
    # digit is a twentieth of a millimetre, and the text it saves is a quarter of
    # the file.
    # Positions and faces only, exactly like the Staunton OBJs: _piece_mesh()
    # welds the export's duplicated vertices and generates one smooth normal per
    # corner plus a cylindrical UV set. Writing normals here as well would add
    # 45% to the file for data that is thrown away and recomputed at load.
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(f"# {kind}, imported by tools/prepare_sculpt_set.py\n")
        handle.write("# Source: user-supplied GLB, see assets/models/<set>/README.md\n")
        handle.write(f"o {kind}\n")
        for point in vertices:
            handle.write(f"v {point[0]:.4f} {point[1]:.4f} {point[2]:.4f}\n")
        for face in faces:
            a, b, c = face + 1
            handle.write(f"f {a} {b} {c}\n")


def main() -> int:
    # `--colours` is opt-in: a set's own colour is a product decision (it takes
    # the army colours away from the game's palette), so the importer only
    # carries it over when asked.
    keep_colour = "--colours" in sys.argv
    positional = [argument for argument in sys.argv[1:] if not argument.startswith("--")]
    source = positional[0] if len(positional) > 0 else "."
    output = positional[1] if len(positional) > 1 else "assets/models/persian"
    os.makedirs(output, exist_ok=True)
    for kind in KINDS:
        # The file names are whatever the author's tool produced: the bastani set
        # arrived as pown1.glb / quin1.glb, the persian replacement as
        # kinge.glb. So the folder is scanned and each file is judged by the
        # piece its name contains, through the same table the checker uses -
        # `tools/piece_names.py`. The old hard-coded list of three spellings
        # meant an upload called `Knight-final.glb` was reported as a missing
        # knight while the file sat right there.
        matches = [name for name in sorted(os.listdir(source))
                   if os.path.isfile(os.path.join(source, name))
                   and os.path.splitext(name)[1].lower() in MODEL_SUFFIXES
                   and kind_of(name) == kind]
        if not matches:
            print(f"missing: no file in {source} names the {kind}", file=sys.stderr)
            return 1
        if len(matches) > 1:
            print(f"{kind}: {len(matches)} files name it ({', '.join(matches)}); using {matches[0]}",
                  file=sys.stderr)
        path = os.path.join(source, matches[0])
        vertices, faces, colours = prepare(kind, path, keep_colour)
        target = os.path.join(output, f"{kind}.obj")
        write_obj(target, kind, vertices, faces)
        tint = os.path.join(output, f"{kind}.tint")
        if colours is not None:
            write_tint(tint, colours)
            printed_colour = f"  colour {len(colours)} verts"
        else:
            if os.path.exists(tint):
                os.remove(tint)
            printed_colour = ""
        low, high = vertices.min(axis=0), vertices.max(axis=0)
        print(f"{kind:7s} {len(faces):6d} tris  height {high[1]:.3f}  "
              f"width {high[0] - low[0]:.3f}  depth {high[2] - low[2]:.3f}  "
              f"{os.path.getsize(target) // 1024} KB{printed_colour}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
