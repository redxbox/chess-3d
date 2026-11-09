extends RefCounted

## A disk cache for the meshes this project builds at run time.
##
## Every piece is not shipped as a mesh: it is an OBJ with no UVs and no normals,
## and main.gd projects UVs onto it, welds its normals, generates tangents and
## bakes the cavity shading into vertex colours. That is a few hundred
## milliseconds per set of six - the first frame of a new launch pays it, and
## every launch paid it again, because the result lived only in memory and the
## style screen reloads the scene.
##
## So the finished `Mesh` is written to `user://` once and loaded back on the next
## launch. A warm start reads six resources instead of parsing six OBJs; the cost
## shows up once, on the first launch after install or after a version bump.
##
## Why a whole Mesh rather than just the shading table: the shading is a third of
## the work. The other two thirds are the OBJ parse, the welded normals and
## `generate_tangents()`, and all three live in exactly the same resource.
##
## The key carries a format version and the engine's version string, because a
## cached mesh is only valid for the code and the engine that produced it. A
## stale entry is deleted rather than trusted, and the caller simply rebuilds.
##
## `user://` is not a build artefact and never ships: the cache is per install.

## Bumped to 7 with the material-map sidecar: the pars set's colours changed from
## one sampled atlas colour per vertex to three materials and two palettes, so a
## 6 written by the previous build holds the camouflage this replaces.
##
## Bumped to 6 because a 5 written by the build that shipped without the `.tint`
## sidecars has the pars set baked into its vertex colours as white. The files are
## in the package now, but the cache outlives one install and would keep drawing
## the old colour until the next format change - so it is the format that changes.
##
## Bumped to 5 with the PARS set: a cached mesh now also carries the sculpture's
## own colours, read from `<kind>.tint` and multiplied into the shading, and its
## key gained the army because the two armies are the same body in two colours. A
## cache written by 4 has neither, so it would draw the coloured set in the
## palette white this round exists to replace.
##
## (4 was the sculpt-fields rewrite: the cavity bake moved to a three-ring patch,
## and a mesh cached by 3 carried the blotched shading that rewrite removed.)
##
## A cache is per install and free to rebuild; keeping a stale one is not.
const FORMAT := 7
const ROOT := "user://mesh_cache"


## The path a cache key maps to, including the format and engine version.
static func path_for(key: String) -> String:
	var engine := str(Engine.get_version_info().get("string", "unknown"))
	var stamp := "%s-%d" % [engine.validate_filename(), FORMAT]
	return "%s/%s/%s.res" % [ROOT, stamp, key.validate_filename()]


## The cached mesh, or null. Never raises: a cache that cannot be read is a
## cache miss, and the caller builds the mesh the slow way.
static func load_mesh(key: String) -> Mesh:
	var path := path_for(key)
	if not FileAccess.file_exists(path):
		return null
	var resource := ResourceLoader.load(path, "Mesh", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null or not (resource is Mesh):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return null
	var mesh := resource as Mesh
	if mesh.get_surface_count() == 0:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return null
	return mesh


## Writes a mesh, best effort. A cache that cannot be written costs a rebuild
## next launch and nothing else, so a failure here is silent by design: some
## Android builds hand the app a `user://` directory that is not yet writable on
## the first run.
static func save_mesh(key: String, mesh: Mesh) -> void:
	var path := path_for(key)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	ResourceSaver.save(mesh, path)


## Removes the whole cache - used when a format bump has to be cleaned up, and by
## the tests.
static func clear() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	if not DirAccess.dir_exists_absolute(root):
		return
	var versions := DirAccess.get_directories_at(root)
	for version in versions:
		var files := DirAccess.get_files_at(root + "/" + version)
		for file in files:
			DirAccess.remove_absolute(root + "/" + version + "/" + file)
		DirAccess.remove_absolute(root + "/" + version)


## How many bytes the cache is using, for the performance report.
static func size_bytes() -> int:
	var total := 0
	for version in DirAccess.get_directories_at(ProjectSettings.globalize_path(ROOT)):
		for file in DirAccess.get_files_at(ProjectSettings.globalize_path(ROOT) + "/" + version):
			var handle := FileAccess.open(ProjectSettings.globalize_path(ROOT) + "/" + version + "/" + file, FileAccess.READ)
			if handle:
				total += handle.get_length()
	return total
