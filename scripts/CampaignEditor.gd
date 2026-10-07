class_name CampaignEditor
extends Control

## The campaign editor (standalone scene, opened from the main menu): create or open a
## campaign (a folder under user://campaigns/, see CampaignIO), then edit its acts. Each act
## has a map image and chapters pinned on it (CampaignMapView - drag pins to place them);
## each chapter picks a mission (copied into the campaign folder), optional story texts and
## links to the chapters that follow a win or a loss. A chapter can be the act's start or
## a finale. "Problems" lists what is wrong with each act's path (no start, unreachable
## chapters, missing missions, no reachable finale).
##
## Edits are not undo-tracked; they are saved with Save, and automatically when switching to
## another campaign or leaving (so nothing is lost). Built entirely in code.

const MENU_SCENE := "res://ui/MainMenu.tscn"

var _campaign: Campaign
var _folder: String = ""
var _act_index: int = -1
var _selected: CampaignChapter
var _selected_place: CampaignPlace
var _selected_quest: CampaignSideQuest
var _condition_editor: EffectEditor
var _effect_editor: EffectEditor
var _variables_dialog: MissionVariablesDialog
var _dirty: bool = false

var _status_label: Label
var _tabs: TabContainer
var _file_menu: PopupMenu
var _edit_menu: PopupMenu
var _open_menu: PopupMenu
var _open_folders: Array[String] = []

enum FileAction { NEW, SAVE, BACK, OPEN }
enum EditAction { UNDO, REDO }

## Undo/redo works on whole-campaign snapshots (like the mission editor's OperationHistory):
## `_baseline` is a copy of the campaign as of the last recorded edit, and every edit pushes the
## previous baseline on the undo stack. Edits less than UNDO_MELD_MSEC apart (typing, dragging a
## pin) share one undo step.
const MAX_UNDO := 50
const UNDO_MELD_MSEC := 1500
var _baseline: Campaign
var _undo_stack: Array[Campaign] = []
var _redo_stack: Array[Campaign] = []
var _last_edit_msec: int = 0
var _body: Control
var _welcome_label: Label
var _campaign_name_edit: LineEdit
var _campaign_intro_edit: TextEdit
var _start_xp_spin: SpinBox
var _acts_list: ItemList
var _act_name_edit: LineEdit
var _act_intro_edit: TextEdit
var _map_label: Label
var _cover_label: Label
var _cover_preview: TextureRect
var _cover_dialog: FileDialog
var _problems_label: Label
var _map_view: CampaignMapView
var _chapter_panel: VBoxContainer
var _suppress: bool = false

