class_name LibraryPage
extends Control

## The New Game page (the designer's mockup): a carousel of hexagonal cards - the campaigns and single missions you have installed, your own
## drafts, and (after the refresh icon is pressed) what the community has shared and you do not have yet - and a detail page with the cover, the story, the
## languages and play time and one button: Install for something from the community, Begin campaign / Play mission for what you have.
## Nothing goes online until the player asks for the community list.

signal back_pressed
signal begin_campaign(folder: String)
signal play_mission(path: String)

const BACKGROUND := "res://models/ui/bg_rock.jpg"
const GRADIENT := "res://models/ui/bg_gradient_blue.jpg"  ## multiplied over the rock: blue on the left, the plain rock on the right
const DETAIL_BACKGROUND := "res://models/ui/bg_detail.jpg"  ## the same recipe, baked by the designer
const REFRESH_ICON := "res://models/ui/icon_refresh.png"
const BACK_ARROW := "res://models/ui/back_arrow.png"
const NAV_ARROW := "res://models/ui/nav_arrow.png"
const INSTALL_BUTTON := "res://models/ui/button_install.png"
const BEGIN_BUTTON := "res://models/ui/button_begin.png"
const CARD_GAP := 24.0
const ARROW_SIZE := 58.0

var _items: Array[Dictionary] = []
var _catalog: Array[Dictionary] = []
var _first := 0
var _per_page := 3
var _busy := false
var _selected: Dictionary = {}

var _carousel: Control
var _cards_row: HBoxContainer
var _prev_button: BaseButton
var _next_button: BaseButton
var _detail: Control
var _detail_backdrop: TextureRect
var _status: Label
var _title: Label
var _service: CommunityService
var _list_button: TextureButton
var _spin: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the designer's background: the rock texture MULTIPLIED by the blue gradient (checked against his mockup: rock x gradient matches it)
	var rock := TextureRect.new()
	rock.texture = load(BACKGROUND) as Texture2D
	rock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rock)
	var gradient := TextureRect.new()
	gradient.texture = load(GRADIENT) as Texture2D
	gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	gradient.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	gradient.material = multiply
	add_child(gradient)
	_detail_backdrop = TextureRect.new()
	_detail_backdrop.texture = load(DETAIL_BACKGROUND) as Texture2D
	_detail_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_detail_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_backdrop.visible = false
	add_child(_detail_backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	header.add_child(MenuStyle.texture_button(BACK_ARROW, Vector2(78, 46), _on_back_pressed))
	_title = MenuStyle.shadow_label("New game", 40, MenuStyle.TEXT_COLOR)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_list_button = MenuStyle.texture_button(REFRESH_ICON, Vector2(78, 46), _on_community_list_pressed)
	_list_button.pivot_offset = Vector2(39, 23)
	_list_button.tooltip_text = "Look for campaigns shared by the community"
	header.add_child(_list_button)

	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(stage)
	_carousel = HBoxContainer.new()
	_carousel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(_carousel)
	_prev_button = MenuStyle.texture_button(NAV_ARROW, Vector2(ARROW_SIZE, ARROW_SIZE), func(): _scroll(-1))
	_prev_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_carousel.add_child(_prev_button)
	_cards_row = HBoxContainer.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", int(CARD_GAP))
	_carousel.add_child(_cards_row)
	_next_button = MenuStyle.texture_button(NAV_ARROW, Vector2(ARROW_SIZE, ARROW_SIZE), func(): _scroll(1), true)
	_next_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_carousel.add_child(_next_button)
	_detail = Control.new()
	_detail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_detail.visible = false
	stage.add_child(_detail)

	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.75)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(_status)

	_service = CommunityService.new()
	add_child(_service)
	_service.progress.connect(func(text: String): _status.text = text)
	resized.connect(_relayout)
	_relayout()


## What the carousel shows is rebuilt from what is installed (a campaign or mission may have been installed, released or removed since).
func refresh() -> void:
	_items = _build_items()
	_first = clampi(_first, 0, maxi(0, _items.size() - _per_page))
	_show_carousel()


