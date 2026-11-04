extends SceneTree

const ChessGame = preload("res://src/chess/chess_game.gd")
const OfflineAI = preload("res://src/ai/offline_ai.gd")
const GameArchive = preload("res://src/storage/game_archive.gd")
const PieceFacing = preload("res://src/chess/piece_facing.gd")
const PieceLayout = preload("res://src/main/piece_layout.gd")
const PieceShading = preload("res://src/main/piece_shading.gd")
const CameraRigSpec = preload("res://src/main/camera_rig.gd")
var passed := 0
var failed := 0


func _init() -> void:
	_test_initial_position()
	_test_basic_moves()
	_test_captured_piece_tracking()
	_test_illegal_move_and_check()
	_test_castling()
	_test_castling_requires_rook()
	_test_push_and_pop_move()
	_test_en_passant()
	_test_promotion()
	_test_insufficient_material()
	_test_checkmate()
	_test_stalemate()
	_test_fen()
	_test_pgn()
	_test_pgn_import()
	_test_pgn_round_trip_from_custom_position()
	_test_threefold_repetition()
	_test_offline_ai()
	_test_game_archive()
	_test_piece_facing()
	_test_piece_layout()
	_test_piece_shading()
	_test_camera_rig()
	print("Chess tests: %d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", message)
	else:
		failed += 1
		push_error("FAIL: " + message)


func _find_move(game, from: Vector2i, to: Vector2i) -> Dictionary:
	for move in game.legal_moves(from):
		if move.to == to:
			return move
	return {}


func _empty_board(game) -> void:
	for y in 8:
		for x in 8:
			game.board[y][x] = ""
	game.castling = {"K": false, "Q": false, "k": false, "q": false}
	game.en_passant = Vector2i(-1, -1)
	game.result = ""


func _test_initial_position() -> void:
	var game = ChessGame.new()
	_expect(game.legal_moves().size() == 20, "initial position has 20 legal moves")
	_expect(game.turn == ChessGame.WHITE, "white starts")
	_expect(not game.is_in_check(ChessGame.WHITE), "white is not initially in check")


func _test_basic_moves() -> void:
	var game = ChessGame.new()
	var e2e4 := _find_move(game, Vector2i(4, 6), Vector2i(4, 4))
	_expect(not e2e4.is_empty() and game.play(e2e4), "white pawn can play e2-e4")
	_expect(game.board[4][4] == "P" and game.turn == ChessGame.BLACK, "board and turn update after move")
	_expect(game.undo() and game.board[6][4] == "P", "undo restores the position")


func _test_captured_piece_tracking() -> void:
	var game = ChessGame.new()
	game.play(_find_move(game, Vector2i(4, 6), Vector2i(4, 4)))
	game.play(_find_move(game, Vector2i(3, 1), Vector2i(3, 3)))
	game.play(_find_move(game, Vector2i(4, 4), Vector2i(3, 3)))
	_expect(game.captured_by_white == ["p"], "captured pieces are tracked by the capturing side")
	game.undo()
	_expect(game.captured_by_white.is_empty(), "undo restores captured piece history")


func _test_illegal_move_and_check() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[0][4] = "r"
	game.board[0][0] = "k"
	game.turn = ChessGame.WHITE
	_expect(game.is_in_check(ChessGame.WHITE), "rook gives check along a file")
	var king_moves := game.legal_moves(Vector2i(4, 7))
	var remains_in_line := false
	for move in king_moves:
		if move.to == Vector2i(4, 6): remains_in_line = true
	_expect(not remains_in_line, "king cannot remain on attacked file")


func _test_castling() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[7][7] = "R"
	game.board[0][4] = "k"
	game.castling.K = true
	game.turn = ChessGame.WHITE
	var castle := _find_move(game, Vector2i(4, 7), Vector2i(6, 7))
	_expect(not castle.is_empty(), "king-side castling is generated")
	game.play(castle)
	_expect(game.board[7][6] == "K" and game.board[7][5] == "R", "castling moves king and rook")