var _new_dialog: ConfirmationDialog
## Asks "are you sure" before something destructive; `_confirm_action` runs when confirmed.
var _confirm_dialog: ConfirmationDialog
var _confirm_action: Callable
var _new_name_edit: LineEdit
var _image_dialog: FileDialog
var _mission_dialog: FileDialog
var _notice: AcceptDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	# --- menu bar (File, like the mission editor's)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	var menu_bar := MenuBar.new()
	bar.add_child(menu_bar)
	_file_menu = PopupMenu.new()
	_file_menu.name = "File"
	menu_bar.add_child(_file_menu)
	_open_menu = PopupMenu.new()
	_open_menu.name = "OpenMenu"
	_open_menu.index_pressed.connect(_on_open_index_pressed)
	_file_menu.add_child(_open_menu)
	_file_menu.add_item("New", FileAction.NEW, (KEY_MASK_CTRL | KEY_N) as Key)
	_file_menu.add_submenu_node_item("Open", _open_menu, FileAction.OPEN)
	_file_menu.add_item("Save", FileAction.SAVE, (KEY_MASK_CTRL | KEY_S) as Key)
	_file_menu.add_separator()
	_file_menu.add_item("Back to Menu", FileAction.BACK)
	_file_menu.id_pressed.connect(_on_file_action)
	_edit_menu = PopupMenu.new()
	_edit_menu.name = "Edit"
	menu_bar.add_child(_edit_menu)
	_edit_menu.add_item("Undo", EditAction.UNDO, (KEY_MASK_CTRL | KEY_Z) as Key)
	_edit_menu.add_item("Redo", EditAction.REDO, (KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_Z) as Key)
	_edit_menu.id_pressed.connect(_on_edit_action)
	_update_edit_menu()
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status_label)

	_welcome_label = Label.new()
	_welcome_label.text = "Create a new campaign or open an existing one."
	root.add_child(_welcome_label)

	# --- body: the map (as big as possible) | tabs on the right: Campaign / Selection
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_body = split

	_map_view = CampaignMapView.new()
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size = Vector2(400, 300)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_view.chapter_selected.connect(_on_map_chapter_selected)
	_map_view.chapter_moved.connect(func(_id: String): _mark_dirty())
	_map_view.place_selected.connect(_on_map_place_selected)
	_map_view.place_moved.connect(func(_id: String): _mark_dirty())
	_map_view.side_quest_selected.connect(_on_map_side_quest_selected)
	_map_view.side_quest_moved.connect(func(_id: String): _mark_dirty())
	var map_column := VBoxContainer.new()
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_stretch_ratio = 4.0
	split.add_child(map_column)
	var map_toolbar := HBoxContainer.new()
	map_column.add_child(map_toolbar)
	map_toolbar.add_child(_button("Add chapter", _on_add_chapter_pressed))
	map_toolbar.add_child(_button("Add place", _on_add_place_pressed))
	map_toolbar.add_child(_button("Add side quest", _on_add_side_quest_pressed))
	map_column.add_child(_map_view)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size.x = 360
	split.add_child(_tabs)

	var left_scroll := ScrollContainer.new()
	left_scroll.name = "Campaign"
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)

	left.add_child(_label("Campaign name:"))
	_campaign_name_edit = LineEdit.new()
	_campaign_name_edit.text_changed.connect(func(text: String):
		if _suppress or _campaign == null:
			return
		_campaign.campaign_name = text
		_mark_dirty()
	)
	left.add_child(_campaign_name_edit)
	left.add_child(_label("Introduction:"))
	_campaign_intro_edit = _text_edit(80)
	_campaign_intro_edit.text_changed.connect(func():
		if _suppress or _campaign == null:
			return
		_campaign.intro = _campaign_intro_edit.text
		_mark_dirty()
	)
	left.add_child(_campaign_intro_edit)
	var cover_row := HBoxContainer.new()
	left.add_child(cover_row)
	cover_row.add_child(_button("Book cover…", func(): _cover_dialog.popup_centered_ratio(0.6)))
	cover_row.add_child(_button("Clear cover", _on_clear_cover_pressed))
	left.add_child(_button("Variables…", func(): _variables_dialog.open_for_list(_campaign.variables, func(_label: String, mutate: Callable):
		mutate.call()
		_mark_dirty()
	)))
	_cover_label = _label("")
	left.add_child(_cover_label)
	_cover_preview = TextureRect.new()
	_cover_preview.custom_minimum_size = Vector2(120, 180)
	_cover_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover_preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_cover_preview)

	left.add_child(HSeparator.new())
	left.add_child(_label("Acts:"))
	_acts_list = ItemList.new()
	_acts_list.custom_minimum_size.y = 110
	_acts_list.item_selected.connect(func(index: int):
		_act_index = index
		_selected = null
		_selected_place = null
		_selected_quest = null
		_refresh_act()
	)
	left.add_child(_acts_list)
	var act_buttons := HBoxContainer.new()
	left.add_child(act_buttons)
	act_buttons.add_child(_button("Add act", _on_add_act_pressed))
	act_buttons.add_child(_button("Remove", _on_remove_act_pressed))
	act_buttons.add_child(_button("↑", func(): _move_act(-1)))
	act_buttons.add_child(_button("↓", func(): _move_act(1)))

	left.add_child(_label("Act name:"))
	_act_name_edit = LineEdit.new()
	_act_name_edit.text_changed.connect(func(text: String):
		var act := _current_act()
		if _suppress or act == null:
			return
		act.act_name = text
		_acts_list.set_item_text(_act_index, text)
		_mark_dirty()
	)
	left.add_child(_act_name_edit)
	left.add_child(_label("Act introduction:"))
	_act_intro_edit = _text_edit(80)
	_act_intro_edit.text_changed.connect(func():
		var act := _current_act()
		if _suppress or act == null:
			return
		act.intro = _act_intro_edit.text
		_mark_dirty()
	)
	left.add_child(_act_intro_edit)
	var xp_row := HBoxContainer.new()
	left.add_child(xp_row)
	xp_row.add_child(_label("XP when the act begins (-1 = keep):"))
	_start_xp_spin = SpinBox.new()
	_start_xp_spin.min_value = -1
	_start_xp_spin.max_value = 9999
	_start_xp_spin.value_changed.connect(func(value: float):
		var act := _current_act()
		if _suppress or act == null:
			return
		act.start_experience = int(value)
		_mark_dirty()
	)
	xp_row.add_child(_start_xp_spin)
	var map_row := HBoxContainer.new()
	left.add_child(map_row)
	map_row.add_child(_button("Map image…", func(): _image_dialog.popup_centered_ratio(0.6)))
	map_row.add_child(_button("Clear map", _on_clear_map_pressed))
	_map_label = _label("")
	left.add_child(_map_label)
	left.add_child(HSeparator.new())
	left.add_child(_label("Problems:"))
	_problems_label = _label("")
	_problems_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_problems_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.4))
	left.add_child(_problems_label)

	var right_scroll := ScrollContainer.new()
	right_scroll.name = "Selection"
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(right_scroll)
	_chapter_panel = VBoxContainer.new()
	_chapter_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(_chapter_panel)

	# --- dialogs
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "New campaign"
	_new_name_edit = LineEdit.new()
	_new_name_edit.placeholder_text = "Campaign name"
	_new_dialog.add_child(_new_name_edit)
	_new_dialog.confirmed.connect(_on_new_confirmed)
	add_child(_new_dialog)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Are you sure?"
	_confirm_dialog.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm_dialog)

	_image_dialog = FileDialog.new()
	_image_dialog.title = "Choose the map image of this act"
	_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_image_dialog.file_selected.connect(_on_image_selected)
	add_child(_image_dialog)

	_cover_dialog = FileDialog.new()
	_cover_dialog.title = "Choose the book cover (it is trimmed to a 2:3 portrait)"
	_cover_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_cover_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_cover_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_cover_dialog.file_selected.connect(_on_cover_selected)
	add_child(_cover_dialog)

	_mission_dialog = FileDialog.new()
	_mission_dialog.title = "Add a mission to this campaign"
	_mission_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_mission_dialog.access = FileDialog.ACCESS_USERDATA
	_mission_dialog.filters = PackedStringArray(["*.tres ; Missions"])
	_mission_dialog.file_selected.connect(_on_mission_file_selected)
	add_child(_mission_dialog)

	_notice = AcceptDialog.new()
	add_child(_notice)

	# The conditions of a side quest are edited with the mission editor's own condition rows, over the
	# campaign's values.
	var commit := func(_label: String, mutate: Callable):
		mutate.call()
		_mark_dirty()
	_condition_editor = EffectEditor.new()
	_condition_editor.setup(self, commit)
	# What happens when a chapter or side quest is won / lost: set a variable or do math on it.
	_effect_editor = EffectEditor.new()
	_effect_editor.allowed_effect_types = [Effect.Type.SET_VARIABLE, Effect.Type.MATH]
	_effect_editor.mission = MissionData.new()
	_effect_editor.setup(self, commit)
	_variables_dialog = MissionVariablesDialog.new()
	add_child(_variables_dialog)

	_refresh_open_list()
	_refresh_all()


# ---------------------------------------------------------------- campaign files

