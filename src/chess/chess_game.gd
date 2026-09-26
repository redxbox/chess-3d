class_name ChessGame
extends RefCounted
## Complete, UI-independent chess rules engine.

const WHITE := 0
const BLACK := 1

var board: Array = []
var turn := WHITE
var castling := {"K": true, "Q": true, "k": true, "q": true}
var en_passant := Vector2i(-1, -1)
var halfmove_clock := 0
var fullmove_number := 1
var result := ""
var history: Array[Dictionary] = []
var move_notation: Array[String] = []
var position_counts: Dictionary = {}


func _init() -> void:
	reset()


func reset() -> void:
	board = []
	for rank in 8:
		board.append(["", "", "", "", "", "", "", ""])
	board[0] = ["r", "n", "b", "q", "k", "b", "n", "r"]
	board[1] = ["p", "p", "p", "p", "p", "p", "p", "p"]
	board[6] = ["P", "P", "P", "P", "P", "P", "P", "P"]
	board[7] = ["R", "N", "B", "Q", "K", "B", "N", "R"]
	turn = WHITE
	castling = {"K": true, "Q": true, "k": true, "q": true}
	en_passant = Vector2i(-1, -1)
	halfmove_clock = 0
	fullmove_number = 1
	result = ""
	history.clear()
	move_notation.clear()
	position_counts.clear()
	position_counts[_position_key()] = 1


func color_of(piece: String) -> int:
	return WHITE if piece == piece.to_upper() else BLACK


func legal_moves(from := Vector2i(-1, -1)) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if result != "":
		return moves
	for y in 8:
		for x in 8:
			var origin := Vector2i(x, y)
			var piece: String = board[y][x]
			if piece == "" or color_of(piece) != turn or (from.x >= 0 and origin != from):
				continue
			for move in _pseudo_moves(origin):
				var snapshot := _snapshot()
				_apply_unchecked(move)
				var legal := not is_in_check(turn)
				_restore(snapshot)
				if legal:
					moves.append(move)
	return moves


func play(move: Dictionary) -> bool:
	var found := false
	for legal in legal_moves(move.from):
		if legal.to == move.to:
			move = legal
			found = true
			break
	if not found:
		return false
	var notation := _notation_for(move)
	history.append(_snapshot())
	_apply_unchecked(move)
	var key := _position_key()
	position_counts[key] = position_counts.get(key, 0) + 1
	_update_result()
	if is_in_check(turn):
		notation += "#" if result.contains("checkmate") else "+"
	move_notation.append(notation)
	return true


func undo() -> bool:
	if history.is_empty():
		return false
	_restore(history.pop_back())
	result = ""
	return true


func is_in_check(color: int) -> bool:
	var king := "K" if color == WHITE else "k"
	var king_pos := Vector2i(-1, -1)
	for y in 8:
		for x in 8:
			if board[y][x] == king:
				king_pos = Vector2i(x, y)
	if king_pos.x < 0:
		return true
	return _is_attacked(king_pos, 1 - color)


