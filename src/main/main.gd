extends Node3D
## Android-first 3D chess presentation and touch controller.

const ChessRules = preload("res://src/chess/chess_game.gd")
const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0

@onready var board: Node3D = $Board
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var game := ChessRules.new()
var pieces_root := Node3D.new()
var highlights_root := Node3D.new()
var selected := Vector2i(-1, -1)
var selected_moves: Array[Dictionary] = []
var play_vs_ai := true
var ai_thinking := false
var _dragging := false
var _pointer_moved := false
var _last_pointer := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _drag_piece_from := Vector2i(-1, -1)
var _drag_piece_active := false
var haptics_enabled := true
var _status_label: Label
var _clock_label: Label
var _top_panel: HBoxContainer
var _mode_button: Button
var clock_enabled := true
var white_time := 600.0
var black_time := 600.0
var _autosave_accumulator := 0.0
const AUTOSAVE_PATH := "user://autosave.json"


func _ready() -> void:
	_setup_environment()
	_create_board()
	pieces_root.name = "Pieces"
	highlights_root.name = "Highlights"
	board.add_child(highlights_root)
	board.add_child(pieces_root)
	if not _load_autosave():
		game.reset()
	_create_pieces()
	_create_ui()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_status()


func _process(delta: float) -> void:
	if clock_enabled and game.result == "":
		if game.turn == ChessRules.WHITE:
			white_time = maxf(0.0, white_time - delta)
			if white_time <= 0.0:
				game.result = "Black wins on time"
		else:
			black_time = maxf(0.0, black_time - delta)
			if black_time <= 0.0:
				game.result = "White wins on time"
		_update_clock_label()
		if game.result != "":
			_update_status()
			_save_autosave()
	_autosave_accumulator += delta
	if _autosave_accumulator >= 5.0:
		_autosave_accumulator = 0.0
		_save_autosave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_autosave()


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111725")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("7180a0")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	$WorldEnvironment.environment = environment


func _create_board() -> void:
	var light_material := _material(Color("d7c4a2"), 0.42, 0.0)
	var dark_material := _material(Color("4b2633"), 0.34, 0.1)

	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var square := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(SQUARE_SIZE, 0.14, SQUARE_SIZE)
			mesh.material = light_material if (file + rank) % 2 == 0 else dark_material
			square.mesh = mesh
			square.position = Vector3(
				(file - 3.5) * SQUARE_SIZE,
				0.0,
				(rank - 3.5) * SQUARE_SIZE
			)
			board.add_child(square)

	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(9.0, 0.32, 9.0)
	base_mesh.material = _material(Color("201820"), 0.28, 0.25)
	base.mesh = base_mesh
	base.position.y = -0.22
	board.add_child(base)


func _create_pieces() -> void:
	for child in pieces_root.get_children():
		child.queue_free()
	var ivory := _material(Color("d8c49a"), 0.24, 0.28)
	var ruby := _material(Color("68172f"), 0.2, 0.38)
	var names := {"p": "pawn", "r": "rook", "n": "knight", "b": "bishop", "q": "queen", "k": "king"}
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var code: String = game.board[rank][file]
			if code != "":
				_add_piece(names[code.to_lower()], file, rank, ivory if code == code.to_upper() else ruby)


