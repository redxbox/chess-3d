extends SceneTree

var output_path := "res://build/preview/theme-preview.png"


func _initialize() -> void:
	# CI chooses board and pieces independently, exactly like the setup menu.
	var piece_theme := OS.get_environment("CHESS_PIECE_THEME")
	var board_theme := OS.get_environment("CHESS_BOARD_THEME")
	if piece_theme == "": piece_theme = "royal_wood"
	if board_theme == "": board_theme = "classic"
	var output_name := OS.get_environment("CHESS_PREVIEW_NAME")
	if output_name == "": output_name = "%s-%s.png" % [board_theme, piece_theme]
	output_path = "res://build/preview/" + output_name
	for preference in [["user://piece_theme.txt", piece_theme], ["user://board_theme.txt", board_theme]]:
		var theme_file := FileAccess.open(preference[0], FileAccess.WRITE)
		if theme_file == null:
			push_error("Could not prepare theme preference: " + preference[0])
			quit(1)
			return
		theme_file.store_string(preference[1])
		theme_file.close()

	var packed_scene := load("res://src/main/main.tscn") as PackedScene
	if packed_scene == null:
		push_error("Could not load the startup scene")
		quit(1)
		return
	root.add_child(packed_scene.instantiate())
	capture_when_ready.call_deferred()


func capture_when_ready() -> void:
	# Main intentionally opens its setup menu at startup. Hide it only in this
	# capture harness so the automated image shows the board and materials.
	#
	# Fifteen frames rather than two before the menu comes down: the theme is
	# read from disk and the procedural maps, meshes and materials are all built
	# on the first frames after that, and two frames was not enough for any of
	# it to have happened.
	for frame in 15:
		await process_frame
	var main := root.get_child(0)
	var menu_overlay := main.get("_menu_overlay") as ColorRect
	if is_instance_valid(menu_overlay):
		menu_overlay.hide()
	# The FPS readout is hidden too. The CI runner has no GPU, so its first
	# frames land roughly a second apart and the counter settles on "1 FPS",
	# which then became the number visible in every published preview. On a real
	# device the label still works exactly as before.
	var fps_label := main.get_node_or_null("UI/PerformanceReadout") as Label
	if is_instance_valid(fps_label):
		fps_label.hide()
	# Pin the graphics preset rather than leaving it on AUTO. AUTO decides from
	# the processor count and then re-decides from the measured frame rate, and
	# on a software renderer the first frames land about a second apart while the
	# later ones do not, so whether the quality step-down had happened by the
	# time of the capture depended on how long startup took. That made the
	# published renders non-deterministic: the same commit could come back with
	# the fill light's shadows on or off, and that single bit moves the pale
	# squares from #fdf6e1 to #fffffe. HIGH is the state the accepted renders
	# were captured in, and it is also what an eight-core phone picks on its own,
	# so pinning it here keeps CI and the device saying the same thing.
	main.set("graphics_quality", "high")
	if main.has_method("_apply_graphics_quality"):
		main.call("_apply_graphics_quality")
	paused = false

	# Allow procedural sky radiance, shaders, and UI layout to settle.
	for frame in 30:
		await process_frame
	await create_timer(2.0).timeout

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/preview"))
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Godot returned an empty preview image")
		quit(1)
		return
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not save preview PNG: %s" % error_string(error))
		quit(1)
		return
	print("Saved real Godot preview to ", output_path)
	quit()
