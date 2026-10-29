class_name CreatorToolbar
extends HBoxContainer

## The Creator's persistent toolbar - sits directly under the MenuBar (see
## MissionMap.tscn's MainLayout), full width, so its controls stay
## reachable regardless of which SidePanel tab (Palette/Outline) is
## currently active. Requested 2026-09-14 to fix exactly that friction:
## "Working group" used to live inside the Outline tab (had to switch away
## from Palette - where you're actually drawing - just to change it), and
## "Show unavailable" used to live inside the Palette's own mesh grid
## (invisible while browsing the Outline tab).
##
## Built entirely in code in _ready(), same pattern as every other
## dynamic Creator UI piece (CreatorPalette, PropertiesDialog, ...).
## `_rebuild_working_group_option()` duplicates the same small "Root +
## groups" list-building loop CreatorOutline.gd's own three near-identical
## builders (the "Move to..." submenu, and CreatorPropertiesPanel.gd's
## batch-move dropdown) already use, rather than sharing it - matches this
## project's established convention of each UI piece owning its own
## near-identical widget-building code.
##
## Talks to CreatorController ONLY through its public API/signals -
## working_group_id/set_working_group()/working_group_changed and
## show_unavailable_meshes/set_show_unavailable_meshes()/
## show_unavailable_meshes_changed - same "controller emits, UI listens"
## convention as CreatorPalette.

@export var creator_controller: CreatorController
@export var layered_map: LayeredMap
@export var creator_outline: CreatorOutline

## The "Problems" button and list (experiment/ai-map-generation): the map checked with MapPlanValidator.validate_mission() - the same
## rules a generated plan has to pass. Re-checked a moment after the mission changes; cheap (a few ms for a normal map).
const CHECK_DELAY_SEC := 0.6
const WATCH_SEC := 2.0

var _stage_dialog: StageDialog
var _problems_button: Button
var _problems_dialog: AcceptDialog
var _problems_list: VBoxContainer
var _issues: Array[Dictionary] = []  # {severity, message, piece (index into _pieces, -1 = none)}
var _pieces: Array = []
var _check_timer: Timer
var _last_signature: int = 0

var _working_group_option: OptionButton
var _working_group_ids: Array[String] = []  # parallel to _working_group_option's items, same pattern as CreatorOutline's own _move_to_target_ids

var _rebuild_queued: bool = false

## The texts' languages: the editing language picker and the dialogs behind it (see LanguageBar / LanguagesDialog / TranslationWindow).
var _language_bar: LanguageBar
var _languages_dialog: LanguagesDialog
var _translation_window: TranslationWindow
var _bar_mission: MissionData  ## the mission the bar was last filled for: another one (load, new, undo) means the languages are read again


func _ready() -> void:
	# Let CreatorController's/LayeredMap's own @onready/_ready finish first -
	# same order-independence trick used throughout this project, see
	# CLAUDE.md's "Hard-won lessons".
	await get_tree().process_frame

	_build_ui()

	creator_controller.working_group_changed.connect(_on_working_group_changed)
	layered_map.mission_objects_changed.connect(_queue_working_group_option_rebuild)
	_rebuild_working_group_option()
	layered_map.mission_objects_changed.connect(_on_mission_maybe_replaced)
	_sync_language()

	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = CHECK_DELAY_SEC
	_check_timer.timeout.connect(_run_check)
	add_child(_check_timer)
	layered_map.mission_objects_changed.connect(_check_timer.start)
	# some edits (start squares, the player count, spawn tiles) don't announce themselves: a cheap look twice a second-ish
	var watch := Timer.new()
	watch.wait_time = WATCH_SEC
	watch.timeout.connect(_watch)
	add_child(watch)
	watch.start()
	_run_check()


