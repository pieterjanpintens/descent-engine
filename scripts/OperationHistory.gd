class_name OperationHistory
extends PopupMenu

## Undo/redo for the Creator - attached to the "Edit" PopupMenu under the
## top-spanning MenuBar (same "script attached directly to a PopupMenu,
## items built in code" pattern as CreatorSaveLoad.gd/"File"), requested
## 2026-09-10.
##
## DESIGN: rather than writing separate do()/undo() logic for every
## mutation kind (paint vs erase vs group-move vs property-edit), every
## recorded Operation just stores a deep-duplicated MissionData snapshot
## from immediately before and immediately after the change
## (`MissionData.duplicate(true)` - Resources duplicate correctly the same
## way they already round-trip through MissionIO's save/load, see that
## script's own doc comment). Undo/redo is then completely uniform:
## `LayeredMap.apply_mission(snapshot.duplicate(true))` - it already does a
## correct, complete GridMap-wipe-and-repaint from a MissionData (used
## today by Load and the Player), and it already emits
## `mission_objects_changed`, so CreatorOutline's tree and CreatorPalette's
## availability grid refresh automatically after any undo/redo with zero
## extra wiring. Trades a bit of memory (a full mission snapshot per
## operation, capped at MAX_OPERATIONS) for never needing per-mutation-
## kind reverse logic - "simplest first", matching every other design
## tradeoff this project has made. Mission sizes here are modest (dozens
## of placements), so this is a fine tradeoff; revisit only if a real
## mission turns out large enough for this to actually cost something.
##
## Every mutation site wraps its EXISTING mutation code in a Callable and
## calls record(label, callable) - CreatorController.gd (paint/erase/
## spawn-cell-toggle), CreatorOutline.gd (group create/rename/delete/
## move), CreatorSaveLoad.gd (objective/player-count fields, now live-
## synced instead of Save-time-only - see that script's own comment for
## why that changed). Snapshotting twice per mutation (before AND after)
## rather than just chaining "after" snapshots also means an operation's
## own `before` is always exactly what was live right before it ran, with
## no dependency on any earlier operation's bookkeeping being correct.
##
## Ctrl+Z/Ctrl+Shift+Z are deliberately handled in
## CreatorController._unhandled_input(), NOT here - this script is
## attached to a PopupMenu (a Window-derived node), and whether a Window's
## _unhandled_input() fires reliably while it's closed/invisible is
## genuinely uncertain without being able to run the editor. Reusing
## CreatorController's own _unhandled_input(), already proven reliable
## this session for every other keyboard shortcut, is the lower-risk
## choice - it just calls undo()/redo() directly, same as the menu items'
## own id_pressed handler does.

const MAX_OPERATIONS := 50
## How long a same-label operation stays "meldable" - e.g. repeatedly
## clicking a player-count SpinBox's arrows should become ONE undo step,
## not one per click. A whole paint/erase drag stroke also melds this way
## (every cell painted during one continuous drag shares the "Paint"/
## "Erase" label), matching how most editors treat a single brush stroke
## as one undo step.
const MELD_WINDOW_MSEC := 1500

@export var layered_map: LayeredMap

enum _EditAction { UNDO, REDO }


class Operation:
	extends RefCounted
	var label: String
	var before: MissionData
	var after: MissionData
	var timestamp_msec: int


var _operations: Array[Operation] = []
## _operations[0 ..< _cursor] are currently applied to the live mission;
## _operations[_cursor ..] are the redo-able tail.
var _cursor: int = 0

var _undo_item_index: int = -1
var _redo_item_index: int = -1

## True while a record() call's `mutate` is running - see record()'s own
## reentrancy handling below.
var _recording: bool = false


func _ready() -> void:
	# Inline text hints, not real set_item_accelerator() bindings (unlike
	# CreatorSaveLoad.gd's New/Save/Load, requested 2026-09-10) - Ctrl+Z/
	# Ctrl+Shift+Z are already handled manually in
	# CreatorController._unhandled_input() (see that script's own comment
	# for why - this is a PopupMenu, a Window-derived node, and its own
	# _unhandled_input()/native-shortcut reliability while closed was
	# uncertain enough to route around back when this was first built).
	# Also binding a native accelerator here on top of that would risk
	# undo()/redo() firing twice per keypress.
	add_item("Undo (Ctrl+Z)", _EditAction.UNDO)
	_undo_item_index = get_item_index(_EditAction.UNDO)
	add_item("Redo (Ctrl+Shift+Z)", _EditAction.REDO)
	_redo_item_index = get_item_index(_EditAction.REDO)
	id_pressed.connect(_on_id_pressed)
	_update_menu_state()


func _on_id_pressed(id: int) -> void:
	match id:
		_EditAction.UNDO:
			undo()
		_EditAction.REDO:
			redo()


## The API every mutation site calls: runs `mutate`, and records
## everything it changed as one Operation (or melds it into the previous
## one - see class doc). Wrap the EXISTING mutation code in a Callable at
## the call site rather than restructuring it - see e.g.
## CreatorController.place_at_cursor().
func record(label: String, mutate: Callable) -> void:
	if _recording:
		# A mutation can have a side effect that triggers ANOTHER recorded
		# mutation - e.g. CreatorSaveLoad's min-players field clamping the
		# max-players field when min gets dragged above it, which fires
		# max's own value_changed -> record() call. Let the OUTER record()
		# capture the whole thing in its own before/after pair rather than
		# also pushing a second, separate operation for what the user
		# experienced as one action.
		mutate.call()
		return

	_recording = true
	var before: MissionData = layered_map.mission.duplicate(true)
	mutate.call()
	var after: MissionData = layered_map.mission.duplicate(true)
	_recording = false

	_push_or_meld(label, before, after)


func _push_or_meld(label: String, before: MissionData, after: MissionData) -> void:
	# A new change after undoing some operations discards the redo-able
	# tail, same as every standard undo/redo implementation - branching
	# into a new future invalidates the old one.
	if _cursor < _operations.size():
		_operations.resize(_cursor)

	var now := Time.get_ticks_msec()
	if not _operations.is_empty():
		var top: Operation = _operations[-1]
		if top.label == label and now - top.timestamp_msec <= MELD_WINDOW_MSEC:
			top.after = after
			top.timestamp_msec = now
			_update_menu_state()
			return

	var op := Operation.new()
	op.label = label
	op.before = before
	op.after = after
	op.timestamp_msec = now
	_operations.append(op)
	_cursor += 1

	if _operations.size() > MAX_OPERATIONS:
		_operations.pop_front()
		_cursor -= 1

	_update_menu_state()


func undo() -> void:
	if _cursor <= 0:
		return
	_cursor -= 1
	_apply(_operations[_cursor].before)


func redo() -> void:
	if _cursor >= _operations.size():
		return
	var snapshot: MissionData = _operations[_cursor].after
	_cursor += 1
	_apply(snapshot)


## Never hands the live MissionData the snapshot object stored IN the
## stack directly - `apply_mission()` makes it the live `mission`, and a
## later edit would then mutate that same object in place, corrupting the
## history entry (Resources are reference types). Duplicate on the way
## out every time instead.
func _apply(snapshot: MissionData) -> void:
	layered_map.apply_mission(snapshot.duplicate(true))
	_update_menu_state()


func _update_menu_state() -> void:
	set_item_disabled(_undo_item_index, _cursor <= 0)
	set_item_disabled(_redo_item_index, _cursor >= _operations.size())
