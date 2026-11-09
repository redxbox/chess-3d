extends SceneTree

const ChessGame = preload("res://src/chess/chess_game.gd")
const OfflineAI = preload("res://src/ai/offline_ai.gd")
const GameArchive = preload("res://src/storage/game_archive.gd")
const PieceFacing = preload("res://src/chess/piece_facing.gd")
const PieceLayout = preload("res://src/main/piece_layout.gd")
const PieceShading = preload("res://src/main/piece_shading.gd")
const CameraRigSpec = preload("res://src/main/camera_rig.gd")
const PieceLadder = preload("res://src/main/piece_ladder.gd")
const ObjLoader = preload("res://src/main/obj_loader.gd")
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
	_test_piece_height_ladder()
	_test_sculpt_relief_and_gild()
	_test_knight_facing_matches_the_meshes()
	_test_colour_sidecars()
	_test_obj_loader_matches_the_file()
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
		["pars", "king", true, PI],
		["pars", "king", false, 0.0],
		# The pars horse looks straight down +Z like the rest of its set, so it
		# takes the figures' turn. The set this one replaced did not, and that is
		# the case that shipped back to front.
		["pars", "knight", true, PI],
		["pars", "knight", false, 0.0],
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
	#
	# A dome this smooth curves by about 0.15 per unit - less than half the
	# curvature at which the occlusion starts - so the correct answer for it is
	# "no shading at all", and that is what the wider patch returns. The convex
	# half of the same measurement is the gild mask, which is checked separately
	# below on a ridge that is sharp enough to be an edge.
	var dome := _paraboloid(-1.0, 12)
	var shade := PieceShading.cavity_shade(dome.positions, dome.normals, dome.indices)
	var dome_min := 1.0
	for value in shade:
		dome_min = minf(dome_min, value)
	_expect(shade.size() == dome.positions.size() and dome_min > 0.999,
		"a smooth convex surface is left alone (darkest %.3f)" % dome_min)

	# A bowl: the inside of a crown, the hollow behind a shield. A paraboloid
	# this shallow is still below the curvature at which a crease begins, so the
	# correct answer is again "nothing" - a hollow is not a fold. What the
	# occlusion must actually do on a fold is checked on the 90 degree valley in
	# _test_sculpt_relief_and_gild, which is the shape a robe fold really is.
	var bowl := _paraboloid(1.0, 12)
	shade = PieceShading.cavity_shade(bowl.positions, bowl.normals, bowl.indices)
	var bowl_min := 1.0
	for value in shade:
		bowl_min = minf(bowl_min, value)
	# Not "exactly 1.000": a paraboloid does curve, by about 0.2 per unit, which
	# is inside the smoothstep's first few percent. What matters is that a hollow
	# of this size is a hair off white while a fold is a real shadow - the fold
	# case below is 0.46.
	_expect(bowl_min > 0.98, "a shallow hollow is barely touched (darkest %.3f)" % bowl_min)

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