func _refresh_open_list() -> void:
	_open_folders = CampaignIO.folder_names()
	_open_menu.clear()
	for folder in _open_folders:
		_open_menu.add_radio_check_item(folder)
		_open_menu.set_item_checked(_open_menu.item_count - 1, folder == _folder)


func _on_file_action(id: int) -> void:
	match id:
		FileAction.NEW:
			_new_name_edit.text = ""
			_new_dialog.popup_centered()
		FileAction.SAVE:
			_save()
		FileAction.BACK:
			_on_back_pressed()


func _on_new_confirmed() -> void:
	var key := CampaignIO.key_for(_new_name_edit.text)
	if key == "":
		_say("A campaign needs a name.")
		return
	if _open_folders.has(key):
		_say("A campaign called '%s' already exists." % key)
		return
	_save_if_dirty()
	var campaign := Campaign.new()
	campaign.campaign_name = _new_name_edit.text.strip_edges()
	campaign.acts.append(CampaignAct.new())
	if not CampaignIO.save_campaign(campaign, key):
		_say("Could not create the campaign.")
		return
	_load_folder(key)


func _on_open_index_pressed(index: int) -> void:
	if index < 0 or index >= _open_folders.size():
		return
	_save_if_dirty()
	_load_folder(_open_folders[index])


func _load_folder(folder: String) -> void:
	var campaign := CampaignIO.load_campaign(folder)
	if campaign == null:
		_say("Could not open '%s'." % folder)
		return
	_campaign = campaign
	_folder = folder
	_act_index = 0 if not campaign.acts.is_empty() else -1
	_selected = null
	_selected_place = null
	_selected_quest = null
	_dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	_baseline = campaign.duplicate(true)
	_update_edit_menu()
	_refresh_open_list()
	_refresh_all()
	_status_label.text = "Opened %s" % folder


func _save() -> void:
	if _campaign == null:
		return
	if CampaignIO.save_campaign(_campaign, _folder):
		_dirty = false
		_status_label.text = "Saved %s" % _folder
	else:
		_status_label.text = "Could not save!"


func _save_if_dirty() -> void:
	if _dirty:
		_save()


func _on_back_pressed() -> void:
	_save_if_dirty()
	get_tree().change_scene_to_file(MENU_SCENE)


func _mark_dirty() -> void:
	_dirty = true
	_status_label.text = "Unsaved changes"
	_record_edit()
	_update_problems()


func _record_edit() -> void:
	if _campaign == null or _baseline == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_edit_msec > UNDO_MELD_MSEC:
		_undo_stack.append(_baseline)
		if _undo_stack.size() > MAX_UNDO:
			_undo_stack.pop_front()
	_baseline = _campaign.duplicate(true)
	_redo_stack.clear()
	_last_edit_msec = now
	_update_edit_menu()


func _on_edit_action(id: int) -> void:
	match id:
		EditAction.UNDO:
			_step_history(_undo_stack, _redo_stack)
		EditAction.REDO:
			_step_history(_redo_stack, _undo_stack)


## Swaps the campaign for the newest snapshot of `from`; the current state goes onto `to`.
func _step_history(from: Array[Campaign], to: Array[Campaign]) -> void:
	if _campaign == null or from.is_empty():
		return
	var chapter_id := _selected.id if _selected != null else ""
	var place_id := _selected_place.id if _selected_place != null else ""
	var quest_id := _selected_quest.id if _selected_quest != null else ""
	to.append(_baseline)
	_campaign = from.pop_back()
	_baseline = _campaign.duplicate(true)
	_last_edit_msec = 0
	_act_index = clampi(_act_index, 0, _campaign.acts.size() - 1) if not _campaign.acts.is_empty() else -1
	var act := _current_act()
	_selected = act.find_chapter(chapter_id) if act != null and chapter_id != "" else null
	_selected_place = act.find_place(place_id) if act != null and place_id != "" else null
	_selected_quest = _campaign.find_side_quest(quest_id) if quest_id != "" else null
	_dirty = true
	_status_label.text = "Unsaved changes"
	_update_edit_menu()
	_refresh_all()


func _update_edit_menu() -> void:
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.UNDO), _undo_stack.is_empty())
	_edit_menu.set_item_disabled(_edit_menu.get_item_index(EditAction.REDO), _redo_stack.is_empty())


# ---------------------------------------------------------------- acts

func _current_act() -> CampaignAct:
	if _campaign == null or _act_index < 0 or _act_index >= _campaign.acts.size():
		return null
	return _campaign.acts[_act_index]


func _on_add_act_pressed() -> void:
	if _campaign == null:
		return
	var act := CampaignAct.new()
	act.act_name = "Act %d" % (_campaign.acts.size() + 1)
	_campaign.acts.append(act)
	_act_index = _campaign.acts.size() - 1
	_selected = null
	_mark_dirty()
	_refresh_all()


func _on_remove_act_pressed() -> void:
	var act := _current_act()
	if act == null:
		return
	_confirm("Remove the act '%s' with its %d chapter(s) and places?" % [act.act_name, act.chapters.size()], _remove_current_act)


func _remove_current_act() -> void:
	if _current_act() == null:
		return
	_campaign.acts.remove_at(_act_index)
	_act_index = mini(_act_index, _campaign.acts.size() - 1)
	_selected = null
	_mark_dirty()
	_refresh_all()


func _move_act(delta: int) -> void:
	var other := _act_index + delta
	if _current_act() == null or other < 0 or other >= _campaign.acts.size():
		return
	var moved := _campaign.acts[_act_index]
	_campaign.acts[_act_index] = _campaign.acts[other]
	_campaign.acts[other] = moved
	_act_index = other
	_mark_dirty()
	_refresh_all()


func _on_image_selected(path: String) -> void:
	var act := _current_act()
	if act == null:
		return
	var file := CampaignIO.import_map_image(_folder, path, _act_index + 1)
	if file == "":
		_say("Could not copy the image into the campaign.")
		return
	act.map_image = file
	_mark_dirty()
	_refresh_act()


