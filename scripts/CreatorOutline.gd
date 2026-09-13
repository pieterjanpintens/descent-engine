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
## Floor/underlay tiles reuse the exact same id/parent_id/outline-tree
## machinery as interactables (see TilePlacement.id, LayeredMap.
## rebuild_floor_tiles()/rebuild_underlay_tiles()'s own identity-carry-over
## fix, mirroring sync_prop_cell()'s) even though those two functions do a
## full clear-and-rebuild rather than interactables' incremental single-
## cell sync - carrying an old placement's id/parent_id forward by
## matching origin_cell against the previous rebuild works just as well
## as sync_prop_cell()'s per-cell carry-over, it just runs across the
## whole layer at once instead of one cell at a time.
##
## Built at runtime in _ready() - same reasoning as CreatorPalette/
## PlayerDialog/EmbarkDialog: content is dynamic (depends on the mission),
## couldn't be static .tscn content anyway. Full rebuild on every relevant
## change rather than incremental TreeItem patching - same simplicity
## tradeoff CreatorPalette._rebuild_mesh_grid() already makes (the object
## count here is small, rebuilds aren't per-frame).
##
## Selecting an item emits `selection_changed` - CreatorPropertiesPanel.gd
## listens and shows the right fields, same "talk only through public API +
## signals" convention CreatorPalette's own doc comment establishes for
## CreatorController. Selecting a single placed OBJECT (not a group, not
## root, and not part of a multi-selection) also jumps the camera to it via
## CreatorController.jump_to_cell() - the "find object back" half of this
## feature's purpose.
##
## **Multi-select** (2026-09-14, `select_mode = SELECT_MULTI` - native
## ctrl+click-toggle/shift+click-range) exists specifically to batch-move
## several already-placed objects into a group at once - see
## CreatorPropertiesPanel.gd's "N items selected" panel.
## `_selected_ids` tracks the FULL current selection (not just one item),
## recomputed from Tree's own `get_next_selected()` chain rather than
## patched incrementally from each `multi_selected` toggle - same
## "recompute from scratch" simplicity already used for `_rebuild_tree()`.
##
## **Confirmed in-editor bug, worked around**: Tree's own native
## SELECT_MULTI click handling does NOT reliably clear the prior selection
## on a plain (no Ctrl/Shift) left-click - it can intermittently leave a
## stale item selected alongside the newly-clicked one, even though
## keyboard nav (arrows + space) behaves correctly. `_on_left_click()`
## (via `gui_input`, which fires AFTER Tree's own built-in handling for the
## same event) corrects this after the fact on every plain click -
## `_select_only()` the clicked item, unconditionally - rather than
## trusting the native behavior. Ctrl/Shift-held clicks are left
## untouched, that's Tree's own native toggle/range-select working as
## intended.
##
## Object rename/delete are deliberately NOT available from this tree -
## rename borders on the property editing the user explicitly deferred to
## a later pass, and delete would need to mirror erase_at_cursor()'s
## GridMap-clear path. Both stay exclusively available via the existing
## 3D-viewport paint/erase tools. Groups, being purely organizational (no
## GridMap presence at all), ARE fully managed here: create/rename/delete/
## move, via a right-click context menu - true drag-and-drop reparenting
## is a possible follow-on, not attempted here (see claude.md).
##
## `creator_controller.working_group_id` is READ/RESET here too (see
## `_delete_group()` below - resets it if the deleted group was the
## current working group) even though the "Working group:" dropdown UI
## itself lives on the persistent toolbar now (`CreatorToolbar.gd`, moved
## there 2026-09-14 so it stays reachable regardless of which SidePanel
## tab is active) - this script still needs to keep that state consistent
## whenever ITS OWN group-CRUD actions could orphan it.

enum SelectionType { ROOT, OBJECT, GROUP, TILE }
enum _ContextAction { NEW_GROUP, NEW_SUBGROUP, RENAME_GROUP, DELETE_GROUP }

signal selection_changed(items: Array)  # Array[Dictionary], each the same {type, id[, grid]} metadata dict every TreeItem carries (see set_metadata() calls below)

@export var layered_map: LayeredMap
@export var creator_controller: CreatorController
@export var operation_history: OperationHistory  ## records group create/rename/delete/move for undo/redo

