extends Node3D
## Android-first 3D chess presentation and touch controller.

const ChessRules = preload("res://src/chess/chess_game.gd")
const OfflineAI = preload("res://src/ai/offline_ai.gd")
const ArchiveStore = preload("res://src/storage/game_archive.gd")
const AMBIENT_MUSIC = preload("res://assets/audio/ambient.wav")
const SOUND_STREAMS := {
	"select": preload("res://assets/audio/select.wav"),
	"move": preload("res://assets/audio/move.wav"),
	"capture": preload("res://assets/audio/capture.wav"),
	"check": preload("res://assets/audio/check.wav"),
	"castle": preload("res://assets/audio/castle.wav"),
	"game_over": preload("res://assets/audio/game_over.wav")
}
const PIECE_MODELS := {
	"pawn": preload("res://assets/models/staunton/pawn.obj"),
	"rook": preload("res://assets/models/staunton/rook.obj"),
	"knight": preload("res://assets/models/staunton/knight.obj"),
	"bishop": preload("res://assets/models/staunton/bishop.obj"),
	"queen": preload("res://assets/models/staunton/queen.obj"),
	"king": preload("res://assets/models/staunton/king.obj")
}
const BOARD_SIZE := 8
const SQUARE_SIZE := 1.0
## Single source of truth for the in-game version label. project.godot carries
## the same value in application/config/version, and export_presets.cfg carries
## the matching version/name, so the UI, the About window and the store build
## can never drift apart again.
const APP_VERSION_FALLBACK := "0.12.0"
const APP_BUILD := "22.50"
const PIECE_KINDS := {"p": "pawn", "r": "rook", "n": "knight", "b": "bishop", "q": "queen", "k": "king"}

@onready var board: Node3D = $Board
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D

var game := ChessRules.new()
var archive := ArchiveStore.new()
var pieces_root := Node3D.new()
var highlights_root := Node3D.new()
var decor_root := Node3D.new()
var coordinates_root := Node3D.new()
var _mesh_cache: Dictionary = {}
var _board_light_material: StandardMaterial3D
var _board_dark_material: StandardMaterial3D
var _piece_ivory_material: Material
var _piece_obsidian_material: Material
var _piece_gold_material: StandardMaterial3D
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
var _auto_quality_override := ""
var _low_fps_seconds := 0
var _fps_accumulator := 0.0
var _fps_label: Label
var capture_effects_enabled := true
var high_contrast_enabled := false
var reduced_motion_enabled := false
var coordinates_enabled := true
var colorblind_enabled := false
var large_text_enabled := false
var sound_enabled := true
var sound_volume := 0.75
var music_enabled := true
var music_volume := 0.28
var _sound_players: Dictionary = {}
var _music_player: AudioStreamPlayer
var _status_label: Label
var _graphics_button: Button
var _sound_button: Button
var _music_button: Button
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
var _archive_window: Window
var _archive_list: VBoxContainer
var _accessibility_window: Window
var _accessibility_buttons: Dictionary = {}
var _tutorial_window: Window
var _about_window: Window
var _ui_theme := Theme.new()
var _archived_current_game := false
var _has_resumable_game := false
var clock_enabled := true
var white_time := 600.0
var black_time := 600.0
var _autosave_accumulator := 0.0
const AUTOSAVE_PATH := "user://autosave.json"
const PIECE_THEME_PATH := "user://piece_theme.txt"
var piece_theme := "classic"
var _piece_theme_button: Button
## Guards the pending move animation so a scene rebuild can never leave
## animating_move stuck on true (which would freeze all board input).
var _move_tween: Tween
var _move_finished_callback: Callable
var _promotion_popup: PopupPanel
## Promotions change the piece kind, so the whole board is rebuilt for that move.
var _needs_full_piece_rebuild := false
## Left-hand HUD column, kept inset from notches and gesture bars.
var _left_column_nodes: Array[Control] = []
var _left_column_base: Dictionary = {}
var _app_version := APP_VERSION_FALLBACK


func _ready() -> void:
	# Seed the global RNG. Without this, every "random" AI choice and every
	# archive id is identical on each launch.
	randomize()
	var configured_version := str(ProjectSettings.get_setting("application/config/version", ""))
	_app_version = configured_version if configured_version != "" else APP_VERSION_FALLBACK
	_load_piece_theme()
	_setup_environment()
	_setup_piece_materials()
	decor_root.name = "EnvironmentDetails"
	coordinates_root.name = "BoardCoordinates"
	board.add_child(decor_root)
	board.add_child(coordinates_root)
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
	_create_audio()
	_apply_graphics_quality()
	_apply_accessibility()
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_status()
	_show_main_menu()


func _process(delta: float) -> void:
	_fps_accumulator += delta
	if _fps_accumulator >= 1.0:
		_fps_accumulator = 0.0
		_monitor_performance()
	var clock_expired := false
	if clock_enabled and game.result == "":
		if game.turn == ChessRules.WHITE:
			white_time = maxf(0.0, white_time - delta)
			if white_time <= 0.0:
				game.result = "Black wins on time"
		else:
			black_time = maxf(0.0, black_time - delta)
			if black_time <= 0.0:
				game.result = "White wins on time"
		clock_expired = game.result != ""
	if clock_expired:
		# Runs exactly once, on the frame the clock ran out.
		_update_status()
		_show_game_over_if_needed()
		_save_autosave()
	_update_clock_label()
	_autosave_accumulator += delta
	if _autosave_accumulator >= 5.0:
		_autosave_accumulator = 0.0
		_save_autosave()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_autosave()
		if is_instance_valid(_music_player): _music_player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if is_instance_valid(_music_player) and music_enabled: _music_player.stream_paused = false


func _setup_environment() -> void:
	# ACES + sRGB. Everything here is renderer level and is set exactly once, so
	# it applies to every GFX preset (AUTO / LOW / MEDIUM / HIGH) alike; the only
	# thing _apply_graphics_quality() varies per preset is shadow casting, MSAA
	# and screen-space AA, never the exposure or the tonemapper.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("3b2e42")
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Exposure is the master fader for the whole frame, and it is set against the
	# light rig below rather than in isolation. The brief's light energies plus
	# the pale Carrara and alabaster albedoes at exposure 0.80 pushed 85% of the
	# classic light squares past 1.0, and a clipped square is a flat white slab
	# with no veining and no shading left anywhere on it.
	environment.tonemap_exposure = 0.66
	var sky_material := ProceduralSkyMaterial.new()
	# A dark studio with a warm horizon. The horizon band is what the brass and
	# gold inlays reflect; with the old near-black sky every gold collar read as mud.
	sky_material.sky_top_color = Color("3d4550")
	sky_material.sky_horizon_color = Color("a0958a")
	sky_material.ground_bottom_color = Color("14100f")
	sky_material.ground_horizon_color = Color("4d4239")
	var studio_sky := Sky.new()
	studio_sky.radiance_size = Sky.RADIANCE_SIZE_64
	studio_sky.sky_material = sky_material
	environment.sky = studio_sky
	# Both the ambient term and the specular term come from the sky rather than
	# from a flat colour. A colour-driven ambient is what made the gold and the
	# polished wood read as dull plastic: there was nothing for them to reflect,
	# so the only highlights on a metallic surface were the three directional
	# lights. The sky gives every metal edge a real environment to mirror.
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	# Scales the sky-driven ambient. Directional lights are additive on top of
	# it, so the sum of key + fill + rim is what decides whether a pale surface
	# survives. The ambient is raised rather than cut whenever the frame is
	# brought down, because it is the only term that reaches the surfaces the
	# key light cannot see: at 0.35 every table step sitting in the board's own
	# shadow collapsed to pure black, which is exactly the void the brief wants
	# gone.
	environment.ambient_light_energy = 0.45
	# A three-point studio rig, so both sets read as solid volume at once. The
	# old single key light left the camera-facing side of every dark piece in
	# its own shadow, which is why the black set used to collapse into
	# silhouettes while the white set went chalky.
	#
	# Key: front-left and above, warm, and the only light that casts.
	#
	# 0.78 was calibrated against the old piece silhouettes. The turned stems, the
	# sculpted knight head and the slimmer pawn all cast less shadow than what
	# they replaced, and with the fill's grazing shadows doing less work the pale
	# squares sat the rest of the way into the clip and came back as flat #ffffff
	# with no shading left on them. 0.73 puts them back just under.
	$KeyLight.light_energy = 0.73
	$KeyLight.light_color = Color(1.0, 0.96, 0.90)
	$KeyLight.rotation_degrees = Vector3(-48, -32, 0)
	# Contact-tight shadows. The normal bias is deliberately small: a large one
	# displaces the shadow lookup a long way along the surface normal, and a
	# flat face can end up sampling the wrong part of the shadow map and drop
	# into shadow for no visible reason.
	$KeyLight.shadow_enabled = true
	$KeyLight.shadow_bias = 0.01
	$KeyLight.shadow_normal_bias = 0.25
	$KeyLight.shadow_blur = 1.2
	# Fill: soft, front-right and low, no shadow. This is what actually lights
	# the side of a piece the camera can see.
	$FillLight.light_energy = 0.28
	$FillLight.light_color = Color(0.88, 0.91, 0.98)
	$FillLight.rotation_degrees = Vector3(-60, 45, 0)
	$FillLight.shadow_enabled = false
	# Rim: behind rank 8, grazing, and bright enough to sculpt. It skims the
	# crown, neck and shoulders of a dark body and leaves a specular edge along
	# its silhouette, so an obsidian piece reads as an object instead of a hole
	# in the picture.
	$RimLight.rotation_degrees = Vector3(-35, 160, 0)
	$RimLight.light_color = Color(0.90, 0.93, 1.0)
	$RimLight.light_energy = 0.50
	$RimLight.shadow_enabled = false
	# Bloom is off. With it on, the Compatibility renderer lifted the whole
	# frame: the background went from the intended #2a1f2e to a flat #be82c6 and
	# the pale squares lost every bit of contrast. The gold inlays read fine on
	# specular alone, and nothing here glows.
	environment.glow_enabled = false
	# SSAO, SSR and depth of field are Forward+ / Mobile features; in Godot 4 depth
	# of field is not an Environment property at all but a CameraAttributesPractical
	# on the camera. Guarding on the renderer keeps startup clean and leaves the
	# settings in place for the day the project moves off Compatibility.
	if str(ProjectSettings.get_setting("rendering/renderer/rendering_method")) != "gl_compatibility":
		environment.ssao_enabled = true
		environment.ssao_radius = 0.85
		environment.ssao_intensity = 1.5
		environment.ssao_power = 1.6
		environment.ssr_enabled = true
		environment.ssr_max_steps = 24
		var camera_attributes := CameraAttributesPractical.new()
		camera_attributes.dof_blur_far_enabled = true
		camera_attributes.dof_blur_far_distance = 13.0
		camera_attributes.dof_blur_far_transition = 5.0
		camera_attributes.dof_blur_amount = 0.10
		camera.attributes = camera_attributes
	$WorldEnvironment.environment = environment


## ---------------------------------------------------------------------------
## Procedural surface maps
##
## Every board and piece material is driven by textures generated once at
## startup into the shared mesh cache. Generating them keeps the APK free of
## binary texture assets while still giving marble veining, wood grain and a
## matching normal map, which is what makes the surfaces read as material
## rather than flat colour under the key light.
## ---------------------------------------------------------------------------

var _surface_maps: Dictionary = {}


func _surface_map(kind: String) -> Texture2D:
	if _surface_maps.has(kind):
		return _surface_maps[kind]
	var texture: Texture2D = null
	match kind:
		"marble": texture = _marble_map()
		"marble_normal": texture = _normal_map(_marble_height())
		"walnut": texture = _walnut_map()
		"walnut_normal": texture = _normal_map(_walnut_height())
		"rosewood": texture = _rosewood_map()
		"rosewood_normal": texture = _normal_map(_rosewood_height())
	_surface_maps[kind] = texture
	return texture


func _map_size() -> int:
	return 64 if _effective_graphics_quality() == "low" else 128


## One shared FBM noise field per surface. TYPE_SIMPLEX_SMOOTH with
## FRACTAL_FBM gives organic blotching; the old generators drove `abs(sin(x + y))`,
## whose zero crossings land on parallel 45-degree lines and read as striped
## fabric rather than as stone or wood. Two decorrelated fields are blended, one
## broad and one fine, so no direction is favoured and the diagonal repeat is
## gone. The amplitude is deliberately tiny - the shade band is only 6% wide - so
## the squares stay smooth and polished with a hint of figure rather than a
## pattern. The albedo map and the height map are built from the same seeded
## field, so the veining and the bump it produces always agree.
func _surface_noise(seed_value: int, frequency: float, octaves: int = 2) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.frequency = frequency
	return noise


## The two decorrelated fields for one surface: a broad one and a fine one. They
## are built once per map rather than once per pixel, because a FastNoiseLite is
## not free to allocate and these maps are 128x128.
##
## The frequencies are in "features across the texture", because the maps are
## sampled on a 0..1 grid and FastNoiseLite's own frequency multiplies that grid.
## Four octaves were tried first and rejected: each octave doubles the frequency,
## so the top one landed under four texels and every square on the far side of
## the board - which is where a tile is only nine pixels wide on screen - sampled
## it one texel to one pixel. That is exactly the banding the brief asks to have
## gone. Two octaves keeps the finest detail near thirty texels, where the
## mip chain the materials filter with has something to fall back on, and the
## shade band is held to four percent so the squares stay smooth and polished
## with a hint of figure rather than a pattern.
func _surface_fields(seed_value: int, fine_seed: int) -> Array:
	return [_surface_noise(seed_value, 0.8), _surface_noise(fine_seed, 2.0)]


## The shared softness field for one surface, sampled on a unit grid.
func _surface_field(fields: Array, u: float, v: float) -> float:
	var broad: FastNoiseLite = fields[0]
	var fine: FastNoiseLite = fields[1]
	return broad.get_noise_2d(u, v) * 0.7 + fine.get_noise_2d(u, v) * 0.3


