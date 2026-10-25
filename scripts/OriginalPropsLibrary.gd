class_name OriginalPropsLibrary
extends RefCounted

## A mesh library that uses the GAME's own prop models (chest, gate, tree, well...) where the user has imported
## them, and our shipped meshes for everything else. Built ONCE, at import time (AssetImporter, from the
## staged .obj files of tools/asset_import/import_original_props.py), and saved to
## user://original_props/descent-meshes.res - the collision shapes are static data too, so nothing is computed
## when the game starts. The shipped res://descent-meshes.res is never touched: nothing of the game's art is
## ever in the repository.
##
## Every item keeps its id and name, so saved missions, footprints and the rules that key off the mesh names
## are unaffected. Each replaced model is scaled (the game draws 1 tile square = 1 unit, our grid cell is
## 3.2), turned to fit its footprint (the gate is 2 squares long along X in the game, along Z in ours) and
## moved so it sits in the footprint rectangle with its base on the floor - the same place our own mesh has.
##
## LayeredMap loads the library instead of the shipped one when PlayerSettings.use_original_props is on and
## is_available().
##
## Never instantiated - a namespace.

const LIBRARY_PATH := "user://original_props/descent-meshes.res"
const SHIPPED_PATH := "res://descent-meshes.res"
const PROPS_DIR := "user://original_props/"
const TILE_UNITS := 3.2  ## the size of one tile square in the mesh library
const MODEL_SCALE := 3.2  ## the game's models are 1 unit per tile square
const PREVIEW_SIZE := 128  ## the palette picture of each replaced / new item, in pixels
## Hand-tuned nudges per item (mesh library units, added after the model is placed) - for models whose trunk/base
## is not where the footprint wants it. A tile square is TILE_UNITS, so 1/6 of a game unit is TILE_UNITS / 6.
const SHIFTS := {
	"tree": Vector3(0.0, 0.0, -TILE_UNITS / 6.0),
}

## Extra turns per item in degrees (x, y, z), applied after the model is stood upright and before it is fitted to the
## footprint - for models whose own pose is not what we want (the spiked barricade stands at 45 degrees).
const TILTS := {
	"barricade": Vector3(0.0, 0.0, 45.0),
	"stair": Vector3(0.0, 180.0, 0.0),
	"dragonhead": Vector3(-60.0, 0.0, 0.0),
}

## Items whose model is scaled (uniformly) so its LONG side is exactly this many tile squares - when the footprint we want is a little smaller
## than the game model (the dragon arch is 6 squares long, the model about 7).
const FIT_LONG_SIDE := {
	"dragonarch": 6.0,
}

## Items placed by the centre of their WHOLE model instead of the centre of their base: a lying dragon head touches the floor with its chin
## only, and the base rule would push the rest of it out of the footprint.
const CENTRE_BY_MODEL := ["dragonhead"]

static var _cached: MeshLibrary


static func is_available() -> bool:
	return FileAccess.file_exists(LIBRARY_PATH)


## The generated library, or null when it was not built.
static func load_library() -> MeshLibrary:
	if _cached == null and is_available():
		_cached = ResourceLoader.load(LIBRARY_PATH, "MeshLibrary", ResourceLoader.CACHE_MODE_IGNORE) as MeshLibrary
	return _cached


## Forget the cached library (after a new import).
static func reset() -> void:
	_cached = null


## What the last build() did, one line per prop (for the import log and for writing footprints of new props).
static var report: Array[String] = []


