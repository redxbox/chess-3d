extends Node3D

# The unused Persian model set was deleted from the repository (it shipped in
# the APK without being referenced by the game). This preview script uses the
# shipped Staunton body instead, which is what the game actually renders.
const PAWN_MODEL := preload("res://assets/models/staunton/pawn.obj")


func _ready() -> void:
	_add_test_pawn(Vector3(-0.65, 0.0, 0.0), true)
	_add_test_pawn(Vector3(0.65, 0.0, 0.0), false)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.4
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4a3525")
	sky_material.sky_horizon_color = Color("a67c52")
	sky_material.ground_bottom_color = Color("1a110a")
	sky_material.ground_horizon_color = Color("593e25")
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.sky_material = sky_material
	environment.sky = sky
	$WorldEnvironment.environment = environment


func _add_test_pawn(position_value: Vector3, is_white: bool) -> void:
	var pawn := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = PAWN_MODEL
	pawn.add_child(body)
	pawn.position = position_value
	pawn.position.y = 0.5
	ChessMaterials.apply_to_tree(pawn, is_white)
	add_child(pawn)