func _marble_map() -> ImageTexture:
	var size := _map_size()
	var fields := _surface_fields(8123, 4409)
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := float(x) / float(size)
			var v := float(y) / float(size)
			# Centred on 0.93 with a band five percent wide. The band is the six
			# percent the brief allows, and the centre is not arbitrary: the
			# accepted renders were measured with a marble map whose mean sat at
			# 0.93, and at 0.975 the pale squares sat just far enough past the
			# clip point that they came back as flat #ffffff with no shading left
			# on them anywhere.
			var shade := clampf(0.93 + 0.025 * _surface_field(fields, u, v), 0.905, 0.955)
			image.set_pixel(x, y, Color(shade, shade * 0.99, shade * 0.965, 1.0))
	# Image.create reserves the mip chain but does not fill it, and an unfilled
	# chain uploads as black - so the far ranks, which are the squares that
	# sample the higher levels, came back banded. Generating them here is what
	# makes the linear-with-mipmaps filter the materials ask for actually work.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _walnut_map() -> ImageTexture:
	var size := _map_size()
	var fields := _surface_fields(4471, 2107)
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := float(x) / float(size)
			var v := float(y) / float(size)
			# Centred on 0.93 with a band five percent wide. The band is the six
			# percent the brief allows, and the centre is not arbitrary: the
			# accepted renders were measured with a marble map whose mean sat at
			# 0.93, and at 0.975 the pale squares sat just far enough past the
			# clip point that they came back as flat #ffffff with no shading left
			# on them anywhere.
			var shade := clampf(0.93 + 0.025 * _surface_field(fields, u, v), 0.905, 0.955)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	# Image.create reserves the mip chain but does not fill it, and an unfilled
	# chain uploads as black - so the far ranks, which are the squares that
	# sample the higher levels, came back banded. Generating them here is what
	# makes the linear-with-mipmaps filter the materials ask for actually work.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _rosewood_map() -> ImageTexture:
	var size := _map_size()
	var fields := _surface_fields(9902, 5511)
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var u := float(x) / float(size)
			var v := float(y) / float(size)
			# Centred on 0.93 with a band five percent wide. The band is the six
			# percent the brief allows, and the centre is not arbitrary: the
			# accepted renders were measured with a marble map whose mean sat at
			# 0.93, and at 0.975 the pale squares sat just far enough past the
			# clip point that they came back as flat #ffffff with no shading left
			# on them anywhere.
			var shade := clampf(0.93 + 0.025 * _surface_field(fields, u, v), 0.905, 0.955)
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	# Image.create reserves the mip chain but does not fill it, and an unfilled
	# chain uploads as black - so the far ranks, which are the squares that
	# sample the higher levels, came back banded. Generating them here is what
	# makes the linear-with-mipmaps filter the materials ask for actually work.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _marble_height() -> PackedFloat32Array:
	var size := _map_size()
	var fields := _surface_fields(8123, 4409)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			heights[y * size + x] = _surface_field(fields,
				float(x) / float(size), float(y) / float(size)) * 0.35
	return heights


func _walnut_height() -> PackedFloat32Array:
	var size := _map_size()
	var fields := _surface_fields(4471, 2107)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			heights[y * size + x] = _surface_field(fields,
				float(x) / float(size), float(y) / float(size)) * 0.35
	return heights


func _rosewood_height() -> PackedFloat32Array:
	var size := _map_size()
	var fields := _surface_fields(9902, 5511)
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			heights[y * size + x] = _surface_field(fields,
				float(x) / float(size), float(y) / float(size)) * 0.35
	return heights


## The bump map for one surface, built from the same field as its albedo so the
## veining and the relief it produces always agree.
##
## The strength is a z divisor, so a larger number is a stronger bump. It is 2.6,
## which is where the accepted renders were measured: the field is calm, so the
## slope is small and the normal stays within a few degrees of straight up. The
## point of the map at this amplitude is not relief, it is the last three percent
## of shading that keeps a broad flat square from reading as a painted decal -
## taking it off entirely pushed the pale squares the rest of the way into the
## clip.
func _normal_map(heights: PackedFloat32Array) -> ImageTexture:
	var size := _map_size()
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	var strength := 2.6
	for y in size:
		for x in size:
			var left: float = heights[y * size + ((x - 1 + size) % size)]
			var right: float = heights[y * size + ((x + 1) % size)]
			var up: float = heights[((y - 1 + size) % size) * size + x]
			var down: float = heights[((y + 1) % size) * size + x]
			var normal := Vector3(left - right, up - down, 1.0 / strength).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _setup_piece_materials() -> void:
	# Both sets are balanced against each other rather than tuned alone, because
	# the board is only ever seen with both of them on it.
	#
	# THEME classic - warm polished alabaster against satin obsidian, with
	# champagne-silver collars. THEME royal_wood - boxwood cream against
	# espresso rosewood, with antique-gold trim.
	var warm := piece_theme == "royal_wood"
	var body_light := Color(0.82, 0.78, 0.70) if not warm else Color(0.86, 0.76, 0.60)
	var body_dark := Color(0.20, 0.21, 0.24) if not warm else Color(0.28, 0.17, 0.11)
	# The trim colour is shared by the piece collars and the board inlay. At the
	# old 0.82 / 0.83 albedo with metallic_specular 0.50 every collar and coronet
	# band clipped to a white ring wherever the light caught it, which is why the
	# black pieces on the h-file side had bright white hoops round their bases
	# while the same pieces on the a-file side read as dark metal.
	var accent := Color(0.60, 0.59, 0.56) if not warm else Color(0.72, 0.56, 0.20)
	var carve := _piece_carve_map()
	# White pieces: polished but never a mirror. roughness 0.24 with a low
	# metallic_specular keeps the pale body mostly diffuse, which is what stops
	# it climbing to 1.0 and clipping to flat white under ACES - and a clipped
	# surface has no shading and no shadow gradient left anywhere on it to show
	# the carving. Pure white is never a white-piece albedo.
	_piece_ivory_material = _luxury_piece_material(body_light, 0.24, 0.05, false, false, 0.06, null, carve, 0.25)
	# Black pieces: never pure black. A satin body with a real clearcoat lobe is
	# what gives the camera-facing side of a dark piece a highlight, so it reads
	# as a solid object beside the white set instead of a silhouette. The
	# specular term is back at its default here because a dark albedo cannot
	# clip the way a pale one does.
	_piece_obsidian_material = _luxury_piece_material(body_dark, 0.22, 0.12, false, true, 0.50, null, carve, 0.25, 0.40, 0.20)
	_piece_gold_material = _luxury_piece_material(accent, 0.22 if warm else 0.20, 0.90, false, false, 0.10)


## Fine procedural carving shared by both piece sets. A FastNoiseLite turned
## into a 128x128 normal map, built as a plain Image and cached once, so every
## one of the thirty-two pieces shares a single texture resource: nothing here
## is regenerated per piece, per theme switch or per frame. This needs UVs on
## the mesh, which is why _piece_mesh() projects them onto the OBJ bodies.
func _piece_carve_map() -> Texture2D:
	if _mesh_cache.has("carve_normal"):
		return _mesh_cache["carve_normal"]
	var size := 128
	var grain := FastNoiseLite.new()
	grain.seed = 4471
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 0.08
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			heights[y * size + x] = grain.get_noise_2d(float(x), float(y))
	var image := Image.create(size, size, true, Image.FORMAT_RGB8)
	var strength := 3.0
	for y in size:
		for x in size:
			var left: float = heights[y * size + ((x - 1 + size) % size)]
			var right: float = heights[y * size + ((x + 1) % size)]
			var up: float = heights[((y - 1 + size) % size) * size + x]
			var down: float = heights[((y + 1) % size) * size + x]
			var normal := Vector3(left - right, up - down, 1.0 / strength).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5, 1.0))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_mesh_cache["carve_normal"] = texture
	return texture


## The Staunton OBJ bodies carry no vt records, so they arrive with no UV
## attribute at all. A material with textures on a mesh without UVs makes the
## Compatibility renderer sample undefined coordinates, which is exactly what
## used to blow the ivory out to flat white. This projects a cylindrical UV set
## over the mesh once and caches the result: it removes that whole class of bug
## and it is what lets the piece materials carry the micro-detail normal map.
func _piece_mesh(kind: String) -> Mesh:
	var cache_key := "piece:%s" % kind
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	# PIECE_MODELS is a Dictionary, so indexing it yields Variant; an explicit
	# type is what lets the rest of this function be checked at all.
	var source: Mesh = PIECE_MODELS[kind]
	if source.get_surface_count() == 0:
		return source
	var arrays := source.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var has_uvs: bool = arrays[Mesh.ARRAY_TEX_UV] != null
	var has_normals: bool = arrays[Mesh.ARRAY_NORMAL] != null
	if has_uvs and has_normals:
		var existing_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if existing_uvs.size() == positions.size():
			# Already complete, so there is nothing to project.
			_mesh_cache[cache_key] = source
			return source
	var source_normals: PackedVector3Array = PackedVector3Array()
	if has_normals:
		source_normals = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var lowest := 0.0
	var highest := 0.0
	for point in positions:
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)
	var span := maxf(0.0001, highest - lowest)
	# The base radius is measured off the mesh rather than assumed, so the same
	# rule covers the pawn's 0.26 foot and the king's 0.33 one.
	var base_radius := 0.0
	for point in positions:
		if point.y <= lowest + span * 0.08:
			base_radius = maxf(base_radius, Vector2(point.x, point.z).length())
	base_radius = maxf(0.0001, base_radius)
	# The waist band is read once, not per vertex: it only depends on the kind.
	var waist_low: float = lowest + _ornate_profile(kind).waist_low
	var waist_high: float = lowest + _ornate_profile(kind).waist_high
	var neck_radius: float = _ornate_profile(kind).neck
	# The pinched silhouette has to exist before the normals are averaged, or the
	# smoothing pass would average the faces of the straight cone the OBJ shipped
	# and hand the turned stem cone normals.
	var shaped := PackedVector3Array()
	shaped.resize(positions.size())
	for i in positions.size():
		shaped[i] = _pinched_stem(positions[i], waist_low, waist_high, base_radius, neck_radius)
	# The bodies ship with no vn records either, so their faces arrive flat
	# shaded. Averaging the face normals of every welded vertex is what turns the
	# knight's chest and neck from stacked boxes into carved curves, and it costs
	# one pass at load time on a mesh that is then cached and shared.
	var smoothed: PackedVector3Array = PackedVector3Array()
	if not has_normals:
		smoothed = _smoothed_normals(shaped, indices)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in shaped.size():
		var vertex: Vector3 = shaped[i]
		var angle := atan2(vertex.z, vertex.x)
		# Two wraps around the piece keeps the carving fine enough to read as
		# detail rather than as one big smear.
		if has_normals:
			tool.set_normal(source_normals[i])
		else:
			tool.set_normal(smoothed[i])
		tool.set_uv(Vector2(angle / TAU + 0.5, (vertex.y - lowest) / span) * 2.0)
		tool.add_vertex(vertex)
	for index in indices:
		tool.add_index(index)
	# The Staunton bodies carry neither vt nor vn records, so they arrive with no
	# UV and no normal attribute. Both are produced here: without them the
	# renderer samples undefined coordinates, which is what used to blow the ivory
	# out to flat white, and without tangents the carve map cannot be applied.
	tool.generate_tangents()
	var mesh := tool.commit()
	_mesh_cache[cache_key] = mesh
	return mesh


## Pulls the stem of a Staunton body in to a concave waist. A plain stem is a
## straight cone, which reads as a dowel under the key light; this remaps every
## vertex inside the waist band onto a curve that bottoms out at 0.20 of the base
## radius and flares back out to the foot below and the neck collar above. The
## flare is pow(t, 1.8), which is flat at the waist and steep at the ends, so the
## silhouette turns smoothly instead of stepping. The band comes from the same
## profile the ornament stem uses, so carving and silhouette are one surface.
func _pinched_stem(point: Vector3, low: float, high: float, base_radius: float, neck: float) -> Vector3:
	if point.y <= low or point.y >= high:
		return point
	var waist: float = base_radius * 0.20
	var along := (point.y - low) / maxf(0.0001, high - low)
	var away := absf(2.0 * along - 1.0)
	var flare: float = pow(away, 1.8)
	var target: float
	if along < 0.5:
		target = waist + (base_radius - waist) * flare
	else:
		target = waist + (neck - waist) * flare
	var current := Vector2(point.x, point.z).length()
	if current <= 0.0001:
		return point
	var squeeze := target / current
	return Vector3(point.x * squeeze, point.y, point.z * squeeze)