func _build_ui() -> void:
	var group_label := Label.new()
	group_label.text = "Working group:"
	add_child(group_label)

	_working_group_option = OptionButton.new()
	_working_group_option.item_selected.connect(_on_working_group_option_selected)
	add_child(_working_group_option)

	_language_bar = LanguageBar.new()
	_language_bar.language_selected.connect(_on_language_selected)
	_language_bar.manage_pressed.connect(_open_languages_dialog)
	_language_bar.translate_pressed.connect(_open_translation_window)
	add_child(_language_bar)
	_languages_dialog = LanguagesDialog.new()
	_languages_dialog.root_provider = func() -> Resource: return layered_map.mission
	_languages_dialog.commit = _commit_language_change
	_languages_dialog.language_requested.connect(_on_language_selected)
	add_child(_languages_dialog)
	_translation_window = TranslationWindow.new()
	_translation_window.root_provider = func() -> Resource: return layered_map.mission
	_translation_window.commit = _commit_language_change
	add_child(_translation_window)

	# Pushes "Show unavailable" to the right - a plain expand-filling
	# spacer, same trick used for centering rows elsewhere in this project.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	var stage_button := Button.new()
	stage_button.text = "Generate stage..."
	stage_button.tooltip_text = "Describe an area in words and let the AI design it from the pieces in the box (experimental)."
	stage_button.pressed.connect(func(): _stage_dialog.open())
	add_child(stage_button)
	_stage_dialog = StageDialog.new()
	_stage_dialog.creator_controller = creator_controller
	_stage_dialog.layered_map = layered_map
	_stage_dialog.visible = false
	add_child(_stage_dialog)

	_problems_button = Button.new()
	_problems_button.flat = true
	_problems_button.tooltip_text = "What is wrong or unfinished in this map: pieces, floors, start squares, the win condition. Click to read the list."
	_problems_button.pressed.connect(_open_problems_dialog)
	add_child(_problems_button)
	_build_problems_dialog()

	var show_unavailable_check := CheckBox.new()
	show_unavailable_check.text = "Show unavailable"
	show_unavailable_check.tooltip_text = "Also list the pieces that are used up (greyed out); clicking one jumps to where it is placed."
	show_unavailable_check.button_pressed = creator_controller.show_unavailable_meshes
	show_unavailable_check.toggled.connect(creator_controller.set_show_unavailable_meshes)
	add_child(show_unavailable_check)


## Coalesces rapid repeated triggers (mission_objects_changed can fire once
## per painted cell during a fast drag stroke) into a single deferred
## rebuild - same pattern as CreatorOutline.gd's refresh()/_do_refresh().
func _queue_working_group_option_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_working_group_option.call_deferred()


## "(none - root)" + every mission.groups entry, flat (no nesting
## indentation - matches CreatorOutline's own "Root + groups" list
## builders' precedent). Re-selects whatever creator_controller.
## working_group_id currently is; resets it if that id no longer exists
## (shouldn't normally happen outside CreatorOutline._delete_group()'s own
## reset, but stays consistent rather than silently keeping a dangling id).
func _rebuild_working_group_option() -> void:
	_rebuild_queued = false
	_working_group_option.clear()
	_working_group_ids.clear()

	_working_group_option.add_item("(none - root)")
	_working_group_ids.append("")

	var mission := layered_map.mission
	if mission != null:
		for group in mission.groups:
			_working_group_option.add_item(group.reference_name if group.reference_name != "" else "(unnamed group)")
			_working_group_ids.append(group.id)

	var current_index := _working_group_ids.find(creator_controller.working_group_id)
	if current_index == -1:
		creator_controller.set_working_group("")
		current_index = 0
	_working_group_option.select(current_index)


func _on_working_group_option_selected(index: int) -> void:
	if index < 0 or index >= _working_group_ids.size():
		return
	creator_controller.set_working_group(_working_group_ids[index])


## Keeps the dropdown's own selection in sync regardless of what triggered
## the change (a pick here, or a reset from CreatorOutline._delete_group()) -
## cheap enough to just re-select rather than rely on
## mission_objects_changed's own refresh pipeline to happen to cover every
## path that could call set_working_group().
func _on_working_group_changed(group_id: String) -> void:
	var index := _working_group_ids.find(group_id)
	_working_group_option.select(index if index != -1 else 0)


# ---------------------------------------------------------------- problems (MapPlanValidator)

func _build_problems_dialog() -> void:
	_problems_dialog = AcceptDialog.new()
	_problems_dialog.title = "Problems"
	_problems_dialog.ok_button_text = "Close"
	_problems_dialog.min_size = Vector2i(560, 320)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(540, 280)
	_problems_list = VBoxContainer.new()
	_problems_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_problems_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_problems_list)
	_problems_dialog.add_child(scroll)
	add_child(_problems_dialog)


## A cheap fingerprint of the things the check looks at; some edits (start squares, the player count) fire no signal.
func _signature() -> int:
	var mission := layered_map.mission
	if mission == null:
		return 0
	var spawn_cells := 0
	for spawn in mission.monster_spawns:
		spawn_cells += spawn.cells.size()
	return hash([mission.floor_placements.size(), mission.underlay_placements.size(), mission.interactables.size(), mission.monster_spawns.size(),
		spawn_cells, mission.player_spawn_cells.hash(), mission.los_blockers.size(), mission.max_players, mission.objectives.size(), mission.custom_variables.size()])


func _watch() -> void:
	if _signature() != _last_signature:
		_run_check()


