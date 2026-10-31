class_name CreatorContextMenu
extends Node

## The mission editor's right-click menu in the 3D view (a right-click that is not a drag - FreeLookCamera.context_requested).
## On a piece it selects it (like a left-click in Select mode, unless it already belongs to the selection) and offers what you
## need most: Actions…, Properties…, Move to stage, Rotate, Delete. On empty ground it offers the tool switches and the level.
## It only wires things together: the work is done by the controller, the outline and the properties panel.

@export var creator_controller: CreatorController
@export var layered_map: LayeredMap
@export var creator_outline: CreatorOutline
@export var properties_panel: CreatorPropertiesPanel
@export var operation_history: OperationHistory

enum Action { ACTIONS, PROPERTIES, VISIBLE, ROTATE, DELETE, SELECT_MODE, DRAW_MODE, MOVE_MODE, LEVEL_UP, LEVEL_DOWN }

var _menu: PopupMenu
var _stage_menu: PopupMenu
var _stage_ids: Array[String] = []


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_action)
	add_child(_menu)
	_stage_menu = PopupMenu.new()
	_stage_menu.name = "StageMenu"
	_stage_menu.id_pressed.connect(_on_stage_chosen)
	_menu.add_child(_stage_menu)
	# the controller finds the scene's camera in its own _ready(): wait a frame so it is there
	await get_tree().process_frame
	var camera := creator_controller.camera
	if camera is FreeLookCamera:
		(camera as FreeLookCamera).context_requested.connect(_on_context_requested)


func _on_context_requested(_screen_position: Vector2) -> void:
	if layered_map.mission == null:
		return
	var picked := creator_controller.pick_at_cursor()
	_menu.clear()
	if picked["id"] != "":
		# like a left-click in Select mode, but keep a multi-selection the piece already belongs to
		if not creator_controller.selected_ids.has(picked["id"]):
			creator_controller.object_picked.emit(picked["kind"], picked["id"])
		_fill_piece_menu()
	else:
		_fill_ground_menu()
	_menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


func _fill_piece_menu() -> void:
	var prop := properties_panel.current_prop() if properties_panel != null else null
	if prop != null:
		_menu.add_item("Actions…", Action.ACTIONS)
		_menu.add_item("Properties…", Action.PROPERTIES)
		_menu.add_separator()
	_fill_stage_menu()
	_menu.add_submenu_node_item("Move to stage", _stage_menu)
	# the "starts visible" flag of the selected pieces (what the Player shows until a Show effect reveals them); checked when all are visible
	_menu.add_check_item("Visible", Action.VISIBLE)
	_menu.set_item_checked(_menu.get_item_index(Action.VISIBLE), _selection_visible())
	_menu.add_separator()
	_menu.add_item("Rotate", Action.ROTATE)
	_menu.add_item("Delete", Action.DELETE)


func _selected_nodes() -> Array[OutlineNode]:
	var nodes: Array[OutlineNode] = []
	for id in creator_controller.selected_ids:
		var node := layered_map.mission.find_node_by_id(id)
		if node != null:
			nodes.append(node)
	return nodes


func _selection_visible() -> bool:
	var nodes := _selected_nodes()
	if nodes.is_empty():
		return true
	for node in nodes:
		if not node.visible:
			return false
	return true


## "(no stage - root)" and every stage (group) the selected pieces may go under.
func _fill_stage_menu() -> void:
	_stage_menu.clear()
	_stage_ids.clear()
	_stage_menu.add_item("(no stage - root)", 0)
	_stage_ids.append("")
	for group in layered_map.mission.groups:
		_stage_menu.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)", _stage_ids.size())
		_stage_ids.append(group.id)


func _fill_ground_menu() -> void:
	_menu.add_item("Select mode", Action.SELECT_MODE)
	_menu.add_item("Draw mode", Action.DRAW_MODE)
	_menu.add_item("Move mode", Action.MOVE_MODE)
	_menu.add_separator()
	_menu.add_item("Level up", Action.LEVEL_UP)
	_menu.add_item("Level down", Action.LEVEL_DOWN)


func _on_action(id: int) -> void:
	match id:
		Action.ACTIONS:
			properties_panel.open_actions()
		Action.PROPERTIES:
			properties_panel.open_properties()
		Action.VISIBLE:
			var nodes := _selected_nodes()
			if nodes.is_empty():
				return
			var make_visible := not _selection_visible()
			operation_history.record("Visible", func():
				for node in nodes:
					node.visible = make_visible
			)
			layered_map.notify_objects_changed()
		Action.ROTATE:
			if creator_controller.selected_placed_id != "":
				creator_controller.rotate_selected_placed()
			else:
				creator_controller.turn_selection()
		Action.DELETE:
			creator_controller.delete_selection()
		Action.SELECT_MODE:
			creator_controller.set_draw_mode(false)
			creator_controller.set_move_mode(false)
		Action.DRAW_MODE:
			creator_controller.set_draw_mode(true)
		Action.MOVE_MODE:
			creator_controller.set_move_mode(true)
		Action.LEVEL_UP:
			creator_controller.change_level(1)
		Action.LEVEL_DOWN:
			creator_controller.change_level(-1)


## Puts every selected piece under the chosen stage, as one undo step.
func _on_stage_chosen(index: int) -> void:
	if index < 0 or index >= _stage_ids.size():
		return
	var target := _stage_ids[index]
	var nodes := _selected_nodes()
	if nodes.is_empty():
		return
	operation_history.record("Move to stage", func():
		for node in nodes:
			node.parent_id = target
	)
	layered_map.notify_objects_changed()
