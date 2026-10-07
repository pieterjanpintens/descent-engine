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
var _dirty: bool = false

var _status_label: Label
var _open_option: OptionButton
var _open_folders: Array[String] = []
var _body: Control
var _welcome_label: Label
var _campaign_name_edit: LineEdit
var _campaign_intro_edit: TextEdit
var _xp_edit: LineEdit
var _slots_edit: LineEdit
var _progression_note: Label
var _acts_list: ItemList
var _act_name_edit: LineEdit
var _act_intro_edit: TextEdit
var _map_label: Label
var _problems_label: Label
var _map_view: CampaignMapView
var _chapter_panel: VBoxContainer
var _suppress: bool = false

var _new_dialog: ConfirmationDialog
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

	# --- top bar
	var bar := HBoxContainer.new()
	root.add_child(bar)
	bar.add_child(_button("New…", func(): _new_name_edit.text = ""; _new_dialog.popup_centered()))
	_open_option = OptionButton.new()
	_open_option.custom_minimum_size.x = 200
	bar.add_child(_open_option)
	bar.add_child(_button("Open", _on_open_pressed))
	bar.add_child(_button("Save", _save))
	bar.add_child(_button("Back to menu", _on_back_pressed))
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status_label)

	_welcome_label = Label.new()
	_welcome_label.text = "Create a new campaign or open an existing one."
	root.add_child(_welcome_label)

	# --- body: campaign/acts | map | chapter
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_body = split

	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 300
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
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

	left.add_child(_label("Hero levels - XP needed for each level (comma separated, starts at 0):"))
	_xp_edit = LineEdit.new()
	_xp_edit.text_submitted.connect(func(_text: String): _commit_progression())
	_xp_edit.focus_exited.connect(_commit_progression)
	left.add_child(_xp_edit)
	left.add_child(_label("Ability slots at each level:"))
	_slots_edit = LineEdit.new()
	_slots_edit.text_submitted.connect(func(_text: String): _commit_progression())
	_slots_edit.focus_exited.connect(_commit_progression)
	left.add_child(_slots_edit)
	_progression_note = _label("")
	_progression_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_progression_note.add_theme_color_override("font_color", Color(1.0, 0.65, 0.4))
	left.add_child(_progression_note)

	left.add_child(HSeparator.new())
	left.add_child(_label("Acts:"))
	_acts_list = ItemList.new()
	_acts_list.custom_minimum_size.y = 110
	_acts_list.item_selected.connect(func(index: int):
		_act_index = index
		_selected = null
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
	var map_row := HBoxContainer.new()
	left.add_child(map_row)
	map_row.add_child(_button("Map image…", func(): _image_dialog.popup_centered_ratio(0.6)))
	map_row.add_child(_button("Clear map", _on_clear_map_pressed))
	_map_label = _label("")
	left.add_child(_map_label)
	left.add_child(_button("Add chapter", _on_add_chapter_pressed))
	left.add_child(HSeparator.new())
	left.add_child(_label("Problems:"))
	_problems_label = _label("")
	_problems_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_problems_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.4))
	left.add_child(_problems_label)

	_map_view = CampaignMapView.new()
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size = Vector2(300, 300)
	_map_view.chapter_selected.connect(_on_map_chapter_selected)
	_map_view.chapter_moved.connect(func(_id: String): _mark_dirty())
	split.add_child(_map_view)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size.x = 340
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right_scroll)
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

	_image_dialog = FileDialog.new()
	_image_dialog.title = "Choose the map image of this act"
	_image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_image_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_image_dialog.file_selected.connect(_on_image_selected)
	add_child(_image_dialog)

	_mission_dialog = FileDialog.new()
	_mission_dialog.title = "Add a mission to this campaign"
	_mission_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_mission_dialog.access = FileDialog.ACCESS_USERDATA
	_mission_dialog.filters = PackedStringArray(["*.tres ; Missions"])
	_mission_dialog.file_selected.connect(_on_mission_file_selected)
	add_child(_mission_dialog)

	_notice = AcceptDialog.new()
	add_child(_notice)

	_refresh_open_list()
	_refresh_all()


# ---------------------------------------------------------------- campaign files

func _refresh_open_list() -> void:
	_open_folders = CampaignIO.folder_names()
	_open_option.clear()
	for folder in _open_folders:
		_open_option.add_item(folder)
	if _folder != "":
		_open_option.select(_open_folders.find(_folder))


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


