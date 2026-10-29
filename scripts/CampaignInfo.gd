class_name CampaignInfo
extends RefCounted

## The two facts about a campaign or mission that the library cards and the community catalog show: the languages it is written in and about how
## long it takes to play. Stored on the campaign, copied into the package manifest (`languages`, `duration_minutes`) and the catalog entry.

## Language code -> name. The flags in the menus exist for the first three (the designer's mockup); other languages are shown as their code.
const LANGUAGES: Array[Dictionary] = [
	{"code": "en", "name": "English", "native": "English"},
	{"code": "es", "name": "Spanish", "native": "Español"},
	{"code": "fr", "name": "French", "native": "Français"},
	{"code": "de", "name": "German", "native": "Deutsch"},
	{"code": "nl", "name": "Dutch", "native": "Nederlands"},
	{"code": "it", "name": "Italian", "native": "Italiano"},
	{"code": "pt", "name": "Portuguese", "native": "Português"},
	{"code": "pl", "name": "Polish", "native": "Polski"},
]
const MAX_LANGUAGES := 8
const MAX_MINUTES := 6000


## Only known codes, each once, in the order of LANGUAGES (so a card always lists them the same way).
static func clean_languages(raw: Variant) -> Array[String]:
	var wanted: Array[String] = []
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_STRING_ARRAY:
		for item: Variant in raw:
			wanted.append(str(item).to_lower().strip_edges())
	var result: Array[String] = []
	for language in LANGUAGES:
		if wanted.has(language["code"]) and result.size() < MAX_LANGUAGES:
			result.append(language["code"])
	return result


static func clean_minutes(raw: Variant) -> int:
	return clampi(int(raw), 0, MAX_MINUTES)


## "45 min", "2 h", "2 h 10 min"; empty when unknown (0).
static func duration_text(minutes: int) -> String:
	if minutes <= 0:
		return ""
	var hours := minutes / 60
	var rest := minutes % 60
	if hours == 0:
		return TranslationServer.translate("%d min") % rest
	if rest == 0:
		return "%d h" % hours
	return TranslationServer.translate("%d h %d min") % [hours, rest]


static func is_known(code: String) -> bool:
	for language in LANGUAGES:
		if language["code"] == code:
			return true
	return false


static func language_name(code: String) -> String:
	for language in LANGUAGES:
		if language["code"] == code:
			return language["name"]
	return code.to_upper()


## The language's own name ("Español"): what a player recognises in a list, whatever language the app is shown in.
static func native_name(code: String) -> String:
	for language in LANGUAGES:
		if language["code"] == code:
			return language["native"]
	return code.to_upper()


## A row of check boxes, one per language; `languages` is edited in place and `on_change` is called after every click.
static func language_row(languages: Array[String], on_change: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	for language in LANGUAGES:
		var code: String = language["code"]
		var box := CheckBox.new()
		box.text = language["name"]
		box.button_pressed = languages.has(code)
		box.toggled.connect(func(pressed: bool):
			if pressed and not languages.has(code):
				languages.append(code)
			elif not pressed:
				languages.erase(code)
			var ordered := clean_languages(languages)
			languages.clear()
			languages.append_array(ordered)
			on_change.call()
		)
		row.add_child(box)
	return row