## Averages the area-weighted face normal of every vertex that shares a
## position, which welds the duplicated vertices an OBJ export leaves behind and
## gives one smooth normal per corner of the solid. Positions are quantised to a
## 0.0005 grid so floating-point noise cannot split what is really one point.
func _smoothed_normals(positions: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var slots := PackedInt32Array()
	slots.resize(positions.size())
	var accumulators: Array = []
	var lookup := {}
	for i in positions.size():
		var point: Vector3 = positions[i]
		var key := "%d_%d_%d" % [roundi(point.x * 2000.0), roundi(point.y * 2000.0), roundi(point.z * 2000.0)]
		if not lookup.has(key):
			lookup[key] = accumulators.size()
			accumulators.append(Vector3.ZERO)
		slots[i] = lookup[key]
	for corner in range(0, indices.size(), 3):
		var a: int = indices[corner]
		var b: int = indices[corner + 1]
		var c: int = indices[corner + 2]
		var face: Vector3 = (positions[b] - positions[a]).cross(positions[c] - positions[a])
		if face.length_squared() < 0.0000001:
			continue
		accumulators[slots[a]] = (accumulators[slots[a]] as Vector3) + face
		accumulators[slots[b]] = (accumulators[slots[b]] as Vector3) + face
		accumulators[slots[c]] = (accumulators[slots[c]] as Vector3) + face
	var normals := PackedVector3Array()
	normals.resize(positions.size())
	for i in positions.size():
		var accumulated: Vector3 = accumulators[slots[i]]
		normals[i] = accumulated.normalized() if accumulated.length_squared() > 0.0000001 else Vector3.UP
	return normals


func _create_board() -> void:
	# Both themes share one geometry - the grid plus the centred slabs below it -
	# so nothing is rebuilt or duplicated when the theme changes; only colour and
	# grain differ. THEME classic is Carrara marble and obsidian with a brushed
	# slate frame and a silver inlay; THEME royal_wood is honey maple over dark
	# mahogany with a warm mahogany frame and an antique-gold inlay.
	var warm := piece_theme == "royal_wood"
	# The classic light square is deliberately below the brief's 0.86. At 0.86 the
	# square is indistinguishable from the alabaster pieces, and even at 0.80 the
	# square saturated: with the relief and the fill's grazing shadows both doing
	# less work than the geometry they replaced, it rendered as flat #ffffff with
	# no veining and no shadow gradient left on it. 0.77 keeps it a warm polished
	# stone that still reads lighter than the pieces, and it is the only albedo in
	# the scene sitting this close to the top of the ACES curve.
	var light_square := Color(0.77, 0.75, 0.71) if not warm else Color(0.82, 0.68, 0.48)
	var dark_square := Color(0.22, 0.25, 0.30) if not warm else Color(0.34, 0.16, 0.09)
	var square_roughness := 0.26 if not warm else 0.30
	# The outer frame was a near-black albedo (0.14), which renders as an unlit
	# silhouette no matter what the lighting does. It is now a light-reactive
	# surface in its own right - brushed dark slate for classic, warm mahogany for
	# royal_wood - with the roughness and metallic the brief asks for, and the
	# bevel step below gives it an angled facet that actually catches the key
	# light instead of one flat normal pointing straight up.
	var apron := Color(0.25, 0.27, 0.32) if not warm else Color(0.42, 0.22, 0.12)
	var apron_roughness := 0.25 if not warm else 0.28
	var apron_metallic := 0.15 if not warm else 0.05
	# The inner trim ring is the metal inlay between the grid and the apron. It
	# has to stay a metal, but at metallic_specular 0.50 the sky reflection rode
	# on top of the diffuse term and the whole ring clipped into a flat white
	# stripe running down the h-file side of the board.
	var trim := Color(0.62, 0.61, 0.58) if not warm else Color(0.72, 0.56, 0.20)
	var trim_roughness := 0.24 if not warm else 0.26
	var table := Color(0.27, 0.23, 0.31) if not warm else Color(0.24, 0.13, 0.08)
	var light_map := "marble" if not warm else "walnut"
	var dark_map := "walnut" if not warm else "rosewood"
	var apron_map := "marble" if not warm else "rosewood"
	# metallic_specular is pinned low on the squares: at Godot's 0.5 default a
	# broad flat face reflects the whole sky on top of its diffuse term and
	# clips to white under ACES.
	_board_light_material = _material(light_square, square_roughness, 0.0, false, 0.05,
		_surface_map(light_map), _surface_map(light_map + "_normal"))
	_board_dark_material = _material(dark_square, square_roughness, 0.0, false, 0.05,
		_surface_map(dark_map), _surface_map(dark_map + "_normal"))
	var apron_material := _material(apron, apron_roughness, apron_metallic, false, 0.06,
		_surface_map(apron_map), _surface_map(apron_map + "_normal"))
	var trim_material := _material(trim, trim_roughness, 0.90, false, 0.10)
	var table_material := _matte_material(table, 0.55,
		_surface_map(apron_map), _surface_map(apron_map + "_normal"), 0.06)

	# The grid is static, so the 32 light squares share one surface and the 32
	# dark squares share another: two draw calls instead of 64, and two mesh
	# resources instead of 64 unique BoxMeshes. Each square is still centred at
	# (file - 3.5) * tile_size and (rank - 3.5) * tile_size, so the grid spans
	# exactly -4.0 * tile_size to +4.0 * tile_size around the origin.
	var square_mesh := _shared_square_mesh()
	var light_tool := SurfaceTool.new()
	light_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dark_tool := SurfaceTool.new()
	dark_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var square_tool := light_tool if (file + rank) % 2 == 0 else dark_tool
			square_tool.append_from(square_mesh, 0, Transform3D(Basis.IDENTITY,
				Vector3((file - 3.5) * SQUARE_SIZE, 0.0, (rank - 3.5) * SQUARE_SIZE)))
	for merged in [light_tool, dark_tool]:
		var squares := MeshInstance3D.new()
		squares.mesh = merged.commit()
		squares.material_override = _board_light_material if merged == light_tool else _board_dark_material
		board.add_child(squares)

	# Slab three: the metallic trim. A solid centred slab under the grid whose
	# exposed ring is only 0.05 wide on every side, with its top face a hair under
	# the tile tops, so it reads as a machined inlay rather than a painted stripe.
	_add_board_box(Vector3(0, -0.012, 0), Vector3(8.10, 0.162, 8.10), trim_material)
	# Slab two: the apron, split into two centred tiers so the frame carries a
	# real 3D step instead of one flat top. The outer tier is the full 9.40 wide
	# and the inner tier rises 0.017 above it to hold the coordinate labels, which
	# is what gives the border a chamfered edge with two differently angled faces
	# for the key light to catch. Both tiers are centred on the origin, so there
	# is never a slot, a seam, a lip or an overhang anywhere for the backdrop to
	# show through - the old multi-part frame left exactly that, a black trench
	# around the grid and under the letters. The labels sit on solid material
	# either way.
	#
	# The inner tier's top stops at 0.065, five millimetres under the tile tops,
	# and that clearance is deliberate. With the tier raised to 0.070 it stood
	# level with the grid, and the frame then rose into the key light's grazing
	# angle far enough to shadow the squares: every pale square dropped to about a
	# fifth of its albedo while the pieces - the casters, sitting above their own
	# shadows - stayed bright. Five millimetres of step is all the bevel needs and
	# it keeps the frame below the grid.
	_add_board_box(Vector3(0, -0.0235, 0), Vector3(9.40, 0.143, 9.40), apron_material)
	_add_board_box(Vector3(0, 0.0565, 0), Vector3(9.06, 0.017, 9.06), apron_material)
	# The plinth and the two table steps below it. Each is centred and exactly as
	# wide as the slab above, so the stack runs continuously from the tile
	# bottoms down to the table with no gap and no overhang on any side.
	_add_board_box(Vector3(0, -0.145, 0), Vector3(9.40, 0.10, 9.40), apron_material)
	_add_board_box(Vector3(0, -0.295, 0), Vector3(10.40, 0.20, 10.40), table_material)
	_add_board_box(Vector3(0, -0.545, 0), Vector3(11.60, 0.30, 11.60), table_material)

	_add_board_coordinates()


## One shared box for every square on the board. Building it once instead of
## once per square is what lets all 64 of them collapse into two surfaces.
func _shared_square_mesh() -> BoxMesh:
	if _mesh_cache.has("board_square"):
		return _mesh_cache["board_square"]
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SQUARE_SIZE, 0.14, SQUARE_SIZE)
	_mesh_cache["board_square"] = mesh
	return mesh


func _add_board_coordinates() -> void:
	# Brass (or champagne) engraving on the apron, lit rather than unshaded so it
	# catches the key light the way real engraved metal does. Slab one's top face
	# is at y = 0.065, so the labels sit a hair above solid material: placed any
	# lower they end up buried inside the mesh and simply vanish, and there is
	# never a void underneath them.
	var label_color := Color("e8c56a") if piece_theme == "royal_wood" else Color("d9d5cc")
	var label_y := 0.073
	for index in BOARD_SIZE:
		for data in [
			["abcdefgh"[index], Vector3((index - 3.5) * SQUARE_SIZE, label_y, 4.22)],
			[str(8 - index), Vector3(-4.22, label_y, (index - 3.5) * SQUARE_SIZE)]
		]:
			var label := Label3D.new()
			label.text = data[0]
			label.font_size = 36
			label.modulate = label_color
			label.shaded = true
			label.outline_size = 6
			label.outline_modulate = Color(0.05, 0.03, 0.03, 0.92)
			label.position = data[1]
			label.rotation_degrees.x = -90.0
			label.pixel_size = 0.0034
			coordinates_root.add_child(label)


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
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var code: String = game.board[rank][file]
			if code != "":
				_add_piece(_kind_for_code(code), code, file, rank, _body_material(code), _piece_gold_material)


## Reconciles the piece nodes with the current board without rebuilding all
## thirty-two pieces after every move. Nodes that stay on the same square with
## the same piece kind are reused; only the moved, captured and promoted pieces
## are touched. _create_pieces() is still used for resets and quality changes.
func _sync_pieces() -> void:
	var existing: Dictionary = {}
	for piece in pieces_root.get_children():
		existing[piece.get_meta("square", Vector2i(-1, -1))] = piece
	for rank in BOARD_SIZE:
		for file in BOARD_SIZE:
			var square := Vector2i(file, rank)
			var code: String = game.board[rank][file]
			if not existing.has(square):
				if code != "":
					_add_piece(_kind_for_code(code), code, file, rank, _body_material(code), _piece_gold_material)
				continue
			var node: Node3D = existing[square]
			if code == "":
				node.queue_free()
				continue
			var kind := _kind_for_code(code)
			if String(node.get_meta("kind", "")) != kind:
				node.queue_free()
				_add_piece(kind, code, file, rank, _body_material(code), _piece_gold_material)
			else:
				node.name = _piece_node_name(kind, file, rank)
				node.set_meta("square", square)
				node.position = Vector3((file - 3.5) * SQUARE_SIZE, 0.072, (rank - 3.5) * SQUARE_SIZE)


func _kind_for_code(code: String) -> String:
	return String(PIECE_KINDS.get(code.to_lower(), "pawn"))


func _body_material(code: String) -> Material:
	return _piece_ivory_material if code == code.to_upper() else _piece_obsidian_material


func _piece_node_name(kind: String, file: int, rank: int) -> String:
	return "%s_%d_%d" % [kind.capitalize(), file, rank]


func _add_piece(kind: String, code: String, file: int, rank: int, body: Material, accent: Material) -> void:
	var is_white := code == code.to_upper()
	var piece := Node3D.new()
	piece.name = _piece_node_name(kind, file, rank)
	# The tile tops are at y = 0.07, so a piece sits directly on its square
	# instead of hovering the width of its own base above it.
	piece.position = Vector3((file - 3.5) * SQUARE_SIZE, 0.072, (rank - 3.5) * SQUARE_SIZE)
	piece.set_meta("square", Vector2i(file, rank))
	piece.set_meta("kind", kind)
	piece.set_meta("code", code)
	pieces_root.add_child(piece)

	if piece_theme == "royal_wood":
		_add_royal_wood_piece(piece, kind, is_white, body, accent)
		return

	# The knight is the one piece whose shipped body is a stack of boxes, so it
	# is built entirely from the trim layer - turned foot, turned stem and the
	# sculpted extruded head - and the OBJ is not loaded for it at all. Every
	# other kind still layers carving over the Staunton body.
	if kind != "knight":
		var model := MeshInstance3D.new()
		model.name = "SculptedModel"
		model.mesh = _piece_mesh(kind)
		model.material_override = body
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if kind == "bishop":
			model.rotation.y = PI * 0.25 if is_white else PI * 1.25
		piece.add_child(model)
	# The Staunton bodies are deliberately plain, so all the carving - tiered
	# foot, filigree, fluting, collars and the crowns - lives in this one merged
	# trim mesh rather than in a swarm of child nodes.
	var trim := MeshInstance3D.new()
	trim.name = "OrnateTrim"
	trim.mesh = _ornate_mesh(kind, body, accent, "classic")
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if kind == "knight":
		# The sculpted head faces +X, so the set is mirrored the same way the
		# body model used to be. The foot and stem are revolved, so rotating the
		# whole trim is invisible on them.
		trim.rotation.y = 0.0 if is_white else PI
	piece.add_child(trim)


func _add_royal_wood_piece(piece: Node3D, kind: String, is_white: bool, wood: Material, gold: Material) -> void:
	# The carved set shares the same sculpted Staunton topology as the classic
	# set, but is finished differently: a taller, wider turned foot and its own
	# palette, so the two sets read as different objects rather than recolours of
	# one another.
	# Same rule as the classic set: the knight's head is sculpted in the trim
	# layer, so its box-stacked OBJ body is never loaded.
	if kind != "knight":
		var model := MeshInstance3D.new()
		model.name = "RoyalWoodSculpture"
		model.mesh = _piece_mesh(kind)
		model.material_override = wood
		model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if kind == "bishop":
			model.rotation.y = PI * 0.25 if is_white else PI * 1.25
		piece.add_child(model)
	var trim := MeshInstance3D.new()
	trim.name = "RoyalWoodTrim"
	trim.mesh = _ornate_mesh(kind, wood, gold, "royal_wood")
	trim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if kind == "knight":
		trim.rotation.y = 0.0 if is_white else PI
	piece.add_child(trim)


## ---------------------------------------------------------------------------
## Ornate trim layer
##
## The sculpted Staunton bodies are plain on purpose; the carving that makes the
## set look crafted lives here. Everything is built from cached primitives and
## then merged into a single ArrayMesh with one surface per material, so a full
## 32-piece set costs 64 trim draw calls. The same ornament set as loose nodes
## would be roughly 600, which is not affordable on a phone.
## ---------------------------------------------------------------------------

const ORNAMENT_BODY := 0
const ORNAMENT_ACCENT := 1


func _radial_segments() -> int:
	match _effective_graphics_quality():
		"low": return 12
		"medium": return 18
	return 24


func _ornament_primitive(shape: String, a: float, b: float, c: float) -> Mesh:
	var key := "orn:%s:%s:%s:%s:%d" % [shape, a, b, c, _radial_segments()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var created: Mesh = null
	match shape:
		"cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = a
			cylinder.bottom_radius = b
			cylinder.height = c
			cylinder.radial_segments = _radial_segments()
			cylinder.rings = 2
			created = cylinder
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = a
			sphere.height = a * 2.0
			sphere.radial_segments = _radial_segments()
			sphere.rings = maxi(4, _radial_segments() / 2)
			created = sphere
		"torus":
			var torus := TorusMesh.new()
			torus.inner_radius = maxf(0.01, a - b)
			torus.outer_radius = a + b
			torus.rings = _radial_segments()
			torus.ring_segments = 6 if _radial_segments() <= 12 else 8
			created = torus
		"box":
			var box := BoxMesh.new()
			box.size = Vector3(a, b, c)
			created = box
	_mesh_cache[key] = created
	return created


func _ornament_add(parts: Array, shape: String, a: float, b: float, c: float, position: Vector3, material_index: int, rotation := Vector3.ZERO) -> void:
	var primitive := _ornament_primitive(shape, a, b, c)
	var basis := Basis.IDENTITY
	if rotation != Vector3.ZERO:
		basis = Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z)))
	parts.append([primitive, Transform3D(basis, position), material_index])


const ORNAMENT_FLUTE_SEGMENTS := 48
## Fluting on the stem is deliberately shallow: 12 grooves, 0.008 of amplitude,
## and only on the narrow mid-stem shaft. The base and the head stay smooth.
const ORNAMENT_FLUTE_COUNT := 12
const ORNAMENT_FLUTE_DEPTH := 0.008
## A flush inlay is 0.015 tall and stands only 0.004 proud of the body profile.
const ORNAMENT_BAND_HEIGHT := 0.015
const ORNAMENT_BAND_PROUD := 0.004


## Revolves a 2D profile around the Y axis into two meshes, one per material
## slot. Each ring is [radius, y, hard, gold]: `hard` duplicates the ring so its
## normal splits there, which is what gives a razor-sharp machined crease at a
## base step or a collar disc while the curves between rings stay silky smooth.
## `gold` routes the ring to the second slot, so the trim is a separate material
## on the same mesh rather than a second draw call.
func _lathe_surfaces(profile: Array, segments: int) -> Array:
	var body_v := PackedVector3Array()
	var body_n := PackedVector3Array()
	var body_uv := PackedVector2Array()
	var body_i := PackedInt32Array()
	var gold_v := PackedVector3Array()
	var gold_n := PackedVector3Array()
	var gold_uv := PackedVector2Array()
	var gold_i := PackedInt32Array()
	var ring_count := profile.size()
	var tangents := PackedVector2Array()
	tangents.resize(ring_count)
	for i in ring_count:
		var before := maxi(0, i - 1)
		var after := mini(ring_count - 1, i + 1)
		var delta := Vector2(
			float(profile[after][0]) - float(profile[before][0]),
			float(profile[after][1]) - float(profile[before][1]))
		tangents[i] = delta.normalized() if delta.length() > 0.0001 else Vector2(0.0, 1.0)
	for i in ring_count - 1:
		var a: Array = profile[i]
		var b: Array = profile[i + 1]
		var edge := Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1]))
		edge = edge.normalized() if edge.length() > 0.0001 else Vector2(0.0, 1.0)
		var tangent_a: Vector2 = edge if int(a[2]) == 1 else tangents[i]
		var tangent_b: Vector2 = edge if int(b[2]) == 1 else tangents[i + 1]
		var use_gold := int(a[3]) == 1 or int(b[3]) == 1
		var first: int
		var second: int
		if use_gold:
			first = _lathe_ring_into(gold_v, gold_n, gold_uv, float(a[0]), float(a[1]), tangent_a, segments)
			second = _lathe_ring_into(gold_v, gold_n, gold_uv, float(b[0]), float(b[1]), tangent_b, segments)
		else:
			first = _lathe_ring_into(body_v, body_n, body_uv, float(a[0]), float(a[1]), tangent_a, segments)
			second = _lathe_ring_into(body_v, body_n, body_uv, float(b[0]), float(b[1]), tangent_b, segments)
		var indices: PackedInt32Array = gold_i if use_gold else body_i
		for j in segments:
			var next_j := (j + 1) % segments
			indices.append(first + j)
			indices.append(second + j)
			indices.append(first + next_j)
			indices.append(first + next_j)
			indices.append(second + j)
			indices.append(second + next_j)
	return [
		_lathe_mesh(body_v, body_n, body_uv, body_i),
		_lathe_mesh(gold_v, gold_n, gold_uv, gold_i)
	]


