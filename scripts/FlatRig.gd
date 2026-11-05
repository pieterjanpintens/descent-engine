class_name FlatRig
extends RefCounted

## EXPERIMENT (2026-11-05): a figure's rigged "flat" model with the game's own idle animation. The data is `flat_rig.json`, written next to the
## static meshes by tools/asset_import/import_flat_rig.py (skeleton, skin weights, bind poses, sampled idle keyframes - see that tool).
## `build()` makes a Node3D holding a Skeleton3D (+ the skinned MeshInstance3D) and an AnimationPlayer that loops the idle.

const RIG_FILE := "flat_rig.json"
const SKELETON_NAME := "Skeleton"

## Switch for the animated figures (the static meshes are used when false).
static var enabled := true
static var _cache := {}  # json path -> parsed Dictionary


## The rig file that belongs to a static mesh path (same folder), or "" when there is none.
static func rig_beside(mesh_path: String) -> String:
	var path := mesh_path.get_base_dir() + "/" + RIG_FILE
	return path if enabled and FileAccess.file_exists(path) else ""


## {node: Node3D, aabb: AABB} - the AABB is the rest pose's (the mesh as stored). Empty when the file can't be used.
static func build(path: String, material: Material) -> Dictionary:
	var data := _load(path)
	if data.is_empty():
		return {}
	var skeleton := Skeleton3D.new()
	skeleton.name = SKELETON_NAME
	var bones: Array = data["bones"]
	var names: Array[String] = []
	for i in bones.size():
		var name := str(bones[i]["name"])
		if names.has(name):
			name = "%s_%d" % [name, i]  # bone names must be unique
		names.append(name)
		skeleton.add_bone(name)
	for i in bones.size():
		var b: Dictionary = bones[i]
		skeleton.set_bone_parent(i, int(b["parent"]))
		var rest := _transform(b["pos"], b["rot"], b["scl"])
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, rest.basis.get_scale())

	var skin := Skin.new()
	var slot_bones: Array = data["skin"]["bones"]
	var bind: Array = data["skin"]["bind"]
	skin.set_bind_count(slot_bones.size())
	for slot in slot_bones.size():
		skin.set_bind_bone(slot, int(slot_bones[slot]))
		skin.set_bind_pose(slot, _bind_pose(bind, slot))

	var mesh := _mesh(data["mesh"])
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.skin = skin
	instance.set_surface_override_material(0, material)
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")

	var root := Node3D.new()
	root.add_child(skeleton)
	var player := AnimationPlayer.new()
	root.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation("idle", _animation(data["anim"], bones, names))
	player.add_animation_library("", library)
	player.root_node = NodePath("..")
	player.play("idle")
	return {"node": root, "aabb": _skinned_aabb(mesh, skeleton, skin)}


## The mesh's bounds as it is drawn at rest: the skin matrices (bone rest pose x bind pose) can move it away from the raw vertex positions.
static func _skinned_aabb(mesh: ArrayMesh, skeleton: Skeleton3D, skin: Skin) -> AABB:
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bone_slots: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weight_slots: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var matrices: Array[Transform3D] = []
	for slot in skin.get_bind_count():
		matrices.append(skeleton.get_bone_global_rest(skin.get_bind_bone(slot)) * skin.get_bind_pose(slot))
	var aabb := AABB()
	for v in positions.size():
		var result := Vector3.ZERO
		for k in 4:
			var weight := weight_slots[v * 4 + k]
			if weight > 0.0:
				result += weight * (matrices[bone_slots[v * 4 + k]] * positions[v])
		aabb = AABB(result, Vector3.ZERO) if v == 0 else aabb.expand(result)
	return aabb