func _on_cover_selected(path: String) -> void:
	if _campaign == null:
		return
	var file := CampaignIO.import_cover_image(_folder, path)
	if file == "":
		_say("Could not read that image.")
		return
	_campaign.cover_image = file
	_mark_dirty()
	_refresh_all()


func _on_clear_cover_pressed() -> void:
	if _campaign == null:
		return
	_campaign.cover_image = ""
	_mark_dirty()
	_refresh_all()


func _on_clear_map_pressed() -> void:
	var act := _current_act()
	if act == null:
		return
	act.map_image = ""
	_mark_dirty()
	_refresh_act()


# ---------------------------------------------------------------- chapters

func _on_add_chapter_pressed() -> void:
	var act := _current_act()
	if act == null:
		return
	var chapter := CampaignChapter.new()
	chapter.id = _campaign.new_chapter_id()
	chapter.title = "Chapter %d" % (act.chapters.size() + 1)
	# A slightly different spot each time so new pins don't pile up on one another.
	chapter.map_position = Vector2(0.15 + 0.1 * (act.chapters.size() % 8), 0.2 + 0.08 * (act.chapters.size() % 8))
	act.chapters.append(chapter)
	if act.start_chapter_id == "":
		act.start_chapter_id = chapter.id
	_selected = chapter
	_selected_place = null
	_selected_quest = null
	_tabs.current_tab = 1
	_mark_dirty()
	_refresh_act()


func _on_map_chapter_selected(chapter_id: String) -> void:
	var act := _current_act()
	if act == null:
		return
	_selected = act.find_chapter(chapter_id)
	_selected_place = null
	_selected_quest = null
	_tabs.current_tab = 1
	_rebuild_chapter_panel()


func _confirm(text: String, action: Callable) -> void:
	_confirm_action = action
	_confirm_dialog.dialog_text = text
	_confirm_dialog.popup_centered()


func _on_delete_chapter_pressed(chapter: CampaignChapter) -> void:
	_confirm("Delete the chapter '%s'?
Links to it are removed too." % chapter.title, func(): _delete_chapter(chapter))


func _delete_chapter(chapter: CampaignChapter) -> void:
	var act := _current_act()
	if act == null:
		return
	act.chapters.erase(chapter)
	for other in act.chapters:
		for link in other.links.duplicate():
			if link.target_id == chapter.id:
				other.links.erase(link)
	if act.start_chapter_id == chapter.id:
		act.start_chapter_id = ""
	for place in act.places:
		if place.unlocked_by_chapter == chapter.id:
			place.unlocked_by_chapter = ""
	for quest in _campaign.side_quests:
		quest.chapter_ids.erase(chapter.id)
	_selected = null
	_mark_dirty()
	_refresh_act()


func _on_mission_file_selected(path: String) -> void:
	if _selected == null and _selected_quest == null:
		return
	var file := CampaignIO.import_mission(_folder, path)
	if file == "":
		_say("Could not copy the mission into the campaign.")
		return
	if _selected_quest != null:
		_selected_quest.mission_file = file
	else:
		_selected.mission_file = file
	_mark_dirty()
	_rebuild_chapter_panel()


# ---------------------------------------------------------------- side quests

## The side quests shown on `act`'s map: the ones linked to one of its chapters, plus the ones not linked
## yet (so a new one can be placed and linked).
func _no_quests() -> Array[CampaignSideQuest]:
	return []


func _quests_on_act(act: CampaignAct) -> Array[CampaignSideQuest]:
	var shown: Array[CampaignSideQuest] = []
	for quest in _campaign.side_quests:
		var on_act := quest.chapter_ids.is_empty()
		for chapter_id in quest.chapter_ids:
			if act.find_chapter(chapter_id) != null:
				on_act = true
		if on_act:
			shown.append(quest)
	return shown


func _on_add_side_quest_pressed() -> void:
	var act := _current_act()
	if act == null:
		return
	var quest := CampaignSideQuest.new()
	quest.id = _campaign.new_side_quest_id()
	quest.title = "Side quest %d" % (_campaign.side_quests.size() + 1)
	quest.map_position = Vector2(0.5 + 0.06 * (_campaign.side_quests.size() % 6), 0.15 + 0.07 * (_campaign.side_quests.size() % 6))
	if _selected != null:
		quest.chapter_ids.append(_selected.id)  # offered at the chapter that is selected right now
	_campaign.side_quests.append(quest)
	_selected = null
	_selected_place = null
	_selected_quest = quest
	_tabs.current_tab = 1
	_mark_dirty()
	_refresh_act()


func _on_map_side_quest_selected(quest_id: String) -> void:
	_selected = null
	_selected_place = null
	_selected_quest = _campaign.find_side_quest(quest_id)
	_tabs.current_tab = 1
	_rebuild_chapter_panel()


## Rows linking a variable of the mission (listed by reading the mission file, so no typing) with a campaign
## variable of the same type. `from_mission` true = "take over from the mission" (mission_outputs: mission
## variable -> a writable campaign variable, copied when the mission ends); false = "give to the mission"
## (mission_inputs: any campaign variable -> a mission variable, preset when the mission starts).
func _build_mapping_section(heading: String, maps: Array[MissionVariableMap], mission_file: String, from_mission: bool) -> void:
	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label(heading))
	var declared := CampaignIO.mission_variables(_folder, mission_file)
	var campaign_side := _campaign.writable_variables() if from_mission else _campaign.all_variables()
	var left_list := declared if from_mission else campaign_side
	var right_list := campaign_side if from_mission else declared
	var left_property := "mission_variable" if from_mission else "campaign_variable"
	var right_property := "campaign_variable" if from_mission else "mission_variable"
	for link in maps:
		var row := HBoxContainer.new()
		var left_option := OptionButton.new()
		var left_index := -1
		var left_type := -1
		for i in left_list.size():
			left_option.add_item(left_list[i].name)
			if left_list[i].name == link.get(left_property):
				left_index = i
				left_type = left_list[i].type
		left_option.select(left_index)
		left_option.item_selected.connect(func(index: int):
			link.set(left_property, left_list[index].name)
			_mark_dirty()
			_rebuild_chapter_panel()
		)
		row.add_child(left_option)
		row.add_child(_label("→"))
		var right_option := OptionButton.new()
		var candidates: Array[MissionVariable] = []
		for variable in right_list:
			if left_type == -1 or variable.type == left_type:
				candidates.append(variable)
				right_option.add_item(variable.name)
		var right_index := -1
		for i in candidates.size():
			if candidates[i].name == link.get(right_property):
				right_index = i
		right_option.select(right_index)
		right_option.item_selected.connect(func(index: int):
			link.set(right_property, candidates[index].name)
			_mark_dirty()
		)
		row.add_child(right_option)
		row.add_child(_button("×", func():
			maps.erase(link)
			_mark_dirty()
			_rebuild_chapter_panel()
		))
		_chapter_panel.add_child(row)
	var add := _button("Add", func():
		maps.append(MissionVariableMap.new())
		_mark_dirty()
		_rebuild_chapter_panel()
	)
	add.disabled = declared.is_empty()
	add.tooltip_text = "The mission declares no variables yet (Variables… in the mission editor)." if declared.is_empty() else ""
	_chapter_panel.add_child(add)


