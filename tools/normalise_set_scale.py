#!/usr/bin/env python3
"""Put every piece set on the classic set's measurements.

The three sets were modelled independently and arrived at three different sizes:
the classic set's bases are 0.261 of the square for a pawn and 0.326 for
everything else, the persian set's are up to 30 per cent wider, and the bastani
set's are up to 20 per cent narrower. On the board that reads as three
different-sized chess sets rather than one game with three styles, which is what
the player sees and what this script fixes.

For each (set, kind) two scale factors are applied to the shipped OBJ:

  * x/z, so the foot of the piece measures the same radius as the classic piece
    of that kind. The foot is measured at 8 per cent of the piece's height,
    which is below every silhouette change on all three sets and is therefore
    the width a player actually reads as "how big is this piece";
  * y, so the piece is exactly as tall as the classic piece of that kind.

Height and footprint are the two things a player compares between sets, so
matching both is what makes the sets interchangeable. The classic set is the
reference because it is the one whose size the author approved.

Vertex order, face order and every other attribute are preserved: only the `v`
lines are rewritten, so the files stay byte-identical apart from the numbers.

    python3 tools/normalise_set_scale.py            # rewrite the assets
    python3 tools/normalise_set_scale.py --check    # report, change nothing
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "assets", "models")
REFERENCE = "staunton"
SETS = ("persian", "bastani")
KINDS = ("pawn", "rook", "knight", "bishop", "queen", "king")
FOOT_FRACTION = 0.08


def read_obj(path):
    with open(path) as handle:
        lines = handle.readlines()
    vertices = []
    for index, line in enumerate(lines):
        if line.startswith("v "):
            parts = line.split()
            vertices.append((index, float(parts[1]), float(parts[2]), float(parts[3])))
    return lines, vertices


def measure(vertices):
    heights = [y for _, _, y, _ in vertices]
    low, high = min(heights), max(heights)
    foot_limit = low + (high - low) * FOOT_FRACTION
    foot = max((x * x + z * z) ** 0.5 for _, x, y, z in vertices if y <= foot_limit)
    return high - low, foot


def main(argv):
    check = "--check" in argv
    reference = {}
    for kind in KINDS:
        lines, vertices = read_obj(os.path.join(MODELS, REFERENCE, f"{kind}.obj"))
        reference[kind] = measure(vertices)

    print(f"{'set':9s} {'kind':8s} {'height':>16s} {'foot radius':>16s} {'scale xz':>9s} {'scale y':>8s}")
    for set_name in SETS:
        for kind in KINDS:
            path = os.path.join(MODELS, set_name, f"{kind}.obj")
            lines, vertices = read_obj(path)
            height, foot = measure(vertices)
            ref_height, ref_foot = reference[kind]
            scale_xz = ref_foot / foot
            scale_y = ref_height / height
            print(
                f"{set_name:9s} {kind:8s} "
                f"{height:7.3f} -> {ref_height:5.3f} "
                f"{foot:7.3f} -> {ref_foot:5.3f} "
                f"{scale_xz:9.4f} {scale_y:8.4f}"
            )
            if check:
                continue
            for index, x, y, z in vertices:
                lines[index] = f"v {x * scale_xz:.5f} {y * scale_y:.5f} {z * scale_xz:.5f}\n"
            with open(path, "w") as handle:
                handle.writelines(lines)
    if check:
        print("\ncheck only - nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
