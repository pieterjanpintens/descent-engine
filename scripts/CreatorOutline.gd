class_name CreatorOutline
extends Tree

## The Creator's object browser - a scene-graph-style outline of everything
## placed on the map: MissionData.interactables (props/doors/hazards/
## level-links), FLOOR and UNDERLAY MissionData.floor_placements/
## underlay_placements (each floor/hazard tile is its own distinct placed
## instance too, added 2026-09-10), plus optional, purely organizational
## MissionGroup nodes the designer can create to group related objects
## (e.g. "everything in this room"), so a future effect can eventually
## target the whole set at once.
##
## **WALL placements are deliberately excluded** - wall painting isn't
## actually used in real missions (flagged by the user as a candidate for
## removal later, not attempted here), so there's no point cluttering the
## tree with them. They still get an id/parent_id assigned uniformly by
## LayeredMap.rebuild_floor_tiles() (floor and wall share that one
## function), this script just skips them when building tree items.
##
## Floor/underlay tiles reuse the exact same id/parent_id/outline-tree
## machinery as interactables (see TilePlacement.id, LayeredMap.
## rebuild_floor_tiles()/rebuild_underlay_tiles()'s own identity-carry-over
## fix, mirroring sync_prop_cell()'s) even though those two functions do a
## full clear-and-rebuild rather than interactables' incremental single-
## cell sync - carrying an old placement's id/parent_id forward by
## matching (layer, origin_cell) against the previous rebuild works just
## as well as sync_prop_cell()'s per-cell carry-over, it just runs across
## the whole layer at once instead of one cell at a time.
##
## Built at runtime in _ready() - same reasoning as CreatorPalette/
## PlayerDialog/EmbarkDialog: content is dynamic (depends on the mission),
## couldn't be static .tscn content anyway. Full rebuild on every relevant
## change rather than incremental TreeItem patching - same simplicity
## tradeoff CreatorPalette._rebuild_mesh_grid() already makes (the object
## count here is small, rebuilds aren't per-frame).
##
## Selecting an item emits `selected` - CreatorPropertiesPanel.gd listens
## and shows the right fields, same "talk only through public API +
## signals" convention CreatorPalette's own doc comment establishes for
## CreatorController. Selecting a placed OBJECT (not a group, not root)
## also jumps the camera to it via CreatorController.jump_to_cell() - the
## "find object back" half of this feature's purpose.
##
## Object rename/delete are deliberately NOT available from this tree -
## rename borders on the property editing the user explicitly deferred to
## a later pass, and delete would need to mirror erase_at_cursor()'s
## GridMap-clear path. Both stay exclusively available via the existing
## 3D-viewport paint/erase tools. Groups, being purely organizational (no
## GridMap presence at all), ARE fully managed here: create/rename/delete/
## move, via a right-click context menu - true drag-and-drop reparenting
## is a possible follow-on, not attempted here (see claude.md).

enum SelectionType { ROOT, OBJECT, GROUP, TILE }
enum _ContextAction { NEW_GROUP, NEW_SUBGROUP, RENAME_GROUP, DELETE_GROUP }

signal selected(type: SelectionType, id: String)

@export var layered_map: LayeredMap
@export var creator_controller: CreatorController
@export var operation_history: OperationHistory  ## records group create/rename/delete/move for undo/redo

var _selected_type: SelectionType = SelectionType.ROOT
var _selected_id: String = ""
var _suppress_item_selected: bool = false

## id -> TreeItem for everything currently in the tree ("" -> the root
## item), rebuilt every _rebuild_tree() call. Used to resolve group
## parents while building, to re-find the previously-selected item after
## a rebuild, and by the context menu's Rename/Move actions.
var _id_to_item: Dictionary = {}

var _context_menu: PopupMenu
var _move_to_menu: PopupMenu
var _move_to_target_ids: Array[String] = []
var _context_target_type: SelectionType = SelectionType.ROOT
var _context_target_id: String = ""


func _ready() -> void:
	# Let LayeredMap's own @onready (floor_grid etc.) finish first - same
	# order-independence trick used throughout this project, see
	# CLAUDE.md's "Hard-won lessons".
	await get_tree().process_frame

	hide_root = false
	select_mode = Tree.SELECT_SINGLE
	item_selected.connect(_on_item_selected)
	item_edited.connect(_on_item_edited)
	gui_input.connect(_on_gui_input)

	_context_menu = PopupMenu.new()
	add_child(_context_menu)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)

	_move_to_menu = PopupMenu.new()
	_context_menu.add_child(_move_to_menu)
	_move_to_menu.id_pressed.connect(_on_move_to_menu_id_pressed)

	layered_map.mission_objects_changed.connect(refresh)
	creator_controller.object_picked.connect(_on_object_picked)
	refresh()


