class_name PlayerInteractionController
extends Control

## Drag-to-interact UI for the Player scene, matching the original
## companion app's own gesture: drag a hero's portrait out onto the world
## to indicate that hero is interacting with something. The game's own
## rule ("only interact with what you're physically adjacent to") isn't
## enforced here - that needs real player-position tracking, which doesn't
## exist (see claude.md's Story layer section).
##
## Scope for this first pass (see claude.md's Open items):
##   1. UI + drag detection - the party set during EmbarkDialog (see
##      set_roster()) shown as a row of placeholder portraits, dragging one
##      draws a line toward the cursor.
##   2. Interactable props (InteractableEntry with a non-empty `actions`)
##      highlight while a drag hovers over them.
##   3. Releasing a drag over an interactable just prints debug info - no
##      PropAction actually fires yet. That needs the trigger/effect
##      evaluator, which doesn't exist yet either.
##
## Deliberately NOT using Godot's built-in Control drag-and-drop system
## (_get_drag_data/_drop_data) - the drop target here is a 3D world
## position found by raycasting, not another Control, so manual mouse
## tracking is more direct than fighting that system to reach underneath it.

@export var layered_map: LayeredMap
@export var camera: Camera3D  ## leave unset to auto-grab the viewport's active camera
@export var highlight_color: Color = Color(0.3, 1.0, 1.0, 0.5)

const PORTRAIT_SIZE := 56.0

var _row: HBoxContainer
var _portraits: Array[Control] = []
## Parallel to _portraits - _roster[dock_position] is the HeroCatalog slot
## index that portrait represents (see set_roster()). Dock position and
## catalog slot aren't the same thing once the party doesn't happen to be
## slots 0..N-1 in order (e.g. roster [0, 2, 5]).
var _roster: Array[int] = []

var _drag_line: Line2D
var _dragging: bool = false
var _drag_dock_position: int = -1

var _highlight_overlay: MeshInstance3D
var _highlight_overlay_mesh: ImmediateMesh
var _hovered_entry: InteractableEntry = null


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()
	_build_ui()
	_setup_highlight_overlay()


func _build_ui() -> void:
	# Full-rect, not just a bottom strip - so the drag line (a direct
	# child, added below) shares the same coordinate space as raw mouse
	# positions instead of needing an offset correction for wherever a
	# smaller anchored rect would place its own local origin.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_row.offset_top = -PORTRAIT_SIZE - 24.0
	_row.offset_bottom = -24.0
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	# Empty until set_roster() is called (after EmbarkDialog resolves) -
	# there's nothing to show a portrait row FOR until the party is chosen.

	_drag_line = Line2D.new()
	_drag_line.width = 4.0
	_drag_line.default_color = Color(1.0, 1.0, 1.0, 0.85)
	_drag_line.visible = false
	add_child(_drag_line)


## Rebuilds the portrait row from the party EmbarkDialog.ask_roster()
## returned - one portrait per HeroCatalog slot index in `roster`, in that
## order. Safe to call again later if the party ever needs to change
## mid-session (not currently done anywhere, but nothing here assumes
## it's only called once).
func set_roster(roster: Array[int]) -> void:
	for child in _row.get_children():
		child.queue_free()
	_portraits.clear()
	_roster = roster.duplicate()

	for dock_position in _roster.size():
		var portrait := _make_portrait(_roster[dock_position], dock_position)
		_row.add_child(portrait)
		_portraits.append(portrait)


## Placeholder only - a flat color swatch + name label, same "safe dummy"
## style used elsewhere in this project (no real hero portrait art). Uses
## HeroCatalog so this always matches whatever EmbarkDialog showed for the
## same slot.
func _make_portrait(hero_slot: int, dock_position: int) -> Control:
	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = HeroCatalog.slot_color(hero_slot)
	style.set_corner_radius_all(8)
	portrait.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = HeroCatalog.slot_name(hero_slot)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(label)

	portrait.gui_input.connect(_on_portrait_gui_input.bind(dock_position))
	return portrait


