class_name CampaignPlayer
extends Control

## Plays a campaign (standalone scene, opened from the main menu's "New Campaign" / "Load Campaign"),
## a small wizard of three pages:
## 1. the LIBRARY ("New Campaign") - every campaign as a "book" (its cover image and title) in a grid;
##    picking a book asks for a save game name and starts a new playthrough;
## 2. the LOAD page ("Load Campaign") - every save game of every campaign: resume one or delete one;
## 3. the PLAY page - the current act's map with the chapters the party can play now, a chapter's story,
##    its mission (the normal Player, which hands the outcome back through GameState when the mission
##    ends), and afterwards what it brought - XP, gold, the story and where the path leads next.
## Progress is the campaign save game (CampaignState), written after every change (so there is no Save
## button: leaving just leaves it resumable). The XP counter is always shown in the play page's top bar,
## The campaign screen opens on the page named by GameState.campaign_screen ("new" or "load") unless a save
## game is handed over (a finished mission returns to its save game's play page).
##
## The map only shows the chapters that can be played now (green) and the optional side quests on offer
## (orange stars, CampaignSideQuest); what was passed through is read back in the
## Campaign Log (top bar), a LogDialog over CampaignState.log_entries. A lost
## chapter without an "on lose" link is simply offered again. Places (diamonds) appear once their
## chapter is won; selecting one lists its offers, which are bought with gold/materials and give the
## party weapon attachments (the embark of a campaign mission offers only owned ones). Not built yet:
## the XP counter scaling the missions' monsters.

const MENU_SCENE := "res://ui/MainMenu.tscn"
const BOOK_SIZE := Vector2(190, 340)
const BOOK_COVER_SIZE := Vector2(170, 255)  ## the 2:3 cover ratio of CampaignIO.COVER_SIZE

var _campaign: Campaign
var _state: CampaignState
var _folder: String = ""
var _selected_id: String = ""

## Shows the story pages and questions of a narrative chapter (the mission player's dialog, reused).
var _narrative_dialog: PlayerDialog
var _library_page: Control
var _library_books: HFlowContainer
var _load_page: Control
var _load_list: VBoxContainer
var _play_page: Control
var _status_label: Label
var _heading_label: Label
var _map_view: CampaignMapView
var _side: VBoxContainer
var _notice: AcceptDialog
var _log_dialog: LogDialog
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _confirm: ConfirmationDialog
var _confirm_action: Callable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var root := Control.new()
	margin.add_child(root)
	_library_page = _build_library_page()
	_load_page = _build_load_page()
	_play_page = _build_play_page()
	for page in [_library_page, _load_page, _play_page]:
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(page)

	_notice = AcceptDialog.new()
	_notice.min_size = Vector2i(480, 0)
	add_child(_notice)
	_log_dialog = LogDialog.new()
	_log_dialog.heading = "Campaign Log"
	_log_dialog.current_label = "You can play"
	_log_dialog.empty_text = "Nothing has happened yet."
	_log_dialog.entries_provider = func() -> Array: return _state.log_entries if _state != null else []
	_log_dialog.objectives_provider = func() -> Array:
		var titles: Array = []
		var act := _current_act()
		if act != null and _state != null:
			for id in _state.available_chapters:
				var chapter := act.find_chapter(id)
				if chapter != null:
					titles.append(chapter.title)
		return titles
	add_child(_log_dialog)
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.min_size = Vector2i(440, 0)
	_name_dialog.ok_button_text = "Start"
	var name_box := VBoxContainer.new()
	name_box.add_theme_constant_override("separation", 8)
	_name_dialog.add_child(name_box)
	name_box.add_child(_wrapped("Your progress is saved automatically under this name, so you can leave and pick up where you stopped (Load Campaign in the main menu). Use a different name for every group or playthrough."))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "e.g. Friday night group"
	_name_edit.text_changed.connect(func(text: String): _name_dialog.get_ok_button().disabled = text.strip_edges() == "")
	_name_edit.text_submitted.connect(func(_text: String):
		if not _name_dialog.get_ok_button().disabled:
			_name_dialog.get_ok_button().emit_signal("pressed")
	)
	name_box.add_child(_name_edit)
	_name_dialog.confirmed.connect(_on_new_name_confirmed)
	add_child(_name_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.min_size = Vector2i(420, 0)
	_confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm)

	var screen := GameState.campaign_screen
	if screen == "load":
		_show_load()
	else:
		_show_library()
	# Coming back from a mission played as a chapter: reopen that save game and apply the outcome.
	if GameState.campaign_folder != "":
		var folder := GameState.campaign_folder
		var key := GameState.campaign_save
		var result := GameState.campaign_result
		GameState.clear_campaign()
		if _open_save(folder, key):
			await _ensure_hero_voices()
			if not result.is_empty():
				await _apply_result(result)