func _add_piece(kind: String, file: int, rank: int, material: Material) -> void:
	var piece := Node3D.new()
	piece.name = "%s_%d_%d" % [kind.capitalize(), file, rank]
	piece.position = Vector3((file - 3.5) * SQUARE_SIZE, 0.12, (rank - 3.5) * SQUARE_SIZE)
	piece.set_meta("square", Vector2i(file, rank))
	pieces_root.add_child(piece)

	_add_cylinder(piece, 0.32, 0.42, 0.14, 0.08, material)
	_add_cylinder(piece, 0.23, 0.29, 0.26, 0.26, material)

	match kind:
		"pawn":
			_add_cylinder(piece, 0.13, 0.20, 0.42, 0.50, material)
			_add_sphere(piece, 0.20, 0.82, material)
		"rook":
			_add_cylinder(piece, 0.21, 0.25, 0.54, 0.53, material)
			_add_cylinder(piece, 0.32, 0.25, 0.16, 0.88, material)
		"knight":
			_add_cylinder(piece, 0.16, 0.23, 0.48, 0.50, material)
			_add_sphere(piece, 0.24, 0.88, material, Vector3(0.08, 0.0, -0.05))
			_add_cylinder(piece, 0.08, 0.16, 0.32, 1.04, material, Vector3(22, 0, 0))
		"bishop":
			_add_cylinder(piece, 0.12, 0.22, 0.62, 0.54, material)
			_add_sphere(piece, 0.22, 0.96, material)
			_add_sphere(piece, 0.07, 1.19, material)
		"queen":
			_add_cylinder(piece, 0.14, 0.24, 0.72, 0.58, material)
			_add_cylinder(piece, 0.28, 0.15, 0.16, 1.00, material)
			_add_sphere(piece, 0.11, 1.19, material)
		"king":
			_add_cylinder(piece, 0.15, 0.25, 0.78, 0.60, material)
			_add_cylinder(piece, 0.26, 0.16, 0.13, 1.05, material)
			_add_cylinder(piece, 0.055, 0.055, 0.34, 1.28, material)
			_add_cylinder(piece, 0.055, 0.055, 0.25, 1.38, material, Vector3(0, 0, 90))


func _add_cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, y: float, material: Material, rotation := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 3
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = y
	mesh_instance.rotation_degrees = rotation
	parent.add_child(mesh_instance)


func _add_sphere(parent: Node3D, radius: float, y: float, material: Material, offset := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(offset.x, y + offset.y, offset.z)
	parent.add_child(mesh_instance)


func _create_ui() -> void:
	_top_panel = HBoxContainer.new()
	var panel := _top_panel
	panel.add_theme_constant_override("separation", 10)
	$UI.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(210, 50)
	_status_label.add_theme_font_size_override("font_size", 20)
	panel.add_child(_status_label)

	_clock_label = Label.new()
	_clock_label.custom_minimum_size = Vector2(155, 50)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 20)
	panel.add_child(_clock_label)

	_mode_button = Button.new()
	_mode_button.text = "VS AI" if play_vs_ai else "LOCAL"
	_mode_button.custom_minimum_size = Vector2(82, 48)
	_mode_button.pressed.connect(_toggle_game_mode)
	panel.add_child(_mode_button)

	var clock_button := Button.new()
	clock_button.text = "CLOCK"
	clock_button.custom_minimum_size = Vector2(86, 48)
	clock_button.pressed.connect(_toggle_clock)
	panel.add_child(clock_button)

	var camera_button := Button.new()
	camera_button.text = "VIEW"
	camera_button.custom_minimum_size = Vector2(78, 48)
	camera_button.pressed.connect(_reset_camera)
	panel.add_child(camera_button)

	var haptic_button := Button.new()
	haptic_button.text = "VIBE" if haptics_enabled else "VIBE OFF"
	haptic_button.custom_minimum_size = Vector2(72, 48)
	haptic_button.pressed.connect(_toggle_haptics.bind(haptic_button))
	panel.add_child(haptic_button)

	var undo_button := Button.new()
	undo_button.text = "UNDO"
	undo_button.custom_minimum_size = Vector2(86, 48)
	undo_button.pressed.connect(_undo)
	panel.add_child(undo_button)

	var new_button := Button.new()
	new_button.text = "NEW"
	new_button.custom_minimum_size = Vector2(86, 48)
	new_button.pressed.connect(_new_game)
	panel.add_child(new_button)


