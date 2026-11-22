class_name GameIcons
extends RefCounted

## The game's own rules icons (success, surge, damage, fatigue, actions, health dial, advantage). In the game's texts
## they are private-use glyphs of its "D3 Calibri" font, wrapped in a glossary link (`<link=TERM_FATIGUE>`).
## The asset import copies that font to FONT_PATH (never shipped); `install()` hangs it behind the default font, so
## every Label, button and tooltip draws the glyphs. Without the font the cleaned texts say "[fatigue]" instead.

const FONT_PATH := "user://official_assets/game_icons.ttf"

## The glyphs are drawn small in the game's font next to normal text; this enlarges them.
const SCALE := 1.3
const DROP := 0.0  # vertical shift of the icons (tried +-0.1: no visible difference at text sizes)
const SPACING := 3  # extra pixels after each icon

static var _font: Font = null
static var _checked := false
static var _installed := false


## True when the imported icon font is there.
static func available() -> bool:
	return font() != null


static func font() -> Font:
	if _checked:
		return _font
	_checked = true
	if not FileAccess.file_exists(FONT_PATH):
		return null
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.is_empty():
		return null
	var loaded := FontFile.new()
	loaded.data = bytes
	if not loaded.has_char(0xF5E3):  # the fatigue glyph: not the game's icon font
		return null
	var sized := FontVariation.new()
	sized.base_font = loaded
	# bigger, a little lower (the scale grows the glyph up from the baseline) and with room after it (the scale does not
	# widen the advance)
	sized.variation_transform = Transform2D(0.0, Vector2(SCALE, SCALE), 0.0, Vector2(0.0, DROP))
	sized.spacing_glyph = SPACING
	_font = sized
	return _font


## Puts the icon font behind the engine's default font, which every font of the app falls back to.
static func install() -> void:
	if _installed or font() == null:
		return
	_installed = true
	var base := ThemeDB.fallback_font
	var fallbacks: Array[Font] = base.fallbacks.duplicate()
	fallbacks.append(_font)
	base.fallbacks = fallbacks