## Appends one revolved ring and returns the index of its first vertex. Packed
## arrays are passed by reference, so the caller's buffers grow in place.
func _lathe_ring_into(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, radius: float, height: float, tangent: Vector2, segments: int) -> int:
	var start: int = vertices.size()
	for j in segments:
		var angle := TAU * float(j) / float(segments)
		# The normal is the profile tangent turned into this ring's radial plane,
		# so it stays perpendicular to the surface however the profile leans.
		var normal := Vector3(tangent.y * cos(angle), -tangent.x, tangent.y * sin(angle))
		vertices.append(Vector3(cos(angle) * radius, height, sin(angle) * radius))
		normals.append(normal.normalized())
		uvs.append(Vector2(float(j) / float(segments), height))
	return start


func _lathe_mesh(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> Mesh:
	if vertices.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## An ultra-thin flush inlay: 0.015 tall, standing only 0.004 proud of the body
## profile, revolved as a flat annulus so it reads as machined metal let into
## the wood rather than as a donut ring sitting on top of it. A revolved annulus
## is used rather than a torus because a torus makes height and protrusion the
## same number, and the brief wants them to differ.
func _flush_band(radius: float, height := ORNAMENT_BAND_HEIGHT, proud := ORNAMENT_BAND_PROUD) -> Array:
	var half := height * 0.5
	var outer := radius + proud
	return [
		[radius, -half, 1, 1],
		[outer, -half, 1, 1],
		[outer, half, 1, 1],
		[radius, half, 1, 1]
	]


## A lathe-revolved cylinder whose radius is modulated around its circumference,
## which is what turns a smooth stem into real carved fluting. 48 radial segments
## keeps 16 grooves crisp without ballooning the triangle count.
func _fluted_cylinder_arrays(top_radius: float, bottom_radius: float, height: float, segments: int, flutes: int, depth: float) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := height * 0.5
	var side := segments + 1
	# Side wall: two vertices per ring, bottom then top.
	for i in side:
		var t := float(i) / float(segments)
		var angle := TAU * t
		var radius := lerpf(bottom_radius, top_radius, t)
		var flute := 1.0 + depth * sin(angle * float(flutes))
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(radial * (radius * flute) + Vector3(0.0, -half, 0.0))
		vertices.append(radial * (radius * flute) + Vector3(0.0, half, 0.0))
		normals.append(radial)
		normals.append(radial)
		uvs.append(Vector2(t * float(flutes), 0.0))
		uvs.append(Vector2(t * float(flutes), 1.0))
	for i in segments:
		var base := i * 2
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)
	# Caps. The bottom cap faces down, so its winding runs the other way.
	var cap_ys := [-half, half]
	for cap_index in 2:
		var cap_y: float = cap_ys[cap_index]
		var radius: float = bottom_radius if cap_y < 0.0 else top_radius
		var upward := cap_y > 0.0
		var centre := vertices.size()
		vertices.append(Vector3(0.0, cap_y, 0.0))
		normals.append(Vector3(0.0, 1.0 if upward else -1.0, 0.0))
		uvs.append(Vector2(0.5, 0.5))
		var ring_start := vertices.size()
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			var flute := 1.0 + depth * sin(angle * float(flutes))
			vertices.append(Vector3(cos(angle) * radius * flute, cap_y, sin(angle) * radius * flute))
			normals.append(Vector3(0.0, 1.0 if upward else -1.0, 0.0))
			uvs.append(Vector2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle)))
		for i in segments:
			var next := ring_start + ((i + 1) % segments)
			var here := ring_start + i
			if upward:
				indices.append(centre)
				indices.append(here)
				indices.append(next)
			else:
				indices.append(centre)
				indices.append(next)
				indices.append(here)
	# Mesh arrays are indexed by the ARRAY_* constants and are expected to be
	# ARRAY_MAX long; a short four-entry list is rejected outright.
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_TEX_UV] = uvs
	result[Mesh.ARRAY_INDEX] = indices
	return result


## Appends a cached fluted lathe to a part list. Used for the lower base collar
## and the stem sleeve, where the brief asks for carved grooves rather than a
## smooth surface.
func _fluted_add(parts: Array, top_radius: float, bottom_radius: float, height: float, position: Vector3, material_index: int, flutes: int, depth: float) -> void:
	var key := "flute:%s:%s:%s:%d:%d:%s" % [top_radius, bottom_radius, height, flutes, ORNAMENT_FLUTE_SEGMENTS, depth]
	if not _mesh_cache.has(key):
		var tool := SurfaceTool.new()
		tool.create_from_arrays(
			_fluted_cylinder_arrays(top_radius, bottom_radius, height, ORNAMENT_FLUTE_SEGMENTS, flutes, depth),
			Mesh.PRIMITIVE_TRIANGLES)
		_mesh_cache[key] = tool.commit()
	parts.append([_mesh_cache[key], Transform3D(Basis.IDENTITY, position), material_index])


## The concave stem curve: `waist` at mid-height, flaring to `bottom_radius` at
## the foot and `top_radius` at the neck collar. The flare is pow(t, 1.8), which
## is flat at the waist and steep at the ends.
func _stem_radius(t: float, bottom_radius: float, waist: float, top_radius: float) -> float:
	var away := absf(2.0 * t - 1.0)
	var flare: float = pow(away, 1.8)
	if t < 0.5:
		return waist + (bottom_radius - waist) * flare
	return waist + (top_radius - waist) * flare


## d(radius) / d(height) of the same curve, differenced numerically so it cannot
## drift out of step with _stem_radius(). The surface normal needs it: a straight
## radial normal on a curve this steep is wrong by up to sixty degrees, and the
## stem would shade as a cone instead of as turned wood.
func _stem_slope(t: float, bottom_radius: float, waist: float, top_radius: float, height: float) -> float:
	var span := maxf(0.001, height)
	var delta := 0.004
	var before := maxf(0.0, t - delta)
	var after := minf(1.0, t + delta)
	if after - before <= 0.0:
		return 0.0
	var radius_before := _stem_radius(before, bottom_radius, waist, top_radius)
	var radius_after := _stem_radius(after, bottom_radius, waist, top_radius)
	return (radius_after - radius_before) / ((after - before) * span)


## A fluted lathe whose radius follows the concave curve instead of a straight
## cone. It pinches to `waist` at mid-height and flares back out to the foot and
## the neck collar, which is the graceful silhouette the brief asks for.
func _turned_stem_arrays(bottom_radius: float, waist: float, top_radius: float, height: float, segments: int, flutes: int, depth: float) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half := height * 0.5
	var side := segments + 1
	for i in side:
		var t := float(i) / float(segments)
		var angle := TAU * t
		var radius := _stem_radius(t, bottom_radius, waist, top_radius)
		var slope := _stem_slope(t, bottom_radius, waist, top_radius, height)
		var flute := 1.0 + depth * sin(angle * float(flutes))
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		# Outward normal of a surface of revolution: the radial direction tilted
		# by minus the profile slope.
		var normal := Vector3(radial.x, -slope, radial.z).normalized()
		vertices.append(radial * (radius * flute) + Vector3(0.0, -half, 0.0))
		vertices.append(radial * (radius * flute) + Vector3(0.0, half, 0.0))
		normals.append(normal)
		normals.append(normal)
		uvs.append(Vector2(t * float(flutes), 0.0))
		uvs.append(Vector2(t * float(flutes), 1.0))
	for i in segments:
		var base := i * 2
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 3)
		indices.append(base + 2)
	var cap_ys := [-half, half]
	for cap_index in 2:
		var cap_y: float = cap_ys[cap_index]
		var radius: float = bottom_radius if cap_y < 0.0 else top_radius
		var upward := cap_y > 0.0
		var centre := vertices.size()
		vertices.append(Vector3(0.0, cap_y, 0.0))
		normals.append(Vector3(0.0, 1.0 if upward else -1.0, 0.0))
		uvs.append(Vector2(0.5, 0.5))
		var ring_start := vertices.size()
		for i in segments:
			var angle := TAU * float(i) / float(segments)
			var flute := 1.0 + depth * sin(angle * float(flutes))
			vertices.append(Vector3(cos(angle) * radius * flute, cap_y, sin(angle) * radius * flute))
			normals.append(Vector3(0.0, 1.0 if upward else -1.0, 0.0))
			uvs.append(Vector2(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle)))
		for i in segments:
			var next := ring_start + ((i + 1) % segments)
			var here := ring_start + i
			if upward:
				indices.append(centre)
				indices.append(here)
				indices.append(next)
			else:
				indices.append(centre)
				indices.append(next)
				indices.append(here)
	# Mesh arrays are indexed by the ARRAY_* constants and are expected to be
	# ARRAY_MAX long; a short four-entry list is rejected outright.
	var result := []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX] = vertices
	result[Mesh.ARRAY_NORMAL] = normals
	result[Mesh.ARRAY_TEX_UV] = uvs
	result[Mesh.ARRAY_INDEX] = indices
	return result


## Appends the turned stem to a part list, spanning the waist band from the
## profile. Cached by its dimensions, so the six kinds share nothing and the
## two themes only diverge where the royal_wood foot makes them.
func _turned_stem_add(parts: Array, profile: Dictionary, foot: float) -> void:
	var low: float = profile.waist_low
	var high: float = profile.waist_high
	var height: float = high - low
	if height <= 0.001:
		return
	# `foot` is passed in rather than read off the profile because the carved set
	# scales its foot, and the stem has to flare out to the foot it is actually
	# sitting on.
	var key := "tstem:%s:%s:%s:%s:%d" % [foot, profile.stem, profile.neck, height, ORNAMENT_FLUTE_SEGMENTS]
	if not _mesh_cache.has(key):
		var tool := SurfaceTool.new()
		tool.create_from_arrays(
			_turned_stem_arrays(foot, profile.stem, profile.neck, height,
				ORNAMENT_FLUTE_SEGMENTS, ORNAMENT_FLUTE_COUNT, ORNAMENT_FLUTE_DEPTH),
			Mesh.PRIMITIVE_TRIANGLES)
		_mesh_cache[key] = tool.commit()
	parts.append([_mesh_cache[key], Transform3D(Basis.IDENTITY, Vector3(0, low + height * 0.5, 0)), ORNAMENT_BODY])


## Per-kind Staunton proportions, in the same units as the body models
## (pawn 0.91 tall ... king 1.62 tall, foot radius about 0.33).
func _ornate_profile(kind: String) -> Dictionary:
	# `stem` is the waist radius, not a sleeve radius: 0.20 of the base radius,
	# which is what makes the silhouette go in at the middle instead of running
	# parallel to the foot. `waist_low` and `waist_high` are the vertical band,
	# in the same 0-based units as the body models, across which both the body
	# mesh is pinched and the ornament stem is turned.
	var profile := {
		"foot": 0.30, "stem": 0.052,
		"neck": 0.125, "neck_y": 0.66, "flutes": 8,
		"waist_low": 0.118, "waist_high": 0.455
	}
	match kind:
		"rook":
			profile.foot = 0.335; profile.stem = 0.065
			profile.neck = 0.17; profile.neck_y = 0.80; profile.flutes = 10
			profile.waist_low = 0.165; profile.waist_high = 0.543
		"knight":
			profile.foot = 0.335; profile.stem = 0.065
			profile.neck = 0.15; profile.neck_y = 0.76; profile.flutes = 0
			profile.waist_low = 0.172; profile.waist_high = 0.726
		"bishop":
			profile.foot = 0.325; profile.stem = 0.065
			profile.neck = 0.155; profile.neck_y = 0.84; profile.flutes = 8
			profile.waist_low = 0.188; profile.waist_high = 0.670
		"queen":
			profile.foot = 0.335; profile.stem = 0.065
			profile.neck = 0.17; profile.neck_y = 0.98; profile.flutes = 12
			profile.waist_low = 0.209; profile.waist_high = 0.745
		"king":
			profile.foot = 0.335; profile.stem = 0.065
			profile.neck = 0.175; profile.neck_y = 1.02; profile.flutes = 12
			profile.waist_low = 0.227; profile.waist_high = 0.810
	return profile


func _ornate_mesh(kind: String, body: Material, accent: Material, variant: String) -> ArrayMesh:
	var key := "trim:%s:%s:%d:%d:%d" % [kind, variant, body.get_instance_id(), accent.get_instance_id(), _radial_segments()]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var parts: Array = _ornate_trim_parts(kind, variant)
	_ornate_identity_parts(parts, kind, variant)
	var mesh := ArrayMesh.new()
	for material_index in [ORNAMENT_BODY, ORNAMENT_ACCENT]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var used := false
		for part in parts:
			if int(part[2]) != material_index:
				continue
			tool.append_from(part[0] as Mesh, 0, part[1] as Transform3D)
			used = true
		if used:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
			mesh.surface_set_material(mesh.get_surface_count() - 1, accent if material_index == ORNAMENT_ACCENT else body)
	_mesh_cache[key] = mesh
	return mesh


## Tiered foot with micro-bevels, a filigree stud band, vertical fluting on the
## stem, a mid-stem brass band and a turned neck collar.
func _ornate_trim_parts(kind: String, variant: String) -> Array:
	var parts: Array = []
	var profile := _ornate_profile(kind)
	var foot: float = profile.foot
	var stem: float = profile.stem
	var neck: float = profile.neck
	var neck_y: float = profile.neck_y
	# The carved set is finished differently from the classic one: a taller, wider
	# turned foot, so it reads as a different object rather than a recolour.
	if variant == "royal_wood":
		foot *= 1.14
	# Tiered foot. The lower collar is a fluted lathe rather than a smooth
	# cylinder, and the fluting is shallow: 0.008 of amplitude over 16 grooves.
	# Nothing here protrudes past the turned profile. Every metal accent on a
	# piece is a flush band let into the shape, never a ring sitting on top of
	# it: the old torus collars and the twelve-bead ring read as a cogwheel
	# around the base.
	_ornament_add(parts, "cylinder", foot * 0.88, foot, 0.05, Vector3(0, 0.025, 0), ORNAMENT_BODY)
	_fluted_add(parts, foot * 0.60, foot * 0.88, 0.055, Vector3(0, 0.082, 0), ORNAMENT_BODY, 16, 0.012)
	# Flush inlay one of three, let into the base step. A flat revolved annulus
	# 0.015 tall standing only 0.004 proud.
	_flush_band_add(parts, foot * 0.64, Vector3(0, 0.108, 0))
	# The mid-stem shaft: a turned lathe spanning the waist band, pinched to
	# `stem` at its middle and flaring into the foot below and the neck collar
	# above. It follows the same curve the body mesh is pinched onto, so the
	# carving and the silhouette are one surface rather than a sleeve buried in
	# the wood, and the fluting is actually visible along the whole stem.
	_turned_stem_add(parts, profile, foot)
	# Flush inlay two of three, sitting on the waist itself.
	_flush_band_add(parts, stem + 0.004, Vector3(0, (profile.waist_low + profile.waist_high) * 0.5, 0), 0.010, 0.004)
	# Turned neck collar, with the third flush inlay let into it.
	_ornament_add(parts, "cylinder", neck * 0.88, neck, 0.07, Vector3(0, neck_y - 0.045, 0), ORNAMENT_BODY)
	_flush_band_add(parts, neck, Vector3(0, neck_y + 0.015, 0))
	return parts


