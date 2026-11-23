class_name MonsterNameplate
extends Control

## The plate under a monster in the monster (M) view, rebuilt from the original game's own pieces: the level in a round badge
## and the name above a health bar, the hitpoints in a heart at its left end, the defense in a shield at its right end, a
## diamond per weakness / resistance / immunity below it ("?" until an attack has discovered it), and a line for its state
## (unaware, conditions). Drawn in 2D into a small SubViewport that a Sprite3D shows lying in front of the figure (`create()`).
## The art goes through the official-asset overrides: dummy placeholders ship, the game's pieces come with the asset import.

const SIZE := Vector2i(640, 280)

const BADGE := "res://models/ui/nameplate_badge.png"         ## official: EnemyLVLBadge_White
const BAR_BG := "res://models/ui/nameplate_bar_bg.png"       ## HealthBarBKG
const BAR_FILL := "res://models/ui/nameplate_bar_fill.png"   ## HealthBarHealthLVL
const BAR_FRAME := "res://models/ui/nameplate_bar_frame.png" ## HealthBarFrameColorShift
const HEART := "res://models/ui/nameplate_heart.png"         ## Icon_Health
const SHIELD := "res://models/ui/nameplate_shield.png"       ## Icon_Defense
const DIAMOND := "res://models/ui/nameplate_weakness.png"    ## Icon_Weakness

## Layout in plate pixels. Tune after a look.
const BADGE_RECT := Rect2(62, 2, 72, 72)
const NAME_POS := Vector2(142, 54)
const NAME_SIZE := 40
const BAR_RECT := Rect2(96, 92, 452, 64)
const HEART_RECT := Rect2(50, 72, 108, 108)
const SHIELD_RECT := Rect2(494, 76, 92, 100)
const NUMBER_SIZE := 40
const DIAMOND_SIZE := 66.0
const DIAMOND_TOP := 176.0
## How far the icon inside a diamond stays from its edge (fraction of the diamond per side): the damage icons and the "?" are
## diamonds themselves, so they need this margin to fit inside the frame.
const ICON_INSET := 0.3
const STATUS_TOP := 262.0
const STATUS_SIZE := 24

const WEAKNESS_COLOR := Color(1.0, 0.82, 0.35)   ## frame tint of a discovered weakness (the combat view's gold)
const RESISTANCE_COLOR := Color(0.95, 0.35, 0.3)
const IMMUNITY_COLOR := Color(0.78, 0.5, 0.98)

## World units per plate pixel when shown in 3D (640 px -> 1.66 units, about one and a half bases wide).
const PIXEL_SIZE := 0.0026

static var _textures := {}
static var _font: Font = null

var _info := {}


## A Node3D holding the plate's SubViewport and the Sprite3D that shows it. `info` keys: name, level, hitpoints, max_hitpoints,
## defense, weaknesses / resistances / immunities (Vulnerability kinds), known_weaknesses / known_resistances / known_immunities,
## status (a line of text, may be empty). `facing_pitch` tilts it towards a fixed camera; billboard = true turns it to any camera.
static func create(info: Dictionary, facing_pitch: float, billboard: bool = false) -> Node3D:
	var holder := Node3D.new()
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var plate := MonsterNameplate.new()
	plate.size = Vector2(SIZE)
	plate.set_info(info)
	viewport.add_child(plate)
	holder.add_child(viewport)
	var sprite := Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.pixel_size = PIXEL_SIZE
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	sprite.double_sided = true
	if billboard:
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		sprite.rotation.x = facing_pitch
		sprite.add_to_group(MonsterDisplay.FACING_GROUP)
	holder.add_child(sprite)
	return holder


func set_info(info: Dictionary) -> void:
	_info = info
	queue_redraw()


