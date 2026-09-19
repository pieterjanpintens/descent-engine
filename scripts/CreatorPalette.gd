class_name CreatorPalette
extends Control

## Real palette UI for the Mission Creator - replaces blind `,`/`.`
## keyboard cycling with clickable layer tabs plus a grid of mesh icons
## for whichever layer is currently active. Talks to CreatorController
## ONLY through its public API (select_layer()/select_mesh()) and listens
## to its layer_changed/mesh_changed signals - see the ARCHITECTURE NOTE
## atop CreatorController.gd. Keyboard cycling and this palette can never
## drift out of sync, since both paths funnel through the same methods
## and the same signals drive this UI's highlighting either way.
##
## Everything here is built at runtime in _ready() rather than hand-authored
## as child nodes in a .tscn - the SAME pattern CreatorController already
## uses for its ghost/grid/origin/occupancy overlay helpers. Far less
## fragile than hand-positioning Control nodes in raw scene text, and the
## mesh grid's contents are dynamic (depend on what's in the MeshLibrary)
## anyway so they couldn't be static .tscn content regardless.

@export var creator_controller: CreatorController
@export var layered_map: LayeredMap

const LAYER_NAMES: Array[String] = ["Floor", "Prop", "Underlay"]
const ICON_SIZE := 64
const PANEL_WIDTH := 260

var _layer_buttons: Array[Button] = []
var _mesh_buttons: Dictionary = {}  # mesh_item_name -> Button
var _mesh_grid: GridContainer
var _mesh_scroll: ScrollContainer  ## wraps _mesh_grid - hidden while the Misc tab is active
var _selected_mesh_name: String = ""
var _side_panel: TabContainer  ## our parent - see _on_side_panel_tab_changed()

## "Misc" is a 4th tab alongside the three mesh layers, for tools that
## aren't mesh-library-backed at all (currently just Player Start - see
## _build_ui()) and so don't fit the Floor/Prop/Underlay grid.
## Requested 2026-09-10, in place of an earlier "second toolbar" idea for
## housing the P hotkey - the user's own reasoning: player-start isn't a
## mesh, so it's "a bit of an odd duck" among the layer tabs, and future
## similar non-mesh tools (whatever they turn out to be) should have
## somewhere to live too, rather than each needing its own bespoke UI
## surface. Not a CreatorController.PaintLayer - purely a CreatorPalette
## presentation concept, CreatorController has no idea this tab exists.
var _misc_button: Button
var _misc_container: VBoxContainer
var _player_start_button: Button
var _monster_spawn_button: Button
var _active_spawn_option: OptionButton
var _active_spawn_ids: Array[String] = []
var _spawn_option_rebuild_queued: bool = false


func _ready() -> void:
	# Let CreatorController's own @onready/_ready (which resolves
	# layered_map.floor_grid etc.) finish first - same order-independence
	# trick used throughout this project, see CLAUDE.md's "Hard-won lessons".
	await get_tree().process_frame

	_build_ui()

	creator_controller.layer_changed.connect(_on_layer_changed)
	creator_controller.mesh_changed.connect(_on_mesh_changed)
	creator_controller.spawn_paint_mode_changed.connect(_on_spawn_paint_mode_changed)
	creator_controller.monster_spawn_paint_mode_changed.connect(_on_monster_spawn_paint_mode_changed)
	creator_controller.active_monster_spawn_changed.connect(_queue_spawn_option_rebuild.unbind(1))
	# "Show unavailable" moved to the persistent toolbar 2026-09-14 (see
	# CreatorToolbar.gd) - this palette just reacts to the controller-owned
	# state now instead of owning the checkbox itself.
	creator_controller.show_unavailable_meshes_changed.connect(_queue_mesh_grid_rebuild.unbind(1))
	# Nothing else used to tell this palette "a placement changed, an
	# item's availability may now be different" - painting the same mesh
	# repeatedly (e.g. several floor tiles in a row without switching
	# mesh) never called _rebuild_mesh_grid() at all, so a now-exhausted
	# mesh stayed shown as available until something else (a layer switch,
	# toggling "Show unavailable") happened to force a rebuild. Fixed 2026-09-10.
	layered_map.mission_objects_changed.connect(_queue_mesh_grid_rebuild)
	layered_map.mission_objects_changed.connect(_queue_spawn_option_rebuild)

	_side_panel = get_parent() as TabContainer
	if _side_panel != null:
		_side_panel.tab_changed.connect(_on_side_panel_tab_changed)

	_on_layer_changed(creator_controller.current_layer)
	_on_spawn_paint_mode_changed(creator_controller.spawn_paint_mode)


