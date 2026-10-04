class_name CombatView
extends Control

## The full-screen attack screen (modelled on the real game's combat dialog):
## hero art left, monster art right (full-height, drawn behind every other
## element here - deliberately diverging from the real game's own smaller
## portraits, "to give an impression of the real game" rather than replicate
## it exactly), monster hitpoints and defense top-right, an info box and the
## big successes picker in the middle with Confirm/Cancel below it, "Damage
## Type" bottom-left and "Weakness" (weakness+resistance combined, shield-
## badge icons) / "Immunity" bottom-right. Those monster properties stay
## "?" (one per entry, so the table sees how many there are) until an
## attack with a matching damage type has hit the monster - see
## RuntimeMonster.known_*. Pure presentation -
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

## Three stages share this one full-screen view and its background (new
## 2026-10-04, "the weapon choice and the result overview look kinda dull"):
## `show_choice()` - the hero's two flat meshes side by side, click one to
## pick that weapon; `configure()` - the combat screen described above;
## `show_result()` - the art again with the damage breakdown text in the
## middle. PlayerDialog owns the awaiting; `hint_label` always points at the
## current stage's voice-hint label.

signal step_requested(delta: int)  ## the picker's arrows

var confirm_button: Button
var cancel_button: Button
var hint_label: Label  ## the CURRENT stage's voice-hint label (see _set_stage())
var choice_buttons: Array[Button] = []  ## the weapon-choice stage's two options, then...
var choice_cancel_button: Button  ## ...its Cancel
var result_ok_button: Button

var _art_layer: Control  ## the hero/monster previews (every stage)
var _ui_layer: Control  ## the combat stage's stats/picker/buttons/columns
var _choice_layer: Control
var _result_layer: Control
var _combat_hint_label: Label
var _choice_hint_label: Label
var _result_hint_label: Label
var _result_label: Label
var _choice_title: Label
var _choice_info: Array[VBoxContainer] = []
var _choice_tween: Tween

## EXPERIMENTAL (branch experiment/monster-flat-meshes) - small 3D previews
## instead of flat TextureRects on both sides, see CombatMeshPreview.gd's
## own doc.
var _hero_preview: CombatMeshPreview
var _monster_preview: CombatMeshPreview
var _hp_label: Label
var _hp_fill: ColorRect
var _defense_label: Label
var _monster_name_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _value_label: Label
var _damage_box: HBoxContainer
var _property_sections: Dictionary = {}  # "vulnerability" (weakness+resistance combined)/"immunity" -> {section, box}

const GOLD := Color(1.0, 0.92, 0.45)
const ORANGE := Color(0.85, 0.42, 0.05)
const ICON_HEIGHT := 64.0
const HP_BOX_SIZE := Vector2(240, 48)  ## ~2.5x the original compact heart-badge box - "make that wider 2.5x and use that [as the health bar]"
const DEFENSE_BOX_WIDTH := 100.0  ## the Defense badge's own width; height is pinned to HP_BOX_SIZE.y, see _build_defense_box()
const HEADING_FONT_SIZE := 20  ## shared by "Damage Type" and "Weakness" so both bottom columns match ("use the same style for the weapon damage type, same font size")
const PROPERTY_ICON_HEIGHT := 30.0  ## the small damage-type icon inside its bordered badge
const TICK_COUNT := 8  ## the outer ring's radial tick marks, one every 45 degrees
const TICK_RADIUS := 56.0  ## matches disc_wrap's own half-size (112/2) - the outer_ring's true edge
const TICK_GAP := 2.0  ## small gap between the ring's edge and where a tick starts
const TICK_LENGTH_SHORT := 6.0  ## the diagonal ticks (45/135/225/315)
const TICK_LENGTH_LONG := 10.0  ## the cardinal ticks (angle mod 90 == 0)
const CHOICE_SLIDE_SEC := 0.55  ## weapon-choice slide-in duration
const CHOICE_SLIDE_STAGGER_SEC := 0.12  ## the right-hand model starts this much later
const CHOICE_CAMERA_SCALE := 1.15  ## weapon-choice stage: a bit more headroom than the combat stage's deliberate overflow, so a hero's weapon isn't clipped at the sides of its half

## Shield-art badges removed (2026-10-01, "remove the shields, but a double
## gray border around the icons") - see `_bordered_icon_box()` for what
## replaced them. The generated shield.png/shield_broken.png files
## themselves are left in models/icons/ (and tools/asset_import/
## generate_shield_icons.py kept, per the earlier "keep the script around"
## request) in case this look is revisited, just no longer referenced here.
const ICON_BORDER_PADDING := Vector2(14, 14)  ## gap between the icon and its own (inner) border
const ICON_BORDER_GAP := 7.0  ## gap between the inner and outer border, each side - widened 5 -> 9 (2026-10-01, "a small bit of whitespace (filled with black) between the inner and outer border"), then eased back slightly to 7 the same day once actually seen rendered
const ICON_BORDER_COLOR := Color(0.72, 0.74, 0.78, 0.9)  ## gray outer ring, and the Damage Type row's own inner ring ("damage type can stay as is color wise")
const WEAKNESS_BORDER_COLOR := Color(0.55, 0.12, 0.10)  ## dark red, same hue family as the background gradient's own monster-side end colour
const RESISTANCE_BORDER_COLOR := Color(0.14, 0.22, 0.42)  ## dark blue, same hue family as the background gradient's own hero-side start colour

