class_name FlatRig
extends RefCounted

## EXPERIMENT (2026-11-05): a figure's rigged "flat" model with the game's own idle animation. The data is `<mesh basename>_rig.json`, written
## next to the static meshes by tools/asset_import/import_flat_rigs.py (the transform hierarchy, the pieces with their skin weights / bind poses /
## textures, and the sampled idle keyframes - see that tool's docstring). `build()` makes a Node3D with one wrapper per piece (a Skeleton3D + the
## skinned MeshInstance3D) and an AnimationPlayer that loops the idle.
##
## The figure is shown exactly as the game poses it (its idle clip stands up the figures whose static mesh lies down, so the static meshes'
## rotation corrections must NOT be applied on top - CombatMeshPreview skips them for a rig). The bounds returned are those of the first frame.

## Switch for the animated figures (the static meshes are used when false).
static var enabled := true
static var _cache := {}  # json path -> parsed Dictionary


## The rig file that belongs to a static mesh path (`flat_0.tres` -> `flat_0_rig.json`), or "" when there is none.
static func rig_beside(mesh_path: String) -> String:
	var path := mesh_path.get_basename() + "_rig.json"
	return path if enabled and FileAccess.file_exists(path) else ""


## {node: Node3D, aabb: AABB}. `material_for.call(texture or null)` makes the material of a surface (null texture = the caller's default).
## Empty when the file can't be used.
static func build(path: String, material_for: Callable) -> Dictionary:
	var data := _load(path)
	if data.is_empty() or not data.has("pieces"):
		return {}
	var dir := path.get_base_dir()
	var textures: Array[Texture2D] = []
	for file in data["textures"]:
		var image := Image.load_from_file(dir + "/" + str(file))
		textures.append(ImageTexture.create_from_image(image) if image != null else null)

	var bones: Array = data["bones"]
	var names: Array[String] = []
	for i in bones.size():
		var bone_name := str(bones[i]["name"])
		names.append("%s_%d" % [bone_name, i])  # bone names must be unique; the index makes them so

	var root := Node3D.new()
	var player := AnimationPlayer.new()
	var animation := Animation.new()
	animation.length = float(data["anim"]["length"])
	animation.loop_mode = Animation.LOOP_LINEAR
	var combined := AABB()
	var first := true
	var pieces: Array = data["pieces"]
	for p in pieces.size():
		var piece: Dictionary = pieces[p]
		var wrapper := Node3D.new()
		wrapper.name = "Piece%d" % p
		root.add_child(wrapper)
		var skeleton := _skeleton(bones, names)
		wrapper.add_child(skeleton)

		var skin := Skin.new()
		var slot_bones: Array = piece["skin_bones"]
		var bind: Array = piece["bind"]
		skin.set_bind_count(slot_bones.size())
		for slot in slot_bones.size():
			skin.set_bind_bone(slot, int(slot_bones[slot]))
			skin.set_bind_pose(slot, _bind_pose(bind, slot))
		var mesh := _mesh(piece, textures, material_for)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.skin = skin
		for s in mesh.get_surface_count():
			instance.set_surface_override_material(s, mesh.surface_get_material(s))
		skeleton.add_child(instance)
		instance.skeleton = NodePath("..")
		var aabb := _first_frame_aabb(mesh, bones, data["anim"], piece)
		combined = aabb if first else combined.merge(aabb)
		first = false
		_add_tracks(animation, data["anim"], "Piece%d/Skeleton" % p, names)
	root.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation("idle", animation)
	player.add_animation_library("", library)
	player.root_node = NodePath("..")
	player.play("idle")
	return {"node": root, "aabb": combined}


static func _skeleton(bones: Array, names: Array[String]) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	for i in bones.size():
		skeleton.add_bone(names[i])
	for i in bones.size():
		var b: Dictionary = bones[i]
		skeleton.set_bone_parent(i, int(b["parent"]))
		var rest := _transform(b["pos"], b["rot"], b["scl"])
		skeleton.set_bone_rest(i, rest)
		skeleton.set_bone_pose_position(i, rest.origin)
		skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, rest.basis.get_scale())
	return skeleton