## Draw/spawn-paint mode only make sense while the Palette is the active
## tab - they're what picks WHAT a click does. Switching to another tab
## (e.g. Outline, to browse/select placed objects) turns both off -
## Select mode is what naturally pairs with that workflow anyway
## (left-click picks an object instead of painting/spawn-marking one).
## Requested 2026-09-10.
func _on_side_panel_tab_changed(tab_index: int) -> void:
	if tab_index != _side_panel.get_tab_idx_from_control(self):
		creator_controller.set_draw_mode(false)
		creator_controller.set_spawn_paint_mode(false)
		creator_controller.set_monster_spawn_paint_mode(false)


func _build_ui() -> void:
	# Deliberately NOT self-anchoring (no set_anchors_and_offsets_preset()
	# here) - this is a TabContainer tab child now (layout_mode = 2 in the
	# .tscn), so TabContainer alone is responsible for this Control's
	# rect. Self-anchoring here used to be harmless when this really was
	# inert, but it turned out NOT to be inert - PRESET_RIGHT_WIDE spans
	# full height from y=0, ignoring the tab bar's own height, which made
	# this Floor/Prop/Underlay row render on top of (and eat clicks
	# meant for) SidePanel's own Palette/Outline tab labels. Confirmed
	# in-editor 2026-09-10 - see claude.md's "Hard-won lessons".
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var vbox := VBoxContainer.new()
	background.add_child(vbox)

	var tabs := HBoxContainer.new()
	vbox.add_child(tabs)
	for i in LAYER_NAMES.size():
		var btn := Button.new()
		btn.text = LAYER_NAMES[i]
		btn.toggle_mode = true
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_layer_tab_pressed.bind(i))
		tabs.add_child(btn)
		_layer_buttons.append(btn)

	_misc_button = Button.new()
	_misc_button.text = "Misc"
	_misc_button.toggle_mode = true
	_misc_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_misc_button.pressed.connect(_on_misc_tab_pressed)
	tabs.add_child(_misc_button)

	_mesh_scroll = ScrollContainer.new()
	_mesh_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_mesh_scroll)

	_mesh_grid = GridContainer.new()
	_mesh_grid.columns = 3
	_mesh_scroll.add_child(_mesh_grid)

	# Misc tab content - not a mesh grid at all, see this tab's own doc
	# comment above. Currently just the one tool; built as a plain
	# VBoxContainer of entries specifically so more can be appended here
	# later without restructuring anything.
	_misc_container = VBoxContainer.new()
	_misc_container.visible = false
	vbox.add_child(_misc_container)

	_player_start_button = Button.new()
	_player_start_button.text = "Player Start"
	_player_start_button.toggle_mode = true
	_player_start_button.pressed.connect(_on_player_start_tool_pressed)
	_misc_container.add_child(_player_start_button)

	_monster_spawn_button = Button.new()
	_monster_spawn_button.text = "Monster Spawn"
	_monster_spawn_button.toggle_mode = true
	_monster_spawn_button.pressed.connect(_on_monster_spawn_tool_pressed)
	_misc_container.add_child(_monster_spawn_button)

	# "Active spawn" - which MonsterSpawn the tool above draws into (see
	# CreatorController.active_monster_spawn_id).
	var spawn_row := HBoxContainer.new()
	_misc_container.add_child(spawn_row)
	_active_spawn_option = OptionButton.new()
	_active_spawn_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_spawn_option.item_selected.connect(_on_active_spawn_selected)
	spawn_row.add_child(_active_spawn_option)
	var new_spawn_button := Button.new()
	new_spawn_button.text = "New spawn"
	new_spawn_button.pressed.connect(_on_new_spawn_pressed)
	spawn_row.add_child(new_spawn_button)


