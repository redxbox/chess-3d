#!/usr/bin/env python3
"""Read a folder of uploaded piece models and say whether it is a usable set.

This is the other half of `tools/sources/incoming/`: that folder is where the
author drops new chess pieces, and this script answers, without a 3D program and
without any dependency beyond the standard library, the four questions that
decide whether the drop can be turned into a playable set:

  * are all six pieces there, and is each one recognisably named,
  * how heavy is each one (the importer decimates, but 3 million triangles takes
    a while and 25 MB is the most a GitHub web upload will take at all),
  * how big is it and which way is up (every body is rescaled onto the height
    ladder, so the absolute size does not matter - but a model lying on its side
    does, and it cannot be rescaled out of that),
  * does it carry its own colours (materials or textures), because the game
    colours the two armies from its own palette and today ignores a model's
    material - see the README in the drop zone.

It reads OBJ, GLB and glTF directly and reports STL, PLY, FBX and DAE only well
enough to say whether they are there; the importer opens all of them.

    python3 tools/check_incoming_set.py                 # report
    python3 tools/check_incoming_set.py --strict        # exit 1 unless complete
    python3 tools/check_incoming_set.py --dir path/to   # another folder
"""

from __future__ import annotations

import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from piece_names import KINDS, MODEL_SUFFIXES, SOURCE_ONLY_SUFFIXES, kind_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(ROOT, "tools", "sources", "incoming")

# A GitHub web upload refuses anything over 25 MB, and the importer decimates
# anyway, so a large upload is a slow upload and nothing more.
WEB_UPLOAD_MB = 25.0
# Roughly the point where decimating a single body takes longer than a coffee.
HEAVY_TRIANGLES = 400_000
# The height ladder the rest of the game is tuned against; a body is rescaled to
# this, so only the *ratio* the artist chose would be lost, not the size.
LADDER = {"pawn": 0.91, "rook": 1.18, "knight": 1.33, "bishop": 1.34, "queen": 1.49, "king": 1.62}


class Model:
    """What the checker could learn about one file."""

    def __init__(self, name: str):
        self.name = name
        self.kind = kind_of(name)
        self.size_bytes = 0
        self.triangles = 0
        self.vertices = 0
        self.height = 0.0
        self.width = 0.0
        self.depth = 0.0
        self.has_material = False
        self.has_texture = False
        self.note = ""

    @property
    def mb(self) -> float:
        return self.size_bytes / (1024.0 * 1024.0)

    @property
    def upright(self) -> bool:
        """A piece is taller than it is wide; a model on its side is not."""
        if self.height <= 0.0:
            return True
        return self.height >= max(self.width, self.depth) * 0.75


def _bounds(points) -> tuple[float, float, float]:
    if not points:
        return (0.0, 0.0, 0.0)
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    zs = [p[2] for p in points]
    return (max(ys) - min(ys), max(xs) - min(xs), max(zs) - min(zs))


def read_obj(path: str, model: Model) -> None:
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    vertices = 0
    triangles = 0
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if line.startswith("v "):
                parts = line.split()
                if len(parts) < 4:
                    continue
                vertices += 1
                for axis in range(3):
                    value = float(parts[axis + 1])
                    lo[axis] = min(lo[axis], value)
                    hi[axis] = max(hi[axis], value)
            elif line.startswith("f "):
                # Any face with more than three corners is a triangle fan; the
                # importer triangulates it, so count it the same way here.
                triangles += max(0, len(line.split()) - 3)
            elif line.startswith("usemtl "):
                model.has_material = True
            elif line.startswith("vt "):
                model.has_texture = True
    model.vertices = vertices
    model.triangles = triangles
    if vertices:
        model.height = hi[1] - lo[1]
        model.width = hi[0] - lo[0]
        model.depth = hi[2] - lo[2]
    if model.has_texture:
        model.note = "has UVs"


