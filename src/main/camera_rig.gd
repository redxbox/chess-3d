extends RefCounted

## Where the camera stands, and why.
##
## A pure module rather than four numbers buried in the scene script, because
## these numbers are the difference between a board you can read and a board you
## have to orbit: tests/test_chess.gd checks them, and the scene file and the
## reset tween both read them from here so they cannot drift apart.
##
## Elevation: 46 degrees, and the set is now framed as a whole piece of
## furniture rather than as a grid.
##
## Two facts set this. The board has side trays, so the frame is about twice as
## wide as the playing surface and the camera has to see all of it - that pushes
## it back. And the reference the author pointed at is a three-quarter view from
## roughly this angle: low enough that the frame's thickness and the trays' rims
## show their front faces, high enough that the far rank is not hidden behind the
## near pawns. 58 (the previous value) was a top-down board with no board in it;
## 46 is a photograph of a set.
const ELEVATION_DEG := 49.0
const FOV := 42.0
const DISTANCE_DEFAULT := 17.6
const DISTANCE_MIN := 11.0
const DISTANCE_MAX := 22.0


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
