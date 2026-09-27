class_name CombatView
extends Control

## The full-screen attack screen (modelled on the real game's combat dialog):
## hero art left, monster art right, weapon plaque top-left, monster hitpoints
## and defense top-right, an info box and the big successes picker in the
## middle with Confirm/Cancel below it, "Damage Type" bottom-left and
## "Weakness" / "Resistance" / "Immunity" bottom-right. Those monster
## properties stay "?" (one per entry, so the table sees how many there are)
## until an attack with a matching damage type has hit the monster - see
## RuntimeMonster.known_*. Pure presentation - PlayerDialog.ask_attack() owns
## the awaiting, the value (its hidden SpinBox) and the voice answers, and
## just calls configure()/show_value() and listens to the buttons/signal below.
##
## Placeholder look: flat colours and shapes, no game art.

signal step_requested(delta: int)  ## the picker's arrows

var confirm_button: Button
var cancel_button: Button
var hint_label: Label

var _hero_image: TextureRect
## EXPERIMENTAL (branch experiment/monster-flat-meshes) - a small 3D preview
## instead of a flat TextureRect, see MonsterCombatPreview.gd's own doc.
var _monster_preview: MonsterCombatPreview
var _hero_name_label: Label
var _weapon_label: Label
var _damage_label: Label
var _hp_label: Label
var _defense_label: Label
var _monster_name_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _value_label: Label
var _damage_box: HBoxContainer
var _property_sections: Dictionary = {}  # "weakness"/"resistance"/"immunity" -> {section, box}

