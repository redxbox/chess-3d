class_name OfflineChessAI
extends RefCounted
## Lightweight fully-offline chess AI using alpha-beta search.
## Designed as the fallback/easy-medium engine beside a future native Stockfish adapter.

const ChessGame = preload("res://src/chess/chess_game.gd")
const INF := 1_000_000
const VALUES := {"p": 100, "n": 320, "b": 330, "r": 500, "q": 900, "k": 20_000}


static func choose_move(fen: String, difficulty: String) -> Dictionary:
	var game = ChessGame.new()
	if not game.load_fen(fen) or not game.is_valid_position():
		return {}
	var moves := game.legal_moves()
	if moves.is_empty():
		return {}
	if difficulty == "easy":
		return _easy_move(moves)

	var depth := 2 if difficulty == "medium" else 3
	var ai_color: int = game.turn
	var best_score := -INF
	var best_moves: Array[Dictionary] = []
	for move in _ordered_moves(moves):
		var snapshot := game._snapshot()
		game._apply_unchecked(move)
		var score := -_negamax(game, depth - 1, -INF, INF, 1 - ai_color)
		game._restore(snapshot)
		if score > best_score:
			best_score = score
			best_moves = [move]
		elif score == best_score:
			best_moves.append(move)
	return best_moves.pick_random()


static func _easy_move(moves: Array[Dictionary]) -> Dictionary:
	var weighted: Array[Dictionary] = []
	for move in moves:
		weighted.append(move)
		if move.captured != "" and randf() < 0.45:
			weighted.append(move)
	return weighted.pick_random()


static func _negamax(game, depth: int, alpha: int, beta: int, perspective: int) -> int:
	if depth <= 0:
		return _evaluate(game, perspective)
	var moves := game.legal_moves()
	if moves.is_empty():
		if game.is_in_check(game.turn):
			return -INF + depth
		return 0
	var best := -INF
	var local_alpha := alpha
	for move in _ordered_moves(moves):
		var snapshot := game._snapshot()
		game._apply_unchecked(move)
		var score := -_negamax(game, depth - 1, -beta, -local_alpha, 1 - perspective)
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
	var ordered := moves.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_value: int = VALUES.get(a.captured.to_lower(), 0)
		var b_value: int = VALUES.get(b.captured.to_lower(), 0)
		return a_value > b_value
	)
	return ordered