func _test_castling_requires_rook() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[0][4] = "k"
	game.castling.K = true
	game.castling.Q = true
	game.turn = ChessGame.WHITE
	_expect(_find_move(game, Vector2i(4, 7), Vector2i(6, 7)).is_empty(), "a castling right without the rook on h1 generates no move")
	_expect(_find_move(game, Vector2i(4, 7), Vector2i(2, 7)).is_empty(), "a castling right without the rook on a1 generates no move")
	game.board[7][7] = "R"
	game.board[7][0] = "R"
	_expect(not _find_move(game, Vector2i(4, 7), Vector2i(6, 7)).is_empty(), "castling is generated once the rook is on h1")
	_expect(not _find_move(game, Vector2i(4, 7), Vector2i(2, 7)).is_empty(), "castling is generated once the rook is on a1")
	# The generated move must actually place the rook, never delete it.
	game.play(_find_move(game, Vector2i(4, 7), Vector2i(6, 7)))
	_expect(game.board[7][6] == "K" and game.board[7][5] == "R", "king-side castling moves king and rook together")


func _test_push_and_pop_move() -> void:
	var game = ChessGame.new()
	var move = _find_move(game, Vector2i(4, 6), Vector2i(4, 4))
	var snapshot := game.push_move(move)
	_expect(game.board[4][4] == "P" and game.turn == ChessGame.BLACK, "push_move applies a move")
	game.pop_move(snapshot)
	_expect(game.board[6][4] == "P" and game.turn == ChessGame.WHITE, "pop_move restores the position")
	_expect(game.move_notation.is_empty(), "push/pop leaves the notation history untouched")
	_expect(game.captured_by_white.is_empty() and game.captured_by_black.is_empty(), "push/pop leaves the capture history untouched")
	_expect(game.legal_moves().size() == 20, "push/pop restores the full legal move list")
	# Legality checking itself runs on the same pair, so pins must survive it.
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[6][4] = "P"
	game.board[5][3] = "p"
	game.board[3][3] = "n"
	game.board[0][4] = "r"
	game.board[0][0] = "k"
	game.turn = ChessGame.WHITE
	_expect(not game.is_in_check(ChessGame.WHITE), "the pawn still shields the king from the rook")
	var pawn_moves := game.legal_moves(Vector2i(4, 6))
	_expect(pawn_moves.size() == 2, "a pawn pinned on a file may still advance along it")
	var captures_off_file := false
	for pawn_move in pawn_moves:
		if pawn_move.to.x != 4:
			captures_off_file = true
	_expect(not captures_off_file, "a pawn pinned on a file may not capture off it")


func _test_en_passant() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[0][4] = "k"
	game.board[3][4] = "P"
	game.board[1][3] = "p"
	game.turn = ChessGame.BLACK
	var double_move := _find_move(game, Vector2i(3, 1), Vector2i(3, 3))
	game.play(double_move)
	var capture := _find_move(game, Vector2i(4, 3), Vector2i(3, 2))
	_expect(not capture.is_empty() and capture.get("en_passant", false), "en passant is available immediately")
	game.play(capture)
	_expect(game.board[3][3] == "" and game.board[2][3] == "P", "en passant removes captured pawn")


func _test_promotion() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[0][4] = "k"
	game.board[1][0] = "P"
	game.turn = ChessGame.WHITE
	var promotions := game.legal_moves(Vector2i(0, 1))
	_expect(promotions.size() == 4, "promotion offers four piece choices")
	var offered: Array[String] = []
	for move in promotions: offered.append(move.promotion)
	_expect(offered == ["Q", "R", "B", "N"], "promotion offers queen, rook, bishop and knight")
	var knight_move: Dictionary = promotions[3]
	game.play(knight_move)
	_expect(game.board[0][0] == "N", "selected underpromotion piece is used")


