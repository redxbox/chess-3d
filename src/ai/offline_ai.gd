class_name OfflineChessAI
extends RefCounted
## Lightweight fully-offline chess AI using alpha-beta search.
## Designed as the fallback/easy-medium engine beside a future native Stockfish adapter.

const ChessGame = preload("res://src/chess/chess_game.gd")
const INF := 1_000_000
const VALUES := {"p": 100, "n": 320, "b": 330, "r": 500, "q": 900, "k": 20_000}


static func choose_move(fen: String, difficulty: String) -> Dictionary:
	var game: ChessGame = ChessGame.new()
	if not game.load_fen(fen) or not game.is_valid_position():
		return {}
	var moves: Array[Dictionary] = game.legal_moves()
	if moves.is_empty():
		return {}
	var book_move := _opening_book_move(game, moves)
	if not book_move.is_empty() and difficulty != "easy":
		return book_move
	if difficulty == "easy":
		return _easy_move(moves)

	var depth := 2
	var time_budget_ms := 450
	if difficulty == "hard":
		depth = 3
		time_budget_ms = 1200
	elif difficulty == "professional":
		depth = 4
		time_budget_ms = 2600
	var deadline := Time.get_ticks_msec() + time_budget_ms
	var ai_color: int = game.turn
	var best_score := -INF
	var best_moves: Array[Dictionary] = []
	for move in _ordered_moves(moves):
		if not best_moves.is_empty() and Time.get_ticks_msec() >= deadline:
			break
		var snapshot: Dictionary = game._snapshot()
		game._apply_unchecked(move)
		var score := -_negamax(game, depth - 1, -INF, INF, 1 - ai_color, deadline)
		game._restore(snapshot)
		if score > best_score:
			best_score = score
			best_moves = [move]
		elif score == best_score:
			best_moves.append(move)
	return best_moves.pick_random()


static func _opening_book_move(game, moves: Array[Dictionary]) -> Dictionary:
	if game.fullmove_number != 1 or game.halfmove_clock != 0:
		return {}
	var candidates: Array[Array] = []
	if game.turn == ChessGame.WHITE:
		candidates = [[Vector2i(4, 6), Vector2i(4, 4)], [Vector2i(3, 6), Vector2i(3, 4)], [Vector2i(6, 7), Vector2i(5, 5)], [Vector2i(2, 6), Vector2i(2, 4)]]
	else:
		candidates = [[Vector2i(4, 1), Vector2i(4, 3)], [Vector2i(2, 1), Vector2i(2, 3)], [Vector2i(6, 0), Vector2i(5, 2)]]
	candidates.shuffle()
	for candidate in candidates:
		for move in moves:
			if move.from == candidate[0] and move.to == candidate[1]:
				return move
	return {}


static func _easy_move(moves: Array[Dictionary]) -> Dictionary:
	var weighted: Array[Dictionary] = []
	for move in moves:
		weighted.append(move)
		if move.captured != "" and randf() < 0.45:
			weighted.append(move)
	return weighted.pick_random()


static func _negamax(game, depth: int, alpha: int, beta: int, perspective: int, deadline: int) -> int:
	if depth <= 0 or Time.get_ticks_msec() >= deadline:
		return _evaluate(game, perspective)
	var moves: Array[Dictionary] = game.legal_moves()
	if moves.is_empty():
		if game.is_in_check(game.turn):
			return -INF + depth
		return 0
	var best := -INF
	var local_alpha := alpha
	for move in _ordered_moves(moves):
		var snapshot: Dictionary = game._snapshot()
		game._apply_unchecked(move)
		var score := -_negamax(game, depth - 1, -beta, -local_alpha, 1 - perspective, deadline)
		game._restore(snapshot)
		best = maxi(best, score)
		local_alpha = maxi(local_alpha, score)
		if local_alpha >= beta:
			break
	return best


static func _evaluate(game, perspective: int) -> int:
	var score := 0
	for y in 8:
		for x in 8:
			var piece: String = game.board[y][x]
			if piece == "":
				continue
			var value: int = VALUES[piece.to_lower()]
			var center_bonus := maxi(0, 6 - int(absf(x - 3.5) + absf(y - 3.5)))
			value += center_bonus
			score += value if game.color_of(piece) == perspective else -value
	return score


static func _ordered_moves(moves: Array[Dictionary]) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = moves.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_value: int = VALUES.get(a.captured.to_lower(), 0)
		var b_value: int = VALUES.get(b.captured.to_lower(), 0)
		return a_value > b_value
	)
	return ordered
