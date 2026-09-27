class_name MonsterCombatPreview
extends SubViewportContainer

## EXPERIMENTAL (branch experiment/monster-flat-meshes) - the combat view's
## monster side, rendered as a small 3D scene instead of a flat 2D image:
## either the monster's real "flat card" mesh(es) (see MonsterDisplay.
## flat_mesh_paths()/flat_diffuse_texture()), or - for Centurion, and as the
## mockup this was first proven with - a single unit quad textured with the
## existing crop image (show_quad()). Both paths share one mechanism
## (one or more MeshInstance3D children + one shared unshaded material +
## camera framed to their combined bounds), so the "mockup with a plane"
## step and the "real mesh" step are literally the same code, not two
## separate implementations to keep in sync.
##
## Unshaded material - these are flat, painted illustration assets (card
## art), not real lit 3D props, so no light node is needed at all; this
## also keeps the crop-quad mockup and the real card visually consistent
## with each other and with the hero croptop beside it.

var _viewport: SubViewport
var _camera: Camera3D
var _root: Node3D


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(480, 480)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_viewport.add_child(_camera)

	_root = Node3D.new()
	_viewport.add_child(_root)


## The mockup/fallback path - a single unit-square quad facing the camera,
## textured with `texture` (e.g. MonsterDisplay.crop_texture()).
func show_quad(texture: Texture2D) -> void:
	_clear()
	_root.rotation_degrees = Vector3.ZERO  # a stale correction from a previous show_meshes() call must not carry over
	if texture == null:
		return
	var aspect: float = float(texture.get_width()) / float(maxi(texture.get_height(), 1))
	var quad := QuadMesh.new()
	quad.size = Vector2(aspect, 1.0)
	quad.material = _unshaded_material(texture)
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	_root.add_child(instance)
	_frame_camera(AABB(Vector3(-aspect / 2.0, -0.5, 0), Vector3(aspect, 1.0, 0.01)))


## The real path - one or more pre-extracted mesh pieces (mesh_paths, each a
## ResourceLoader-loadable .tres), sharing `default_texture` on every
## surface EXCEPT one named in `surface_texture_overrides` (surface name ->
## Texture2D - MonsterDisplay.flat_surface_texture_overrides(), confirmed
## needed for Centurion's card: one mesh, "body"/"wings"/"body" surfaces,
## the wings needing a genuinely different texture - see that method's own
## doc). `rotation_degrees_correction` (MonsterDisplay.flat_card_rotation())
## corrects the card's true facing, since the flat mesh's own orientation is
## unverified - see that field's own doc.
func show_meshes(mesh_paths: Array[String], default_texture: Texture2D, rotation_degrees_correction: Vector3 = Vector3.ZERO, surface_texture_overrides: Dictionary = {}) -> void:
	_clear()
	_root.rotation_degrees = rotation_degrees_correction
	var combined := AABB()
	var first := true
	var default_material := _unshaded_material(default_texture)
	var override_materials := {}
	var overrides: Dictionary = surface_texture_overrides
	for surface_name in overrides:
		override_materials[surface_name] = _unshaded_material(overrides[surface_name])
	for path in mesh_paths:
		# ArrayMesh, not the base Mesh - surface_get_name() (needed for the
		# per-surface override lookup) is only declared on that subclass, and
		# every mesh converted through this project's own import pipeline
		# (convert_staged_meshes.gd) always produces one anyway.
		var mesh: ArrayMesh = ResourceLoader.load(path)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		for i in mesh.get_surface_count():
			var surface_name := mesh.surface_get_name(i)
			instance.set_surface_override_material(i, override_materials.get(surface_name, default_material))
		_root.add_child(instance)
		var aabb := mesh.get_aabb()
		combined = aabb if first else combined.merge(aabb)
		first = false
	if not first:
		# Frame the ROTATED bounds (basis applied to the AABB), not the mesh's
		# own local-space one, so a correction doesn't clip out of view.
		_frame_camera(_root.transform * combined)


func _unshaded_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # a flat card should read from either side
	return material


## Orthographic size = the AABB's largest extent (plus a small margin) so
## the whole piece fits regardless of its own local scale/orientation -
## the same "don't assume a shared scale" caution MonsterDisplay's own
## per-mesh auto-scaling already follows for the M-view miniatures.
func _frame_camera(aabb: AABB) -> void:
	var center := aabb.get_center()
	var extent := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_camera.size = maxf(extent, 0.01) * 1.15
	_camera.global_position = center + Vector3(0, 0, extent + 1.0)
	_camera.look_at(center, Vector3.UP)


func _clear() -> void:
	for child in _root.get_children():
		child.queue_free()
