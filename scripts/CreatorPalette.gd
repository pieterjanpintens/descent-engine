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

const LAYER_NAMES: Array[String] = ["Floor", "Wall", "Prop", "Underlay"]
const ICON_SIZE := 64
const PANEL_WIDTH := 260

var _layer_buttons: Array[Button] = []
var _mesh_buttons: Dictionary = {}  # mesh_item_name -> Button
var _mesh_grid: GridContainer
var _selected_mesh_name: String = ""

## false (default): meshes with no physical copies left simply aren't
## shown - matches the natural "the palette is what you can currently
## draw" flow. true: shows everything, greys out unavailable entries, and
## repurposes clicking one of those into "jump to where it's already
## placed" instead of selecting it (selecting it for painting wouldn't be
## possible anyway once it's exhausted).
var _show_unavailable: bool = false


func _ready() -> void:
	# Let CreatorController's own @onready/_ready (which resolves
	# layered_map.floor_grid etc.) finish first - same order-independence
	# trick used throughout this project, see CLAUDE.md's "Hard-won lessons".
	await get_tree().process_frame

	_build_ui()

	creator_controller.layer_changed.connect(_on_layer_changed)
	creator_controller.mesh_changed.connect(_on_mesh_changed)

	_on_layer_changed(creator_controller.current_layer)


func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	offset_left = -PANEL_WIDTH

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

	var show_unavailable_check := CheckBox.new()
	show_unavailable_check.text = "Show unavailable (click to locate)"
	show_unavailable_check.toggled.connect(_on_show_unavailable_toggled)
	vbox.add_child(show_unavailable_check)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_mesh_grid = GridContainer.new()
	_mesh_grid.columns = 3
	scroll.add_child(_mesh_grid)


func _on_layer_tab_pressed(layer_index: int) -> void:
	creator_controller.select_layer(layer_index as CreatorController.PaintLayer)


func _on_layer_changed(layer: CreatorController.PaintLayer) -> void:
	for i in _layer_buttons.size():
		_layer_buttons[i].button_pressed = (i == layer)
	_rebuild_mesh_grid()


func _on_show_unavailable_toggled(pressed: bool) -> void:
	_show_unavailable = pressed
	_rebuild_mesh_grid()


## Full rebuild rather than a diff - the mesh list is small (a couple dozen
## entries at most) and this only runs on a layer switch or the toggle
## flipping, not every frame, so the simplicity is worth more than the
## (negligible) perf cost.
func _rebuild_mesh_grid() -> void:
	for child in _mesh_grid.get_children():
		child.queue_free()
	_mesh_buttons.clear()

	var library := layered_map.floor_grid.mesh_library
	if library == null:
		return

	for mesh_name in creator_controller.get_available_mesh_names():
		var available := creator_controller.is_mesh_available(mesh_name)
		if not available and not _show_unavailable:
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
	creator_controller.select_mesh(mesh_name)


func _on_locate_mesh_button_pressed(mesh_name: String) -> void:
	creator_controller.locate_mesh(mesh_name)


func _on_mesh_changed(mesh_name: String) -> void:
	_selected_mesh_name = mesh_name
	_update_mesh_selection_highlight()


func _update_mesh_selection_highlight() -> void:
	for mesh_name in _mesh_buttons:
		_mesh_buttons[mesh_name].button_pressed = (mesh_name == _selected_mesh_name)