## Appends one flush inlay band to a part list, taking only the gold surface out
## of the lathe so it lands in the trim mesh's gold slot.
func _flush_band_add(parts: Array, radius: float, position: Vector3, height := ORNAMENT_BAND_HEIGHT, proud := ORNAMENT_BAND_PROUD) -> void:
	var key := "band:%s:%s:%s:%d" % [radius, height, proud, ORNAMENT_FLUTE_SEGMENTS]
	if not _mesh_cache.has(key):
		var surfaces := _lathe_surfaces(_flush_band(radius, height, proud), ORNAMENT_FLUTE_SEGMENTS)
		_mesh_cache[key] = surfaces[1]
	parts.append([_mesh_cache[key], Transform3D(Basis.IDENTITY, position), ORNAMENT_ACCENT])


## Emits one triangle of the knight head, wound so its normal points away from
## the mesh's own centre. The head is a solid blob around that centre, which
## makes "away from the centre" a reliable outward test for the flat faces, the
## bevel bands and the side walls alike, and it removes any chance of a face
## being lit from inside.
func _emit_head_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	if normal.dot(a - centre) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	tool.set_normal(normal)
	tool.set_uv(_head_uv(a))
	tool.add_vertex(a)
	tool.set_uv(_head_uv(b))
	tool.add_vertex(b)
	tool.set_uv(_head_uv(c))
	tool.add_vertex(c)


## Triangulates one flat end of the extrusion as a fan from the middle of its
## own ring.
func _emit_head_fan(tool: SurfaceTool, ring: PackedVector3Array, centre: Vector3) -> void:
	var middle := Vector3.ZERO
	for point in ring:
		middle += point
	middle /= float(maxi(1, ring.size()))
	for i in ring.size():
		var j := (i + 1) % ring.size()
		_emit_head_triangle(tool, middle, ring[i], ring[j], centre)


## Cylindrical UVs, matching the projection the Staunton bodies get.
func _head_uv(point: Vector3) -> Vector2:
	return Vector2(atan2(point.z, point.x) / TAU + 0.5, point.y)


## The knight's head. The shipped OBJ builds it from stacked boxes, which read as
## cubes the moment a silhouette shows. This is the same head as one 2D side
## profile - snout, jaw, arched mane, pointed ears - extruded across Z through
## four layers: the outer pair carries the flat face and the inset pair gives
## the bevelled edge, so the sides taper instead of meeting at a hard wall. It is
## built once and cached, and it lands in the trim mesh's body slot like any
## other carved part.
func _knight_head_mesh() -> Mesh:
	var key := "knight_head"
	if _mesh_cache.has(key):
		var cached: Mesh = _mesh_cache[key]
		return cached
	# [x, y] of the side profile, running from the back of the neck up over the
	# mane and the ears, down the face, and back along the jaw and throat.
	var profile: Array = [
		[-0.150, 0.780], [-0.205, 0.950], [-0.140, 1.055], [-0.062, 1.082],
		[-0.034, 1.215], [0.022, 1.058], [0.084, 1.195], [0.106, 1.028],
		[0.188, 0.958], [0.232, 0.858], [0.242, 0.768], [0.196, 0.722],
		[0.116, 0.718], [0.060, 0.658], [-0.050, 0.618], [-0.122, 0.690]
	]
	# Half-width in Z for the same sixteen points: wide through the neck and the
	# chest, pinched at the ears and at the nose.
	var widths: Array = [
		0.145, 0.120, 0.100, 0.078, 0.016, 0.084,
		0.016, 0.108, 0.118, 0.100, 0.058, 0.072,
		0.090, 0.104, 0.118, 0.132
	]
	var count := profile.size()
	var back := PackedVector3Array()
	var inner_back := PackedVector3Array()
	var inner_front := PackedVector3Array()
	var front := PackedVector3Array()
	for i in count:
		# Indexed through a typed local: a bare Variant chain like profile[i][0]
		# is not something the analyser will type-check.
		var row: Array = profile[i]
		var x: float = row[0]
		var y: float = row[1]
		var half_width: float = widths[i]
		back.append(Vector3(x, y, -half_width))
		inner_back.append(Vector3(x, y, -half_width * 0.55))
		inner_front.append(Vector3(x, y, half_width * 0.55))
		front.append(Vector3(x, y, half_width))
	var centre := Vector3.ZERO
	for row in [back, inner_back, inner_front, front]:
		for point in row:
			centre += point
	centre /= float(maxi(1, count * 4))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_head_fan(tool, front, centre)
	_emit_head_fan(tool, back, centre)
	var layers := [back, inner_back, inner_front, front]
	for layer in layers.size() - 1:
		var near: PackedVector3Array = layers[layer]
		var far: PackedVector3Array = layers[layer + 1]
		for i in count:
			var j := (i + 1) % count
			_emit_head_triangle(tool, near[i], far[i], far[j], centre)
			_emit_head_triangle(tool, near[i], far[j], near[j], centre)
	tool.generate_tangents()
	var built: Mesh = tool.commit()
	_mesh_cache[key] = built
	return built


## Piece-specific crowns and caps, replacing the old single-ring accents.
func _ornate_identity_parts(parts: Array, kind: String, variant: String) -> void:
	match kind:
		"pawn":
			# A classic Staunton pawn is one uninterrupted sphere with a single
			# thin collar at the neck. The old build added a second torus at
			# y = 0.90 - inside the ball's own radius, so it cut a dark groove
			# clean around the head - and a finial nub on top of it. Both are
			# gone; what is left is the ball and the one collar under it.
			_ornament_add(parts, "torus", 0.135, 0.010, 0.0, Vector3(0, 0.72, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "sphere", 0.115, 0.0, 0.0, Vector3(0, 0.83, 0), ORNAMENT_BODY)
		"rook":
			# Stonework battlements around a flanged crown, with a brass rim.
			_ornament_add(parts, "torus", 0.205, 0.018, 0.0, Vector3(0, 0.84, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "cylinder", 0.225, 0.205, 0.13, Vector3(0, 0.90, 0), ORNAMENT_BODY)
			var merlons := 6 if _radial_segments() <= 12 else 8
			for i in merlons:
				var merlon_angle := PI * 2.0 * float(i) / float(merlons)
				_ornament_add(parts, "box", 0.085, 0.14, 0.085,
					Vector3(cos(merlon_angle) * 0.165, 0.99, sin(merlon_angle) * 0.165), ORNAMENT_BODY)
			_ornament_add(parts, "torus", 0.175, 0.012, 0.0, Vector3(0, 1.05, 0), ORNAMENT_ACCENT)
		"knight":
			# The head is sculpted, not stacked: one side profile extruded across
			# Z. The old build fanned seven separate cylinders around the neck as
			# a mane, which read as a bottle brush, and hung two torus hoops in
			# mid-air where the head used to be a box. The only metal accent left
			# on a knight is the flush band at its neck, from the trim parts.
			parts.append([_knight_head_mesh(), Transform3D(Basis.IDENTITY, Vector3.ZERO), ORNAMENT_BODY])
		"bishop":
			# Carved mitre with a patterned collar and a small finial ball, and
			# nothing else. The gold slab that used to be rotated out of the
			# mitre's flank is gone: from the camera it read as a stick jammed
			# through the side of the head. The mitre stays clean and symmetrical.
			_ornament_add(parts, "torus", 0.205, 0.024, 0.0, Vector3(0, 0.91, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "sphere", 0.235, 0.0, 0.0, Vector3(0, 1.10, 0), ORNAMENT_BODY)
			_ornament_add(parts, "torus", 0.070, 0.008, 0.0, Vector3(0, 1.02, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "sphere", 0.060, 0.0, 0.0, Vector3(0, 1.35, 0), ORNAMENT_ACCENT)
		"queen":
			# Multi-pointed coronet of brass balls over a fluted drum.
			_ornament_add(parts, "torus", 0.240, 0.026, 0.0, Vector3(0, 1.05, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "cylinder", 0.285, 0.19, 0.18, Vector3(0, 1.14, 0), ORNAMENT_BODY)
			var points := 8 if _radial_segments() <= 12 else 12
			for i in points:
				var crown_angle := PI * 2.0 * float(i) / float(points)
				_ornament_add(parts, "sphere", 0.042, 0.0, 0.0,
					Vector3(cos(crown_angle) * 0.215, 1.30, sin(crown_angle) * 0.215), ORNAMENT_ACCENT)
				_ornament_add(parts, "cylinder", 0.012, 0.012, 0.075,
					Vector3(cos(crown_angle) * 0.215, 1.26, sin(crown_angle) * 0.215), ORNAMENT_BODY)
			_ornament_add(parts, "sphere", 0.085, 0.0, 0.0, Vector3(0, 1.36, 0), ORNAMENT_BODY)
			_ornament_add(parts, "torus", 0.090, 0.009, 0.0, Vector3(0, 1.42, 0), ORNAMENT_ACCENT)
		"king":
			# Coronet with a pearl finial and a brass cross on top.
			_ornament_add(parts, "torus", 0.235, 0.028, 0.0, Vector3(0, 1.17, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "cylinder", 0.185, 0.235, 0.16, Vector3(0, 1.26, 0), ORNAMENT_BODY)
			var crown := 6 if _radial_segments() <= 12 else 8
			for i in crown:
				var king_angle := PI * 2.0 * float(i) / float(crown)
				_ornament_add(parts, "sphere", 0.026, 0.0, 0.0,
					Vector3(cos(king_angle) * 0.185, 1.33, sin(king_angle) * 0.185), ORNAMENT_ACCENT)
			_ornament_add(parts, "sphere", 0.075, 0.0, 0.0, Vector3(0, 1.40, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "box", 0.05, 0.34, 0.05, Vector3(0, 1.55, 0), ORNAMENT_ACCENT)
			_ornament_add(parts, "box", 0.26, 0.05, 0.05, Vector3(0, 1.60, 0), ORNAMENT_ACCENT)
	# royal_wood separates itself from the classic set by the taller, wider turned
	# foot in _ornate_trim_parts() and by its own colours - not by an extra
	# protruding collar ring, which is the cogwheel the brief asked to remove.


func _add_cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, y: float, material: Material, rotation := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var segments := 12 if _effective_graphics_quality() == "low" else (18 if _effective_graphics_quality() == "medium" else 24)
	var key := "cyl:%s:%s:%s:%d:%d" % [top_radius, bottom_radius, height, segments, material.get_instance_id()]
	if not _mesh_cache.has(key):
		var created := CylinderMesh.new()
		created.top_radius = top_radius
		created.bottom_radius = bottom_radius
		created.height = height
		created.radial_segments = segments
		created.rings = 2
		created.material = material
		_mesh_cache[key] = created
	mesh_instance.mesh = _mesh_cache[key]
	mesh_instance.position.y = y
	mesh_instance.rotation_degrees = rotation
	parent.add_child(mesh_instance)


func _add_torus(parent: Node3D, radius: float, tube: float, y: float, material: Material, rotation := Vector3.ZERO, offset := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var segments := 12 if _effective_graphics_quality() == "low" else (18 if _effective_graphics_quality() == "medium" else 24)
	var key := "torus:%s:%s:%d:%d" % [radius, tube, segments, material.get_instance_id()]
	if not _mesh_cache.has(key):
		var created := TorusMesh.new()
		created.inner_radius = maxf(0.01, radius - tube)
		created.outer_radius = radius + tube
		created.rings = segments
		created.ring_segments = 6 if segments == 12 else 8
		created.material = material
		_mesh_cache[key] = created
	mesh_instance.mesh = _mesh_cache[key]
	mesh_instance.position = Vector3(offset.x, y + offset.y, offset.z)
	mesh_instance.rotation_degrees = rotation
	parent.add_child(mesh_instance)


func _add_box(parent: Node3D, size: Vector3, position: Vector3, material: Material, rotation := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var key := "box:%s:%d" % [size, material.get_instance_id()]
	if not _mesh_cache.has(key):
		var created := BoxMesh.new()
		created.size = size
		created.material = material
		_mesh_cache[key] = created
	mesh_instance.mesh = _mesh_cache[key]
	mesh_instance.position = position
	mesh_instance.rotation_degrees = rotation
	parent.add_child(mesh_instance)


func _add_sphere(parent: Node3D, radius: float, y: float, material: Material, offset := Vector3.ZERO) -> void:
	var mesh_instance := MeshInstance3D.new()
	var segments := 12 if _effective_graphics_quality() == "low" else (18 if _effective_graphics_quality() == "medium" else 24)
	var rings := 6 if segments == 12 else (9 if segments == 18 else 12)
	var key := "sphere:%s:%d:%d:%d" % [radius, segments, rings, material.get_instance_id()]
	if not _mesh_cache.has(key):
		var created := SphereMesh.new()
		created.radius = radius
		created.height = radius * 2.0
		created.radial_segments = segments
		created.rings = rings
		created.material = material
		_mesh_cache[key] = created
	mesh_instance.mesh = _mesh_cache[key]
	mesh_instance.position = Vector3(offset.x, y + offset.y, offset.z)
	parent.add_child(mesh_instance)


func _create_ui() -> void:
	# A single restrained sidebar groups secondary controls without competing
	# with the board. It is inserted behind the scene title and all HUD controls.
	var sidebar := PanelContainer.new()
	sidebar.position = Vector2(14, 14)
	sidebar.size = Vector2(208, 572)
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_theme_stylebox_override("panel", _glass_stylebox(14, Color(0.05, 0.06, 0.09, 0.62), Color(0.62, 0.55, 0.42, 0.30)))
	$UI.add_child(sidebar)
	$UI.move_child(sidebar, 0)
	_register_left_column(sidebar)

	_top_panel = HBoxContainer.new()
	var panel := _top_panel
	panel.add_theme_constant_override("separation", 6)
	$UI.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(196, 44)
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", Color("e8c56a"))
	panel.add_child(_status_label)

	_clock_label = Label.new()
	_clock_label.custom_minimum_size = Vector2(146, 44)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.add_theme_font_size_override("font_size", 20)
	_clock_label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.92, 0.94))
	panel.add_child(_clock_label)

	_mode_button = Button.new()
	_mode_button.text = "VS AI" if play_vs_ai else "LOCAL"
	_mode_button.custom_minimum_size = Vector2(76, 42)
	_mode_button.pressed.connect(_toggle_game_mode)
	panel.add_child(_mode_button)

	var clock_button := Button.new()
	clock_button.text = "CLOCK"
	clock_button.custom_minimum_size = Vector2(78, 42)
	clock_button.pressed.connect(_toggle_clock)
	panel.add_child(clock_button)

	var camera_button := Button.new()
	camera_button.text = "VIEW"
	camera_button.custom_minimum_size = Vector2(72, 42)
	camera_button.pressed.connect(_reset_camera)
	panel.add_child(camera_button)

	var haptic_button := Button.new()
	haptic_button.text = "VIBE" if haptics_enabled else "VIBE OFF"
	haptic_button.custom_minimum_size = Vector2(68, 42)
	haptic_button.pressed.connect(_toggle_haptics.bind(haptic_button))
	panel.add_child(haptic_button)

	var undo_button := Button.new()
	undo_button.text = "UNDO"
	undo_button.custom_minimum_size = Vector2(78, 42)
	undo_button.pressed.connect(_undo)
	panel.add_child(undo_button)

	var new_button := Button.new()
	new_button.text = "NEW"
	new_button.custom_minimum_size = Vector2(78, 42)
	new_button.pressed.connect(_new_game)
	panel.add_child(new_button)

	var menu_button := Button.new()
	menu_button.text = "MENU"
	menu_button.custom_minimum_size = Vector2(76, 42)
	menu_button.pressed.connect(_show_main_menu)
	panel.add_child(menu_button)

	_graphics_button = Button.new()
	_graphics_button.position = Vector2(28, 66)
	_graphics_button.size = Vector2(112, 36)
	_graphics_button.pressed.connect(_cycle_graphics_quality)
	$UI.add_child(_graphics_button)
	_register_left_column(_graphics_button)
	_update_graphics_button()

	_sound_button = Button.new()
	_sound_button.position = Vector2(28, 108)
	_sound_button.size = Vector2(112, 36)
	_sound_button.pressed.connect(_toggle_sound)
	$UI.add_child(_sound_button)
	_register_left_column(_sound_button)
	_update_sound_button()

	_music_button = Button.new()
	_music_button.position = Vector2(28, 150)
	_music_button.size = Vector2(112, 36)
	_music_button.pressed.connect(_toggle_music)
	$UI.add_child(_music_button)
	_register_left_column(_music_button)
	_update_music_button()

	for child in panel.get_children():
		if child is Button:
			_style_hud_button(child)
	for button in [_graphics_button, _sound_button, _music_button]:
		_style_hud_button(button)

	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.offset_left = -145.0
	_fps_label.offset_top = -48.0
	_fps_label.offset_right = -20.0
	_fps_label.offset_bottom = -18.0
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82, 0.90))
	_fps_label.add_theme_font_size_override("font_size", 15)
	# Named so the automated capture harness can hide it: on the software
	# renderer CI uses, the very first frames land about a second apart, so the
	# readout froze on "1 FPS" and that is what ended up in the screenshot.
	_fps_label.name = "PerformanceReadout"
	$UI.add_child(_fps_label)
	_create_main_menu()
	_create_game_panels()


func _style_hud_button(button: Button) -> void:
	# Glassmorphic: a translucent dark fill, a hairline border that catches the
	# warm key light, and a gold accent on hover and press. Without the explicit
	# styleboxes a themed Button falls back to the default project theme, which
	# is opaque and ignores these colours entirely.
	var normal := _glass_stylebox(8, Color(0.07, 0.08, 0.11, 0.60), Color(0.58, 0.60, 0.68, 0.42))
	var active := _glass_stylebox(8, Color(0.17, 0.13, 0.09, 0.78), Color("d4af37"))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("pressed", active)
	button.add_theme_stylebox_override("focus", active)
	button.add_theme_stylebox_override("disabled", normal)
	button.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88, 0.96))
	button.add_theme_color_override("font_hover_color", Color("f6e7c4"))
	button.add_theme_color_override("font_pressed_color", Color("f6e7c4"))
	button.add_theme_color_override("font_focus_color", Color("f6e7c4"))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.56, 0.60, 0.7))


## One translucent panel used by the sidebar, the HUD buttons and the move
## history, so the whole overlay reads as one glass layer over the board.
func _glass_stylebox(radius: int, fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	# A light top edge and a dark bottom edge fake the specular streak a real
	# glass bevel would give, which is most of what sells the material.
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	return style


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
	panel.custom_minimum_size = Vector2(620, 680)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.052, 0.07, 0.98)
	panel_style.border_color = Color(0.55, 0.39, 0.2, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 34
	panel_style.content_margin_right = 34
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var title := Label.new()
	title.text = "♜  CHESS 3D  ♖"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("e6cb8c"))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "THE CLASSIC GAME • REIMAGINED"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.66, 0.7, 0.78))
	content.add_child(subtitle)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 8)
	content.add_child(rule)

	var settings_title := Label.new()
	settings_title.text = "MATCH SETUP"
	settings_title.add_theme_font_size_override("font_size", 14)
	settings_title.add_theme_color_override("font_color", Color("c5a96b"))
	content.add_child(settings_title)
	var settings := GridContainer.new()
	settings.columns = 4
	settings.add_theme_constant_override("h_separation", 10)
	content.add_child(settings)
	_color_button = _menu_button("PLAY AS: " + ("WHITE" if human_color == ChessRules.WHITE else "BLACK"), _cycle_player_color, Vector2(130, 50))
	settings.add_child(_color_button)
	_difficulty_button = _menu_button("AI: " + ai_difficulty.to_upper(), _cycle_ai_difficulty, Vector2(130, 50))
	settings.add_child(_difficulty_button)
	_language_button = _menu_button("ENGLISH", _cycle_language, Vector2(130, 50))
	settings.add_child(_language_button)
	_piece_theme_button = _menu_button("PIECES: " + piece_theme.to_upper(), _cycle_piece_theme, Vector2(130, 50))
	settings.add_child(_piece_theme_button)

	var play_title := Label.new()
	play_title.text = "PLAY"
	play_title.add_theme_font_size_override("font_size", 14)
	play_title.add_theme_color_override("font_color", Color("c5a96b"))
	content.add_child(play_title)
	_continue_button = _menu_button("▶  CONTINUE MATCH", _continue_game)
	content.add_child(_continue_button)
	_ai_start_button = _menu_button("♟  NEW MATCH VS COMPUTER", _start_ai_game)
	content.add_child(_ai_start_button)
	_local_start_button = _menu_button("♙  LOCAL TWO PLAYERS", _start_local_game)
	content.add_child(_local_start_button)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(tools)
	tools.add_child(_menu_button("ARCHIVE", _show_archive, Vector2(170, 48)))
	tools.add_child(_menu_button("ACCESSIBILITY", _show_accessibility, Vector2(190, 48)))
	_close_menu_button = _menu_button("RETURN TO BOARD", _continue_game, Vector2(190, 48))
	tools.add_child(_close_menu_button)

	var version := Label.new()
	version.text = "ANDROID • OFFLINE • " + _version_label()
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(0.48, 0.52, 0.61, 1))
	content.add_child(version)
	_apply_language()
	_menu_overlay.hide()