func _build_items() -> Array[Dictionary]:
	var released: Array[Dictionary] = []
	var drafts: Array[Dictionary] = []
	var online: Array[Dictionary] = []
	var installed_ids: Dictionary = {}
	for entry in CommunityLibrary.installed():
		installed_ids["%s@%s" % [entry["id"], entry["version"]]] = true
		var item := {
			"source": "installed", "id": entry["id"], "version": entry["version"], "title": CommunityLibrary.strip_version_suffix(str(entry["name"])),
			"text": str(entry.get("description", "")), "languages": CampaignInfo.clean_languages(entry.get("languages", [])),
			"minutes": int(entry.get("duration_minutes", 0)), "texture": null, "author": str(entry.get("author", "")),
		}
		if entry["type"] == SharePackage.TYPE_CAMPAIGN:
			var folder := str(entry["path"]).trim_suffix("/").get_file()
			var campaign := CampaignIO.load_campaign(folder)
			if campaign == null:
				continue
			item["kind"] = "campaign"
			item["folder"] = folder
			item["title"] = CommunityLibrary.strip_version_suffix(campaign.campaign_name)
			item["text"] = campaign.intro if campaign.intro != "" else item["text"]
			item["languages"] = CampaignInfo.clean_languages(campaign.languages)
			item["minutes"] = campaign.duration_minutes
			item["texture"] = CampaignIO.image_texture(folder, campaign.cover_image)
		else:
			item["kind"] = "mission"
			item["path"] = str(entry["path"])
		released.append(item)
	for folder in CampaignIO.folder_names():
		if CampaignIO.is_release(folder):
			continue
		var campaign := CampaignIO.load_campaign(folder)
		if campaign != null:
			drafts.append({
				"source": "draft", "kind": "campaign", "folder": folder, "title": campaign.campaign_name, "text": campaign.intro,
				"languages": CampaignInfo.clean_languages(campaign.languages), "minutes": campaign.duration_minutes,
				"texture": CampaignIO.image_texture(folder, campaign.cover_image), "author": "",
			})
	for entry in _catalog:
		if installed_ids.has("%s@%s" % [entry["id"], entry["version"]]):
			continue
		online.append({
			"source": "catalog", "kind": "campaign" if entry["type"] == SharePackage.TYPE_CAMPAIGN else "mission", "entry": entry,
			"title": CommunityLibrary.strip_version_suffix(str(entry["name"])), "version": entry["version"], "text": entry["description"], "languages": entry.get("languages", []),
			"minutes": int(entry.get("duration_minutes", 0)), "texture": null, "author": entry["author"],
		})
	var all: Array[Dictionary] = []
	all.append_array(released)
	all.append_array(drafts)
	all.append_array(online)
	return all


# ---------------------------------------------------------------- the carousel

func _relayout() -> void:
	if _cards_row == null:
		return
	var room := size.x - 44.0 - 2.0 * (ARROW_SIZE + 12.0)
	var per_page := clampi(int((room + CARD_GAP) / (CampaignCard.CARD_SIZE.x + CARD_GAP)), 1, 5)
	if per_page != _per_page:
		_per_page = per_page
		_first = clampi(_first, 0, maxi(0, _items.size() - _per_page))
		if _carousel.visible:
			_fill_cards()


func _show_carousel() -> void:
	_selected = {}
	_detail.visible = false
	_detail_backdrop.visible = false
	_carousel.visible = true
	_title.text = "New game"
	_list_button.visible = true
	_fill_cards()


func _fill_cards() -> void:
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.free()
	if _items.is_empty():
		var empty := Label.new()
		empty.text = "Nothing here yet. Press the refresh icon to see what the community has shared, or release a campaign of your own in the Campaign Editor."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(520, 0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cards_row.add_child(empty)
	for index in range(_first, mini(_items.size(), _first + _per_page)):
		var card := CampaignCard.new()
		card.setup(_items[index])
		var item := _items[index]
		card.pressed.connect(func(): _open_detail(item))
		_cards_row.add_child(card)
	_prev_button.visible = _first > 0
	_next_button.visible = _first + _per_page < _items.size()


func _scroll(direction: int) -> void:
	_first = clampi(_first + direction * _per_page, 0, maxi(0, _items.size() - _per_page))
	_fill_cards()


# ---------------------------------------------------------------- the detail page

func _open_detail(item: Dictionary) -> void:
	_selected = item
	_carousel.visible = false
	_list_button.visible = false
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.free()
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 28)
	_detail.add_child(row)

	# the cover (a plain coloured one while a community entry has no picture)
	var cover_holder := Control.new()
	cover_holder.custom_minimum_size = Vector2(330, 0)
	row.add_child(cover_holder)
	var cover := item.get("texture") as Texture2D
	if cover != null:
		var picture := TextureRect.new()
		picture.texture = cover
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover_holder.add_child(picture)
	else:
		var plain := ColorRect.new()
		plain.color = Color.from_hsv(float(str(item["title"]).hash() % 360) / 360.0, 0.45, 0.3)
		plain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cover_holder.add_child(plain)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	row.add_child(column)
	var title := MenuStyle.shadow_label(str(item["title"]), 36, MenuStyle.TEXT_COLOR)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(420, 0)
	column.add_child(title)
	var byline := str(item.get("author", ""))
	if str(item.get("version", "")) != "":
		byline += ("   ·   " if byline != "" else "") + "v%s" % item["version"]
	if item.get("source", "") == "catalog":
		byline = byline.replace("by ", "")
	if byline != "":
		var author := Label.new()
		author.text = ("by %s" % byline) if str(item.get("author", "")) != "" else byline
		author.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		author.modulate = Color(1, 1, 1, 0.6)
		column.add_child(author)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var text := Label.new()
	text.text = str(item.get("text", "")) if str(item.get("text", "")) != "" else "No description."
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(420, 0)
	text.add_theme_font_size_override("font_size", 19)
	scroll.add_child(text)
	column.add_child(_info_row(item))
	var action_row := CenterContainer.new()
	column.add_child(action_row)
	action_row.add_child(_action_button(item))
	_detail.visible = true
	_detail_backdrop.visible = true
	_title.text = ""


