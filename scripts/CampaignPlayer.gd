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
const EDITOR_SCENE := "res://ui/CampaignEditor.tscn"
## The playtest save game made by the campaign editor's Playtest.
const PLAYTEST_SAVE := "Playtest"

func _update_blocked_text() -> String:
	return tr("This save game cannot be moved to v%s:") + NL2 + "- %s" + NL2 + tr("It stays as it is; you can keep playing it on its own version.")


func _update_ask_text() -> String:
	return tr("Make a copy of '%s' on v%s?") + NL2 + tr("The original save game is not changed - you can always go back to it.")


func _update_note_text() -> String:
	return NL2 + tr("Note:") + NL + "- %s"
const NL := "\n"
const NL2 := "\n\n"
const BULLET_JOIN := "\n- "

var _campaign: Campaign
var _state: CampaignState
var _folder: String = ""
var _selected_id: String = ""

## Shows the story pages and questions of a narrative chapter (the mission player's dialog, reused).
var _narrative_dialog: PlayerDialog
var _library_page: LibraryPage
var _load_page: LoadPage
var _play_page: Control
var _hud: CampaignHud
var _map_view: CampaignMapView
## The panel of the chapter / side quest / place that was clicked on the map: a popup (_detail_dialog) holding `_side`.
var _detail_dialog: AcceptDialog
var _side: VBoxContainer
var _options_dialog: VoiceSettingsDialog
var _notice: AcceptDialog
var _log_dialog: LogDialog
var _inventory_dialog: InventoryDialog
var _setup_page: CampaignSetupPage  ## the page between Begin campaign and the first chapter; null when not showing
var _confirm: ConfirmationDialog
var _confirm_action: Callable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_library_page = LibraryPage.new()
	_library_page.back_pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	_library_page.begin_campaign.connect(_on_new_game_pressed)
	_library_page.play_mission.connect(_on_play_mission_pressed)
	_load_page = LoadPage.new()
	_load_page.back_pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	_load_page.resume_pressed.connect(func(folder: String, key: String): await _resume(folder, key))
	_load_page.delete_pressed.connect(_on_delete_save_pressed)
	_load_page.update_pressed.connect(_on_update_save_pressed)
	_play_page = _build_play_page()
	# The library and load pages have their own full-screen backgrounds, so they sit outside the margin like the map page.
	add_child(_library_page)
	add_child(_load_page)
	# The map page covers the whole screen (no margin): the map is centred in it and the HUD floats over it.
	_play_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_play_page)

	_notice = AcceptDialog.new()
	_notice.min_size = Vector2i(480, 0)
	add_child(_notice)
	_detail_dialog = AcceptDialog.new()
	_detail_dialog.ok_button_text = "Close"
	_detail_dialog.min_size = Vector2i(560, 420)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(560, 380)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_dialog.add_child(detail_scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(_side)
	_detail_dialog.visibility_changed.connect(_on_detail_visibility_changed)
	_notice.visibility_changed.connect(func():
		if not _notice.visible:
			Narrator.stop()
	)
	add_child(_detail_dialog)
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
	_inventory_dialog = InventoryDialog.new()
	_inventory_dialog.state_provider = func() -> CampaignState: return _state
	add_child(_inventory_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.min_size = Vector2i(420, 0)
	_confirm.confirmed.connect(func(): _confirm_action.call())
	add_child(_confirm)

	var screen := GameState.campaign_screen
	if screen == "load":
		_show_load()
	else:
		_show_library()
	# Started by the campaign editor's Playtest: straight into the campaign on the "Playtest" save.
	if GameState.campaign_playtest != "":
		var playtest_folder := GameState.campaign_playtest
		var fresh := GameState.campaign_playtest_fresh
		GameState.campaign_playtest = ""
		_start_playtest(playtest_folder, fresh)
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


func _show_library() -> void:
	_library_page.refresh()
	_library_page.auto_load_catalog()  # fills the community cards by itself unless the cached list is fresh
	_show_page(_library_page)


## A single mission installed from the community: straight into the Player (no campaign around it).
func _on_play_mission_pressed(path: String) -> void:
	GameState.clear_campaign()
	GameState.clear_debug()
	GameState.current_mission_path = path
	get_tree().change_scene_to_file("res://player/MissionPlayer.tscn")


## Every save game of every campaign as a row of the Load game page: the campaign's art, the save game's name, the campaign and how far it is.
func _show_load() -> void:
	var entries: Array[Dictionary] = []
	for folder in CampaignIO.folder_names():
		var campaign := CampaignIO.load_campaign(folder)
		if campaign == null:
			continue
		for key in CampaignIO.save_keys(folder):
			var saved := CampaignIO.load_state(folder, key)
			if saved == null:
				continue
			var progress := tr("Campaign complete") if saved.campaign_complete or saved.current_act >= campaign.acts.size() \
				else campaign.acts[saved.current_act].act_name
			var newer := SaveUpdater.newer_release(folder)
			entries.append({
				"folder": folder, "key": key, "group": saved.save_name if saved.save_name != "" else key,
				"campaign": campaign.campaign_name, "tag": "" if CampaignIO.is_release(folder) else "  " + tr("[draft]"),
				"progress": tr("%s  -  XP %d,  gold %d") % [progress, saved.experience, saved.gold],
				"texture": CampaignIO.image_texture(folder, campaign.cover_image), "newer": str(newer.get("version", "")),
			})
	_load_page.refresh(entries)
	_show_page(_load_page)


func _on_delete_save_pressed(folder: String, key: String, save_name: String) -> void:
	_ask(tr("Delete the save game '%s'?") % save_name, func():
		CampaignIO.delete_state(folder, key)
		_show_load()
	)


func _on_update_save_pressed(folder: String, key: String) -> void:
	var campaign := CampaignIO.load_campaign(folder)
	var saved := CampaignIO.load_state(folder, key)
	var newer := SaveUpdater.newer_release(folder)
	if campaign != null and saved != null and not newer.is_empty():
		_offer_update(campaign, saved, newer)


## Check the newer release against the save and show what would change; only after the player agrees is a COPY written.
func _offer_update(old_campaign: Campaign, saved: CampaignState, newer: Dictionary) -> void:
	var new_folder := str(newer["path"]).get_file()
	var new_campaign := CampaignIO.load_campaign(new_folder)
	if new_campaign == null:
		_say("The newer version could not be opened.")
		return
	var report := SaveUpdater.check(saved, old_campaign, new_campaign, new_folder)
	var errors: Array = report["errors"]
	var warnings: Array = report["warnings"]
	if not errors.is_empty():
		_say(_update_blocked_text() % [newer["version"], BULLET_JOIN.join(errors)])
		return
	var text := _update_ask_text() % [saved.save_name, newer["version"]]
	if not warnings.is_empty():
		text += _update_note_text() % BULLET_JOIN.join(warnings)
	_ask(text, func():
		if SaveUpdater.apply(saved, newer, new_campaign) == null:
			_say("The updated copy could not be saved.")
		else:
			_say("Done. The updated copy is in the list.")
		_show_load()
	)


## "Begin campaign": the setup page (save game name, hero voices, later more) - nothing is created before Start is pressed there.
func _on_new_game_pressed(folder: String) -> void:
	_folder = folder
	var campaign := CampaignIO.load_campaign(folder)
	# a suggestion (date and time) so starting is one Enter; type your own name to tell playthroughs apart (e.g. "Friday night group")
	var stamp := Time.get_datetime_dict_from_system()
	var base := tr("Game %04d-%02d-%02d %02d:%02d") % [stamp["year"], stamp["month"], stamp["day"], stamp["hour"], stamp["minute"]]
	var suggestion := base
	var counter := 2
	while CampaignIO.save_keys(_folder).has(CampaignIO.save_key(suggestion)):
		suggestion = "%s (%d)" % [base, counter]
		counter += 1
	_close_setup_page()
	_setup_page = CampaignSetupPage.new()
	var offered: Array[String] = ["en"]
	var start_language := "en"
	if campaign != null:
		offered = campaign.offered_languages()
		start_language = campaign.best_language(PlayerSettings.preferred_languages)
	_setup_page.setup(campaign.campaign_name if campaign != null else folder, suggestion, func(entered: String) -> bool:
		return CampaignIO.save_keys(_folder).has(CampaignIO.save_key(entered)),
		offered, start_language)
	_setup_page.cancelled.connect(func():
		_close_setup_page()
		_library_page.visible = true)
	_setup_page.confirmed.connect(_on_setup_confirmed)
	add_child(_setup_page)
	_library_page.visible = false


func _close_setup_page() -> void:
	if _setup_page != null:
		_setup_page.queue_free()
		_setup_page = null


func _on_setup_confirmed(save_name: String, hero_voices: Dictionary, language: String) -> void:
	_close_setup_page()
	if _begin(_folder, save_name, language):
		_state.set_hero_voices_for(language if language != "" else NarratorVoices.reading_language(), hero_voices)
		_save()
		if _campaign.intro != "":
			await _announce(_campaign.intro, _campaign.campaign_name, _campaign.intro)
		await _announce_act()


## The map page: the map fills the whole screen (centred, scaled to fit), the HUD floats over it. Clicking a pin opens a popup
## with that chapter, side quest or place instead of a sidebar.
func _build_play_page() -> Control:
	var page := Control.new()
	_map_view = CampaignMapView.new()
	_map_view.read_only = true
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_view.chapter_selected.connect(_on_map_item_selected)
	_map_view.place_selected.connect(_on_map_item_selected)
	_map_view.side_quest_selected.connect(_on_map_item_selected)
	page.add_child(_map_view)
	_hud = CampaignHud.new()
	_hud.back_to_menu_pressed.connect(func():
		GameState.campaign_from_editor = false
		get_tree().change_scene_to_file(MENU_SCENE)
	)
	_hud.back_to_editor_pressed.connect(_back_to_editor)
	_hud.log_pressed.connect(func(): _log_dialog.open())
	_hud.inventory_pressed.connect(func(): _inventory_dialog.open())
	_hud.options_pressed.connect(_open_options)
	_hud.rules_pressed.connect(func(): OS.shell_open(PlayerHud.RULES_REFERENCE_URL))
	page.add_child(_hud)
	return page


## The same Options dialog as the main menu and the mission player (voice, narration, AI). Nothing listens here, so the dialog
## (live = false) only saves the settings and installs the voice packs.
func _open_options() -> void:
	if _options_dialog == null:
		var listener := VoiceListener.new()  # never started: it is only asked what is installed
		add_child(listener)
		_options_dialog = VoiceSettingsDialog.new()
		_options_dialog.voice_listener = listener
		_options_dialog.live = false
		_options_dialog.main_menu = false
		add_child(_options_dialog)
		PlayerSettings.ui_language_changed.connect(_on_ui_language_changed)
	# The language of the game can be changed here (this is a moment the game can be saved - Options is not reachable otherwise).
	if _campaign != null and _state != null:
		_options_dialog.game_languages = _campaign.offered_languages()
		_options_dialog.game_language = _state.language if _state.language != "" else _campaign.best_language(PlayerSettings.preferred_languages)
		_options_dialog.game_language_changed = _set_game_language
	_options_dialog.open()


## The player picked another language for this game: it is stored in the save game and everything on screen that shows the game's texts is
## shown again (the log re-reads its entries in the new language when it is opened).
func _set_game_language(code: String) -> void:
	if _state == null or _campaign == null:
		return
	_state.language = code
	_save()
	_apply_language(_campaign, code)
	_refresh_after_language()


func _on_ui_language_changed() -> void:
	call_deferred("_refresh_after_language")


func _refresh_after_language() -> void:
	if _campaign == null or _state == null:
		return
	_refresh_view()
	if _detail_dialog != null and _detail_dialog.visible:
		_rebuild_side()


## A pin on the map was clicked: show its panel in the popup.
func _on_map_item_selected(id: String) -> void:
	_selected_id = id
	_map_view.selected_id = id
	_map_view.queue_redraw()
	_rebuild_side()
	if _side.get_child_count() > 0:
		# A fixed, narrow width and (nearly) the whole height of the window: the lists grow downwards and scroll, never sideways.
		var screen := get_viewport_rect().size
		_detail_dialog.max_size = Vector2i(660, int(screen.y * 0.94))
		_detail_dialog.popup_centered(Vector2i(640, int(screen.y * 0.9)))


## Closing the popup deselects the pin.
func _on_detail_visibility_changed() -> void:
	if not _detail_dialog.visible:
		Narrator.stop()
	if not _detail_dialog.visible and _selected_id != "":
		_selected_id = ""
		_map_view.selected_id = ""
		_map_view.queue_redraw()


func _ask(text: String, action: Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = action
	_confirm.popup_centered()


# ---------------------------------------------------------------- campaign

## The campaign editor's Playtest: opens the "Playtest" save game of `folder` - from the start (the old one is replaced), or the
## existing one when `fresh` is false (a new one if there is none).
func _start_playtest(folder: String, fresh: bool) -> void:
	var key := CampaignIO.save_key(PLAYTEST_SAVE)
	if fresh or not CampaignIO.save_keys(folder).has(key):
		CampaignIO.delete_state(folder, key)
		var campaign := CampaignIO.load_campaign(folder)
		var language := GameState.editor_language if campaign != null and campaign.offered_languages().has(GameState.editor_language) else ""
		if _begin(folder, PLAYTEST_SAVE, language):  # in the language the editor was editing, to see the translation
			_announce_act()
	else:
		_open_save(folder, key)


## Whether the campaign is a draft (being edited) rather than a release.
func _is_draft() -> bool:
	return _folder != "" and not CampaignIO.is_release(_folder)


## Playtest mode: a draft that was opened from the campaign editor. Only then the playtest tools (Count as won / lost, Back to Editor)
## are offered - a draft played from the main menu, like any campaign, is just played.
func _in_playtest() -> bool:
	return GameState.campaign_from_editor and _is_draft()


## Back to the campaign editor, which reopens this campaign.
func _back_to_editor() -> void:
	GameState.campaign_editor_folder = _folder
	GameState.campaign_from_editor = false
	get_tree().change_scene_to_file(EDITOR_SCENE)


## Playtest: a chapter or side quest counts as won or lost without playing it - through the same rules as a played one (rewards, effects,
## links, the lose branch), so a branch can be tried both ways. A win also sets the yes/no campaign variables the chapter takes over from
## its mission, since the mission that would have set them is not played.
func _playtest_result(id: String, won: bool) -> void:
	var outputs: Array[MissionVariableMap] = []
	var quest := _campaign.find_side_quest(id)
	if quest != null:
		outputs = quest.mission_outputs
	else:
		for act in _campaign.acts:
			var chapter := act.find_chapter(id)
			if chapter != null:
				outputs = chapter.mission_outputs
				break
	var values := {}
	if won:
		for mapping in outputs:
			for variable in _campaign.all_variables():
				if variable.name == mapping.campaign_variable and variable.type == MissionVariable.Type.BOOL:
					values[mapping.mission_variable] = true
	await _apply_result({"won": won, "chapter_id": id, "mission_variables": values, "loot": {}})


## The playtest buttons at the top of a chapter's or side quest's panel, above its long story text so they stay in view (playtest mode only).
func _add_playtest_buttons(id: String) -> void:
	if not _in_playtest():
		return
	var row := HFlowContainer.new()
	var tag := _label("Playtest:")
	tag.modulate = Color(1.0, 0.7, 0.3)
	row.add_child(tag)
	row.add_child(_button("Count as won", func(): _playtest_result(id, true)))
	row.add_child(_button("Count as lost", func(): _playtest_result(id, false)))
	_side.add_child(row)


## Everything from here on is read, logged and narrated in `language` (the save game's own; "" = the player's preferred languages only). LText is
## static, so a mission started from here uses it too; the main menu puts the player's own order back.
func _apply_language(campaign: Campaign, language: String) -> void:
	var order: Array[String] = []
	if language != "":
		order.append(language)
	for code in PlayerSettings.preferred_languages:
		if not order.has(code):
			order.append(code)
	LText.set_preferred(order)
	LText.edit_language = ""
	LText.fallback_language = campaign.default_language
	LogText.set_languages(campaign.offered_languages(), language)  # the logs are written once per language of the campaign


## Starts a fresh playthrough of campaign `folder` as save game `save_name`, in `language`.
func _begin(folder: String, save_name: String, language: String = "") -> bool:
	var campaign := CampaignIO.load_campaign(folder)
	if campaign == null:
		_say(tr("Could not open the campaign '%s'.") % folder)
		return false
	_apply_language(campaign, language)
	var state := CampaignState.new()
	state.campaign_folder = folder
	state.language = language
	state.campaign_id = str(CampaignIO.release_entry(folder).get("id", ""))
	state.campaign_version = str(CampaignIO.release_entry(folder).get("version", ""))
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
	var lang := NarratorVoices.reading_language()
	if _state == null or not Narrator.is_available() or not _state.hero_voices_for(lang).is_empty() or NarratorVoices.installed_for(lang).is_empty():
		return
	var dialog := HeroVoicesDialog.new()
	add_child(dialog)
	_state.set_hero_voices_for(lang, await dialog.ask({}, lang))
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
	_apply_language(campaign, state.language)
	state.ensure_started(campaign)
	_use(campaign, state)
	return true


func _use(campaign: Campaign, state: CampaignState) -> void:
	_campaign = campaign
	_state = state
	_state.bind_campaign(_campaign)
	_folder = state.campaign_folder
	_selected_id = ""
	_save()
	_refresh_view()
	_show_page(_play_page)
	_hud.set_playtest_tools(GameState.campaign_from_editor)


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
		_hud.set_heading(_campaign.campaign_name, tr("Campaign complete! (%s)") % _state.save_name)
		_map_view.side_quests = []
		_map_view.show_act(null, null)
	else:
		_hud.set_heading(_campaign.campaign_name, "%s (%s)" % [act.act_name, _state.save_name])
		_map_view.statuses = {}
		for chapter in act.chapters:
			_map_view.statuses[chapter.id] = _status_of(chapter.id)
		_map_view.hidden_place_ids = []
		for place in act.places:
			if not _state.is_place_open(place):
				_map_view.hidden_place_ids.append(place.id)
		_map_view.side_quests = _state.visible_side_quests(_campaign)
		_map_view.ending_quest_ids = []
		for quest in _map_view.side_quests:
			if quest.warn_when_ending and _state.vanishing_chapter(_campaign, quest) != "":
				_map_view.ending_quest_ids.append(quest.id)
		_map_view.show_act(act, CampaignIO.image_texture(_folder, act.map_image), _selected_id)
	_hud.set_status(tr("XP: %d  |  Gold: %d") % [_state.experience, _state.gold])
	_rebuild_side()


# ---------------------------------------------------------------- chapter panel

func _rebuild_side() -> void:
	for child in _side.get_children():
		_side.remove_child(child)
		child.queue_free()
	var act := _current_act()
	if _campaign == null or act == null:
		_detail_dialog.hide()
		return
	var place := act.find_place(_selected_id)
	if place != null and _state.is_place_open(place):
		_detail_dialog.title = place.title
		_build_place_panel(place)
		return
	var quest := _campaign.find_side_quest(_selected_id)
	if quest != null and _state.is_side_quest_visible(_campaign, quest):
		_detail_dialog.title = "Side quest"
		_build_side_quest_panel(quest)
		return
	var chapter := act.find_chapter(_selected_id)
	if chapter == null or _status_of(chapter.id) != "available":
		_detail_dialog.hide()  # nothing (valid) selected: no popup
		return
	_detail_dialog.title = "Chapter"
	var title := _label(chapter.title)
	title.add_theme_font_size_override("font_size", 20)
	_side.add_child(title)
	_side.add_child(_label(tr("Reward: ") + CampaignState.reward_text(chapter.reward_xp, chapter.reward_gold)))
	_add_playtest_buttons(chapter.id)
	_add_story(chapter.story_before)
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
	var vanishing := _state.vanishing_chapter(_campaign, quest) if quest.warn_when_ending else ""
	if vanishing != "":
		var warning := _wrapped(tr("Ending soon: this side quest is gone once \"%s\" is won.") % vanishing)
		warning.modulate = Color(1.0, 0.45, 0.4)
		_side.add_child(warning)
	_side.add_child(_label(tr("Reward: ") + CampaignState.reward_text(quest.reward_xp, quest.reward_gold)))
	_add_playtest_buttons(quest.id)
	_add_story(quest.story_before)
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
	# the market and the smithy show the party's materials as pictures and the recipe shop is about gold: only the offers list them in text
	var has_materials := not _state.materials.is_empty() and place.kind == CampaignPlace.Kind.OFFERS
	_side.add_child(_label((tr("You have %d gold and %s.") % [_state.gold, CampaignState.format_materials(_state.materials)]) if has_materials else tr("You have %d gold.") % _state.gold))
	match place.kind:
		CampaignPlace.Kind.MARKET:
			_build_market_panel()
		CampaignPlace.Kind.RECIPE_SHOP:
			_build_recipe_shop_panel(place)
		CampaignPlace.Kind.SMITHY:
			_build_smithy_panel()
		CampaignPlace.Kind.ALCHEMIST:
			_build_alchemist_panel()
		_:
			_build_offers_panel(place)



## An ordinary place: its authored offers, each with a Buy button.
func _build_offers_panel(place: CampaignPlace) -> void:
	if place.offers.is_empty():
		_side.add_child(_label("Nothing for sale here."))
	for offer in place.offers:
		_side.add_child(HSeparator.new())
		_side.add_child(_label(offer.title))
		if offer.description != "":
			_side.add_child(_wrapped(offer.description))
		var cost: Array[String] = []
		if offer.cost_gold > 0:
			cost.append(tr("%d gold") % offer.cost_gold)
		if not offer.cost_materials.is_empty():
			cost.append(CampaignState.format_materials(offer.cost_materials))
		_side.add_child(_label(tr("Cost: %s") % (", ".join(cost) if not cost.is_empty() else tr("free"))))
		if offer.attachment != "":
			_side.add_child(_label(tr("Gives: %s") % _attachment_summary(offer.attachment)))
		if offer.weapon != "":
			_side.add_child(_label(tr("Gives the weapon: %s%s") % [WeaponData.weapon_label(offer.weapon), " (+)" if offer.upgraded else ""]))
		if offer.rune != "":
			_side.add_child(_label(tr("Gives the rune: %s") % WeaponData.rune_label(offer.rune)))
		if offer.armor != "":
			_side.add_child(_wrapped(tr("Gives the armor: %s%s - %s") % [ArmorData.label(offer.armor), " (+)" if offer.upgraded else "", ArmorData.rule_text(offer.armor, offer.upgraded)]))
		if offer.trinket != "":
			_side.add_child(_wrapped(tr("Gives the trinket: %s%s - %s") % [TrinketData.label(offer.trinket), " (+)" if offer.upgraded else "", TrinketData.rule_text(offer.trinket, offer.upgraded)]))
		var bought := offer.once and _state.purchased_offers.has(offer.id)
		var buy := _button("Bought" if bought else "Buy", func(): _buy(offer))
		buy.disabled = not _state.can_buy(offer)
		_side.add_child(buy)


## The market: every material can be bought at its full value and sold at the campaign's sell percentage.
func _build_market_panel() -> void:
	_side.add_child(HSeparator.new())
	if _campaign.sell_percent <= 0:
		_side.add_child(_wrapped("The market sells materials but does not buy them."))
	var keys: Array[String] = []
	keys.append_array(LootMaterials.COMMON)
	keys.append_array(LootMaterials.ESSENCES)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for key in keys:
		var have := int(_state.materials.get(key, 0))
		var price := LootMaterials.value(key)
		var sell_price := _state.sell_price(_campaign, key)
		var buttons := VBoxContainer.new()
		buttons.add_theme_constant_override("separation", 2)
		var buy := _button(tr("Buy  %d") % price, func(): _market_trade(key, true))
		buy.disabled = _state.gold < price
		buttons.add_child(buy)
		var sell := _button(tr("Sell  %d") % sell_price, func(): _market_trade(key, false))
		sell.disabled = have <= 0 or sell_price <= 0
		buttons.add_child(sell)
		flow.add_child(ItemTile.build(ItemTile.data(LootMaterials.display_name(key), ItemData.material_image(key), false, have, tr("%s - buy for %d gold, sell for %d") % [LootMaterials.display_name(key), price, sell_price]), buttons))
	_side.add_child(flow)


func _market_trade(key: String, buying: bool) -> void:
	if (_state.buy_material(key) if buying else _state.sell_material(_campaign, key)):
		_save()
		_refresh_view()


## The recipe shop: what is on sale now (recipes the author listed, then the rotating stock), what leaves after the next
## chapter, and a vague rumour of what may arrive.
func _build_recipe_shop_panel(place: CampaignPlace) -> void:
	_side.add_child(HSeparator.new())
	if not RecipeData.available():
		_side.add_child(_wrapped("No recipes are known: import the game's data first (Game assets in the main menu)."))
		return
	var view := _state.shop_view(place)
	if view["entries"].is_empty():
		_side.add_child(_label("No recipes for sale right now."))
	for entry: Dictionary in view["entries"]:
		var recipe := RecipeData.find(str(entry["id"]))
		var buy := _button((tr("Buy  %d gold") if recipe["direct"] else tr("Buy recipe  %d gold")) % int(recipe["price"]), func(): _buy_recipe(str(entry["id"])))
		buy.disabled = not _state.can_buy_recipe(str(entry["id"]))
		_side.add_child(_recipe_card(recipe, tr("Leaves after the next chapter!") if entry["leaving"] else "", buy))
	if view["rumour"] != "":
		var rumour := _wrapped(str(view["rumour"]))
		rumour.modulate = Color(0.8, 0.8, 1.0)
		_side.add_child(rumour)


## A recipe as a card: the picture of what it makes on the left, on the right its tier, a note (what is about to change), what an armor
## does, the materials it needs (red when the party has too few) and the action button (Buy recipe / Forge).
func _recipe_card(recipe: Dictionary, note: String, action: Button) -> Control:
	var card_id := str(recipe["card"])
	var panel := ItemTile.card_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(ItemTile.build(ItemTile.data(RecipeData.card_label(card_id), RecipeData.card_image(card_id), bool(recipe["upgrade"]) or ConsumableData.is_upgraded(card_id), -1, RecipeData.label(recipe))))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	var tier := RecipeData.tier(recipe)
	var tier_label := _label((tr("Upgrade - tier %d") if recipe["upgrade"] else tr("Recipe - tier %d")) % tier if tier > 0 else tr("Story recipe"))
	tier_label.modulate = Color(1, 1, 1, 0.6)
	info.add_child(tier_label)
	if note != "":
		var note_label := _label(note)
		note_label.modulate = Color(1.0, 0.7, 0.3)
		info.add_child(note_label)
	if RecipeData.card_kind(card_id) == "consumable":
		var potion_rules := _wrapped(ConsumableData.rule_text(card_id))
		potion_rules.custom_minimum_size.x = 260.0
		info.add_child(potion_rules)
	if RecipeData.card_kind(card_id) == "trinket":
		var trinket_rules := _wrapped(TrinketData.rule_text(card_id, recipe["upgrade"]))
		trinket_rules.custom_minimum_size.x = 260.0
		info.add_child(trinket_rules)
	if RecipeData.card_kind(card_id) == "armor":
		var rules := _wrapped(ArmorData.rule_text(card_id, recipe["upgrade"]))
		rules.custom_minimum_size.x = 260.0  # a wrapping label needs a width to start from
		info.add_child(rules)
	if not recipe["ingredients"].is_empty():
		var needs := HFlowContainer.new()
		needs.add_theme_constant_override("h_separation", 8)
		for key: String in recipe["ingredients"]:
			needs.add_child(ItemTile.ingredient_chip(key, int(recipe["ingredients"][key]), int(_state.materials.get(key, 0))))
		info.add_child(needs)
	action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(action)
	return panel


func _buy_recipe(recipe_id: String) -> void:
	if _state.buy_recipe(recipe_id):
		_save()
		_refresh_view()


## The smithy: forge the items of the recipes the party owns from materials.
func _build_smithy_panel() -> void:
	_side.add_child(HSeparator.new())
	_add_material_strip()
	var recipes := _state.forgeable_recipes()
	if recipes.is_empty():
		_side.add_child(_wrapped("You know no recipe that makes something new. Recipes are sold in the recipe shops."))
		return
	for recipe in recipes:
		var forge := _button("Forge", func(): _forge(str(recipe["id"])))
		forge.disabled = not _state.can_forge(str(recipe["id"]))
		_side.add_child(_recipe_card(recipe, "", forge))


## The alchemist: brew consumables (potions) from the recipes the party owns; the party carries a count of each.
func _build_alchemist_panel() -> void:
	_side.add_child(HSeparator.new())
	_add_material_strip()
	var recipes := _state.brewable_recipes()
	if recipes.is_empty():
		_side.add_child(_wrapped("You know no potion recipe. Recipes are sold in the recipe shops or found as loot."))
		return
	for recipe in recipes:
		var brew := _button("Brew", func(): _brew(str(recipe["id"])))
		brew.disabled = not _state.can_brew(str(recipe["id"]))
		_side.add_child(_recipe_card(recipe, tr("You carry %d.") % _state.consumable_count(str(recipe["card"])), brew))


func _brew(recipe_id: String) -> void:
	if _state.brew(recipe_id):
		_save()
		_refresh_view()


## "Your materials:" and the party's stock as pictures.
func _add_material_strip() -> void:
	_side.add_child(_label("Your materials:"))
	var stock := HFlowContainer.new()
	stock.add_theme_constant_override("h_separation", 12)
	stock.add_theme_constant_override("v_separation", 4)
	var any_material := false
	for key: String in LootMaterials.COMMON + LootMaterials.ESSENCES:
		var have := int(_state.materials.get(key, 0))
		if have > 0:
			stock.add_child(ItemTile.stock_chip(key, have))
			any_material = true
	if any_material:
		_side.add_child(stock)
	else:
		_side.add_child(_wrapped("None yet - materials come from defeated monsters, missions and the market."))
	_side.add_child(HSeparator.new())


func _forge(recipe_id: String) -> void:
	if _state.forge(recipe_id):
		_save()
		_refresh_view()


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
	_detail_dialog.hide()
	if chapter.is_narrative:
		_play_narrative(chapter)
		return
	_play_mission(chapter.mission_file, chapter.id, chapter.mission_inputs)


## Starts the mission `mission_file` of the chapter or side quest `id`; `inputs` are the campaign variables
## handed to the mission's own variables.
func _play_mission(mission_file: String, id: String, inputs: Array[MissionVariableMap]) -> void:
	_detail_dialog.hide()
	var path := "%s/%s" % [CampaignIO.folder_path(_folder), mission_file]
	if mission_file == "" or not FileAccess.file_exists(path):
		_say("The mission is missing from the campaign folder.")
		return
	GameState.clear_debug()
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
	var pages: Array = []  # what was read and chosen: builders, written to the log once per language (see LogText)
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
			pages.append(func() -> String: return NarrationMarkup.plain(step.text, _campaign.characters))
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
		pages.append(func() -> String:
			var asked: String = step.text if step.question == "" else "%s\n\n%s" % [step.text, step.question]
			return tr("%s\n\nYou chose: %s") % [NarrationMarkup.plain(asked, _campaign.characters), answer.text])
		if answer.reply != "":
			await _narrative_dialog.ask_ok(answer.reply, true, false, "", null, null, true)
			pages.append(func() -> String: return NarrationMarkup.plain(answer.reply, _campaign.characters))
		if answer.ends_narrative:
			break
		var target := chapter.find_step_index(answer.goto_step_id)
		if target != -1:
			position = target
	_state.add_log(func() -> String: return chapter.title, pages)
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
	_detail_dialog.hide()
	var won: bool = result.get("won", false)
	var finished_id := str(result.get("chapter_id", ""))
	var summary: Dictionary
	var quests_before: Array[String] = []
	for quest in _state.visible_side_quests(_campaign):
		quests_before.append(quest.id)
	if _campaign.find_side_quest(finished_id) != null:
		summary = await _state.apply_side_quest_result(_campaign, finished_id, won, result.get("mission_variables", {}), result.get("loot", {}))
	else:
		summary = await _state.apply_result(_campaign, finished_id, won, result.get("mission_variables", {}), result.get("loot", {}))
	_save()
	_selected_id = ""
	_refresh_view()
	var lines: Array[String] = []
	var story_after := ""
	lines.append(tr("Victory!") if won else tr("Defeat."))
	if won:
		var parts: Array[String] = []
		if summary["xp_gained"] > 0 or summary["gold"] > 0 or summary["materials"].is_empty():
			parts.append(CampaignState.reward_text(summary["xp_gained"], summary["gold"]) + (tr(" (XP now %d)") % summary["xp"] if summary["xp_gained"] > 0 else ""))
		if not summary["materials"].is_empty():
			parts.append(CampaignState.format_materials(summary["materials"]))
		if summary.has("items"):
			parts.append(", ".join(summary["items"]))
		lines.append(", ".join(parts) + ".")
		if summary["story_after"] != "":
			lines.append("\n" + summary["story_after"])
			story_after = str(summary["story_after"])
	elif summary["next"].is_empty():
		lines.append(tr("The party has to try this chapter again."))
	if summary["act_complete"]:
		lines.append("\n" + tr("Act complete!"))
		if summary["campaign_complete"]:
			lines.append(tr("The campaign is complete - congratulations!"))
	var new_quests: Array[String] = []  # only side quests that came up with this result, not the ones that were already on offer
	for quest in _state.visible_side_quests(_campaign):
		if not quests_before.has(quest.id):
			new_quests.append(quest.title)
	if not summary["next"].is_empty():
		lines.append("\n" + tr("Available now: %s") % ", ".join(summary["next"]))
	if not new_quests.is_empty():
		lines.append(("" if not summary["next"].is_empty() else "\n") + tr_n("New side quest: %s", "New side quests: %s", new_quests.size()) % ", ".join(new_quests))
	await _announce("\n".join(lines), tr("Notice"), story_after)
	if summary["act_complete"] and not summary["campaign_complete"]:
		await _announce_act()  # the next act begins


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


## A notice that waits until it is closed (so several can follow each other).
## `narrate` (optional): the story text read aloud while the notice is open (the narrator, when it is set up and switched on).
func _announce(message: String, title: String = "Notice", narrate: String = "") -> void:
	_say(message, title)
	if narrate != "":
		_speak(narrate)
	while _notice.visible:
		await _notice.visibility_changed


## The popup that opens an act: its name as the title, its introduction as the text (nothing when the act has no introduction).
func _announce_act() -> void:
	var act := _current_act()
	if act != null and act.intro.strip_edges() != "":
		await _announce(act.intro, act.act_name, act.intro)


## The characters whose tags the texts may contain: the campaign's own and the heroes (with their chosen voices).
func _speakers() -> Array[NarratorCharacter]:
	if _campaign == null or _state == null:
		return []
	return _state.speakers(_campaign.characters)


## Reads a story text aloud in the story teller's and the characters' voices (nothing unless narration is set up and on).
func _speak(text: String) -> void:
	if Narrator.is_enabled():
		Narrator.speak(text, _speakers())


## A story text of a chapter or side quest in its panel, without voice tags, with a button to hear it when narration is on.
func _add_story(text: String) -> void:
	if text == "":
		return
	_side.add_child(_wrapped(NarrationMarkup.plain(text, _speakers())))
	if Narrator.is_enabled():
		_side.add_child(_button("▶ Read aloud", func(): _speak(text)))


func _say(message: String, title: String = "Notice") -> void:
	_detail_dialog.hide()  # two exclusive popups at once are not allowed
	_notice.title = title
	# Wrapped to a readable width: a long text (a campaign introduction) with no wrapping made the dialog wider than the screen.
	_notice.dialog_autowrap = true
	_notice.dialog_text = NarrationMarkup.plain(message, _speakers())  # voice tags are not shown
	_notice.popup_centered_clamped(Vector2i(620, 0), 0.8)
