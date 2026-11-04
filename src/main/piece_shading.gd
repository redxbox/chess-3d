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
## Pure and static so that tests/test_chess.gd can check it on meshes it builds
## itself, with no scene and no renderer.

## How dark the deepest crease gets. 0.62 leaves the fold at a bit over a third
## of the surrounding stone: visible as a fold on the pale army, and on the dark
## army it is the difference between a robe and a black shape.
const DEPTH := 0.62


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
	# Weld by position, quantised to a tenth of a millimetre: the duplicated
	# vertices of a seam are identical in the export, but two vertices a hair
	# apart from the exporter's rounding must still be one point.
	var welded := {}
	var weld_of := PackedInt32Array()
	weld_of.resize(count)
	var weld_positions := PackedVector3Array()
	for i in count:
		var point := positions[i]
		var key := "%d,%d,%d" % [roundi(point.x * 10000.0), roundi(point.y * 10000.0), roundi(point.z * 10000.0)]
		if not welded.has(key):
			welded[key] = weld_positions.size()
			weld_positions.append(point)
		weld_of[i] = welded[key]

	# Neighbour sets, as welded indices. A triangle contributes all three of its
	# edges, so a crease made of two faces shares the vertices along it.
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

	# Curvature per welded point, then two smoothing passes over the same
	# adjacency. One pass leaves visible stair-stepping where the export's
	# triangles are uneven; two are enough to read as a soft shadow in the fold
	# and cost a single extra walk of the edges.
	#
	# The vertex's own normal is the average of the normals welded onto it,
	# because the duplicated copies face different ways along a hard edge.
	var weld_normals := _welded_normals(normals, weld_of, weld_positions.size())
	# Two rings, not one. A single ring measures the curvature of a single
	# triangle, which on these meshes is a few millimetres: it finds the groove
	# between two buttons and misses the fold a robe hangs in. At two rings the
	# average reaches far enough to see the fold - measured on the shipped
	# meshes, it is the difference between 4% and 25% of the silhouette carrying
	# a shadow.
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
	# Back onto the render vertices. The duplicated copies of a welded point keep
	# the vertex normal they were exported with - that is what makes a hard edge
	# hard - but they share the one shading value, so the seam cannot show.
	for i in count:
		# Linear, not squared. Squared was measured on these meshes and left the
		# folds at 0.83 of the stone: a tint, not a shadow. Linear puts the
		# deepest quarter of a sculpted figure at 0.74 and the flat faces at 1.0,
		# which is the contrast the carving needs to read at phone size. On a
		# turned piece, which is nearly all convex, it changes almost nothing.
		shade[i] = clampf(1.0 - DEPTH * concavity[weld_of[i]], 1.0 - DEPTH, 1.0)
	return shade


static func _welded_normals(normals: PackedVector3Array, weld_of: PackedInt32Array, welded_count: int) -> PackedVector3Array:
	var totals := PackedVector3Array()
	totals.resize(welded_count)
	for i in weld_of.size():
		totals[weld_of[i]] += normals[i]
	for w in welded_count:
		totals[w] = totals[w].normalized() if totals[w].length_squared() > 0.0000001 else Vector3.UP
	return totals
