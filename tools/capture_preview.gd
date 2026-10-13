extends SceneTree

const OUTPUT_PATH := "res://build/preview/persian-luxury-preview.png"


func _initialize() -> void:
	# CI starts with an empty user directory; select the Persian presentation
	# before Main._ready() reads the saved visual-theme preference.
	var theme_file := FileAccess.open("user://visual_theme.txt", FileAccess.WRITE)
	if theme_file == null:
		push_error("Could not prepare the Persian preview preference")
		quit(1)
		return
	theme_file.store_string("metal")
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
	for frame in 2:
		await process_frame
	var main := root.get_child(0)
	var menu_overlay := main.get("_menu_overlay") as ColorRect
	if is_instance_valid(menu_overlay):
		menu_overlay.hide()
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
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("Could not save preview PNG: %s" % error_string(error))
		quit(1)
		return
	print("Saved real Godot preview to ", OUTPUT_PATH)
	quit()
