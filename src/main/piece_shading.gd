extends RefCounted

## How much of a sculpted piece's carving is visible, baked once per mesh.
##
## The pieces are single-colour stone. Under a compatibility renderer there is no
## ambient occlusion pass, so a fold in a robe, the gap under a mane, the inside
## of a crown and the crevice between an arm and a body all receive the same
## amount of light as the surface facing the key - and the figure flattens into a
## silhouette painted one colour. That is what "the black side is not
## recognisable" looks like, and no amount of light energy fixes it: raising the
## lights to make the folds visible blows out the pale army instead.
##
## So the shading is measured from the geometry itself. For every vertex, the
## average direction to its neighbours tells you which way the surface curves
## there: on a convex bump the neighbours sit below the tangent plane and the
## average direction points back into the piece, opposite the normal; in a
## crease the neighbours rise around the vertex and the average points along the
## normal. That dot product is a curvature, and the concave half of it is exactly
## where a renderer with ambient occlusion would darken. Multiplying it into the
## vertex colour costs nothing at run time - it is one pass at load - and it is
## stable: the light rig can be retuned without the carving disappearing again.
##
## Cost. This is the only per-vertex CPU work in the project and it runs on six
## meshes per set (about 110 000 vertices in total), on the frame that builds the
## board. The first version of it allocated a Dictionary per vertex, a Dictionary
## per neighbour ring and a string key per welded point, and measured as several
## hundred milliseconds per set - the reason the style screen and the menu felt
## like they stuttered. It is now flat arrays throughout: welded points, edges,
## a CSR adjacency, and one integer-keyed dictionary for the weld and the edge
## dedupe. Same output, a fraction of the allocation.
##
## The result is cached twice over, in main.gd: the finished Mesh is written to
## user:// and loaded straight back on the next launch, and piece_shading's own
## output is memoised per source mesh, so a set is only ever measured once per
## process. See MeshCache.
##
## Pure and static so that tests/test_chess.gd can check it on meshes it builds
## itself, with no scene and no renderer.

## How dark the deepest crease gets.
##
## 0.68 leaves the deepest fold at about a third of the surrounding stone: visible
## as a fold on the pale army, and on the dark army it is the difference between
## a robe and a black shape. This is the project's ambient occlusion: the
## Compatibility renderer Godot 4 ships for Android has no SSAO pass, so the
## occlusion has to be baked, and it is baked here from the geometry.
const DEPTH := 0.68

## The weld precision, as steps per unit: a tenth of a millimetre.
const WELD_STEPS := 10000.0


