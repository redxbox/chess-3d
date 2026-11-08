"""Which chess piece an uploaded file is, judged only from its name.

The author's exports have never followed one convention: the bastani set
arrived as `pown1.glb` / `quin1.glb`, the persian replacement as `kinge.glb`,
and the next set may well come as `شاه.fbx` or `Knight-final-v2.glb`. Rather
than make someone rename their files - which is how a piece goes missing - both
`tools/check_incoming_set.py` and `tools/prepare_sculpt_set.py` ask this module
what a file is.

Kept in one place so the checker's verdict and the importer's file choice cannot
disagree, which they would if each had its own list.
"""

from __future__ import annotations

import os

KINDS = ("pawn", "rook", "knight", "bishop", "queen", "king")

# Lower-case fragments, longest and least ambiguous first. English first because
# that is what the last two sets used, then the Persian names, then the plain
# English synonyms a modelling tool might export. "castle" and "tower" are the
# rook, "horse" the knight, "elephant" the bishop (the bastani bishop is one),
# and "vizier" the queen - the figure, not the piece.
ALIASES = {
    "knight": ("knight", "horse", "asb", "اسب"),
    "bishop": ("bishop", "elephant", "fil", "فیل"),
    "queen": ("queen", "quin", "quee", "vizier", "vazir", "minister", "وزیر", "ملکه"),
    "king": ("king", "shah", "monarch", "شاه"),
    "rook": ("rook", "rukh", "castle", "tower", "rokh", "رخ"),
    "pawn": ("pawn", "pown", "pwan", "soldier", "guard", "peon", "سرباز", "پیاده"),
}

# Formats trimesh can open, best first. `.glb` is the one to prefer: one file,
# textures inside it, and no chance of an .obj arriving without its .mtl.
MODEL_SUFFIXES = (".glb", ".gltf", ".obj", ".stl", ".ply", ".fbx", ".dae")

# Things a modelling program opens but nothing in this pipeline can.
SOURCE_ONLY_SUFFIXES = (".blend", ".max", ".ma", ".mb", ".c4d", ".ztl", ".zpr")


def kind_of(filename: str) -> str:
    """The piece a filename names, or "" if it names none.

    Matching is on the stem only, and the longest alias wins, so `knight-ox.obj`
    is a knight and `king-crown.obj` is a king - a plain `king in name` test
    would call the second one a knight's cousin and the first one whatever came
    first in the list.
    """
    stem = os.path.splitext(os.path.basename(filename))[0].lower()
    best: tuple[int, str] = (0, "")
    for kind, aliases in ALIASES.items():
        for alias in aliases:
            if alias in stem and len(alias) > best[0]:
                best = (len(alias), kind)
    return best[1]


def scan(directory: str) -> dict[str, list[str]]:
    """Every model file in `directory`, grouped by the piece it names.

    Files whose names name no piece are returned under the key "" so a caller
    can report them rather than silently ignore an upload.
    """
    found: dict[str, list[str]] = {kind: [] for kind in KINDS}
    found[""] = []
    if not os.path.isdir(directory):
        return found
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        if name.startswith(".") or name.lower().endswith(".md"):
            continue
        suffix = os.path.splitext(name)[1].lower()
        if suffix in SOURCE_ONLY_SUFFIXES:
            found[""].append(name)
            continue
        if suffix not in MODEL_SUFFIXES:
            found[""].append(name)
            continue
        found[kind_of(name)].append(name)
    return found