const GOLD := Color(1.0, 0.92, 0.45)
const ORANGE := Color(0.85, 0.42, 0.05)
const BLUE := Color(0.12, 0.42, 0.68)
const ICON_HEIGHT := 64.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	# Background: dark blue (hero side) fading to dark red (monster side).
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.05, 0.09, 0.16))
	gradient.set_color(1, Color(0.22, 0.06, 0.07))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.15, 0.5)
	gradient_texture.fill_to = Vector2(0.85, 0.5)
	var background := TextureRect.new()
	background.texture = gradient_texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Art: hero on the left, monster on the right.
	_hero_image = _art(0.02, 0.44, 0.12, 0.62)
	_monster_preview = MonsterCombatPreview.new()
	_anchor(_monster_preview, 0.56, 0.98, 0.12, 0.62)
	_monster_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_monster_preview)

	# Top-left plaque: hero name, weapon name, base damage - like the real
	# game's own equipped-weapon plaque, but stacked (that one only ever shows
	# one hero/weapon at a time; we need hero + weapon + damage together).
	var plaque := _panel(BLUE, 4)
	plaque.set_anchors_preset(Control.PRESET_TOP_LEFT)
	plaque.offset_left = 0
	plaque.offset_top = 12
	plaque.custom_minimum_size = Vector2(260, 0)
	add_child(plaque)
	var plaque_box := VBoxContainer.new()
	plaque_box.add_theme_constant_override("separation", 2)
	plaque.add_child(plaque_box)
	_hero_name_label = Label.new()
	_hero_name_label.add_theme_font_size_override("font_size", 24)
	plaque_box.add_child(_hero_name_label)
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 18)
	_weapon_label.modulate = Color(1, 1, 1, 0.85)
	plaque_box.add_child(_weapon_label)
	_damage_label = Label.new()
	_damage_label.add_theme_font_size_override("font_size", 16)
	_damage_label.modulate = GOLD
	plaque_box.add_child(_damage_label)

	# Top-right: hitpoints (heart) + defense (shield), monster name below.
	var stats := VBoxContainer.new()
	stats.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	stats.offset_right = -16
	stats.offset_top = 12
	add_child(stats)
	var stat_row := HBoxContainer.new()
	stat_row.alignment = BoxContainer.ALIGNMENT_END
	stat_row.add_theme_constant_override("separation", 12)
	stats.add_child(stat_row)
	_hp_label = _stat_badge(stat_row, Color(0.75, 0.12, 0.1), "♥")
	_defense_label = _stat_badge(stat_row, Color(0.35, 0.4, 0.5), "⛨")
	_monster_name_label = Label.new()
	_monster_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_monster_name_label.add_theme_font_size_override("font_size", 28)
	stats.add_child(_monster_name_label)

	# Centre column: info box, picker, confirm/cancel.
	var centre := VBoxContainer.new()
	centre.set_anchors_preset(Control.PRESET_CENTER)
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	centre.grow_vertical = Control.GROW_DIRECTION_BOTH
	centre.custom_minimum_size = Vector2(440, 0)
	centre.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_theme_constant_override("separation", 14)
	add_child(centre)

	# The info box is for a MONSTER ABILITY/effect (e.g. "Resilience: immune
	# to affliction..."), not a description of the attack - hidden entirely
	# when there is none (no monster abilities exist yet, see configure()).
	_info_panel = _panel(Color(0.02, 0.02, 0.03, 0.9), 2)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 20)
	_info_panel.add_child(_info_label)
	centre.add_child(_info_panel)

	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 18)
	centre.add_child(picker)
	picker.add_child(_arrow("◀", -1))
	var disc := PanelContainer.new()
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(0.02, 0.02, 0.02)
	disc_style.border_color = ORANGE
	disc_style.set_border_width_all(4)
	disc_style.set_corner_radius_all(48)
	disc.add_theme_stylebox_override("panel", disc_style)
	disc.custom_minimum_size = Vector2(96, 96)
	_value_label = Label.new()
	_value_label.text = "0"
	_value_label.add_theme_font_size_override("font_size", 54)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(_value_label)
	picker.add_child(disc)
	picker.add_child(_arrow("▶", 1))

	# Confirm/Cancel sit at the very bottom, between the Damage Type and
	# Weakness/Resistance/Immunity columns - not in the centre column, so they
	# stay put regardless of how tall the (optional) info box or a monster's
	# property list gets.
	var buttons := VBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	buttons.anchor_left = 0.40
	buttons.anchor_right = 0.60
	buttons.anchor_top = 1.0
	buttons.anchor_bottom = 1.0
	buttons.offset_top = -140
	buttons.offset_bottom = -16
	add_child(buttons)
	confirm_button = _big_button("Confirm", ORANGE, 30, Vector2(260, 60))
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_child(confirm_button)
	cancel_button = _big_button("Cancel", Color(0.3, 0.3, 0.32), 22, Vector2(200, 40))
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_child(cancel_button)

	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.modulate = Color(1, 1, 1, 0.65)
	hint_label.visible = false
	buttons.add_child(hint_label)

	# Bottom-left: the weapon's damage types.
	var left := _bottom_column(0.03, 0.40)
	_damage_box = _section(left, "Damage Type", 30)

	# Bottom-right: what is known about the monster.
	var right := _bottom_column(0.60, 0.98)
	for key in ["weakness", "resistance", "immunity"]:
		var section := VBoxContainer.new()
		right.add_child(section)
		var box := _section(section, key.capitalize(), 22)
		_property_sections[key] = {"section": section, "box": box}


