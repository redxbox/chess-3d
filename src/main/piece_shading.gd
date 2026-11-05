extends RefCounted

## How much of a sculpted piece's carving is visible, baked once per mesh - and
## which of its ornaments are metal.
##
## The pieces are single-colour stone. Under a compatibility renderer there is no
## ambient occlusion pass, so a fold in a robe, the gap under a mane, the inside
## of a crown and the crevice between an arm and a body all receive the same
## amount of light as the surface facing the key - and the figure flattens into a
## silhouette painted one colour.
##
## So the shading is measured from the geometry itself: mean curvature per vertex,
## from the average direction to its neighbours. The concave half of it is where a
## renderer with ambient occlusion would darken; the convex half is where a
## highlighted edge would catch the light.
##
## ## What changed, and why
##
## The first version measured curvature over a single triangle's neighbourhood and
## remapped whatever it found across the full range. Two things were wrong with
## that, and together they are exactly the "dirty blotches" the figurative set was
## reported with:
##
##   1. One ring is a few millimetres. On a decimated sculpt the triangles are
##      irregular, so a one-ring measurement reports the tessellation as much as
##      the form - and normalising a near-cancelling sum (flat ground is 0 +/- 0.1)
##      amplifies that noise into the blobs.
##   2. A hard remap puts every irregularity at full strength somewhere, so there
##      is no "this is a fold" versus "this is a facet".
##
## It is measured over a three-ring patch now (about a centimetre on these meshes,
## which is the scale of a fold of drapery rather than of a triangle), the sum is
## divided by the patch's own radius so the value is a real 1/unit curvature
## instead of a normalised one, and it is thresholded with a smoothstep rather
## than stretched. Then the occlusion is blurred over the same adjacency, because
## a crease that darkens only along the exact line of the valley reads as a
## scratch rather than as a shadow.
##
## ## Two fields, one pass
##
## `sculpt_fields()` returns both:
##
##   * `shade` - 1.0 on open stone, down to `1 - DEPTH` in the deepest crease.
##     Multiplied into the vertex colour's rgb.
##   * `gild`  - 0.0 on stone, 1.0 on an ornament that should be metal: the tips
##     and edges of the carving, which is where a gilded statuette is gilded -
##     crowns, sceptre heads, spear tips, a griffin's beak, the ridge of a mane.
##     main.gd builds a second surface from the vertices where this is high.
##
## The gild mask is the convex half of the same measurement, which is what makes
## it land on edges rather than on faces. It is suppressed over each piece's
## plinth: a statuette's base is stone, and a gold ring at the bottom of every
## piece reads as a band of paint rather than as ornament.
##
## Pure and static so tests/test_chess.gd can check it on meshes it builds itself,
## with no scene and no renderer.

## How dark the deepest crease gets.
const DEPTH := 0.60

## The weld precision, as steps per unit: a tenth of a millimetre.
const WELD_STEPS := 10000.0

## How far the curvature is measured, in rings of adjacency. Three rings on these
## meshes is about a centimetre and a half of surface - a fold, a flute, the
## moulding round a crown - where one ring is a single triangle.
const RINGS := 3

## How many times the curvature, the occlusion and the gild mask are diffused
## over the mesh. The diffusion is what turns per-triangle noise into a smooth
## gradient; it is the single most important number in this file.
const CURVATURE_PASSES := 3
const OCCLUSION_PASSES := 2
const GILD_PASSES := 1