var _rebuild_queued: bool = false


## Public - also callable directly if something ever needs to force a
## rebuild outside of the mission_objects_changed signal. Coalesces rapid
## repeated calls into a single deferred rebuild instead of one immediate
## rebuild per call - e.g. dragging to paint several floor cells in one
## stroke fires mission_objects_changed once per cell. Two reasons this
## matters, not just performance: calling Tree.clear()/create_item() too
## rapidly back-to-back was observed (2026-09-10) to intermittently make
## create_item() return null mid-rebuild ("Cannot call method 'set_text'
## on a null value" in _rebuild_tree) - spacing rebuilds out via
## call_deferred() avoids that, on top of avoiding a full Tree rebuild on
## every single painted cell during a fast drag stroke.
func refresh() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	_rebuild_queued = false
	_migrate_missing_ids()
	_rebuild_tree()


## Pre-existing (pre-this-feature) saved missions have interactables with
## id == "" - lazily adopt them into the id system the first time they're
## seen, rather than requiring a one-off migration script. Idempotent -
## safe to call on every refresh().
func _migrate_missing_ids() -> void:
	var mission := layered_map.mission
	if mission == null:
		return
	for group in mission.groups:
		if group.id == "":
			group.id = mission.allocate_object_id()
	for entry in mission.interactables:
		if entry.id == "":
			entry.id = mission.allocate_object_id()
	for placement in mission.floor_placements:
		if placement.layer == TilePlacement.Layer.FLOOR and placement.id == "":
			placement.id = mission.allocate_object_id()
	for placement in mission.underlay_placements:
		if placement.id == "":
			placement.id = mission.allocate_object_id()


func _rebuild_tree() -> void:
	clear()
	_id_to_item.clear()

	var mission := layered_map.mission
	if mission == null:
		return

	var root_item := create_item()
	root_item.set_text(0, mission.mission_name if mission.mission_name != "" else "Untitled Mission")
	root_item.set_metadata(0, {"type": SelectionType.ROOT, "id": ""})
	_id_to_item[""] = root_item

	# Groups can nest under groups (MissionGroup.parent_id) - Tree items
	# are created directly under their real parent, there's no "create
	# then reparent" API, so groups whose parent is itself a group must be
	# created only once that parent item already exists. Repeatedly place
	# whichever remaining groups now have a resolved parent until nothing
	# progresses; anything left after that has a broken/cyclic parent_id
	# (shouldn't happen from normal use of this script) and gets parented
	# under root instead of silently dropped.
	var pending: Array = mission.groups.duplicate()
	while not pending.is_empty():
		var still_pending: Array = []
		var progressed := false
		for group in pending:
			if _id_to_item.has(group.parent_id):
				_id_to_item[group.id] = _create_group_item(_id_to_item[group.parent_id], group)
				progressed = true
			else:
				still_pending.append(group)
		pending = still_pending
		if not progressed:
			for group in pending:
				_id_to_item[group.id] = _create_group_item(root_item, group)
			break

	for entry in mission.interactables:
		var parent_item: TreeItem = _id_to_item.get(entry.parent_id, root_item)
		var item := create_item(parent_item)
		item.set_text(0, entry.reference_name if entry.reference_name != "" else entry.mesh_item_name)
		item.set_metadata(0, {"type": SelectionType.OBJECT, "id": entry.id})
		_id_to_item[entry.id] = item

	# WALL placements are deliberately skipped here - see class doc.
	for placement in mission.floor_placements:
		if placement.layer != TilePlacement.Layer.FLOOR:
			continue
		_add_tile_item(placement, "floor")

	for placement in mission.underlay_placements:
		_add_tile_item(placement, "underlay")

	# Re-select whatever was selected before this rebuild, if it still
	# exists (falls back to root otherwise - e.g. the selected object was
	# just erased). Deliberately does NOT jump the camera - that's only
	# for an actual user click, see _on_item_selected().
	var reselect_key: String = _selected_id if _id_to_item.has(_selected_id) else ""
	var reselect_item: TreeItem = _id_to_item[reselect_key]
	_suppress_item_selected = true
	reselect_item.select(0)
	_suppress_item_selected = false
	_notify_selection(reselect_item.get_metadata(0), false)