func _run_check() -> void:
	var mission := layered_map.mission
	_issues.clear()
	_pieces = []
	_last_signature = _signature()
	if mission == null:
		_problems_button.visible = false
		return
	var result := MapPlanValidator.validate_mission(mission)
	_pieces = result["pieces"]
	for kind in ["errors", "warnings"]:
		for issue: Dictionary in result[kind]:
			_issues.append({"severity": issue["severity"], "message": str(issue["message"]), "piece": int(issue["piece"])})
	_problems_button.visible = true
	var errors: int = (result["errors"] as Array).size()
	var warnings: int = (result["warnings"] as Array).size()
	if errors + warnings == 0:
		_problems_button.text = "No problems"
		_problems_button.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	else:
		_problems_button.text = "⚠ Problems (%d)" % (errors + warnings)
		_problems_button.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if errors > 0 else Color(1.0, 0.82, 0.4))
	if _problems_dialog.visible:
		_fill_problems_dialog()


func _open_problems_dialog() -> void:
	_run_check()
	_fill_problems_dialog()
	_problems_dialog.popup_centered_clamped(Vector2i(600, 400), 0.9)


func _fill_problems_dialog() -> void:
	for child in _problems_list.get_children():
		_problems_list.remove_child(child)
		child.free()
	if _issues.is_empty():
		var ok := Label.new()
		ok.text = "No problems - everything the checks look at is in order."
		_problems_list.add_child(ok)
		return
	for issue in _issues:
		var row := HBoxContainer.new()
		var is_error: bool = issue["severity"] == "error"
		var label := Label.new()
		label.text = ("Error: " if is_error else "Warning: ") + str(issue["message"])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 440.0  # a wrapping label needs a width to start from
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5) if is_error else Color(1.0, 0.82, 0.5))
		row.add_child(label)
		var piece_index: int = issue["piece"]
		if piece_index >= 0 and piece_index < _pieces.size() and (_pieces[piece_index] as Dictionary).has("node_id"):
			var show := Button.new()
			show.text = "Show"
			show.tooltip_text = "Select the piece in the outline and jump the camera to it."
			show.pressed.connect(_show_piece.bind(piece_index))
			row.add_child(show)
		_problems_list.add_child(row)


## Select the piece in the outline (switching to its tab) and move the camera there.
func _show_piece(piece_index: int) -> void:
	if piece_index < 0 or piece_index >= _pieces.size():
		return
	var piece: Dictionary = _pieces[piece_index]
	var grid: GridMap = layered_map.prop_grid
	if piece["layer"] == "floor":
		grid = layered_map.floor_grid
	elif piece["layer"] == "underlay":
		grid = layered_map.underlay_grid
	creator_controller.jump_to_cell(piece["fine_origin"], grid)
	if creator_outline != null:
		var node: Node = creator_outline
		while node.get_parent() != null and not (node.get_parent() is TabContainer):
			node = node.get_parent()
		if node.get_parent() is TabContainer:
			(node.get_parent() as TabContainer).current_tab = node.get_index()
		creator_outline.select_id(str(piece["node_id"]))


# ---------------------------------------------------------------- languages

func _read_only() -> bool:
	var save_load := get_node_or_null("../MenuBar/File") as CreatorSaveLoad
	return save_load != null and save_load.read_only


## From now on the texts are read, shown and written in `language`.
func _use_language(language: String) -> void:
	LText.use_for_editing(language, layered_map.mission.default_language)
	GameState.editor_language = language


## A mission that was loaded, started or restored by undo is another object: its languages are read again, and the editing language must be one it has.
func _on_mission_maybe_replaced() -> void:
	if layered_map.mission != _bar_mission:
		_sync_language()


func _sync_language() -> void:
	var mission := layered_map.mission
	if mission == null or _language_bar == null:
		return
	_bar_mission = mission
	var wanted := LText.edit_language if LText.edit_language != "" else GameState.editor_language
	_use_language(wanted if mission.default_language == wanted or mission.languages.has(wanted) else mission.default_language)
	_update_language_bar()
	_translation_window.refresh()


func _update_language_bar() -> void:
	var mission := layered_map.mission
	var codes := TextWalker.content_languages(mission, TextWalker.collect(mission))
	_language_bar.show_languages(codes, LText.edit_language, mission.default_language)


func _on_language_selected(language: String) -> void:
	_use_language(language)
	_update_language_bar()
	layered_map.notify_objects_changed()  # the outline and the properties panel show the texts again


## What the languages dialog and the translation window do to the mission: one undo step, then everything is shown again.
func _commit_language_change(label: String, mutate: Callable) -> void:
	if _read_only():
		return
	creator_controller.operation_history.record(label, mutate)
	_bar_mission = layered_map.mission
	layered_map.notify_objects_changed()
	_update_language_bar()


func _open_languages_dialog() -> void:
	_languages_dialog.read_only = _read_only()
	_languages_dialog.open()


func _open_translation_window() -> void:
	_translation_window.read_only = _read_only()
	_translation_window.open(LText.edit_language)
