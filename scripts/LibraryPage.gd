class_name LibraryPage
extends Control

## The New Game page (the designer's mockup): a carousel of hexagonal cards - the campaigns and single missions you have installed, your own
## drafts, and (after the refresh icon is pressed) what the community has shared and you do not have yet - and a detail page with the cover, the story, the
## languages and play time and one button: Install for something from the community, Begin campaign / Play mission for what you have.
## The community list fills itself when the page opens (auto_load_catalog(): a cached list younger than an hour is enough); the refresh icon forces an update.

signal back_pressed
signal begin_campaign(folder: String)
signal play_mission(path: String)

const BACKGROUND := "res://models/ui/bg_rock.jpg"
const GRADIENT := "res://models/ui/bg_gradient_blue.jpg"  ## multiplied over the rock: blue on the left, the plain rock on the right
const DETAIL_BACKGROUND := "res://models/ui/bg_detail.jpg"  ## the same recipe, baked by the designer
const REFRESH_ICON := "res://models/ui/icon_refresh.png"
const BACK_ARROW := "res://models/ui/back_arrow.png"
const NAV_ARROW := "res://models/ui/nav_arrow.png"
## Cover-flow: the card in focus is in the middle, the others step back to each side (smaller, narrower, darker) - all derived from one float.
const FOCUS_SECONDS := 0.5
const SIDE_SQUASH := 0.22      ## how much narrower a card next to the focus looks, as if it were turned away
const SIDE_SHRINK := 0.2       ## and how much smaller
const FAR_SPACING := 0.6       ## spacing of the cards beyond the first neighbour, relative to the first step
const DRAG_THRESHOLD := 8.0
const CATALOG_MAX_AGE_SEC := 3600.0  ## a cached list younger than this is not fetched again by itself
const CATALOG_CACHE := "user://community/catalog_cache.json"  ## the last community list, so it is there at once next time (and offline)
const ARROW_SIZE := 58.0

var _items: Array[Dictionary] = []
var _catalog: Array[Dictionary] = []
var _catalog_saved := ""
var _catalog_saved_unix := 0.0
var _target := 0               ## the card the carousel is heading for
var _focus := 0.0              ## where the carousel is now (animated; the card at this position is in the middle)
var _focus_tween: Tween
var _pressed_in_row := false
var _dragging := false
var _dragged := false          ## a drag happened since the last press, so the release is not a click
var _drag_travel := 0.0
var _drag_velocity := 0.0      ## cards per second
var _busy := false
var _selected: Dictionary = {}

var _carousel: Control
var _cards_row: Control
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
	_cards_row = Control.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_row.gui_input.connect(_on_row_input)
	_cards_row.resized.connect(_update_cards)
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
	_load_cached_catalog()


## What the carousel shows is rebuilt from what is installed (a campaign or mission may have been installed, released or removed since).
func refresh() -> void:
	_items = _build_items()
	_target = clampi(_target, 0, maxi(0, _items.size() - 1))
	_show_carousel()


func _build_items() -> Array[Dictionary]:
	var released: Array[Dictionary] = []
	var drafts: Array[Dictionary] = []
	var online: Array[Dictionary] = []
	# several versions of one package can be installed side by side; the carousel only shows the newest of each
	var latest_installed: Dictionary = {}
	for entry in CommunityLibrary.installed():
		var known: String = latest_installed.get(entry["id"], "")
		if known == "" or CommunityLibrary.compare_versions(str(entry["version"]), known) > 0:
			latest_installed[entry["id"]] = str(entry["version"])
	for entry in CommunityLibrary.installed():
		if str(entry["version"]) != latest_installed[entry["id"]]:
			continue
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
			item["languages"] = CampaignInfo.clean_languages(campaign.offered_languages())
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
				"languages": CampaignInfo.clean_languages(campaign.offered_languages()), "minutes": campaign.duration_minutes,
				"texture": CampaignIO.image_texture(folder, campaign.cover_image), "author": "",
			})
	var latest_online: Dictionary = {}
	for entry in _catalog:
		var seen: String = latest_online.get(entry["id"], "")
		if seen == "" or CommunityLibrary.compare_versions(str(entry["version"]), seen) > 0:
			latest_online[entry["id"]] = str(entry["version"])
	for entry in _catalog:
		if str(entry["version"]) != latest_online[entry["id"]]:
			continue
		# already have this version or a newer one
		if latest_installed.has(entry["id"]) and CommunityLibrary.compare_versions(str(entry["version"]), latest_installed[entry["id"]]) <= 0:
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
	_update_cards()