## A list of effects (set a variable / do math on it) the campaign applies when a chapter or side quest is
## won or lost, in the panel on the right.
func _build_effects_section(heading: String, effects: Array[Effect]) -> void:
	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label(heading))
	_effect_editor.campaign_variables = _campaign.writable_variables()
	for effect in effects:
		_chapter_panel.add_child(_effect_editor.build_effect_row(effects, effect, _rebuild_chapter_panel))
	_chapter_panel.add_child(_button("Add effect", func():
		var created := Effect.new()
		created.type = Effect.Type.SET_VARIABLE
		created.variable_name = _campaign.writable_variables()[0].name
		created.value = 0
		effects.append(created)
		_mark_dirty()
		_rebuild_chapter_panel()
	))


func _delete_side_quest(quest: CampaignSideQuest) -> void:
	_campaign.side_quests.erase(quest)
	_selected_quest = null
	_mark_dirty()
	_refresh_act()


## The right-hand panel for a selected side quest: its mission, rewards, stories, the chapters it is offered
## at and the conditions that have to hold.
func _build_side_quest_panel(quest: CampaignSideQuest) -> void:
	_map_view.selected_id = quest.id
	_map_view.queue_redraw()
	_chapter_panel.add_child(_label("Side quest title:"))
	var title_edit := LineEdit.new()
	title_edit.text = quest.title
	title_edit.text_changed.connect(func(text: String):
		quest.title = text
		_mark_dirty()
	)
	_chapter_panel.add_child(title_edit)

	_chapter_panel.add_child(_label("Mission:"))
	var mission_row := HBoxContainer.new()
	_chapter_panel.add_child(mission_row)
	var files := CampaignIO.mission_files(_folder)
	var mission_option := OptionButton.new()
	mission_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_option.add_item("(none)")
	for file in files:
		mission_option.add_item(file)
	if quest.mission_file != "" and not files.has(quest.mission_file):
		mission_option.add_item("%s (missing)" % quest.mission_file)
		mission_option.select(mission_option.item_count - 1)
	else:
		mission_option.select(files.find(quest.mission_file) + 1 if quest.mission_file != "" else 0)
	mission_option.item_selected.connect(func(index: int):
		quest.mission_file = files[index - 1] if index >= 1 and index <= files.size() else quest.mission_file if index > files.size() else ""
		_mark_dirty()
	)
	mission_row.add_child(mission_option)
	mission_row.add_child(_button("Add mission…", func():
		_mission_dialog.current_dir = "user://missions"
		_mission_dialog.popup_centered_ratio(0.6)
	))

	var reward_row := HBoxContainer.new()
	_chapter_panel.add_child(reward_row)
	reward_row.add_child(_label("Win gives XP:"))
	reward_row.add_child(_reward_spin(quest.reward_xp, func(value: int): quest.reward_xp = value))
	reward_row.add_child(_label("gold:"))
	reward_row.add_child(_reward_spin(quest.reward_gold, func(value: int): quest.reward_gold = value))
	var materials_row := HBoxContainer.new()
	_chapter_panel.add_child(materials_row)
	materials_row.add_child(_label("Materials won:"))
	var materials_edit := LineEdit.new()
	materials_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials_edit.placeholder_text = "e.g. iron:2, leather:1"
	materials_edit.text = CampaignState.format_materials(quest.reward_materials)
	var commit_materials := func():
		quest.reward_materials = CampaignState.parse_materials(materials_edit.text)
		_mark_dirty()
	materials_edit.text_submitted.connect(func(_t: String): commit_materials.call())
	materials_edit.focus_exited.connect(commit_materials)
	materials_row.add_child(materials_edit)

	_chapter_panel.add_child(_label("Story before the mission:"))
	var before_edit := _text_edit(80)
	before_edit.text = quest.story_before
	before_edit.text_changed.connect(func():
		quest.story_before = before_edit.text
		_mark_dirty()
	)
	_chapter_panel.add_child(before_edit)
	_chapter_panel.add_child(_label("Story after the mission:"))
	var after_edit := _text_edit(80)
	after_edit.text = quest.story_after
	after_edit.text_changed.connect(func():
		quest.story_after = after_edit.text
		_mark_dirty()
	)
	_chapter_panel.add_child(after_edit)

	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label("Offered while the party is at one of these chapters:"))
	for act in _campaign.acts:
		for chapter in act.chapters:
			var check := CheckBox.new()
			check.text = "%s - %s" % [act.act_name, chapter.title]
			check.button_pressed = quest.chapter_ids.has(chapter.id)
			check.toggled.connect(func(on: bool):
				if on and not quest.chapter_ids.has(chapter.id):
					quest.chapter_ids.append(chapter.id)
				elif not on:
					quest.chapter_ids.erase(chapter.id)
				_mark_dirty()
				_map_view.side_quests = _quests_on_act(_current_act()) if _current_act() != null else _no_quests()
				_map_view.queue_redraw()
			)
			_chapter_panel.add_child(check)

	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label("Only offered when:"))
	_condition_editor.campaign_variables = _campaign.all_variables()
	for condition in quest.conditions:
		_chapter_panel.add_child(_condition_editor.build_condition_row(quest.conditions, condition, _rebuild_chapter_panel))
	_chapter_panel.add_child(_button("Add condition", func():
		var created := Condition.new()
		created.variable_name = Campaign.BUILTIN_VARIABLES[0]
		created.operator = Condition.Operator.GREATER_EQUAL
		created.value = 0
		quest.conditions.append(created)
		_mark_dirty()
		_rebuild_chapter_panel()
	))

	_build_mapping_section("Give to the mission when it starts:", quest.mission_inputs, quest.mission_file, false)
	_build_mapping_section("Take over from the mission when it ends:", quest.mission_outputs, quest.mission_file, true)
	_build_effects_section("When won, set:", quest.win_effects)
	_build_effects_section("When lost, set:", quest.lose_effects)
	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_button("Delete side quest", func(): _delete_side_quest(quest)))