func _on_open_pressed() -> void:
	if _open_option.selected < 0:
		return
	_save_if_dirty()
	_load_folder(_open_folders[_open_option.selected])


func _load_folder(folder: String) -> void:
	var campaign := CampaignIO.load_campaign(folder)
	if campaign == null:
		_say("Could not open '%s'." % folder)
		return
	_campaign = campaign
	_folder = folder
	_act_index = 0 if not campaign.acts.is_empty() else -1
	_selected = null
	_dirty = false
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
	_update_problems()


## Applies the two level fields to the campaign's HeroProgression - only if they are valid
## (same count, XP ascending from 0, slots >= 1); otherwise the note says why and nothing changes.
func _commit_progression() -> void:
	if _suppress or _campaign == null:
		return
	var xp := _parse_ints(_xp_edit.text)
	var slots := _parse_ints(_slots_edit.text)
	var problem := ""
	if xp.is_empty() or slots.is_empty():
		problem = "Both lists need at least one number."
	elif xp.size() != slots.size():
		problem = "The two lists need the same number of entries (one per level)."
	elif xp[0] != 0:
		problem = "Level 1 must need 0 XP."
	else:
		for i in range(1, xp.size()):
			if xp[i] <= xp[i - 1]:
				problem = "XP must go up with every level."
		for slot_count in slots:
			if slot_count < 1:
				problem = "Every level needs at least 1 ability slot."
	_progression_note.text = problem
	if problem != "":
		return
	if xp != _campaign.progression.xp_thresholds or slots != _campaign.progression.slots_by_level:
		_campaign.progression.xp_thresholds = xp
		_campaign.progression.slots_by_level = slots
		_mark_dirty()


## "0, 10 , 25" -> [0, 10, 25]; entries that are not whole numbers are skipped.
func _parse_ints(text: String) -> Array[int]:
	var numbers: Array[int] = []
	for part in text.split(","):
		var trimmed := part.strip_edges()
		if trimmed.is_valid_int():
			numbers.append(int(trimmed))
	return numbers


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
	_mark_dirty()
	_refresh_act()


func _on_map_chapter_selected(chapter_id: String) -> void:
	var act := _current_act()
	if act == null:
		return
	_selected = act.find_chapter(chapter_id)
	_rebuild_chapter_panel()


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
	_selected = null
	_mark_dirty()
	_refresh_act()


func _on_mission_file_selected(path: String) -> void:
	if _selected == null:
		return
	var file := CampaignIO.import_mission(_folder, path)
	if file == "":
		_say("Could not copy the mission into the campaign.")
		return
	_selected.mission_file = file
	_mark_dirty()
	_rebuild_chapter_panel()


# ---------------------------------------------------------------- refreshing

func _refresh_all() -> void:
	var has_campaign := _campaign != null
	_body.visible = has_campaign
	_welcome_label.visible = not has_campaign
	if not has_campaign:
		return
	_suppress = true
	_campaign_name_edit.text = _campaign.campaign_name
	_campaign_intro_edit.text = _campaign.intro
	_xp_edit.text = ", ".join(_campaign.progression.xp_thresholds.map(func(v: int) -> String: return str(v)))
	_slots_edit.text = ", ".join(_campaign.progression.slots_by_level.map(func(v: int) -> String: return str(v)))
	_progression_note.text = ""
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
	_suppress = false
	_map_label.text = "Map: %s" % (act.map_image if act != null and act.map_image != "" else "none")
	_map_view.show_act(act, CampaignIO.map_texture(_folder, act.map_image) if act != null else null, _selected.id if _selected != null else "")
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
	_problems_label.text = "\n".join(lines) if not lines.is_empty() else "none"
	_map_view.queue_redraw()


func _rebuild_chapter_panel() -> void:
	for child in _chapter_panel.get_children():
		_chapter_panel.remove_child(child)
		child.queue_free()
	var act := _current_act()
	if act == null or _selected == null:
		_chapter_panel.add_child(_label("Select a chapter on the map, or add one."))
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

	_chapter_panel.add_child(HSeparator.new())
	_chapter_panel.add_child(_button("Delete chapter", func(): _delete_chapter(chapter)))


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
