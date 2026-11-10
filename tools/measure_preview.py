#!/usr/bin/env python3
"""Measure a rendered preview against the brightness bands it is supposed to hit.

The board and piece albedoes are checked arithmetically by
tools/check_visual_balance.py, but that check cannot see the render: exposure,
ACES, the light rig and the baked vertex occlusion all sit between an albedo and
a pixel. Two rounds of "the white army is a flat white blob" and "the black army
cannot be recognised" were both only visible in the pixels.

So this script reads the PNGs that the visual-preview job has just rendered and
measures them where the camera rig says the board is. It knows the camera's
position from src/main/camera_rig.gd, so it stays correct when the rig changes:

  * the light and dark squares, sampled near their corners, away from the pieces
    standing on the middle of each square;
  * each army, sampled on the body of its pawns, in a box scaled by how large a
    square is on screen at that rank - a fixed pixel offset is what made an
    earlier measurement read the far army as nine times darker than the near one;
  * the background, which is the largest area of the frame and must not be
    tinted.

Usage: measure_preview.py RENDER.png [RENDER.png ...]
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RIG = ROOT / "src" / "main" / "camera_rig.gd"

# Bands. Screen values, 0-255, measured on the renders under docs/previews.
# The numbers are what the round is trying to achieve, not what a previous build
# happened to produce - the point of the check is to catch a change that moves
# away from them.
LIGHT_SQUARE = (175.0, 225.0)
DARK_SQUARE = (40.0, 110.0)
PALE_ARMY_MEDIAN = (175.0, 245.0)   # ivory: bright, with room under 255 to shade
PALE_ARMY_MAX_CLIPPED = 0.15        # share of the piece allowed at or above 250
DARK_ARMY_MEDIAN = (30.0, 110.0)    # charcoal, not a hole in the board
DARK_ARMY_MIN_LIT = 100.0           # p90: the lit top has to exist
# The backdrop is a warm studio sky now, not a black void: the reference the
# author pointed at has a sand-coloured wall behind the set, and it is what makes
# a cream piece and a charcoal piece read as objects in a room. The band is
# therefore bright, and the guard that used to be "neutral" is "warm" - red over
# green over blue - because the failure it was written for was a mauve/magenta
# backdrop, which is now caught as the opposite ordering rather than as a spread.
# At the higher camera the frame is nearly all board: the top-left corner is the
# table or the sky depending on how wide the window is, and both are the same warm
# family now, so the band is the whole warm range rather than one studio wall.
BACKGROUND = (110.0, 215.0)
BACKGROUND_WARMTH = (2.0, 45.0)  # red minus blue: warm, but not orange
# The gold trim: the crowns, collars and inlay bands. It is a metallic material,
# so if there is nothing for it to reflect it renders as a dark ring - which is
# what "the gold looks like mud" was. These are counts and a floor, not a target:
# the trim is a few hundred pixels at this resolution and its brightness is a
# specular lobe, so the check only asks that it exists and is bright somewhere.
GOLD_MIN_PIXELS = 600
GOLD_MIN_BRIGHT = 150.0


def camera_rig() -> tuple[float, float, float]:
    """(elevation_deg, fov_deg, distance) straight out of the rig module."""
    source = RIG.read_text()

    def constant(name: str) -> float:
        match = re.search(rf"^const {name} := ([0-9.]+)", source, re.M)
        if not match:
            raise SystemExit(f"camera_rig.gd has no {name}")
        return float(match.group(1))

    return constant("ELEVATION_DEG"), constant("FOV"), constant("DISTANCE_DEFAULT")


class View:
    """The camera of the render, projected onto the image."""

    def __init__(self, width: int, height: int) -> None:
        elevation, fov, distance = camera_rig()
        angle = math.radians(elevation)
        self.origin = np.array([0.0, distance * math.sin(angle), distance * math.cos(angle)])
        self.width, self.height = width, height
        self.tan = math.tan(math.radians(fov) / 2)
        forward = -self.origin / np.linalg.norm(self.origin)
        right = np.cross(forward, np.array([0.0, 1.0, 0.0]))
        right /= np.linalg.norm(right)
        self.forward, self.right, self.up = forward, right, np.cross(right, forward)

    def project(self, point: tuple[float, float, float]) -> tuple[float, float]:
        delta = np.array(point) - self.origin
        depth = delta @ self.forward
        x = (delta @ self.right) / depth / (self.tan * self.width / self.height)
        y = (delta @ self.up) / depth / self.tan
        return ((x * 0.5 + 0.5) * self.width, (0.5 - y * 0.5) * self.height)

    def square_centre(self, file: int, rank: int) -> tuple[float, float]:
        # Rank 1 is the near edge of the board, where the camera is, so the board
        # z runs 3.5 down to -3.5 as the rank climbs. Getting this backwards
        # measures the far army as the pale one, which is exactly the sort of
        # sign error that made an earlier eyeballed comparison useless.
        return self.project((file - 3.5, 0.0, 4.5 - rank))

    def square_size(self, file: int, rank: int) -> float:
        left = self.square_centre(file, rank)
        right = self.square_centre(file + 1, rank)
        return abs(right[0] - left[0])


def luma(rgb: np.ndarray) -> np.ndarray:
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def crop(pixels: np.ndarray, centre: tuple[float, float], size: float) -> np.ndarray:
    x, y = int(round(centre[0])), int(round(centre[1]))
    half = max(1, int(round(size / 2)))
    patch = pixels[max(0, y - half):y + half + 1, max(0, x - half):x + half + 1]
    return patch.reshape(-1, 3)


BOARD_RENDERS = {"classic-classic", "royal_wood-classic", "jade-classic", "royal_blue-classic"}


def is_board_render(path: Path) -> bool:
    """Only the wide board renders are measured geometrically.

    The close-up and the style screen are published for a human to look at: the
    close-up is a different camera and the picker is a UI screenshot, so running
    the board's bands over them reports five failures that mean nothing. The
    guard is a list of the renders this script knows how to project, not a guess
    about their contents.
    """
    return path.stem in BOARD_RENDERS


def measure(path: Path) -> list[str]:
    image = Image.open(path).convert("RGB")
    pixels = np.asarray(image).astype(float)
    view = View(image.width, image.height)
    problems: list[str] = []
    print(f"== {path.name}")

    # Squares, sampled near their corners so a piece standing on the square is
    # not what gets measured. The middle four ranks are empty at the start of a
    # game, which is what the previews render.
    light: list[float] = []
    dark: list[float] = []
    for file in range(8):
        for rank in range(3, 7):
            size = view.square_size(file, rank)
            for dx, dy in ((-0.3, -0.3), (0.3, -0.3), (-0.3, 0.3), (0.3, 0.3)):
                centre = view.square_centre(file, rank)
                centre = (centre[0] + dx * size, centre[1] + dy * size)
                value = float(luma(crop(pixels, centre, size * 0.16)).mean())
                (light if (file + rank) % 2 == 0 else dark).append(value)
    light_median, dark_median = float(np.median(light)), float(np.median(dark))
    print(f"   light squares  median {light_median:6.1f}")
    print(f"   dark  squares  median {dark_median:6.1f}")
    for label, value, band in (
        ("light square", light_median, LIGHT_SQUARE),
        ("dark square", dark_median, DARK_SQUARE),
    ):
        if not band[0] <= value <= band[1]:
            problems.append(f"{label} renders at {value:.0f}, outside {band[0]:.0f}-{band[1]:.0f}")

    # The armies, sampled on the pawns of each side and separated from the board
    # by value rather than by a box: the pale pawns that stand on dark squares,
    # counting only the pixels brighter than that square, and the dark pawns on
    # light squares, counting only the pixels darker than theirs.
    #
    # This is the third way this measurement was tried and the only one that
    # holds. A fixed pixel offset read the far army nine times darker than the
    # near one, because the far army is half the size on screen; a box scaled by
    # the square still caught the board behind the piece, and the three sets are
    # not the same height, so any offset that caught one set's body caught
    # another set's background. Thresholding against the square the piece stands
    # on needs neither a size nor a height.
    for label, rank, wanted in (("pale", 2, "pale"), ("dark", 7, "dark")):
        values = []
        for file in range(8):
            square_is_light = (file + rank) % 2 == 0
            if square_is_light == (wanted == "pale"):
                continue  # a pale army is measured on dark squares, and vice versa
            size = view.square_size(file, rank)
            centre = view.square_centre(file, rank)
            box = luma(crop(pixels, (centre[0], centre[1] - 0.45 * size), size * 1.05))
            keep = box > dark_median + 12 if wanted == "pale" else box < light_median - 12
            if keep.any():
                values.append(box[keep])
        army = np.concatenate(values)
        median = float(np.median(army))
        p10, p90 = (float(percentile) for percentile in np.percentile(army, (10, 90)))
        clipped = float((army >= 250).mean())
        print(f"   {label} army     median {median:6.1f}  p10 {p10:5.1f}  p90 {p90:5.1f}  "
              f"clipped {clipped * 100:4.1f}%")
        if wanted == "pale":
            if not PALE_ARMY_MEDIAN[0] <= median <= PALE_ARMY_MEDIAN[1]:
                problems.append(
                    f"pale army renders at {median:.0f}, outside "
                    f"{PALE_ARMY_MEDIAN[0]:.0f}-{PALE_ARMY_MEDIAN[1]:.0f}")
            if clipped > PALE_ARMY_MAX_CLIPPED:
                problems.append(
                    f"pale army is {clipped * 100:.0f}% clipped at 250+, over "
                    f"{PALE_ARMY_MAX_CLIPPED * 100:.0f}% - the carving is gone")
        else:
            if not DARK_ARMY_MEDIAN[0] <= median <= DARK_ARMY_MEDIAN[1]:
                problems.append(
                    f"dark army renders at {median:.0f}, outside "
                    f"{DARK_ARMY_MEDIAN[0]:.0f}-{DARK_ARMY_MEDIAN[1]:.0f}")
            if p90 < DARK_ARMY_MIN_LIT:
                problems.append(
                    f"dark army's lit top is only {p90:.0f} (p90), needs "
                    f"{DARK_ARMY_MIN_LIT:.0f} - it is a silhouette, not a piece")

    # The gold trim, found by hue rather than by position: gold is the only warm
    # saturated thing in a frame of neutral stone and slate.
    rgb = pixels.reshape(-1, 3)
    # A low threshold finds the mahogany board as well as the trim - a board is
    # warm too. Gold separates from wood on saturation: (0.76, 0.60, 0.23) is a
    # much wider R-B than any square on any of the four boards.
    # The mask is "more yellow than the room". The board's cream, the walnut
    # frame and the sand backdrop are all warm, and on the green-minus-blue axis
    # they sit at 25-35; gold is the only thing in the frame above 45, which is
    # what keeps 200 000 pixels of warm background out of the measurement.
    warm = (rgb[:, 0] - rgb[:, 2] > 70) & (rgb[:, 1] - rgb[:, 2] > 45) & (rgb[:, 0] > 100)
    gold = luma(rgb[warm])
    gold_count = int(warm.sum())
    gold_bright = float(np.percentile(gold, 90)) if gold_count else 0.0
    print(f"   gold trim      {gold_count:6d} px  p90 {gold_bright:6.1f}")
    # Only the turned set has crowns, collars and inlay: the two sculpted sets
    # carry their gold in the carving itself and have a fraction of the pixels.
    # The floor is a per-set expectation, so it is asked of the set that has the
    # trim rather than of every render.
    if "-classic" not in path.stem:
        gold_count = max(gold_count, GOLD_MIN_PIXELS)
    if gold_count < GOLD_MIN_PIXELS:
        problems.append(
            f"only {gold_count} gold pixels found, needs {GOLD_MIN_PIXELS} - "
            f"the crowns and inlay have gone dark or grey")
    elif gold_bright < GOLD_MIN_BRIGHT:
        problems.append(
            f"gold trim peaks at {gold_bright:.0f}, needs {GOLD_MIN_BRIGHT:.0f} - "
            f"the metal has nothing to reflect")

    # The background: the bottom-left corner. The top-left corner is under the
    # HUD panel, which is a translucent dark glass, so it measured the panel and
    # not the studio - the number moved every time the panel did.
    background = pixels[-48:-8, 8:48].reshape(-1, 3)
    background_luma = float(luma(background).mean())
    red_blue = float(background[:, 0].mean() - background[:, 2].mean())
    print(f"   background     luma {background_luma:6.1f}  r-b {red_blue:4.1f}")
    if not BACKGROUND[0] <= background_luma <= BACKGROUND[1]:
        problems.append(f"background renders at {background_luma:.0f}, outside {BACKGROUND[0]:.0f}-{BACKGROUND[1]:.0f}")
    if not BACKGROUND_WARMTH[0] <= red_blue <= BACKGROUND_WARMTH[1]:
        problems.append(
            f"background is {red_blue:.0f} red-minus-blue, outside "
            f"{BACKGROUND_WARMTH[0]:.0f}-{BACKGROUND_WARMTH[1]:.0f} - it is not the warm studio")

    for problem in problems:
        print(f"   FAIL {problem}")
    return problems


def main(argv: list[str]) -> int:
    if not argv:
        raise SystemExit("usage: measure_preview.py RENDER.png [RENDER.png ...]")
    failures: list[str] = []
    argv = [path for path in argv if is_board_render(Path(path))]
    for name in argv:
        failures += [f"{Path(name).name}: {problem}" for problem in measure(Path(name))]
    if failures:
        print("render measurement failed:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print("render measurement ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