## Curvature thresholds, in 1/unit, applied with a smoothstep (so the transition
## itself is smooth rather than a hard cut).
##
## Measured on the bastani set: a smooth robe reads 0.2-0.6, a fold 1-3, the
## groove beside a fluted column 4-8, the tip of a spear or a crown point 3-15.
## The occlusion band starts where folds are and the gild band where edges are.
##
## One fixture matters for both bands, because it is what they were tuned on: two
## planes meeting along an edge at 90 degrees, which is the shape of a fold of
## drapery and of a crown point, drawn analytically in tests/test_chess.gd. Turned
## into a valley it paints 0.46 at the crease and leaves 90% of the sheet at 1.00
## - a shadow with an edge, not a tint. A smooth dome of the same size stays at
## 1.00 either way: a hollow is not a fold.
##
## Curvature is per unit, so the same shape at ornament scale reads several times
## tighter than at drapery scale. The gild band is set for ornament - a crown
## point is two or three millimetres across on a piece 1.3 units tall - which is
## why the test's ridge is a quarter of the size of its fold. The first band, at
## 0.8, gilded a fifth of every figure: shoulders, hands and the flat of a shield,
## which is gold leaf thrown at the model rather than an ornament picked out.
##
## The earlier bands left the same valley at 0.92, which is the "blurry" half of
## the complaint, and no amount of gilding on top of it fixes that.
const CONCAVE_LOW := 0.4
const CONCAVE_HIGH := 2.2
const CONVEX_LOW := 2.4
const CONVEX_HIGH := 6.4

## The fraction of a piece's height occupied by its plinth, above which the gild
## mask is allowed. Per kind, because a column's base is proportionally taller
## than a figure's. Anything at or below this is stone.
const PLINTH_TOP := 0.20
## And the band it takes to ramp in, so the gold does not start on a hard line.
const PLINTH_FADE := 0.08


