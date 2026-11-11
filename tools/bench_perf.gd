extends SceneTree

## A reproducible frame-time and load-time benchmark, for CI.
##
## There is no phone in the build pipeline, so this cannot report the number the
## player sees. What it can report is whether a change made things better or
## worse in a way that is comparable run to run, because the software renderer
## and the machine are the same every time:
##
##   load_ready_ms      - how long the scene takes to become interactive,
##                        which is the mesh build plus the first board;
##   mesh_cold_ms       - building one set's six bodies from the OBJ files, with
##                        the cavity bake - the hitch behind "the menus stutter"
##                        when a new style is applied;
##   mesh_warm_ms       - the same six bodies read back from the disk cache;
##   frames_avg_ms      - the mean frame time over 120 rendered frames at
##                        1536x864 on llvmpipe, with the board on screen;
##   draw_calls,
##   triangles          - what the frame actually costs the GPU;
##   shadow_casters     - how many lights still cast, which is the one number
##                        that used to be two.
##
## Every figure is printed as `BENCH <name> <value>` so the CI step can grep them
## out and compare a run with the previous one.

const RUN_FRAMES := 120

var _main: Node
var _results: Dictionary = {}


func _initialize() -> void:
	# The cold measurement has to happen before the first launch reads the cache,
	# so the cache is cleared at the start of every benchmark run.
	var cache: GDScript = load("res://src/main/mesh_cache.gd")
	cache.clear()

	var started := Time.get_ticks_msec()
	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("Could not load the startup scene")
		quit(1)
		return
	_main = packed_scene.instantiate()
	root.add_child(_main)
	_measure.call_deferred(started)


func _measure(scene_started: int) -> void:
	for frame in 15:
		await process_frame
	_results["load_ready_ms"] = Time.get_ticks_msec() - scene_started

	var menu_overlay := _main.get("_menu_overlay") as ColorRect
	if is_instance_valid(menu_overlay):
		menu_overlay.hide()
	_main.set("graphics_quality", "high")
	if _main.has_method("_apply_graphics_quality"):
		_main.call("_apply_graphics_quality")
	paused = false
	for frame in 20:
		await process_frame

	# --- what the frame costs ----------------------------------------------
	var shadow_casters := 0
	for light in _main.find_children("*", "DirectionalLight3D", true, false):
		if (light as DirectionalLight3D).shadow_enabled:
			shadow_casters += 1
	_results["shadow_casters"] = shadow_casters
	_results["draw_calls"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	_results["triangles"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	_results["objects"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)

	# --- frame time ---------------------------------------------------------
	# Measured with the frame-time counter rather than by wall clock per frame:
	# the tree pauses between the frames of this loop, and a stopped clock would
	# report the loop, not the renderer.
	var total_ms := 0.0
	var samples := 0
	for frame in RUN_FRAMES:
		await process_frame
		var frame_ms: float = root.get_process_delta_time() * 1000.0
		if frame >= 20:
			total_ms += frame_ms
			samples += 1
	_results["frames_avg_ms"] = snappedf(total_ms / float(maxi(1, samples)), 0.01)
	_results["fps_equivalent"] = snappedf(1000.0 / maxf(0.01, float(_results["frames_avg_ms"])), 0.1)

	# --- mesh build cost ----------------------------------------------------
	# One set, cleared from memory and from disk, then the same set read back.
	var MeshCache: GDScript = load("res://src/main/mesh_cache.gd")
	var set_id := String(_main.get("piece_theme"))
	_main.set("piece_theme", set_id)
	var cache_backup: Dictionary = _main.get("_mesh_cache")

	MeshCache.clear()
	cache_backup.clear()
	var cold_started := Time.get_ticks_msec()
	for kind in ["pawn", "rook", "knight", "bishop", "queen", "king"]:
		_main.call("_piece_mesh", kind)
	_results["mesh_cold_ms"] = Time.get_ticks_msec() - cold_started

	cache_backup.clear()
	var warm_started := Time.get_ticks_msec()
	for kind in ["pawn", "rook", "knight", "bishop", "queen", "king"]:
		_main.call("_piece_mesh", kind)
	_results["mesh_warm_ms"] = Time.get_ticks_msec() - warm_started
	_results["mesh_cache_bytes"] = MeshCache.size_bytes()

	# --- the bake itself, against the implementation it replaced --------------
	var shading: GDScript = load("res://src/main/piece_shading.gd")
	var king_arrays: Array = _main.call("_piece_models")["king"].surface_get_arrays(0)
	var king_positions: PackedVector3Array = king_arrays[Mesh.ARRAY_VERTEX]
	var king_normals: PackedVector3Array = king_arrays[Mesh.ARRAY_NORMAL]
	var king_indices: PackedInt32Array = king_arrays[Mesh.ARRAY_INDEX] if king_arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	_results["king_vertices"] = king_positions.size()
	# The bake the figures are actually carved with: the two fields in one pass,
	# plus the second pass that turns faces into gilded triangles. The occlusion
	# alone is timed as well, because on the flat sets that is all that runs.
	var fast_started := Time.get_ticks_msec()
	shading.cavity_shade(king_positions, king_normals, king_indices)
	_results["bake_fast_ms"] = Time.get_ticks_msec() - fast_started

	var sculpt_started := Time.get_ticks_msec()
	var fields: Dictionary = shading.sculpt_fields(king_positions, king_normals, king_indices, 0.25, 1.0)
	var gild: PackedFloat32Array = fields["gild"]
	var gilded: PackedInt32Array = shading.gilded_indices(king_indices, gild, 0.55)
	_results["bake_sculpt_ms"] = Time.get_ticks_msec() - sculpt_started
	_results["gild_triangles"] = gilded.size() / 3

	for name in _results:
		print("BENCH %s %s" % [name, _results[name]])
	quit()