## `tile_grid` ("floor"/"underlay") is stored as metadata alongside
## type/id so a later camera-jump (see _notify_selection()) knows which
## GridMap to look the cell up on without re-searching both arrays.
func _add_tile_item(placement: TilePlacement, tile_grid: String) -> void:
	var parent_item: TreeItem = _id_to_item.get(placement.parent_id, _id_to_item[""])
	var item := create_item(parent_item)
	item.set_text(0, placement.mesh_item_name)
	item.set_metadata(0, {"type": SelectionType.TILE, "id": placement.id, "grid": tile_grid})
	_id_to_item[placement.id] = item


func _create_group_item(parent_item: TreeItem, group: MissionGroup) -> TreeItem:
	var item := create_item(parent_item)
	item.set_text(0, group.name if group.name != "" else "(unnamed group)")
	item.set_metadata(0, {"type": SelectionType.GROUP, "id": group.id})
	# Only groups are inline-renamable (double-click, or "Rename Group" in
	# the context menu below) - objects/root are not, see class doc.
	item.set_editable(0, true)
	return item


func _on_item_selected() -> void:
	if _suppress_item_selected:
		return
	var item := get_selected()
	if item == null:
		return
	_notify_selection(item.get_metadata(0), true)


## Takes the clicked/reselected item's whole metadata dict (type/id, plus
## "grid" for a TILE) rather than separate params, since only a TILE
## selection needs the extra "grid" tag baked in at tree-build time (see
## _add_tile_item()) to know which GridMap its cell lives on.
func _notify_selection(meta: Dictionary, jump_camera: bool) -> void:
	var type: SelectionType = meta["type"]
	var id: String = meta["id"]
	_selected_type = type
	_selected_id = id
	selected.emit(type, id)
	if not jump_camera:
		return
	match type:
		SelectionType.OBJECT:
			var entry := _find_interactable_by_id(id)
			if entry != null:
				creator_controller.jump_to_cell(entry.origin_cell)
		SelectionType.TILE:
			var placement := _find_tile_by_id(id)
			if placement != null:
				var grid: GridMap = layered_map.floor_grid if meta.get("grid", "") == "floor" else layered_map.underlay_grid
				creator_controller.jump_to_cell(placement.origin_cell, grid)


## Select mode's counterpart to the camera-jump in _notify_selection() -
## the user clicked an object/tile in the 3D world (see CreatorController.
## select_at_cursor(), Left-click while draw_mode is off) and this
## selects/scrolls to the matching tree item, WITHOUT jumping the camera
## again - it's already exactly where they clicked. Reads the item's OWN
## stored metadata (rather than reconstructing type/grid from `_kind`) so
## this can never disagree with what _rebuild_tree() actually put there.
func _on_object_picked(_kind: String, id: String) -> void:
	var item: TreeItem = _id_to_item.get(id, null)
	if item == null:
		return  # not in the tree (yet) - refresh() is deferred, see that comment
	_suppress_item_selected = true
	item.select(0)
	_suppress_item_selected = false
	scroll_to_item(item)
	_notify_selection(item.get_metadata(0), false)


func _on_item_edited() -> void:
	var item := get_edited()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta["type"] != SelectionType.GROUP:
		return
	var group := _find_group_by_id(meta["id"])
	if group == null:
		return
	var new_name: String = item.get_text(0).strip_edges()
	operation_history.record("Rename group", func():
		group.name = new_name if new_name != "" else "New Group"
	)
	item.set_text(0, group.name)  # normalize back if it was blanked out
	layered_map.notify_objects_changed()


func _find_interactable_by_id(id: String) -> InteractableEntry:
	for entry in layered_map.mission.interactables:
		if entry.id == id:
			return entry
	return null


func _find_group_by_id(id: String) -> MissionGroup:
	for group in layered_map.mission.groups:
		if group.id == id:
			return group
	return null


## Searches FLOOR floor_placements + all of underlay_placements (WALL is
## excluded from the tree entirely, see class doc, so never looked up here).
func _find_tile_by_id(id: String) -> TilePlacement:
	for placement in layered_map.mission.floor_placements:
		if placement.layer == TilePlacement.Layer.FLOOR and placement.id == id:
			return placement
	for placement in layered_map.mission.underlay_placements:
		if placement.id == id:
			return placement
	return null


## ---- Right-click context menu: group New/Rename/Delete/Move to... ----