## The mesh's bounds as drawn in the animation's first frame. The bone chain is multiplied out here (rest, with the first keyframe of every
## animated bone) - a Skeleton3D outside the scene tree does not update its global poses.
static func _first_frame_aabb(mesh: ArrayMesh, bones: Array, anim: Dictionary, piece: Dictionary) -> AABB:
	var locals: Array[Transform3D] = []
	for b in bones:
		locals.append(_transform(b["pos"], b["rot"], b["scl"]))
	var tracks: Dictionary = anim["tracks"]
	for key in tracks:
		var track: Dictionary = tracks[key]
		var bone := int(track["index"])
		var pos: Vector3 = locals[bone].origin
		var rot: Quaternion = locals[bone].basis.get_rotation_quaternion()
		var scl: Vector3 = locals[bone].basis.get_scale()
		if track.has("pos"):
			var v: Array = track["pos"]
			pos = Vector3(v[0], v[1], v[2])
		if track.has("rot"):
			var v: Array = track["rot"]
			rot = Quaternion(v[0], v[1], v[2], v[3]).normalized()
		if track.has("scl"):
			var v: Array = track["scl"]
			scl = Vector3(v[0], v[1], v[2])
		locals[bone] = Transform3D(Basis(rot).scaled(scl), pos)
	var globals: Array[Transform3D] = []
	for i in bones.size():
		var parent := int(bones[i]["parent"])
		globals.append(locals[i] if parent < 0 else globals[parent] * locals[i])
	var slot_bones: Array = piece["skin_bones"]
	var matrices: Array[Transform3D] = []
	for slot in slot_bones.size():
		matrices.append(globals[int(slot_bones[slot])] * _bind_pose(piece["bind"], slot))
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bone_slots: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weight_slots: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
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


static func _mesh(piece: Dictionary, textures: Array[Texture2D], material_for: Callable) -> ArrayMesh:
	var data: Dictionary = piece["mesh"]
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
	# the file keeps as many influences per vertex as the game's mesh has (1-4); Godot wants exactly 4 slots
	var raw_bones: Array = data["bones"]
	var raw_weights: Array = data["weights"]
	var per_vertex: int = maxi(int(piece.get("per_vertex", 4)), 1)
	var bone_slots := PackedInt32Array()
	var weight_slots := PackedFloat32Array()
	bone_slots.resize(positions.size() * 4)
	weight_slots.resize(positions.size() * 4)
	for v in positions.size():
		for k in mini(per_vertex, 4):
			bone_slots[v * 4 + k] = int(raw_bones[v * per_vertex + k])
			weight_slots[v * 4 + k] = float(raw_weights[v * per_vertex + k])
	var mesh := ArrayMesh.new()
	for surface: Dictionary in piece["surfaces"]:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		if normals.size() == positions.size():
			arrays[Mesh.ARRAY_NORMAL] = normals
		if uvs.size() == positions.size():
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_BONES] = bone_slots
		arrays[Mesh.ARRAY_WEIGHTS] = weight_slots
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(surface["indices"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var texture_index := int(surface["texture"])
		var texture: Texture2D = textures[texture_index] if texture_index >= 0 and texture_index < textures.size() else null
		mesh.surface_set_material(mesh.get_surface_count() - 1, material_for.call(texture))
	return mesh


static func _add_tracks(animation: Animation, data: Dictionary, skeleton_path: String, names: Array[String]) -> void:
	var fps := float(data["fps"])
	var tracks: Dictionary = data["tracks"]
	for key in tracks:
		var track: Dictionary = tracks[key]
		var path := NodePath("%s:%s" % [skeleton_path, names[int(track["index"])]])
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