func _test_insufficient_material() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[7][4] = "K"
	game.board[0][4] = "k"
	game.board[6][2] = "B"
	game.board[1][5] = "b"
	game._update_result()
	_expect(game.result == "Draw by insufficient material", "same-colored bishops are insufficient material")
	game.result = ""
	game.board[1][5] = ""
	game.board[1][4] = "b"
	game._update_result()
	_expect(game.result == "", "opposite-colored bishops are not auto-declared insufficient")


func _test_checkmate() -> void:
	var game = ChessGame.new()
	game.play(_find_move(game, Vector2i(5, 6), Vector2i(5, 5)))
	game.play(_find_move(game, Vector2i(4, 1), Vector2i(4, 3)))
	game.play(_find_move(game, Vector2i(6, 6), Vector2i(6, 4)))
	game.play(_find_move(game, Vector2i(3, 0), Vector2i(7, 4)))
	_expect(game.result.contains("checkmate"), "Fool's Mate is recognized as checkmate")


func _test_stalemate() -> void:
	var game = ChessGame.new()
	_empty_board(game)
	game.board[0][0] = "k"
	game.board[2][2] = "K"
	game.board[2][1] = "Q"
	game.turn = ChessGame.BLACK
	game._update_result()
	_expect(game.result == "Draw by stalemate", "known stalemate position is recognized")


func _test_fen() -> void:
	var game = ChessGame.new()
	var initial := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	_expect(game.to_fen() == initial, "initial position exports to standard FEN")
	var custom := "r3k2r/ppp2ppp/2n1bn2/3qp3/8/2N1PN2/PPPP1PPP/R2QKB1R b KQkq - 4 9"
	_expect(game.load_fen(custom), "valid FEN imports successfully")
	_expect(game.to_fen() == custom, "FEN round trip preserves all six fields")
	_expect(not game.load_fen("not a fen"), "invalid FEN is rejected")
	var empty_game = ChessGame.new()
	empty_game.load_fen("8/8/8/8/8/8/8/8 w - - 0 1")
	_expect(not empty_game.is_valid_position(), "position without both kings is rejected by autosave validation")


func _test_pgn() -> void:
	var game = ChessGame.new()
	game.play(_find_move(game, Vector2i(4, 6), Vector2i(4, 4)))
	game.play(_find_move(game, Vector2i(4, 1), Vector2i(4, 3)))
	game.play(_find_move(game, Vector2i(6, 7), Vector2i(5, 5)))
	var pgn := game.to_pgn({"White": "Alice", "Black": "Offline AI"})
	_expect(pgn.contains("[White \"Alice\"]"), "PGN contains player headers")
	_expect(pgn.contains("1. e4 e5 2. Nf3"), "PGN contains algebraic move text")


func _test_pgn_import() -> void:
	var source = ChessGame.new()
	source.play(_find_move(source, Vector2i(4, 6), Vector2i(4, 4)))
	source.play(_find_move(source, Vector2i(4, 1), Vector2i(4, 3)))
	source.play(_find_move(source, Vector2i(6, 7), Vector2i(5, 5)))
	source.play(_find_move(source, Vector2i(1, 0), Vector2i(2, 2)))
	source.play(_find_move(source, Vector2i(5, 7), Vector2i(1, 3)))
	var exported := source.to_pgn({"White": "Importer Test"})
	var imported = ChessGame.new()
	var response := imported.load_pgn(exported)
	_expect(response.ok and response.ply == 5, "exported PGN imports all moves")
	_expect(imported.to_fen() == source.to_fen(), "PGN import recreates the exact position")
	var annotated := "[Event \"Comments\"]\n\n1. e4 {King pawn} e5 2. Nf3 Nc6 3. Bb5 *"
	var annotated_game = ChessGame.new()
	_expect(annotated_game.load_pgn(annotated).ok, "PGN parser accepts comments and result tokens")
	var invalid_game = ChessGame.new()
	_expect(not invalid_game.load_pgn("1. e5 *").ok, "PGN parser reports illegal moves")


