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
	_create_pieces()


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
	var ivory := _material(Color("ead9b5"), 0.2, 0.35)
	var ruby := _material(Color("6f1832"), 0.18, 0.45)
	var back_rank := ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]

	for file in BOARD_SIZE:
		_add_piece(back_rank[file], file, 0, ruby)
		_add_piece("pawn", file, 1, ruby)
		_add_piece("pawn", file, 6, ivory)
		_add_piece(back_rank[file], file, 7, ivory)


func _add_piece(kind: String, file: int, rank: int, material: Material) -> void:
	var piece := Node3D.new()
	piece.name = "%s_%d_%d" % [kind.capitalize(), file, rank]
	piece.position = Vector3((file - 3.5) * SQUARE_SIZE, 0.12, (rank - 3.5) * SQUARE_SIZE)
	board.add_child(piece)

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