static func _load(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	_cache[path] = data
	return data


static func _transform(pos: Array, rot: Array, scl: Array) -> Transform3D:
	var basis := Basis(Quaternion(rot[0], rot[1], rot[2], rot[3]).normalized()).scaled(Vector3(scl[0], scl[1], scl[2]))
	return Transform3D(basis, Vector3(pos[0], pos[1], pos[2]))


## 16 floats, row-major (e00 e01 e02 e03 e10 ...): column c of the matrix is a basis axis, column 3 the origin.
static func _bind_pose(values: Array, slot: int) -> Transform3D:
	var o := slot * 16
	var m := func(r: int, c: int) -> float: return float(values[o + r * 4 + c])
	var basis := Basis(
		Vector3(m.call(0, 0), m.call(1, 0), m.call(2, 0)),
		Vector3(m.call(0, 1), m.call(1, 1), m.call(2, 1)),
		Vector3(m.call(0, 2), m.call(1, 2), m.call(2, 2)))
	return Transform3D(basis, Vector3(m.call(0, 3), m.call(1, 3), m.call(2, 3)))


static func _mesh(data: Dictionary) -> ArrayMesh:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var raw_pos: Array = data["pos"]
	var raw_nrm: Array = data["nrm"]
	var raw_uv: Array = data["uv"]
	for i in raw_pos.size() / 3:
		positions.append(Vector3(raw_pos[i * 3], raw_pos[i * 3 + 1], raw_pos[i * 3 + 2]))
	for i in raw_nrm.size() / 3:
		normals.append(Vector3(raw_nrm[i * 3], raw_nrm[i * 3 + 1], raw_nrm[i * 3 + 2]))
	for i in raw_uv.size() / 2:
		uvs.append(Vector2(raw_uv[i * 2], raw_uv[i * 2 + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	if normals.size() == positions.size():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if uvs.size() == positions.size():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	# the file keeps as many influences per vertex as the game's mesh has (1-4); Godot wants exactly 4 slots
	var raw_bones: Array = data["bones"]
	var raw_weights: Array = data["weights"]
	var per_vertex: int = raw_bones.size() / maxi(positions.size(), 1)
	var bone_slots := PackedInt32Array()
	var weight_slots := PackedFloat32Array()
	bone_slots.resize(positions.size() * 4)
	weight_slots.resize(positions.size() * 4)
	for v in positions.size():
		for k in mini(per_vertex, 4):
			bone_slots[v * 4 + k] = int(raw_bones[v * per_vertex + k])
			weight_slots[v * 4 + k] = float(raw_weights[v * per_vertex + k])
	arrays[Mesh.ARRAY_BONES] = bone_slots
	arrays[Mesh.ARRAY_WEIGHTS] = weight_slots
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data["indices"])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _animation(data: Dictionary, bones: Array, names: Array[String]) -> Animation:
	var animation := Animation.new()
	animation.length = float(data["length"])
	animation.loop_mode = Animation.LOOP_LINEAR
	var fps := float(data["fps"])
	var tracks: Dictionary = data["tracks"]
	for bone_name in tracks:
		var track: Dictionary = tracks[bone_name]
		var index := int(track["index"])
		var path := NodePath("%s:%s" % [SKELETON_NAME, names[index]])
		if track.has("pos"):
			var t := animation.add_track(Animation.TYPE_POSITION_3D)
			animation.track_set_path(t, path)
			var v: Array = track["pos"]
			for f in v.size() / 3:
				animation.position_track_insert_key(t, f / fps, Vector3(v[f * 3], v[f * 3 + 1], v[f * 3 + 2]))
		if track.has("rot"):
			var t := animation.add_track(Animation.TYPE_ROTATION_3D)
			animation.track_set_path(t, path)
			var v: Array = track["rot"]
			for f in v.size() / 4:
				animation.rotation_track_insert_key(t, f / fps, Quaternion(v[f * 4], v[f * 4 + 1], v[f * 4 + 2], v[f * 4 + 3]).normalized())
		if track.has("scl"):
			var t := animation.add_track(Animation.TYPE_SCALE_3D)
			animation.track_set_path(t, path)
			var v: Array = track["scl"]
			for f in v.size() / 3:
				animation.scale_track_insert_key(t, f / fps, Vector3(v[f * 3], v[f * 3 + 1], v[f * 3 + 2]))
	return animation
