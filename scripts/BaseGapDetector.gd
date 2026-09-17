class_name BaseGapDetector
extends RefCounted

## Fraction of the mesh's own total height (not a fixed absolute number) -
## fixed 2026-09-17 after a real bug: this project's monster meshes vary in
## raw local scale by roughly 150x (some ~0.015 units tall, others ~2.4,
## per each monster's own scale_factor calibration elsewhere in this
## project), so a fixed absolute tolerance like the old `0.01` covered
## anywhere from 0.4% to 69% of a given mesh's own height depending on
## which monster it was - nowhere close to "the base disc" for the
## small-scale meshes, even though it happened to not crash for them.
const FLOOR_TOLERANCE_PCT := 0.01

## Returns a Dictionary with `outer_a`/`outer_b`/`inner_a`/`inner_b`
## (Vector3, local mesh space - `outer_a`/`outer_b` are the two floor-level
## vertices bordering the gap; `inner_a`/`inner_b` are the same X/Z, bumped
## `wall_height_local` further along local "up") on success, or an empty
## Dictionary if no gap could be found (mesh has too few floor vertices to
## trace a ring - never throws, same "return empty/null, let the caller
## skip gracefully" convention `MonsterDisplay._build_real_figure()`
## already uses for a missing mesh). `basis` should be the SAME rotation
## `MonsterDisplay` applies to the figure (pitch_correction +
## extra_rotation_degrees - a SCALE component is harmless too if present,
## since the "up" direction derived from it is explicitly normalized below,
## but only rotation is actually needed) - purely for internal floor/angle
## analysis and to know which local direction counts as "up" when
## synthesizing the inner corners; the returned points stay in the mesh's
## own untouched local space either way, so `wall_height_local` must
## already be in that same local scale (see this file's own class doc for
## why that's now the caller's job, not a percentage computed in here).
static func detect_gap_quad(mesh: Mesh, basis: Basis, wall_height_local: float) -> Dictionary:
	var positions := PackedVector3Array()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			positions.append(v)

	if positions.size() < 5:
		return {}

	var rotated := PackedVector3Array()
	rotated.resize(positions.size())
	for i in positions.size():
		rotated[i] = basis * positions[i]

	var min_y := INF
	var max_y := -INF
	for v in rotated:
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)
	var height: float = max_y - min_y
	var floor_max_y: float = min_y + height * FLOOR_TOLERANCE_PCT

	var floor_indices: Array = []
	for i in rotated.size():
		if rotated[i].y <= floor_max_y:
			floor_indices.append(i)
	if floor_indices.size() < 5:
		return {}

	# Centroid of the FLOOR RING ITSELF, not the mesh's raw local origin -
	# a mesh's local (0,0) is NOT guaranteed to sit at the center of its own
	# base disc. Confirmed as the actual cause of a real follow-up bug: the
	# -INF fix below stopped every pitch_correction_degrees == 0 monster
	# (Berserker/Blood Sister/Golem/Specter/Wolf/Zealot) from crashing, but
	# their quadrant split was still measured against raw (0,0) - since
	# their entire floor ring sits at z <= 0 in local space (their origin
	# sits toward the FRONT of the model, not centered under the base), the
	# "highest z" each side found was just whichever floor vertex happened
	# to be LEAST far back, not anywhere near a real notch - confirmed by
	# direct user report after rendering ("i think that the ones that are
	# fixed look bad"). Splitting by (x - cx)/(z - cz) against this
	# computed center instead makes the quadrant logic work regardless of
	# where the mesh's own local origin happens to sit.
	var cx := 0.0
	var cz := 0.0
	for i in floor_indices:
		cx += rotated[i].x
		cz += rotated[i].z
	cx /= floor_indices.size()
	cz /= floor_indices.size()

	var gap_before_idx := -1
	var gap_after_idx := -1

	var max_z: float

	# find the index (gap_before_idx) of vertex on floor level with higest z coordinates in 3 quadrant x < 0
	# Starts at -INF, not 0.0 - a mesh whose local origin doesn't happen to
	# sit centered under its own base would otherwise never find a
	# candidate here, silently leaving gap_before_idx at -1.
	max_z = -INF
	for i in floor_indices:
		if rotated[i].x < cx and rotated[i].z - cz > max_z:
			max_z = rotated[i].z - cz
			gap_before_idx = i

	# find the index (gap_after_idx) of vertex on floor level with higest z coordinates in 4 quadrant x > 0
	max_z = -INF
	for i in floor_indices:
		if rotated[i].x > cx and rotated[i].z - cz > max_z:
			max_z = rotated[i].z - cz
			gap_after_idx = i

	# `positions[-1]` is a SILENT success in GDScript (negative array
	# indexing resolves to the last element) rather than an error - without
	# this check, a mesh where one side never finds a candidate would
	# return some totally unrelated vertex as outer_a/outer_b instead of
	# failing loudly or gracefully. Confirmed as the actual cause of a real
	# bug: every pitch_correction_degrees == 0 monster (Berserker/Blood
	# Sister/Golem/Specter/Wolf/Zealot) hit exactly this path.
	if gap_before_idx == -1 or gap_after_idx == -1:
		return {}

	var outer_a: Vector3 = positions[gap_before_idx]
	var outer_b: Vector3 = positions[gap_after_idx]

	# Synthesize the inner corners directly above the outer ones - same
	# local X/Z, bumped `wall_height_local` along whatever local axis "up"
	# maps to once `basis` is applied. Explicitly `.normalized()` - `basis`
	# may carry a uniform scale (MonsterDisplay's callers pass figure.basis,
	# which does), and since `wall_height_local` is already the exact local
	# distance to move (not a ratio that needs re-scaling), a non-unit
	# direction vector here would silently shrink/grow the bump by whatever
	# scale factor happens to be baked into `basis` - normalizing removes
	# that dependency entirely, matching this function's own contract that
	# `wall_height_local` is used exactly as given.
	var local_up: Vector3 = (basis.inverse() * Vector3.UP).normalized()
	var bump: Vector3 = local_up * wall_height_local

	return {
		"outer_a": outer_a,
		"outer_b": outer_b,
		"inner_a": outer_a + bump,
		"inner_b": outer_b + bump,
	}