## Builds and saves the library from the staged props (`staging_root`/<item name>/mesh.obj [+ edge.obj], the texture
## is user://original_props/<item name>/diffuse.png). A prop whose name the shipped library has replaces that item
## (same id); any other name becomes a NEW item at the end (it needs a FootprintRegistry entry to be placeable
## properly). Every replaced / new item also gets a palette picture rendered from its new mesh (needs a real window,
## so a headless build keeps the old pictures and has none for new items). A coroutine - the rendering takes a few
## frames. Returns how many items were replaced or added (0 = nothing saved).
static func build(staging_root: String) -> int:
	report.clear()
	var shipped := load(SHIPPED_PATH) as MeshLibrary
	if shipped == null:
		return 0
	var library := MeshLibrary.new()
	var next_id := 0
	for id in shipped.get_item_list():
		_copy_item(shipped, library, id)
		next_id = maxi(next_id, id + 1)

	var changed := 0
	var meshes_by_id := {}  ## item id -> its new mesh, for the palette pictures
	var folders := DirAccess.get_directories_at(staging_root)
	folders.sort()
	for item_name in folders:
		var folder := "%s/%s" % [staging_root.trim_suffix("/"), item_name]
		var body := ObjMeshBuilder.build(folder + "/mesh.obj")
		var image := Image.load_from_file(ProjectSettings.globalize_path("%s%s/diffuse.png" % [PROPS_DIR, item_name]))
		if body == null or image == null:
			report.append("%s: mesh or texture missing - skipped" % item_name)
			continue
		var sources: Array[ArrayMesh] = [body]
		if FileAccess.file_exists(folder + "/edge.obj"):
			var edge := ObjMeshBuilder.build(folder + "/edge.obj")
			if edge != null:
				sources.append(edge)
		var id := shipped.find_item_by_name(item_name)
		var reference := shipped.get_item_mesh(id).get_aabb() if id != -1 else AABB()
		var mesh := _fit(sources, item_name, image, reference, id != -1)
		var is_new := id == -1
		if is_new:
			id = next_id
			next_id += 1
			library.create_item(id)
			library.set_item_name(id, item_name)
		library.set_item_mesh(id, mesh)
		library.set_item_mesh_transform(id, Transform3D.IDENTITY)
		var shape := mesh.create_trimesh_shape()
		if shape != null:
			shape.backface_collision = true
			library.set_item_shapes(id, [shape, Transform3D.IDENTITY])
		meshes_by_id[id] = mesh
		var box := mesh.get_aabb()
		report.append("%s%s: %.2f x %.2f tile squares, %.2f high (%.1f units)" % [item_name, " (NEW)" if is_new else "", box.size.x / TILE_UNITS, box.size.z / TILE_UNITS, box.size.y / TILE_UNITS, box.size.y])
		changed += 1

	if changed == 0:
		return 0
	# the floor tile faces, hazards and every other item we did not replace (tokens...) get a picture too, with the official textures on them when those were imported
	# (the same swap LayeredMap does at start-up, done here on copies so nothing is baked into the saved meshes)
	var flat_ids := {}
	var other_ids: Array[int] = []
	var textured := MeshLibrary.new()
	for id in library.get_item_list():
		if meshes_by_id.has(id):
			continue
		var layer := FootprintRegistry.get_layer(library.get_item_name(id))
		var source := library.get_item_mesh(id)
		if source == null:
			continue
		# every item we did not replace (floor tiles, hazards, the tokens...) - the official textures are put on copies
		textured.create_item(id)
		textured.set_item_mesh(id, source.duplicate())
		if layer == "floor" or layer == "underlay":
			flat_ids[id] = true
		else:
			other_ids.append(id)
	OfficialAssetOverrides.apply_overrides(textured)
	var to_render := meshes_by_id.duplicate()
	for id in flat_ids:
		to_render[id] = textured.get_item_mesh(id)
	for id in other_ids:
		to_render[id] = textured.get_item_mesh(id)
	var pictured := await _render_previews(to_render, library, flat_ids)
	report.append("palette pictures rendered: %d of %d (%d of them floor / hazard tiles, %d other unchanged items such as tokens)" % [pictured, to_render.size(), flat_ids.size(), other_ids.size()])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PROPS_DIR))
	if ResourceSaver.save(library, LIBRARY_PATH) != OK:
		push_warning("Could not save " + LIBRARY_PATH)
		return 0
	reset()
	return changed