# ---------------------------------------------------------------- places

func _selected_id() -> String:
	if _selected_quest != null:
		return _selected_quest.id
	if _selected_place != null:
		return _selected_place.id
	return _selected.id if _selected != null else ""


func _on_add_place_pressed() -> void:
	var act := _current_act()
	if act == null:
		return
	var place := CampaignPlace.new()
	place.id = _campaign.new_place_id()
	place.title = "Place %d" % (act.places.size() + 1)
	place.map_position = Vector2(0.8 - 0.08 * (act.places.size() % 6), 0.8 - 0.06 * (act.places.size() % 6))
	act.places.append(place)
	_selected_place = place
	_selected = null
	_tabs.current_tab = 1
	_mark_dirty()
	_refresh_act()


func _on_map_place_selected(place_id: String) -> void:
	var act := _current_act()
	if act == null:
		return
	_selected_place = act.find_place(place_id)
	_selected = null
	_tabs.current_tab = 1
	_rebuild_chapter_panel()


func _delete_place(place: CampaignPlace) -> void:
	var act := _current_act()
	if act == null:
		return
	act.places.erase(place)
	_selected_place = null
	_selected_quest = null
	_mark_dirty()
	_refresh_act()


## The right-hand panel for a selected place: its name, description, which chapter unlocks it and
## its offers (cost in gold/materials, the attachment it gives, once-only or not).
func _build_place_panel(act: CampaignAct, place: CampaignPlace) -> void:
	_map_view.selected_id = place.id
	_map_view.queue_redraw()
	_chapter_panel.add_child(_label("Place name:"))
	var title_edit := LineEdit.new()
	title_edit.text = place.title
	title_edit.text_changed.connect(func(text: String):
		place.title = text
		_mark_dirty()
	)
	_chapter_panel.add_child(title_edit)
	_chapter_panel.add_child(_label("Description:"))
	var description_edit := _text_edit(60)
	description_edit.text = place.description
	description_edit.text_changed.connect(func():
		place.description = description_edit.text
		_mark_dirty()
	)
	_chapter_panel.add_child(description_edit)

	_chapter_panel.add_child(_label("Opens when this chapter is won:"))
	var unlock_option := OptionButton.new()
	unlock_option.add_item("(from the start of the act)")
	var unlock_index := 0
	for i in act.chapters.size():
		unlock_option.add_item(act.chapters[i].title)
		if act.chapters[i].id == place.unlocked_by_chapter:
			unlock_index = i + 1
	unlock_option.select(unlock_index)
	unlock_option.item_selected.connect(func(index: int):
		place.unlocked_by_chapter = act.chapters[index - 1].id if index >= 1 else ""
		_mark_dirty()
	)
	_chapter_panel.add_child(unlock_option)

	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label("Offers:"))
	var attachment_names: Array[String] = []
	for attachment in AttachmentCatalog.all():
		attachment_names.append(attachment.attachment_name)
	for offer in place.offers:
		_chapter_panel.add_child(_build_offer_block(place, offer, attachment_names))
	_chapter_panel.add_child(_button("Add offer", func():
		var created := CampaignOffer.new()
		created.id = _campaign.new_offer_id()
		place.offers.append(created)
		_mark_dirty()
		_rebuild_chapter_panel()
	))
	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_button("Delete place", func(): _delete_place(place)))