func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var item := get_item_at_position(event.position)
	if item == null:
		return
	item.select(0)  # right-click also selects (and jumps the camera for an object), matching common tree/editor UX
	var meta: Dictionary = item.get_metadata(0)
	_context_target_type = meta["type"]
	_context_target_id = meta["id"]
	_populate_context_menu(_context_target_type)
	_context_menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _populate_context_menu(type: SelectionType) -> void:
	_context_menu.clear()
	match type:
		SelectionType.ROOT:
			_context_menu.add_item("New Group", _ContextAction.NEW_GROUP)
		SelectionType.GROUP:
			_context_menu.add_item("New Subgroup", _ContextAction.NEW_SUBGROUP)
			_context_menu.add_item("Rename Group", _ContextAction.RENAME_GROUP)
			_context_menu.add_item("Delete Group", _ContextAction.DELETE_GROUP)
			_context_menu.add_separator()
			_add_move_to_submenu()
		SelectionType.OBJECT, SelectionType.TILE:
			_add_move_to_submenu()


func _add_move_to_submenu() -> void:
	_move_to_menu.clear()
	_move_to_target_ids.clear()

	_move_to_menu.add_item("Root", 0)
	_move_to_target_ids.append("")

	for group in layered_map.mission.groups:
		if not _is_valid_move_target(group.id):
			continue
		_move_to_menu.add_item(group.name if group.name != "" else "(unnamed group)", _move_to_target_ids.size())
		_move_to_target_ids.append(group.id)

	_context_menu.add_submenu_node_item("Move to…", _move_to_menu)


## An object can move under any group. A group can move under any group
## except itself or one of its own descendants (that would create a
## cycle) - walk the candidate target's own ancestor chain looking for
## the group being moved.
func _is_valid_move_target(target_group_id: String) -> bool:
	if _context_target_type != SelectionType.GROUP:
		return true
	if target_group_id == _context_target_id:
		return false
	var walk := target_group_id
	var guard := layered_map.mission.groups.size() + 1  # defends against a corrupted/cyclic parent_id chain
	while walk != "" and guard > 0:
		if walk == _context_target_id:
			return false
		var group := _find_group_by_id(walk)
		if group == null:
			break
		walk = group.parent_id
		guard -= 1
	return true


func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		_ContextAction.NEW_GROUP:
			_create_group("")
		_ContextAction.NEW_SUBGROUP:
			_create_group(_context_target_id)
		_ContextAction.RENAME_GROUP:
			_begin_rename_group(_context_target_id)
		_ContextAction.DELETE_GROUP:
			_delete_group(_context_target_id)


func _create_group(parent_id: String) -> void:
	var mission := layered_map.mission
	operation_history.record("New group", func():
		var group := MissionGroup.new()
		group.id = mission.allocate_object_id()
		group.name = "New Group"
		group.parent_id = parent_id
		mission.groups.append(group)
	)
	layered_map.notify_objects_changed()


func _begin_rename_group(group_id: String) -> void:
	var item: TreeItem = _id_to_item.get(group_id, null)
	if item == null:
		return
	item.select(0)
	edit_selected()  # force_edit=false is fine - group items are already set_editable(0, true)


## Deletes a group WITHOUT deleting what's in it - a group is purely
## organizational, so its direct children (both groups and objects) get
## promoted to the deleted group's own parent rather than removed.
func _delete_group(group_id: String) -> void:
	var mission := layered_map.mission
	var group := _find_group_by_id(group_id)
	if group == null:
		return
	operation_history.record("Delete group", func():
		for child_group in mission.groups:
			if child_group.parent_id == group_id:
				child_group.parent_id = group.parent_id
		for entry in mission.interactables:
			if entry.parent_id == group_id:
				entry.parent_id = group.parent_id
		for placement in mission.floor_placements:
			if placement.parent_id == group_id:
				placement.parent_id = group.parent_id
		for placement in mission.underlay_placements:
			if placement.parent_id == group_id:
				placement.parent_id = group.parent_id
		mission.groups.erase(group)
	)
	layered_map.notify_objects_changed()


func _on_move_to_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= _move_to_target_ids.size():
		return
	var new_parent_id: String = _move_to_target_ids[id]

	# Resolve the target FIRST, outside the closure - so a not-found target
	# (shouldn't normally happen) bails out without recording a no-op
	# operation, same as the original early-return behavior.
	var group: MissionGroup = null
	var entry: InteractableEntry = null
	var placement: TilePlacement = null
	match _context_target_type:
		SelectionType.GROUP:
			group = _find_group_by_id(_context_target_id)
		SelectionType.OBJECT:
			entry = _find_interactable_by_id(_context_target_id)
		SelectionType.TILE:
			placement = _find_tile_by_id(_context_target_id)
		_:
			return
	if group == null and entry == null and placement == null:
		return

	operation_history.record("Move to group", func():
		if group != null:
			group.parent_id = new_parent_id
		elif entry != null:
			entry.parent_id = new_parent_id
		elif placement != null:
			placement.parent_id = new_parent_id
	)
	layered_map.notify_objects_changed()