## cfg: hero_image, hero_name, weapon_name, base_damage, monster_name,
## hitpoints, defense, damage_types (Array of Vulnerability.Kind), per
## property kind (weaknesses/resistances/immunities, each an Array of Kind)
## plus its known_* twin (the ones already discovered), and optional
## `ability_text` - a MONSTER ability/effect ("Resilience: immune to
## affliction..."), not a description of the attack; the info box is
## hidden entirely when this is empty (no monster abilities are authorable
## yet - fill this in once they are).
##
## The monster side is EITHER `monster_flat_meshes` (Array[String],
## MonsterDisplay.flat_mesh_paths()) + `monster_flat_texture` (Texture2D) -
## the real flat card, rendered in 3D (see MonsterCombatPreview.gd) - OR,
## when those aren't given (Centurion, or a monster with nothing extracted
## yet), `monster_image` (Texture2D, the old crop_texture() mockup) shown
## as a textured quad through that SAME preview mechanism.
func configure(cfg: Dictionary) -> void:
	_hero_image.texture = cfg.get("hero_image")
	var flat_meshes: Array = cfg.get("monster_flat_meshes", [])
	if not flat_meshes.is_empty():
		var typed_paths: Array[String] = []
		for path in flat_meshes:
			typed_paths.append(str(path))
		_monster_preview.show_meshes(typed_paths, cfg.get("monster_flat_texture"), cfg.get("monster_flat_rotation", Vector3.ZERO), cfg.get("monster_flat_surface_overrides", {}))
	else:
		_monster_preview.show_quad(cfg.get("monster_image"))
	_hero_name_label.text = cfg.get("hero_name", "")
	_weapon_label.text = cfg.get("weapon_name", "")
	var base_damage: Variant = cfg.get("base_damage")
	_damage_label.text = "Damage %s" % base_damage if base_damage != null else ""
	_hp_label.text = str(cfg.get("hitpoints", 0))
	_defense_label.text = str(cfg.get("defense", 0))
	_monster_name_label.text = cfg.get("monster_name", "")
	var ability_text: String = cfg.get("ability_text", "")
	_info_panel.visible = ability_text != ""
	_info_label.text = ability_text
	show_value(0)

	var damage_types: Array = cfg.get("damage_types", [])
	_clear(_damage_box)
	for kind in damage_types:
		_damage_box.add_child(_icon_box(kind))

	for pair in [["weakness", "weaknesses", "known_weaknesses"], ["resistance", "resistances", "known_resistances"], ["immunity", "immunities", "known_immunities"]]:
		var entry: Dictionary = _property_sections[pair[0]]
		var all: Array = cfg.get(pair[1], [])
		var known: Array = cfg.get(pair[2], [])
		entry["section"].visible = not all.is_empty()
		_clear(entry["box"])
		for kind in all:
			# Hidden ("?" icon) until discovered.
			entry["box"].add_child(_icon_box(kind if known.has(kind) else -1))


func show_value(v: int) -> void:
	_value_label.text = str(v)


# ---------------------------------------------------------------- helpers

func _art(left: float, right: float, top: float, bottom: float) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_anchor(t, left, right, top, bottom)
	add_child(t)
	return t


func _anchor(control: Control, left: float, right: float, top: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_right = right
	control.anchor_top = top
	control.anchor_bottom = bottom


func _panel(color: Color, border: int) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = color.lightened(0.35)
	s.set_border_width_all(border)
	s.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", s)
	return p


func _stat_badge(parent: Control, color: Color, glyph: String) -> Label:
	var p := _panel(color, 3)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var g := Label.new()
	g.text = glyph
	g.add_theme_font_size_override("font_size", 26)
	row.add_child(g)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 34)
	row.add_child(l)
	p.add_child(row)
	parent.add_child(p)
	return l


func _arrow(glyph: String, delta: int) -> Button:
	var b := Button.new()
	b.text = glyph
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_color_override("font_color", Color(0.9, 0.45, 0.05))
	b.add_theme_color_override("font_hover_color", Color(1, 0.65, 0.2))
	b.pressed.connect(func(): step_requested.emit(delta))
	return b


func _big_button(text: String, color: Color, font_size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.lightened(0.15) if state == "hover" else color
		s.border_color = color.lightened(0.4)
		s.set_border_width_all(3)
		s.set_corner_radius_all(4)
		b.add_theme_stylebox_override(state, s)
	return b


## A bottom-anchored column between two horizontal anchors.
func _bottom_column(left: float, right: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	v.anchor_top = 1.0
	v.anchor_bottom = 1.0
	v.anchor_left = left
	v.anchor_right = right
	v.offset_top = -260
	v.offset_bottom = -16
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	return v


## A gold heading plus a centred row of icon boxes under it; returns the row.
func _section(parent: Control, title: String, font_size: int) -> HBoxContainer:
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", font_size)
	heading.add_theme_color_override("font_color", GOLD)
	parent.add_child(heading)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	parent.add_child(box)
	return box


## The damage-type icon (kind < 0 = the red "?"), scaled to a fixed height.
func _icon_box(kind: int) -> Control:
	var t := TextureRect.new()
	t.texture = Vulnerability.icon(kind)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var h := ICON_HEIGHT
	t.custom_minimum_size = Vector2(h * t.texture.get_width() / t.texture.get_height(), h)
	t.tooltip_text = Vulnerability.display_name(kind) if kind >= 0 else "Unknown"
	return t


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.free()