## A faint atmospheric background texture (new 2026-10-01, user-supplied
## image - "can we use this as a very light overlay in the combat view,
## make it very transparant" -> "i mean as background") - a dark pentagram/
## skulls illustration, layered on top of the existing blue->red gradient
## (not replacing it) at very low opacity so it reads as a subtle mood
## texture rather than competing with the hero/monster art or any UI on
## top of it. Not derived from the real game's own assets in any way
## (unlike the damage-type icons/HUD icons elsewhere in this project,
## which DO have confirmed real names in the game's own asset dump) - the
## user's own supplied image, same "no official counterpart, ships as-is"
## treatment this project already gives its other original/generated art
## (gate/archway/tree, the shield icons before this session removed them).
const BACKGROUND_TEXTURE := preload("res://models/combat_background_pentagram.jpg")
const BACKGROUND_TEXTURE_ALPHA := 0.12  ## "very transparant" - a first-guess opacity, adjust after a real look


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

	# A faint pentagram/skulls texture over the gradient (new 2026-10-01,
	# see BACKGROUND_TEXTURE's own doc) - STRETCH_KEEP_ASPECT_COVERED so it
	# fills the screen at any aspect ratio without distorting, cropped
	# rather than letterboxed. Added right after the plain gradient, so
	# the hero/monster art and every UI element still draws on top of it
	# same as they already do for the gradient itself.
	var background_texture := TextureRect.new()
	background_texture.texture = BACKGROUND_TEXTURE
	# EXPAND_IGNORE_SIZE (new 2026-10-01, fixing "it's off center atm") -
	# without this, a TextureRect's own minimum size defaults to its
	# texture's native pixel size (1408x768 here), which can win out over
	# the PRESET_FULL_RECT anchors below and leave it sized/positioned
	# from its top-left corner instead of actually filling (and centering
	# within) the real viewport rect - exactly what "off centre" looks
	# like. The working gradient background above already sets this; this
	# TextureRect just hadn't been given the same treatment yet.
	background_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background_texture.modulate = Color(1, 1, 1, BACKGROUND_TEXTURE_ALPHA)
	background_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background_texture)

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
	_art_layer = _layer()
	add_child(_art_layer)
	_ui_layer = _layer()
	add_child(_ui_layer)
	_hero_preview = CombatMeshPreview.new()
	_hero_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(_hero_preview)
	_monster_preview = CombatMeshPreview.new()
	_monster_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_layer.add_child(_monster_preview)
	_anchor_art_for_combat()

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
	_ui_layer.add_child(stats)
	var stat_row := HBoxContainer.new()
	stat_row.alignment = BoxContainer.ALIGNMENT_END
	stat_row.add_theme_constant_override("separation", 12)
	stats.add_child(stat_row)
	_build_hp_box(stat_row)
	_defense_label = _build_defense_box(stat_row)

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
	_ui_layer.add_child(centre)

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

	# The successes disc gets a second, concentric ring around it (new
	# 2026-09-29, "to give the input a bit more feel, can we add a double
	# circle around it") - a plain wrapper Control sized a bit bigger than
	# the disc itself, holding a second bordered-but-transparent-fill ring
	# BEHIND the disc, centred on the same point so an even gap shows
	# between the two circles.
	#
	# **Bug fix, same day** - the first version (PRESET_CENTER anchors on
	# both the ring and the disc) came out rendered off-centre from each
	# other, and the whole cluster no longer sat evenly between the two
	# arrow buttons. Same root cause as the HP box fix above: `disc_wrap`
	# is a plain Control inside `picker` (an HBoxContainer) and its
	# cross-axis size flag defaults to SIZE_FILL, so it could stretch
	# unpredictably; `size_flags_vertical = SIZE_SHRINK_CENTER` locks it to
	# exactly its own 112x112 minimum, and both children are positioned
	# with plain absolute `position`/`size` (default top-left anchors,
	# `disc` hand-centred at `(112-96)/2 = 8` on each side) instead of
	# anchor-preset tricks - fully deterministic.
	var disc_wrap := Control.new()
	disc_wrap.custom_minimum_size = Vector2(112, 112)
	disc_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.add_child(disc_wrap)

	var outer_ring := PanelContainer.new()
	var outer_ring_style := StyleBoxFlat.new()
	outer_ring_style.bg_color = Color(0, 0, 0, 0)
	outer_ring_style.border_color = ORANGE.darkened(0.35)
	outer_ring_style.set_border_width_all(2)
	outer_ring_style.set_corner_radius_all(56)
	outer_ring.add_theme_stylebox_override("panel", outer_ring_style)
	outer_ring.position = Vector2.ZERO
	outer_ring.size = Vector2(112, 112)
	outer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc_wrap.add_child(outer_ring)

	# Radial tick marks around the outer ring (new 2026-09-29, "add a small
	# outside pointing lines, lets say we add one every 45degree, make the
	# ones for which mod 90 = 0 a bit longer") - a plain dial/gauge
	# decoration, 8 short Line2D segments pointing straight out from the
	# ring's centre, the 4 cardinal ones (0/90/180/270) a bit longer than
	# the 4 diagonal ones (45/135/225/315).
	_build_disc_ticks(disc_wrap)

	var disc := PanelContainer.new()
	var disc_style := StyleBoxFlat.new()
	disc_style.bg_color = Color(0.02, 0.02, 0.02)
	disc_style.border_color = ORANGE
	disc_style.set_border_width_all(4)
	disc_style.set_corner_radius_all(48)
	disc.add_theme_stylebox_override("panel", disc_style)
	disc.position = Vector2(8, 8)
	disc.size = Vector2(96, 96)
	_value_label = Label.new()
	_value_label.text = "0"
	_value_label.add_theme_font_size_override("font_size", 54)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.add_child(_value_label)
	disc_wrap.add_child(disc)

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
	_ui_layer.add_child(buttons)
	# Sized down 2026-09-29 - "make confirm and cancel buttons a bit
	# smaller, they feel very large."
	confirm_button = _big_button("Confirm", ORANGE, 22, Vector2(190, 44))
	confirm_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_child(confirm_button)
	cancel_button = _big_button("Cancel", Color(0.3, 0.3, 0.32), 16, Vector2(150, 32))
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buttons.add_child(cancel_button)

	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.modulate = Color(1, 1, 1, 0.65)
	hint_label.visible = false
	buttons.add_child(hint_label)
	_combat_hint_label = hint_label

	# Bottom-left: the weapon's damage types. No modifier badge underneath
	# each icon any more (removed 2026-09-29, "remove the actual damage
	# indicator, it needs a better spot but not there it should be a bit
	# symmetrical") - plain icons now, same as the Weakness list opposite
	# it, so the two bottom corners read as a matching pair.
	var left := _bottom_column(0.03, 0.40)
	_damage_box = _section(left, "Damage Type", HEADING_FONT_SIZE)

	# Bottom-right: what is known about the monster. Weakness/Resistance
	# share ONE compact list now (new 2026-09-29) - small bordered icons
	# instead of each getting its own full-size heading+row ("weakness is
	# a bit verbose, in the game they put the weakness on a list, make the
	# icon smaller"). Immunity keeps its own full-size section, unchanged -
	# only weakness/resistance were called out. Heading text shortened to
	# just "Weakness" (same day, follow-up request).
	# No longer shifted up relative to `left` (that 30px offset existed
	# only to make room for the old shield badges' own extra height -
	# removed 2026-10-01 alongside the shields themselves, "make sure that
	# the weapon damage and weakness areas are aligned vertically on the
	# same height" - both columns now use the identical `_bordered_icon_box()`
	# badge size, so the shared `_bottom_column()` anchoring already lines
	# them up with no per-column correction needed).
	var right := _bottom_column(0.60, 0.98)
	var vulnerability_section := VBoxContainer.new()
	right.add_child(vulnerability_section)
	var vulnerability_box := _section(vulnerability_section, "Weakness", HEADING_FONT_SIZE)
	_property_sections["vulnerability"] = {"section": vulnerability_section, "box": vulnerability_box}
	var immunity_section := VBoxContainer.new()
	right.add_child(immunity_section)
	var immunity_box := _section(immunity_section, "Immunity", 22)
	_property_sections["immunity"] = {"section": immunity_section, "box": immunity_box}

	_build_choice_layer()
	_build_result_layer()
	_set_stage("combat")