func _create_game_panels() -> void:
	var history_panel := PanelContainer.new()
	history_panel.position = Vector2(24, 198)
	history_panel.size = Vector2(188, 240)
	history_panel.add_theme_stylebox_override("panel", _glass_stylebox(12, Color(0.05, 0.06, 0.09, 0.58), Color(0.55, 0.58, 0.66, 0.34)))
	$UI.add_child(history_panel)
	_register_left_column(history_panel)
	_history_label = RichTextLabel.new()
	_history_label.bbcode_enabled = true
	_history_label.fit_content = false
	_history_label.scroll_following = true
	_history_label.add_theme_font_size_override("normal_font_size", 16)
	history_panel.add_child(_history_label)
	_update_move_history()

	_captured_label = Label.new()
	_captured_label.position = Vector2(24, 448)
	_captured_label.size = Vector2(190, 66)
	_captured_label.add_theme_font_size_override("font_size", 17)
	$UI.add_child(_captured_label)
	_register_left_column(_captured_label)
	_update_captured_pieces()

	var resign_button := Button.new()
	resign_button.text = "RESIGN"
	resign_button.position = Vector2(24, 526)
	resign_button.size = Vector2(104, 38)
	_style_hud_button(resign_button)
	resign_button.pressed.connect(_request_resign)
	$UI.add_child(resign_button)
	_register_left_column(resign_button)

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

	_archive_window = Window.new()
	_archive_window.title = "GAME ARCHIVE"
	_archive_window.size = Vector2i(720, 620)
	_archive_window.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_archive_window.close_requested.connect(_archive_window.hide)
	var scroll := ScrollContainer.new()
	_archive_window.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_archive_list = VBoxContainer.new()
	_archive_list.custom_minimum_size = Vector2(680, 0)
	_archive_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_archive_list)
	$UI.add_child(_archive_window)

	_accessibility_window = Window.new()
	_accessibility_window.title = "ACCESSIBILITY"
	_accessibility_window.size = Vector2i(560, 650)
	_accessibility_window.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_accessibility_window.close_requested.connect(_accessibility_window.hide)
	var accessibility_list := VBoxContainer.new()
	accessibility_list.add_theme_constant_override("separation", 14)
	_accessibility_window.add_child(accessibility_list)
	accessibility_list.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for setting in ["contrast", "colorblind", "motion", "coordinates", "text"]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(500, 68)
		button.pressed.connect(_toggle_accessibility.bind(setting))
		accessibility_list.add_child(button)
		_accessibility_buttons[setting] = button
	var tutorial_button := Button.new()
	tutorial_button.text = "HOW TO PLAY"
	tutorial_button.custom_minimum_size = Vector2(500, 68)
	tutorial_button.pressed.connect(_show_tutorial)
	accessibility_list.add_child(tutorial_button)
	var about_button := Button.new()
	about_button.text = "ABOUT & LICENSES"
	about_button.custom_minimum_size = Vector2(500, 68)
	about_button.pressed.connect(_show_about)
	accessibility_list.add_child(about_button)
	$UI.add_child(_accessibility_window)
	_create_information_windows()
	_update_accessibility_buttons()
	_apply_language()
	_apply_accessibility()


func _menu_button(text: String, callback: Callable, minimum_size := Vector2(540, 58)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.085, 0.095, 0.12, 0.96)
	normal.border_color = Color(0.26, 0.28, 0.34, 1)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.14, 0.11, 1)
	hover.border_color = Color("d1ae68")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(callback)
	return button


func _text(key: String) -> String:
	var fa := {
		"continue": "ادامه بازی", "new_ai": "بازی جدید با هوش مصنوعی", "local": "بازی دونفره محلی",
		"close": "بستن منو", "white": "سفید", "black": "سیاه", "play_as": "بازی با مهره‌های: ",
		"level": "سطح هوش مصنوعی: ", "easy": "آسان", "medium": "متوسط", "hard": "سخت", "professional": "حرفه‌ای",
		"white_turn": "نوبت سفید", "black_turn": "نوبت سیاه", "check": " — کیش", "thinking": "هوش مصنوعی در حال فکر کردن...",
		"moves": "حرکت‌ها", "white_captured": "گرفته‌های سفید: ", "black_captured": "گرفته‌های سیاه: ",
		"language": "زبان: فارسی", "game_over": "پایان بازی", "resign_confirm": "آیا مطمئن هستید که می‌خواهید تسلیم شوید؟",
		"saved_automatically": "\n\nبازی به‌صورت خودکار ذخیره شد."
	}
	var en := {
		"continue": "CONTINUE GAME", "new_ai": "NEW GAME VS AI", "local": "LOCAL TWO PLAYERS",
		"close": "CLOSE MENU", "white": "WHITE", "black": "BLACK", "play_as": "PLAY AS: ",
		"level": "AI LEVEL: ", "easy": "EASY", "medium": "MEDIUM", "hard": "HARD", "professional": "PROFESSIONAL",
		"white_turn": "White to move", "black_turn": "Black to move", "check": " — CHECK", "thinking": "Computer thinking...",
		"moves": "MOVES", "white_captured": "White captured: ", "black_captured": "Black captured: ",
		"language": "LANGUAGE: ENGLISH", "game_over": "GAME OVER", "resign_confirm": "Are you sure you want to resign?",
		"saved_automatically": "\n\nThe game was saved automatically."
	}
	return fa.get(key, key) if language == "fa" else en.get(key, key)


func _load_piece_theme() -> void:
	if FileAccess.file_exists(PIECE_THEME_PATH):
		var file := FileAccess.open(PIECE_THEME_PATH, FileAccess.READ)
		if file: piece_theme = file.get_as_text().strip_edges()
	if piece_theme not in ["classic", "royal_wood"]: piece_theme = "classic"


func _cycle_piece_theme() -> void:
	var themes := ["classic", "royal_wood"]
	piece_theme = themes[(themes.find(piece_theme) + 1) % themes.size()]
	var file := FileAccess.open(PIECE_THEME_PATH, FileAccess.WRITE)
	if file: file.store_string(piece_theme)
	# Persist the game before the scene reload, otherwise up to five seconds of
	# moves could be lost when the fresh _ready() reads the autosave.
	_save_autosave()
	_cancel_move_animation()
	get_tree().reload_current_scene()


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
	var levels := ["easy", "medium", "hard", "professional"]
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
	_archive_completed_game()
	_game_over_dialog.dialog_text = _translate_result(game.result) + _text("saved_automatically")
	_game_over_dialog.popup_centered()
	_play_sound("game_over")
	_haptic(80)


func _create_information_windows() -> void:
	_tutorial_window = _information_window("HOW TO PLAY", "[font_size=24][b]QUICK START[/b][/font_size]\n\n1. Tap one of your pieces. Legal destinations light up.\n\n2. Tap a highlighted square to move. Dragging also works.\n\n3. Protect your king: orange/red means check. The game detects checkmate, stalemate, repetition and draw rules automatically.\n\n4. Pinch to zoom, drag empty space to orbit, and use FLIP or RESET for the camera.\n\n5. Open MENU to choose AI strength, clocks, graphics, archive, sound and accessibility.")
	_about_window = _information_window("ABOUT & LICENSES", "[font_size=24][b]Chess 3D  •  Version " + _version_label() + "[/b][/font_size]\n\nAn offline-first 3D chess game made with Godot. No account, advertising, analytics or network connection is required.\n\n[b]ENGINE[/b]\nGodot Engine is available under the MIT License. Copyright © 2014-present Godot Engine contributors; copyright © 2007-2014 Juan Linietsky, Ariel Manzur.\n\n[b]GAME CONTENT[/b]\nCode, procedural models, interface and generated local audio in this repository are original project assets. Chess rules are public domain.\n\nOpen-source license text is distributed with the source repository.")