# ---------------------------------------------------------------- pages

func _show_page(page: Control) -> void:
	for candidate in [_library_page, _load_page, _play_page]:
		candidate.visible = candidate == page


func _build_library_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var bar := HBoxContainer.new()
	page.add_child(bar)
	bar.add_child(_button("‹ Back to menu", func(): get_tree().change_scene_to_file(MENU_SCENE)))
	var title := _label("Choose a campaign")
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_library_books = HFlowContainer.new()
	_library_books.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_books.add_theme_constant_override("h_separation", 20)
	_library_books.add_theme_constant_override("v_separation", 20)
	scroll.add_child(_library_books)
	return page


func _show_library() -> void:
	for child in _library_books.get_children():
		_library_books.remove_child(child)
		child.queue_free()
	var folders := CampaignIO.folder_names()
	for folder in folders:
		var campaign := CampaignIO.load_campaign(folder)
		if campaign != null:
			_library_books.add_child(_book(folder, campaign))
	if folders.is_empty():
		_library_books.add_child(_wrapped("No campaigns yet - make one in the Campaign Editor (Editors & Tools in the main menu)."))
	_show_page(_library_page)


## One "book": the cover (or a plain coloured one with the title) over the campaign's title; a click
## starts a new game of it.
func _book(folder: String, campaign: Campaign) -> Control:
	var book := Control.new()
	book.custom_minimum_size = BOOK_SIZE
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.add_child(column)
	column.add_child(_cover(folder, campaign, BOOK_COVER_SIZE))
	var title := _wrapped(campaign.campaign_name)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	var click := Button.new()
	click.flat = true
	click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click.pressed.connect(func(): _on_new_game_pressed(folder))
	book.add_child(click)
	return book


## The cover of `campaign` at `size` (always the 2:3 ratio, as imported); without a cover image a plain
## coloured cover showing the title.
func _cover(folder: String, campaign: Campaign, size: Vector2) -> Control:
	var texture := CampaignIO.image_texture(folder, campaign.cover_image)
	var holder := Control.new()
	holder.custom_minimum_size = size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if texture != null:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(picture)
	else:
		var panel := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color.from_hsv(float(campaign.campaign_name.hash() % 360) / 360.0, 0.45, 0.35)
		style.set_corner_radius_all(6)
		style.set_border_width_all(3)
		style.border_color = style.bg_color.lightened(0.35)
		panel.add_theme_stylebox_override("panel", style)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(panel)
		var name_label := _wrapped(campaign.campaign_name)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(name_label)
	return holder


func _build_load_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var bar := HBoxContainer.new()
	page.add_child(bar)
	bar.add_child(_button("‹ Back to menu", func(): get_tree().change_scene_to_file(MENU_SCENE)))
	var title := _label("Load campaign")
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_load_list = VBoxContainer.new()
	_load_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_load_list)
	return page


## Every save game of every campaign: its book, its name and progress, Resume and Delete.
func _show_load() -> void:
	for child in _load_list.get_children():
		_load_list.remove_child(child)
		child.queue_free()
	var listed := 0
	for folder in CampaignIO.folder_names():
		var campaign := CampaignIO.load_campaign(folder)
		if campaign == null:
			continue
		for key in CampaignIO.save_keys(folder):
			var saved := CampaignIO.load_state(folder, key)
			if saved != null:
				_load_list.add_child(_save_row(campaign, folder, key, saved))
				listed += 1
	if listed == 0:
		_load_list.add_child(_label("No save games yet - start one with New Campaign."))
	_show_page(_load_page)


func _save_row(campaign: Campaign, folder: String, key: String, saved: CampaignState) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.add_child(_cover(folder, campaign, BOOK_COVER_SIZE * 0.5))
	var progress := "Campaign complete" if saved.campaign_complete or saved.current_act >= campaign.acts.size() \
		else campaign.acts[saved.current_act].act_name
	var info := _label("%s\n%s  -  %s,  XP %d,  gold %d" % [saved.save_name if saved.save_name != "" else key, campaign.campaign_name, progress, saved.experience, saved.gold])
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info)
	row.add_child(_button("Resume", func(): await _resume(folder, key)))
	row.add_child(_button("Delete", func():
		_ask("Delete the save game '%s'?" % saved.save_name, func():
			CampaignIO.delete_state(folder, key)
			_show_load()
		)
	))
	return row