# ---------------------------------------------------------------- stages

## A full-rect, click-through container - the stage layers' common shape.
func _layer() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _anchor_art_for_combat() -> void:
	_anchor(_hero_preview, 0.0, 0.55, 0.0, 1.0)
	_anchor(_monster_preview, 0.45, 1.0, 0.0, 1.0)
	_reset_art_offsets()


## The weapon-choice slide-in animates the previews' offsets - every other
## stage needs them back at 0 (rect == anchors) and the tween gone.
func _reset_art_offsets() -> void:
	if _choice_tween != null:
		_choice_tween.kill()
		_choice_tween = null
	for p in [_hero_preview, _monster_preview]:
		p.offset_left = 0.0
		p.offset_right = 0.0
		p.offset_top = 0.0
		p.offset_bottom = 0.0
	for info in _choice_info:
		info.modulate.a = 1.0
	if _ui_layer != null:
		_ui_layer.modulate.a = 1.0


## The two weapon models slide in from the screen edges (hero's weapon 1 from
## the left, weapon 2 from the right, the right one a beat later), and the
## weapon texts fade in once they've mostly arrived (new 2026-10-04, "make the
## models slide in from the side").
func _slide_in_choice() -> void:
	_slide_in(get_viewport_rect().size.x * 0.5, [_choice_info[0], _choice_info[1]])


