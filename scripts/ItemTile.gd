class_name ItemTile
extends RefCounted

## A tile of the item grids (the inventory, the market...) - never instantiated, a shared builder: the picture (a coloured
## placeholder with the first letter when there is none), the name under it, a "+" badge for an upgraded card and a count for
## materials. Extra controls (the market's Buy / Sell buttons) can be added under the name.

const WIDTH := 112.0
const PICTURE_HEIGHT := 96.0


## The dark rounded panel every tile and card sits in.
static func card_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.17, 0.9)
	style.border_color = Color(0.3, 0.33, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	return panel


## A material of the party's stock as a chip: its small picture and how many the party has.
static func stock_chip(key: String, count: int) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	chip.tooltip_text = "%s: %d" % [LootMaterials.display_name(key), count]
	var texture := ItemData.material_image(key)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.custom_minimum_size = Vector2(36, 36)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(rect)
	else:
		var name_label := Label.new()
		name_label.text = LootMaterials.display_name(key)
		chip.add_child(name_label)
	var amount := Label.new()
	amount.text = "×%d" % count
	amount.add_theme_font_size_override("font_size", 16)
	chip.add_child(amount)
	return chip


## A material in a recipe: its small picture and "have/needed" - the party's stock against what the recipe needs (green when there is
## enough, red when not).
static func ingredient_chip(key: String, needed: int, have: int) -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 2)
	chip.tooltip_text = "%s: needs %d, you have %d" % [LootMaterials.display_name(key), needed, have]
	var texture := ItemData.material_image(key)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.custom_minimum_size = Vector2(32, 32)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(rect)
	else:
		var name_label := Label.new()
		name_label.text = LootMaterials.display_name(key)
		chip.add_child(name_label)
	var count := Label.new()
	count.text = "%d/%d" % [have, needed]
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if have < needed else Color(0.55, 0.9, 0.55))
	chip.add_child(count)
	return chip


## `item`: {title, texture (Texture2D or null), badge ("+" or ""), count (-1 = none), tooltip}. `below` is put under the name.
static func build(item: Dictionary, below: Control = null) -> Control:
	var panel := card_panel()
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.tooltip_text = str(item.get("tooltip", item["title"]))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var picture := Control.new()
	picture.custom_minimum_size = Vector2(WIDTH - 12, PICTURE_HEIGHT)
	box.add_child(picture)
	var texture: Texture2D = item.get("texture")
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.add_child(rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color.from_hsv(float(str(item["title"]).hash() % 360) / 360.0, 0.4, 0.45)
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		picture.add_child(placeholder)
		var initial := Label.new()
		initial.text = str(item["title"]).substr(0, 1).to_upper()
		initial.add_theme_font_size_override("font_size", 32)
		initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		picture.add_child(initial)
	var badge := str(item.get("badge", ""))
	if badge != "":
		picture.add_child(_corner_label(badge, Control.PRESET_TOP_RIGHT, Color(1.0, 0.85, 0.35)))
	var count := int(item.get("count", -1))
	if count >= 0:
		picture.add_child(_corner_label("×%d" % count, Control.PRESET_BOTTOM_RIGHT, Color(1, 1, 1)))
		if count == 0:
			picture.modulate = Color(1, 1, 1, 0.45)

	var name_label := Label.new()
	name_label.text = str(item["title"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size.x = WIDTH - 12
	name_label.add_theme_font_size_override("font_size", 12)
	box.add_child(name_label)
	if below != null:
		box.add_child(below)
	return panel


## {title, texture, badge, count, tooltip} - what build() takes.
static func data(title: String, texture: Texture2D, upgraded: bool = false, count: int = -1, tooltip: String = "") -> Dictionary:
	return {"title": title, "texture": texture, "badge": "+" if upgraded else "", "count": count, "tooltip": tooltip if tooltip != "" else title}


## A small bold label stuck to a corner of a tile picture (the "+" of an upgraded card, the count of a material).
static func _corner_label(text: String, preset: Control.LayoutPreset, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 5)
	label.set_anchors_and_offsets_preset(preset)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if preset == Control.PRESET_BOTTOM_RIGHT:
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return label
