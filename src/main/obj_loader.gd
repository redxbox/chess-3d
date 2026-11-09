extends RefCounted

## Reads a piece body straight out of its `.obj` file instead of letting Godot
## import it.
##
## WHY THIS EXISTS
## ---------------
## The pars set carries one byte per vertex in `<kind>.tint`, in the vertex order
## of the OBJ file. That is a promise about the *file*, and Godot's OBJ importer
## does not keep it: it walks the faces and builds its own vertex array as it
## goes (so vertices come out in face order, not file order), and it can reorder
## that array again to optimise the vertex cache. Vertex 3004 of the imported
## mesh is therefore almost never vertex 3004 of the file.
##
## The consequence is not subtle. The first two versions of the pars colour bake
## were blamed for the camouflage on the phone - a leopard print of gold, silver
## and maroon - and the sidecars were fine both times: the material map was clean
## in file order and the game was applying it to a different vertex order. With
## three materials and a fixed share for each, the same mismatch reads as
## confetti.
##
## So for a set that carries per-vertex data, the file is the authority and this
## parses it. Everything downstream - welding normals, projecting UVs, generating
## tangents - is unchanged and still runs on the arrays this returns.
##
## The parse is deliberately small: `v` and `f` are the only records these files
## contain (tools/prepare_sculpt_set.py writes them and nothing else), and the
## result is cached by MeshCache like any other built mesh, so this runs on a cold
## start only.

const PRECISION := 4


## The positions and triangle indices of one body, in file order.
##
## `positions` has exactly one entry per `v` line, in the order they appear, and
## `indices` refers to them with the OBJ's one-based numbering removed. That
## one-to-one correspondence is the whole point of this file: it is what lets a
## sidecar say "vertex 3004 is gilded" and mean it.
static func load_arrays(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open %s" % path)
		return {}
	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	while not file.eof_reached():
		var line := file.get_line()
		if line.length() < 2:
			continue
		var entry := line[0]
		if entry == "v" and line[1] == " ":
			var parts := line.split(" ", false)
			if parts.size() < 4:
				continue
			positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif entry == "f" and line[1] == " ":
			# `f a b c`, and `f a/t/n b/t/n c/t/n` if a future export adds them:
			# only the first field is the vertex, which is all a face needs here.
			var corners := line.split(" ", false)
			if corners.size() < 4:
				continue
			var face := PackedInt32Array()
			for i in range(1, corners.size()):
				var token := corners[i].get_slice("/", 0)
				var index := token.to_int() - 1
				# Negative indices are relative to the end of the list, and a
				# zero is a parse failure rather than a vertex.
				if token.begins_with("-"):
					index = positions.size() + index
				if index < 0 or index >= positions.size():
					face = PackedInt32Array()
					break
				face.append(index)
			if face.size() == 3:
				indices.append_array(face)
			elif face.size() > 3:
				# A quad or an n-gon: fan it, which is what the importer does too.
				for k in range(1, face.size() - 1):
					indices.append(face[0])
					indices.append(face[k])
					indices.append(face[k + 1])
	file.close()
	if positions.is_empty() or indices.is_empty():
		push_error("%s has no geometry" % path)
		return {}
	return {"positions": positions, "indices": indices}
