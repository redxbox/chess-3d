extends Node3D
## Android-first 3D chess presentation and touch controller.

const ChessRules = preload("res://src/chess/chess_game.gd")
const OfflineAI = preload("res://src/ai/offline_ai.gd")
const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0

@onready var board: Node3D = $Board
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var game := ChessRules.new()
var pieces_root := Node3D.new()
var highlights_root := Node3D.new()
var decor_root := Node3D.new()
var selected := Vector2i(-1, -1)
var selected_moves: Array[Dictionary] = []
var last_move: Dictionary = {}
var play_vs_ai := true
var human_color := ChessRules.WHITE
var ai_difficulty := "medium"
var language := "en"
var ai_thinking := false
var ai_generation := 0
var animating_move := false
var _dragging := false
var _pointer_moved := false
var _last_pointer := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_distance := 0.0
var _drag_piece_from := Vector2i(-1, -1)
var _drag_piece_active := false
var haptics_enabled := true
var graphics_quality := "auto"
var capture_effects_enabled := true
var _status_label: Label
var _graphics_button: Button
var _clock_label: Label
var _top_panel: HBoxContainer
var _mode_button: Button
var _menu_overlay: ColorRect
var _continue_button: Button
var _color_button: Button
var _difficulty_button: Button
var _language_button: Button
var _ai_start_button: Button
var _local_start_button: Button
var _close_menu_button: Button
var _history_label: RichTextLabel
var _captured_label: Label
var _game_over_dialog: AcceptDialog
var _resign_dialog: ConfirmationDialog
var _has_resumable_game := false
var clock_enabled := true
var white_time := 600.0
var black_time := 600.0
var _autosave_accumulator := 0.0
const AUTOSAVE_PATH := "user://autosave.json"


func _ready() -> void:
	_setup_environment()
	decor_root.name = "EnvironmentDetails"
	board.add_child(decor_root)
	_create_board()
	pieces_root.name = "Pieces"
	highlights_root.name = "Highlights"
	board.add_child(highlights_root)
	board.add_child(pieces_root)
	_has_resumable_game = _load_autosave()
	if not _has_resumable_game:
		game.reset()
	_create_pieces()
	_create_ui()
	_apply_graphics_quality()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_status()
	_show_main_menu()


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
			_show_game_over_if_needed()
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

	var wood := _material(Color("241418"), 0.3, 0.18)
	var gold := _material(Color("9f7440"), 0.22, 0.72)
	for rail in [
		[Vector3(0, -0.02, -4.38), Vector3(9.15, 0.26, 0.42)],
		[Vector3(0, -0.02, 4.38), Vector3(9.15, 0.26, 0.42)],
		[Vector3(-4.38, -0.02, 0), Vector3(0.42, 0.26, 8.35)],
		[Vector3(4.38, -0.02, 0), Vector3(0.42, 0.26, 8.35)]
	]:
		_add_board_box(rail[0], rail[1], wood)
	for accent in [
		[Vector3(0, 0.125, -4.12), Vector3(8.2, 0.035, 0.045)],
		[Vector3(0, 0.125, 4.12), Vector3(8.2, 0.035, 0.045)],
		[Vector3(-4.12, 0.125, 0), Vector3(0.045, 0.035, 8.2)],
		[Vector3(4.12, 0.125, 0), Vector3(0.045, 0.035, 8.2)]
	]:
		_add_board_box(accent[0], accent[1], gold)

	var table := MeshInstance3D.new()
	var table_mesh := CylinderMesh.new()
	table_mesh.top_radius = 5.8
	table_mesh.bottom_radius = 6.4
	table_mesh.height = 0.45
	table_mesh.radial_segments = 64
	table_mesh.material = wood
	table.mesh = table_mesh
	table.position.y = -0.58
	board.add_child(table)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(36.0, 36.0)
	floor_mesh.material = _material(Color("090d16"), 0.72, 0.06)
	floor.mesh = floor_mesh
	floor.position.y = -0.82
	decor_root.add_child(floor)
	_add_board_coordinates()
	_create_room_details(wood, gold)