func _on_new_game_pressed(folder: String) -> void:
	_folder = folder
	var campaign := CampaignIO.load_campaign(folder)
	_name_dialog.title = "Start a new game of %s" % (campaign.campaign_name if campaign != null else folder)
	_name_edit.text = ""
	_name_dialog.get_ok_button().disabled = true
	_name_dialog.popup_centered()
	_name_edit.grab_focus()


func _on_new_name_confirmed() -> void:
	var save_name := _name_edit.text.strip_edges()
	if save_name == "":
		_say("A save game needs a name.")
		return
	if CampaignIO.save_keys(_folder).has(CampaignIO.save_key(save_name)):
		_say("A save game called '%s' already exists." % save_name)
		return
	if _begin(_folder, save_name):
		await _ensure_hero_voices()
		var act := _current_act()
		_say("%s\n\n%s\n\n%s" % [_campaign.campaign_name, _campaign.intro, ("%s\n%s" % [act.act_name, act.intro]) if act != null else ""])


func _build_play_page() -> Control:
	var page := VBoxContainer.new()
	var bar := HBoxContainer.new()
	page.add_child(bar)
	bar.add_child(_button("‹ Main menu", func(): get_tree().change_scene_to_file(MENU_SCENE)))
	bar.add_child(_button("Campaign Log", func(): _log_dialog.open()))
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status_label)

	_heading_label = Label.new()
	_heading_label.add_theme_font_size_override("font_size", 22)
	page.add_child(_heading_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(split)
	_map_view = CampaignMapView.new()
	_map_view.read_only = true
	_map_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_view.custom_minimum_size = Vector2(320, 320)
	_map_view.chapter_selected.connect(func(id: String):
		_selected_id = id
		_rebuild_side()
	)
	_map_view.place_selected.connect(func(id: String):
		_selected_id = id
		_rebuild_side()
	)
	_map_view.side_quest_selected.connect(func(id: String):
		_selected_id = id
		_rebuild_side()
	)
	split.add_child(_map_view)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_side)
	return page


