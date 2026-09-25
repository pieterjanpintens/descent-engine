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
##   2. Interactable props (InteractableEntry with props["interactible"]
##      not explicitly false, AND at least one action whose own
##      `conditions` currently hold - see MissionRuntime.
##      first_available_action(), new 2026-09-14) highlight while a drag
##      hovers over them.
##   3. Releasing a drag over an interactable presents every CURRENTLY-
##      AVAILABLE action (MissionRuntime.available_actions() - conditions
##      gate which ones are even offered) as a choice via a
##      PlayerDialog.ask_choice() picker (new 2026-09-14, see
##      _offer_actions()) - Cancel is always included alongside them.
##      Picking one fires it via MissionRuntime.fire_prop_action().
##
## Deliberately NOT using Godot's built-in Control drag-and-drop system
## (_get_drag_data/_drop_data) - the drop target here is a 3D world
## position found by raycasting, not another Control, so manual mouse
## tracking is more direct than fighting that system to reach underneath it.

## Fired when firing a PropAction resolves an objective node (see
## MissionRuntime.fire_prop_action()) - MissionPlayer._ready() connects
## this to its own _on_game_over_requested(), which shows the outcome and
## returns to the menu. A genuine signal (unlike MissionPlayer._advance_to()'s
## deliberate avoidance of one for the checkpoint-driven path) is safe here
## specifically because nothing below continues an internal loop after
## _end_drag() that would need to wait on the connected handler finishing.
signal game_over_requested(objective: MissionObjective)

## Fired every time firing a PropAction runs the objectives evaluator,
## regardless of outcome - a DAG group can be replaced by its children
## (advancing which objective is "active") without that resolving all the
## way to a leaf, so MissionPlayer needs to know to refresh its objective
## label even when game_over_requested above doesn't fire. See
## MissionRuntime.get_current_objective_descriptions().
signal objectives_progressed

@export var layered_map: LayeredMap
@export var camera: Camera3D  ## leave unset to auto-grab the viewport's active camera
@export var dialog: PlayerDialog  ## %Dialog - the action picker (see _offer_actions()) shows through this
@export var highlight_color: Color = Color(0.3, 1.0, 1.0, 0.5)

## Assigned by MissionPlayer._ready() right after construction - a plain
## var, not @export/NodePath, since MissionRuntime is built at runtime via
## .new() and never placed in a .tscn (same pattern
## CreatorPropertiesPanel._build_object_fields() uses for
## PropertiesDialog.operation_history/.layered_map).
var mission_runtime: MissionRuntime

## Assigned by MissionPlayer._ready() (same plain-var reasoning as above).
## While it's visible (the M view) a drag targets its monsters, not the world.
var monster_display: MonsterDisplay

## {hero slot index: Array[Weapon]}, set by MissionPlayer after embark.
var hero_weapons: Dictionary = {}

const PORTRAIT_SIZE := 96.0  ## was 56 - too small to read once these became real portrait images rather than a flat colour swatch; matches EmbarkDialog's own portrait cell size
## Space reserved below the portrait row for the mic status line + CommandInput,
## now stacked centered directly underneath it (see VoiceListener.gd's/
## CommandInput.gd's own offsets, which occupy this same margin).
const BOTTOM_MARGIN := 12.0

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
	# Confirmed bug, 2026-09-23: PRESET_CENTER_BOTTOM leaves grow_horizontal
	# at its own default of GROW_DIRECTION_END, not BOTH - with offset_left/
	# offset_right left at the preset's own 0/0 (a zero-width rect at the
	# anchor point) and no explicit width set here, the row only grew
	# RIGHTWARD as portraits were added, pinning its LEFT edge to screen
	# centre instead of actually centering - confirmed with a headless test
	# reading the row's real global rect (500px left margin vs. 80px right,
	# not the ~renders-symmetric result the anchor math alone suggested).
	# Forcing BOTH is what actually centers a content-sized (not explicitly
	# offset) Control under a CENTER anchor.
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# Lifted clear of the mic status line + CommandInput, now stacked
	# centered directly underneath (see VoiceListener.gd/CommandInput.gd's
	# own offsets, which start right where this row's own bottom margin -
	# BOTTOM_MARGIN below - ends).
	_row.offset_top = -PORTRAIT_SIZE - BOTTOM_MARGIN
	_row.offset_bottom = -BOTTOM_MARGIN
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


## HeroCatalog.slot_portrait() - the shipped dummy placeholder art, or a
## user's own official portrait if OfficialAssetOverrides finds one locally
## (see HeroCatalog.gd's own class doc). A name caption still overlays the
## bottom (readable with an outline, same convention InteractionLabels/
## CreatorController's own overlay labels use), since the REAL art has no
## text baked in the way the dummy placeholders do. Uses HeroCatalog so this
## always matches whatever EmbarkDialog showed for the same slot.
func _make_portrait(hero_slot: int, dock_position: int) -> Control:
	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.clip_contents = true  # a non-square portrait shouldn't spill past the panel's own rect
	portrait.add_theme_stylebox_override("panel", StyleBoxEmpty.new())  # the portrait texture (below) covers the whole panel now - no flat colour needed/visible behind it

	var texture_rect := TextureRect.new()
	texture_rect.texture = HeroCatalog.slot_portrait(hero_slot)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(texture_rect)

	var label := Label.new()
	label.text = HeroCatalog.slot_name(hero_slot)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.add_child(label)

	portrait.gui_input.connect(_on_portrait_gui_input.bind(dock_position))
	return portrait


