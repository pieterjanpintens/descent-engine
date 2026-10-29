class_name LogText
extends RefCounted

## Text for the quest log / campaign log that survives a change of language.
## A log entry is written ONCE but stored for EVERY language the content has: of() runs a builder (a Callable that returns
## the text) once per language, each time with the app's own texts (tr()) and the content's texts (LText) switched to that language,
## and keeps the results as a language map {code: text} - the same shape the authored texts have. The log dialog then shows the
## entry in the language the game is read in now (LText.pick), so a log never mixes languages and switching language later shows
## the whole log in the new one. The builder must only FORMAT (read state, call tr(), pick texts): it runs several times.
## A plain String put in an entry (older saves, or a call site that was not converted) is shown as it is.

## The languages entries are recorded in: set by the player of a campaign / mission to the content's languages.
static var languages: Array[String] = []


## Sets the languages of the content being played (the language it is read in first); an empty list records only the current one.
static func set_languages(list: Array, reading: String = "") -> void:
	var cleaned: Array[String] = []
	for code in list:
		var text := str(code)
		if text != "" and not cleaned.has(text):
			cleaned.append(text)
	if reading != "" and not cleaned.has(reading):
		cleaned.append(reading)
	languages = cleaned


static func reset() -> void:
	languages = []


## The app's own texts exist for some languages only; any other language gets the English ones.
static func ui_locale_for(code: String) -> String:
	return code if PlayerSettings.UI_LANGUAGES.has(code) else "en"


static func _recording_languages() -> Array[String]:
	var current: Array[String] = LText.reading_order()
	var first: String = current[0] if not current.is_empty() else LText.LEGACY_LANGUAGE
	var list: Array[String] = [first]
	for code in languages:
		if not list.has(code):
			list.append(code)
	return list


## Runs `builder` once per recording language and returns {code: text}.
static func of(builder: Callable) -> Dictionary:
	var map := {}
	var saved_locale := TranslationServer.get_locale()
	var saved_order: Array[String] = LText.preferred.duplicate()
	for code in _recording_languages():
		var locale := ui_locale_for(code)
		if TranslationServer.get_locale() != locale:
			TranslationServer.set_locale(locale)
		LText.preferred = [code]
		map[code] = str(builder.call())
	LText.preferred = saved_order
	if TranslationServer.get_locale() != saved_locale:
		TranslationServer.set_locale(saved_locale)
	return map


## A title that is a msgid of the app's own texts ("Loot", "Monster attack"): translated per language like any builder.
static func of_msgid(msgid: String) -> Dictionary:
	return of(func() -> String: return TranslationServer.translate(msgid))


## What an entry's value (a map, or a plain String from before) reads in the language the game is read in now.
static func show(value: Variant) -> String:
	if value is Dictionary:
		return LText.pick(value)
	return str(value)


## Normalises what a caller hands in: a Callable is built per language, a map is kept, a String stays a plain String.
static func record(value: Variant) -> Variant:
	if value is Callable:
		return of(value)
	if value is Dictionary:
		return value
	return str(value)


## record() for a title given as a plain String: it is a msgid, so it is translated per language too.
static func record_title(value: Variant) -> Variant:
	if value is String:
		return of_msgid(value) if value != "" else ""
	return record(value)