func _build_offer_block(place: CampaignPlace, offer: CampaignOffer, attachment_names: Array[String]) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	panel.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var title_edit := LineEdit.new()
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.text = offer.title
	title_edit.text_changed.connect(func(text: String):
		offer.title = text
		_mark_dirty()
	)
	top.add_child(title_edit)
	top.add_child(_button("×", func():
		place.offers.erase(offer)
		_mark_dirty()
		_rebuild_chapter_panel()
	))
	var description_edit := LineEdit.new()
	description_edit.placeholder_text = "Description"
	description_edit.text = offer.description
	description_edit.text_changed.connect(func(text: String):
		offer.description = text
		_mark_dirty()
	)
	box.add_child(description_edit)
	var cost_row := HBoxContainer.new()
	box.add_child(cost_row)
	cost_row.add_child(_label("Gold:"))
	cost_row.add_child(_reward_spin(offer.cost_gold, func(value: int): offer.cost_gold = value))
	cost_row.add_child(_label("Materials:"))
	var materials_edit := LineEdit.new()
	materials_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials_edit.placeholder_text = "iron:2, leather:1"
	materials_edit.text = CampaignState.format_materials(offer.cost_materials)
	var commit_materials := func():
		offer.cost_materials = CampaignState.parse_materials(materials_edit.text)
		_mark_dirty()
	materials_edit.text_submitted.connect(func(_t: String): commit_materials.call())
	materials_edit.focus_exited.connect(commit_materials)
	cost_row.add_child(materials_edit)
	var give_row := HBoxContainer.new()
	box.add_child(give_row)
	give_row.add_child(_label("Gives:"))
	var attachment_option := OptionButton.new()
	attachment_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attachment_option.add_item("(nothing)")
	for attachment_name in attachment_names:
		attachment_option.add_item(attachment_name)
	var attachment_index := attachment_names.find(offer.attachment)
	if offer.attachment != "" and attachment_index < 0:
		attachment_option.add_item("%s (unknown)" % offer.attachment)
		attachment_option.select(attachment_option.item_count - 1)
	else:
		attachment_option.select(attachment_index + 1 if attachment_index >= 0 else 0)
	attachment_option.item_selected.connect(func(index: int):
		if index == 0:
			offer.attachment = ""
		elif index <= attachment_names.size():
			offer.attachment = attachment_names[index - 1]
		_mark_dirty()
	)
	give_row.add_child(attachment_option)
	var once_check := CheckBox.new()
	once_check.text = "Only once"
	once_check.button_pressed = offer.once
	once_check.toggled.connect(func(on: bool):
		offer.once = on
		_mark_dirty()
	)
	give_row.add_child(once_check)
	return panel


# ---------------------------------------------------------------- refreshing

func _refresh_all() -> void:
	var has_campaign := _campaign != null
	_body.visible = has_campaign
	_welcome_label.visible = not has_campaign
	_file_menu.set_item_disabled(_file_menu.get_item_index(FileAction.SAVE), not has_campaign)
	if not has_campaign:
		return
	_suppress = true
	_campaign_name_edit.text = _campaign.campaign_name
	_campaign_intro_edit.text = _campaign.intro
	_cover_label.text = "Book cover: %s (trimmed to 2:3)" % (_campaign.cover_image if _campaign.cover_image != "" else "none - a dummy is shown")
	_cover_preview.texture = CampaignIO.image_texture(_folder, _campaign.cover_image)
	_cover_preview.visible = _cover_preview.texture != null
	_acts_list.clear()
	for act in _campaign.acts:
		_acts_list.add_item(act.act_name)
	if _act_index >= 0:
		_acts_list.select(_act_index)
	_suppress = false
	_refresh_act()


func _refresh_act() -> void:
	var act := _current_act()
	_suppress = true
	_act_name_edit.editable = act != null
	_act_intro_edit.editable = act != null
	_act_name_edit.text = act.act_name if act != null else ""
	_act_intro_edit.text = act.intro if act != null else ""
	_start_xp_spin.editable = act != null
	_start_xp_spin.value = act.start_experience if act != null else -1
	_suppress = false
	_map_label.text = "Map: %s" % (act.map_image if act != null and act.map_image != "" else "none")
	_map_view.side_quests = _quests_on_act(act) if act != null else _no_quests()
	_map_view.show_act(act, CampaignIO.image_texture(_folder, act.map_image) if act != null else null, _selected_id())
	_rebuild_chapter_panel()
	_update_problems()


func _update_problems() -> void:
	if _campaign == null:
		return
	var files := CampaignIO.mission_files(_folder)
	var lines: Array[String] = []
	for act in _campaign.acts:
		for problem in act.problems(files):
			lines.append("%s: %s" % [act.act_name, problem])
	for problem in _campaign.side_quest_problems(files):
		lines.append(problem)
	for problem in CampaignIO.mission_link_problems(_campaign, _folder):
		lines.append(problem)
	_problems_label.text = "\n".join(lines) if not lines.is_empty() else "none"
	_map_view.queue_redraw()