## The combat stage does the same (new 2026-10-04, "do the same on the combat
## view itself with hero and monster"): hero from the left, monster from the
## right, the whole UI layer (stats, picker, buttons, columns) fading in once
## they've mostly arrived.
func _slide_in_combat() -> void:
	_slide_in(get_viewport_rect().size.x * 0.55, [_ui_layer])


## Slides the left preview in from the left and the right one in from the
## right by `distance` pixels (the right one a beat later), fading each of
## `fade_in` (one node per side, or a single one for both) in at ~60% of the
## slide.
func _slide_in(distance: float, fade_in: Array) -> void:
	_reset_art_offsets()
	_hero_preview.offset_left = -distance
	_hero_preview.offset_right = -distance
	_monster_preview.offset_left = distance
	_monster_preview.offset_right = distance
	_choice_tween = create_tween().set_parallel(true)
	var previews: Array[CombatMeshPreview] = [_hero_preview, _monster_preview]
	for i in 2:
		var delay := i * CHOICE_SLIDE_STAGGER_SEC
		for prop in ["offset_left", "offset_right"]:
			_choice_tween.tween_property(previews[i], prop, 0.0, CHOICE_SLIDE_SEC).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in fade_in.size():
		var node: Control = fade_in[i]
		node.modulate.a = 0.0
		_choice_tween.tween_property(node, "modulate:a", 1.0, 0.3).set_delay(i * CHOICE_SLIDE_STAGGER_SEC + CHOICE_SLIDE_SEC * 0.6)


## The weapon-choice stage reuses the same two previews, one per half of the
## screen (hero weapon 1 left, weapon 2 right) - no extra 3D viewports.
func _anchor_art_for_choice() -> void:
	_anchor(_hero_preview, 0.0, 0.5, 0.0, 1.0)
	_anchor(_monster_preview, 0.5, 1.0, 0.0, 1.0)


func _set_stage(stage: String) -> void:
	_ui_layer.visible = stage == "combat"
	_choice_layer.visible = stage == "choice"
	_result_layer.visible = stage == "result"
	if stage == "choice":
		_anchor_art_for_choice()
	else:
		_anchor_art_for_combat()
	match stage:
		"choice":
			hint_label = _choice_hint_label
		"result":
			hint_label = _result_hint_label
		_:
			hint_label = _combat_hint_label


## Weapon-choice stage UI: a title, one big click target per half (translucent
## highlight on hover) with the weapon's name / summary / damage-type icons at
## the bottom of its half, and Cancel in the middle. The previews behind it
## are the shared art ones, filled in by show_choice().
func _build_choice_layer() -> void:
	_choice_layer = _layer()
	add_child(_choice_layer)

	_choice_title = Label.new()
	_choice_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_choice_title.offset_top = 20
	_choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_choice_title.add_theme_font_size_override("font_size", 30)
	_choice_title.add_theme_color_override("font_color", GOLD)
	_choice_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choice_layer.add_child(_choice_title)

	for i in 2:
		var click := Button.new()
		click.focus_mode = Control.FOCUS_NONE
		click.flat = true
		var normal := StyleBoxEmpty.new()
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.06)
		hover.border_color = Color(GOLD, 0.8)
		hover.set_border_width_all(3)
		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(1, 1, 1, 0.14)
		pressed.border_color = GOLD
		pressed.set_border_width_all(3)
		click.add_theme_stylebox_override("normal", normal)
		click.add_theme_stylebox_override("hover", hover)
		click.add_theme_stylebox_override("pressed", pressed)
		click.add_theme_stylebox_override("focus", normal)
		_anchor(click, i * 0.5, (i + 1) * 0.5, 0.0, 1.0)
		click.offset_top = 80
		click.offset_bottom = -100
		click.offset_left = 12 if i == 0 else 6
		click.offset_right = -6 if i == 0 else -12
		_choice_layer.add_child(click)
		choice_buttons.append(click)

	for i in 2:
		var info := VBoxContainer.new()
		info.alignment = BoxContainer.ALIGNMENT_END
		info.add_theme_constant_override("separation", 6)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anchor(info, i * 0.5, (i + 1) * 0.5, 1.0, 1.0)
		info.offset_top = -260
		info.offset_bottom = -110
		_choice_layer.add_child(info)
		_choice_info.append(info)

	var bottom := VBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	_anchor(bottom, 0.35, 0.65, 1.0, 1.0)
	bottom.offset_top = -92
	bottom.offset_bottom = -12
	_choice_layer.add_child(bottom)
	choice_cancel_button = _big_button("Cancel", Color(0.3, 0.3, 0.32), 16, Vector2(150, 32))
	choice_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(choice_cancel_button)
	_choice_hint_label = _hint_label_node()
	bottom.add_child(_choice_hint_label)


## The result stage: the combat art stays up, the damage breakdown text sits in
## a panel in the middle with an OK button under it. Text only for now.
func _build_result_layer() -> void:
	_result_layer = _layer()
	add_child(_result_layer)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(560, 0)
	column.add_theme_constant_override("separation", 16)
	_result_layer.add_child(column)

	var panel := _panel(Color(0.02, 0.02, 0.03, 0.88), 2)
	column.add_child(panel)
	_result_label = Label.new()
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 26)
	panel.add_child(_result_label)

	result_ok_button = _big_button("OK", ORANGE, 22, Vector2(190, 44))
	result_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(result_ok_button)
	_result_hint_label = _hint_label_node()
	column.add_child(_result_hint_label)