func _on_portrait_gui_input(event: InputEvent, dock_position: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if dialog != null and dialog.visible:
			return  # a placement dialog leaves the screen clickable - no interacting yet
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


## True while the M monster view is what's on screen - drags then target
## monsters (attack) instead of world props.
func _monster_view_active() -> bool:
	return monster_display != null and monster_display.visible


func _update_hover_highlight(screen_pos: Vector2) -> void:
	if _monster_view_active():
		return
	var entry := _interactable_at(screen_pos)
	if entry == _hovered_entry:
		return
	_hovered_entry = entry
	_rebuild_highlight()


## Async now (new 2026-09-14) - releasing over an interactable no longer
## fires immediately, it awaits _offer_actions()'s picker dialog first
## (see that function). Drag visuals reset FIRST, before that await, so
## the drag line/highlight don't sit around while the modal dialog is up -
## the drag gesture itself is complete the moment the mouse is released,
## the picker is a separate follow-up interaction. hero_name is captured
## before _drag_dock_position resets. Called un-awaited from _input()
## (an ordinary, non-async function) - a fine GDScript pattern, this just
## runs as a background coroutine, nothing needs to wait on it.
func _end_drag(screen_pos: Vector2) -> void:
	var hero_slot: int = _roster[_drag_dock_position]
	var hero_name := HeroCatalog.slot_name(hero_slot)
	var monster_view := _monster_view_active()
	var entry: InteractableEntry = null if monster_view else _interactable_at(screen_pos)
	var monster: RuntimeMonster = monster_display.monster_at(screen_pos) if monster_view else null

	_dragging = false
	_drag_dock_position = -1
	_drag_line.visible = false
	_hovered_entry = null
	_rebuild_highlight()

	if monster_view:
		if monster == null:
			print("%s: drag released on no monster" % hero_name)
			return
		await attack(hero_slot, monster)
		return
	if entry == null:
		print("%s: drag released on nothing interactable" % hero_name)
		return
	await _offer_actions(hero_name, entry)


## Public: a hero interacts with a prop - the same picker-then-fire flow a
## portrait drag onto it ends in (_offer_actions()). Used by voice/typed
## commands ("use the pile of dirt").
func interact(hero_slot: int, entry: InteractableEntry) -> void:
	await _offer_actions(HeroCatalog.slot_name(hero_slot), entry)


## Combat: dragging a hero portrait onto a monster in the M view attacks it.
## The table rolls its dice (and applies abilities/potions) outside the engine
## and reports the final number of successes; MissionRuntime.resolve_attack()
## does the rest (successes x weapon damage - random 0..defense, taken off
## the monster's hitpoints) and a large dialog shows the breakdown.
## Public: a portrait drag ends here, and so does a typed/spoken command
## (PlayerCommandRunner) - both attack through this one call.
## `weapon_text` / `successes` are answers already given by voice ("attack John
## with the sword, I rolled three"): a weapon phrase that names one of the
## hero's weapons skips the "Which weapon?" question, a number >= 0 skips the
## "How many successes?" question. Anything not (clearly) given is asked as usual.
func attack(hero_slot: int, monster: RuntimeMonster, weapon_text: String = "", preset_successes: int = -1) -> void:
	var hero_name := HeroCatalog.slot_name(hero_slot)
	if mission_runtime == null:
		return
	var target := "%s (%s chip)" % [monster.display_name(), MonsterChip.display_name(monster.chip)]
	# One of the hero's two embark weapons (asked only when there is a choice).
	var weapons: Array = hero_weapons.get(hero_slot, [])
	var weapon: Weapon = null
	if weapons.size() == 1:
		weapon = weapons[0]
	elif weapons.size() > 1:
		var spoken := -1
		if weapon_text != "":
			var weapon_names: Array[String] = []
			for w: Weapon in weapons:
				weapon_names.append(w.weapon_name)
			spoken = VoiceAnswerParser.match_choice(weapon_text, weapon_names)
		if spoken >= 0:
			weapon = weapons[spoken]
		else:
			var labels: Array[String] = []
			for w: Weapon in weapons:
				labels.append(w.summary())
			var picked: int = await dialog.ask_choice("%s attacks %s.\nWhich weapon?" % [hero_name, target], labels)
			if picked < 0:
				return
			weapon = weapons[picked]
	# Show the weapon in use before asking for the roll - the weapon question is
	# often skipped now (only one weapon, or it was spoken), so this is where the
	# table sees which one it is.
	var weapon_line := "" if weapon == null else "\nwith the %s" % weapon.summary()
	var successes: int = preset_successes if preset_successes >= 0 else await dialog.ask_count("%s attacks %s%s.\nHow many successes did you roll?" % [hero_name, target, weapon_line], 0, 99)
	var r := mission_runtime.resolve_attack(monster, successes, weapon)

	var text := "%s attacks %s\nwith the %s (damage %d)\n" % [hero_name, target, r["weapon_name"], r["base_damage"]]
	if r["weakness_bonus"] > 0:
		text += "\nWeakness: +%d damage" % r["weakness_bonus"]
	if r["resistance_penalty"] > 0:
		text += "\nResistance: -%d damage" % r["resistance_penalty"]
	if r["immune"]:
		text += "\nImmune! The attack does no damage.\n\n0 damage dealt"
	else:
		text += "\n%d successes x %d weapon damage = %d damage\nDefense roll: -%d\n\n%d damage dealt" % [
			r["successes"], r["weapon_damage"], r["damage"], r["defense_roll"], r["dealt"]]
	if r["defeated"]:
		text += "\n\n%s is defeated! Remove it from the board." % monster.display_name()
	else:
		text += "\n\n%s has %d hitpoints left." % [monster.display_name(), r["hitpoints"]]
	await dialog.ask_ok(text, true, true, "Attack")


## Presents every CURRENTLY-AVAILABLE action on `entry` (see
## MissionRuntime.available_actions() - re-resolved here rather than
## trusting whatever _interactable_at()'s last hover check found,
## conditions could in principle have changed between then and release)
## as a choice via dialog.ask_choice(), Cancel always included alongside
## them (PlayerDialog.ask_choice()'s own doc - never omitted). Picking
## Cancel (or dropping on a prop with zero available actions right now,
## which _interactable_at() already excludes from being a valid drop
## target in the first place) does nothing. Otherwise fires the chosen
## action exactly like the old single-action _end_drag() body did.
func _offer_actions(hero_name: String, entry: InteractableEntry) -> void:
	if mission_runtime == null:
		return
	var actions := mission_runtime.available_actions(entry)
	if actions.is_empty():
		return
	var label := entry.reference_name if entry.reference_name != "" else entry.mesh_item_name

	var option_labels: Array[String] = []
	var option_disabled: Array[bool] = []
	for action in actions:
		option_labels.append(action.description if action.description != "" else action.action_id)
		option_disabled.append(action.single_shot and action.already_used)
	var choice: int = await dialog.ask_choice("%s: interact with '%s'" % [hero_name, label], option_labels, option_disabled)

	if choice < 0 or choice >= actions.size():
		print("%s: cancelled interacting with '%s'" % [hero_name, label])
		return

	var action := actions[choice]
	if action.single_shot and action.already_used:
		# Shouldn't be reachable through a correctly-disabled button, but
		# a used-up single-shot action must never actually fire again -
		# cheap insurance rather than trusting the UI's disabled state alone.
		print("%s: '%s' has already been used on '%s'" % [hero_name, action.description, label])
		return
	var objective := await mission_runtime.fire_prop_action(action, hero_name)
	objectives_progressed.emit()
	if objective != null:
		game_over_requested.emit(objective)
	print("%s used '%s' on '%s' (%s)" % [hero_name, action.description, label, entry.mesh_item_name])


## Real physics raycast against the actual GridMap collision (same
## technique CreatorController.erase_at_cursor() uses, not the flat-plane
## approximation _update_hover() uses for painting - that assumes a fixed
## editing level, which doesn't make sense here; we want whatever's
## actually there at whatever height it renders). Only the prop layer is
## interactable right now (InteractableEntry only covers props) - a mesh
## needs props["interactible"] not explicitly false (purely decorative
## props, and props temporarily toggled off via that well-known key,
## aren't valid drag targets) AND at least one action whose own
## `conditions` currently hold (see _resolve_action()) - an entry whose
## every action is conditionally unavailable right now reads the same as
## having no actions at all.
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
	if entry == null or not entry.props.get("interactible", true):
		return null
	if _resolve_action(entry) == null:
		return null
	return entry


## Cheap existence check for _interactable_at() above - is THERE an
## action here right now, not WHICH one (see _offer_actions() for the
## full picker that actually fires one). The first (by declared order,
## see MissionRuntime.first_available_action()'s own doc) whose
## `conditions` currently hold. Falls back to the plain first/only action
## if mission_runtime isn't set yet (shouldn't normally happen once the
## game has actually started - see mission_runtime's own doc) rather than
## conditions silently gating nothing. Returns null for a null entry so
## _interactable_at() doesn't need to null-check separately first.
func _resolve_action(entry: InteractableEntry) -> PropAction:
	if entry == null or entry.actions.is_empty():
		return null
	if mission_runtime != null:
		return mission_runtime.first_available_action(entry)
	return entry.actions[0]


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