func _show_carousel() -> void:
	_selected = {}
	_detail.visible = false
	_detail_backdrop.visible = false
	_carousel.visible = true
	_title.text = "New game"
	_list_button.visible = true
	_fill_cards()


func _fill_cards() -> void:
	_stop_focus_tween()
	for child in _cards_row.get_children():
		_cards_row.remove_child(child)
		child.free()
	_target = clampi(_target, 0, maxi(0, _items.size() - 1))
	_focus = float(_target)
	if _items.is_empty():
		var empty := Label.new()
		empty.text = "Nothing here yet. Press the refresh icon to see what the community has shared, or release a campaign of your own in the Campaign Editor."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		empty.custom_minimum_size = Vector2(520, 0)
		empty.grow_horizontal = Control.GROW_DIRECTION_BOTH
		empty.grow_vertical = Control.GROW_DIRECTION_BOTH
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards_row.add_child(empty)
	for index in _items.size():
		var card := CampaignCard.new()
		card.setup(_items[index])
		card.mouse_filter = Control.MOUSE_FILTER_PASS  # the row sees the same events, for dragging
		card.size = CampaignCard.CARD_SIZE
		card.pivot_offset = CampaignCard.CARD_SIZE / 2.0
		card.pressed.connect(_on_card_clicked.bind(index))
		_cards_row.add_child(card)
	_update_arrows()
	_update_cards()


## Puts every card where the carousel's position says: x from the distance to the focus, size, squash, brightness and stacking order from it too.
func _update_cards() -> void:
	if _cards_row == null:
		return
	var fit := _card_fit()
	var step := _card_step()
	var middle := Vector2(_cards_row.size.x / 2.0, _cards_row.size.y / 2.0)
	var cards := _cards_row.get_children()
	for index in cards.size():
		var card := cards[index] as CampaignCard
		if card == null:
			continue
		var distance := float(index) - _focus
		var away := absf(distance)
		var near := minf(away, 1.0)
		var beyond := clampf(away - 1.0, 0.0, 1.0)
		card.visible = away < 3.2
		if not card.visible:
			continue
		var offset_x := signf(distance) * step * (near + maxf(away - 1.0, 0.0) * FAR_SPACING)
		var shrink := fit * (1.0 - SIDE_SHRINK * near - 0.1 * beyond)
		card.scale = Vector2(shrink * (1.0 - SIDE_SQUASH * near - 0.06 * beyond), shrink)
		card.position = Vector2(middle.x + offset_x, middle.y + 14.0 * near * fit) - card.pivot_offset
		var shade := lerpf(1.0, 0.62, near) - 0.12 * beyond
		card.modulate = Color(shade, shade, shade, 1.0 - clampf(away - 2.2, 0.0, 1.0))
		card.z_index = 100 - int(roundf(away * 10.0))


## How big a card is drawn: it grows with the room the stage has (cards are 176 x 456 at 1.0).
func _card_fit() -> float:
	return clampf(_cards_row.size.y / (CampaignCard.CARD_SIZE.y * 1.08), 0.5, 1.3)


## The distance between the middle of the focused card and the first neighbour's.
func _card_step() -> float:
	return CampaignCard.CARD_SIZE.x * _card_fit() * 0.95


func _set_focus(value: float) -> void:
	_focus = value
	_update_cards()


func _stop_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