func _hint_label_node() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.modulate = Color(1, 1, 1, 0.65)
	l.visible = false
	return l


## Weapon-choice stage. cfg: `title` (e.g. "Brynn attacks Wolf - choose a
## weapon"), `hero_size_units`, and `options` - exactly two Dictionaries, one
## per weapon, each `name`, `subtitle`, `damage_types` (Array of Kind) plus the
## hero's art for that weapon in the same keys configure() uses
## (`flat_meshes`/`flat_texture`/`flat_rotation`, else `image`). The player
## clicks (or says) one - see choice_buttons/choice_cancel_button.
func show_choice(cfg: Dictionary) -> void:
	_set_stage("choice")
	_choice_title.text = cfg.get("title", "Choose a weapon")
	var hero_size_units: float = cfg.get("hero_size_units", 1.0)
	var options: Array = cfg.get("options", [])
	var previews: Array[CombatMeshPreview] = [_hero_preview, _monster_preview]
	for i in mini(options.size(), 2):
		var option: Dictionary = options[i]
		_configure_preview(previews[i], option.get("flat_meshes", []), option.get("flat_texture"), option.get("image"), option.get("flat_rotation", Vector3.ZERO), {}, hero_size_units, hero_size_units * CHOICE_CAMERA_SCALE, true)
		var info := _choice_info[i]
		_clear(info)
		var name_label := Label.new()
		name_label.text = option.get("name", "")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 30)
		name_label.add_theme_color_override("font_color", GOLD)
		info.add_child(name_label)
		var subtitle := Label.new()
		subtitle.text = option.get("subtitle", "")
		subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		subtitle.add_theme_font_size_override("font_size", 18)
		info.add_child(subtitle)
		var icons := HBoxContainer.new()
		icons.alignment = BoxContainer.ALIGNMENT_CENTER
		icons.add_theme_constant_override("separation", 10)
		for kind in option.get("damage_types", []):
			icons.add_child(_bordered_icon_box(kind, Vulnerability.display_name(kind)))
		info.add_child(icons)
		_ignore_mouse(info)
	_slide_in_choice()


## Result stage: the combat art (configured from `cfg`, same dictionary as
## configure() - needed because the view may not have been shown for this
## attack at all when the successes were spoken in the command) plus `text`.
func show_result(cfg: Dictionary, text: String) -> void:
	configure(cfg, false)  # no slide-in - the art is already in place from the successes screen
	_set_stage("result")
	_result_label.text = text


func _ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)


## cfg: monster_name, hitpoints, max_hitpoints (new 2026-09-29 - the health
## bar's "progress" denominator; falls back to hitpoints itself, i.e. a full
## bar, if not given), defense, damage_types (Array of
## Vulnerability.Kind), per property kind (weaknesses/resistances/immunities,
## each an Array of Kind) plus its known_* twin (the ones already
## discovered - see the Weakness shield badges below), and optional `ability_text` -
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
##
## Monster preview passes `write_depth = false` (new 2026-09-29) - see
## CombatMeshPreview._unshaded_material()'s own doc for why: monster cards
## are built from SEPARATE pieces meant to layer via alpha (a jacket's
## mostly-transparent cutout drawn over pants), and forcing depth write
## broke that ("the bandit upper jacket comes over his pants... the pants
## are hidden a bit by blackness"). Heroes keep the default `true` - a
## single open mesh's own self-occlusion is a different problem, confirmed
## fixed by exactly this depth write.
func configure(cfg: Dictionary, animate: bool = true) -> void:
	_set_stage("combat")
	var hero_size_units: float = cfg.get("hero_size_units", 1.0)
	var monster_size_units: float = cfg.get("monster_size_units", 1.0)
	var camera_size_units := maxf(hero_size_units, monster_size_units)
	_configure_preview(_hero_preview, cfg.get("hero_flat_meshes", []), cfg.get("hero_flat_texture"), cfg.get("hero_image"), cfg.get("hero_flat_rotation", Vector3.ZERO), {}, hero_size_units, camera_size_units, true)
	_configure_preview(_monster_preview, cfg.get("monster_flat_meshes", []), cfg.get("monster_flat_texture"), cfg.get("monster_image"), cfg.get("monster_flat_rotation", Vector3.ZERO), cfg.get("monster_flat_surface_overrides", {}), monster_size_units, camera_size_units, false)
	var hitpoints: int = cfg.get("hitpoints", 0)
	var max_hitpoints: int = cfg.get("max_hitpoints", maxi(hitpoints, 1))
	_hp_label.text = str(hitpoints)
	var hp_fraction := clampf(float(hitpoints) / float(max_hitpoints), 0.0, 1.0) if max_hitpoints > 0 else 0.0
	_hp_fill.size.x = HP_BOX_SIZE.x * hp_fraction
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
	# Damage Type icons use the same bordered badge as Weakness/Resistance
	# (2026-09-29, "damage type can also use the shields" - carried over to
	# the shield-less badge below) but deliberately keep the plain gray
	# border colour ("damage type can stay as is color wise" - a weapon's
	# own damage types have no weakness/resistance concept of their own to
	# colour-code), hence no `inner_border_color` argument here.
	_clear(_damage_box)
	for kind in damage_types:
		_damage_box.add_child(_bordered_icon_box(kind, Vulnerability.display_name(kind)))

	var weaknesses: Array = cfg.get("weaknesses", [])
	var resistances: Array = cfg.get("resistances", [])
	var vulnerability_entry: Dictionary = _property_sections["vulnerability"]
	vulnerability_entry["section"].visible = not weaknesses.is_empty() or not resistances.is_empty()
	_clear(vulnerability_entry["box"])
	for kind in weaknesses:
		# Hidden ("?" icon) until discovered - which CATEGORY a monster has
		# is never secret, only which damage kind it's for.
		var shown_weakness: int = kind if known_weaknesses.has(kind) else -1
		var weakness_tooltip := "Weakness: %s" % (Vulnerability.display_name(shown_weakness) if shown_weakness >= 0 else "Unknown")
		vulnerability_entry["box"].add_child(_bordered_icon_box(shown_weakness, weakness_tooltip, WEAKNESS_BORDER_COLOR))
	for kind in resistances:
		var shown_resistance: int = kind if known_resistances.has(kind) else -1
		var resistance_tooltip := "Resistance: %s" % (Vulnerability.display_name(shown_resistance) if shown_resistance >= 0 else "Unknown")
		vulnerability_entry["box"].add_child(_bordered_icon_box(shown_resistance, resistance_tooltip, RESISTANCE_BORDER_COLOR))

	var immunity_entry: Dictionary = _property_sections["immunity"]
	var immunities: Array = cfg.get("immunities", [])
	immunity_entry["section"].visible = not immunities.is_empty()
	_clear(immunity_entry["box"])
	for kind in immunities:
		# Hidden ("?" icon) until discovered.
		immunity_entry["box"].add_child(_icon_box(kind if known_immunities.has(kind) else -1))
	if animate:
		_slide_in_combat()


