#!/usr/bin/env python3
"""Check that the board and the two armies are built from separable albedoes.

Two rounds in a row the user's complaint was really one arithmetic failure: an
army and a square landing on the same value, so the pieces vanished into the
board, or the pale army sitting at 255 where ACES has nothing left to shade.

That failure is visible in the palettes themselves, before anything is rendered:

  * a pale army albedo that is close to the light squares' - the white pieces
    then have nothing but their own shading to stand out with, and on a phone
    seen at arm's length they do not;
  * a dark army albedo that is close to the dark squares' - the same failure
    from the other end;
  * an albedo past about 0.75, which this rig's key light drives past 1.0, and
    a clipped piece has no carving left on it at all.

What the numbers were measured to produce is in docs/previews and is checked
end-to-end by tools/measure_preview.py against a real render. This script is the
cheap guard that runs on every push, on every board and set, without a GPU.
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN_GD = ROOT / "src" / "main" / "main.gd"

# Albedo bands. These are the colour components as written in PIECE_THEMES, which
# the renderer converts from sRGB to linear - see the comment in main.gd for why
# the shipped ivory is 0.72 and not the 0.88 a brief asked for. The upper edge is
# where the measured render clips: 0.88 put 30% of the pale army at 250+, 0.72
# keeps it near 10%, and this band is what stops the next albedo bump walking back
# into it.
LIGHT_SQUARE = (0.42, 0.58)
DARK_SQUARE = (0.10, 0.27)
PALE_ARMY = (0.55, 0.78)
DARK_ARMY = (0.28, 0.35)

# How far apart an army and the square it can stand on have to be, in luma.
#
# 0.06 rather than something larger because a dark army cannot be pushed much
# further from a dark square without becoming grey: the mahogany board's dark
# square is 0.22 and the charcoal army is 0.30, and at that spacing the render
# measurement shows a 25-point gap on screen. Below about 0.06 the piece is
# distinguishable only by its specular ring, which is what the previous round
# shipped and what the user reported as "the black side cannot be recognised".
MIN_TERRITORY_LUMA = 0.06


def luma(rgb: tuple[float, float, float]) -> float:
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def parse_theme_table(source: str, name: str) -> dict[str, dict[str, tuple[float, ...]]]:
    """Pull `const NAME := { "id": { "key": Color(r, g, b), ... }, ... }` apart."""
    start = source.index(f"const {name} := {{")
    depth = 0
    end = start
    for offset, char in enumerate(source[start:], start):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = offset + 1
                break
    block = source[start:end]

    entries: dict[str, dict[str, tuple[float, ...]]] = {}
    for entry in re.finditer(r'"([a-z_]+)": \{(.*?)\n\t\}', block, re.S):
        theme_id, body = entry.group(1), entry.group(2)
        values: dict[str, tuple[float, ...]] = {}
        for line in body.splitlines():
            match = re.match(r'\s*"([a-z_]+)": Color\(([^)]*)\),', line)
            if match:
                channels = tuple(float(part.strip()) for part in match.group(2).split(","))
                values[match.group(1)] = channels
            match = re.match(r'\s*"([a-z_]+)": ([0-9.]+),', line)
            if match:
                values[match.group(1)] = (float(match.group(2)),)
            # String and boolean flags as well: `vertex_colour` and `model_set`
            # select a different source of albedo for a set that carries its own.
            match = re.match(r'\s*"([a-z_]+)": "([a-z_]+)",', line)
            if match:
                values[match.group(1)] = (match.group(2),)
            match = re.match(r'\s*"([a-z_]+)": (true|false),', line)
            if match:
                values[match.group(1)] = (match.group(2) == "true",)
        entries[theme_id] = values
    return entries


def srgb_to_linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def tinted_armies(palette: dict[str, tuple[float, ...]]) -> tuple[float, float] | None:
    """The pale/ink albedos of a set whose colours are baked into the mesh.

    A set marked `vertex_colour` has a white multiplier in PIECE_THEMES on
    purpose: the albedo is the `.tint` sidecar next to its OBJs, one RGB per
    vertex per army. Reading the palette there would measure the multiplier and
    conclude the set is two white armies. So the sidecar is read instead, and the
    numbers checked are the ones the mesh actually carries - median linear luma
    over every vertex of all six pieces, which is the same statistic this script
    uses for the other sets' flat albedos.
    """
    if not palette.get("vertex_colour", (False,))[0]:
        return None
    entry = palette.get("model_set")
    if not entry or not isinstance(entry[0], str):
        return None
    model_set = entry[0]
    directory = ROOT / "assets" / "models" / model_set
    pale_values: list[float] = []
    ink_values: list[float] = []
    for path in sorted(directory.glob("*.tint")):
        raw = path.read_bytes()
        if raw[:4] != b"TINT" or raw[4] != 3:
            continue
        count = int.from_bytes(raw[5:9], "little")
        gain, gamma = struct.unpack("<ff", raw[9:17])
        lift = struct.unpack("<fff", raw[17:29])
        for i in range(count):
            r, g, b = raw[29 + i * 3: 32 + i * 3]
            # Linear, like the palette values of the other two sets: the bands in
            # this file are linear luma, and Godot treats an albedo as linear, so
            # the sidecar's bytes are read back through sRGB first.
            pale = tuple(srgb_to_linear(c / 255.0) for c in (r, g, b))
            pale_values.append(luma(pale))
            ink_values.append(luma(tuple(min(1.0, pow(c, gamma) * gain + l) for c, l in zip(pale, lift))))
    if not pale_values:
        return None
    pale_values.sort()
    ink_values.sort()
    return (pale_values[len(pale_values) // 2], ink_values[len(ink_values) // 2])


def band_problem(label: str, value: float, band: tuple[float, float]) -> str | None:
    low, high = band
    if value < low:
        return f"{label}: {value:.3f} is below {low:.2f} - too dark to read on a phone"
    if value > high:
        return f"{label}: {value:.3f} is above {high:.2f} - it will clip"
    return None


def main() -> int:
    source = MAIN_GD.read_text()
    boards = parse_theme_table(source, "BOARD_THEMES")
    pieces = parse_theme_table(source, "PIECE_THEMES")

    problems: list[str] = []
    print("albedoes (Rec.709 luma, as written in the theme tables)")

    for board_id, board in boards.items():
        if "light_square" not in board or "dark_square" not in board:
            problems.append(f"board {board_id} has no light_square / dark_square")
            continue
        light = luma(board["light_square"])
        dark = luma(board["dark_square"])
        print(f"  board {board_id:11s} light {light:.3f}  dark {dark:.3f}")
        for label, value, band in (
            (f"board {board_id} light square", light, LIGHT_SQUARE),
            (f"board {board_id} dark square", dark, DARK_SQUARE),
        ):
            problem = band_problem(label, value, band)
            if problem:
                problems.append(problem)

    for set_id, palette in pieces.items():
        if "light" not in palette or "dark" not in palette:
            problems.append(f"set {set_id} has no light / dark body colour")
            continue
        measured = tinted_armies(palette)
        if measured is not None:
            pale, dark = measured
            print(f"  set   {set_id:11s} pale {pale:.3f}  dark {dark:.3f}   (measured from the .tint sidecars)")
        else:
            pale = luma(palette["light"])
            dark = luma(palette["dark"])
            print(f"  set   {set_id:11s} pale {pale:.3f}  dark {dark:.3f}")
        for label, value, band in (
            (f"set {set_id} pale army", pale, PALE_ARMY),
            (f"set {set_id} dark army", dark, DARK_ARMY),
        ):
            problem = band_problem(label, value, band)
            if problem:
                problems.append(problem)
        if dark > 0 and pale / dark < 2.0:
            problems.append(
                f"set {set_id}: the two armies are only {pale / dark:.1f}x apart in "
                f"albedo (needs 2.0) - they will read as one colour")

    # Every board can be worn with every set, so every pairing has to work.
    for board_id, board in boards.items():
        if "light_square" not in board or "dark_square" not in board:
            continue
        light = luma(board["light_square"])
        dark = luma(board["dark_square"])
        for set_id, palette in pieces.items():
            if "light" not in palette or "dark" not in palette:
                continue
            measured = tinted_armies(palette)
            if measured is not None:
                pale, army = measured
            else:
                pale = luma(palette["light"])
                army = luma(palette["dark"])
            # Both armies stand on both colours of square, so what matters is the
            # distance in either direction, not the sign: a charcoal piece that is
            # lighter than the dark square reads fine, it just has to be
            # decisively lighter rather than nearly equal.
            for name, value in (("pale", pale), ("dark", army)):
                for square_name, square in (("light", light), ("dark", dark)):
                    if abs(value - square) < MIN_TERRITORY_LUMA:
                        problems.append(
                            f"board {board_id} + set {set_id}: the {name} army "
                            f"({value:.3f}) is only {abs(value - square):.3f} from the "
                            f"{square_name} squares ({square:.3f}), needs "
                            f"{MIN_TERRITORY_LUMA:.2f}")

    if problems:
        print("visual balance check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1

    print(f"visual balance ok: {len(boards)} boards, {len(pieces)} piece sets, "
          f"every pairing keeps the armies clear of the squares")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
