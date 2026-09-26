extends Node3D
## Temporary visual foundation for the Android-first 3D chess board.
## All geometry is generated at runtime, so the project is immediately runnable.

const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0

@onready var board: Node3D = $Board
@onready var camera_rig: Node3D = $CameraRig

var _dragging := false
var _last_pointer := Vector2.ZERO


func _ready() -> void:
	_setup_environment()
	_create_board()


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


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_dragging = event.pressed
		_last_pointer = event.position
	elif event is InputEventScreenDrag:
		_rotate_camera(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_last_pointer = event.position
	elif event is InputEventMouseMotion and _dragging:
		_rotate_camera(event.relative)


func _rotate_camera(relative: Vector2) -> void:
	camera_rig.rotate_y(-relative.x * 0.006)