func show_value(v: int) -> void:
	_value_label.text = str(v)


## Shared by both sides' configure() branch - real mesh(es) if given, else
## the flat-image mockup/fallback quad. See configure()'s own doc.
func _configure_preview(preview: CombatMeshPreview, flat_meshes: Array, flat_texture: Texture2D, fallback_image: Texture2D, rotation_correction: Vector3 = Vector3.ZERO, surface_overrides: Dictionary = {}, size_units: float = 1.0, camera_size_units: float = 1.0, write_depth: bool = true) -> void:
	if not flat_meshes.is_empty():
		var typed_paths: Array[String] = []
		for path in flat_meshes:
			typed_paths.append(str(path))
		preview.show_meshes(typed_paths, flat_texture, rotation_correction, surface_overrides, size_units, camera_size_units, write_depth)
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


## The HP stat badge, widened into the health bar itself (new 2026-09-29,
## replacing the separate bar this used to sit above it - "there is a box
## with the actual health in it, make that wider 2.5x and use that").
## Two ColorRects sit behind the heart+number: a black baseline (the
## "missing" portion of health) and a red overlay sized to
## hitpoints/max_hitpoints on top of it (the "current" portion) -
## configure() resizes the red one's width each attack. The original
## bordered-panel look is kept as a THIRD, topmost overlay with a fully
## transparent fill and just a border stroke ("the border can stay") -
## drawn last so its border renders over the fill beneath without hiding
## it. `_hp_label` is left-anchored within the box rather than centred,
## per the explicit "align that to the left" request.
##
## **Bug fix, same day** - the first version anchored everything with
## PRESET_FULL_RECT/PRESET_CENTER_LEFT tricks and, seen rendered, came out
## visibly wrong: the fill/empty split ran top-to-bottom instead of
## left-to-right, wasn't fully filled at full health, and the heart+number
## floated "somewhere halfway." Root cause: `box` is a plain (non-Container)
## `Control` sitting inside `stat_row`, an `HBoxContainer` - by default a
## Control's CROSS-axis size flag is `SIZE_FILL`, so `box` was silently
## stretched TALLER to match its sibling (the taller Defense badge), while
## `_hp_fill`'s hardcoded `size = HP_BOX_SIZE` only ever covered the
## intended 48px from the top, leaving the rest of the now-taller box as
## bare black underneath it - reading as a top/bottom split, not a
## left/right progress bar. Fixed two ways at once: `box.size_flags_vertical
## = SIZE_SHRINK_CENTER` stops the stretch outright (box is now reliably
## exactly `HP_BOX_SIZE`), and every child here now uses plain absolute
## `position`/`size` (default top-left anchors) instead of anchor-preset
## tricks - fully deterministic, no dependency on a preset call correctly
## reading a not-yet-settled combined minimum size.
func _build_hp_box(parent: Control) -> void:
	var box := Control.new()
	box.custom_minimum_size = HP_BOX_SIZE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(box)

	# The concave-arc ConcaveBorderBox treatment tried here 2026-10-01 ("can
	# we use the same style for the health bar and defense UI elements")
	# was reverted the same day ("revert the health and defense, that arced
	# thing is not good there") - back to plain ColorRects + a straight
	# PanelContainer border, same as before that round.
	var empty_bg := ColorRect.new()
	empty_bg.color = Color(0.03, 0.03, 0.03)
	empty_bg.position = Vector2.ZERO
	empty_bg.size = HP_BOX_SIZE
	empty_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(empty_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.75, 0.12, 0.1)
	_hp_fill.position = Vector2.ZERO
	_hp_fill.size = HP_BOX_SIZE  # width re-set in configure() to the hp fraction
	_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_hp_fill)

	var border := PanelContainer.new()
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = Color(0.75, 0.12, 0.1).lightened(0.35)
	border_style.set_border_width_all(3)
	border.add_theme_stylebox_override("panel", border_style)
	border.position = Vector2.ZERO
	border.size = HP_BOX_SIZE
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(border)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.position = Vector2(14, 0)
	row.size = Vector2(HP_BOX_SIZE.x - 14, HP_BOX_SIZE.y)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	var glyph := Label.new()
	glyph.text = "♥"
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	_hp_label = Label.new()
	_hp_label.add_theme_font_size_override("font_size", 34)
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_hp_label)


