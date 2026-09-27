class_name CombatMeshPreview
extends SubViewportContainer

## EXPERIMENTAL (branch experiment/monster-flat-meshes) - either side of the
## combat view (hero left, monster right), rendered as a small 3D scene
## instead of a flat 2D image: either the real "flat card"/hero mesh(es)
## (see MonsterDisplay.flat_mesh_paths()/HeroCatalog.flat_mesh_paths() and
## their diffuse-texture counterparts), or - for anything without one yet,
## and as the mockup this was first proven with - a single unit quad
## textured with the existing crop image (show_quad()). Both paths share
## one mechanism (one or more MeshInstance3D children + one shared unshaded
## material + camera framed to their combined bounds), so the "mockup with
## a plane" step and the "real mesh" step are literally the same code, not
## two separate implementations to keep in sync. Originally built (and
## still named after) the monster side specifically - genuinely generic
## from the start, so reused as-is once heroes turned out to have real
## meshes too, rather than duplicated.
##
## Unshaded material - these are flat, painted illustration assets (card
## art), not real lit 3D props, so no light node is needed at all; this
## also keeps the crop-quad mockup and the real card visually consistent
## with each other.

var _viewport: SubViewport
var _camera: Camera3D
var _root: Node3D


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	# CONFIRMED BUG, fixed 2026-09-27: without this, a SubViewport shares the
	# SAME World3D as whatever it's nested under by default - this preview
	# lives inside PlayerDialog (a Control/CanvasLayer tree), but that still
	# resolves to the game's own main World3D, so its camera could see
	# MonsterDisplay's M-view stands, AND its own card mesh kept existing in
	# that shared world after the dialog closed (only cleared on the NEXT
	# show_quad()/show_meshes() call, not when the dialog itself closes) -
	# reported directly: "parts of the mesh of the monster overlay in the
	## combat dialog, and after combat the flat mesh is also in the monster
	# overview." own_world_3d gives this SubViewport a genuinely separate,
	# isolated 3D scene graph, so nothing here is visible from the main
	# world and vice versa.
	_viewport.own_world_3d = true
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
	# CONFIRMED BUG, fixed 2026-09-27: these diffuse textures are dense
	# texture ATLASES (many small hand-painted pieces packed edge-to-edge -
	# e.g. Kehli's crossbow/straps, Galaden's cloth/feathers, each in its own
	# tiny region with little to no padding between them). Godot's default
	# TEXTURE_FILTER_LINEAR_WITH_MIPMAPS blends each texel with its
	# neighbours across generated mip levels, which on a tightly packed
	# atlas like this bleeds colour in from the ADJACENT, unrelated patch -
	# reported directly as "an additional/wrong texture" on specific small
	# pieces (Kehli's shield-ish "Fluid" submesh, Galaden's "Cloth" one),
	# while a hero whose second submesh happens to sit in a less crowded
	# part of its own atlas (Vaerix) showed no such bleed. Plain
	# TEXTURE_FILTER_LINEAR (no mipmaps) samples only a texel's immediate
	# neighbourhood, which stays inside one atlas patch.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
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


## CONFIRMED BUG, fixed 2026-09-27: queue_free() defers actual removal to
## end of frame, so a SECOND show_meshes()/show_quad() call on the SAME
## preview (e.g. a second attack reusing PlayerDialog's cached CombatView)
## added its new MeshInstance3D(s) here while the PREVIOUS ones were still
## technically present and rendering for at least the rest of that frame -
## confirmed directly (a synthetic two-call test showed 2 children
## immediately after the second call, not the expected 1). This is exactly
## the same class of bug claude.md's own Hard-won lessons already documents
## for ObjectivesDialog's GraphNode rebuild - the general rule there
## ("never queue_free() something you're about to synchronously replace")
## applies here too, just as an overlapping-mesh visual glitch (reported as
## "an additional/wrong texture") rather than a silent name collision.
func _clear() -> void:
	for child in _root.get_children():
		_root.remove_child(child)
		child.free()