func _test_pgn_round_trip_from_custom_position() -> void:
	var custom := "r3k2r/ppp2ppp/2n1bn2/3qp3/8/2N1PN2/PPPP1PPP/R2QKB1R b KQkq - 4 9"
	var source = ChessGame.new()
	_expect(source.load_fen(custom), "custom FEN loads")
	var exported := source.to_pgn()
	_expect(exported.contains("[SetUp \"1\"]"), "non-standard start positions export a SetUp header")
	_expect(exported.contains("[FEN \"" + custom + "\"]"), "non-standard start positions export a FEN header")
	var imported = ChessGame.new()
	_expect(imported.load_pgn(exported).ok, "a PGN with a FEN header imports")
	_expect(imported.to_fen() == source.to_fen(), "a PGN replay restores the custom starting position")
	# The standard start must stay header-clean so ordinary PGNs remain portable.
	var plain = ChessGame.new()
	_expect(not plain.to_pgn().contains("[SetUp"), "standard start positions export no SetUp header")
	# A corrupt FEN header must be rejected instead of silently resetting.
	var broken = ChessGame.new()
	_expect(not broken.load_pgn("[SetUp \"1\"]\n[FEN \"not a fen\"]\n\n1. e4 *").ok, "an invalid FEN header is rejected")


func _test_threefold_repetition() -> void:
	var game = ChessGame.new()
	for cycle in 2:
		game.play(_find_move(game, Vector2i(6, 7), Vector2i(5, 5)))
		game.play(_find_move(game, Vector2i(6, 0), Vector2i(5, 2)))
		game.play(_find_move(game, Vector2i(5, 5), Vector2i(6, 7)))
		game.play(_find_move(game, Vector2i(5, 2), Vector2i(6, 0)))
	_expect(game.result == "Draw by threefold repetition", "threefold position repetition is detected")


func _test_offline_ai() -> void:
	var game = ChessGame.new()
	for difficulty in ["easy", "medium", "hard", "professional"]:
		var chosen := OfflineAI.choose_move(game.to_fen(), difficulty)
		_expect(not chosen.is_empty() and not _find_move(game, chosen.from, chosen.to).is_empty(),
			"offline AI returns a legal move on " + difficulty)
	_expect(OfflineAI.choose_move("", "medium").is_empty(), "offline AI rejects an invalid FEN")
	_expect(OfflineAI.choose_move(game.to_fen(), "unknown").is_empty() == false, "offline AI falls back to a search depth for an unknown difficulty")