## The Defense stat badge (the ⛨ "shield" icon + number), pinned to the
## SAME height as the HP bar next to it (new 2026-09-29, "make the shield
## box the same size as the health bar vertically" - "shield" here turned
## out to mean this badge's own ⛨ glyph, not the Weakness/Resistance
## shield-BACKGROUND icons a few messages earlier mistakenly took the same
## wording to mean - "it also has a shield icon so that got us confused").
## Previously built via the generic `_stat_badge()`/`_panel()` helpers,
## which added a `content_margin_all(10)` PanelContainer margin on top of
## the label text - that margin, not the font size, was the actual reason
## the old badge came out taller (~60px) than `HP_BOX_SIZE.y` (48): a
## 34pt number's own natural line height easily fits inside 48px on its
## own (confirmed - that's exactly the font size `_build_hp_box()` already
## uses at this same 48px height), it just never had 20px of margin piled
## on top of it before. Built the same deterministic way as
## `_build_hp_box()` (absolute `position`/`size`, no `PanelContainer`
## content-margin overhead, `size_flags_vertical = SIZE_SHRINK_CENTER` so
## it can't stretch to match a taller sibling) so it reliably matches
## `HP_BOX_SIZE.y` exactly. `_stat_badge()` itself is deleted - HP moved
## off it earlier the same day, this was its only remaining caller.
func _build_defense_box(parent: Control) -> Label:
	var box_size := Vector2(DEFENSE_BOX_WIDTH, HP_BOX_SIZE.y)
	var color := Color(0.35, 0.4, 0.5)

	var box := Control.new()
	box.custom_minimum_size = box_size
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(box)

	# The concave-arc ConcaveBorderBox treatment tried here 2026-10-01 ("can
	# we use the same style for the health bar and defense UI elements")
	# was reverted the same day ("revert the health and defense, that arced
	# thing is not good there") - back to a plain ColorRect + a straight
	# PanelContainer border, same as before that round.
	var bg := ColorRect.new()
	bg.color = color
	bg.position = Vector2.ZERO
	bg.size = box_size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bg)

	var border := PanelContainer.new()
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0, 0, 0, 0)
	border_style.border_color = color.lightened(0.35)
	border_style.set_border_width_all(3)
	border.add_theme_stylebox_override("panel", border_style)
	border.position = Vector2.ZERO
	border.size = box_size
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(border)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(6, 0)
	row.size = Vector2(box_size.x - 12, box_size.y)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)

	var glyph := Label.new()
	glyph.text = "⛨"
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	var value_label := Label.new()
	value_label.add_theme_font_size_override("font_size", 34)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	return value_label


## 8 short Line2D ticks radiating outward from the centre of `parent`
## (expected to be `disc_wrap`, a 112x112 Control), one every 45 degrees -
## see TICK_* consts' own doc. Line2D is a Node2D, not a Control, but
## Godot allows mixing CanvasItem-derived nodes under a Control freely -
## its `position` is just a local-space point relative to the parent
## Control's own top-left corner, same coordinate space `position`/`size`
## already use elsewhere in this function.
func _build_disc_ticks(parent: Control) -> void:
	var center := Vector2(TICK_RADIUS, TICK_RADIUS)
	for i in TICK_COUNT:
		var angle_deg := i * 360.0 / TICK_COUNT
		var is_cardinal := int(angle_deg) % 90 == 0
		var length := TICK_LENGTH_LONG if is_cardinal else TICK_LENGTH_SHORT
		var direction := Vector2.RIGHT.rotated(deg_to_rad(angle_deg))
		var tick := Line2D.new()
		tick.points = PackedVector2Array([
			center + direction * (TICK_RADIUS + TICK_GAP),
			center + direction * (TICK_RADIUS + TICK_GAP + length),
		])
		tick.width = 2.0
		tick.default_color = ORANGE.darkened(0.1 if is_cardinal else 0.3)
		parent.add_child(tick)


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
	_ui_layer.add_child(v)
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


