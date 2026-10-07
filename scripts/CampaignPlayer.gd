class_name CampaignPlayer
extends Control

## Plays a campaign (standalone scene, main menu "Campaign"): pick a campaign (CampaignIO),
## see the current act's map with the chapters the party can play now, read a chapter's story,
## play its mission (the normal Player, which hands the outcome back through GameState when
## the mission ends) and then see what it brought - the experience counter, gold, the story
## afterwards and where the path leads next. Progress is the campaign save (CampaignState),
## written after every change. The XP counter is always shown in the top bar.
##
## Chapter statuses on the map: green = available (play it), grey ✓ = won, dark = locked. A lost
## chapter without an "on lose" link is simply offered again. Places (diamonds) appear once their
## chapter is won; selecting one lists its offers, which are bought with gold/materials and give the
## party weapon attachments (the embark of a campaign mission offers only owned ones). Not built yet:
## the XP counter scaling the missions' monsters.

const MENU_SCENE := "res://ui/MainMenu.tscn"

var _campaign: Campaign
var _state: CampaignState
var _folder: String = ""
var _selected_id: String = ""

var _campaign_option: OptionButton
var _folders: Array[String] = []
var _status_label: Label
var _heading_label: Label
var _body: Control
var _welcome_label: Label
var _map_view: CampaignMapView
var _side: VBoxContainer
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

	var bar := HBoxContainer.new()
	root.add_child(bar)
	_campaign_option = OptionButton.new()
	_campaign_option.custom_minimum_size.x = 220
	bar.add_child(_campaign_option)
	bar.add_child(_button("Start / Continue", _on_start_pressed))
	bar.add_child(_button("Back to menu", func(): get_tree().change_scene_to_file(MENU_SCENE)))
	_status_label = Label.new()
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_status_label)

	_welcome_label = Label.new()
	_welcome_label.text = "Choose a campaign (make one in the Campaign Editor) and press Start / Continue."
	root.add_child(_welcome_label)

	_heading_label = Label.new()
	_heading_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_heading_label)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	_body = split
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
	split.add_child(_map_view)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 360
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_side = VBoxContainer.new()
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_side)

	_notice = AcceptDialog.new()
	_notice.min_size = Vector2i(480, 0)
	add_child(_notice)

	_refresh_campaign_list()
	_refresh_view()
	# Coming back from a mission played as a chapter: reopen that campaign and apply the outcome.
	if GameState.campaign_folder != "":
		var folder := GameState.campaign_folder
		var result := GameState.campaign_result
		GameState.clear_campaign()
		if _open_campaign(folder) and not result.is_empty():
			_apply_result(result)


# ---------------------------------------------------------------- campaign

func _refresh_campaign_list() -> void:
	_folders = CampaignIO.folder_names()
	_campaign_option.clear()
	for folder in _folders:
		_campaign_option.add_item(folder)
	if _folder != "":
		_campaign_option.select(_folders.find(_folder))


func _on_start_pressed() -> void:
	if _campaign_option.selected >= 0:
		_open_campaign(_folders[_campaign_option.selected])