## The fold, the ridge and the gilded edge - the three things the figurative
## set's complaint was actually about.
##
## The fixtures are analytic so that "concave" and "convex" are facts about the
## geometry rather than about a winding order I got wrong: two planes meeting
## along an edge is a valley at +1 and a ridge at -1, and nothing else. Both are
## 90 degree edges, because 90 degrees is what a crown point, a spear tip and the
## rim of a shield are; a table of thresholds tuned on a 15 degree roof would be
## tuned on nothing.
func _test_sculpt_relief_and_gild() -> void:
	# --- a fold of drapery -------------------------------------------------
	# The numbers here are measured on this fixture with the shipped constants:
	# 0.46 in the valley, 98% of the surface untouched, and the shading spread
	# over about a tenth of the sheet rather than sitting on the seam.
	var valley := _roof(1.0, 24, 1.0)
	var fields := PieceShading.sculpt_fields(valley.positions, valley.normals, valley.indices, 0.0)
	var shade: PackedFloat32Array = fields["shade"]
	var deepest := INF
	var painted := 0
	for value in shade:
		deepest = minf(deepest, value)
		if value < 0.99:
			painted += 1
	_expect(deepest < 0.60, "a fold of drapery darkens sharply (deepest %.3f)" % deepest)
	_expect(deepest > 0.35, "and stays stone rather than going black (%.3f)" % deepest)
	var painted_share := float(painted) / float(shade.size())
	_expect(painted_share > 0.03 and painted_share < 0.55,
		"the fold is a band, not a line (%.0f%% of the surface)" % (painted_share * 100.0))

	# A valley is never gold: gilding a crease is paint, not ornament, and it was
	# half of what "blurry noisy mess" described.
	var valley_gild: PackedFloat32Array = fields["gild"]
	var valley_gilded := 0
	for value in valley_gild:
		if value > 0.5:
			valley_gilded += 1
	_expect(valley_gilded == 0, "a fold is not gilded (%d vertices)" % valley_gilded)

	# --- a convex edge -----------------------------------------------------
	# A ridge must not be darkened at all: it is the brightest thing on a
	# carving, and greying it is exactly the "aggressive vertex-darkening" the
	# set was reported with.
	# A quarter of the fold's size: a crown point, not a roof. Curvature is per
	# unit, so the scale is the whole difference between "an edge" and "a plane
	# with a bend in it".
	var ridge := _roof(-1.0, 24, 1.0, 0.25)
	var ridge_fields := PieceShading.sculpt_fields(ridge.positions, ridge.normals, ridge.indices, 0.0)
	var ridge_shade: PackedFloat32Array = ridge_fields["shade"]
	var ridge_min := INF
	for value in ridge_shade:
		ridge_min = minf(ridge_min, value)
	_expect(ridge_min > 0.999, "a ridge is not darkened at all (darkest %.3f)" % ridge_min)

	# And it is where the gold goes. On the fixture a few vertices carry it (a
	# single edge is not a crown); what the test can still pin is that the mask
	# exists, is strongest on the axis of the ridge, and is scaled by the
	# set's own strength.
	var ridge_gild: PackedFloat32Array = ridge_fields["gild"]
	var ridge_peak := 0.0
	for value in ridge_gild:
		ridge_peak = maxf(ridge_peak, value)
	_expect(ridge_peak > 0.25, "the ridge carries gold (peak %.2f)" % ridge_peak)
	var weaker := PieceShading.sculpt_fields(ridge.positions, ridge.normals, ridge.indices, 0.0, 0.0)
	var weaker_peak := 0.0
	for value in (weaker["gild"] as PackedFloat32Array):
		weaker_peak = maxf(weaker_peak, value)
	_expect(weaker_peak == 0.0, "a set that asks for no gold gets none (peak %.2f)" % weaker_peak)

	# --- the plinth is stone ------------------------------------------------
	# A statuette is gilded on its ornament, not round its base: a gold ring at
	# the bottom of every piece reads as a band of paint, and it was the thing
	# the first prototype of this mask produced. So with the plinth line put at a
	# third of the height, the same ridge below a tenth of the height must be bare
	# and its tip must still be gold - suppressed, not switched off.
	var lowest := INF
	var highest := -INF
	for point in ridge.positions:
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)
	var base := PieceShading.sculpt_fields(ridge.positions, ridge.normals, ridge.indices, 0.33, 1.0)
	var base_gild: PackedFloat32Array = base["gild"]
	var bare_peak := 0.0
	var tip_peak := 0.0
	for index in base_gild.size():
		var height: float = (ridge.positions[index].y - lowest) / maxf(highest - lowest, 0.0001)
		if height < 0.10:
			bare_peak = maxf(bare_peak, base_gild[index])
		elif height > 0.60:
			tip_peak = maxf(tip_peak, base_gild[index])
	_expect(bare_peak == 0.0, "nothing below the plinth line is gilded (peak %.2f)" % bare_peak)
	_expect(tip_peak > 0.25, "the same ridge above the plinth line still is (peak %.2f)" % tip_peak)

	# --- the gilded surface is whole triangles ------------------------------
	var indices := PieceShading.gilded_indices(ridge.indices, ridge_gild, 0.0)
	_expect(indices.size() % 3 == 0 and indices.size() == ridge.indices.size(),
		"a threshold of zero keeps every triangle (%d)" % indices.size())
	var none := PieceShading.gilded_indices(ridge.indices, ridge_gild, 2.0)
	_expect(none.is_empty(), "a threshold above the peak keeps none")