func _test_game_archive() -> void:
	var test_path := "user://test_game_archive.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	var store = GameArchive.new(test_path)
	var id: String = store.add_game("[Result \"1-0\"]\n\n1. e4 1-0", "White wins", {"mode": "ai"})
	_expect(store.games.size() == 1 and store.games[0].id == id, "completed game is added to local archive")
	var reloaded = GameArchive.new(test_path)
	_expect(reloaded.games.size() == 1 and reloaded.games[0].pgn.contains("e4"), "game archive persists to disk")
	_expect(reloaded.remove_game(id) and reloaded.games.is_empty(), "archived game can be deleted")
	# Which side the player controlled must survive a reload, otherwise a game
	# played as Black would never get another move from the engine.
	var side_store = GameArchive.new(test_path)
	var side_id := side_store.add_game("[Result \"*\"]\n\n1. e4", "In progress", {"mode": "ai", "human_color": ChessGame.BLACK})
	var side_reloaded = GameArchive.new(test_path)
	_expect(int(side_reloaded.games[0].get("human_color", ChessGame.WHITE)) == ChessGame.BLACK, "archive entries remember which side the player controlled")
	side_store.remove_game(side_id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


## Every piece with a front must face the opposing army.
##
## This is a table, tested rather than eyeballed, because it has now been wrong in
## both directions: first only the king and queen were listed, so the guards and
## the elephant faced their own player; then the turned set was given no
## per-army turn at all, so its black king and knights stood with their backs to
## the enemy.
func _test_piece_facing() -> void:
	var expectations := [
		# Turned set: muzzle -Z, so White keeps it and Black takes half a turn.
		["staunton", "knight", true, 0.0],
		["staunton", "knight", false, PI],
		# Its bishop also needs the quarter turn that puts the mitre slit forward.
		["staunton", "bishop", true, PI * 0.25],
		["staunton", "bishop", false, PI * 1.25],
		# A turned pawn and rook are surfaces of revolution: no front, no turn.
		["staunton", "pawn", true, 0.0],
		["staunton", "rook", false, 0.0],
		# Sculpted sets face +Z: White takes half a turn, Black keeps the model.
		["persian", "king", true, PI],
		["persian", "king", false, 0.0],
		["persian", "knight", true, PI],
		["persian", "knight", false, 0.0],
		["bastani", "knight", true, PI],
		["bastani", "knight", false, 0.0],
		["bastani", "bishop", true, PI],
		["bastani", "bishop", false, 0.0],
	]
	for case in expectations:
		var set_name: String = case[0]
		var kind: String = case[1]
		var is_white: bool = case[2]
		var expected: float = case[3]
		var actual: float = PieceFacing.yaw(set_name, kind, is_white)
		var same := absf(wrapf(actual - expected, -PI, PI)) < 0.001
		_expect(same, "%s %s %s faces the enemy (yaw %.2f)" % [set_name, kind, "white" if is_white else "black", actual])


## Only one node may stand on a square, and it has to be the right piece. Every
## case here is one that went wrong on a real board: a capture leaving two bodies
## on the arrival square, a promotion keeping the pawn's body, and a desynced node
## that would have been turned into the wrong shape rather than replaced.
func _test_piece_layout() -> void:
	var empty_board := _blank_board()
	# Nothing on the board, pieces in the tree: all of them go.
	var plan := PieceLayout.plan([PieceLayout.node(Vector2i(4, 4), "pawn")], empty_board)
	_expect(plan.free == [0] and plan.create.is_empty() and plan.keep.is_empty(),
		"a piece that is not on the board is removed")

	# A plain move. The animation re-tags the mover to its destination before the
	# board is reconciled, so the node is already there and is simply kept.
	var moved := _blank_board()
	moved[4][4] = "P"
	plan = PieceLayout.plan([PieceLayout.node(Vector2i(4, 4), "pawn")], moved)
	_expect(plan.keep.get(0) == Vector2i(4, 4) and plan.create.is_empty() and plan.free.is_empty(),
		"a moved piece keeps its node")
	# If it was never re-tagged - a cancelled animation - the node is still on the
	# square it left; it is freed and the piece is built on its real square, which
	# is the behaviour that makes a desync repair itself instead of persisting.
	plan = PieceLayout.plan([PieceLayout.node(Vector2i(4, 2), "pawn")], moved)
	_expect(plan.free == [0] and plan.create == [Vector2i(4, 4)],
		"a node left on a square the board no longer has is rebuilt")

	# The capture window: the captor and the captured body both claim the square.
	var captured := _blank_board()
	captured[4][4] = "P"
	plan = PieceLayout.plan([
		PieceLayout.node(Vector2i(4, 4), "pawn"),
		PieceLayout.node(Vector2i(4, 4), "pawn"),
	], captured)
	_expect(plan.keep.size() == 1 and plan.free.size() == 1 and plan.create.is_empty(),
		"two nodes on one square are reduced to one")

	# The captured body and its captor are both pawns, so child order decides -
	# unless the caller says which one is the corpse.
	plan = PieceLayout.plan([
		PieceLayout.node(Vector2i(4, 4), "pawn"),
		PieceLayout.node(Vector2i(4, 4), "pawn"),
	], captured, [0])
	_expect(plan.keep.get(1) == Vector2i(4, 4) and plan.free == [0],
		"the captured body is given up rather than the captor")

	# Same square, different kinds: the one that matches the board wins, whichever
	# order they come in.
	captured[4][4] = "Q"
	plan = PieceLayout.plan([
		PieceLayout.node(Vector2i(4, 4), "pawn"),
		PieceLayout.node(Vector2i(4, 4), "queen"),
	], captured)
	_expect(plan.keep.get(1) == Vector2i(4, 4) and plan.free == [0],
		"the node of the right kind is kept on a contested square")
	plan = PieceLayout.plan([
		PieceLayout.node(Vector2i(4, 4), "queen"),
		PieceLayout.node(Vector2i(4, 4), "pawn"),
	], captured)
	_expect(plan.keep.get(0) == Vector2i(4, 4) and plan.free == [1],
		"and the other way round")

	# A promotion: the pawn's body cannot become a queen, so it is replaced.
	var promoted := _blank_board()
	promoted[7][4] = "Q"
	# board[rank][file], but a square is Vector2i(file, rank): rank 7, file 4.
	plan = PieceLayout.plan([PieceLayout.node(Vector2i(4, 7), "pawn")], promoted)
	_expect(plan.free == [0] and plan.create == [Vector2i(4, 7)],
		"a promoted pawn's node is replaced, not re-positioned")

	# A square that has nothing on it at all has to be built.
	var start := ChessGame.new().board
	plan = PieceLayout.plan([], start)
	_expect(plan.create.size() == 32 and plan.free.is_empty(),
		"an empty tree builds all thirty-two pieces")
	# ...and reconciling a board that already matches touches nothing.
	var nodes: Array = []
	for square in plan.create:
		var code: String = start[square.y][square.x]
		nodes.append(PieceLayout.node(square, String(PieceLayout.KIND_FOR_CODE[code.to_lower()])))
	plan = PieceLayout.plan(nodes, start)
	_expect(plan.create.is_empty() and plan.free.is_empty() and plan.keep.size() == 32,
		"a board that already matches is left alone")

	# The rook's half of a castle, which is the half that used to be invisible.
	var castled_king_side := {"from": Vector2i(4, 7), "to": Vector2i(6, 7), "castle": "king"}
	_expect(PieceLayout.castle_rook_squares(castled_king_side) == [Vector2i(7, 7), Vector2i(5, 7)],
		"king-side castling moves the rook h to f")
	var castled_queen_side := {"from": Vector2i(4, 7), "to": Vector2i(2, 7), "castle": "queen"}
	_expect(PieceLayout.castle_rook_squares(castled_queen_side) == [Vector2i(0, 7), Vector2i(3, 7)],
		"queen-side castling moves the rook a to d")
	_expect(PieceLayout.castle_rook_squares({"from": Vector2i(4, 7), "to": Vector2i(4, 6)}).is_empty(),
		"an ordinary move moves no rook")


func _blank_board() -> Array:
	var board: Array = []
	for rank in 8:
		var row: Array = []
		row.resize(8)
		row.fill("")
		board.append(row)
	return board


## The carving has to show up as shading, on both armies, from geometry alone.
## The shapes are analytic so that "concave" and "convex" are not a matter of
## getting a winding order right in a test: a paraboloid y = +-(x^2 + z^2) / 2
## with its exact surface normal is either a bowl or a dome, and nothing else.
func _test_piece_shading() -> void:
	# A dome: nothing on it may be darkened, or every collar and crown on the
	# board would get a grey line down it.
	var dome := _paraboloid(-1.0, 12)
	var shade := PieceShading.cavity_shade(dome.positions, dome.normals, dome.indices)
	var dome_min := 1.0
	for value in shade:
		dome_min = minf(dome_min, value)
	_expect(shade.size() == dome.positions.size() and dome_min > 0.95,
		"a convex surface is left alone (darkest %.2f)" % dome_min)

	# A bowl: the folds of a robe, the inside of a crown. It must darken, and it
	# must stay stone-coloured rather than going to black.
	var bowl := _paraboloid(1.0, 12)
	shade = PieceShading.cavity_shade(bowl.positions, bowl.normals, bowl.indices)
	var bowl_total := 0.0
	var bowl_min := 1.0
	for value in shade:
		bowl_total += value
		bowl_min = minf(bowl_min, value)
	var bowl_mean := bowl_total / float(shade.size())
	_expect(bowl_mean < 0.80, "a concave surface is darkened (mean %.2f)" % bowl_mean)
	_expect(bowl_min > 0.30, "and it stays stone rather than going black (%.2f)" % bowl_min)

	# The two must be far enough apart to read as light and shadow at phone size.
	_expect(dome_min - bowl_mean > 0.20,
		"convex and concave differ by enough to see (%.2f against %.2f)" % [dome_min, bowl_mean])

	# A flat face carries no shading at all: the turned pieces are all convex and
	# flat, and greying them over would read as dirt.
	var plate := PieceShading.cavity_shade(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]),
		PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
		PackedInt32Array([0, 1, 2, 2, 1, 3]))
	var plate_min := 1.0
	for value in plate:
		plate_min = minf(plate_min, value)
	_expect(plate.size() == 4 and plate_min > 0.999, "a flat face carries no shading")

	# Degenerate inputs come back as "no shading", never as a table the wrong
	# size for the mesh it is about to be applied to.
	shade = PieceShading.cavity_shade(PackedVector3Array(), PackedVector3Array(), PackedInt32Array())
	_expect(shade.is_empty(), "an empty mesh shades to nothing")
	shade = PieceShading.cavity_shade(PackedVector3Array([Vector3.UP]),
		PackedVector3Array([Vector3.UP]), PackedInt32Array())
	_expect(shade.size() == 1 and shade[0] > 0.999, "a lone vertex has nothing to curve against")