## The campaign / mission icon, the flags and the play time.
func _info_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var icon := TextureRect.new()
	icon.texture = load("res://models/ui/icon_campaign.png" if item.get("kind", "campaign") == "campaign" else "res://models/ui/icon_mission.png") as Texture2D
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = "A campaign" if item.get("kind", "campaign") == "campaign" else "A single mission"
	row.add_child(icon)
	for code: Variant in item.get("languages", []):
		var path := "res://models/ui/flag_%s.png" % str(code)
		if ResourceLoader.exists(path):
			var flag := TextureRect.new()
			flag.texture = load(path) as Texture2D
			flag.custom_minimum_size = Vector2(34, 26)
			flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flag.tooltip_text = CampaignInfo.language_name(str(code))
			row.add_child(flag)
		else:
			var tag := Label.new()
			tag.text = str(code).to_upper()
			row.add_child(tag)
	var time_text := CampaignInfo.duration_text(int(item.get("minutes", 0)))
	if time_text != "":
		var clock := TextureRect.new()
		clock.texture = load("res://models/ui/icon_clock.png") as Texture2D
		clock.custom_minimum_size = Vector2(26, 26)
		clock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(clock)
		var time := Label.new()
		time.text = time_text
		time.add_theme_font_size_override("font_size", 19)
		row.add_child(time)
	return row


## Install (blue) for what comes from the community, otherwise the gold Begin campaign; a single mission gets the blue plaque (the lettering of
## Install / Begin campaign is part of the designer's pictures).
func _action_button(item: Dictionary) -> Control:
	var install: bool = item.get("source", "") == "catalog"
	var button: BaseButton
	if install:
		button = MenuStyle.texture_button(INSTALL_BUTTON, Vector2(260, 101), Callable())
	elif item.get("kind", "campaign") == "campaign":
		button = MenuStyle.texture_button(BEGIN_BUTTON, Vector2(420, 105), Callable())
	else:
		var plaque := MenuStyle.plaque_button("Play mission", Vector2(310, 101), Callable())
		(plaque.get_child(0) as Label).add_theme_font_size_override("font_size", 32)
		button = plaque
	button.pressed.connect(func(): _on_action_pressed(item, button))
	return button


func _on_action_pressed(item: Dictionary, button: BaseButton) -> void:
	if item.get("source", "") != "catalog":
		if item.get("kind", "campaign") == "campaign":
			begin_campaign.emit(str(item["folder"]))
		else:
			play_mission.emit(str(item["path"]))
		return
	if _busy:
		return
	_busy = true
	button.disabled = true
	button.modulate = Color(1, 1, 1, 0.5)
	_status.text = "Installing…"
	var installed := await _install(item["entry"])
	_busy = false
	if not installed:
		button.disabled = false
		button.modulate = Color.WHITE
		return
	_status.text = "Installed \"%s\"." % item["title"]
	refresh()
	for candidate in _items:
		if candidate.get("source", "") == "installed" and candidate.get("id", "") == item["entry"]["id"] and candidate.get("version", "") == item["entry"]["version"]:
			_open_detail(candidate)  # the same page, now with Begin campaign
			return


## Downloads, checks (the whole safe-import validation) and installs a catalog entry. True when it was installed.
func _install(entry: Dictionary) -> bool:
	var path := await _service.download_package(entry["url"], entry["sha256"], entry["name"])
	if path == "":
		return false
	var package := SharePackage.read(path)
	var problem := ""
	if not package["ok"]:
		problem = "This package was not installed - it is damaged or contains something that is not allowed."
	elif package["manifest"]["id"] != entry["id"] or package["manifest"]["version"] != entry["version"]:
		problem = "The downloaded package is not the one the list promised. It was not installed."
	else:
		var result := CommunityLibrary.install(package, entry["url"])
		if not result["ok"]:
			problem = str(result["error"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CommunityService.DOWNLOAD_FILE))
	if problem != "":
		_status.text = problem
		return false
	return true


# ---------------------------------------------------------------- header buttons

func _on_back_pressed() -> void:
	if _detail.visible:
		_show_carousel()
	else:
		back_pressed.emit()


func _on_community_list_pressed() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Downloading the community list…"
	_spin = create_tween().set_loops()
	_spin.tween_property(_list_button, "rotation", TAU, 1.0).from(0.0)
	var address := PlayerSettings.community_catalog_url if PlayerSettings.community_catalog_url != "" else CommunityService.DEFAULT_CATALOG_URL
	var result := await _service.fetch_catalog(address)
	_busy = false
	_spin.kill()
	_list_button.rotation = 0.0
	if not result["ok"]:
		_status.text = str(result["error"])
		return
	_catalog.assign(result["entries"])
	refresh()
	var fresh := 0
	for item in _items:
		if item.get("source", "") == "catalog":
			fresh += 1
	_status.text = "%d from the community to install." % fresh if fresh > 0 else "Nothing new in the community list."