## Two planes meeting along the x axis, welded along the seam so it is a real
## edge: sign +1 is a valley (a fold), sign -1 a ridge (a crown point). `slope` 1
## is a 90 degree dihedral, and `scale` sets how large the shape is - which is
## what decides how tight it reads, because curvature is per unit.
func _roof(sign: float, steps: int, slope: float, scale := 1.0) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for side in 2:
		for i in steps + 1:
			var x := float(i) / float(steps)
			for j in steps + 1:
				var z := -1.0 + 2.0 * float(j) / float(steps)
				positions.append(Vector3(x, sign * slope * x, z))
				normals.append(Vector3(-sign * slope, 1.0, 0.0).normalized())
	var half := (steps + 1) * (steps + 1)
	var indices := PackedInt32Array()
	for side in 2:
		var base := side * half
		var flip := side == 1
		for i in steps:
			for j in steps:
				var a := base + i * (steps + 1) + j
				var b := a + 1
				var c := a + steps + 1
				var d := c + 1
				if flip:
					# Mirroring reverses the winding: keep the faces facing out.
					for index in [a, d, b, a, c, d]:
						indices.append(index)
				else:
					for index in [a, b, d, a, d, c]:
						indices.append(index)
	# Mirror the second sheet onto the other side of the seam.
	for i in range(half, positions.size()):
		positions[i] = Vector3(-positions[i].x, positions[i].y, positions[i].z)
		normals[i] = Vector3(-normals[i].x, normals[i].y, normals[i].z)
	if not is_equal_approx(scale, 1.0):
		for i in positions.size():
			positions[i] = positions[i] * scale
	return {"positions": positions, "normals": normals, "indices": indices}


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


## The height ladder: the six kinds must climb in the requested proportions, and
## the bishop must be decisively taller than the knight.
##
## This is a test rather than a comment because the previous ladder had the two
## within 1.5% of each other, which on a phone is the same height.
func _test_piece_height_ladder() -> void:
	var order := ["pawn", "rook", "knight", "bishop", "queen", "king"]
	for index in order.size():
		var kind: String = order[index]
		var height := PieceLadder.height(kind)
		_expect(is_equal_approx(height, PieceLadder.RATIOS[kind] / PieceLadder.RATIOS["king"] * PieceLadder.KING_HEIGHT),
			"%s sits on the ladder" % kind)
		if index > 0:
			_expect(height > PieceLadder.height(order[index - 1]),
				"%s is taller than %s" % [kind, order[index - 1]])
	_expect(PieceLadder.height("king") / PieceLadder.height("pawn") > 1.64,
		"the king is 1.65x the pawn")
	_expect(PieceLadder.height("bishop") / PieceLadder.height("knight") >= 1.07,
		"the bishop is clearly taller than the knight (%.2f)"
			% (PieceLadder.height("bishop") / PieceLadder.height("knight")))
	# The scale is a ratio to the shipped height: a piece that already ships at its
	# ladder height must not be scaled at all.
	_expect(is_equal_approx(PieceLadder.height_scale("king", PieceLadder.KING_HEIGHT), 1.0),
		"a king at reference height is scaled by exactly 1")
	var pawn_scale := PieceLadder.height_scale("pawn", 0.910, 1.620)
	_expect(is_equal_approx(0.910 * pawn_scale, PieceLadder.height("pawn")),
		"the pawn ends at its ladder height (%.3f)" % (0.910 * pawn_scale))
	# And the ladder is anchored to the king's *measured* height, so a set that
	# ships at half scale keeps its proportions instead of doubling in size.
	var half := PieceLadder.height_scale("pawn", 0.455, 0.810)
	_expect(is_equal_approx(half, pawn_scale), "a set at half scale scales the same (%.4f)" % half)