func _select_square(square: Vector2i) -> void:
	if ai_thinking or game.result != "":
		return
	var destination_moves: Array[Dictionary] = []
	for move in selected_moves:
		if move.to == square:
			destination_moves.append(move)
	if destination_moves.size() > 1 and destination_moves[0].has("promotion"):
		_show_promotion_picker(destination_moves)
		return
	elif destination_moves.size() == 1:
		_play_move(destination_moves[0])
		return
	var piece: String = game.board[square.y][square.x]
	if piece != "" and game.color_of(piece) == game.turn:
		selected = square
		selected_moves = game.legal_moves(square)
		_haptic(18)
	else:
		selected = Vector2i(-1, -1)
		selected_moves.clear()
	_draw_highlights()


func _show_promotion_picker(moves: Array[Dictionary]) -> void:
	var popup := PopupPanel.new()
	popup.name = "PromotionPicker"
	var layout := VBoxContainer.new()
	layout.custom_minimum_size = Vector2(320, 250)
	var title := Label.new()
	title.text = "CHOOSE PROMOTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	layout.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(row)
	var labels := {"Q": "QUEEN", "R": "ROOK", "B": "BISHOP", "N": "KNIGHT"}
	for move in moves:
		var button := Button.new()
		button.text = labels[str(move.promotion).to_upper()]
		button.custom_minimum_size = Vector2(72, 150)
		button.pressed.connect(_choose_promotion.bind(move, popup))
		row.add_child(button)
	popup.add_child(layout)
	$UI.add_child(popup)
	popup.popup_centered(Vector2i(420, 260))


func _choose_promotion(move: Dictionary, popup: PopupPanel) -> void:
	popup.hide()
	popup.queue_free()
	_play_move(move)


func _play_move(move: Dictionary) -> void:
	if not game.play(move):
		return
	_haptic(35 if move.captured != "" else 22)
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_save_autosave()
	if play_vs_ai and game.turn == ChessRules.BLACK and game.result == "":
		ai_thinking = true
		_update_status()
		get_tree().create_timer(0.45).timeout.connect(_play_ai_move)
	elif not play_vs_ai and game.result == "":
		_flip_camera_for_local_turn()


func _play_ai_move() -> void:
	var moves := game.legal_moves()
	if not moves.is_empty():
		var best_moves: Array[Dictionary] = []
		var best_score := -999
		var values := {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9, "k": 0, "": 0}
		for move in moves:
			var score: int = values[move.captured.to_lower()] * 10 + randi_range(0, 5)
			if score > best_score:
				best_score = score
				best_moves = [move]
			elif score == best_score:
				best_moves.append(move)
		game.play(best_moves.pick_random())
	ai_thinking = false
	_create_pieces()
	_update_status()
	_save_autosave()


func _draw_highlights() -> void:
	for child in highlights_root.get_children():
		child.queue_free()
	if selected.x >= 0:
		_add_highlight(selected, Color(0.95, 0.72, 0.18, 0.62), 0.47)
	for move in selected_moves:
		_add_highlight(move.to, Color(0.2, 0.85, 0.55, 0.72), 0.18 if move.captured == "" else 0.38)


func _add_highlight(square: Vector2i, color: Color, radius: float) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.025
	mesh.radial_segments = 32
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	marker.mesh = mesh
	marker.position = Vector3((square.x - 3.5) * SQUARE_SIZE, 0.1, (square.y - 3.5) * SQUARE_SIZE)
	highlights_root.add_child(marker)