def _gltf_json(path: str, model: Model) -> dict:
    if path.lower().endswith(".glb"):
        with open(path, "rb") as handle:
            header = handle.read(12)
            if len(header) < 12:
                raise ValueError("not a GLB: too short")
            magic, _version, _length = struct.unpack("<4sII", header)
            if magic != b"glTF":
                raise ValueError("not a GLB: bad magic")
            while True:
                chunk_header = handle.read(8)
                if len(chunk_header) < 8:
                    break
                chunk_length, chunk_type = struct.unpack("<II", chunk_header)
                payload = handle.read(chunk_length)
                if chunk_type == 0x4E4F534A:  # 'JSON'
                    return json.loads(payload.decode("utf-8", errors="replace"))
        raise ValueError("GLB has no JSON chunk")
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return json.load(handle)


def read_gltf(path: str, model: Model) -> None:
    document = _gltf_json(path, model)
    accessors = document.get("accessors", [])
    vertices = 0
    triangles = 0
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            position = primitive.get("attributes", {}).get("POSITION")
            if position is None or position >= len(accessors):
                continue
            accessor = accessors[position]
            vertices += int(accessor.get("count", 0))
            # The min/max in an accessor are the exporter's own bounds, which is
            # exactly what is needed here and costs nothing: reading a 3-million
            # triangle buffer to measure it would take longer than the import.
            if "min" in accessor and "max" in accessor and len(accessor["min"]) == 3:
                for axis in range(3):
                    lo[axis] = min(lo[axis], float(accessor["min"][axis]))
                    hi[axis] = max(hi[axis], float(accessor["max"][axis]))
            index = primitive.get("indices")
            if index is not None and index < len(accessors):
                triangles += int(accessors[index].get("count", 0)) // 3
            else:
                triangles += int(accessor.get("count", 0)) // 3
    model.vertices = vertices
    model.triangles = triangles
    if lo[0] < float("inf"):
        model.height = hi[1] - lo[1]
        model.width = hi[0] - lo[0]
        model.depth = hi[2] - lo[2]
    model.has_material = bool(document.get("materials"))
    model.has_texture = bool(document.get("images")) or bool(document.get("textures"))
    if model.has_texture:
        model.note = "textures embedded"
    elif model.has_material:
        model.note = "materials, no textures"
    # Bounds are per primitive and ignore the node transform that places it, so
    # a model assembled from scaled or rotated nodes can read differently here
    # than it renders. Say so instead of pretending the number is exact.
    if any(node.get("matrix") or node.get("scale") or node.get("rotation")
           for node in document.get("nodes", [])):
        model.note = (model.note + "; node transforms present, size is approximate").strip("; ")


def read_stl(path: str, model: Model) -> None:
    with open(path, "rb") as handle:
        header = handle.read(84)
        if len(header) < 84:
            raise ValueError("not an STL: too short")
        count = struct.unpack("<I", header[80:84])[0]
        expected = 84 + count * 50
        if os.path.getsize(path) < expected - 8:
            raise ValueError("not a binary STL (ASCII STL cannot be measured here)")
        model.triangles = count
        model.vertices = count * 3
        model.note = "positions only, no colour"


def read_ply(path: str, model: Model) -> None:
    vertices = faces = 0
    with open(path, "rb") as handle:
        for _ in range(200):
            line = handle.readline().decode("ascii", errors="replace").strip()
            if line.startswith("element vertex "):
                vertices = int(line.split()[-1])
            elif line.startswith("element face "):
                faces = int(line.split()[-1])
            elif line == "end_header":
                break
    model.vertices = vertices
    model.triangles = faces
    model.note = "positions only"


def measure(name: str, directory: str) -> Model:
    path = os.path.join(directory, name)
    model = Model(name)
    model.size_bytes = os.path.getsize(path)
    suffix = os.path.splitext(name)[1].lower()
    try:
        if suffix == ".obj":
            read_obj(path, model)
        elif suffix in (".glb", ".gltf"):
            read_gltf(path, model)
        elif suffix == ".stl":
            read_stl(path, model)
        elif suffix == ".ply":
            read_ply(path, model)
        else:
            model.note = "opened by the importer; not measured here"
    except Exception as error:  # noqa: BLE001 - a broken upload is a report, not a crash
        model.note = f"UNREADABLE: {error}"
    return model


