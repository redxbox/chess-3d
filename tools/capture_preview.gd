extends SceneTree

var output_path := "res://build/preview/theme-preview.png"


func _initialize() -> void:
	# CI chooses board and pieces independently, exactly like the setup menu.
	var piece_theme := OS.get_environment("CHESS_PIECE_THEME")
	var board_theme := OS.get_environment("CHESS_BOARD_THEME")
	if piece_theme == "": piece_theme = "persian"
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
	# One capture mode renders the style screen itself rather than the board, so
	# the picker can be reviewed from CI instead of only on a device. It is taken
	# before the menu comes down, because that is the screen the player sees when
	# they tap the style button.
	var show_picker := OS.get_environment("CHESS_PREVIEW_PICKER") == "1"
	if show_picker:
		if is_instance_valid(menu_overlay):
			menu_overlay.hide()
		if main.has_method("_open_theme_picker"):
			main.call("_open_theme_picker")
	elif is_instance_valid(menu_overlay):
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

	# One capture mode stands four units from the near army instead of thirteen.
	#
	# This exists because the board render cannot answer the question it is
	# published for. At 1536x864 a figure is about sixty pixels tall, so a crown,
	# a spearhead, a griffin's beak and a robe fold are three or four pixels each
	# - which is enough to see that *something* is there and not enough to tell
	# whether it reads as what it is. Every judgement about the figurative set's
	# carving was being made on that, so the close-up is rendered by CI next to
	# the board rather than being taken on trust.
	#
	# After the settle loop, because the rig writes the camera in
	# _apply_camera_rig() and would overwrite anything set before it.
	if OS.get_environment("CHESS_PREVIEW_DETAIL") == "1":
		var camera := main.get("camera") as Camera3D
		if is_instance_valid(camera):
			# Global rather than local: the camera hangs off a rig node that the
			# scene rotates to face the near army, and a local transform typed
			# here would depend on that rotation.
			camera.fov = 26.0
			# The white army stands on the +z half of the board, so the camera
			# stands off that side and looks back at its back rank; the first
			# attempt was written from memory of the board render, where the pale
			# army is at the bottom of the frame, and came back a portrait of the
			# far army's backs.
			camera.global_position = Vector3(0.62, 3.00, 7.40)
			camera.look_at(Vector3(0.00, 0.60, 3.30), Vector3.UP)
			# The HUD is not part of what the close-up is for, and the moves panel
			# sits over the pieces at this distance.
			var hud := main.get_node_or_null("UI") as CanvasItem
			if is_instance_valid(hud):
				hud.hide()
			for frame in 4:
				await process_frame

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