## Renders a picture of each mesh (a small off-screen 3D scene, seen from the front-right and above, transparent
## background) and stores it as the item's palette preview. Returns how many pictures were made - 0 without a renderer.
static func _render_previews(meshes_by_id: Dictionary, library: MeshLibrary, flat_ids: Dictionary = {}) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return 0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PREVIEW_SIZE, PREVIEW_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.84)
	environment.ambient_light_energy = 0.5
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	light.light_energy = 0.65
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 30.0
	viewport.add_child(camera)
	var holder := MeshInstance3D.new()
	viewport.add_child(holder)
	tree.root.add_child.call_deferred(viewport)  # the root may still be busy setting up its children
	await tree.process_frame

	var made := 0
	for id in meshes_by_id:
		var mesh: Mesh = meshes_by_id[id]
		holder.mesh = mesh
		var box := mesh.get_aabb()
		var radius := maxf(box.size.length() / 2.0, 0.01)
		var distance := radius / sin(deg_to_rad(camera.fov / 2.0)) * 1.05
		var centre := box.position + box.size / 2.0
		# flat tiles are seen from higher up so their texture shows
		var direction := Vector3(0.45, 1.3, 0.6) if flat_ids.has(id) else Vector3(0.8, 0.75, 1.0)
		camera.position = centre + direction.normalized() * distance
		camera.look_at(centre)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			continue
		image.convert(Image.FORMAT_RGBA8)
		library.set_item_preview(id, ImageTexture.create_from_image(image))
		made += 1
	viewport.queue_free()
	return made


static func _copy_item(from: MeshLibrary, to: MeshLibrary, id: int) -> void:
	to.create_item(id)
	to.set_item_name(id, from.get_item_name(id))
	to.set_item_mesh(id, from.get_item_mesh(id))
	to.set_item_mesh_transform(id, from.get_item_mesh_transform(id))
	to.set_item_mesh_cast_shadow(id, from.get_item_mesh_cast_shadow(id))
	to.set_item_shapes(id, from.get_item_shapes(id))
	to.set_item_navigation_mesh(id, from.get_item_navigation_mesh(id))
	to.set_item_navigation_mesh_transform(id, from.get_item_navigation_mesh_transform(id))
	to.set_item_navigation_layers(id, from.get_item_navigation_layers(id))
	# the palette icon (the editor made it from the shipped mesh)
	to.set_item_preview(id, from.get_item_preview(id))


## Turns the model so its "up" is +Y. The game's .fbx models are exported with a different up axis (a chest stands on
## +Z, the pillars on X): the up axis is the one whose range starts or ends at 0 (the model's pivot is on one end of
## it) while the other two are centred, and the model extends from the pivot UP - so up points the way the box
## lies (a cauldron or round table with y from -0.8 to 0 is stored upside down, a chest with z from 0 to 0.65 is
## not). Everything without such an axis is already Y-up. This works on the coordinates as the OBJ exporter wrote
## them (it mirrors X, which is already in the sign of the centre).
static func _upright(box: AABB) -> Basis:
	var size := box.size
	var centre := box.position + box.size / 2.0
	var ratio := Vector3(absf(centre.x) / maxf(size.x, 0.001), absf(centre.y) / maxf(size.y, 0.001), absf(centre.z) / maxf(size.z, 0.001))
	var pivot_axes := 0
	for axis in 3:
		if ratio[axis] >= 0.4:
			pivot_axes += 1
	if pivot_axes != 1:
		return Basis.IDENTITY
	if ratio.z >= 0.4:
		return Basis(Vector3.RIGHT, -PI / 2.0 if centre.z > 0.0 else PI / 2.0)  # +Z or -Z -> +Y
	if ratio.x >= 0.4:
		return Basis(Vector3.BACK, PI / 2.0 if centre.x > 0.0 else -PI / 2.0)  # +X or -X -> +Y
	return Basis.IDENTITY if centre.y > 0.0 else Basis(Vector3.RIGHT, PI)  # already Y-up, or stored upside down


