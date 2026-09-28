class_name CombatView
extends Control

## The full-screen attack screen (modelled on the real game's combat dialog):
## hero art left, monster art right (full-height, drawn behind every other
## element here - deliberately diverging from the real game's own smaller
## portraits, "to give an impression of the real game" rather than replicate
## it exactly), monster hitpoints and defense top-right, an info box and the
## big successes picker in the middle with Confirm/Cancel below it, "Damage
## Type" bottom-left (each icon with a +1/-1/+? modifier badge - see
## _damage_type_box()) and "Weakness" / "Resistance" / "Immunity"
## bottom-right. Those monster properties stay "?" (one per entry, so the
## table sees how many there are) until an attack with a matching damage type
## has hit the monster - see RuntimeMonster.known_*. Pure presentation -
## PlayerDialog.ask_attack() owns the awaiting, the value (its hidden
## SpinBox) and the voice answers, and just calls configure()/show_value()
## and listens to the buttons/signal below.
##
## No hero-name/weapon-name/base-damage plaque (removed 2026-09-28, direct
## request - "given that the weapon is not visible from the character, we
## can remove it, the character name is also kinda [redundant]... lets
## remove the blue box top left") - the weapon itself was never rendered on
## the hero mesh (see HeroCatalog's own "Weapon" bone/socket doc - nothing's
## attached to it), so naming it added little.
##
## Placeholder look: flat colours and shapes, no game art.

signal step_requested(delta: int)  ## the picker's arrows

var confirm_button: Button
var cancel_button: Button
var hint_label: Label

## EXPERIMENTAL (branch experiment/monster-flat-meshes) - small 3D previews
## instead of flat TextureRects on both sides, see CombatMeshPreview.gd's
## own doc.
var _hero_preview: CombatMeshPreview
var _monster_preview: CombatMeshPreview
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
const ICON_HEIGHT := 64.0
const WEAKNESS_COLOR := Color(0.45, 0.85, 0.45)   # +1 - a known weakness to this damage type
const RESISTANCE_COLOR := Color(0.88, 0.35, 0.35) # -1 - a known resistance to this damage type
const IMMUNE_COLOR := Color(0.55, 0.55, 0.6)      # x - already known to be immune to this type
const UNKNOWN_MODIFIER_COLOR := Color(0.75, 0.75, 0.75) # +? - not yet discovered either way


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

	# Art: hero on the left, monster on the right - full-height and wide, like
	# the real game's own attack screen (2026-09-28, "try to make the
	# hero/monsters a lot bigger, just draw them behind the UI elements... to
	# give an impression of the real game"). Added BEFORE every other node
	# below (plaque/stats/centre/buttons/bottom columns) so those all draw ON
	# TOP of the art regardless of how far it extends - Control z-order is
	# child order, and this was already true even at the old small size, it
	# just wasn't visible since the art never reached under anything. A
	# generous horizontal overlap (0.45-0.55) toward the centre, rather than
	# meeting edge-to-edge at 0.5, so a weapon/limb can dramatically cross
	# into the middle the way the reference screenshot's hammer does.
	_hero_preview = CombatMeshPreview.new()
	_anchor(_hero_preview, 0.0, 0.55, 0.0, 1.0)
	_hero_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero_preview)
	_monster_preview = CombatMeshPreview.new()
	_anchor(_monster_preview, 0.45, 1.0, 0.0, 1.0)
	_monster_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_monster_preview)

	# Particle effects (dust/smoke, briefly also fire sparks) at each
	# fighter's feet were tried and removed again 2026-09-28 - several
	# rounds of tuning (wide ambient band -> localized burst -> bigger
	# clouds, sparks added then removed) never landed ("does not look good
	# remove the particles all together, we come back to that"). See
	# claude.md's own history for the full saga if picking this back up -
	# the generated `_puff_texture()`/CPUParticles2D approach, the
	# foot-localized positioning idea, and a real CC0 sprite pack
	# (Kenney's "Smoke Particles") that was found but never actually
	# integrated are all documented there as starting points.

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