func _ask(text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = action
	_confirm.popup_centered()


# ---------------------------------------------------------------- campaign

## Starts a fresh playthrough of campaign `folder` as save game `save_name`.
func _begin(folder: String, save_name: String) -> bool:
	var campaign := CampaignIO.load_campaign(folder)
	if campaign == null:
		_say("Could not open the campaign '%s'." % folder)
		return false
	var state := CampaignState.new()
	state.campaign_folder = folder
	state.save_name = save_name
	state.ensure_started(campaign)
	_use(campaign, state)
	return true


func _resume(folder: String, key: String) -> void:
	if _open_save(folder, key):
		await _ensure_hero_voices()


## The players give each hero a narration voice once per playthrough - when the campaign starts (or the first resume
## after narration was installed). Skipped while narration isn't installed: there would be nothing to hear.
func _ensure_hero_voices() -> void:
	if _state == null or not _state.hero_voices.is_empty() or not Narrator.is_available():
		return
	var dialog := HeroVoicesDialog.new()
	add_child(dialog)
	_state.hero_voices = await dialog.ask({})
	dialog.queue_free()
	_save()


## Resumes the save game with file name `key` of campaign `folder`.
func _open_save(folder: String, key: String) -> bool:
	var campaign := CampaignIO.load_campaign(folder)
	var state := CampaignIO.load_state(folder, key)
	if campaign == null or state == null:
		_say("Could not open that save game.")
		return false
	state.campaign_folder = folder
	state.ensure_started(campaign)
	_use(campaign, state)
	return true


func _use(campaign: Campaign, state: CampaignState) -> void:
	_campaign = campaign
	_state = state
	_folder = state.campaign_folder
	_selected_id = ""
	_save()
	_refresh_view()
	_show_page(_play_page)


func _save() -> void:
	if _state != null:
		CampaignIO.save_state(_state)


func _current_act() -> CampaignAct:
	if _campaign == null or _state == null or _state.current_act < 0 or _state.current_act >= _campaign.acts.size():
		return null
	return _campaign.acts[_state.current_act]


func _status_of(chapter_id: String) -> String:
	if _state.available_chapters.has(chapter_id):
		return "available"
	if _state.completed_chapters.has(chapter_id):
		return "done"
	return "locked"


func _refresh_view() -> void:
	if _campaign == null or _state == null:
		return
	var act := _current_act()
	if _state.campaign_complete or act == null:
		_heading_label.text = "%s - campaign complete! (%s)" % [_campaign.campaign_name, _state.save_name]
		_map_view.side_quests = []
		_map_view.show_act(null, null)
	else:
		_heading_label.text = "%s - %s (%s)" % [_campaign.campaign_name, act.act_name, _state.save_name]
		_map_view.statuses = {}
		for chapter in act.chapters:
			_map_view.statuses[chapter.id] = _status_of(chapter.id)
		_map_view.hidden_place_ids = []
		for place in act.places:
			if not _state.is_place_unlocked(place):
				_map_view.hidden_place_ids.append(place.id)
		_map_view.side_quests = _state.visible_side_quests(_campaign)
		_map_view.show_act(act, CampaignIO.image_texture(_folder, act.map_image), _selected_id)
	_status_label.text = "XP: %d  |  Gold: %d%s" % [_state.experience, _state.gold, ("  |  " + CampaignState.format_materials(_state.materials)) if not _state.materials.is_empty() else ""]
	_rebuild_side()


# ---------------------------------------------------------------- chapter panel

func _rebuild_side() -> void:
	for child in _side.get_children():
		_side.remove_child(child)
		child.queue_free()
	var act := _current_act()
	if _campaign == null or act == null:
		return
	var place := act.find_place(_selected_id)
	if place != null and _state.is_place_unlocked(place):
		_build_place_panel(place)
		return
	var quest := _campaign.find_side_quest(_selected_id)
	if quest != null and _state.is_side_quest_visible(_campaign, quest):
		_build_side_quest_panel(quest)
		return
	var chapter := act.find_chapter(_selected_id)
	if chapter == null:
		_side.add_child(_wrapped(act.intro if act.intro != "" else "Select a chapter on the map."))
		return
	if _status_of(chapter.id) != "available":
		_side.add_child(_wrapped(act.intro if act.intro != "" else "Select a chapter on the map."))
		return
	var title := _label(chapter.title)
	title.add_theme_font_size_override("font_size", 20)
	_side.add_child(title)
	_side.add_child(_label("Reward: +%d XP%s" % [chapter.reward_xp, (", %d gold" % chapter.reward_gold) if chapter.reward_gold > 0 else ""]))
	if chapter.story_before != "":
		_side.add_child(_wrapped(chapter.story_before))
	var play := _button("Read this chapter" if chapter.is_narrative else "Play this chapter", func(): _play(chapter))
	play.disabled = chapter.steps.is_empty() if chapter.is_narrative else chapter.mission_file == ""
	_side.add_child(play)


## An optional side quest on offer: tagged as such, its reward and story and a Play button.
func _build_side_quest_panel(quest: CampaignSideQuest) -> void:
	var tag := _label("Side quest (optional)")
	tag.modulate = CampaignMapView.SIDE_QUEST_COLOR
	_side.add_child(tag)
	var title := _label(quest.title)
	title.add_theme_font_size_override("font_size", 20)
	_side.add_child(title)
	_side.add_child(_label("Reward: +%d XP%s" % [quest.reward_xp, (", %d gold" % quest.reward_gold) if quest.reward_gold > 0 else ""]))
	if quest.story_before != "":
		_side.add_child(_wrapped(quest.story_before))
	var play := _button("Play this side quest", func(): _play_mission(quest.mission_file, quest.id, quest.mission_inputs))
	play.disabled = quest.mission_file == ""
	_side.add_child(play)


## The shop of a place: its description, what the party has and each offer with a Buy button.
func _build_place_panel(place: CampaignPlace) -> void:
	var title := _label(place.title)
	title.add_theme_font_size_override("font_size", 20)
	_side.add_child(title)
	if place.description != "":
		_side.add_child(_wrapped(place.description))
	_side.add_child(_label("You have %d gold%s." % [_state.gold, (" and " + CampaignState.format_materials(_state.materials)) if not _state.materials.is_empty() else ""]))
	if place.offers.is_empty():
		_side.add_child(_label("Nothing for sale here."))
	for offer in place.offers:
		_side.add_child(HSeparator.new())
		_side.add_child(_label(offer.title))
		if offer.description != "":
			_side.add_child(_wrapped(offer.description))
		var cost: Array[String] = []
		if offer.cost_gold > 0:
			cost.append("%d gold" % offer.cost_gold)
		if not offer.cost_materials.is_empty():
			cost.append(CampaignState.format_materials(offer.cost_materials))
		_side.add_child(_label("Cost: %s" % (", ".join(cost) if not cost.is_empty() else "free")))
		if offer.attachment != "":
			_side.add_child(_label("Gives: %s" % _attachment_summary(offer.attachment)))
		if offer.weapon != "":
			_side.add_child(_label("Gives the weapon: %s%s" % [WeaponData.weapon_label(offer.weapon), " (+)" if offer.upgraded else ""]))
		if offer.rune != "":
			_side.add_child(_label("Gives the rune: %s" % WeaponData.rune_label(offer.rune)))
		var bought := offer.once and _state.purchased_offers.has(offer.id)
		var buy := _button("Bought" if bought else "Buy", func(): _buy(offer))
		buy.disabled = not _state.can_buy(offer)
		_side.add_child(buy)
	if not _state.owned_attachments.is_empty():
		_side.add_child(HSeparator.new())
		var owned_labels: Array[String] = []
		for part_id in _state.owned_attachments:
			owned_labels.append(AttachmentCatalog.label(part_id))
		_side.add_child(_wrapped("Owned attachments: %s" % ", ".join(owned_labels)))
	if not _state.owned_weapons.is_empty():
		var weapon_labels: Array[String] = []
		for weapon_id in _state.owned_weapons:
			weapon_labels.append(WeaponData.weapon_label(weapon_id) + (" +" if _state.upgraded_cards.has(weapon_id) else ""))
		_side.add_child(_wrapped("Owned weapons: %s" % ", ".join(weapon_labels)))
	if not _state.owned_runes.is_empty():
		var rune_labels: Array[String] = []
		for rune_id in _state.owned_runes:
			rune_labels.append(WeaponData.rune_label(rune_id))
		_side.add_child(_wrapped("Owned runes: %s" % ", ".join(rune_labels)))


func _attachment_summary(part_id: String) -> String:
	var attachment := AttachmentCatalog.find(part_id)
	if attachment == null:
		return part_id
	return "%s - %s" % [AttachmentCatalog.label(part_id), attachment.ability_text]


func _buy(offer: CampaignOffer) -> void:
	if _state.buy(offer):
		_save()
		_refresh_view()


func _play(chapter: CampaignChapter) -> void:
	if chapter.is_narrative:
		_play_narrative(chapter)
		return
	_play_mission(chapter.mission_file, chapter.id, chapter.mission_inputs)


## Starts the mission `mission_file` of the chapter or side quest `id`; `inputs` are the campaign variables
## handed to the mission's own variables.
func _play_mission(mission_file: String, id: String, inputs: Array[MissionVariableMap]) -> void:
	var path := "%s/%s" % [CampaignIO.folder_path(_folder), mission_file]
	if mission_file == "" or not FileAccess.file_exists(path):
		_say("The mission is missing from the campaign folder.")
		return
	GameState.current_mission_path = path
	GameState.load_save_path = ""
	GameState.campaign_folder = _folder
	GameState.campaign_save = CampaignIO.save_key(_state.save_name)
	GameState.campaign_chapter_id = id
	var values := _state.variable_values(_campaign)
	GameState.campaign_mission_inputs = {}
	for input in inputs:
		if values.has(input.campaign_variable):
			GameState.campaign_mission_inputs[input.mission_variable] = values[input.campaign_variable]
	GameState.campaign_result = {}
	get_tree().change_scene_to_file("res://player/MissionPlayer.tscn")


## A narrative chapter: every step is a screen of story; a step with answers asks its question (no cancel). Steps
## and answers with unmet conditions are skipped, an answer can end the story early. The effects of the chosen answers
## are applied to the save together once the end is reached, so quitting halfway changes nothing, and the chapter then
## counts as won. What was read and chosen goes in the campaign log.
const MAX_NARRATIVE_STEPS := 200


func _play_narrative(chapter: CampaignChapter) -> void:
	if _narrative_dialog == null:
		_narrative_dialog = PlayerDialog.new()
		add_child(_narrative_dialog)
	_narrative_dialog.characters = _state.speakers(_campaign.characters)
	var pages: Array[String] = []
	var chosen: Array[NarrativeAnswer] = []
	# Steps and answers can depend on the campaign variables - including what was answered earlier in this very
	# story - so the chosen effects are applied to a scratch copy while reading and to the real save at the end.
	var scratch: CampaignState = _state.duplicate(true)
	var position := 0
	var shown := 0  # a goto loop can't run forever
	while position < chapter.steps.size() and shown < MAX_NARRATIVE_STEPS:
		var step := chapter.steps[position]
		position += 1
		if not scratch.conditions_hold(_campaign, step.conditions):
			continue
		shown += 1
		var offered: Array[NarrativeAnswer] = []
		for answer in step.answers:
			if scratch.conditions_hold(_campaign, answer.conditions):
				offered.append(answer)
		if offered.is_empty():
			await _narrative_dialog.ask_narrative([step.text], "", true, Callable(), true)
			pages.append(NarrationMarkup.plain(step.text, _campaign.characters))
			continue
		var labels: Array[String] = []
		for answer in offered:
			labels.append(answer.text)
		var prompt := step.text if step.question == "" else "%s\n\n%s" % [step.text, step.question]
		var index: int = await _narrative_dialog.ask_choice(prompt, labels, [], false, true)
		var answer := offered[index]
		chosen.append(answer)
		await _speak_answer(answer)
		await scratch.apply_effects(_campaign, answer.effects)
		pages.append("%s\n\nYou chose: %s" % [NarrationMarkup.plain(prompt, _campaign.characters), answer.text])
		if answer.reply != "":
			await _narrative_dialog.ask_ok(answer.reply, true, false, "", null, null, true)
			pages.append(NarrationMarkup.plain(answer.reply, _campaign.characters))
		if answer.ends_narrative:
			break
		var target := chapter.find_step_index(answer.goto_step_id)
		if target != -1:
			position = target
	_state.add_log(chapter.title, pages)
	for answer in chosen:
		await _state.apply_effects(_campaign, answer.effects)
	_apply_result({"won": true, "chapter_id": chapter.id, "mission_variables": {}})


## The chosen answer is spoken when it has voice tags (`[Chance]...[/Chance]`, usually a hero) - an untagged answer is
## just what the players picked and stays silent. Waits until it has been said so the reply doesn't cut it off.
func _speak_answer(answer: NarrativeAnswer) -> void:
	if NarrationMarkup.tag_names(answer.text).is_empty() or not Narrator.is_enabled():
		return
	Narrator.speak(answer.text, _narrative_dialog.characters)
	while Narrator.speaking:
		await Narrator.speaking_changed


# ---------------------------------------------------------------- results

func _apply_result(result: Dictionary) -> void:
	var won: bool = result.get("won", false)
	var finished_id := str(result.get("chapter_id", ""))
	var summary: Dictionary
	if _campaign.find_side_quest(finished_id) != null:
		summary = await _state.apply_side_quest_result(_campaign, finished_id, won, result.get("mission_variables", {}))
	else:
		summary = await _state.apply_result(_campaign, finished_id, won, result.get("mission_variables", {}))
	_save()
	_selected_id = ""
	_refresh_view()
	var lines: Array[String] = []
	lines.append("Victory!" if won else "Defeat.")
	if won:
		lines.append("+%d XP (now %d), +%d gold%s." % [summary["xp_gained"], summary["xp"], summary["gold"], (", " + CampaignState.format_materials(summary["materials"])) if not summary["materials"].is_empty() else ""])
		if summary["story_after"] != "":
			lines.append("\n" + summary["story_after"])
	elif summary["next"].is_empty():
		lines.append("The party has to try this chapter again.")
	if summary["act_complete"]:
		lines.append("\nAct complete!")
		var act := _current_act()
		if summary["campaign_complete"]:
			lines.append("The campaign is complete - congratulations!")
		elif act != null:
			lines.append("Next act: %s\n%s" % [act.act_name, act.intro])
	if not summary["next"].is_empty():
		lines.append("\nAvailable now: %s" % ", ".join(summary["next"]))
	_say("\n".join(lines))


# ---------------------------------------------------------------- helpers

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _wrapped(text: String) -> Label:
	var label := _label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


func _say(message: String) -> void:
	_notice.dialog_text = message
	_notice.popup_centered()