func _add_board_coordinates() -> void:
	var label_color := Color("d5b875")
	for index in BOARD_SIZE:
		for data in [
			["abcdefgh"[index], Vector3((index - 3.5) * SQUARE_SIZE, 0.15, 4.34)],
			[str(8 - index), Vector3(-4.34, 0.15, (index - 3.5) * SQUARE_SIZE)]
		]:
			var label := Label3D.new()
			label.text = data[0]
			label.font_size = 48
			label.modulate = label_color
			label.outline_size = 8
			label.outline_modulate = Color(0.03, 0.02, 0.03, 0.9)
			label.position = data[1]
			label.rotation_degrees.x = -90.0
			label.pixel_size = 0.005
			board.add_child(label)


func _create_room_details(wood: Material, gold: Material) -> void:
	for corner in [Vector3(-8.5, -0.8, -8.5), Vector3(8.5, -0.8, -8.5), Vector3(-8.5, -0.8, 8.5), Vector3(8.5, -0.8, 8.5)]:
		var column := Node3D.new()
		column.position = corner
		decor_root.add_child(column)
		_add_cylinder(column, 0.72, 0.9, 0.28, 0.14, gold)
		_add_cylinder(column, 0.42, 0.55, 4.8, 2.65, wood)
		_add_torus(column, 0.48, 0.08, 0.45, gold)
		_add_torus(column, 0.48, 0.08, 4.88, gold)
		_add_cylinder(column, 0.9, 0.72, 0.28, 5.04, gold)