## cfg: monster_name, hitpoints, defense, damage_types (Array of
## Vulnerability.Kind), per property kind (weaknesses/resistances/immunities,
## each an Array of Kind) plus its known_* twin (the ones already
## discovered - see the Damage Type badges below), and optional `ability_text` -
## a MONSTER ability/effect ("Resilience: immune to affliction..."), not a
## description of the attack; the info box is hidden entirely when this is
## empty (no monster abilities are authorable yet - fill this in once they
## are).
##
## Each side is EITHER `<side>_flat_meshes` (Array[String], HeroCatalog/
## MonsterDisplay.flat_mesh_paths()) + `<side>_flat_texture` (Texture2D) -
## the real mesh, rendered in 3D (see CombatMeshPreview.gd) - OR, when those
## aren't given (nothing extracted for this hero/monster yet), `hero_image`/
## `monster_image` (Texture2D, the old crop_texture() mockup) shown as a
## textured quad through that SAME preview mechanism. `monster_flat_rotation`/
## `monster_flat_surface_overrides` are monster-only (Centurion's wings need
## a distinct texture; heroes have no such override case yet). `hero_size_units`/
## `monster_size_units` (new 2026-09-28, default 1.0 each) feed
## CombatMeshPreview's relative-scale system - see that script's own doc.
## The camera frame itself is sized off `maxf()` of the two - THIS
## encounter's own larger fighter, not the largest size_units in the whole
## game - so a small pair (e.g. Kehli vs. a Wolf) fills the screen as much
## as a Centurion encounter does, rather than every non-Centurion fight
## rendering small inside headroom reserved for a creature that isn't
## actually there ("show characters as big as possible, not relative to the
## biggest character in the game but to each other").
func configure(cfg: Dictionary) -> void:
	var hero_size_units: float = cfg.get("hero_size_units", 1.0)
	var monster_size_units: float = cfg.get("monster_size_units", 1.0)
	var camera_size_units := maxf(hero_size_units, monster_size_units)
	_configure_preview(_hero_preview, cfg.get("hero_flat_meshes", []), cfg.get("hero_flat_texture"), cfg.get("hero_image"), cfg.get("hero_flat_rotation", Vector3.ZERO), {}, hero_size_units, camera_size_units)
	_configure_preview(_monster_preview, cfg.get("monster_flat_meshes", []), cfg.get("monster_flat_texture"), cfg.get("monster_image"), cfg.get("monster_flat_rotation", Vector3.ZERO), cfg.get("monster_flat_surface_overrides", {}), monster_size_units, camera_size_units)
	_hp_label.text = str(cfg.get("hitpoints", 0))
	_defense_label.text = str(cfg.get("defense", 0))
	_monster_name_label.text = cfg.get("monster_name", "")
	var ability_text: String = cfg.get("ability_text", "")
	_info_panel.visible = ability_text != ""
	_info_label.text = ability_text
	show_value(0)

	var damage_types: Array = cfg.get("damage_types", [])
	var known_weaknesses: Array = cfg.get("known_weaknesses", [])
	var known_resistances: Array = cfg.get("known_resistances", [])
	var known_immunities: Array = cfg.get("known_immunities", [])
	_clear(_damage_box)
	for kind in damage_types:
		_damage_box.add_child(_damage_type_box(kind, known_weaknesses, known_resistances, known_immunities))

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


## Shared by both sides' configure() branch - real mesh(es) if given, else
## the flat-image mockup/fallback quad. See configure()'s own doc.
func _configure_preview(preview: CombatMeshPreview, flat_meshes: Array, flat_texture: Texture2D, fallback_image: Texture2D, rotation_correction: Vector3 = Vector3.ZERO, surface_overrides: Dictionary = {}, size_units: float = 1.0, camera_size_units: float = 1.0) -> void:
	if not flat_meshes.is_empty():
		var typed_paths: Array[String] = []
		for path in flat_meshes:
			typed_paths.append(str(path))
		preview.show_meshes(typed_paths, flat_texture, rotation_correction, surface_overrides, size_units, camera_size_units)
	else:
		preview.show_quad(fallback_image)


# ---------------------------------------------------------------- helpers

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


## A Damage Type icon PLUS a small modifier badge underneath it, telling the
## table what bonus/penalty they can expect from attacking with this damage
## type - "maybe also show +1/-1 based on know weakness/resistance so
## players get an idea of what bonuses they can expect. If unknown do '+ ?'"
## (2026-09-28). Deliberately reads only the KNOWN sets (never the full,
## still-secret weaknesses/resistances/immunities arrays also present in
## cfg) - anything not yet discovered shows "+?" regardless of whether it's
## secretly a real bonus or not, same "hidden until discovered" rule the
## Weakness/Resistance/Immunity sections already enforce; showing the real
## answer here would let a table read a monster's hidden properties straight
## off the weapon picker without ever having to land a matching hit first.
func _damage_type_box(kind: int, known_weaknesses: Array, known_resistances: Array, known_immunities: Array) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 2)
	column.add_child(_icon_box(kind))

	var text: String
	var color: Color
	if known_immunities.has(kind):
		# A known immunity always wins over a weakness/resistance to the same
		# kind (matches MissionRuntime.resolve_attack()'s own precedence -
		# immune sets damage to 0 outright, weakness/resistance never apply).
		text = "×"
		color = IMMUNE_COLOR
	elif known_weaknesses.has(kind) and known_resistances.has(kind):
		text = "+0"  # both known and cancel out - genuinely possible, MonsterTemplate doesn't forbid the same kind appearing in both lists
		color = UNKNOWN_MODIFIER_COLOR
	elif known_weaknesses.has(kind):
		text = "+1"
		color = WEAKNESS_COLOR
	elif known_resistances.has(kind):
		text = "-1"
		color = RESISTANCE_COLOR
	else:
		text = "+?"
		color = UNKNOWN_MODIFIER_COLOR

	var badge := Label.new()
	badge.text = text
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 18)
	badge.add_theme_color_override("font_color", color)
	column.add_child(badge)
	return column


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.free()
