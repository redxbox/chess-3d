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

4. `--colours`: bake the sculpture's own colour per vertex into `<kind>.tint`
   beside the OBJ, in both armies. See write_tint() for the layout and the
   grading rules, and main.gd's `_read_tint()` for the other end.

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
    """The mesh's own per-vertex colour, sampled from whatever it arrives as.

    A GLB can carry its colour three ways - a baked texture atlas with UVs, a
    colour per vertex, or a single flat material colour - and `trimesh` will
    flatten all three into vertex colours with `visual.to_color()`. Sampling the
    atlas per vertex is what makes a coloured upload survive decimation: the
    texture is a few megabytes of image that would have to be shipped and UV'd,
    while 3 bytes per vertex costs 30 KB and needs no texture unit at all.
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
## Everything below is done in sRGB, and that is the decision this block exists
## to record. The palette in main.gd - ivory 0.68, charcoal 0.32 - is written in
## sRGB, and tools/check_visual_balance.py measures it in that space. A first
## version of this file did its arithmetic in linear light, which is the correct
## space for multiplying light and the wrong space for matching a palette: the
## "dark" army came out at 0.32 *linear*, which is 0.60 on screen, and rendered
## as a mid-brown piece rather than a black one. sRGB numbers are what the artist
## and the checker both speak, so the bake speaks it too and converts once, at
## the end, into what the shader wants.
##
## Three things happen to the uploaded colours:
##
##   1. A tone squeeze. The atlas spans nearly black to bright gold, and the
##      render cannot use that range: past about 0.78 the key light clips and the
##      piece is a white cut-out, which is the failure this project has shipped
##      twice. Each piece's colours are mapped onto their own percentile ranks,
##      between PALE_FLOOR and PALE_CEILING. Ranking rather than scaling is what
##      keeps the gold gold and the silver silver: the order of the pixels is
##      untouched, only the distance between them is compressed.
##
##   2. The second army. The reference image the author supplied is the same
##      sculpture in black armour - same gold trim, same red plume, everything
##      else dark - so the ink army is the pale army with a gamma and a gain. The
##      gamma is what puts the contrast back: at 1.6 the dark cloth and the skin
##      fall away while the gilding keeps half its brightness, which a plain
##      multiply did not do (measured: the gold ended up 1.35x the body instead of
##      the 2.5x the photograph has).
##
##   3. Both armies land in the bands the rest of the game lives in.
##      tools/check_visual_balance.py checks that against every board, and the
##      render measurement (tools/measure_preview.py, on a real Godot frame)
##      is the final word: at an ink median of 0.322 - the value that matches the
##      other two sets' palette charcoal exactly - the pars black pawns rendered
##      at 25 of 255 on the royal_blue board, under the 30 floor. The reason is
##      that the palette number is one flat albedo while this army is a mix, and
##      its darks are darker than its median. 0.345 is where the render lands
##      inside the band with its own mix.
##
## The two numbers were not guessed. The first attempt - pale 0.60, ink 0.25 -
## sat 0.05 from the light squares and 0.01 from the dark ones, i.e. a gold piece
## vanished into a gold-adjacent square; the second was 1.9x apart when the rule
## wants 2x. Both were caught by that checker, not by the eye.
PALE_TARGET = 0.70
PALE_GAMMA = 0.62
PALE_CEILING = 0.84
INK_MEDIAN = 0.345
INK_GAMMA = 1.6
INK_LIFT = np.array([0.006, 0.007, 0.010])


def luma(rgb: np.ndarray) -> np.ndarray:
    return 0.2126 * rgb[:, 0] + 0.7152 * rgb[:, 1] + 0.0722 * rgb[:, 2]


def pale_army(colours: np.ndarray) -> np.ndarray:
    """The uploaded colours (sRGB 0-1), squeezed into the brightness band the render can use.

    The squeeze is a uniform multiply per vertex, so it cannot change a hue: the
    red of the plume stays red at every brightness. That property is the whole
    reason it is written this way - the first version mapped each piece's colours
    onto their percentile ranks instead, which preserves contrast but not hue, and
    the set came out orange plastic: the dark pixels got multiplied far harder
    than the bright ones, so every channel that was already warm clipped first.
    """
    values = np.maximum(luma(colours), 1e-4)
    median = float(np.median(values))
    target = np.minimum(PALE_TARGET * np.power(values / median, PALE_GAMMA), PALE_CEILING)
    out = colours * (target / values)[:, None]
    high = out.max(axis=1, keepdims=True)
    return np.clip(np.where(high > 1.0, out / np.maximum(high, 1e-6), out), 0.0, 1.0)


def ink_gain(pale: np.ndarray) -> float:
    """The gain that puts the ink army's median on INK_MEDIAN.

    Derived per set rather than fixed, because that median is where the
    arithmetic has to land: tools/check_visual_balance.py wants the two armies at
    least 2x apart AND each at least 0.06 clear of every square it can stand on.
    The dark squares sit at 0.23-0.26 and the dark army's band tops out at 0.35,
    so an ink median has one narrow place to live - 0.32, where the other two
    sets' charcoal is.
    """
    median = float(np.median(luma(ink_army(pale, 1.0))))
    return float(np.clip(INK_MEDIAN / max(median, 1e-4), 0.05, 2.0))


def ink_army(pale: np.ndarray, gain: float) -> np.ndarray:
    """The same piece in dark armour: the gold stays the brightest thing on it."""
    curved = np.power(np.clip(pale, 0.0, 1.0), INK_GAMMA) * gain
    return np.clip(curved + INK_LIFT, 0.0, 1.0)


def tint_luma(colours_srgb: np.ndarray) -> float:
    return float(np.median(luma(np.asarray(colours_srgb, dtype=np.float64) / 255.0)))


def write_tint(path: str, colours: np.ndarray) -> None:
    """Write the pale army's vertex colours beside the OBJ, in the OBJ's vertex order.

    Layout, all little-endian:

        b"TINT"   uint8 version (3)   uint32 vertex count
        float32 ink_gain, ink_gamma, ink_r, ink_g, ink_b    <- the ink army's rule
        count x RGB, one sRGB byte triple per vertex

    Only the pale army is stored. The ink army is `pale ** ink_gamma * ink_gain
    + ink` in sRGB, and those five numbers travel in the header rather than being
    written out as a second colour per vertex: that would put the packaged
    content over its budget for data the game can compute for the cost of one
    power. main.gd's `_read_tint()` is the other end of this file, and
    tools/check_visual_balance.py reads it too - the numbers in docs are the
    numbers the game draws.

    A sidecar rather than an OBJ feature: OBJ has no agreed vertex-colour syntax,
    and the game's own OBJ reader rebuilds the vertex array anyway. Three bytes a
    vertex is 15 KB for a whole piece, against 1.3 MB for the atlas it was
    sampled from.
    """
    pale = pale_army(np.asarray(colours, dtype=np.float64) / 255.0)
    gain = ink_gain(pale)
    stored = np.clip(np.round(pale * 255.0), 0, 255).astype(np.uint8)
    with open(path, "wb") as handle:
        handle.write(b"TINT")
        handle.write(bytes([3]))
        handle.write(len(stored).to_bytes(4, "little"))
        handle.write(np.asarray([gain, INK_GAMMA], dtype="<f4").tobytes())
        handle.write(np.asarray(INK_LIFT, dtype="<f4").tobytes())
        handle.write(np.ascontiguousarray(stored, dtype=np.uint8).tobytes())


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