## Picking a layer or a mesh (below) is a clear "I want to paint" signal -
## the reverse of _on_side_panel_tab_changed() turning draw mode off when
## you leave the Palette entirely. Requested 2026-09-10. Also disengages
## spawn-paint mode (the Misc tab's Player Start tool) - only one tool
## should ever determine what a left-click does at a time, so picking a
## mesh/layer here is just as much "not Player Start anymore" as it is
## "now drawing". Deliberately NOT on toggling "Show unavailable" (a
## display filter, not paint intent, and lives on the toolbar now anyway -
## see CreatorToolbar.gd) or _on_locate_mesh_button_pressed()
## (clicking an EXHAUSTED mesh to jump to it - explicitly not something
## you can select to paint).
func _on_layer_tab_pressed(layer_index: int) -> void:
	creator_controller.set_draw_mode(true)
	creator_controller.set_spawn_paint_mode(false)
	creator_controller.select_layer(layer_index as CreatorController.PaintLayer)


## Also resets the Misc tab's own pressed/visible state - picking a REAL
## layer means Misc (if it happened to be active) no longer is.
func _on_layer_changed(layer: CreatorController.PaintLayer) -> void:
	for i in _layer_buttons.size():
		_layer_buttons[i].button_pressed = (i == layer)
	_misc_button.button_pressed = false
	_mesh_scroll.visible = true
	_misc_container.visible = false
	_queue_mesh_grid_rebuild()


## Switches this panel to the Misc tab's tool list instead of the mesh
## grid - see the "Misc" tab's own doc comment. Does turn draw_mode off
## (bug fix, 2026-09-10: the mesh placement ghost was staying visible
## after switching here, since nothing had told CreatorController the
## previously-selected mesh no longer applies - _update_ghost_transform()
## already hides it whenever draw_mode is false, it just needed something
## to actually flip that). Deliberately does NOT touch spawn_paint_mode -
## Player Start lives IN this tab, switching here shouldn't turn ITS own
## tool off; that only happens by leaving the Palette entirely or picking
## a mesh/layer (see _on_layer_tab_pressed()).
func _on_misc_tab_pressed() -> void:
	for btn in _layer_buttons:
		btn.button_pressed = false
	_misc_button.button_pressed = true
	_mesh_scroll.visible = false
	_misc_container.visible = true
	creator_controller.set_draw_mode(false)


## Same "picking a tool is paint/mark intent" reasoning as
## _on_layer_tab_pressed() above, mirrored: engages spawn-paint mode and
## disengages draw mode (Player Start isn't "drawing" a mesh).
func _on_player_start_tool_pressed() -> void:
	creator_controller.set_spawn_paint_mode(true)
	creator_controller.set_draw_mode(false)


## Keeps the button's pressed state in sync regardless of which path
## toggled spawn_paint_mode (this button, or the P hotkey) - same
## "controller emits, UI listens" convention as _on_layer_changed() above.
func _on_spawn_paint_mode_changed(enabled: bool) -> void:
	_player_start_button.button_pressed = enabled


## Monster Spawn tool (new 2026-09-19) - same shape as Player Start above;
## the controller's setters keep it exclusive with every other tool.
func _on_monster_spawn_tool_pressed() -> void:
	creator_controller.set_monster_spawn_paint_mode(true)


func _on_monster_spawn_paint_mode_changed(enabled: bool) -> void:
	_monster_spawn_button.button_pressed = enabled


func _on_new_spawn_pressed() -> void:
	creator_controller.create_monster_spawn()
	creator_controller.set_monster_spawn_paint_mode(true)


func _on_active_spawn_selected(index: int) -> void:
	if index >= 0 and index < _active_spawn_ids.size():
		creator_controller.set_active_monster_spawn(_active_spawn_ids[index])


## Coalesced (mission_objects_changed can fire once per painted cell), same
## pattern as _queue_mesh_grid_rebuild().
func _queue_spawn_option_rebuild() -> void:
	if _spawn_option_rebuild_queued:
		return
	_spawn_option_rebuild_queued = true
	_rebuild_active_spawn_option.call_deferred()