## The FULL current selection, by id - "" (root) is a valid entry, same as
## any other id. Recomputed from scratch (see _recompute_selected_ids())
## rather than patched per multi_selected toggle.
var _selected_ids: Array[String] = [""]
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
	select_mode = Tree.SELECT_MULTI
	multi_selected.connect(_on_multi_selected)
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
		if placement.id == "":
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

	for placement in mission.floor_placements:
		_add_tile_item(placement, "floor")

	for placement in mission.underlay_placements:
		_add_tile_item(placement, "underlay")

	# Re-select whatever was selected before this rebuild - ALL of it, not
	# just one item. Floor/underlay edits already fire mission_objects_changed
	# (rebuilding this tree) on every painted cell, so without preserving
	# the WHOLE multi-selection, painting anything else while mid-way
	# through organizing a batch of objects into a group would silently
	# collapse the selection back down to one item. Falls back to root only
	# if NONE of the previous selection survived (e.g. everything selected
	# just got erased).
	_suppress_item_selected = true
	var survived := false
	for id in _selected_ids:
		var item: TreeItem = _id_to_item.get(id)
		if item != null:
			item.select(0)
			survived = true
	if not survived:
		root_item.select(0)
	_suppress_item_selected = false
	_recompute_selected_ids()
	# Deliberately does NOT jump the camera - that's only for an actual
	# user click, see _on_multi_selected()/_on_gui_input().
	_emit_selection_changed(false)


## `tile_grid` ("floor"/"underlay") is stored as metadata alongside
## type/id so a later camera-jump (see _emit_selection_changed()) knows
## which GridMap to look the cell up on without re-searching both arrays.
func _add_tile_item(placement: TilePlacement, tile_grid: String) -> void:
	var parent_item: TreeItem = _id_to_item.get(placement.parent_id, _id_to_item[""])
	var item := create_item(parent_item)
	item.set_text(0, placement.reference_name if placement.reference_name != "" else placement.mesh_item_name)
	item.set_metadata(0, {"type": SelectionType.TILE, "id": placement.id, "grid": tile_grid})
	_id_to_item[placement.id] = item


func _create_group_item(parent_item: TreeItem, group: MissionGroup) -> TreeItem:
	var item := create_item(parent_item)
	item.set_text(0, group.reference_name if group.reference_name != "" else "(unnamed group)")
	item.set_metadata(0, {"type": SelectionType.GROUP, "id": group.id})
	# Only groups are inline-renamable (double-click, or "Rename Group" in
	# the context menu below) - objects/root are not, see class doc.
	item.set_editable(0, true)
	return item


func _on_multi_selected(_item: TreeItem, _column: int, _selected: bool) -> void:
	if _suppress_item_selected:
		return
	_recompute_selected_ids()
	_emit_selection_changed(true)


## Rebuilds _selected_ids from Tree's own live selection state via
## get_next_selected() - the standard way to enumerate a SELECT_MULTI
## Tree's full selection (there's no single "current selection" property).
## Recomputing from scratch rather than patching from each multi_selected
## toggle's own (item, selected) params matches this project's existing
## "simplest first, full rebuild over incremental patching" convention.
func _recompute_selected_ids() -> void:
	_selected_ids.clear()
	var item := get_next_selected(null)
	while item != null:
		_selected_ids.append(item.get_metadata(0)["id"])
		item = get_next_selected(item)


## Forces a single-item selection - used by the right-click context menu
## and the 3D-world-click pick, both of which mean "act on THIS one thing"
## regardless of whatever multi-selection existed a moment ago.
func _select_only(item: TreeItem) -> void:
	_suppress_item_selected = true
	deselect_all()
	item.select(0)
	_suppress_item_selected = false


## The single chokepoint for telling the rest of the Creator what's
## selected now - builds `items` from _selected_ids (each entry the same
## metadata dict _rebuild_tree() stores per TreeItem, so only a TILE
## selection carries the extra "grid" tag) and emits selection_changed.
## Highlight/camera-jump only apply when exactly one item is selected - a
## multi-selection has no single "the" object to outline or jump to.
func _emit_selection_changed(jump_camera: bool) -> void:
	var items: Array = []
	for id in _selected_ids:
		var item: TreeItem = _id_to_item.get(id)
		if item != null:
			items.append(item.get_metadata(0))
	selection_changed.emit(items)

	if items.size() != 1:
		creator_controller.clear_selection_highlight()
		return

	var meta: Dictionary = items[0]
	var type: SelectionType = meta["type"]
	var id: String = meta["id"]

	# The camera jump alone stays gated on jump_camera - see this
	# function's own callers for why (an actual click jumps, a
	# rebuild-driven reselection or a world-click pick doesn't).
	match type:
		SelectionType.OBJECT:
			var entry := _find_interactable_by_id(id)
			if entry != null:
				creator_controller.highlight_footprint(entry.origin_cell, entry.footprint, layered_map.prop_grid)
				if jump_camera:
					creator_controller.jump_to_cell(entry.origin_cell)
				return
		SelectionType.TILE:
			var placement := _find_tile_by_id(id)
			if placement != null:
				var grid: GridMap = layered_map.floor_grid if meta.get("grid", "") == "floor" else layered_map.underlay_grid
				var footprint := FootprintRegistry.rotate_footprint(FootprintRegistry.get_footprint(placement.mesh_item_name), grid.get_cell_item_basis(placement.origin_cell))
				creator_controller.highlight_footprint(placement.origin_cell, footprint, grid)
				if jump_camera:
					creator_controller.jump_to_cell(placement.origin_cell, grid)
				return
	creator_controller.clear_selection_highlight()