func _add_board_box(position: Vector3, size: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	instance.mesh = mesh
	instance.position = position
	board.add_child(instance)


func _create_pieces() -> void:
	for child in pieces_root.get_children():
		child.queue_free()
	var ivory := _material(Color("c8ad78"), 0.3, 0.2)
	var ruby := _material(Color("591329"), 0.26, 0.32)
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
			_add_torus(piece, 0.15, 0.04, 0.70, material)
			_add_sphere(piece, 0.20, 0.84, material)
		"rook":
			_add_cylinder(piece, 0.21, 0.25, 0.54, 0.53, material)
			_add_torus(piece, 0.24, 0.055, 0.79, material)
			_add_cylinder(piece, 0.31, 0.27, 0.15, 0.88, material)
			for angle in [0.0, 90.0, 180.0, 270.0]:
				var offset := Vector3(cos(deg_to_rad(angle)) * 0.22, 1.02, sin(deg_to_rad(angle)) * 0.22)
				_add_box(piece, Vector3(0.16, 0.18, 0.16), offset, material)
		"knight":
			_add_cylinder(piece, 0.16, 0.23, 0.42, 0.48, material)
			_add_torus(piece, 0.19, 0.045, 0.70, material)
			_add_cylinder(piece, 0.13, 0.19, 0.48, 0.88, material, Vector3(-22, 0, 0))
			_add_sphere(piece, 0.22, 1.10, material, Vector3(0.0, 0.0, -0.10))
			_add_cylinder(piece, 0.035, 0.07, 0.20, 1.29, material, Vector3(-18, 0, -12))
			_add_cylinder(piece, 0.035, 0.07, 0.20, 1.29, material, Vector3(-18, 0, 12))
		"bishop":
			_add_cylinder(piece, 0.12, 0.22, 0.62, 0.54, material)
			_add_torus(piece, 0.20, 0.045, 0.83, material)
			_add_sphere(piece, 0.22, 1.00, material)
			_add_sphere(piece, 0.065, 1.23, material)
		"queen":
			_add_cylinder(piece, 0.14, 0.24, 0.72, 0.58, material)
			_add_torus(piece, 0.23, 0.05, 0.91, material)
			_add_cylinder(piece, 0.27, 0.18, 0.14, 1.01, material)
			for angle in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
				var crown_offset := Vector3(cos(deg_to_rad(angle)) * 0.22, 0.0, sin(deg_to_rad(angle)) * 0.22)
				_add_sphere(piece, 0.065, 1.16, material, crown_offset)
			_add_sphere(piece, 0.10, 1.22, material)
		"king":
			_add_cylinder(piece, 0.15, 0.25, 0.78, 0.60, material)
			_add_torus(piece, 0.23, 0.05, 0.96, material)
			_add_cylinder(piece, 0.26, 0.16, 0.13, 1.06, material)
			_add_cylinder(piece, 0.05, 0.05, 0.34, 1.29, material)
			_add_cylinder(piece, 0.05, 0.05, 0.25, 1.39, material, Vector3(0, 0, 90))


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


func _add_torus(parent: Node3D, radius: float, tube: float, y: float, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - tube)
	mesh.outer_radius = radius + tube
	mesh.rings = 24
	mesh.ring_segments = 8
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position.y = y
	parent.add_child(mesh_instance)


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = position
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

	var menu_button := Button.new()
	menu_button.text = "MENU"
	menu_button.custom_minimum_size = Vector2(82, 48)
	menu_button.pressed.connect(_show_main_menu)
	panel.add_child(menu_button)

	_graphics_button = Button.new()
	_graphics_button.position = Vector2(28, 78)
	_graphics_button.size = Vector2(128, 44)
	_graphics_button.pressed.connect(_cycle_graphics_quality)
	$UI.add_child(_graphics_button)
	_update_graphics_button()
	_create_main_menu()
	_create_game_panels()


func _create_main_menu() -> void:
	_menu_overlay = ColorRect.new()
	_menu_overlay.color = Color(0.025, 0.035, 0.055, 0.94)
	$UI.add_child(_menu_overlay)
	_menu_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	_menu_overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 700)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)

	var title := Label.new()
	title.text = "CHESS 3D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("e6cb8c"))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "A classic board. A new dimension."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	content.add_child(subtitle)

	_color_button = _menu_button("PLAY AS: " + ("WHITE" if human_color == ChessRules.WHITE else "BLACK"), _cycle_player_color)
	content.add_child(_color_button)
	_difficulty_button = _menu_button("AI LEVEL: " + ai_difficulty.to_upper(), _cycle_ai_difficulty)
	content.add_child(_difficulty_button)
	_language_button = _menu_button("LANGUAGE: ENGLISH", _cycle_language)
	content.add_child(_language_button)
	_continue_button = _menu_button("CONTINUE GAME", _continue_game)
	content.add_child(_continue_button)
	_ai_start_button = _menu_button("NEW GAME VS AI", _start_ai_game)
	content.add_child(_ai_start_button)
	_local_start_button = _menu_button("LOCAL TWO PLAYERS", _start_local_game)
	content.add_child(_local_start_button)
	_close_menu_button = _menu_button("CLOSE MENU", _continue_game)
	content.add_child(_close_menu_button)

	var version := Label.new()
	version.text = "Android • Offline • v0.6.0"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75, 1))
	content.add_child(version)
	_apply_language()
	_menu_overlay.hide()


func _create_game_panels() -> void:
	var history_panel := PanelContainer.new()
	history_panel.position = Vector2(24, 140)
	history_panel.size = Vector2(235, 300)
	$UI.add_child(history_panel)
	_history_label = RichTextLabel.new()
	_history_label.bbcode_enabled = true
	_history_label.fit_content = false
	_history_label.scroll_following = true
	_history_label.add_theme_font_size_override("normal_font_size", 16)
	history_panel.add_child(_history_label)
	_update_move_history()

	_captured_label = Label.new()
	_captured_label.position = Vector2(24, 452)
	_captured_label.size = Vector2(280, 86)
	_captured_label.add_theme_font_size_override("font_size", 17)
	$UI.add_child(_captured_label)
	_update_captured_pieces()

	var resign_button := Button.new()
	resign_button.text = "RESIGN"
	resign_button.position = Vector2(24, 548)
	resign_button.size = Vector2(120, 44)
	resign_button.pressed.connect(_request_resign)
	$UI.add_child(resign_button)

	_game_over_dialog = AcceptDialog.new()
	_game_over_dialog.title = "GAME OVER"
	_game_over_dialog.min_size = Vector2i(460, 240)
	_game_over_dialog.confirmed.connect(_show_main_menu)
	$UI.add_child(_game_over_dialog)

	_resign_dialog = ConfirmationDialog.new()
	_resign_dialog.title = "RESIGN GAME"
	_resign_dialog.dialog_text = "Are you sure you want to resign?"
	_resign_dialog.min_size = Vector2i(440, 210)
	_resign_dialog.confirmed.connect(_confirm_resign)
	$UI.add_child(_resign_dialog)
	_apply_language()