## A small damage-type icon framed by a double gray border (new 2026-10-01,
## "remove the shields, but a double gray border around the icons" -
## replaces the earlier shield-background badge entirely, see
## `tools/asset_import/generate_shield_icons.py`'s own doc comment for that
## shield art's history). Used by both the Damage Type row and the combined
## Weakness/Resistance list, so the two bottom corners stay visually
## identical. Same concentric-ring idea as the successes picker's own
## double ring (`disc_wrap`/`outer_ring`), just rectangular and per-icon:
## an outer bordered box (always the neutral `ICON_BORDER_COLOR`, filled
## black so the border reads clearly against the art behind it - "make
## sure the color between the borders is also black so it is visible"), a
## smaller bordered box inset inside it (also the icon's own dark backdrop,
## black fill too so the two rings blend into one solid black field with
## just their two border lines visible), and the icon centred on top of
## both. `inner_border_color` (new, same round - "make weak inner border
## dark red, resistance dark blue") lets the INNER ring alone carry the
## weakness-vs-resistance distinction that used to live in the shield
## art - `WEAKNESS_BORDER_COLOR`/`RESISTANCE_BORDER_COLOR` for those two
## callers. Damage Type explicitly keeps the plain default
## `ICON_BORDER_COLOR` gray ("damage type can stay as is color wise") -
## it has no weakness/resistance concept of its own, so there's nothing
## for a second colour to distinguish there; it still gets the same
## square sizing and black-between-borders treatment as everything else,
## only the colour was asked to stay put. (Immunity has its own
## `_icon_box()` and never reaches here.) **All badges render as an equal
## SQUARE now** (new, same round -
## "can we make all equal size (square)") - `icon`'s own box is a fixed
## `h x h` square regardless of a given damage icon's real aspect ratio,
## with `STRETCH_KEEP_ASPECT_CENTERED` still letterboxing the actual
## artwork inside it undistorted - so every ring size this function builds
## is identical across every icon, not just same-height-different-width
## like the very first bordered pass.
## `kind < 0` (not yet discovered) still shows the "?" icon - which
## CATEGORY a monster has is never secret, only which damage type (same
## rule `_icon_box()`'s own "?" already follows) - irrelevant for the
## Damage Type row, which never passes `kind < 0` (a weapon's own damage
## types are never secret).
##
## Both rings are `ConcaveBorderBox` now (new 2026-10-01, "make it arcs
## pointing inward so that their tips come together on the corners making
## sharp pointy corner") rather than a plain `StyleBoxFlat` rounded rect -
## see that script's own doc for the actual arc geometry. A first pass at
## this shape, asked for as one ("try something first we correct it") -
## not yet seen rendered.
func _bordered_icon_box(kind: int, tooltip: String, inner_border_color: Color = ICON_BORDER_COLOR) -> Control:
	var h := PROPERTY_ICON_HEIGHT
	var icon_texture := Vulnerability.icon(kind)
	var icon_size := Vector2(h, h)
	var inner_size := icon_size + ICON_BORDER_PADDING
	var outer_size := inner_size + Vector2(ICON_BORDER_GAP, ICON_BORDER_GAP) * 2.0

	var badge := Control.new()
	badge.custom_minimum_size = outer_size
	badge.tooltip_text = tooltip

	# Both rings are ConcaveBorderBox now (new 2026-10-01, "make it arcs
	# pointing inward so that their tips come together on the corners
	# making sharp pointy corner") instead of a plain StyleBoxFlat rounded
	# rect - see that script's own doc for the shape itself. Only the
	# SHAPE changed here; the fill/border colour scheme from the previous
	# round (always-gray outer, colour-coded inner) is untouched.
	var outer_ring := ConcaveBorderBox.new()
	outer_ring.fill_color = Color(0, 0, 0, 0.9)
	outer_ring.border_color = ICON_BORDER_COLOR
	outer_ring.custom_minimum_size = outer_size
	outer_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(outer_ring)

	# The inner ring doubles as the icon's own dark backdrop (the
	# contrast fix from the previous round) - one box, not a separate
	# backing plate plus a separate border. Its own border colour is the
	# only thing that distinguishes a weakness entry from a resistance one
	# now that the shield art is gone.
	var inner_ring := ConcaveBorderBox.new()
	inner_ring.fill_color = Color(0, 0, 0, 0.9)
	inner_ring.border_color = inner_border_color
	inner_ring.custom_minimum_size = inner_size
	inner_ring.set_anchors_preset(Control.PRESET_CENTER)
	inner_ring.grow_horizontal = Control.GROW_DIRECTION_BOTH
	inner_ring.grow_vertical = Control.GROW_DIRECTION_BOTH
	inner_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(inner_ring)

	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = icon_size
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	icon.grow_vertical = Control.GROW_DIRECTION_BOTH
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(icon)

	return badge


func _clear(box: Control) -> void:
	for c in box.get_children():
		c.free()
