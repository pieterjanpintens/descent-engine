class_name LText
extends RefCounted

## Text that exists in several languages: a Dictionary {language code -> text}. Every authored text field (a chapter's title, a story page, an objective...)
## keeps its old name and type for READING - `chapter.title` is a String - but is stored as the map `chapter.title_texts`:
##
##     @export var title_texts: Dictionary = {"en": "New chapter"}
##     var title: String:
##         get: return LText.pick(title_texts)
##         set(value): LText.put(title_texts, value)
##
## Reading takes the first language of `reading_order()` that has a text; writing goes to `write_language()`. Both are plain static state, set by whoever
## knows the situation: the app (the player's preferred languages), the campaign player (the language chosen for the save game), the editors
## (the language being edited). The setter is also what loads the plain strings of files written before this existed: while `loading` is true
## they are filed under LEGACY_LANGUAGE, so old campaigns, missions and packages open unchanged and become maps the next time they are saved.

const LEGACY_LANGUAGE := "en"

## The languages to read in, best first (the player's preferred languages; for a campaign game the language of the save game comes first).
static var preferred: Array[String] = []
## The player's own list from Options (what `preferred` goes back to).
static var player_order: Array[String] = []
## The default language of the campaign / mission being played or edited: what is read when none of `preferred` has a text.
static var fallback_language: String = "en"
## The language writes go to ("" = fallback_language). Editors set it while another language is being edited.
static var edit_language: String = ""
## True while an old file is being loaded (see above).
static var loading: bool = false


## The languages in the order a text is looked for: preferred, then the content's default, then English, then whatever exists (see pick()).
static func reading_order() -> Array[String]:
	var order: Array[String] = []
	for code in preferred:
		if not order.has(code):
			order.append(code)
	for code in [fallback_language, LEGACY_LANGUAGE]:
		if code != "" and not order.has(code):
			order.append(code)
	return order


static func write_language() -> String:
	if loading:
		return LEGACY_LANGUAGE
	return edit_language if edit_language != "" else fallback_language


## The text to show: the first non-empty one in reading order, else any text at all, else "".
static func pick(map: Dictionary) -> String:
	for code in reading_order():
		var text := str(map.get(code, ""))
		if text != "":
			return text
	for code in map:
		var text := str(map[code])
		if text != "":
			return text
	return ""


## The text in exactly this language ("" when there is none) - for editors, which must not show a fallback as if it were the translation.
static func exact(map: Dictionary, language: String) -> String:
	return str(map.get(language, ""))


## Stores `text` in the write language; an empty text removes it (the language then counts as missing).
## Writing back exactly what is shown for a language that has no text of its own (an editor box that shows the default language's text as a
## starting point and writes it back untouched) changes nothing: that would only copy the fallback in as a fake translation.
static func put(map: Dictionary, text: String) -> void:
	var language := write_language()
	if not loading and text != "" and str(map.get(language, "")) == "" and text == pick(map):
		return
	put_in(map, language, text)


static func put_in(map: Dictionary, language: String, text: String) -> void:
	if text == "":
		map.erase(language)
	else:
		map[language] = text


## The language codes that have a (non-empty) text, in the order of CampaignInfo.LANGUAGES.
static func languages_in(map: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for language in CampaignInfo.LANGUAGES:
		if str(map.get(language["code"], "")) != "":
			found.append(language["code"])
	return found


## Sets the reading order from a list of codes (unknown entries dropped, repeats removed).
static func set_preferred(list: Array) -> void:
	player_order = clean_codes(list)
	preferred = player_order.duplicate()


## An editor starts editing `language`: it is read first and written to (the player's own languages and the content's default still back it up).
static func use_for_editing(language: String, content_default: String) -> void:
	fallback_language = content_default
	edit_language = language
	var order: Array[String] = [language]
	for code in player_order:
		if not order.has(code):
			order.append(code)
	preferred = order


## Back to plain reading: the player's own order, nothing being edited.
static func reset_editing() -> void:
	edit_language = ""
	preferred = player_order.duplicate()


## Only known codes, each once, keeping the given order (CampaignInfo.clean_languages sorts them instead).
static func clean_codes(list: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(list) != TYPE_ARRAY and typeof(list) != TYPE_PACKED_STRING_ARRAY:
		return result
	for item: Variant in list:
		var code := str(item).to_lower().strip_edges()
		if CampaignInfo.is_known(code) and not result.has(code):
			result.append(code)
	return result


## Loads a resource file that may be in the old (plain string) format - a campaign, a mission, a save game, a template.
static func load_file(path: String, type_hint: String = "") -> Resource:
	var before := loading
	loading = true
	var loaded := ResourceLoader.load(path, type_hint, ResourceLoader.CACHE_MODE_IGNORE)
	loading = before
	return loaded