func _menu_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 62)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	return button


func _text(key: String) -> String:
	var fa := {
		"continue": "ادامه بازی", "new_ai": "بازی جدید با هوش مصنوعی", "local": "بازی دونفره محلی",
		"close": "بستن منو", "white": "سفید", "black": "سیاه", "play_as": "بازی با مهره‌های: ",
		"level": "سطح هوش مصنوعی: ", "easy": "آسان", "medium": "متوسط", "hard": "سخت",
		"white_turn": "نوبت سفید", "black_turn": "نوبت سیاه", "check": " — کیش", "thinking": "هوش مصنوعی در حال فکر کردن...",
		"moves": "حرکت‌ها", "white_captured": "گرفته‌های سفید: ", "black_captured": "گرفته‌های سیاه: ",
		"language": "زبان: فارسی", "game_over": "پایان بازی", "resign_confirm": "آیا مطمئن هستید که می‌خواهید تسلیم شوید؟"
	}
	var en := {
		"continue": "CONTINUE GAME", "new_ai": "NEW GAME VS AI", "local": "LOCAL TWO PLAYERS",
		"close": "CLOSE MENU", "white": "WHITE", "black": "BLACK", "play_as": "PLAY AS: ",
		"level": "AI LEVEL: ", "easy": "EASY", "medium": "MEDIUM", "hard": "HARD",
		"white_turn": "White to move", "black_turn": "Black to move", "check": " — CHECK", "thinking": "Computer thinking...",
		"moves": "MOVES", "white_captured": "White captured: ", "black_captured": "Black captured: ",
		"language": "LANGUAGE: ENGLISH", "game_over": "GAME OVER", "resign_confirm": "Are you sure you want to resign?"
	}
	return fa.get(key, key) if language == "fa" else en.get(key, key)


func _cycle_language() -> void:
	language = "fa" if language == "en" else "en"
	_apply_language()
	_save_autosave()


func _apply_language() -> void:
	if is_instance_valid(_menu_overlay):
		_menu_overlay.layout_direction = Control.LAYOUT_DIRECTION_RTL if language == "fa" else Control.LAYOUT_DIRECTION_LTR
	if is_instance_valid(_language_button): _language_button.text = _text("language")
	if is_instance_valid(_continue_button): _continue_button.text = _text("continue")
	if is_instance_valid(_ai_start_button): _ai_start_button.text = _text("new_ai")
	if is_instance_valid(_local_start_button): _local_start_button.text = _text("local")
	if is_instance_valid(_close_menu_button): _close_menu_button.text = _text("close")
	if is_instance_valid(_color_button): _color_button.text = _text("play_as") + _text("white" if human_color == ChessRules.WHITE else "black")
	if is_instance_valid(_difficulty_button): _difficulty_button.text = _text("level") + _text(ai_difficulty)
	if is_instance_valid(_game_over_dialog): _game_over_dialog.title = _text("game_over")
	if is_instance_valid(_resign_dialog): _resign_dialog.dialog_text = _text("resign_confirm")
	_update_status()
	_update_move_history()
	_update_captured_pieces()


func _cycle_player_color() -> void:
	human_color = ChessRules.BLACK if human_color == ChessRules.WHITE else ChessRules.WHITE
	_color_button.text = _text("play_as") + _text("white" if human_color == ChessRules.WHITE else "black")


func _cycle_ai_difficulty() -> void:
	var levels := ["easy", "medium", "hard"]
	ai_difficulty = levels[(levels.find(ai_difficulty) + 1) % levels.size()]
	_difficulty_button.text = _text("level") + _text(ai_difficulty)