func _pseudo_moves(from: Vector2i) -> Array[Dictionary]:
	var piece: String = board[from.y][from.x]
	var kind := piece.to_lower()
	var color := color_of(piece)
	var moves: Array[Dictionary] = []
	if kind == "p":
		var direction := -1 if color == WHITE else 1
		var start_rank := 6 if color == WHITE else 1
		var one := from + Vector2i(0, direction)
		if _inside(one) and board[one.y][one.x] == "":
			_add_move(moves, from, one, piece)
			var two := from + Vector2i(0, direction * 2)
			if from.y == start_rank and board[two.y][two.x] == "":
				moves.append(_move(from, two, piece, "", {"double": true}))
		for dx in [-1, 1]:
			var target := from + Vector2i(dx, direction)
			if not _inside(target):
				continue
			if board[target.y][target.x] != "" and color_of(board[target.y][target.x]) != color:
				_add_move(moves, from, target, piece)
			elif target == en_passant:
				moves.append(_move(from, target, piece, "p" if color == WHITE else "P", {"en_passant": true}))
	elif kind == "n":
		for delta in [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]:
			_add_if_available(moves, from, from + delta, piece)
	elif kind == "b":
		_slide(moves, from, piece, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
	elif kind == "r":
		_slide(moves, from, piece, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	elif kind == "q":
		_slide(moves, from, piece, [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)])
	elif kind == "k":
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx != 0 or dy != 0:
					_add_if_available(moves, from, from + Vector2i(dx, dy), piece)
		_add_castling(moves, from, color, piece)
	return moves


func _add_castling(moves: Array[Dictionary], from: Vector2i, color: int, piece: String) -> void:
	var rank := 7 if color == WHITE else 0
	var enemy := 1 - color
	if from != Vector2i(4, rank) or is_in_check(color):
		return
	var king_key := "K" if color == WHITE else "k"
	var queen_key := "Q" if color == WHITE else "q"
	if castling[king_key] and board[rank][5] == "" and board[rank][6] == "" and not _is_attacked(Vector2i(5, rank), enemy) and not _is_attacked(Vector2i(6, rank), enemy):
		moves.append(_move(from, Vector2i(6, rank), piece, "", {"castle": "king"}))
	if castling[queen_key] and board[rank][1] == "" and board[rank][2] == "" and board[rank][3] == "" and not _is_attacked(Vector2i(3, rank), enemy) and not _is_attacked(Vector2i(2, rank), enemy):
		moves.append(_move(from, Vector2i(2, rank), piece, "", {"castle": "queen"}))


func _is_attacked(square: Vector2i, by_color: int) -> bool:
	var pawn := "P" if by_color == WHITE else "p"
	var pawn_dir := -1 if by_color == WHITE else 1
	for dx in [-1, 1]:
		var origin := square - Vector2i(dx, pawn_dir)
		if _inside(origin) and board[origin.y][origin.x] == pawn:
			return true
	var knight := "N" if by_color == WHITE else "n"
	for delta in [Vector2i(1, 2), Vector2i(2, 1), Vector2i(-1, 2), Vector2i(-2, 1), Vector2i(1, -2), Vector2i(2, -1), Vector2i(-1, -2), Vector2i(-2, -1)]:
		var origin := square + delta
		if _inside(origin) and board[origin.y][origin.x] == knight:
			return true
	for data in [[Vector2i(1, 0), "rq"], [Vector2i(-1, 0), "rq"], [Vector2i(0, 1), "rq"], [Vector2i(0, -1), "rq"], [Vector2i(1, 1), "bq"], [Vector2i(-1, 1), "bq"], [Vector2i(1, -1), "bq"], [Vector2i(-1, -1), "bq"]]:
		var pos: Vector2i = square + data[0]
		while _inside(pos):
			var target: String = board[pos.y][pos.x]
			if target != "":
				if color_of(target) == by_color and data[1].contains(target.to_lower()):
					return true
				break
			pos += data[0]
	var king := "K" if by_color == WHITE else "k"
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var pos := square + Vector2i(dx, dy)
			if _inside(pos) and board[pos.y][pos.x] == king:
				return true
	return false


func _slide(moves: Array[Dictionary], from: Vector2i, piece: String, directions: Array) -> void:
	for direction in directions:
		var target: Vector2i = from + direction
		while _inside(target):
			if board[target.y][target.x] == "":
				moves.append(_move(from, target, piece))
			else:
				if color_of(board[target.y][target.x]) != color_of(piece):
					moves.append(_move(from, target, piece, board[target.y][target.x]))
				break
			target += direction


func _add_if_available(moves: Array[Dictionary], from: Vector2i, to: Vector2i, piece: String) -> void:
	if _inside(to) and (board[to.y][to.x] == "" or color_of(board[to.y][to.x]) != color_of(piece)):
		moves.append(_move(from, to, piece, board[to.y][to.x]))


func _add_move(moves: Array[Dictionary], from: Vector2i, to: Vector2i, piece: String) -> void:
	var extra := {}
	if to.y == 0 or to.y == 7:
		extra["promotion"] = "Q" if color_of(piece) == WHITE else "q"
	moves.append(_move(from, to, piece, board[to.y][to.x], extra))


func _move(from: Vector2i, to: Vector2i, piece: String, captured := "", extra := {}) -> Dictionary:
	var move := {"from": from, "to": to, "piece": piece, "captured": captured}
	move.merge(extra)
	return move


func _apply_unchecked(move: Dictionary) -> void:
	var piece: String = move.piece
	var color := color_of(piece)
	board[move.from.y][move.from.x] = ""
	if move.get("en_passant", false):
		board[move.to.y + (1 if color == WHITE else -1)][move.to.x] = ""
	if move.has("castle"):
		var rank: int = move.from.y
		if move.castle == "king":
			board[rank][5] = board[rank][7]
			board[rank][7] = ""
		else:
			board[rank][3] = board[rank][0]
			board[rank][0] = ""
	board[move.to.y][move.to.x] = move.get("promotion", piece)
	_update_castling_rights(piece, move.from, move.to)
	en_passant = Vector2i(move.from.x, (move.from.y + move.to.y) / 2) if move.get("double", false) else Vector2i(-1, -1)
	halfmove_clock = 0 if piece.to_lower() == "p" or move.captured != "" else halfmove_clock + 1
	if color == BLACK:
		fullmove_number += 1
	turn = 1 - turn


func _update_castling_rights(piece: String, from: Vector2i, to: Vector2i) -> void:
	if piece == "K": castling.K = false; castling.Q = false
	if piece == "k": castling.k = false; castling.q = false
	if from == Vector2i(0, 7) or to == Vector2i(0, 7): castling.Q = false
	if from == Vector2i(7, 7) or to == Vector2i(7, 7): castling.K = false
	if from == Vector2i(0, 0) or to == Vector2i(0, 0): castling.q = false
	if from == Vector2i(7, 0) or to == Vector2i(7, 0): castling.k = false


func _update_result() -> void:
	var available := legal_moves()
	if available.is_empty():
		result = ("Black wins by checkmate" if turn == WHITE else "White wins by checkmate") if is_in_check(turn) else "Draw by stalemate"
	elif position_counts.get(_position_key(), 0) >= 3:
		result = "Draw by threefold repetition"
	elif halfmove_clock >= 100:
		result = "Draw by fifty-move rule"
	elif _insufficient_material():
		result = "Draw by insufficient material"


func _insufficient_material() -> bool:
	var pieces: Array[String] = []
	for row in board:
		for piece in row:
			if piece != "" and piece.to_lower() != "k": pieces.append(piece.to_lower())
	return pieces.is_empty() or (pieces.size() == 1 and pieces[0] in ["b", "n"])


func to_fen() -> String:
	var ranks: Array[String] = []
	for y in 8:
		var rank := ""
		var empty := 0
		for x in 8:
			var piece: String = board[y][x]
			if piece == "":
				empty += 1
			else:
				if empty > 0: rank += str(empty); empty = 0
				rank += piece
		if empty > 0: rank += str(empty)
		ranks.append(rank)
	var rights := ""
	for key in ["K", "Q", "k", "q"]:
		if castling[key]: rights += key
	if rights == "": rights = "-"
	return "%s %s %s %s %d %d" % ["/".join(ranks), "w" if turn == WHITE else "b", rights, _square_name(en_passant) if en_passant.x >= 0 else "-", halfmove_clock, fullmove_number]


func load_fen(fen: String) -> bool:
	var fields := fen.strip_edges().split(" ", false)
	if fields.size() != 6:
		return false
	var ranks := fields[0].split("/")
	if ranks.size() != 8 or fields[1] not in ["w", "b"]:
		return false
	var parsed: Array = []
	for rank_text in ranks:
		var row: Array[String] = []
		for character in rank_text:
			if character.is_valid_int():
				for unused in int(character): row.append("")
			elif "prnbqkPRNBQK".contains(character):
				row.append(character)
			else:
				return false
		if row.size() != 8: return false
		parsed.append(row)
	if not fields[4].is_valid_int() or not fields[5].is_valid_int(): return false
	board = parsed
	turn = WHITE if fields[1] == "w" else BLACK
	castling = {"K": fields[2].contains("K"), "Q": fields[2].contains("Q"), "k": fields[2].contains("k"), "q": fields[2].contains("q")}
	en_passant = _parse_square(fields[3]) if fields[3] != "-" else Vector2i(-1, -1)
	if fields[3] != "-" and en_passant.x < 0: return false
	halfmove_clock = int(fields[4])
	fullmove_number = int(fields[5])
	result = ""
	history.clear()
	move_notation.clear()
	position_counts = {_position_key(): 1}
	return true


func to_pgn(headers := {}) -> String:
	var tags := {"Event": headers.get("Event", "Casual Game"), "Site": headers.get("Site", "Chess 3D Android"), "Date": headers.get("Date", Time.get_date_string_from_system().replace("-", ".")), "Round": headers.get("Round", "-"), "White": headers.get("White", "Player"), "Black": headers.get("Black", "Computer")}
	var output := ""
	for key in ["Event", "Site", "Date", "Round", "White", "Black"]:
		output += "[%s \"%s\"]\n" % [key, tags[key]]
	var result_code := "*"
	if result.begins_with("White wins"): result_code = "1-0"
	elif result.begins_with("Black wins"): result_code = "0-1"
	elif result.begins_with("Draw"): result_code = "1/2-1/2"
	output += "[Result \"%s\"]\n\n" % result_code
	for index in move_notation.size():
		if index % 2 == 0: output += "%d. " % (index / 2 + 1)
		output += move_notation[index] + " "
	return output + result_code


func _notation_for(move: Dictionary) -> String:
	if move.has("castle"):
		return "O-O" if move.castle == "king" else "O-O-O"
	var kind: String = move.piece.to_upper()
	var notation := "" if kind == "P" else kind
	if move.captured != "" or move.get("en_passant", false):
		if kind == "P": notation += "abcdefgh"[move.from.x]
		notation += "x"
	notation += _square_name(move.to)
	if move.has("promotion"): notation += "=" + str(move.promotion).to_upper()
	return notation


func _position_key() -> String:
	return " ".join(to_fen().split(" ").slice(0, 4))


func _square_name(square: Vector2i) -> String:
	return "abcdefgh"[square.x] + str(8 - square.y)


func _parse_square(value: String) -> Vector2i:
	if value.length() != 2: return Vector2i(-1, -1)
	var file := "abcdefgh".find(value[0])
	var rank := 8 - int(value[1]) if value[1].is_valid_int() else -1
	var square := Vector2i(file, rank)
	return square if _inside(square) else Vector2i(-1, -1)


func _snapshot() -> Dictionary:
	return {"board": board.duplicate(true), "turn": turn, "castling": castling.duplicate(), "en_passant": en_passant, "halfmove": halfmove_clock, "fullmove": fullmove_number, "result": result, "notation": move_notation.duplicate(), "positions": position_counts.duplicate()}


func _restore(snapshot: Dictionary) -> void:
	board = snapshot.board.duplicate(true)
	turn = snapshot.turn
	castling = snapshot.castling.duplicate()
	en_passant = snapshot.en_passant
	halfmove_clock = snapshot.halfmove
	fullmove_number = snapshot.fullmove
	result = snapshot.result
	move_notation = snapshot.get("notation", []).duplicate()
	position_counts = snapshot.get("positions", {}).duplicate()


func _inside(square: Vector2i) -> bool:
	return square.x >= 0 and square.x < 8 and square.y >= 0 and square.y < 8