func _draw() -> void:
	if _font == null:
		_font = MenuStyle.font()  # kept: a font made in _draw() and dropped is freed before it is drawn
	var font := _font
	var outline := Color(0, 0, 0, 0.95)
	# the level badge and the name
	draw_texture_rect(_tex(BADGE), BADGE_RECT, false)
	_centered(font, str(_info.get("level", 1)), BADGE_RECT.get_center(), NUMBER_SIZE - 6, Color.WHITE, outline)
	draw_string_outline(font, NAME_POS, str(_info.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - NAME_POS.x - 8, NAME_SIZE, 8, outline)
	draw_string(font, NAME_POS, str(_info.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - NAME_POS.x - 8, NAME_SIZE, Color.WHITE)
	# the health bar: background, the red part cut at the fraction left, the frame
	var hitpoints := int(_info.get("hitpoints", 0))
	var max_hitpoints := maxi(int(_info.get("max_hitpoints", 1)), 1)
	var fraction := clampf(float(hitpoints) / float(max_hitpoints), 0.0, 1.0)
	draw_texture_rect(_tex(BAR_BG), BAR_RECT, false)
	var fill := _tex(BAR_FILL)
	if fraction > 0.0:
		var source := Rect2(Vector2.ZERO, Vector2(fill.get_width() * fraction, fill.get_height()))
		draw_texture_rect_region(fill, Rect2(BAR_RECT.position, Vector2(BAR_RECT.size.x * fraction, BAR_RECT.size.y)), source)
	draw_texture_rect(_tex(BAR_FRAME), BAR_RECT, false)
	# the heart with the hitpoints, the shield with the defense
	draw_texture_rect(_tex(HEART), HEART_RECT, false)
	_centered(font, str(hitpoints), HEART_RECT.get_center() + Vector2(0, -4), NUMBER_SIZE, Color.WHITE, outline)
	draw_texture_rect(_tex(SHIELD), SHIELD_RECT, false)
	_centered(font, str(int(_info.get("defense", 0))), SHIELD_RECT.get_center() + Vector2(0, -4), NUMBER_SIZE, Color.WHITE, outline)
	# a diamond per weakness / resistance / immunity
	var entries := _property_entries()
	var gap := 6.0
	var total := entries.size() * DIAMOND_SIZE + maxf(entries.size() - 1, 0) * gap
	var x := BAR_RECT.get_center().x - total * 0.5
	for entry: Dictionary in entries:
		var rect := Rect2(x, DIAMOND_TOP, DIAMOND_SIZE, DIAMOND_SIZE)
		draw_texture_rect(_tex(DIAMOND), rect, false, entry["tint"])
		var icon := _icon(entry["kind"])
		if icon != null:
			draw_texture_rect(icon, rect.grow(-DIAMOND_SIZE * ICON_INSET), false)
		x += DIAMOND_SIZE + gap
	# what state it is in
	var status := str(_info.get("status", ""))
	if status != "":
		var y := STATUS_TOP if not entries.is_empty() else DIAMOND_TOP + STATUS_SIZE
		draw_string_outline(font, Vector2(0, y), status, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, STATUS_SIZE, 6, outline)
		draw_string(font, Vector2(0, y), status, HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, STATUS_SIZE, Color(1.0, 0.85, 0.55))


## [{kind (-1 = not discovered yet), tint}] in the order weaknesses, resistances, immunities - one per entry, like the combat view.
func _property_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for group in [["weaknesses", "known_weaknesses", WEAKNESS_COLOR], ["resistances", "known_resistances", RESISTANCE_COLOR],
			["immunities", "known_immunities", IMMUNITY_COLOR]]:
		var known: Array = _info.get(group[1], [])
		for kind in _info.get(group[0], []):
			var discovered: bool = known.has(kind)
			entries.append({"kind": int(kind) if discovered else -1, "tint": group[2] if discovered else Color.WHITE})
	return entries


func _centered(font: Font, text: String, centre: Vector2, font_size: int, color: Color, outline: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var pos := Vector2(centre.x - width * 0.5, centre.y + (ascent - descent) * 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, outline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Draw textures are kept in a static cache: a texture loaded inside _draw() and not kept is freed before the renderer draws it.
static func _tex(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = OfficialAssetOverrides.texture_for(path)
	return _textures[path]


static func _icon(kind: int) -> Texture2D:
	var key := "kind_%d" % kind
	if not _textures.has(key):
		_textures[key] = Vulnerability.icon(kind)
	return _textures[key]