func _update_move_history() -> void:
	if not is_instance_valid(_history_label):
		return
	var text := "[color=#d8bd82][font_size=20]%s[/font_size][/color]\n\n" % _text("moves")
	for index in game.move_notation.size():
		if index % 2 == 0:
			text += "%d. " % (index / 2 + 1)
		text += game.move_notation[index] + ("\n" if index % 2 == 1 else "    ")
	_history_label.text = text
	_history_label.scroll_to_line(maxi(0, game.move_notation.size() / 2 - 1))


func _update_captured_pieces() -> void:
	if not is_instance_valid(_captured_label):
		return
	var symbols := {"p": "♟", "n": "♞", "b": "♝", "r": "♜", "q": "♛", "P": "♙", "N": "♘", "B": "♗", "R": "♖", "Q": "♕"}
	var white_captures := ""
	var black_captures := ""
	for piece in game.captured_by_white:
		white_captures += symbols.get(piece, piece) + " "
	for piece in game.captured_by_black:
		black_captures += symbols.get(piece, piece) + " "
	_captured_label.text = _text("white_captured") + (white_captures if white_captures != "" else "—") + "\n" + _text("black_captured") + (black_captures if black_captures != "" else "—")
	_captured_label.layout_direction = Control.LAYOUT_DIRECTION_RTL if language == "fa" else Control.LAYOUT_DIRECTION_LTR


func _request_resign() -> void:
	if game.result == "" and not ai_thinking and not animating_move:
		_resign_dialog.popup_centered()


func _confirm_resign() -> void:
	var resigning_color := human_color if play_vs_ai else game.turn
	game.result = "Black wins by resignation" if resigning_color == ChessRules.WHITE else "White wins by resignation"
	_update_status()
	_save_autosave()
	_show_game_over_if_needed()


func _show_game_over_if_needed() -> void:
	if game.result == "" or not is_instance_valid(_game_over_dialog):
		return
	_game_over_dialog.dialog_text = _translate_result(game.result) + ("\n\nبازی به‌صورت خودکار ذخیره شد." if language == "fa" else "\n\nThe game was saved automatically.")
	_game_over_dialog.popup_centered()
	_haptic(80)


func _show_main_menu() -> void:
	if not is_instance_valid(_menu_overlay):
		return
	_continue_button.disabled = not _has_resumable_game and game.move_notation.is_empty()
	_menu_overlay.show()
	get_tree().paused = true
	_menu_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _continue_game() -> void:
	_menu_overlay.hide()
	get_tree().paused = false


func _start_ai_game() -> void:
	play_vs_ai = true
	_mode_button.text = "VS AI"
	_new_game()
	camera_rig.rotation.y = 0.0 if human_color == ChessRules.WHITE else PI
	_has_resumable_game = true
	_continue_game()
	if game.turn != human_color:
		ai_thinking = true
		_update_status()
		get_tree().create_timer(0.35).timeout.connect(_play_ai_move)


func _start_local_game() -> void:
	play_vs_ai = false
	_mode_button.text = "LOCAL"
	_new_game()
	_has_resumable_game = true
	_continue_game()


func _select_square(square: Vector2i) -> void:
	if ai_thinking or animating_move or game.result != "":
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
	last_move = move.duplicate(true)
	_haptic(35 if move.captured != "" else 22)
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_animate_board_move(move, _finish_player_move)


func _finish_player_move() -> void:
	animating_move = false
	_create_pieces()
	_draw_highlights()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_show_game_over_if_needed()
	_save_autosave()
	if play_vs_ai and game.turn != human_color and game.result == "":
		ai_thinking = true
		_update_status()
		get_tree().create_timer(0.45).timeout.connect(_play_ai_move)
	elif not play_vs_ai and game.result == "":
		_flip_camera_for_local_turn()