## Per-vertex shading multipliers in [1 - DEPTH, 1], one per vertex.
##
## `positions`, `normals` and `indices` are a triangle surface as imported. The
## export duplicates vertices along every facet, so adjacency is built on welded
## positions: without welding, every vertex would appear to have no neighbours
## across the seam and those seams would light up as bright lines.
static func cavity_shade(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> PackedFloat32Array:
	var count := positions.size()
	var shade := PackedFloat32Array()
	shade.resize(count)
	shade.fill(1.0)
	if count == 0 or normals.size() != count or indices.size() < 3:
		return shade

	# --- weld ---------------------------------------------------------------
	# One integer-keyed dictionary instead of a string per vertex. The exported
	# duplicate of a seam vertex is bit-identical, and two vertices a hair apart
	# from the exporter's rounding still land on the same integer key.
	var weld_lookup := {}
	var weld_of := PackedInt32Array()
	weld_of.resize(count)
	var weld_positions := PackedVector3Array()
	weld_positions.resize(count)
	var welded_count := 0
	for i in count:
		var point := positions[i]
		var key := Vector3i(
			roundi(point.x * WELD_STEPS),
			roundi(point.y * WELD_STEPS),
			roundi(point.z * WELD_STEPS))
		var welded: int = weld_lookup.get(key, -1)
		if welded < 0:
			welded = welded_count
			weld_lookup[key] = welded
			weld_positions[welded] = point
			welded_count += 1
		weld_of[i] = welded
	weld_positions.resize(welded_count)

	# --- edges, deduplicated ------------------------------------------------
	var edge_lookup := {}
	var edge_from := PackedInt32Array()
	var edge_to := PackedInt32Array()
	# The three edges of a triangle are written out rather than looped over an
	# array of pairs: this runs 40 000 times per mesh and an allocated pair array
	# per triangle is the difference between a fast pass and a slow one.
	for triangle in range(0, indices.size() - 2, 3):
		var a := weld_of[indices[triangle]]
		var b := weld_of[indices[triangle + 1]]
		var c := weld_of[indices[triangle + 2]]
		for step in 3:
			var from: int = a if step == 0 else (b if step == 1 else c)
			var to: int = b if step == 0 else (c if step == 1 else a)
			if from == to:
				continue
			var key: int = from * welded_count + to if from < to else to * welded_count + from
			if edge_lookup.has(key):
				continue
			edge_lookup[key] = true
			edge_from.append(from)
			edge_to.append(to)

	# --- CSR adjacency ------------------------------------------------------
	var degree := PackedInt32Array()
	degree.resize(welded_count)
	for e in edge_from.size():
		degree[edge_from[e]] += 1
		degree[edge_to[e]] += 1
	var offsets := PackedInt32Array()
	offsets.resize(welded_count + 1)
	for w in welded_count:
		offsets[w + 1] = offsets[w] + degree[w]
	var fill := offsets.duplicate()
	var adjacency := PackedInt32Array()
	adjacency.resize(offsets[welded_count])
	for e in edge_from.size():
		var from := edge_from[e]
		var to := edge_to[e]
		adjacency[fill[from]] = to
		fill[from] += 1
		adjacency[fill[to]] = from
		fill[to] += 1

	# --- welded normals -----------------------------------------------------
	# The vertex's own normal is the average of the normals welded onto it,
	# because the duplicated copies face different ways along a hard edge.
	var weld_normals := PackedVector3Array()
	weld_normals.resize(welded_count)
	for i in count:
		weld_normals[weld_of[i]] += normals[i]
	for w in welded_count:
		weld_normals[w] = weld_normals[w].normalized() if weld_normals[w].length_squared() > 0.0000001 else Vector3.UP

	# --- two-ring neighbourhood, then curvature -----------------------------
	# Two rings, not one. A single ring measures the curvature of a single
	# triangle, which on these meshes is a few millimetres: it finds the groove
	# between two buttons and misses the fold a robe hangs in. At two rings the
	# average reaches far enough to see the fold - measured on the shipped
	# meshes, it is the difference between 4% and 25% of the silhouette carrying
	# a shadow.
	#
	# The ring is deduplicated with a stamp array rather than a Dictionary: a
	# vertex id written into `ring_stamp` with the current token is already in
	# the ring, which is one integer compare instead of a hash insert.
	var ring_stamp := PackedInt32Array()
	ring_stamp.resize(welded_count)
	ring_stamp.fill(-1)
	# Preallocated once at the largest a ring can be (every other welded point).
	# Writing past the end of a packed array is an error, not a resize, so this
	# has to be sized up front.
	var ring := PackedInt32Array()
	ring.resize(welded_count)
	ring.fill(0)
	var concavity := PackedFloat32Array()
	concavity.resize(welded_count)
	for w in welded_count:
		var ring_size := 0
		ring_stamp[w] = w
		for first in range(offsets[w], offsets[w + 1]):
			var other := adjacency[first]
			if ring_stamp[other] == w:
				continue
			ring_stamp[other] = w
			ring[ring_size] = other
			ring_size += 1
		var first_end := ring_size
		for index in first_end:
			var through := ring[index]
			for second in range(offsets[through], offsets[through + 1]):
				var far := adjacency[second]
				if ring_stamp[far] == w:
					continue
				ring_stamp[far] = w
				ring[ring_size] = far
				ring_size += 1
		if ring_size == 0:
			continue
		var away := Vector3.ZERO
		for index in ring_size:
			var delta := weld_positions[ring[index]] - weld_positions[w]
			if delta.length_squared() > 0.0000000001:
				away += delta.normalized()
		if away.length_squared() < 0.0000000001:
			continue
		concavity[w] = clampf(float(away.normalized().dot(weld_normals[w])), 0.0, 1.0)

	# --- smoothing ----------------------------------------------------------
	# Two passes over the same adjacency. One pass leaves visible stair-stepping
	# where the export's triangles are uneven; two are enough to read as a soft
	# shadow in the fold and cost a single extra walk of the edges.
	for pass_index in 2:
		var smoothed := concavity.duplicate()
		for w in welded_count:
			var total := 0.0
			var neighbours := offsets[w + 1] - offsets[w]
			if neighbours == 0:
				continue
			for index in range(offsets[w], offsets[w + 1]):
				total += concavity[adjacency[index]]
			smoothed[w] = (concavity[w] * 2.0 + total / float(neighbours)) / 3.0
		concavity = smoothed

	# --- back onto the render vertices --------------------------------------
	# The duplicated copies of a welded point keep the vertex normal they were
	# exported with - that is what makes a hard edge hard - but they share the
	# one shading value, so the seam cannot show.
	#
	# Linear, not squared. Squared was measured on these meshes and left the
	# folds at 0.83 of the stone: a tint, not a shadow. Linear puts the deepest
	# quarter of a sculpted figure at 0.74 and the flat faces at 1.0, which is
	# the contrast the carving needs to read at phone size. On a turned piece,
	# which is nearly all convex, it changes almost nothing.
	for i in count:
		shade[i] = clampf(1.0 - DEPTH * concavity[weld_of[i]], 1.0 - DEPTH, 1.0)
	return shade


## The first implementation of the bake, kept as a reference.
##
## It computes the same thing by the same definition - welded positions, a
## two-ring neighbourhood, the same two smoothing passes, the same linear remap -
## but with a Dictionary per vertex, a Dictionary per ring and a string key per
## welded point. It cost several hundred milliseconds per set, which is what the
## style screen's stutter was.
##
## It is not dead code: tests/test_chess.gd checks that the shipped fast version
## produces the same shading on the same mesh, and tools/bench_perf.gd times both
## so the speed-up is a measured number rather than a claim.
static func cavity_shade_reference(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> PackedFloat32Array:
	var count := positions.size()
	var shade := PackedFloat32Array()
	shade.resize(count)
	shade.fill(1.0)
	if count == 0 or normals.size() != count or indices.size() < 3:
		return shade
	var welded := {}
	var weld_of := PackedInt32Array()
	weld_of.resize(count)
	var weld_positions := PackedVector3Array()
	for i in count:
		var point := positions[i]
		var key := "%d,%d,%d" % [roundi(point.x * WELD_STEPS), roundi(point.y * WELD_STEPS), roundi(point.z * WELD_STEPS)]
		if not welded.has(key):
			welded[key] = weld_positions.size()
			weld_positions.append(point)
		weld_of[i] = welded[key]
	var neighbours: Array = []
	neighbours.resize(weld_positions.size())
	for i in neighbours.size():
		neighbours[i] = {}
	for triangle in range(0, indices.size() - 2, 3):
		var a := weld_of[indices[triangle]]
		var b := weld_of[indices[triangle + 1]]
		var c := weld_of[indices[triangle + 2]]
		(neighbours[a] as Dictionary)[b] = true
		(neighbours[a] as Dictionary)[c] = true
		(neighbours[b] as Dictionary)[a] = true
		(neighbours[b] as Dictionary)[c] = true
		(neighbours[c] as Dictionary)[a] = true
		(neighbours[c] as Dictionary)[b] = true
	var weld_normals := PackedVector3Array()
	weld_normals.resize(weld_positions.size())
	for i in count:
		weld_normals[weld_of[i]] += normals[i]
	for w in weld_positions.size():
		weld_normals[w] = weld_normals[w].normalized() if weld_normals[w].length_squared() > 0.0000001 else Vector3.UP
	var ring: Array = []
	ring.resize(weld_positions.size())
	for w in weld_positions.size():
		var first: Dictionary = neighbours[w]
		var extended := {}
		for other in first:
			extended[other] = true
			for second in (neighbours[other] as Dictionary):
				extended[second] = true
		extended.erase(w)
		ring[w] = extended
	var concavity := PackedFloat32Array()
	concavity.resize(weld_positions.size())
	for w in weld_positions.size():
		var list: Array = (ring[w] as Dictionary).keys()
		if list.is_empty():
			continue
		var away := Vector3.ZERO
		for other in list:
			var delta: Vector3 = weld_positions[other] - weld_positions[w]
			if delta.length_squared() > 0.0000000001:
				away += delta.normalized()
		if away.length_squared() < 0.0000000001:
			continue
		concavity[w] = clampf(float(away.normalized().dot(weld_normals[w])), 0.0, 1.0)
	for pass_index in 2:
		var smoothed := concavity.duplicate()
		for w in weld_positions.size():
			var list: Array = (neighbours[w] as Dictionary).keys()
			if list.is_empty():
				continue
			var total := 0.0
			for other in list:
				total += concavity[other]
			smoothed[w] = (concavity[w] * 2.0 + total / float(list.size())) / 3.0
		concavity = smoothed
	for i in count:
		shade[i] = clampf(1.0 - DEPTH * concavity[weld_of[i]], 1.0 - DEPTH, 1.0)
	return shade
