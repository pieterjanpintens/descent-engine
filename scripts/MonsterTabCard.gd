class_name MonsterTabCard
extends Control

## One monster on the side of the Player's map view, built from the game's own "EnemyTab" pieces (placeholders in models/ui/enemytab_*.png, the
## real art through OfficialAssetOverrides): a stone background, the monster's picture (its "<Monster>_Tab"), the frame, the colour chip as a bar on
## the left edge, a health bar along the bottom and the level in a round badge. A monster type + chip colour is unique on the board, so the
## picture and the colour tell the table exactly which figure it is. Nothing here takes the mouse.

const CARD_SIZE := Vector2(156, 81)  ## the frame's proportions (512 x 265)
const BG_PATH := "res://models/ui/enemytab_bg.png"
const FRAME_PATH := "res://models/ui/enemytab_frame.png"
const CHIP_PATH := "res://models/ui/enemytab_chip.png"
const LEVEL_PATH := "res://models/ui/enemytab_level.png"
const HEALTH_PATH := "res://models/ui/enemytab_healthbar.png"
const UNIQUE_FRAME_PATH := "res://models/ui/enemytab_frameunique.png"  ## the ornate frame (562 x 265) of a monster about to do its special tactic
const UNIQUE_SCALE := 562.0 / 512.0  ## it is wider than the plain frame by this much

const BAR_INSET := 13.0
const BAR_HEIGHT := 7.0
const BADGE_SIZE := 30.0

var monster_id: String = ""

var _portrait: TextureRect
var _chip: TextureRect
var _bar_fill: Control
var _level_label: Label
var _bar_width := 0.0
var _highlight: Panel
var _tactic_frame: TextureRect
var _tactic_glow: Panel
var _pulse: Tween


func _init() -> void:
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = CARD_SIZE / 2.0
	_build()


func _picture(path: String, tint: Color = Color.WHITE) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = OfficialAssetOverrides.texture_for(path)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.modulate = tint
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _place(rect: Control, at: Vector2, extent: Vector2) -> void:
	rect.position = at
	rect.size = extent


func _build() -> void:
	var background := _picture(BG_PATH, Color(0.5, 0.46, 0.44))
	_place(background, Vector2.ZERO, CARD_SIZE)
	add_child(background)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_portrait, Vector2(7, 6), CARD_SIZE - Vector2(14, 14))
	_portrait.clip_contents = true
	add_child(_portrait)
	var frame := _picture(FRAME_PATH, Color(0.84, 0.8, 0.76))
	_place(frame, Vector2.ZERO, CARD_SIZE)
	add_child(frame)
	# a monster that has a tactic prepared (it will do something special in the next monster phase) gets the ornate frame and a pulsing red glow
	_tactic_glow = Panel.new()
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(0.9, 0.1, 0.1, 0.0)
	glow.border_color = Color(0.95, 0.2, 0.15)
	glow.set_border_width_all(3)
	glow.set_corner_radius_all(5)
	glow.shadow_color = Color(0.95, 0.15, 0.1, 0.65)
	glow.shadow_size = 9
	_tactic_glow.add_theme_stylebox_override("panel", glow)
	_tactic_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tactic_glow.visible = false
	_place(_tactic_glow, Vector2(-1, -1), CARD_SIZE + Vector2(2, 2))
	add_child(_tactic_glow)
	_tactic_frame = _picture(UNIQUE_FRAME_PATH, Color(1.0, 0.82, 0.7))
	var wide := CARD_SIZE.x * UNIQUE_SCALE
	_place(_tactic_frame, Vector2(-(wide - CARD_SIZE.x) / 2.0, 0.0), Vector2(wide, CARD_SIZE.y))
	_tactic_frame.visible = false
	add_child(_tactic_frame)
	# the health bar: a dark trough with the red bar clipped to the fraction left
	_bar_width = CARD_SIZE.x - BAR_INSET * 2.0
	var trough := _picture(HEALTH_PATH, Color(0.2, 0.2, 0.22, 0.9))
	_place(trough, Vector2(BAR_INSET, CARD_SIZE.y - BAR_HEIGHT - 8.0), Vector2(_bar_width, BAR_HEIGHT))
	add_child(trough)
	_bar_fill = Control.new()
	_bar_fill.clip_contents = true
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_bar_fill, trough.position, trough.size)
	var fill := _picture(HEALTH_PATH)
	_place(fill, Vector2.ZERO, trough.size)
	_bar_fill.add_child(fill)
	add_child(_bar_fill)
	# the chip colour bar sticks out over the left edge, like the game's tab
	_chip = _picture(CHIP_PATH)
	_place(_chip, Vector2(-5, 9), Vector2(13, CARD_SIZE.y - 24.0))
	add_child(_chip)
	# the level in a round badge at the bottom right
	var badge := _picture(LEVEL_PATH)
	_place(badge, Vector2(CARD_SIZE.x - BADGE_SIZE + 5.0, CARD_SIZE.y - BADGE_SIZE + 5.0), Vector2(BADGE_SIZE, BADGE_SIZE))
	add_child(badge)
	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_color_override("font_color", Color.WHITE)
	_level_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_level_label.add_theme_constant_override("outline_size", 3)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_level_label, badge.position, badge.size)
	add_child(_level_label)
	# a gold outline while a dragged hero is over the card (the attack target)
	_highlight = Panel.new()
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(1.0, 0.85, 0.3, 0.12)
	outline.border_color = Color(1.0, 0.85, 0.3)
	outline.set_border_width_all(3)
	outline.set_corner_radius_all(4)
	_highlight.add_theme_stylebox_override("panel", outline)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	_place(_highlight, Vector2(-2, -2), CARD_SIZE + Vector2(4, 4))
	add_child(_highlight)


## The tactic highlight: the ornate frame plus a slow red pulse; off when the tactic is used.
func _show_tactic(on: bool) -> void:
	if _tactic_frame.visible == on:
		return
	_tactic_frame.visible = on
	_tactic_glow.visible = on
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	_tactic_glow.modulate = Color.WHITE
	if on and is_inside_tree():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_tactic_glow, "modulate:a", 0.25, 0.8).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_tactic_glow, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func set_highlighted(on: bool) -> void:
	_highlight.visible = on


## Is this screen position on the card (its own scale and position taken into account)?
func contains_screen_point(screen_pos: Vector2) -> bool:
	var local := get_global_transform().affine_inverse() * screen_pos
	return Rect2(Vector2.ZERO, size).has_point(local)


## Shows `monster`: its picture, chip colour, health and level (cheap - the sidebar calls it on every change of the monsters).
func show_monster(monster: RuntimeMonster) -> void:
	monster_id = monster.id
	_portrait.texture = MonsterDisplay.crop_texture(monster.folder)
	_portrait.modulate = Color(0.72, 0.72, 0.78) if monster.unaware else Color.WHITE  # a surprised (asleep) monster looks dimmer
	_chip.modulate = MonsterChip.color(monster.chip)
	var fraction := clampf(float(monster.hitpoints) / float(maxi(monster.max_hitpoints, 1)), 0.0, 1.0)
	_bar_fill.size.x = _bar_width * fraction
	_level_label.text = str(monster.level)
	_show_tactic(monster.prepared_tactic >= 0)
	tooltip_text = "%s - %s" % [monster.display_name(), MonsterChip.display_name(monster.chip)]
