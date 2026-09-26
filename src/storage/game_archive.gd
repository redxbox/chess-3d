class_name GameArchive
extends RefCounted
## Persistent local archive. Uses versioned JSON and never requires network access.

const FORMAT_VERSION := 1
const MAX_GAMES := 50
var path := "user://game_archive.json"
var games: Array[Dictionary] = []


func _init(custom_path := "") -> void:
	if custom_path != "":
		path = custom_path
	load_archive()


func load_archive() -> bool:
	games.clear()
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != FORMAT_VERSION:
		return false
	for entry in parsed.get("games", []):
		if entry is Dictionary and entry.has("pgn") and entry.has("id"):
			games.append(entry)
	return true


func add_game(pgn: String, result: String, metadata := {}) -> String:
	var id := "%d-%d" % [int(Time.get_unix_time_from_system()), randi_range(1000, 9999)]
	var entry: Dictionary = {
		"id": id,
		"saved_at": Time.get_unix_time_from_system(),
		"date": Time.get_datetime_string_from_system(false, true),
		"result": result,
		"pgn": pgn,
		"white_time": metadata.get("white_time", 0.0),
		"black_time": metadata.get("black_time", 0.0),
		"mode": metadata.get("mode", "ai"),
		"difficulty": metadata.get("difficulty", "medium")
	}
	games.push_front(entry)
	if games.size() > MAX_GAMES:
		games.resize(MAX_GAMES)
	save_archive()
	return id


func remove_game(id: String) -> bool:
	for index in games.size():
		if games[index].id == id:
			games.remove_at(index)
			save_archive()
			return true
	return false


func save_archive() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return false
	file.store_string(JSON.stringify({"version": FORMAT_VERSION, "games": games}, "  "))
	return true