## Both fields for one surface.
##
## `plinth_fraction` is the top of the base, as a fraction of the piece's height;
## `gild_strength` scales the whole mask, so a set can ask for less metal without
## changing thresholds.
static func sculpt_fields(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, plinth_fraction := PLINTH_TOP, gild_strength := 1.0) -> Dictionary:
	var count := positions.size()
	var shade := PackedFloat32Array()
	shade.resize(count)
	shade.fill(1.0)
	var gild := PackedFloat32Array()
	gild.resize(count)
	gild.fill(0.0)
	if count == 0 or normals.size() != count or indices.size() < 3:
		return {"shade": shade, "gild": gild}

	# --- weld ---------------------------------------------------------------
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

	# --- edges and CSR adjacency -------------------------------------------
	var edge_lookup := {}
	var edge_from := PackedInt32Array()
	var edge_to := PackedInt32Array()
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
	var weld_normals := PackedVector3Array()
	weld_normals.resize(welded_count)
	for i in count:
		weld_normals[weld_of[i]] += normals[i]
	for w in welded_count:
		weld_normals[w] = weld_normals[w].normalized() if weld_normals[w].length_squared() > 0.0000001 else Vector3.UP

	# --- curvature over a RINGS-wide patch ----------------------------------
	# A breath-first expansion, with the visited set kept in a stamp array: a
	# vertex is in this patch if its stamp equals the current token, which is one
	# integer compare instead of a hash insert. The queue and the stamp array are
	# allocated once and reused for every vertex.
	var stamp := PackedInt32Array()
	stamp.resize(welded_count)
	stamp.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(welded_count)
	var curvature := PackedFloat32Array()
	curvature.resize(welded_count)
	for w in welded_count:
		var token := w
		stamp[w] = token
		var size := 0
		for first in range(offsets[w], offsets[w + 1]):
			var other := adjacency[first]
			if stamp[other] == token:
				continue
			stamp[other] = token
			queue[size] = other
			size += 1
		var head := 0
		for depth in range(1, RINGS):
			var boundary := size
			while head < boundary:
				var through := queue[head]
				head += 1
				for index in range(offsets[through], offsets[through + 1]):
					var far := adjacency[index]
					if stamp[far] == token:
						continue
					stamp[far] = token
					queue[size] = far
					size += 1
			if size == boundary:
				break
		if size == 0:
			continue
		# The mean of the unit vectors to the patch, projected on the normal, is
		# the sine of the mean slope of the patch; dividing by the patch's own
		# mean radius turns it into 1/unit. Flat ground gives 0, a crease gives a
		# positive number, a ridge a negative one - and the division is what keeps
		# the value comparable between a wide robe and a narrow spear, which a
		# normalised dot product cannot do.
		var away := Vector3.ZERO
		var reach := 0.0
		for index in size:
			var delta := weld_positions[queue[index]] - weld_positions[w]
			var length := delta.length()
			if length > 0.0000001:
				away += delta / length
				reach += length
		if reach <= 0.0000001:
			continue
		away /= float(size)
		reach /= float(size)
		curvature[w] = away.dot(weld_normals[w]) / reach

	for pass_index in CURVATURE_PASSES:
		var smoothed := curvature.duplicate()
		for w in welded_count:
			var neighbours := offsets[w + 1] - offsets[w]
			if neighbours == 0:
				continue
			var total := 0.0
			for index in range(offsets[w], offsets[w + 1]):
				total += curvature[adjacency[index]]
			smoothed[w] = (curvature[w] * 2.0 + total / float(neighbours)) / 3.0
		curvature = smoothed

	# --- the two fields -----------------------------------------------------
	var occlusion := PackedFloat32Array()
	occlusion.resize(welded_count)
	var metal := PackedFloat32Array()
	metal.resize(welded_count)
	var lowest := INF
	var highest := -INF
	for w in welded_count:
		lowest = minf(lowest, weld_positions[w].y)
		highest = maxf(highest, weld_positions[w].y)
	var span := maxf(0.0001, highest - lowest)
	for w in welded_count:
		occlusion[w] = smoothstep(CONCAVE_LOW, CONCAVE_HIGH, curvature[w])
		# The plinth is stone. The mask is faded in over PLINTH_FADE of the piece's
		# height so the gold does not begin on a hard line across the base.
		var height := (weld_positions[w].y - lowest) / span
		var above_base := smoothstep(plinth_fraction, plinth_fraction + PLINTH_FADE, height)
		metal[w] = smoothstep(CONVEX_LOW, CONVEX_HIGH, -curvature[w]) * above_base * gild_strength

	for pass_index in OCCLUSION_PASSES:
		var blurred := occlusion.duplicate()
		for w in welded_count:
			var neighbours := offsets[w + 1] - offsets[w]
			if neighbours == 0:
				continue
			var total := 0.0
			for index in range(offsets[w], offsets[w + 1]):
				total += occlusion[adjacency[index]]
			blurred[w] = (occlusion[w] * 2.0 + total / float(neighbours)) / 3.0
		occlusion = blurred
	for pass_index in GILD_PASSES:
		var blurred := metal.duplicate()
		for w in welded_count:
			var neighbours := offsets[w + 1] - offsets[w]
			if neighbours == 0:
				continue
			var total := 0.0
			for index in range(offsets[w], offsets[w + 1]):
				total += metal[adjacency[index]]
			blurred[w] = (metal[w] * 2.0 + total / float(neighbours)) / 3.0
		metal = blurred

	for i in count:
		shade[i] = clampf(1.0 - DEPTH * occlusion[weld_of[i]], 1.0 - DEPTH, 1.0)
		gild[i] = clampf(metal[weld_of[i]], 0.0, 1.0)
	return {"shade": shade, "gild": gild}


## Just the occlusion, for callers that do not care about the metal mask.
static func cavity_shade(positions: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array) -> PackedFloat32Array:
	return sculpt_fields(positions, normals, indices)["shade"]


## The vertices of `indices` whose gild weight is at or above `threshold`, as a
## new index array - the triangles of the gilded ornaments.
##
## A triangle is taken whole or not at all: a mask sampled per vertex on a
## half-covered triangle would tear a hole in the stone where the gold ends, and
## the two surfaces would show a seam along every trim edge.
static func gilded_indices(indices: PackedInt32Array, gild: PackedFloat32Array, threshold := 0.5) -> PackedInt32Array:
	var out := PackedInt32Array()
	if gild.size() == 0:
		return out
	for triangle in range(0, indices.size() - 2, 3):
		var a := indices[triangle]
		var b := indices[triangle + 1]
		var c := indices[triangle + 2]
		var weight := (gild[a] + gild[b] + gild[c]) / 3.0
		if weight >= threshold:
			out.append(a)
			out.append(b)
			out.append(c)
	return out