func _play_ai_move() -> void:
	if game.result != "" or game.turn == human_color:
		ai_thinking = false
		_update_status()
		return
	ai_generation += 1
	var request_generation := ai_generation
	var fen := game.to_fen()
	var difficulty := ai_difficulty
	WorkerThreadPool.add_task(func() -> void:
		var chosen := OfflineAI.choose_move(fen, difficulty)
		call_deferred("_apply_ai_choice", chosen, request_generation)
	)


func _apply_ai_choice(chosen: Dictionary, request_generation: int) -> void:
	if request_generation != ai_generation or not ai_thinking:
		return
	if chosen.is_empty() or not game.play(chosen):
		ai_thinking = false
		_update_status()
		return
	last_move = chosen.duplicate(true)
	_animate_board_move(chosen, _finish_ai_move)


func _finish_ai_move() -> void:
	animating_move = false
	ai_thinking = false
	_create_pieces()
	_draw_highlights()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_show_game_over_if_needed()
	_save_autosave()


func _animate_board_move(move: Dictionary, finished: Callable) -> void:
	animating_move = true
	var moving_piece: Node3D
	var captured_piece: Node3D
	var captured_square: Vector2i = move.to
	if move.get("en_passant", false):
		captured_square = Vector2i(move.to.x, move.from.y)
	for piece in pieces_root.get_children():
		var square: Vector2i = piece.get_meta("square", Vector2i(-1, -1))
		if square == move.from:
			moving_piece = piece
		elif square == captured_square:
			captured_piece = piece
	if not is_instance_valid(moving_piece):
		finished.call()
		return
	var target := Vector3((move.to.x - 3.5) * SQUARE_SIZE, 0.12, (move.to.y - 3.5) * SQUARE_SIZE)
	var midpoint := (moving_piece.position + target) * 0.5
	midpoint.y = 0.75
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(moving_piece, "position", midpoint, 0.13)
	tween.tween_property(moving_piece, "position", target, 0.15)
	if is_instance_valid(captured_piece):
		_spawn_capture_effect(captured_piece.position, move.captured)
		var capture_tween := create_tween().set_parallel(true)
		capture_tween.tween_property(captured_piece, "scale", Vector3.ZERO, 0.2)
		capture_tween.tween_property(captured_piece, "position:y", -0.25, 0.2)
	tween.finished.connect(finished)


func _spawn_capture_effect(position: Vector3, captured_code: String) -> void:
	if not capture_effects_enabled:
		return
	var particles := CPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.16
	particles.direction = Vector3(0, 1, 0)
	particles.spread = 70.0
	particles.initial_velocity_min = 1.0
	particles.initial_velocity_max = 2.2
	particles.gravity = Vector3(0, -4.2, 0)
	particles.scale_amount_min = 0.45
	particles.scale_amount_max = 1.0
	var spark := SphereMesh.new()
	spark.radius = 0.035
	spark.height = 0.07
	spark.radial_segments = 8
	spark.rings = 4
	var spark_material := StandardMaterial3D.new()
	var spark_color := Color("d6bd82") if captured_code == captured_code.to_upper() else Color("b72a55")
	spark_material.albedo_color = spark_color
	spark_material.emission_enabled = true
	spark_material.emission = spark_color
	spark_material.emission_energy_multiplier = 1.8
	spark.material = spark_material
	particles.mesh = spark
	particles.position = position + Vector3(0, 0.45, 0)
	board.add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.0).timeout.connect(particles.queue_free)


func _draw_highlights() -> void:
	for child in highlights_root.get_children():
		child.queue_free()
	if not last_move.is_empty():
		_add_highlight(last_move.from, Color(0.22, 0.52, 0.9, 0.32), 0.44)
		_add_highlight(last_move.to, Color(0.22, 0.52, 0.9, 0.48), 0.44)
	if game.result == "" and game.is_in_check(game.turn):
		var king_code := "K" if game.turn == ChessRules.WHITE else "k"
		for rank in BOARD_SIZE:
			for file in BOARD_SIZE:
				if game.board[rank][file] == king_code:
					_add_highlight(Vector2i(file, rank), Color(0.95, 0.1, 0.12, 0.72), 0.46)
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


