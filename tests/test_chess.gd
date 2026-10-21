extends SceneTree

const ChessGame = preload("res://src/chess/chess_game.gd")
const OfflineAI = preload("res://src/ai/offline_ai.gd")
const GameArchive = preload("res://src/storage/game_archive.gd")
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
