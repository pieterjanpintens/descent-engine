class_name GameIcons
extends RefCounted

## The game's own rules icons (success, surge, damage, fatigue, actions, health dial, advantage). In the game's texts
## they are private-use glyphs of its "D3 Calibri" font, wrapped in a glossary link (`<link=TERM_FATIGUE>`).
## The asset import copies that font to FONT_PATH (never shipped); `install()` hangs it behind the default font, so
## every Label, button and tooltip draws the glyphs. Without the font the cleaned texts say "[fatigue]" instead.
## Authored texts can use the same names: "Heal 2 [health dial]", "Recover [actions]" - `apply()` turns the tag into the
## icon when the font is there and leaves the word otherwise; `spoken()` gives the narrator a word instead.

const FONT_PATH := "user://official_assets/game_icons.ttf"

## The glyphs are drawn small in the game's font next to normal text; this enlarges them.
const SCALE := 1.3
const DROP := 0.0  # vertical shift of the icons (tried +-0.1: no visible difference at text sizes)
const SPACING := 3  # extra pixels after each icon

## Tag name (as the cleaned game texts write it, any case) -> glyph of the icon font.
const ICONS := {
	"success": 0xF5E8,
	"surge": 0xF5E1,
	"damage": 0xF5E5,
	"fatigue": 0xF5E3,
	"actions": 0xF5E4,
	"health dial": 0xF5D0,
	"advantage": 0xF5DE,
}

## What the narrator says for an icon (an app text, translated into the language read aloud).
const SPOKEN := {
	"success": "success",
	"surge": "surge",
	"damage": "damage",
	"fatigue": "fatigue",
	"actions": "actions",
	"health dial": "health",
	"advantage": "advantage",
}

static var _font: Font = null
static var _tag_regex: RegEx = null
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


## `text` with every icon tag ("[fatigue]", "[Health Dial]") replaced by its icon - unchanged without the font.
static func apply(text: String) -> String:
	if not text.contains("[") or not available():
		return text
	return _replace_tags(text, func(tag: String) -> String: return String.chr(ICONS[tag]))


## `text` as the narrator should read it: icon tags and icon glyphs become words in the language `locale` ("" = the
## app's current language).
static func spoken(text: String, locale: String = "") -> String:
	var result := _replace_tags(text, func(tag: String) -> String: return _word(tag, locale)) if text.contains("[") else text
	for tag: String in ICONS:
		var glyph := String.chr(ICONS[tag])
		if result.contains(glyph):
			result = result.replace(glyph, " " + _word(tag, locale) + " ")
	return result


static func _word(tag: String, locale: String) -> String:
	var word: String = SPOKEN[tag]
	if locale == "":
		return TranslationServer.translate(word)
	var translation := TranslationServer.get_translation_object(locale)
	if translation == null:
		return word
	var translated := String(translation.get_message(word))
	return translated if translated != "" else word


static func _replace_tags(text: String, replacement: Callable) -> String:
	if _tag_regex == null:
		_tag_regex = RegEx.create_from_string("\\[([A-Za-z ]+)\\]")
	var result := ""
	var last := 0
	for found in _tag_regex.search_all(text):
		var tag := found.get_string(1).strip_edges().to_lower()
		if not ICONS.has(tag):
			continue
		result += text.substr(last, found.get_start() - last) + str(replacement.call(tag))
		last = found.get_end()
	return result + text.substr(last)
