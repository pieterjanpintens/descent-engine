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

## Relative scale (new 2026-09-28, direct request - "add relative scale
## using size_units for monsters, for heroes... take the mercenary as a
## base") - both sides used to independently auto-fit their camera to
## whatever mesh was shown, so a huge Centurion and a tiny Wolf (or a hero
## standing next to either) all rendered at roughly the same on-screen
## size regardless of their true relative scale. Now: every mesh is scaled
## against ONE shared reference (REFERENCE_MONSTER_FOLDER's own raw flat-
## card diagonal, cached lazily below) by its own `size_units` (see
## show_meshes()'s new parameter, HeroCatalog.size_units()/MonsterDisplay.
## size_units() on the calling side), and the camera uses a FIXED size
## (not an auto-fit one) so relative scale between the two sides survives
## being rendered in two entirely separate SubViewports.
##
## What that fixed size should actually BE was corrected the same day,
## same request: originally sized to comfortably hold the largest
## size_units in the WHOLE roster (Centurion, 2.0) regardless of who's
## actually fighting - meaning almost every real encounter (nothing else
## reaches 2.0) rendered small, with most of the frame sitting empty. "ok
## but now let try to show characters as big as possible, not relative to
## the biggest character in the game but to each other" - `show_meshes()`'s
## `camera_size_units` parameter (new, no longer a fixed MAX_SIZE_UNITS
## const) is now THIS ENCOUNTER's own larger of the two `size_units`
## involved, computed once by CombatView.configure() (the only place that
## sees both sides at once) and passed identically to both previews - a
## Wolf (1.0) fighting a Kehli (0.5) now fills the frame based on the
## Wolf's own 1.0, not Centurion's global 2.0, while still rendering Kehli
## correctly smaller within that same frame; a Centurion encounter still
## gets the full 2.0 headroom it actually needs. Both previews MUST receive
## the identical value for this to work - a mismatched pair would silently
## reintroduce the exact bug this whole feature fixes, since camera.size
## directly determines world-units-per-pixel independently per viewport.
## show_quad()'s own fallback path is untouched (no size_units concept
## applies to a flat crop image) and keeps auto-fitting via the original
## _frame_camera().
const REFERENCE_MONSTER_FOLDER := "mercenary"
const RELATIVE_CAMERA_MARGIN := 0.85  # 2026-09-28: "make them bigger again... fill the entire space of the screen, if they fall off a bit that is ok" - below 1.0 on purpose, so the frame is now smaller than the figure's own diagonal instead of padded around it
static var _cached_reference_diagonal := -1.0  # lazily computed once, shared by every CombatMeshPreview instance

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
	_root.scale = Vector3.ONE  # ditto for a stale relative-scale factor - see show_meshes()'s own doc
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
## unverified - see that field's own doc. `size_units` (new 2026-09-28,
## default 1.0 - the shared baseline, so an un-updated caller keeps
## rendering exactly as before) is THIS mesh's own size relative to
## REFERENCE_MONSTER_FOLDER; `camera_size_units` (also new) is the larger of
## the two size_units actually present in the current encounter (the SAME
## value must be passed to both the hero and monster preview for a given
## encounter) - see this script's own class-level doc above for the full
## mechanism and why these are two different numbers.
func show_meshes(mesh_paths: Array[String], default_texture: Texture2D, rotation_degrees_correction: Vector3 = Vector3.ZERO, surface_texture_overrides: Dictionary = {}, size_units: float = 1.0, camera_size_units: float = 1.0) -> void:
	_clear()
	_root.rotation_degrees = rotation_degrees_correction
	_root.scale = Vector3.ONE  # measure the RAW (unscaled) combined AABB below before applying any relative-scale factor
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
		# Scale this mesh, relative to the shared reference diagonal, by its
		# own size_units - matches MonsterDisplay._build_real_figure()'s own
		# diagonal-based formula exactly (diagonal, not a single axis, since
		# a mesh's "tall" axis isn't consistent across every source asset -
		# see that method's own doc for why).
		var raw_diagonal := combined.size.length()
		var reference := _reference_diagonal()
		var scale_factor := (reference * size_units) / raw_diagonal if raw_diagonal > 0.0 else 1.0
		_root.scale = Vector3.ONE * scale_factor
		# Frame the ROTATED-AND-SCALED bounds (basis applied to the AABB), not
		# the mesh's own local-space one, so a correction doesn't clip out of
		# view - but with a FIXED camera size (not an auto-fit one), so a
		# smaller size_units figure genuinely renders smaller within the
		# shared frame instead of being zoomed to fill it.
		_frame_camera_relative((_root.transform * combined).get_center(), reference, camera_size_units)