func _information_window(title: String, content: String) -> Window:
	var window := Window.new()
	window.title = title
	window.size = Vector2i(720, 620)
	window.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	window.close_requested.connect(window.hide)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 24
	layout.offset_top = 20
	layout.offset_right = -24
	layout.offset_bottom = -20
	window.add_child(layout)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = false
	text.text = content
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 20)
	layout.add_child(text)
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.custom_minimum_size = Vector2(0, 58)
	close_button.pressed.connect(window.hide)
	layout.add_child(close_button)
	$UI.add_child(window)
	return window


func _show_tutorial() -> void:
	_accessibility_window.hide()
	_tutorial_window.popup_centered()


func _show_about() -> void:
	_accessibility_window.hide()
	_about_window.popup_centered()


func _show_accessibility() -> void:
	_update_accessibility_buttons()
	_accessibility_window.popup_centered()


func _toggle_accessibility(setting: String) -> void:
	match setting:
		"contrast": high_contrast_enabled = not high_contrast_enabled
		"colorblind": colorblind_enabled = not colorblind_enabled
		"motion": reduced_motion_enabled = not reduced_motion_enabled
		"coordinates": coordinates_enabled = not coordinates_enabled
		"text": large_text_enabled = not large_text_enabled
	_apply_accessibility()
	_update_accessibility_buttons()
	_save_autosave()


func _update_accessibility_buttons() -> void:
	if _accessibility_buttons.is_empty(): return
	_accessibility_buttons.contrast.text = "HIGH CONTRAST: " + ("ON" if high_contrast_enabled else "OFF")
	_accessibility_buttons.colorblind.text = "COLORBLIND PALETTE: " + ("ON" if colorblind_enabled else "OFF")
	_accessibility_buttons.motion.text = "REDUCED MOTION: " + ("ON" if reduced_motion_enabled else "OFF")
	_accessibility_buttons.coordinates.text = "BOARD COORDINATES: " + ("ON" if coordinates_enabled else "OFF")
	_accessibility_buttons.text.text = "LARGE TEXT: " + ("ON" if large_text_enabled else "OFF")


func _apply_accessibility() -> void:
	# This runs at the end of _ready(), so these are the albedoes the board
	# actually renders with; they have to track _create_board() or the two
	# disagree. The neutral path leaves the theme's own colours alone.
	if is_instance_valid(_board_light_material):
		_board_light_material.albedo_color = Color(0.90, 0.89, 0.86) if high_contrast_enabled else _board_light_material.albedo_color
	if is_instance_valid(_board_dark_material):
		_board_dark_material.albedo_color = Color("263654") if colorblind_enabled else (Color("6e7f9c") if high_contrast_enabled else _board_dark_material.albedo_color)
	coordinates_root.visible = coordinates_enabled
	_ui_theme.default_font_size = 21 if large_text_enabled else 16
	_apply_theme_recursive($UI)
	_draw_highlights()


## Walks the whole UI tree so late-created controls (archive rows, the promotion
## picker) inherit the shared theme and the large-text scale as well.
func _apply_theme_recursive(node: Node) -> void:
	if node is Control:
		var control := node as Control
		# Capture the base font size before the shared theme is attached,
		# otherwise repeated passes would compound the scale.
		_apply_text_scale(control)
		control.theme = _ui_theme
	for child in node.get_children():
		_apply_theme_recursive(child)


func _apply_text_scale(control: Control) -> void:
	if not (control is Label or control is Button or control is RichTextLabel):
		return
	var font_key := "normal_font_size" if control is RichTextLabel else "font_size"
	if not control.has_meta("_base_font_size"):
		control.set_meta("_base_font_size", control.get_theme_font_size(font_key))
	var base_size: int = control.get_meta("_base_font_size")
	var scale := 1.3 if large_text_enabled else 1.0
	control.add_theme_font_size_override(font_key, maxi(10, int(round(base_size * scale))))


func _version_label() -> String:
	return "%s Beta %s" % [_app_version, APP_BUILD]


func _show_archive() -> void:
	_refresh_archive_list()
	_archive_window.popup_centered()


func _refresh_archive_list() -> void:
	if not is_instance_valid(_archive_list):
		return
	for child in _archive_list.get_children():
		child.queue_free()
	var heading := Label.new()
	heading.text = "Saved games (%d/%d)" % [archive.games.size(), ArchiveStore.MAX_GAMES]
	heading.add_theme_font_size_override("font_size", 24)
	_archive_list.add_child(heading)
	if archive.games.is_empty():
		var empty := Label.new()
		empty.text = "No archived games yet. Completed games are saved automatically."
		_archive_list.add_child(empty)
		return
	for entry in archive.games:
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s  •  %s  •  %s" % [entry.date, entry.result, entry.mode.to_upper()]
		info.custom_minimum_size = Vector2(390, 50)
		row.add_child(info)
		var load_button := Button.new()
		load_button.text = "LOAD"
		load_button.pressed.connect(_load_archived_game.bind(entry))
		row.add_child(load_button)
		var copy_button := Button.new()
		copy_button.text = "COPY PGN"
		copy_button.pressed.connect(_copy_archived_pgn.bind(entry.pgn))
		row.add_child(copy_button)
		var delete_button := Button.new()
		delete_button.text = "DELETE"
		delete_button.pressed.connect(_delete_archived_game.bind(entry.id))
		row.add_child(delete_button)
		_archive_list.add_child(row)
	_apply_accessibility()


func _load_archived_game(entry: Dictionary) -> void:
	var response := game.load_pgn(entry.pgn)
	if not response.ok:
		return
	white_time = float(entry.get("white_time", 600.0))
	black_time = float(entry.get("black_time", 600.0))
	play_vs_ai = entry.get("mode", "ai") == "ai"
	ai_difficulty = entry.get("difficulty", "medium")
	# Remember which side the player controlled, otherwise loading a game played
	# as Black would leave the engine waiting for a move that never comes.
	human_color = int(entry.get("human_color", ChessRules.WHITE))
	_archived_current_game = true
	_has_resumable_game = true
	_archive_window.hide()
	_menu_overlay.hide()
	get_tree().paused = false
	_cancel_move_animation()
	ai_generation += 1
	ai_thinking = false
	_create_pieces()
	_draw_highlights()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_save_autosave()
	if game.result == "" and play_vs_ai and game.turn != human_color:
		ai_thinking = true
		_update_status()
		get_tree().create_timer(0.35).timeout.connect(_play_ai_move)
	elif game.result != "":
		_show_game_over_if_needed()


func _copy_archived_pgn(pgn: String) -> void:
	DisplayServer.clipboard_set(pgn)


func _delete_archived_game(id: String) -> void:
	archive.remove_game(id)
	_refresh_archive_list()


func _archive_completed_game() -> void:
	if _archived_current_game or game.result == "":
		return
	archive.add_game(game.to_pgn({"White": "Player", "Black": "Offline AI"}), game.result, {
		"white_time": white_time, "black_time": black_time,
		"mode": "ai" if play_vs_ai else "local", "difficulty": ai_difficulty,
		"human_color": human_color
	})
	_archived_current_game = true


func _show_main_menu() -> void:
	if not is_instance_valid(_menu_overlay):
		return
	_hide_secondary_windows()
	_continue_button.disabled = not _has_resumable_game and game.move_notation.is_empty()
	_menu_overlay.show()
	get_tree().paused = true
	_menu_overlay.process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _hide_secondary_windows() -> void:
	for window in [_archive_window, _accessibility_window, _tutorial_window, _about_window]:
		if is_instance_valid(window):
			window.hide()


func _continue_game() -> void:
	_hide_secondary_windows()
	_menu_overlay.hide()
	get_tree().paused = false
	# A finished game restored from the autosave or the archive would otherwise
	# never surface its game-over dialog again.
	if game.result != "":
		_show_game_over_if_needed()


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
	if is_instance_valid(_promotion_popup):
		return
	if ai_thinking or animating_move or game.result != "":
		return
	var previous_selected := selected
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
		if previous_selected != square:
			_set_piece_selected(previous_selected, false)
		selected = square
		selected_moves = game.legal_moves(square)
		_set_piece_selected(selected, true)
		_haptic(18)
		_play_sound("select")
	else:
		_set_piece_selected(previous_selected, false)
		selected = Vector2i(-1, -1)
		selected_moves.clear()
	_draw_highlights()


func _set_piece_selected(square: Vector2i, lifted: bool) -> void:
	if square.x < 0:
		return
	for piece in pieces_root.get_children():
		if piece.get_meta("square", Vector2i(-1, -1)) == square:
			var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			var duration := 0.01 if reduced_motion_enabled else 0.14
			tween.tween_property(piece, "position:y", 0.30 if lifted else 0.12, duration)
			return


func _show_promotion_picker(moves: Array[Dictionary]) -> void:
	# A previous picker must never linger: PopupPanel is modal, so a leaked popup
	# would swallow every later board tap.
	if is_instance_valid(_promotion_popup):
		_promotion_popup.queue_free()
		_promotion_popup = null
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
	popup.popup_hide.connect(_on_promotion_popup_hidden.bind(popup))
	_promotion_popup = popup
	popup.popup_centered(Vector2i(420, 260))
	_apply_accessibility()


func _choose_promotion(move: Dictionary, popup: PopupPanel) -> void:
	if _promotion_popup == popup:
		_promotion_popup = null
	popup.queue_free()
	_play_move(move)


## Fired when the player dismisses the picker by tapping outside it.
func _on_promotion_popup_hidden(popup: PopupPanel) -> void:
	if _promotion_popup == popup:
		_promotion_popup = null
	popup.queue_free()


func _play_move(move: Dictionary) -> void:
	if not game.play(move):
		return
	_needs_full_piece_rebuild = move.has("promotion")
	last_move = move.duplicate(true)
	_haptic(35 if move.captured != "" else 22)
	if move.has("castle"):
		_play_sound("castle")
	elif move.captured != "":
		_play_sound("capture")
	else:
		_play_sound("move")
	if game.is_in_check(game.turn):
		_play_sound("check")
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	_draw_highlights()
	_animate_board_move(move, _finish_player_move)


func _finish_player_move() -> void:
	animating_move = false
	_refresh_pieces_after_move()
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
	_needs_full_piece_rebuild = chosen.has("promotion")
	last_move = chosen.duplicate(true)
	if chosen.has("castle"):
		_play_sound("castle")
	elif chosen.captured != "":
		_play_sound("capture")
	else:
		_play_sound("move")
	if game.is_in_check(game.turn):
		_play_sound("check")
	_animate_board_move(chosen, _finish_ai_move)


func _finish_ai_move() -> void:
	animating_move = false
	ai_thinking = false
	_refresh_pieces_after_move()
	_draw_highlights()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_show_game_over_if_needed()
	_save_autosave()


func _refresh_pieces_after_move() -> void:
	if _needs_full_piece_rebuild:
		_needs_full_piece_rebuild = false
		_create_pieces()
	else:
		_sync_pieces()


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
		animating_move = false
		finished.call()
		return
	# The rules engine already applied the move, so re-tag the node to its new
	# square right away. The piece sync below can then reuse this node instead of
	# rebuilding all thirty-two pieces after every single move.
	moving_piece.set_meta("square", move.to)
	moving_piece.name = _piece_node_name(String(moving_piece.get_meta("kind", "pawn")), move.to.x, move.to.y)
	var target := Vector3((move.to.x - 3.5) * SQUARE_SIZE, 0.12, (move.to.y - 3.5) * SQUARE_SIZE)
	var midpoint := (moving_piece.position + target) * 0.5
	midpoint.y = 0.75
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var first_duration := 0.01 if reduced_motion_enabled else 0.13
	var second_duration := 0.01 if reduced_motion_enabled else 0.15
	tween.tween_property(moving_piece, "position", midpoint, first_duration)
	tween.tween_property(moving_piece, "position", target, second_duration)
	if is_instance_valid(captured_piece):
		_spawn_capture_effect(captured_piece.position, move.captured)
		var capture_tween := create_tween().set_parallel(true)
		var capture_duration := 0.01 if reduced_motion_enabled else 0.2
		capture_tween.tween_property(captured_piece, "scale", Vector3.ZERO, capture_duration)
		capture_tween.tween_property(captured_piece, "position:y", -0.25, capture_duration)
	_move_tween = tween
	_move_finished_callback = finished
	tween.finished.connect(_on_move_animation_finished)


## Single funnel for the animation callback. A tween that is killed before it
## finishes never emits finished, so the callback is always cleared here to keep
## animating_move from staying stuck on true.
func _on_move_animation_finished() -> void:
	var callback := _move_finished_callback
	_move_tween = null
	_move_finished_callback = Callable()
	if callback.is_valid():
		callback.call()


## Abandons an in-flight move animation. Used whenever the scene is about to be
## rebuilt or reset, where the tweened node would otherwise be destroyed and the
## game would freeze with animating_move stuck on true.
func _cancel_move_animation() -> void:
	animating_move = false
	_move_finished_callback = Callable()
	if _move_tween != null:
		_move_tween.kill()
		_move_tween = null


func _spawn_capture_effect(position: Vector3, captured_code: String) -> void:
	if not capture_effects_enabled or reduced_motion_enabled:
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
	var check_color := Color(0.95, 0.46, 0.10, 0.70) if colorblind_enabled else Color(0.82, 0.16, 0.12, 0.64)
	var move_color := Color(0.20, 0.56, 0.85, 0.66) if colorblind_enabled else Color(0.72, 0.56, 0.25, 0.58)
	if game.result == "" and game.is_in_check(game.turn):
		var king_code := "K" if game.turn == ChessRules.WHITE else "k"
		for rank in BOARD_SIZE:
			for file in BOARD_SIZE:
				if game.board[rank][file] == king_code:
					_add_highlight(Vector2i(file, rank), check_color, 0.46)
	if selected.x >= 0:
		_add_highlight(selected, Color(1.0, 0.72, 0.05, 0.78 if high_contrast_enabled else 0.62), 0.47)
	for move in selected_moves:
		_add_highlight(move.to, move_color, 0.18 if move.captured == "" else 0.38)


func _add_highlight(square: Vector2i, color: Color, radius: float) -> void:
	var marker := MeshInstance3D.new()
	# The disc geometry and the material are shared between every marker, so a
	# full highlight redraw allocates nothing but the markers themselves.
	marker.mesh = _highlight_mesh(radius)
	marker.material_override = _highlight_material(color)
	marker.position = Vector3((square.x - 3.5) * SQUARE_SIZE, 0.1, (square.y - 3.5) * SQUARE_SIZE)
	highlights_root.add_child(marker)


func _highlight_mesh(radius: float) -> CylinderMesh:
	var key := "highlight:%s" % radius
	if not _mesh_cache.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = 0.025
		mesh.radial_segments = 32
		_mesh_cache[key] = mesh
	return _mesh_cache[key] as CylinderMesh


func _highlight_material(color: Color) -> StandardMaterial3D:
	var key := "highlight_material:%s" % color.to_html(true)
	if not _mesh_cache.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mesh_cache[key] = material
	return _mesh_cache[key] as StandardMaterial3D


