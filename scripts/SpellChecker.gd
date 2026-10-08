class_name SpellChecker
extends RefCounted

## An offline English spell checker for the story text boxes. The word list (`data/words_en.txt`) is the Hunspell en_US
## dictionary (SCOWL size 60, see data/words_en.LICENSE.txt) expanded to plain words; the player's own additions live in
## `user://spelling/custom_words.txt`. Never instantiated.
##
## Rules of thumb (it is a helper, not a judge): a capitalised word in the middle of a sentence is assumed to be a name,
## ALL CAPS words are skipped, words touching digits are skipped, and the tag names in `[Name]...[/Name]` are skipped.
## Character names and the hero names are always fine (`names_set()`).

const WORD_FILE := "res://data/words_en.txt"
const CUSTOM_FILE := "user://spelling/custom_words.txt"
const LETTERS := "abcdefghijklmnopqrstuvwxyz"

static var _words: Dictionary = {}
static var _custom: Dictionary = {}
static var _loaded := false
static var _token: RegEx


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_token = RegEx.create_from_string("[A-Za-z]+(?:['’][A-Za-z]+)*")
	for word in FileAccess.get_file_as_string(WORD_FILE).split("\n", false):
		_words[word] = true
	if FileAccess.file_exists(CUSTOM_FILE):
		for word in FileAccess.get_file_as_string(CUSTOM_FILE).split("\n", false):
			_custom[word] = true


## The lower-case words that are always fine: every character's name and the heroes'.
static func names_set(characters: Array[NarratorCharacter]) -> Dictionary:
	var names := {}
	var all: Array[NarratorCharacter] = characters.duplicate()
	all.append_array(HeroCatalog.hero_characters())
	for character in all:
		for part in character.character_name.to_lower().split(" ", false):
			names[part] = true
	return names


## Teaches the checker a word (saved in the player's own list).
static func add_word(word: String) -> void:
	ensure_loaded()
	var lower := word.to_lower().replace("’", "'")
	if _custom.has(lower):
		return
	_custom[lower] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://spelling"))
	var file := FileAccess.open(CUSTOM_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_custom.keys()) + "\n")


static func _known(lower: String, names: Dictionary) -> bool:
	if _words.has(lower) or _custom.has(lower) or names.has(lower):
		return true
	var quote := lower.find("'")
	if quote > 0:  # guard's, guards' - the stem is what counts
		var stem := lower.substr(0, quote)
		return _words.has(stem) or _custom.has(stem) or names.has(stem)
	return false


## The [start, end) ranges of the misspelled words in `text` (one line).
static func misspelled_ranges(text: String, names: Dictionary = {}) -> Array[Vector2i]:
	ensure_loaded()
	var found: Array[Vector2i] = []
	for match in _token.search_all(text):
		var start := match.get_start()
		var end := match.get_end()
		var word := match.get_string().replace("’", "'")
		if word.length() < 2:
			continue
		if start > 0 and (text[start - 1] in "[/" or text[start - 1].is_valid_int()):
			continue  # a tag name, or glued to a number
		if end < text.length() and text[end].is_valid_int():
			continue
		if word == word.to_upper():
			continue  # NPC, HP...
		var lower := word.to_lower()
		if word[0] != lower[0] and not _starts_sentence(text, start):
			continue  # a name in the middle of a sentence
		if not _known(lower, names):
			found.append(Vector2i(start, end))
	return found


static func _starts_sentence(text: String, start: int) -> bool:
	var i := start - 1
	while i >= 0 and text[i] in " \t\"“‘'([":
		i -= 1
	return i < 0 or text[i] in ".!?:"


## The misspelled word at `column` of `text`: {"start", "end", "word"}, or {} when that word is fine / there is none.
static func misspelled_at(text: String, column: int, names: Dictionary = {}) -> Dictionary:
	for span in misspelled_ranges(text, names):
		if column >= span.x and column <= span.y:
			return {"start": span.x, "end": span.y, "word": text.substr(span.x, span.y - span.x)}
	return {}


## Likely corrections, best first (one or two edits away from a real word), in the word's own capitalisation.
static func suggestions(word: String, limit: int = 6) -> Array[String]:
	ensure_loaded()
	var lower := word.to_lower().replace("’", "'")
	var ranked: Array[String] = []
	var seen := {lower: true}
	var first_edits := _edits(lower)
	for candidate in first_edits:
		if not seen.has(candidate) and (_words.has(candidate) or _custom.has(candidate)):
			seen[candidate] = true
			ranked.append(candidate)
	_sort_by_likeness(ranked, lower)
	if ranked.size() < limit and lower.length() <= 12:
		var second: Array[String] = []
		for edited in first_edits:
			for candidate in _edits(edited):
				if not seen.has(candidate) and _words.has(candidate):
					seen[candidate] = true
					second.append(candidate)
		_sort_by_likeness(second, lower)
		ranked.append_array(second)
	var result: Array[String] = []
	var capital := word[0] != word[0].to_lower()
	for candidate in ranked.slice(0, limit):
		result.append(candidate.capitalize() if capital and not candidate.contains("'") else candidate)
	return result


## Same first letter, similar length and a shared ending come first.
static func _sort_by_likeness(list: Array[String], word: String) -> void:
	list.sort_custom(func(a: String, b: String) -> bool:
		return _likeness(a, word) > _likeness(b, word)
	)


static func _likeness(candidate: String, word: String) -> int:
	var score := 0
	if candidate[0] == word[0]:
		score += 4
	if candidate.length() == word.length():
		score += 2
	if candidate[candidate.length() - 1] == word[word.length() - 1]:
		score += 1
	return score


## Every string one edit away: deletions, transpositions, replacements, insertions.
static func _edits(word: String) -> Array[String]:
	var edits: Array[String] = []
	var n := word.length()
	for i in n:
		edits.append(word.substr(0, i) + word.substr(i + 1))
	for i in n - 1:
		edits.append(word.substr(0, i) + word[i + 1] + word[i] + word.substr(i + 2))
	for i in n:
		for letter in LETTERS:
			edits.append(word.substr(0, i) + letter + word.substr(i + 1))
	for i in n + 1:
		for letter in LETTERS:
			edits.append(word.substr(0, i) + letter + word.substr(i))
	return edits