## The facing table against the meshes it describes.
##
## The rule a piece "faces" is a fact about its geometry, and it has now been
## wrong twice - once for every knight, once for a set's knights only - with a
## human seeing it in a screenshot as the only detector. So the knights are
## measured here: in the top 15% of the piece - the head, the ears and the mane
## above the neck - the point furthest forward or back along z is the muzzle, and
## its z sign is what the table has to say.
##
## Two cheaper rules were tried and both got a set wrong, which is why this one is
## spelled out. "Furthest point from the vertical axis" reads the bastani horse's
## near-side cheek in the top fifth of its height and calls the set backwards. The
## mass of the top 5% reads the mane that sweeps back over the neck: -0.031 on
## bastani, also backwards. Along z, in the top 15%, the three sets measure
## -0.317 (staunton), +0.218 (pars) and +0.249 (bastani) - the three carved
## directions, with a margin on every one.
func _test_knight_facing_matches_the_meshes() -> void:
	for set_name in ["staunton", "pars", "bastani"]:
		var path := "res://assets/models/%s/knight.obj" % set_name
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "%s has a knight mesh" % set_name)
		if file == null:
			continue
		var points: Array[Vector3] = []
		while not file.eof_reached():
			var line := file.get_line()
			if not line.begins_with("v "):
				continue
			var parts := line.split(" ", false)
			if parts.size() < 4:
				continue
			points.append(Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
		file.close()
		_expect(points.size() > 100, "%s's knight has geometry (%d vertices)" % [set_name, points.size()])
		var lowest := INF
		var highest := -INF
		for point in points:
			lowest = minf(lowest, point.y)
			highest = maxf(highest, point.y)
		var height := highest - lowest
		var muzzle_z := 0.0
		for point in points:
			if point.y < lowest + height * 0.85:
				continue
			if absf(point.z) > absf(muzzle_z):
				muzzle_z = point.z
		_expect(absf(muzzle_z) > 0.1, "%s's knight has a muzzle that sticks out (%.3f)" % [set_name, muzzle_z])
		var measured := 1 if muzzle_z > 0.0 else -1
		_expect(measured == PieceFacing.front_sign(set_name, "knight"),
			"%s's knight is carved facing %s, as the table says (muzzle z %+.3f)"
				% [set_name, "+Z" if measured > 0 else "-Z", muzzle_z])
		# And the consequence, which is the thing the player actually sees: the two
		# knights of a set end up facing each other.
		var white_yaw := PieceFacing.yaw(set_name, "knight", true)
		var black_yaw := PieceFacing.yaw(set_name, "knight", false)
		_expect(absf(wrapf(white_yaw - black_yaw, -PI, PI)) > 3.0,
			"%s's two knights face each other (yaws %.2f and %.2f)" % [set_name, white_yaw, black_yaw])
		# The rule stated the other way round, because this is the form the bug
		# was reported in and the form a future reader will check: after the turn,
		# White's knight holds its muzzle toward rank 8 (-Z) and Black's toward
		# rank 1 (+Z). A half turn reverses a muzzle, so the world direction is the
		# carved direction times the turn.
		var white_world: int = measured * (1 if is_zero_approx(white_yaw) else -1)
		var black_world: int = measured * (1 if is_zero_approx(black_yaw) else -1)
		_expect(white_world == -1,
			"%s: White's knight looks toward rank 8" % set_name)
		_expect(black_world == 1,
			"%s: Black's knight looks toward rank 1" % set_name)


## The pars set's colours live in a sidecar, and a sidecar is data no compiler
## checks. Every failure this project has shipped in that file was invisible to
## the renderer until it reached a phone: six sidecars missing from the package
## drew two armies of white, and a per-vertex sample of the atlas drew both
## armies gold. So the file itself is checked here - the header, the length, the
## vertex count against the OBJ, and the one property that matters to a player:
## the two armies are far apart in brightness.
func _test_colour_sidecars() -> void:
	const KINDS := ["pawn", "rook", "knight", "bishop", "queen", "king"]
	const MATERIALS := 3
	var pale_totals := 0.0
	var ink_totals := 0.0
	var samples := 0
	var seen := {}
	for kind in KINDS:
		var path := "res://assets/models/pars/%s.tint" % kind
		var file := FileAccess.open(path, FileAccess.READ)
		_expect(file != null, "%s.tint is in the project" % kind)
		if file == null:
			continue
		var raw := file.get_buffer(file.get_length())
		file.close()
		_expect(raw.slice(0, 4).get_string_from_ascii() == "TINT",
			"%s.tint is a TINT sidecar" % kind)
		_expect(raw[4] == 4, "%s.tint is version 4 (material map)" % kind)
		var count := raw.decode_u32(5)
		var materials := raw[9]
		_expect(materials == MATERIALS, "%s.tint names %d materials" % [kind, MATERIALS])
		_expect(raw.size() == 10 + materials * 6 + count,
			"%s.tint is exactly its header plus one byte per vertex" % kind)
		# The OBJ's vertex count is the number the reader indexes with, so a
		# mismatch here is a wrong colour on every vertex after the first gap.
		var mesh := FileAccess.open("res://assets/models/pars/%s.obj" % kind, FileAccess.READ)
		var vertices := 0
		if mesh != null:
			while not mesh.eof_reached():
				if mesh.get_line().begins_with("v "):
					vertices += 1
			mesh.close()
		_expect(count == vertices, "%s.tint has one material per vertex (%d vs %d)"
			% [kind, count, vertices])
		var pale := []
		var ink := []
		for i in materials:
			pale.append(Color8(raw[10 + i * 3], raw[11 + i * 3], raw[12 + i * 3]))
			ink.append(Color8(raw[10 + materials * 3 + i * 3],
				raw[11 + materials * 3 + i * 3], raw[12 + materials * 3 + i * 3]))
		var out_of_range := 0
		for i in count:
			var label: int = raw[10 + materials * 6 + i]
			if label >= materials:
				out_of_range += 1
			seen[label] = true
			var pale_colour: Color = pale[mini(label, materials - 1)]
			var ink_colour: Color = ink[mini(label, materials - 1)]
			pale_totals += pale_colour.srgb_to_linear().get_luminance()
			ink_totals += ink_colour.srgb_to_linear().get_luminance()
			samples += 1
		_expect(out_of_range == 0, "%s.tint names no material that does not exist" % kind)
	for material in MATERIALS:
		_expect(seen.has(material), "some piece uses material %d" % material)
	_expect(samples > 0, "the sidecars were read (%d vertices)" % samples)
	if samples > 0:
		var pale_average := pale_totals / samples
		var ink_average := ink_totals / samples
		_expect(ink_average < pale_average * 0.7,
			"the two armies are different in brightness (%.2f vs %.2f)"
				% [pale_average, ink_average])


## The sidecar is indexed by the OBJ's vertex order, and that promise is what
## obj_loader.gd exists to keep: Godot's OBJ importer builds its own vertex array
## (in face order, and reordered again to optimise the vertex cache), so index N
## of the imported mesh is not vertex N of the file.
##
## The one sided symptom was the pars set drawing as confetti - a clean material
## map in file order, applied to a different order - and it survived two rounds
## of looking at the colours themselves. So the order is what is checked: every
## `v` line is one vertex, in the order it appears, and every face index is
## within them.
func _test_obj_loader_matches_the_file() -> void:
	var loaded: Dictionary = ObjLoader.load_arrays("res://assets/models/pars/knight.obj")
	_expect(not loaded.is_empty(), "the knight body parses")
	if loaded.is_empty():
		return
	var positions: PackedVector3Array = loaded["positions"]
	var indices: PackedInt32Array = loaded["indices"]
	# Counted the slow way, from the file, so this is a comparison and not a
	# restatement of what the loader believes.
	var file := FileAccess.open("res://assets/models/pars/knight.obj", FileAccess.READ)
	var vertices := []
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("v "):
			var parts := line.split(" ", false)
			vertices.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
	file.close()
	_expect(positions.size() == vertices.size(),
		"obj_loader keeps one vertex per `v` line (%d vs %d)" % [positions.size(), vertices.size()])
	var order_ok := true
	for i in mini(positions.size(), vertices.size()):
		if not positions[i].is_equal_approx(vertices[i]):
			order_ok = false
			break
	_expect(order_ok, "obj_loader keeps the file's vertex order, so a sidecar index means something")
	_expect(indices.size() % 3 == 0, "obj_loader returns whole triangles")
	var in_range := true
	for index in indices:
		if index < 0 or index >= positions.size():
			in_range = false
			break
	_expect(in_range, "every face index is inside the vertex list")
	# The sidecar's length is the contract between the two files.
	var tint := FileAccess.open("res://assets/models/pars/knight.tint", FileAccess.READ)
	var raw := tint.get_buffer(tint.get_length())
	tint.close()
	_expect(raw.decode_u32(5) == positions.size(),
		"the knight's sidecar covers exactly the vertices obj_loader returns")
