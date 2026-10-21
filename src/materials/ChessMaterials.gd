class_name ChessMaterials
extends RefCounted

## Cached, texture-free mobile materials for geometry-only chess GLBs.
## Imported image-to-3D models may expose one or two surfaces. Surface 0 always
## receives the army body; surface 1 receives shared polished gold when present.

static var _white_body: StandardMaterial3D
static var _black_body: StandardMaterial3D
static var _gold_trim: StandardMaterial3D


static func white_body() -> StandardMaterial3D:
	if not is_instance_valid(_white_body):
		_white_body = StandardMaterial3D.new()
		_white_body.resource_name = "Glossy Ivory Marble"
		_white_body.albedo_color = Color(0.96, 0.93, 0.86)
		_white_body.metallic = 0.0
		_white_body.metallic_specular = 0.72
		_white_body.roughness = 0.15
		# Cheap translucent-depth approximation supported by StandardMaterial3D.
		_white_body.subsurf_scatter_enabled = true
		_white_body.subsurf_scatter_strength = 0.10
	return _white_body


static func black_body() -> StandardMaterial3D:
	if not is_instance_valid(_black_body):
		_black_body = StandardMaterial3D.new()
		_black_body.resource_name = "Glossy Black Marble"
		_black_body.albedo_color = Color(0.08, 0.07, 0.09)
		_black_body.metallic = 0.10
		_black_body.metallic_specular = 0.64
		_black_body.roughness = 0.20
	return _black_body


static func gold_trim() -> StandardMaterial3D:
	if not is_instance_valid(_gold_trim):
		_gold_trim = StandardMaterial3D.new()
		_gold_trim.resource_name = "Polished Gold Trim"
		_gold_trim.albedo_color = Color(0.85, 0.65, 0.13)
		_gold_trim.metallic = 1.0
		_gold_trim.metallic_specular = 0.50
		_gold_trim.roughness = 0.25
	return _gold_trim


static func body_for_side(is_white: bool) -> StandardMaterial3D:
	return white_body() if is_white else black_body()


static func apply_to_tree(root: Node, is_white: bool, cast_shadow := true) -> void:
	var body := body_for_side(is_white)
	var trim := gold_trim()
	_apply_recursive(root, body, trim, cast_shadow)


static func _apply_recursive(node: Node, body: Material, trim: Material, cast_shadow: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = null
		if is_instance_valid(mesh_instance.mesh):
			var surface_count := mesh_instance.mesh.get_surface_count()
			if surface_count > 0:
				mesh_instance.set_surface_override_material(0, body)
			if surface_count > 1:
				mesh_instance.set_surface_override_material(1, trim)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
	for child in node.get_children():
		_apply_recursive(child, body, trim, cast_shadow)