func _rebuild_chapter_panel() -> void:
	for child in _chapter_panel.get_children():
		_chapter_panel.remove_child(child)
		child.queue_free()
	var act := _current_act()
	if act != null and _selected_quest != null:
		_build_side_quest_panel(_selected_quest)
		return
	if act != null and _selected_place != null:
		_build_place_panel(act, _selected_place)
		return
	if act == null or _selected == null:
		_chapter_panel.add_child(_label("Select a chapter, place or side quest on the map, or add one."))
		return
	var chapter := _selected
	_map_view.selected_id = chapter.id
	_map_view.queue_redraw()

	_chapter_panel.add_child(_label("Chapter title:"))
	var title_edit := LineEdit.new()
	title_edit.text = chapter.title
	title_edit.text_changed.connect(func(text: String):
		chapter.title = text
		_mark_dirty()
	)
	_chapter_panel.add_child(title_edit)

	_chapter_panel.add_child(_label("Mission:"))
	var mission_row := HBoxContainer.new()
	_chapter_panel.add_child(mission_row)
	var files := CampaignIO.mission_files(_folder)
	var mission_option := OptionButton.new()
	mission_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission_option.add_item("(none)")
	for file in files:
		mission_option.add_item(file)
	if chapter.mission_file != "" and not files.has(chapter.mission_file):
		mission_option.add_item("%s (missing)" % chapter.mission_file)
		mission_option.select(mission_option.item_count - 1)
	else:
		mission_option.select(files.find(chapter.mission_file) + 1 if chapter.mission_file != "" else 0)
	mission_option.item_selected.connect(func(index: int):
		chapter.mission_file = files[index - 1] if index >= 1 and index <= files.size() else chapter.mission_file if index > files.size() else ""
		_mark_dirty()
	)
	mission_row.add_child(mission_option)
	mission_row.add_child(_button("Add mission…", func():
		_mission_dialog.current_dir = "user://missions"
		_mission_dialog.popup_centered_ratio(0.6)
	))

	var start_check := CheckBox.new()
	start_check.text = "Start of the act"
	start_check.button_pressed = act.start_chapter_id == chapter.id
	start_check.toggled.connect(func(on: bool):
		if on:
			act.start_chapter_id = chapter.id
		elif act.start_chapter_id == chapter.id:
			act.start_chapter_id = ""
		_mark_dirty()
		_map_view.queue_redraw()
	)
	_chapter_panel.add_child(start_check)
	var finale_check := CheckBox.new()
	finale_check.text = "Act finale (winning it ends the act)"
	finale_check.button_pressed = chapter.is_finale
	finale_check.toggled.connect(func(on: bool):
		chapter.is_finale = on
		_mark_dirty()
		_map_view.queue_redraw()
	)
	_chapter_panel.add_child(finale_check)
	var join_check := CheckBox.new()
	join_check.text = "Wait for all chapters that lead here"
	join_check.tooltip_text = "Playable only once every chapter linking to it is won (fan-out, then join). Don't use it after exclusive branches."
	join_check.button_pressed = chapter.wait_for_all
	join_check.toggled.connect(func(on: bool):
		chapter.wait_for_all = on
		_mark_dirty()
	)
	_chapter_panel.add_child(join_check)
	var choice_check := CheckBox.new()
	choice_check.text = "Its links are a choice (only one can be played)"
	choice_check.tooltip_text = "Once the party has won one of the chapters this one links to, the others close for good."
	choice_check.button_pressed = chapter.exclusive_links
	choice_check.toggled.connect(func(on: bool):
		chapter.exclusive_links = on
		_mark_dirty()
	)
	_chapter_panel.add_child(choice_check)

	var reward_row := HBoxContainer.new()
	_chapter_panel.add_child(reward_row)
	reward_row.add_child(_label("Win gives XP:"))
	reward_row.add_child(_reward_spin(chapter.reward_xp, func(value: int): chapter.reward_xp = value))
	reward_row.add_child(_label("gold:"))
	reward_row.add_child(_reward_spin(chapter.reward_gold, func(value: int): chapter.reward_gold = value))

	var materials_row := HBoxContainer.new()
	_chapter_panel.add_child(materials_row)
	materials_row.add_child(_label("Materials won:"))
	var materials_edit := LineEdit.new()
	materials_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	materials_edit.placeholder_text = "e.g. iron:2, leather:1"
	materials_edit.text = CampaignState.format_materials(chapter.reward_materials)
	var commit_materials := func():
		chapter.reward_materials = CampaignState.parse_materials(materials_edit.text)
		_mark_dirty()
	materials_edit.text_submitted.connect(func(_t: String): commit_materials.call())
	materials_edit.focus_exited.connect(commit_materials)
	materials_row.add_child(materials_edit)

	_chapter_panel.add_child(_label("Story before the mission:"))
	var before_edit := _text_edit(80)
	before_edit.text = chapter.story_before
	before_edit.text_changed.connect(func():
		chapter.story_before = before_edit.text
		_mark_dirty()
	)
	_chapter_panel.add_child(before_edit)
	_chapter_panel.add_child(_label("Story after the mission:"))
	var after_edit := _text_edit(80)
	after_edit.text = chapter.story_after
	after_edit.text_changed.connect(func():
		chapter.story_after = after_edit.text
		_mark_dirty()
	)
	_chapter_panel.add_child(after_edit)

	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_label("Next (no link for an outcome = play this chapter again):"))
	var others: Array[CampaignChapter] = []
	for other in act.chapters:
		if other != chapter:
			others.append(other)
	for link in chapter.links:
		_chapter_panel.add_child(_build_link_row(chapter, link, others))
	var add_link := _button("Add link", func():
		if others.is_empty():
			return
		var created := CampaignLink.new()
		created.target_id = others[0].id
		chapter.links.append(created)
		_mark_dirty()
		_rebuild_chapter_panel()
		_map_view.queue_redraw()
	)
	add_link.disabled = others.is_empty()
	_chapter_panel.add_child(add_link)

	_build_mapping_section("Give to the mission when it starts:", chapter.mission_inputs, chapter.mission_file, false)
	_build_mapping_section("Take over from the mission when it ends:", chapter.mission_outputs, chapter.mission_file, true)
	_build_effects_section("When won, set:", chapter.win_effects)
	_build_effects_section("When lost, set:", chapter.lose_effects)
	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_button("Delete chapter", func(): _on_delete_chapter_pressed(chapter)))


func _build_link_row(chapter: CampaignChapter, link: CampaignLink, others: Array[CampaignChapter]) -> Control:
	var row := HBoxContainer.new()
	var outcome_option := OptionButton.new()
	for outcome in CampaignLink.Outcome.values():
		outcome_option.add_item(CampaignLink.outcome_name(outcome), outcome)
	outcome_option.select(outcome_option.get_item_index(link.outcome))
	outcome_option.item_selected.connect(func(index: int):
		link.outcome = outcome_option.get_item_id(index) as CampaignLink.Outcome
		_mark_dirty()
		_map_view.queue_redraw()
	)
	row.add_child(outcome_option)
	var target_option := OptionButton.new()
	target_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var target_index := -1
	for i in others.size():
		target_option.add_item(others[i].title)
		if others[i].id == link.target_id:
			target_index = i
	target_option.select(target_index)
	target_option.item_selected.connect(func(index: int):
		link.target_id = others[index].id
		_mark_dirty()
		_map_view.queue_redraw()
	)
	row.add_child(target_option)
	row.add_child(_button("×", func():
		chapter.links.erase(link)
		_mark_dirty()
		_rebuild_chapter_panel()
		_map_view.queue_redraw()
	))
	return row


# ---------------------------------------------------------------- small helpers

func _reward_spin(initial: int, on_change: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 9999
	spin.value = initial
	spin.value_changed.connect(func(value: float):
		on_change.call(int(value))
		_mark_dirty()
	)
	return spin


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _text_edit(height: float) -> TextEdit:
	var edit := TextEdit.new()
	edit.custom_minimum_size.y = height
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit


func _say(message: String) -> void:
	_notice.dialog_text = message
	_notice.popup_centered()