## Select mode's counterpart to the camera-jump in _emit_selection_changed() -
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
	_select_only(item)
	scroll_to_item(item)
	_recompute_selected_ids()
	_emit_selection_changed(false)


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
		group.reference_name = new_name if new_name != "" else "New Group"
	)
	item.set_text(0, group.reference_name)  # normalize back if it was blanked out
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


## Searches floor_placements + all of underlay_placements.
func _find_tile_by_id(id: String) -> TilePlacement:
	for placement in layered_map.mission.floor_placements:
		if placement.id == id:
			return placement
	for placement in layered_map.mission.underlay_placements:
		if placement.id == id:
			return placement
	return null


## ---- Right-click context menu: group New/Rename/Delete/Move to... ----

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_left_click(event)
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		return
	var item := get_item_at_position(event.position)
	if item == null:
		return
	# Right-click forces a single-item selection (matching common tree/
	# editor UX) - it also selects and jumps the camera for an object,
	# regardless of whatever multi-selection existed a moment ago. Batch
	# operations belong in CreatorPropertiesPanel's multi-select panel, not
	# this per-item context menu.
	_select_only(item)
	_recompute_selected_ids()
	_emit_selection_changed(true)
	var meta: Dictionary = item.get_metadata(0)
	_context_target_type = meta["type"]
	_context_target_id = meta["id"]
	_populate_context_menu(_context_target_type)
	_context_menu.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


## A plain left-click (no Ctrl, no Shift) should always replace the WHOLE
## selection with just the clicked item - confirmed in-editor 2026-09-14
## that Tree's own native SELECT_MULTI click handling doesn't reliably do
## this on its own (a plain click could intermittently leave a stale prior
## selection in place alongside the newly-clicked item, even though
## keyboard nav - arrows + space - behaves correctly; the user caught this
## by comparing the two). This `gui_input` handler fires AFTER Tree's own
## built-in click-to-select logic has already run for the same event (the
## signal is emitted once the engine's internal handling is done, not
## before), so this doesn't prevent whatever Tree just did - it corrects
## it immediately after, same `_select_only()` used for right-click/
## world-pick. Ctrl/Shift-held clicks are left alone entirely (toggle/
## range-select, Tree's own native handling for those is what
## multi-select exists for in the first place).
func _on_left_click(event: InputEventMouseButton) -> void:
	if event.ctrl_pressed or event.shift_pressed:
		return
	var item := get_item_at_position(event.position)
	if item == null:
		return
	_select_only(item)
	_recompute_selected_ids()
	_emit_selection_changed(true)


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
		if not is_valid_move_target(_context_target_type, _context_target_id, group.id):
			continue
		_move_to_menu.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)", _move_to_target_ids.size())
		_move_to_target_ids.append(group.id)

	_context_menu.add_submenu_node_item("Move to…", _move_to_menu)


## An object/tile can move under any group. A group can move under any
## group except itself or one of its own descendants (that would create a
## cycle) - walk the candidate target's own ancestor chain looking for the
## group being moved. Public (not just this script's own context-menu
## "Move to..." use) - CreatorPropertiesPanel.gd's batch move reuses this
## exact same guard per selected item, parameterized instead of reading
## _context_target_type/_context_target_id instance state.
func is_valid_move_target(source_type: SelectionType, source_id: String, target_group_id: String) -> bool:
	if source_type != SelectionType.GROUP:
		return true
	if target_group_id == source_id:
		return false
	var walk := target_group_id
	var guard := layered_map.mission.groups.size() + 1  # defends against a corrupted/cyclic parent_id chain
	while walk != "" and guard > 0:
		if walk == source_id:
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
		group.reference_name = "New Group"
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

	# Not undo-tracked (deliberately outside the record() closure above) -
	# working_group_id is tool state on CreatorController, not MissionData,
	# so it isn't part of the operation_history snapshot anyway. Promoted
	# to the deleted group's own parent, same as its actual children just
	# above, rather than reset all the way to root.
	if creator_controller.working_group_id == group_id:
		creator_controller.set_working_group(group.parent_id)


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
