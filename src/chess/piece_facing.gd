extends RefCounted

## Which way each piece has to be turned so that it faces the opposing army.
##
## Kept out of main.gd so it can be tested without building a board: this has now
## been wrong in both directions, and both times the only thing that caught it was
## a human looking at a screenshot.
##
## Two facts decide every value here, and both are facts about the geometry:
##
##   1. White stands on the +Z half of the board and Black on -Z (the camera is
##      at +Z, which is why White is the army nearest the player). To face the
##      enemy, White has to look -Z and Black +Z.
##   2. The turned Staunton bodies are sculpted with their muzzle down -Z. Both
##      sculpted sets are sculpted facing +Z - the persian king and queen hold
##      their staff and orb in front of them, and the bastani figures are cut the
##      same way.
##
## So a -Z-front body needs no turn for White and half a turn for Black, and a
## +Z-front body needs exactly the opposite. The turned bishop additionally
## carries a quarter turn that puts its mitre slit forward; that is added to
## whichever half turn its army needs.

const TURNED_SET := "staunton"

## Sets whose models are sculpted facing +Z. Everything else is assumed to face
## -Z, which is the turned set's convention.
const PLUS_Z_SETS := ["persian", "bastani"]


static func yaw(set_name: String, kind: String, is_white: bool) -> float:
	# A piece with no front is left exactly as it was modelled. Turning it would
	# not change a single pixel, and spinning nine hundred vertices per piece for
	# nothing is the sort of thing that later reads as a bug.
	if not has_front(set_name, kind):
		return 0.0
	var front_is_plus_z := set_name in PLUS_Z_SETS
	var facing := (PI if is_white else 0.0) if front_is_plus_z else (0.0 if is_white else PI)
	if set_name == TURNED_SET and kind == "bishop":
		# The turned bishop's mitre is cut on a diagonal, so it needs the quarter
		# turn on top of the half turn to point its slit down the board.
		facing += PI * 0.25
	return facing


## The kinds that actually have a front. A turned pawn, rook, queen and king are
## surfaces of revolution: turning them changes nothing, so they are left alone
## rather than being spun for the sake of it.
static func has_front(set_name: String, kind: String) -> bool:
	if set_name in PLUS_Z_SETS:
		return kind in ["pawn", "knight", "bishop", "king", "queen"]
	if set_name == TURNED_SET:
		return kind in ["knight", "bishop"]
	return false
