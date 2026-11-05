extends RefCounted

## Where the camera stands, and why.
##
## A pure module rather than four numbers buried in the scene script, because
## these numbers are the difference between a board you can read and a board you
## have to orbit: tests/test_chess.gd checks them, and the scene file and the
## reset tween both read them from here so they cannot drift apart.
##
## Elevation: 50 degrees. At the 42 the project shipped with, the back rank sat
## directly behind the pawns - a knight's head was cut in half by the pawn in
## front of it on a phone screen, and the far side of the board could only be
## read by dragging the camera round. 50 also matches how the classic desktop
## chess games frame their boards.
##
## Field of view: 40 degrees. The first version shipped at 52, which turned the
## board into a trapezoid: the near rank twice the size of the far one. 34 was
## tried in the other direction and cropped the near rank on a phone in
## landscape. 38-42 keeps both ranks usable, and 40 is the middle of it.
##
## The camera always looks at (0, 0, 0). The rig sits at the board's origin and
## the camera stands on the elevation vector from it, so the look-at point is the
## middle of the grid by construction rather than by a rotation someone typed.

const ELEVATION_DEG := 50.0
const FOV := 40.0
const DISTANCE_DEFAULT := 13.2
const DISTANCE_MIN := 8.0
const DISTANCE_MAX := 16.0


## The camera's position for a distance, on the elevation vector from the origin.
static func home(distance := DISTANCE_DEFAULT, elevation_deg := ELEVATION_DEG) -> Vector3:
	var angle := deg_to_rad(elevation_deg)
	return Vector3(0.0, distance * sin(angle), distance * cos(angle))


## The elevation a camera at `position` has, in degrees.
static func elevation_of(position: Vector3) -> float:
	return rad_to_deg(atan2(position.y, position.z))


## How far the back rank clears a pawn, in board units.
##
## `span` is the horizontal distance from a piece to the pawn that stands between
## it and the camera, and `obstruction` is the height of that pawn. Anything at
## or below zero means the far piece is hidden behind the near one.
static func back_rank_lift(elevation_deg := ELEVATION_DEG, span := 5.5, obstruction := 1.0) -> float:
	return tan(deg_to_rad(elevation_deg)) * span - obstruction