def survey(directory: str) -> tuple[list[Model], list[str]]:
    models: list[Model] = []
    unnamed: list[str] = []
    if not os.path.isdir(directory):
        return models, unnamed
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path) or name.startswith(".") or name.lower().endswith(".md"):
            continue
        suffix = os.path.splitext(name)[1].lower()
        if suffix in SOURCE_ONLY_SUFFIXES:
            unnamed.append(f"{name} (a modelling source - export it as .glb first)")
            continue
        if suffix not in MODEL_SUFFIXES:
            unnamed.append(f"{name} (not a 3D file this pipeline reads)")
            continue
        if kind_of(name) == "":
            unnamed.append(f"{name} (no piece name in the filename)")
            continue
        models.append(measure(name, directory))
    return models, unnamed


def main(argv: list[str]) -> int:
    strict = "--strict" in argv
    directory = DEFAULT_DIR
    if "--dir" in argv:
        directory = argv[argv.index("--dir") + 1]

    models, unnamed = survey(directory)
    print(f"drop zone: {os.path.relpath(directory, ROOT)}")

    if not models and not unnamed:
        print("empty - nothing waiting to be imported. See the README beside it.")
        return 0

    by_kind: dict[str, list[Model]] = {kind: [] for kind in KINDS}
    for model in models:
        by_kind[model.kind].append(model)

    problems: list[str] = []
    print()
    print(f"{'piece':7s} {'file':26s} {'tris':>9s} {'height':>7s} {'width':>6s} {'MB':>6s}  colour")
    for kind in KINDS:
        found = by_kind[kind]
        if not found:
            print(f"{kind:7s} {'-':26s} {'':>9s} {'':>7s} {'':>6s} {'':>6s}  MISSING")
            continue
        if len(found) > 1:
            problems.append(
                f"{kind}: {len(found)} files claim it ({', '.join(m.name for m in found)}) "
                f"- keep one per piece, or rename the others")
        model = found[0]
        colour = "yes" if model.has_texture else ("materials" if model.has_material else "no")
        print(f"{kind:7s} {model.name[:26]:26s} {model.triangles:9d} "
              f"{model.height:7.3f} {model.width:6.3f} {model.mb:6.2f}  {colour}")
        if model.note.startswith("UNREADABLE"):
            problems.append(f"{model.name}: {model.note}")
        if model.mb > WEB_UPLOAD_MB:
            problems.append(f"{model.name}: {model.mb:.1f} MB - GitHub's web upload stops at "
                            f"{WEB_UPLOAD_MB:.0f} MB; export a lighter mesh")
        elif model.mb > 10.0:
            problems.append(f"{model.name}: {model.mb:.1f} MB is a heavy upload, "
                            f"the importer will decimate it anyway")
        if model.triangles > HEAVY_TRIANGLES:
            problems.append(f"{model.name}: {model.triangles / 1e6:.2f}M triangles - "
                            f"decimating this takes minutes; decimating in the modelling "
                            f"tool first is kinder")
        if not model.upright:
            problems.append(f"{model.name}: {model.height:.3f} tall by {model.width:.3f} wide - "
                            f"it looks like it is lying on its side; +Y is up")

    for note in unnamed:
        problems.append(f"ignored: {note}")

    missing = [kind for kind in KINDS if not by_kind[kind]]
    if missing:
        problems.append(f"missing: {', '.join(missing)}")

    heights = [model.height for model in models if model.height > 0]
    if len(heights) >= 3 and (max(heights) - min(heights)) <= max(heights) * 0.01:
        # Not a problem, but it is worth saying out loud: the previous two sets
        # both arrived with every piece exactly one unit tall, which is why the
        # importer has a height ladder in the first place.
        print()
        print("note: every piece is the same height - the importer will put them on the "
              "height ladder (pawn 0.91 ... king 1.62) rather than keep that.")

    print()
    if problems:
        print("to fix before this can be imported:")
        for problem in problems:
            print(f"  - {problem}")
    else:
        print("complete set, nothing to fix.")
        print()
        print("next, turn it into a playable set:")
        print(f"  python3 tools/prepare_sculpt_set.py {os.path.relpath(directory, ROOT)} "
              f"assets/models/<set-name>")
        print("  python3 tools/normalise_set_scale.py")

    if strict and (problems or missing):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
