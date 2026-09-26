extends SceneTree

const ChessGame = preload("res://src/chess/chess_game.gd")
var passed := 0
var failed := 0


func _init() -> void:
	_test_initial_position()
	_test_basic_moves()
	_test_illegal_move_and_check()
	_test_castling()
	_test_en_passant()
	_test_promotion()
	_test_checkmate()
	_test_stalemate()
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
	var promotion := _find_move(game, Vector2i(0, 1), Vector2i(0, 0))
	_expect(promotion.get("promotion", "") == "Q", "promotion move is marked")
	game.play(promotion)
	_expect(game.board[0][0] == "Q", "pawn promotes to queen")


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
