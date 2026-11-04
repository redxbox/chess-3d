extends RefCounted

## How tall each kind stands, relative to the pawn.
##
## The ladder used to be whatever the three sets happened to be modelled at, and
## the model had two problems. The bishop was only 1.5% taller than the knight, so
## from a camera 13 units away the two read as the same height - and those are two
## of the four pieces a player most needs to tell apart. And the pawn-to-king climb
## was steep enough (1.00 to 1.78) that the back rank towered over the pawns
## instead of climbing away from them.
##
## These are the requested proportions, and the ordering property that matters is
## the gap between the bishop and the knight: 1.35 against 1.25 is a visible step,
## where the shipped meshes gave 1.473 against 1.444.
##
## The ladder is applied as a Y-only scale at spawn. Every set is normalised to
## the classic set's height and footprint, so one table serves all three - and a
## table that lives in code survives a set being re-exported, which a table baked
## into the OBJ files does not.
##
## Pure and static, so tests/test_chess.gd can check the ordering without a board.

const RATIOS := {
	"pawn": 1.00,
	"rook": 1.15,
	"knight": 1.25,
	"bishop": 1.35,
	"queen": 1.50,
	"king": 1.65,
}

## The height the king keeps, in model units. Every other kind is scaled so the
## finished piece sits at `RATIOS[kind] / RATIOS["king"] * KING_HEIGHT`, which is
## what keeps the knight's head above the pawn without moving the whole board's
## sense of scale.
const KING_HEIGHT := 1.620


## The Y multiplier for `kind`, given the height its mesh actually ships at and
## the height the king of the same set ships at.
##
## Both are measured from the meshes rather than tabulated, and the king's
## measured height - not the constant above - is what the whole ladder is
## anchored to. Anchoring to a constant would silently resize every piece the day
## the OBJ importer's unit scale changed, or a set was re-normalised: the ratio
## would still be right, but the board would grow or shrink as a whole.
static func height_scale(kind: String, shipped_height: float, king_height := KING_HEIGHT) -> float:
	if shipped_height <= 0.0001 or king_height <= 0.0001:
		return 1.0
	var unit := king_height / float(RATIOS["king"])
	return float(RATIOS.get(kind, RATIOS["pawn"])) * unit / shipped_height


## The finished height of `kind`, for the tests and for anything that has to
## reason about whether a piece clears its neighbours.
static func height(kind: String, king_height := KING_HEIGHT) -> float:
	return float(RATIOS.get(kind, RATIOS["pawn"])) * king_height / float(RATIOS["king"])
