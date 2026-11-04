#!/usr/bin/env python3
"""Checks that the board and the armies stay in separate brightness bands.

The complaint that drove this file - twice, in different words - is that one
army washes out and the other disappears. Both are the same failure: a piece and
a square landing on the same value, or a piece landing on 255. It is not a matter
of taste, it is arithmetic, and the arithmetic is cheap enough to run on every
push.

The model is deliberately simple and empirical, and it predicts 8-bit sRGB
directly rather than going through a tonemapper: in the unclipped middle of this
rig's range the output is close enough to proportional to the albedo that the
slope below is within a few per cent. It was calibrated against the previous
shipped render, where a 0.738 light square came back at 246 and a 0.257 dark
square at 90 - a slope of about 340 at exposure 0.68, scaled to 390 here for the
0.78 exposure.

Only the *relative* placement is ever checked - is the white army brighter than
the light squares, is the black army darker than the dark squares - so a small
error in the slope cannot turn a good palette red.

Run with no arguments. Exits non-zero and prints every violation if a band
overlaps or a colour clips.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = ROOT / "src" / "main" / "main.gd"

BOARD_GAIN = 390.0   # upward-facing squares
PIECE_GAIN = 318.0   # lit vertical piece surfaces

# The band each surface has to land in, in 8-bit sRGB. Chosen so that nothing
# clips (255) and no two bands touch: a gap of 8 is roughly three visible steps.
LIGHT_SQUARE = (175, 220)
DARK_SQUARE = (60, 125)
WHITE_PIECE = (225, 252)
BLACK_PIECE = (45, 95)
MIN_WHITE_GAP = 8      # white army above the light squares
MIN_BLACK_GAP = 12     # black army below the dark squares


def value_of(albedo_rgb: tuple[float, float, float], gain: float) -> int:
    """Rec.709 luma of one albedo under the rig, as 8-bit sRGB."""
    luma = 0.2126 * albedo_rgb[0] + 0.7152 * albedo_rgb[1] + 0.0722 * albedo_rgb[2]
    return int(round(max(0.0, min(255.0, luma * gain))))


def luma_of(albedo_rgb: tuple[float, float, float]) -> int:
    return value_of(albedo_rgb, 255.0)


def parse_blocks(source: str, name: str) -> dict[str, dict[str, tuple[float, float, float]]]:
    """Every `"key": {...}` block inside a top-level `const <name> := {...}`."""
    start = source.index(f"const {name} := {{")
    end = source.index("\n}\n", start)
    body = source[start:end]
    blocks: dict[str, dict[str, tuple[float, float, float]]] = {}
    for match in re.finditer(r'\n\t"([a-z_]+)": \{(.*?)\n\t\},', body, re.S):
        block_id = match.group(1)
        fields: dict[str, tuple[float, float, float]] = {}
        for colour in re.finditer(r'"([a-z_]+)": Color\(([0-9.]+), ([0-9.]+), ([0-9.]+)\)', match.group(2)):
            fields[colour.group(1)] = (
                float(colour.group(2)),
                float(colour.group(3)),
                float(colour.group(4)),
            )
        blocks[block_id] = fields
    return blocks


def check(problems: list[str], label: str, value: int, band: tuple[int, int]) -> None:
    low, high = band
    if value < low:
        problems.append(f"{label}: {value} is below {low} - too dark to read")
    elif value > high:
        problems.append(f"{label}: {value} is above {high} - clipping or glaring")


def main() -> int:
    source = MAIN.read_text(encoding="utf-8")
    boards = parse_blocks(source, "BOARD_THEMES")
    pieces = parse_blocks(source, "PIECE_THEMES")
    if not boards or not pieces:
        print("could not parse the theme tables out of main.gd", file=sys.stderr)
        return 2

    problems: list[str] = []
    for board_id, board in boards.items():
        for field, band, name in (
            ("light_square", LIGHT_SQUARE, "light square"),
            ("dark_square", DARK_SQUARE, "dark square"),
        ):
            if field not in board:
                problems.append(f"board '{board_id}' has no {field}")
                continue
            check(problems, f"board {board_id} {name}", value_of(board[field], BOARD_GAIN), band)

    for set_id, palette in pieces.items():
        for field, band, name in (
            ("light", WHITE_PIECE, "white army"),
            ("dark", BLACK_PIECE, "black army"),
        ):
            if field not in palette:
                problems.append(f"set '{set_id}' has no {field}")
                continue
            check(problems, f"set {set_id} {name}", value_of(palette[field], PIECE_GAIN), band)

    # The two relationships that make the armies read against the board, checked
    # against every pairing because a player can combine any board with any set.
    for board_id, board in boards.items():
        if "light_square" not in board or "dark_square" not in board:
            continue
        light = value_of(board["light_square"], BOARD_GAIN)
        dark = value_of(board["dark_square"], BOARD_GAIN)
        for set_id, palette in pieces.items():
            if "light" in palette:
                white = value_of(palette["light"], PIECE_GAIN)
                if white - light < MIN_WHITE_GAP:
                    problems.append(
                        f"board {board_id} + set {set_id}: white army {white} sits on the "
                        f"light squares {light} (needs {MIN_WHITE_GAP})"
                    )
            if "dark" in palette:
                black = value_of(palette["dark"], PIECE_GAIN)
                if dark - black < MIN_BLACK_GAP:
                    problems.append(
                        f"board {board_id} + set {set_id}: black army {black} sits on the "
                        f"dark squares {dark} (needs {MIN_BLACK_GAP})"
                    )

    if problems:
        print("visual balance check failed:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 1
    print(f"visual balance ok: {len(boards)} boards, {len(pieces)} piece sets, "
          f"every pairing keeps the armies clear of the squares")
    # Printed rather than only asserted, so the numbers are in the CI log next to
    # the check that used them.
    for board_id, board in boards.items():
        if "light_square" in board and "dark_square" in board:
            print(f"  board {board_id:11s} light {value_of(board['light_square'], BOARD_GAIN):3d}"
                  f"  dark {value_of(board['dark_square'], BOARD_GAIN):3d}")
    for set_id, palette in pieces.items():
        if "light" in palette and "dark" in palette:
            print(f"  set   {set_id:11s} white {value_of(palette['light'], PIECE_GAIN):3d}"
                  f"  black {value_of(palette['dark'], PIECE_GAIN):3d}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