func _on_portrait_gui_input(event: InputEvent, dock_position: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_dragging = true
		_drag_dock_position = dock_position
		_drag_line.visible = true
		get_viewport().set_input_as_handled()


## Drag motion/release can land anywhere on screen, not just back over the
## originating portrait - a global handler (rather than relying on
## gui_input, which only fires while the mouse stays over one Control) is
## the only reliable way to track it.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_update_drag_line(event.position)
		_update_hover_highlight(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag(event.position)


func _update_drag_line(mouse_pos: Vector2) -> void:
	var portrait := _portraits[_drag_dock_position]
	var start := portrait.global_position + portrait.size / 2.0
	_drag_line.points = PackedVector2Array([start, mouse_pos])


func _update_hover_highlight(screen_pos: Vector2) -> void:
	var entry := _interactable_at(screen_pos)
	if entry == _hovered_entry:
		return
	_hovered_entry = entry
	_rebuild_highlight()


func _end_drag(screen_pos: Vector2) -> void:
	var hero_name := HeroCatalog.slot_name(_roster[_drag_dock_position])
	var entry := _interactable_at(screen_pos)
	if entry != null:
		var action_ids: Array = entry.actions.map(func(a): return a.action_id)
		var label := entry.reference_name if entry.reference_name != "" else entry.mesh_item_name
		print("%s interacted with '%s' (%s) - actions: %s" % [hero_name, label, entry.mesh_item_name, action_ids])
	else:
		print("%s: drag released on nothing interactable" % hero_name)

	_dragging = false
	_drag_dock_position = -1
	_drag_line.visible = false
	_hovered_entry = null
	_rebuild_highlight()


## Real physics raycast against the actual GridMap collision (same
## technique CreatorController.erase_at_cursor() uses, not the flat-plane
## approximation _update_hover() uses for painting - that assumes a fixed
## editing level, which doesn't make sense here; we want whatever's
## actually there at whatever height it renders). Only the prop layer is
## interactable right now (InteractableEntry only covers props) - a mesh
## needs a non-empty `actions` list to count, per this feature's scope
## (purely decorative props aren't valid drag targets).
func _interactable_at(screen_pos: Vector2) -> InteractableEntry:
	if camera == null or layered_map == null or layered_map.mission == null:
		return null

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var ray_end := ray_origin + ray_dir * 1000.0

	var space_state := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return null

	var hit_grid = result.collider
	if not (hit_grid is GridMap) or hit_grid != layered_map.prop_grid:
		return null

	var interior_point: Vector3 = result.position - result.normal * 0.01
	var local_pos: Vector3 = hit_grid.to_local(interior_point)
	var hit_cell: Vector3i = hit_grid.local_to_map(local_pos)

	var entry := layered_map.mission.get_interactable_at(hit_cell)
	if entry == null or entry.actions.is_empty():
		return null
	return entry


func _setup_highlight_overlay() -> void:
	_highlight_overlay_mesh = ImmediateMesh.new()
	_highlight_overlay = MeshInstance3D.new()
	_highlight_overlay.mesh = _highlight_overlay_mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.disable_ambient_light = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_overlay.material_override = material
	_highlight_overlay.visible = false
	# Owned by layered_map (a real Node3D), not self (a Control) - keeps 3D
	# overlay nodes under a 3D parent, matching LayeredMap's own spawn
	# overlay, rather than relying on Node3D-under-Control working (it
	# probably would, World3D resolution isn't blocked by 2D ancestors, but
	# there's no reason to rely on that when a proper parent is right here).
	layered_map.add_child(_highlight_overlay)


func _rebuild_highlight() -> void:
	_highlight_overlay_mesh.clear_surfaces()
	if _hovered_entry == null:
		_highlight_overlay.visible = false
		return

	_highlight_overlay_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for offset in _hovered_entry.footprint:
		_add_highlight_quad(_hovered_entry.origin_cell + offset)
	_highlight_overlay_mesh.surface_end()
	_highlight_overlay.global_transform = Transform3D.IDENTITY  # vertices already computed in world space
	_highlight_overlay.visible = true


## Same corner-based box-building approach used throughout this project's
## overlays (GridMap's Center X/Y/Z are OFF, so map_to_local() returns a
## cell's CORNER) - a filled quad per footprint cell, lifted a hair above
## the prop surface to avoid z-fighting.
func _add_highlight_quad(cell: Vector3i) -> void:
	var grid := layered_map.prop_grid
	var corner_local: Vector3 = grid.map_to_local(cell)
	var size := grid.cell_size
	var lift := Vector3(0, 0.05, 0)
	var a := grid.to_global(corner_local + lift)
	var b := grid.to_global(corner_local + Vector3(size.x, 0, 0) + lift)
	var c := grid.to_global(corner_local + Vector3(size.x, 0, size.z) + lift)
	var d := grid.to_global(corner_local + Vector3(0, 0, size.z) + lift)
	for v in [a, b, c, a, c, d]:
		_highlight_overlay_mesh.surface_set_color(highlight_color)
		_highlight_overlay_mesh.surface_add_vertex(v)