## Opens `folder` and continues its saved progress (or begins it). Returns whether it worked.
func _open_campaign(folder: String) -> bool:
	var campaign := CampaignIO.load_campaign(folder)
	if campaign == null:
		_say("Could not open the campaign '%s'." % folder)
		return false
	var state := CampaignIO.load_state(folder)
	var is_new := state == null
	if is_new:
		state = CampaignState.new()
		state.campaign_folder = folder
	state.ensure_started(campaign)
	_campaign = campaign
	_state = state
	_folder = folder
	_selected_id = ""
	_save()
	_refresh_campaign_list()
	_refresh_view()
	if is_new:
		var act := _current_act()
		_say("%s\n\n%s\n\n%s" % [campaign.campaign_name, campaign.intro, ("%s\n%s" % [act.act_name, act.intro]) if act != null else ""])
	return true


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
	var has_campaign := _campaign != null
	_body.visible = has_campaign
	_heading_label.visible = has_campaign
	_welcome_label.visible = not has_campaign
	if not has_campaign:
		return
	var act := _current_act()
	if _state.campaign_complete or act == null:
		_heading_label.text = "%s - campaign complete!" % _campaign.campaign_name
		_map_view.show_act(null, null)
	else:
		_heading_label.text = "%s - %s" % [_campaign.campaign_name, act.act_name]
		_map_view.statuses = {}
		for chapter in act.chapters:
			_map_view.statuses[chapter.id] = _status_of(chapter.id)
		_map_view.hidden_place_ids = []
		for place in act.places:
			if not _state.is_place_unlocked(place):
				_map_view.hidden_place_ids.append(place.id)
		_map_view.show_act(act, CampaignIO.map_texture(_folder, act.map_image), _selected_id)
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
	var chapter := act.find_chapter(_selected_id)
	if chapter == null:
		_side.add_child(_wrapped(act.intro if act.intro != "" else "Select a chapter on the map."))
		return
	var status := _status_of(chapter.id)
	var title := _label(chapter.title)
	title.add_theme_font_size_override("font_size", 20)
	_side.add_child(title)
	var status_text: String = {"available": "Ready to play", "done": "Completed", "locked": "Locked - win the chapters before it first"}[status]
	_side.add_child(_label(status_text))
	_side.add_child(_label("Reward: +%d XP%s" % [CampaignState.XP_PER_WIN, (", %d gold" % chapter.reward_gold) if chapter.reward_gold > 0 else ""]))
	if status != "locked" and chapter.story_before != "":
		_side.add_child(_wrapped(chapter.story_before))
	if status == "done" and chapter.story_after != "":
		_side.add_child(HSeparator.new())
		_side.add_child(_wrapped(chapter.story_after))
	if status == "available":
		var play := _button("Play this chapter", func(): _play(chapter))
		play.disabled = chapter.mission_file == ""
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
		var bought := offer.once and _state.purchased_offers.has(offer.id)
		var buy := _button("Bought" if bought else "Buy", func(): _buy(offer))
		buy.disabled = not _state.can_buy(offer)
		_side.add_child(buy)
	if not _state.owned_attachments.is_empty():
		_side.add_child(HSeparator.new())
		_side.add_child(_wrapped("Owned attachments: %s" % ", ".join(_state.owned_attachments)))


func _attachment_summary(attachment_name: String) -> String:
	for attachment in AttachmentCatalog.all():
		if attachment.attachment_name == attachment_name:
			return attachment.summary()
	return attachment_name


func _buy(offer: CampaignOffer) -> void:
	if _state.buy(offer):
		_save()
		_refresh_view()


func _play(chapter: CampaignChapter) -> void:
	var path := "%s/%s" % [CampaignIO.folder_path(_folder), chapter.mission_file]
	if chapter.mission_file == "" or not FileAccess.file_exists(path):
		_say("The mission of this chapter is missing from the campaign folder.")
		return
	GameState.current_mission_path = path
	GameState.load_save_path = ""
	GameState.campaign_folder = _folder
	GameState.campaign_chapter_id = chapter.id
	GameState.campaign_result = {}
	get_tree().change_scene_to_file("res://player/MissionPlayer.tscn")


# ---------------------------------------------------------------- results

func _apply_result(result: Dictionary) -> void:
	var won: bool = result.get("won", false)
	var summary := _state.apply_result(_campaign, str(result.get("chapter_id", "")), won)
	_save()
	_selected_id = ""
	_refresh_view()
	var lines: Array[String] = []
	lines.append("Victory!" if won else "Defeat.")
	if won:
		lines.append("+%d XP (now %d), +%d gold%s." % [CampaignState.XP_PER_WIN, summary["xp"], summary["gold"], (", " + CampaignState.format_materials(summary["materials"])) if not summary["materials"].is_empty() else ""])
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