func _translate_result(value: String) -> String:
	if language != "fa": return value
	var replacements := {
		"White wins by checkmate": "سفید با کیش‌مات برنده شد", "Black wins by checkmate": "سیاه با کیش‌مات برنده شد",
		"White wins on time": "سفید با پایان زمان حریف برنده شد", "Black wins on time": "سیاه با پایان زمان حریف برنده شد",
		"White wins by resignation": "سفید با تسلیم حریف برنده شد", "Black wins by resignation": "سیاه با تسلیم حریف برنده شد",
		"Draw by stalemate": "مساوی با پات", "Draw by threefold repetition": "مساوی با تکرار سه‌باره",
		"Draw by fifty-move rule": "مساوی با قانون پنجاه حرکت", "Draw by insufficient material": "مساوی به‌دلیل کمبود مهره"
	}
	return replacements.get(value, value)


func _update_status() -> void:
	if game.result != "":
		_status_label.text = _translate_result(game.result)
	elif ai_thinking:
		_status_label.text = _text("thinking")
	else:
		_status_label.text = _text("white_turn" if game.turn == ChessRules.WHITE else "black_turn") + (_text("check") if game.is_in_check(game.turn) else "")
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


func _effective_graphics_quality() -> String:
	if graphics_quality != "auto":
		return graphics_quality
	var cores := OS.get_processor_count()
	if cores <= 4:
		return "low"
	elif cores <= 6:
		return "medium"
	return "high"


func _apply_graphics_quality() -> void:
	var quality := _effective_graphics_quality()
	capture_effects_enabled = quality != "low"
	decor_root.visible = quality != "low"
	$KeyLight.shadow_enabled = quality != "low"
	$FillLight.shadow_enabled = quality == "high"
	match quality:
		"high":
			get_viewport().msaa_3d = Viewport.MSAA_2X
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"medium":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_update_graphics_button()


func _cycle_graphics_quality() -> void:
	var levels := ["auto", "low", "medium", "high"]
	var index := levels.find(graphics_quality)
	graphics_quality = levels[(index + 1) % levels.size()]
	_apply_graphics_quality()
	_save_autosave()


func _update_graphics_button() -> void:
	if is_instance_valid(_graphics_button):
		_graphics_button.text = "GFX: " + graphics_quality.to_upper()


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
	_top_panel.offset_left = -1060.0 - right_inset
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
		"graphics_quality": graphics_quality,
		"camera_yaw": camera_rig.rotation.y,
		"camera_distance": camera.position.length(),
		"play_vs_ai": play_vs_ai,
		"human_color": human_color,
		"ai_difficulty": ai_difficulty,
		"language": language,
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
	graphics_quality = parsed.get("graphics_quality", "auto")
	if graphics_quality not in ["auto", "low", "medium", "high"]:
		graphics_quality = "auto"
	camera_rig.rotation.y = float(parsed.get("camera_yaw", 0.0))
	_set_camera_distance(float(parsed.get("camera_distance", camera.position.length())))
	play_vs_ai = bool(parsed.get("play_vs_ai", true))
	human_color = int(parsed.get("human_color", ChessRules.WHITE))
	ai_difficulty = parsed.get("ai_difficulty", "medium")
	if ai_difficulty not in ["easy", "medium", "hard"]:
		ai_difficulty = "medium"
	language = parsed.get("language", "en")
	if language not in ["en", "fa"]: language = "en"
	game.result = parsed.get("result", game.result)
	return true


func _undo() -> void:
	if ai_thinking or animating_move:
		return
	last_move.clear()
	if game.undo() and play_vs_ai and game.turn != human_color:
		game.undo()
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_save_autosave()


func _new_game() -> void:
	game.reset()
	last_move.clear()
	camera_rig.rotation.y = 0.0
	white_time = 600.0
	black_time = 600.0
	ai_generation += 1
	ai_thinking = false
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_save_autosave()


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.clearcoat_enabled = true
	material.clearcoat_roughness = minf(0.65, roughness + 0.12)
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