## A grid sampling y = +-(x*x + z*z) / 2 over [-1, 1]^2, with the exact analytic
## normal, as (positions, normals, indices).
func _paraboloid(sign: float, steps: int) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in steps + 1:
		for j in steps + 1:
			var x := -1.0 + 2.0 * float(i) / float(steps)
			var z := -1.0 + 2.0 * float(j) / float(steps)
			positions.append(Vector3(x, sign * (x * x + z * z) * 0.5, z))
			normals.append(Vector3(-sign * x, 1.0, -sign * z).normalized())
	var indices := PackedInt32Array()
	for i in steps:
		for j in steps:
			var a := i * (steps + 1) + j
			var b := a + 1
			var c := a + steps + 1
			var d := c + 1
			for index in [a, b, d, a, d, c]:
				indices.append(index)
	return {"positions": positions, "normals": normals, "indices": indices}


## The camera rig, checked for the properties that were asked for and that a
## future edit could quietly undo: the elevation is in the range that clears the
## pawns, the field of view is narrow enough not to trapezoid the board, and the
## camera looks at the exact centre of the board rather than near it.
func _test_camera_rig() -> void:
	var home := CameraRigSpec.home()
	var elevation := CameraRigSpec.elevation_of(home)
	_expect(elevation >= 48.0 and elevation <= 52.0,
		"the camera looks down at 48-52 degrees (%.1f)" % elevation)
	_expect(CameraRigSpec.FOV >= 38.0 and CameraRigSpec.FOV <= 42.0,
		"the field of view is 38-42 degrees (%.1f)" % CameraRigSpec.FOV)
	# A camera on the origin's elevation vector looks at the origin: the angle
	# below the horizon equals the elevation exactly, so the look-at point is
	# (0, 0, 0) and the two armies are framed identically.
	_expect(absf(elevation - CameraRigSpec.ELEVATION_DEG) < 0.001,
		"the camera aims at the middle of the board")
	_expect(home.x == 0.0, "and it is centred on the board's x axis")
	_expect(CameraRigSpec.DISTANCE_DEFAULT >= CameraRigSpec.DISTANCE_MIN \
			and CameraRigSpec.DISTANCE_DEFAULT <= CameraRigSpec.DISTANCE_MAX,
		"the resting distance is inside the zoom range")
	# The far rank has to clear the pawns, which is the whole reason for the
	# elevation. At 50 degrees a piece five and a half units behind a one-unit
	# pawn is seen about 5.5 units above it; at the old 42 it was 3.9.
	var lift := CameraRigSpec.back_rank_lift()
	_expect(lift > 5.0, "the back rank clears the pawns (%.2f units)" % lift)