func _rebuild_active_spawn_option() -> void:
	_spawn_option_rebuild_queued = false
	_active_spawn_option.clear()
	_active_spawn_ids.clear()
	var mission := creator_controller.layered_map.mission
	if mission == null:
		return
	var selected := -1
	for i in mission.monster_spawns.size():
		var spawn: MonsterSpawn = mission.monster_spawns[i]
		var label := spawn.reference_name if spawn.reference_name != "" else "Monster Spawn %d" % (i + 1)
		_active_spawn_option.add_item("%s (%d tiles)" % [label, spawn.cells.size()])
		_active_spawn_option.set_item_icon(i, _color_icon(LayeredMap.monster_spawn_color(i)))
		_active_spawn_ids.append(spawn.id)
		if spawn.id == creator_controller.active_monster_spawn_id:
			selected = i
	_active_spawn_option.selected = selected


func _color_icon(color: Color) -> Texture2D:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


var _mesh_grid_rebuild_queued: bool = false


## Coalesces rapid repeated triggers (mission_objects_changed can fire once
## per painted cell, e.g. dragging across several floor tiles in one
## stroke) into a single deferred rebuild instead of one immediate rebuild
## per call - same reasoning/pattern as CreatorOutline.gd's refresh(), see
## that comment and claude.md's matching "hard-won lesson".
func _queue_mesh_grid_rebuild() -> void:
	if _mesh_grid_rebuild_queued:
		return
	_mesh_grid_rebuild_queued = true
	_rebuild_mesh_grid.call_deferred()


## Full rebuild rather than a diff - the mesh list is small (a couple dozen
## entries at most), so the simplicity is worth more than the (negligible)
## perf cost. Callers should go through _queue_mesh_grid_rebuild() above,
## not call this directly, given mission_objects_changed can now trigger
## it far more often than the original layer-switch/checkbox triggers did.
func _rebuild_mesh_grid() -> void:
	_mesh_grid_rebuild_queued = false
	for child in _mesh_grid.get_children():
		child.queue_free()
	_mesh_buttons.clear()

	var library := layered_map.floor_grid.mesh_library
	if library == null:
		return

	for mesh_name in creator_controller.get_available_mesh_names():
		var available := creator_controller.is_mesh_available(mesh_name)
		if not available and not creator_controller.show_unavailable_meshes:
			continue  # can't be drawn right now - just leave it out entirely

		var item_id := layered_map.find_item_id(layered_map.floor_grid, mesh_name)
		if item_id == -1:
			continue

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		btn.toggle_mode = true
		btn.text = mesh_name

		var preview := library.get_item_preview(item_id)
		if preview != null:
			btn.icon = preview
			btn.expand_icon = true
			btn.text = ""

		if available:
			btn.tooltip_text = mesh_name
			btn.pressed.connect(_on_mesh_button_pressed.bind(mesh_name))
		else:
			# Greyed + repurposed: can't be selected for painting (no
			# copies left), so clicking it jumps to where it's already
			# placed instead.
			btn.modulate = Color(1, 1, 1, 0.35)
			btn.tooltip_text = "%s - no copies left, click to locate" % mesh_name
			btn.pressed.connect(_on_locate_mesh_button_pressed.bind(mesh_name))

		_mesh_grid.add_child(btn)
		_mesh_buttons[mesh_name] = btn

	_update_mesh_selection_highlight()


func _on_mesh_button_pressed(mesh_name: String) -> void:
	creator_controller.set_draw_mode(true)  # see _on_layer_tab_pressed()'s comment
	creator_controller.set_spawn_paint_mode(false)
	creator_controller.select_mesh(mesh_name)


func _on_locate_mesh_button_pressed(mesh_name: String) -> void:
	creator_controller.locate_mesh(mesh_name)


func _on_mesh_changed(mesh_name: String) -> void:
	_selected_mesh_name = mesh_name
	_update_mesh_selection_highlight()


func _update_mesh_selection_highlight() -> void:
	for mesh_name in _mesh_buttons:
		_mesh_buttons[mesh_name].button_pressed = (mesh_name == _selected_mesh_name)