func _screen_to_square(screen_position: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var plane := Plane(Vector3.UP, 0.1)
	var hit = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector2i(-1, -1)
	var local: Vector3 = board.to_local(hit)
	var file := floori(local.x / SQUARE_SIZE + 4.0)
	var rank := floori(local.z / SQUARE_SIZE + 4.0)
	return Vector2i(file, rank) if file in range(8) and rank in range(8) else Vector2i(-1, -1)


func _update_status() -> void:
	if game.result != "":
		_status_label.text = game.result
	elif ai_thinking:
		_status_label.text = "Computer thinking..."
	else:
		var side := "White" if game.turn == ChessRules.WHITE else "Black"
		_status_label.text = side + (" — CHECK" if game.is_in_check(game.turn) else " to move")
	_update_clock_label()


func _update_clock_label() -> void:
	if not is_instance_valid(_clock_label):
		return
	if not clock_enabled:
		_clock_label.text = "Clock: OFF"
		return
	_clock_label.text = "W %s  •  B %s" % [_format_time(white_time), _format_time(black_time)]


func _format_time(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _apply_safe_area() -> void:
	if not is_instance_valid(_top_panel):
		return
	var window_size := Vector2(DisplayServer.window_get_size())
	var viewport_size := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var scale_x := viewport_size.x / maxf(window_size.x, 1.0)
	var scale_y := viewport_size.y / maxf(window_size.y, 1.0)
	var right_inset := maxf(20.0, (window_size.x - safe.end.x) * scale_x + 20.0)
	var top_inset := maxf(20.0, safe.position.y * scale_y + 20.0)
	_top_panel.offset_left = -970.0 - right_inset
	_top_panel.offset_top = top_inset
	_top_panel.offset_right = -right_inset
	_top_panel.offset_bottom = top_inset + 64.0


func _toggle_game_mode() -> void:
	play_vs_ai = not play_vs_ai
	_mode_button.text = "VS AI" if play_vs_ai else "LOCAL"
	_new_game()


func _toggle_clock() -> void:
	clock_enabled = not clock_enabled
	_update_clock_label()
	_save_autosave()


func _toggle_haptics(button: Button) -> void:
	haptics_enabled = not haptics_enabled
	button.text = "VIBE" if haptics_enabled else "VIBE OFF"
	_haptic(25)
	_save_autosave()


func _save_autosave() -> void:
	if not is_inside_tree():
		return
	var data := {
		"version": 1,
		"pgn": game.to_pgn({"White": "Player", "Black": "Offline AI"}),
		"fen": game.to_fen(),
		"result": game.result,
		"white_time": white_time,
		"black_time": black_time,
		"clock_enabled": clock_enabled,
		"haptics_enabled": haptics_enabled,
		"camera_yaw": camera_rig.rotation.y,
		"camera_distance": camera.position.length(),
		"play_vs_ai": play_vs_ai,
		"saved_at": Time.get_unix_time_from_system()
	}
	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func _load_autosave() -> bool:
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return false
	var file := FileAccess.open(AUTOSAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or int(parsed.get("version", 0)) != 1:
		return false
	var loaded := false
	var pgn: String = parsed.get("pgn", "")
	if pgn != "":
		loaded = game.load_pgn(pgn).ok
	if not loaded:
		loaded = game.load_fen(parsed.get("fen", ""))
	if not loaded or not game.is_valid_position():
		game.reset()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUTOSAVE_PATH))
		return false
	white_time = maxf(0.0, float(parsed.get("white_time", 600.0)))
	black_time = maxf(0.0, float(parsed.get("black_time", 600.0)))
	clock_enabled = bool(parsed.get("clock_enabled", true))
	haptics_enabled = bool(parsed.get("haptics_enabled", true))
	camera_rig.rotation.y = float(parsed.get("camera_yaw", 0.0))
	_set_camera_distance(float(parsed.get("camera_distance", camera.position.length())))
	play_vs_ai = bool(parsed.get("play_vs_ai", true))
	game.result = parsed.get("result", game.result)
	return true


func _undo() -> void:
	if ai_thinking:
		return
	if game.undo() and play_vs_ai and game.turn == ChessRules.BLACK:
		game.undo()
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_save_autosave()


func _new_game() -> void:
	game.reset()
	camera_rig.rotation.y = 0.0
	white_time = 600.0
	black_time = 600.0
	ai_thinking = false
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_save_autosave()


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_dragging = true
			_pointer_moved = _touches.size() > 1
			_last_pointer = event.position
			if _touches.size() == 1:
				var pressed_square := _screen_to_square(event.position)
				if pressed_square.x >= 0:
					var pressed_piece: String = game.board[pressed_square.y][pressed_square.x]
					if pressed_piece != "" and game.color_of(pressed_piece) == game.turn:
						_drag_piece_from = pressed_square
						_select_square(pressed_square)
			if _touches.size() == 2:
				_drag_piece_from = Vector2i(-1, -1)
				_drag_piece_active = false
				_pinch_distance = _current_pinch_distance()
		else:
			var was_single_touch := _touches.size() == 1
			_touches.erase(event.index)
			var released_square := _screen_to_square(event.position)
			if _drag_piece_active:
				_snap_dragged_piece()
			if was_single_touch and _drag_piece_active and released_square.x >= 0:
				_select_square(released_square)
			elif was_single_touch and not _pointer_moved and released_square.x >= 0:
				_select_square(released_square)
			_drag_piece_from = Vector2i(-1, -1)
			_drag_piece_active = false
			_dragging = not _touches.is_empty()
			if _touches.size() < 2:
				_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var new_distance := _current_pinch_distance()
			if _pinch_distance > 0.0 and new_distance > 10.0:
				_zoom_camera(_pinch_distance / new_distance)
			_pinch_distance = new_distance
			_pointer_moved = true
		elif event.relative.length() > 3.0:
			_pointer_moved = true
			if _drag_piece_from.x >= 0:
				_drag_piece_active = true
				_update_drag_marker(event.position)
			else:
				_rotate_camera(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_pointer_moved = false
			_last_pointer = event.position
		else:
			if not _pointer_moved:
				var square := _screen_to_square(event.position)
				if square.x >= 0:
					_select_square(square)
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		if event.relative.length() > 3.0:
			_pointer_moved = true
			_rotate_camera(event.relative)
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
		_zoom_camera(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1)


func _update_drag_marker(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit = Plane(Vector3.UP, 0.55).intersects_ray(origin, direction)
	if hit == null:
		return
	var local_hit: Vector3 = board.to_local(hit)
	for piece in pieces_root.get_children():
		if piece.get_meta("square", Vector2i(-1, -1)) == _drag_piece_from:
			piece.position = Vector3(local_hit.x, 0.55, local_hit.z)
			return


func _snap_dragged_piece() -> void:
	for piece in pieces_root.get_children():
		if piece.get_meta("square", Vector2i(-1, -1)) == _drag_piece_from:
			piece.position = Vector3((_drag_piece_from.x - 3.5) * SQUARE_SIZE, 0.12, (_drag_piece_from.y - 3.5) * SQUARE_SIZE)
			return


func _current_pinch_distance() -> float:
	var positions := _touches.values()
	return positions[0].distance_to(positions[1]) if positions.size() >= 2 else 0.0


func _zoom_camera(factor: float) -> void:
	_set_camera_distance(camera.position.length() * factor)


func _set_camera_distance(distance: float) -> void:
	var target_distance := clampf(distance, 8.0, 16.0)
	camera.position = camera.position.normalized() * target_distance


func _rotate_camera(relative: Vector2) -> void:
	camera_rig.rotate_y(-relative.x * 0.006)
	camera_rig.rotation.y = wrapf(camera_rig.rotation.y, -PI, PI)


func _flip_camera_for_local_turn() -> void:
	var target_yaw := 0.0 if game.turn == ChessRules.WHITE else PI
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera_rig, "rotation:y", target_yaw, 0.55)


func _reset_camera() -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera_rig, "rotation:y", 0.0, 0.35)
	tween.tween_property(camera, "position", Vector3(0, 8.5, 9.5), 0.35)
	_haptic(20)


func _haptic(duration_ms: int) -> void:
	if haptics_enabled:
		Input.vibrate_handheld(duration_ms)
