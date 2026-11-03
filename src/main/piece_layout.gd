extends RefCounted

## Which piece node belongs on which square.
##
## The board is rebuilt after every move by reconciling the existing nodes with
## the position, and the one invariant that has to hold is: at most one node per
## square, of the right kind. Breaking it is visible - two pieces stand on the
## same tile, one of them the piece that was just captured - and it is worse than
## visible: the old code keyed the nodes by square into a Dictionary, so a second
## node on a square silently overwrote the first and the loser was never visited
## again. It stayed in the tree, at its old square, forever.
##
## Duplicates are not hypothetical. _animate_board_move() re-tags the moving node
## to its destination the moment the rules engine has applied the move, and the
## captured node is still in the tree with that same square until its collapse
## tween ends. Any reconcile in that window sees two nodes claiming one square,
## and which one it kept was decided by child order.
##
## So the decision is made here, purely, from a list of nodes and the position:
## keep at most one node per occupied square, and only if its kind is right; free
## everything else and create what is missing. main.gd only carries it out.

const KIND_FOR_CODE := {
	"p": "pawn", "r": "rook", "n": "knight",
	"b": "bishop", "q": "queen", "k": "king",
}


## One node as the layout sees it: where it says it is, and what it is.
static func node(square: Vector2i, kind: String) -> Dictionary:
	return {"square": square, "kind": kind}


## Computes what to do with the nodes of one board.
##
## `nodes` is the array returned by `node()` for every piece currently in the
## tree, in child order. `board` is the position: eight rows of eight codes,
## uppercase for White, empty string for a bare square.
##
## `avoid` is a list of node indices to drop in preference to any other when two
## nodes claim the same square. It exists for exactly one caller: the body of the
## piece that was just captured is still in the tree, claiming the square its
## captor has arrived on, and if both are the same kind - a pawn taking a pawn -
## child order alone would keep the corpse.
##
## Returns:
##   "keep"   - {index: Vector2i}, the node that stays, and where it now belongs
##              (it may have moved, so the caller re-tags it even when the square
##              is unchanged).
##   "free"   - [index], nodes with no place in this position.
##   "create" - [Vector2i], squares that have no node at all.
static func plan(nodes: Array, board: Array, avoid := []) -> Dictionary:
	var by_square := {}
	for index in nodes.size():
		var data: Dictionary = nodes[index]
		var square: Vector2i = data.square
		if not by_square.has(square):
			by_square[square] = []
		(by_square[square] as Array).append(index)

	var keep := {}
	var free := []
	var create := []
	for rank in board.size():
		var row: Array = board[rank]
		for file in row.size():
			var square := Vector2i(file, rank)
			var candidates: Array = by_square.get(square, [])
			var code := String(row[file])
			if code == "":
				for index in candidates:
					free.append(index)
				continue
			var wanted := String(KIND_FOR_CODE.get(code.to_lower(), "pawn"))
			var chosen := -1
			for index in candidates:
				# The first node of the right kind is kept, unless it is one of the
				# nodes explicitly being given up. A node of the wrong kind on an
				# occupied square is a promotion or a desync, and it is replaced
				# rather than turned into the wrong shape.
				if chosen < 0 and String((nodes[index] as Dictionary).kind) == wanted \
						and not avoid.has(index):
					chosen = index
			if chosen < 0:
				# Everything here is avoidable; there is nothing better to keep.
				for index in candidates:
					if chosen < 0 and String((nodes[index] as Dictionary).kind) == wanted:
						chosen = index
			for index in candidates:
				if index != chosen:
					free.append(index)
			if chosen >= 0:
				keep[chosen] = square
			else:
				create.append(square)
	# A node whose square is off the board - or that two squares somehow claimed -
	# is not part of any position and goes.
	for index in nodes.size():
		if keep.has(index) or free.has(index):
			continue
		free.append(index)
	return {"keep": keep, "free": free, "create": create}


## Where the rook goes when the king castles: [from, to].
##
## Castling moves two pieces and the record of a move has to show both, or the
## rook simply appears on a square it was never seen to travel to. The rule is
## written once here, from the king's destination, which is what the rules engine
## writes: the g-file is the king side and the c-file the queen side.
static func castle_rook_squares(move: Dictionary) -> Array:
	if not move.has("castle"):
		return []
	var rank: int = move.from.y
	if move.castle == "king":
		return [Vector2i(7, rank), Vector2i(5, rank)]
	return [Vector2i(0, rank), Vector2i(3, rank)]