## Moves the carousel to a card with an eased animation (repeated calls start from wherever it is now).
func _go_to(index: int) -> void:
	_target = clampi(index, 0, maxi(0, _items.size() - 1))
	_stop_focus_tween()
	_focus_tween = create_tween()
	_focus_tween.tween_method(_set_focus, _focus, float(_target), FOCUS_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_update_arrows()


func _update_arrows() -> void:
	_prev_button.visible = _target > 0
	_next_button.visible = _target < _items.size() - 1


func _scroll(direction: int) -> void:
	_go_to(_target + direction)


## A card was released without a drag: a card on the side comes to the middle, the one in the middle opens.
func _on_card_clicked(index: int) -> void:
	if _dragged:
		return
	if index == _target:
		_open_detail(_items[index])
	else:
		_go_to(index)


## Dragging (the row also sees the events of the cards on it) and the mouse wheel.
func _on_row_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressed_in_row = true
				_dragging = false
				_dragged = false
				_drag_travel = 0.0
				_drag_velocity = 0.0
			elif _pressed_in_row:
				_pressed_in_row = false
				if _dragging:
					_dragging = false
					# a flick carries on a little: the speed decides how many cards further it goes
					_go_to(roundi(_focus - _drag_velocity * 0.25))
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll(1)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll(-1)
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressed_in_row and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not _items.is_empty():
		_drag_travel += absf(motion.relative.x)
		if not _dragging and _drag_travel > DRAG_THRESHOLD:
			_dragging = true
			_dragged = true
			_stop_focus_tween()
		if _dragging:
			var cards_moved := -motion.relative.x / _card_step()
			_focus = clampf(_focus + cards_moved, -0.4, float(_items.size() - 1) + 0.4)
			var seconds := maxf(get_process_delta_time(), 0.001)
			_drag_velocity = lerpf(_drag_velocity, cards_moved / seconds, 0.35)
			_target = clampi(roundi(_focus), 0, _items.size() - 1)
			_update_arrows()
			_update_cards()


func _unhandled_input(event: InputEvent) -> void:
	if not _carousel.visible or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_left"):
		_scroll(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		_scroll(1)
		accept_event()
	elif event.is_action_pressed("ui_accept") and not _items.is_empty():
		_open_detail(_items[_target])
		accept_event()


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
			flag.tooltip_text = CampaignInfo.native_name(str(code))
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


## Install (blue plaque) for what comes from the community, otherwise the gold Begin campaign; a single mission gets the blue plaque. The art has no
## lettering: the captions are drawn (and translatable).
func _action_button(item: Dictionary) -> Control:
	var install: bool = item.get("source", "") == "catalog"
	var button: BaseButton
	if install:
		button = MenuStyle.plaque_button(tr("Install"), Vector2(310, 101), Callable(), 36)
	elif item.get("kind", "campaign") == "campaign":
		button = MenuStyle.gold_button(tr("Begin Campaign"), Vector2(470, 102), 44, Callable())
	else:
		button = MenuStyle.plaque_button(tr("Play mission"), Vector2(310, 101), Callable(), 32)
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
	_status.text = tr("Installed \"%s\".") % item["title"]
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


## The refresh icon: always fetch the list now.
func _on_community_list_pressed() -> void:
	await _fetch_catalog()


## Called when the page is shown: fills the list by itself when there is none yet or it is older than CATALOG_MAX_AGE_SEC (the cached one
## is shown meanwhile). The refresh icon forces an update.
func auto_load_catalog() -> void:
	if _busy:
		return
	if _catalog_saved_unix > 0.0 and Time.get_unix_time_from_system() - _catalog_saved_unix < CATALOG_MAX_AGE_SEC:
		return
	await _fetch_catalog()


func _fetch_catalog() -> void:
	if _busy:
		return
	_busy = true
	_status.text = "Looking for shared campaigns…"
	_spin = create_tween().set_loops()
	_spin.tween_property(_list_button, "rotation", TAU, 1.0).from(0.0)
	var address := PlayerSettings.community_catalog_url if PlayerSettings.community_catalog_url != "" else CommunityService.DEFAULT_CATALOG_URL
	var result := await _service.fetch_catalog(address)
	_busy = false
	if _spin != null:
		_spin.kill()
	_list_button.rotation = 0.0
	if not result["ok"]:
		_status.text = ("Offline - showing the last community list. " if not _catalog.is_empty() else "") + str(result["error"])
		return
	_catalog.assign(result["entries"])
	_save_cached_catalog()
	# rebuild the cards without throwing away a detail page the player may have opened meanwhile
	_items = _build_items()
	if _carousel.visible:
		_fill_cards()
	var fresh := 0
	for item in _items:
		if item.get("source", "") == "catalog":
			fresh += 1
	_status.text = tr("%d from the community to install.") % fresh if fresh > 0 else "Nothing new in the community list."


# ---------------------------------------------------------------- the cached list

## The list from the last time it was fetched: read from the disk, nothing goes online.
func _load_cached_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_CACHE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_CACHE))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_catalog_saved = str((parsed as Dictionary).get("saved", ""))
	_catalog_saved_unix = float((parsed as Dictionary).get("saved_unix", 0.0))
	var entries: Variant = (parsed as Dictionary).get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return
	_catalog.clear()
	for raw: Variant in entries:
		var entry := CommunityService._clean_entry(raw)  # the same checks as a freshly downloaded list
		if not entry.is_empty():
			_catalog.append(entry)


func _save_cached_catalog() -> void:
	_catalog_saved = Time.get_datetime_string_from_system(false)
	_catalog_saved_unix = Time.get_unix_time_from_system()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CommunityLibrary.ROOT))
	var file := FileAccess.open(CATALOG_CACHE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"saved": _catalog_saved, "saved_unix": _catalog_saved_unix, "entries": _catalog}))
		file.close()