## Lazily loads/caches REFERENCE_MONSTER_FOLDER's own flat-card mesh once
## and returns its raw (unscaled) AABB diagonal - the shared "size_units
## 1.0" reference every show_meshes() call scales against. A plain float
## cache, not the mesh itself, is kept around (nothing else ever needs the
## reference mesh's actual geometry). Falls back to 1.0 (a no-op reference -
## every mesh then renders at its own raw scale, same as before this
## feature existed) if the reference mesh can't be found/loaded, so a
## missing/not-yet-imported asset degrades gracefully rather than breaking
## every combat screen.
static func _reference_diagonal() -> float:
	if _cached_reference_diagonal < 0.0:
		_cached_reference_diagonal = 1.0
		var paths := MonsterDisplay.flat_mesh_paths(REFERENCE_MONSTER_FOLDER)
		if not paths.is_empty():
			var mesh: ArrayMesh = ResourceLoader.load(paths[0])
			if mesh != null:
				var diagonal := mesh.get_aabb().size.length()
				if diagonal > 0.0:
					_cached_reference_diagonal = diagonal
	return _cached_reference_diagonal


## The fixed-size counterpart to _frame_camera() above (used only by
## show_meshes()'s relative-scale path) - camera.size is constant for a
## given `camera_size_units` (reference * camera_size_units * margin)
## regardless of which specific mesh is shown, so relative scale between
## calls sharing the same `camera_size_units` is preserved; only the
## centering point changes per mesh. `camera_size_units` itself is the
## caller's job to pick consistently (CombatView.configure() uses the
## larger of the current encounter's two size_units) - see show_meshes()'s
## own doc for why this must match between the hero and monster preview.
func _frame_camera_relative(center: Vector3, reference_diagonal: float, camera_size_units: float) -> void:
	var camera_size := reference_diagonal * camera_size_units * RELATIVE_CAMERA_MARGIN
	_camera.size = maxf(camera_size, 0.01)
	_camera.global_position = center + Vector3(0, 0, camera_size + 1.0)
	_camera.look_at(center, Vector3.UP)


func _unshaded_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # a flat card should read from either side
	# CONFIRMED BUG, fixed 2026-09-28, "certain parts that need to be in the
	# back are clipped to the front... models are not closed": Godot's
	# alpha-blend materials don't write to the depth buffer by default
	# (depth_draw_mode = DEPTH_DRAW_OPAQUE_ONLY), so triangles within ONE
	# transparent mesh never depth-test against each other - they just paint
	# in whatever order they're stored in (painter's-algorithm-style),
	# regardless of actual camera distance. With CULL_DISABLED (both faces
	# render) and an open/non-manifold mesh (no back wall to occlude
	# anything geometrically either), a back-facing triangle submitted after
	# a front-facing one paints right over it. DEPTH_DRAW_ALWAYS makes this
	# material write depth like an opaque one - each triangle now correctly
	# depth-tests against whatever already drew, so the actually-nearer
	# triangle wins regardless of draw order. Confirmed visually (spinning
	# the mesh around Y showed exactly this symptom before the fix).
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
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
## per-mesh auto-scaling already follows for the M-view miniatures. Used
## ONLY by show_quad()'s own fallback path now (2026-09-28) - show_meshes()
## uses the FIXED-size _frame_camera_relative() below instead, so relative
## scale between different meshes/calls is preserved; a flat crop image has
## no size_units concept, so it keeps auto-fitting to always fill its box.
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