## The game model scaled, stood up, turned and moved onto the footprint of item `item_name`, with its materials.
## `reference` is the shipped mesh's box of an item we already had (its footprint centre and long side are matched),
## a new item gets a footprint rectangle from its own size.
static func _fit(sources: Array[ArrayMesh], item_name: String, texture_image: Image, reference: AABB, has_reference: bool) -> ArrayMesh:
	var box := sources[0].get_aabb()
	var tilt: Vector3 = TILTS.get(item_name, Vector3.ZERO)
	var upright := Basis.from_euler(Vector3(deg_to_rad(tilt.x), deg_to_rad(tilt.y), deg_to_rad(tilt.z))) * _upright(box)
	var stood := Transform3D(upright, Vector3.ZERO) * box

	# horizontal footprint to match: ours when we have the item, else from the model's own size (in tile squares)
	var target_size := Vector2(reference.size.x, reference.size.z)
	var target_centre := Vector2(reference.position.x + reference.size.x / 2.0, reference.position.z + reference.size.z / 2.0)
	if not has_reference:
		var fit := 1.0
		if FIT_LONG_SIDE.has(item_name):
			fit = float(FIT_LONG_SIDE[item_name]) / maxf(maxf(stood.size.x, stood.size.z), 0.001)
		var squares_x := maxi(1, roundi(stood.size.x * fit))
		var squares_z := maxi(1, roundi(stood.size.z * fit))
		target_size = Vector2(squares_x, squares_z) * TILE_UNITS
		target_centre = -target_size / 2.0

	var yaw := 0.0
	if absf(target_size.x - target_size.y) > 0.5 and (target_size.x > target_size.y) != (stood.size.x > stood.size.z):
		yaw = PI / 2.0  # the model is long the other way than the footprint
	var model_scale := MODEL_SCALE
	if FIT_LONG_SIDE.has(item_name):
		model_scale = MODEL_SCALE * float(FIT_LONG_SIDE[item_name]) / maxf(maxf(stood.size.x, stood.size.z), 0.001)
	var turn := Transform3D(Basis(Vector3.UP, yaw) * upright * Basis.from_scale(Vector3.ONE * model_scale), Vector3.ZERO)
	var turned := turn * box
	# the real lowest vertex, not the corner of the turned box (a tilted model's box is looser than the model)
	var lowest := _lowest_y(sources, turn)
	# centre the BASE of the model (a tree's branches reach further to one side than its trunk), not its whole box
	var base := _model_centre(sources, turn) if CENTRE_BY_MODEL.has(item_name) else _base_centre(sources[0], turn, lowest)
	var origin := Vector3(target_centre.x - base.x, -lowest, target_centre.y - base.y)
	origin += SHIFTS.get(item_name, Vector3.ZERO)
	var placed := Transform3D(turn.basis, origin)

	var body := StandardMaterial3D.new()
	body.albedo_texture = ImageTexture.create_from_image(texture_image)
	body.roughness = 1.0
	if texture_image.detect_alpha() != Image.ALPHA_NONE:
		body.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var edge := StandardMaterial3D.new()
	edge.albedo_color = Color.BLACK
	edge.roughness = 1.0

	var result := ArrayMesh.new()
	for source in sources:
		for surface in source.get_surface_count():
			var tool := SurfaceTool.new()
			tool.append_from(source, surface, placed)
			var index := result.get_surface_count()
			tool.commit(result)
			var surface_name := source.surface_get_name(surface)
			result.surface_set_name(index, surface_name)
			result.surface_set_material(index, body if surface_name == "body" else edge)
	return result


## The middle (x, z) of the whole model's real extent (vertices, not a turned box) once `turn` is applied.
static func _model_centre(sources: Array[ArrayMesh], turn: Transform3D) -> Vector2:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for source in sources:
		for surface in source.get_surface_count():
			var vertices: PackedVector3Array = source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var moved := turn * vertex
				low = Vector2(minf(low.x, moved.x), minf(low.y, moved.z))
				high = Vector2(maxf(high.x, moved.x), maxf(high.y, moved.z))
	return (low + high) / 2.0


## The lowest y of any vertex once `turn` is applied.
static func _lowest_y(sources: Array[ArrayMesh], turn: Transform3D) -> float:
	var lowest := INF
	for source in sources:
		for surface in source.get_surface_count():
			var vertices: PackedVector3Array = source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				lowest = minf(lowest, (turn * vertex).y)
	return lowest


## The middle (x, z) of the part of the model that touches the ground: the box of its lowest vertices once `turn` is applied.
static func _base_centre(source: ArrayMesh, turn: Transform3D, lowest_y: float) -> Vector2:
	var height := (turn * source.get_aabb()).size.y
	var limit := lowest_y + maxf(height * 0.06, 0.05)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for surface in source.get_surface_count():
		var vertices: PackedVector3Array = source.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var moved := turn * vertex
			if moved.y > limit:
				continue
			low = Vector2(minf(low.x, moved.x), minf(low.y, moved.z))
			high = Vector2(maxf(high.x, moved.x), maxf(high.y, moved.z))
	if low.x == INF:
		var box := turn * source.get_aabb()
		return Vector2(box.position.x + box.size.x / 2.0, box.position.z + box.size.z / 2.0)
	return (low + high) / 2.0