func _screen_to_square(screen_position: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	# Sample the top face of the board squares (BoxMesh is 0.14 tall and centred
	# on y = 0), not a plane floating above them, so a tap lands on the square the
	# player actually sees instead of one biased towards the camera.
	var plane := Plane(Vector3.UP, 0.07)
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
	var text := "Clock: OFF"
	if clock_enabled:
		text = "W %s  •  B %s" % [_format_time(white_time), _format_time(black_time)]
	if text == _clock_label.text:
		return
	_clock_label.text = text


func _format_time(seconds: float) -> String:
	var total := maxi(0, ceili(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func _create_audio() -> void:
	for sound_name in SOUND_STREAMS:
		var player := AudioStreamPlayer.new()
		player.name = "Sound_" + sound_name.capitalize()
		player.stream = SOUND_STREAMS[sound_name]
		player.volume_db = linear_to_db(sound_volume)
		add_child(player)
		_sound_players[sound_name] = player
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "AmbientMusic"
	# Untyped on purpose: Resource.duplicate() is statically a Resource, and the
	# loop helper narrows it to AudioStreamWAV at runtime.
	var music_stream = AMBIENT_MUSIC.duplicate()
	_configure_music_loop(music_stream)
	_music_player.stream = music_stream
	_music_player.volume_db = linear_to_db(music_volume)
	add_child(_music_player)
	if music_enabled: _music_player.play()


## loop_end is measured in sample frames, so the byte size has to be divided by
## the frame size of the actual format. The old hard-coded /2 only happened to
## be right for this mono 16-bit file.
func _configure_music_loop(stream: AudioStream) -> void:
	if not (stream is AudioStreamWAV):
		return
	var wav := stream as AudioStreamWAV
	var bytes_per_frame := 0
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			bytes_per_frame = 2 if wav.stereo else 1
		AudioStreamWAV.FORMAT_16_BITS:
			bytes_per_frame = 4 if wav.stereo else 2
		_:
			bytes_per_frame = 0
	if bytes_per_frame <= 0 or wav.data.is_empty():
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = wav.data.size() / bytes_per_frame


func _play_sound(sound_name: String) -> void:
	if not sound_enabled or not _sound_players.has(sound_name):
		return
	var player: AudioStreamPlayer = _sound_players[sound_name]
	player.stop()
	player.play()


func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	_update_sound_button()
	if sound_enabled: _play_sound("select")
	_save_autosave()


func _update_sound_button() -> void:
	if is_instance_valid(_sound_button):
		_sound_button.text = "SOUND: ON" if sound_enabled else "SOUND: OFF"


func _toggle_music() -> void:
	music_enabled = not music_enabled
	if is_instance_valid(_music_player):
		if music_enabled:
			_music_player.stream_paused = false
			if not _music_player.playing: _music_player.play()
		else:
			_music_player.stream_paused = true
	_update_music_button()
	_save_autosave()


func _update_music_button() -> void:
	if is_instance_valid(_music_button):
		_music_button.text = "MUSIC: ON" if music_enabled else "MUSIC: OFF"


func _monitor_performance() -> void:
	var fps := Engine.get_frames_per_second()
	if is_instance_valid(_fps_label):
		_fps_label.text = "%d FPS • %s" % [fps, _effective_graphics_quality().to_upper()]
	if graphics_quality != "auto":
		_low_fps_seconds = 0
		return
	if fps > 0 and fps < 28:
		_low_fps_seconds += 1
	else:
		_low_fps_seconds = maxi(0, _low_fps_seconds - 1)
	if _low_fps_seconds >= 5:
		# Never replace piece nodes while a move tween or AI handoff owns them.
		if animating_move or ai_thinking:
			return
		var current := _effective_graphics_quality()
		# One step only, and it stops at MEDIUM. Falling to LOW turned off the
		# shadows and the anti-aliasing, which read as a broken board rather than
		# as a slower one.
		_auto_quality_override = "medium" if current == "high" else "medium"
		_low_fps_seconds = 0
		# Apply renderer settings now. Piece LOD refreshes after the next completed
		# move, avoiding node replacement during Android touch/tween dispatch.
		_apply_graphics_quality()
		_mesh_cache.clear()
		_needs_full_piece_rebuild = true


func _effective_graphics_quality() -> String:
	if graphics_quality != "auto":
		return graphics_quality
	if _auto_quality_override != "":
		return _auto_quality_override
	var cores := OS.get_processor_count()
	# The floor for AUTO is MEDIUM, never LOW: LOW disables the shadows that make
	# the pieces sit on the board.
	if cores <= 6:
		return "medium"
	return "high"


func _apply_graphics_quality() -> void:
	var quality := _effective_graphics_quality()
	capture_effects_enabled = quality != "low"
	decor_root.visible = quality != "low"
	# Shadows and MSAA are never traded away. AUTO used to fall all the way to
	# LOW, which switched both off and left the pieces floating on the board with
	# jagged edges; the drop now bottoms out at MEDIUM, and even a manually
	# selected LOW keeps 2x MSAA and the key light's shadows.
	$KeyLight.shadow_enabled = true
	# The fill casts at HIGH and not below. This is the brief's own rig and it
	# stays as written: the fill sits front-right and low, so its shadows fall
	# across the back half of the board and hold the pale squares just under the
	# clip point. Turning it off unconditionally was tried and measured - the
	# light squares went from #fdf6e1 to #fffffe and the near-white pixel count
	# went up tenfold, because with nothing in the grazing angle the fill reaches
	# every square at once. The rig is balanced against its own shadows.
	$FillLight.shadow_enabled = quality == "high"
	get_viewport().msaa_3d = Viewport.MSAA_2X
	match quality:
		"high":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		"medium":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_:
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_update_graphics_button()


func _cycle_graphics_quality() -> void:
	var levels := ["auto", "low", "medium", "high"]
	var index := levels.find(graphics_quality)
	graphics_quality = levels[(index + 1) % levels.size()]
	_auto_quality_override = ""
	_mesh_cache.clear()
	# Abandon any in-flight animation first: _create_pieces() destroys the very
	# node the tween is targeting, which would leave animating_move stuck on.
	_cancel_move_animation()
	_needs_full_piece_rebuild = false
	_apply_graphics_quality()
	_create_pieces()
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
	_apply_left_column_safe_area(safe, scale_x, scale_y, viewport_size)


## Records a left-hand HUD control so it can be inset from display cutouts.
func _register_left_column(control: Control) -> void:
	if control == null or _left_column_base.has(control):
		return
	_left_column_base[control] = control.position
	_left_column_nodes.append(control)


## Keeps the whole sidebar column clear of notches and gesture bars. The entire
## column is shifted as one block so the background panel and the controls it
## hosts stay aligned.
func _apply_left_column_safe_area(safe: Rect2i, scale_x: float, scale_y: float, viewport_size: Vector2) -> void:
	if _left_column_nodes.is_empty():
		return
	var window_size := Vector2(DisplayServer.window_get_size())
	var left_inset := maxf(0.0, safe.position.x * scale_x)
	var top_inset := maxf(0.0, safe.position.y * scale_y)
	var bottom_inset := maxf(0.0, (window_size.y - safe.end.y) * scale_y)
	var group_bottom := 0.0
	for node in _left_column_nodes:
		var base: Vector2 = _left_column_base.get(node, node.position)
		group_bottom = maxf(group_bottom, base.y + node.size.y)
	var shift_y := minf(top_inset, maxf(0.0, viewport_size.y - bottom_inset - group_bottom))
	for node in _left_column_nodes:
		var base: Vector2 = _left_column_base.get(node, node.position)
		node.position = Vector2(base.x + left_inset, base.y + shift_y)


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
		"sound_enabled": sound_enabled,
		"sound_volume": sound_volume,
		"music_enabled": music_enabled,
		"music_volume": music_volume,
		"high_contrast": high_contrast_enabled,
		"reduced_motion": reduced_motion_enabled,
		"coordinates": coordinates_enabled,
		"colorblind": colorblind_enabled,
		"large_text": large_text_enabled,
		"camera_yaw": camera_rig.rotation.y,
		"camera_distance": camera.position.length(),
		"camera_composition_version": 2,
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
	sound_enabled = bool(parsed.get("sound_enabled", true))
	sound_volume = clampf(float(parsed.get("sound_volume", 0.75)), 0.0, 1.0)
	music_enabled = bool(parsed.get("music_enabled", true))
	music_volume = clampf(float(parsed.get("music_volume", 0.28)), 0.0, 1.0)
	high_contrast_enabled = bool(parsed.get("high_contrast", false))
	reduced_motion_enabled = bool(parsed.get("reduced_motion", false))
	coordinates_enabled = bool(parsed.get("coordinates", true))
	colorblind_enabled = bool(parsed.get("colorblind", false))
	large_text_enabled = bool(parsed.get("large_text", false))
	camera_rig.rotation.y = float(parsed.get("camera_yaw", 0.0))
	# Beta 19 changes both lens and viewing angle. Do not apply a distance saved
	# for the old 42-degree lens, because it would recreate the old distortion.
	if int(parsed.get("camera_composition_version", 1)) >= 2:
		_set_camera_distance(float(parsed.get("camera_distance", camera.position.length())))
	play_vs_ai = bool(parsed.get("play_vs_ai", true))
	human_color = int(parsed.get("human_color", ChessRules.WHITE))
	ai_difficulty = parsed.get("ai_difficulty", "medium")
	if ai_difficulty not in ["easy", "medium", "hard", "professional"]:
		ai_difficulty = "medium"
	language = parsed.get("language", "en")
	if language not in ["en", "fa"]: language = "en"
	game.result = parsed.get("result", game.result)
	return true


func _undo() -> void:
	if ai_thinking or animating_move:
		return
	last_move.clear()
	# Taking moves back un-finishes a game, so it becomes archivable again.
	_archived_current_game = false
	if is_instance_valid(_game_over_dialog) and _game_over_dialog.visible:
		_game_over_dialog.hide()
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
	# Abandon any in-flight move animation first: _create_pieces() would destroy
	# the tweened node and leave animating_move stuck on, freezing all input.
	_cancel_move_animation()
	game.reset()
	_archived_current_game = false
	_needs_full_piece_rebuild = false
	last_move.clear()
	camera_rig.rotation.y = 0.0
	white_time = 600.0
	black_time = 600.0
	ai_generation += 1
	ai_thinking = false
	selected = Vector2i(-1, -1)
	selected_moves.clear()
	if is_instance_valid(_game_over_dialog) and _game_over_dialog.visible:
		_game_over_dialog.hide()
	_draw_highlights()
	_create_pieces()
	_update_status()
	_update_move_history()
	_update_captured_pieces()
	_save_autosave()


func _luxury_piece_material(color: Color, roughness: float, metallic: float, emissive := false, glossy := false, sheen := 0.30, figure: Texture2D = null, normal: Texture2D = null, bump_scale := 0.7, clearcoat := 0.40, clearcoat_roughness := 0.20) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = sheen
	material.clearcoat_enabled = glossy
	material.clearcoat = clearcoat
	material.clearcoat_roughness = clearcoat_roughness if glossy else 0.0
	# Explicit rather than left to the default: an emitting pale albedo is the
	# other way a white piece ends up as a glowing white silhouette.
	material.emission_enabled = emissive
	if figure != null:
		material.albedo_texture = figure
		# The same map drives roughness, so veining and grain also vary the
		# polish instead of only the colour.
		material.roughness_texture = figure
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if normal != null:
		material.normal_texture = normal
		material.normal_scale = bump_scale
	if emissive:
		material.emission_enabled = true
		material.emission = color * 0.32
		material.emission_energy_multiplier = 0.65
	return material


func _matte_material(color: Color, roughness: float, figure: Texture2D = null, normal: Texture2D = null, sheen := 0.04) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	# Board furniture is a surround, not a mirror. metallic_specular at its 0.5
	# default adds the direct specular lobe and the sky reflection on top of the
	# diffuse term, which is what pushed the pale squares and the ivory pieces
	# past 1.0 and clipped them to flat white under ACES.
	material.metallic_specular = sheen
	if figure != null:
		material.albedo_texture = figure
		material.roughness_texture = figure
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if normal != null:
		material.normal_texture = normal
		material.normal_scale = 0.7
	return material


func _material(color: Color, roughness: float, metallic: float, glossy := false, sheen := 0.10, figure: Texture2D = null, normal: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	material.metallic_specular = sheen
	material.clearcoat_enabled = glossy
	material.clearcoat_roughness = minf(0.65, roughness + 0.12)
	if figure != null:
		material.albedo_texture = figure
		material.roughness_texture = figure
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if normal != null:
		material.normal_texture = normal
		material.normal_scale = 0.7
	return material


## True while a modal layer owns the screen: the setup menu, the promotion
## picker, or one of the information windows.
func _modal_ui_is_open() -> bool:
	if is_instance_valid(_menu_overlay) and _menu_overlay.visible:
		return true
	if is_instance_valid(_promotion_popup):
		return true
	for window in [_archive_window, _accessibility_window, _tutorial_window, _about_window]:
		if is_instance_valid(window) and window.visible:
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Android delivers the hardware back button as ui_cancel (Escape) because
	# project.godot sets application/config/quit_on_go_back=false.
	if event.is_action_pressed("ui_cancel"):
		_handle_back_request()
		get_viewport().set_input_as_handled()
		return
	# input_devices/pointing/emulate_mouse_from_touch must stay enabled, because
	# builtin Control nodes only react to mouse events on a touch screen. It does
	# mean every tap also produces a synthetic mouse event, which carries
	# device == -1. Dropping those here is what keeps a single touch from being
	# handled twice: without it the camera spun twice as fast on a drag, and
	# dragging a piece also orbited the board.
	var pointer := event as InputEventMouse
	if pointer != null and pointer.device == -1:
		return
	# A tap on a HUD button or a dialog button must not also reach the board
	# underneath it. While a modal layer is up the scene is paused, so this is
	# belt-and-braces; it also covers a raw touch that a Control consumed.
	if (event is InputEventScreenTouch or event is InputEventScreenDrag) and _modal_ui_is_open():
		return
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
			piece.position = Vector3((_drag_piece_from.x - 3.5) * SQUARE_SIZE, 0.30, (_drag_piece_from.y - 3.5) * SQUARE_SIZE)
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
	tween.tween_property(camera_rig, "rotation:y", target_yaw, 0.01 if reduced_motion_enabled else 0.55)


func _reset_camera() -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var duration := 0.01 if reduced_motion_enabled else 0.35
	tween.tween_property(camera_rig, "rotation:y", 0.0, duration)
	tween.tween_property(camera, "position", Vector3(0, 9.8, 10.8), duration)
	_haptic(20)


func _haptic(duration_ms: int) -> void:
	if haptics_enabled:
		Input.vibrate_handheld(duration_ms)


## Walks out of the topmost thing on screen: promotion picker, then secondary
## windows, then the setup menu, and finally pauses back into the menu.
func _handle_back_request() -> void:
	if is_instance_valid(_promotion_popup):
		_promotion_popup.hide()
		return
	for window in [_archive_window, _accessibility_window, _tutorial_window, _about_window]:
		if is_instance_valid(window) and window.visible:
			window.hide()
			return
	if is_instance_valid(_menu_overlay) and _menu_overlay.visible:
		_continue_game()
		return
	if game.result == "":
		_show_main_menu()
