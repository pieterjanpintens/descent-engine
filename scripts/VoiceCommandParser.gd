class_name VoiceCommandParser
extends RefCounted

## Turns a spoken/typed command ("hey DM, hero 2 attack green bandit") into a
## structured request. Never instantiated - static functions only, pure text
## in / data out, so it can be tested without audio or a scene. Speech
## recognition mishears things, so everything is matched against a CLOSED
## vocabulary (live monster names, chip colours, hero numbers, verbs) with
## light fuzzy matching instead of exact strings.
##
## Grammar (all parts case-insensitive, punctuation ignored):
##   [wake phrase] [hero N] <attack verb> [the] [colour] [monster name]
##       [with [the] <weapon>] [I rolled <N>]     e.g. "attack John with the
##       sword, I rolled three" - the weapon and the successes are optional and,
##       when spoken, answer the attack's two questions up front
##   [wake phrase] [hero N] <use|interact with|trigger> [the] <object name>
## e.g. "attack green bandit", "hey DM hero two hits the zealot",
## "use the pile of dirt", "interact with exploration two", "trigger the lever".
##   end phase | next phase | end turn        (verb "end_phase")
##   show monsters | monster view              (verb "show_monsters")
##   show map | world view | back to the map   (verb "show_map")
## An attack needs a colour or a name. The interact verbs are deliberately
## just "use", "interact" and "trigger" - never "open"/"search"/"touch" - so
## level designers aren't forced to name actions to match a verb; WHICH action
## happens is picked afterwards from the object's own available actions.
##
## parse() returns a Dictionary:
##   error     String - "" on success, else a message fit to show the table
##   verb      String - "attack" (the only verb so far)
##   hero_slot int    - 0-based HeroCatalog slot, -1 if not spoken
##   monsters  Array[RuntimeMonster] - attack: every live monster matching the
##             target (one = unambiguous; several = the caller must ask which)
##   objects   Array[Dictionary] - interact: every labelled object matching,
##             each {"entry": InteractableEntry, "label": String} (same rule)
##   verb      is "attack" or "interact"
##   weapon_text String - attack: the spoken weapon ("sword of light"), or ""
##   successes int  - attack: the spoken number of successes, -1 if not spoken

const ATTACK_VERBS: Array[String] = ["attack", "hit", "strike", "fight", "kill", "stab", "slash"]
const INTERACT_VERBS: Array[String] = ["use", "interact", "trigger"]

## "I rolled/got/scored/made three" - the verb list is generous but finite; a
## number attached to one of them (or to "successes") is the roll.
const ROLL_WORDS: Array[String] = ["rolled", "roll", "rolls", "rolling", "got", "get", "scored", "made", "threw", "throw", "have", "had"]
const SUCCESS_WORDS: Array[String] = ["success", "successes", "hits"]
## Introduce the weapon: "attack John WITH the sword".
const WEAPON_SPLIT_WORDS: Array[String] = ["with", "using", "wielding"]
const WEAPON_FILLER_WORDS: Array[String] = ["i", "and", "my", "use", "using", "the", "a", "an", "his", "her", "weapon", "please"]

## "end phase" & co (Whisper sometimes writes "face" for "phase").
const END_WORDS: Array[String] = ["end", "next", "finish"]
const PHASE_WORDS: Array[String] = ["phase", "face", "faze", "turn", "round"]
## View switching ("show monsters", "back to the map").
const SHOW_WORDS: Array[String] = ["show", "open", "switch", "view", "display", "see", "go", "back", "return"]
const MONSTER_WORDS: Array[String] = ["monster", "monsters", "enemy", "enemies"]
const MAP_WORDS: Array[String] = ["map", "board", "world", "overview"]
const FILLER_WORDS: Array[String] = ["the", "a", "an", "at", "on", "that", "this", "please", "and", "with", "i"]

## Words the recognizer commonly produces for the wake phrase - stripped from
## the start of the text when present.
const WAKE_PHRASES: Array = [
	["hey", "dm"], ["hey", "d", "m"], ["hey", "dee", "em"], ["a", "dm"],
	["hey", "adam"], ["hate", "dm"], ["hey", "dungeon", "master"],
]

## Spoken numbers, including the homophones speech-to-text likes to write.
const NUMBER_WORDS: Dictionary = {
	"one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3,
	"four": 4, "for": 4, "five": 5, "six": 6,
}


## `interactables` = InteractionLabels.labelled(): [{"entry", "label"}] of the
## objects that can be interacted with right now (their spoken names).
static func parse(text: String, monsters: Array, interactables: Array = []) -> Dictionary:
	var result := {"error": "", "verb": "", "hero_slot": -1, "monsters": [], "objects": [], "weapon_text": "", "successes": -1}
	var words := _words(text)
	words = _strip_wake_phrase(words)

	# Optional "hero N" anywhere before the verb.
	var hero := _extract_hero(words)
	result["hero_slot"] = hero["slot"]
	words = hero["words"]

	# Verb: the first word.
	if words.is_empty():
		result["error"] = "I didn't catch a command."
		return result
	if _is_attack_verb(words[0]):
		result["verb"] = "attack"
		return _parse_attack(result, words.slice(1), monsters)
	if _is_interact_verb(words[0]):
		result["verb"] = "interact"
		return _parse_interact(result, words.slice(1), interactables)
	var system := _system_command(words)
	if system != "":
		result["verb"] = system
		return result
	result["error"] = "I don't know the command \"%s\". Try: attack green bandit, use the pile of dirt, end phase, or show monsters." % " ".join(words)
	return result


## Commands that aren't about a target: "end_phase", "show_monsters" or
## "show_map" ("" if the words are none of them).
static func _system_command(words: Array[String]) -> String:
	var spoken: Array[String] = []
	for word in words:
		if not FILLER_WORDS.has(word) and word != "to":
			spoken.append(word)
	if spoken.is_empty():
		return ""
	if spoken.size() >= 2 and END_WORDS.has(spoken[0]) and PHASE_WORDS.has(spoken[1]):
		return "end_phase"
	# A view request: just the noun ("monsters"), a show-verb, or "... view".
	if spoken.size() == 1 or SHOW_WORDS.has(spoken[0]) or spoken.has("view"):
		for word in spoken:
			if MONSTER_WORDS.has(word):
				return "show_monsters"
		for word in spoken:
			if MAP_WORDS.has(word):
				return "show_map"
	return ""


## Target of an attack: an optional chip colour plus the rest as a monster name.
static func _parse_attack(result: Dictionary, words: Array[String], monsters: Array) -> Dictionary:
	# 1. The roll, wherever it is: "I rolled three", "got a 4", "3 successes".
	var rest: Array[String] = []
	var i := 0
	while i < words.size():
		var word := words[i]
		if ROLL_WORDS.has(word):
			# The number is within the next few words ("rolled a three", "got
			# it for three", "scored twenty five"): the first real number word
			# wins, a homophone ("to", "for") only counts right after the verb.
			var found := -1
			var consumed := 0
			for j in range(i + 1, mini(i + 5, words.size())):
				if VoiceAnswerParser.HOMOPHONES.has(words[j]) and j != i + 1:
					continue
				var value := VoiceAnswerParser.parse_number(words[j])
				if value < 0:
					continue
				var used := 1
				if VoiceAnswerParser.TENS.has(words[j]) and j + 1 < words.size():
					var ones := words[j + 1]
					if VoiceAnswerParser.ONES.has(ones) and not VoiceAnswerParser.HOMOPHONES.has(ones) and VoiceAnswerParser.ONES[ones] >= 1 and VoiceAnswerParser.ONES[ones] <= 9:
						value += VoiceAnswerParser.ONES[ones]
						used = 2
				found = value
				consumed = j + used - i
				break
			if found >= 0:
				result["successes"] = found
				i += consumed
				continue
		if SUCCESS_WORDS.has(word) and not rest.is_empty():
			var before := VoiceAnswerParser.parse_number(rest[rest.size() - 1])
			if before >= 0:
				result["successes"] = before
				rest.remove_at(rest.size() - 1)
				i += 1
				continue
		rest.append(word)
		i += 1

	# 2. The weapon: everything after the first "with"/"using".
	var target_words: Array[String] = []
	var weapon_words: Array[String] = []
	var after_split := false
	for word in rest:
		if not after_split and WEAPON_SPLIT_WORDS.has(word):
			after_split = true
		elif after_split:
			if not WEAPON_FILLER_WORDS.has(word):
				weapon_words.append(word)
		else:
			target_words.append(word)
	result["weapon_text"] = " ".join(weapon_words)

	# 3. The target: an optional chip colour plus the rest as a monster name.
	var chip := -1
	var name_words: Array[String] = []
	for word in target_words:
		if FILLER_WORDS.has(word):
			continue
		var word_chip := _chip_for_word(word)
		if word_chip != -1 and chip == -1:
			chip = word_chip
		else:
			name_words.append(word)
	if chip == -1 and name_words.is_empty():
		result["error"] = "Attack what? Say a colour and a monster, like \"attack green bandit\"."
		return result
	if monsters.is_empty():
		result["error"] = "There are no monsters on the board."
		return result

	var matches: Array[RuntimeMonster] = []
	for monster: RuntimeMonster in monsters:
		if chip != -1 and monster.chip != chip:
			continue
		if _name_matches(name_words, monster):
			matches.append(monster)
	# Nothing matched: retry by SOUND, for names speech recognition can't spell
	# ("Mieke" heard as "Mikey"/"Micky").
	if matches.is_empty() and not name_words.is_empty():
		for monster: RuntimeMonster in monsters:
			if chip != -1 and monster.chip != chip:
				continue
			if _name_matches(name_words, monster, true):
				matches.append(monster)
	if matches.is_empty():
		result["error"] = "No monster matches \"%s\"." % " ".join(_target_words(chip, name_words))
		return result
	result["monsters"] = matches
	return result


## Target of an interaction: the spoken name of a labelled object. Every spoken
## word must match a word of its label ("pile of dirt", "front door" for
## front_door, "exploration two" for "exploration 2"); among the matches only
## the ones with the fewest unspoken extra words survive, so "exploration 2"
## isn't confused with "exploration 20" while plain "exploration" still matches
## every numbered token (the caller then asks which).
static func _parse_interact(result: Dictionary, words: Array[String], interactables: Array) -> Dictionary:
	var spoken: Array[String] = []
	for word in words:
		if not FILLER_WORDS.has(word):
			spoken.append(word)
	if spoken.is_empty():
		result["error"] = "Use what? Say the name of an object, like \"use the pile of dirt\"."
		return result
	if interactables.is_empty():
		result["error"] = "There is nothing to interact with right now."
		return result

	var matches: Array[Dictionary] = []
	var best_extra := 1000
	for item: Dictionary in interactables:
		var label_words: Array[String] = _words(item["label"])
		var all_match := true
		for spoken_word in spoken:
			var found := false
			for label_word in label_words:
				if VoiceAnswerParser.word_matches(spoken_word, label_word):
					found = true
					break
			if not found:
				all_match = false
				break
		if not all_match:
			continue
		var extra := label_words.size() - spoken.size()
		if extra < best_extra:
			best_extra = extra
			matches.clear()
		if extra == best_extra:
			matches.append(item)
	if matches.is_empty():
		result["error"] = "Nothing called \"%s\" can be interacted with right now." % " ".join(spoken)
		return result
	result["objects"] = matches
	return result


## True if the text starts with the wake phrase ("hey DM ...").
static func has_wake_phrase(text: String) -> bool:
	var words := _words(text)
	return _strip_wake_phrase(words).size() < words.size()


## True if the text is ONLY the wake phrase ("hey DM") - a cue to listen for
## the command in the next sentence.
static func is_wake_only(text: String) -> bool:
	var words := _words(text)
	return words.size() > 0 and _strip_wake_phrase(words).is_empty()


## Lowercase words with everything but letters/digits removed.
static func _words(text: String) -> Array[String]:
	var cleaned := ""
	for i in text.length():
		var ch := text[i].to_lower()
		var code := ch.unicode_at(0)
		var is_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		cleaned += ch if (is_letter or is_digit) else " "
	var words: Array[String] = []
	for word in cleaned.split(" ", false):
		words.append(word)
	return words


static func _strip_wake_phrase(words: Array[String]) -> Array[String]:
	for phrase: Array in WAKE_PHRASES:
		if words.size() >= phrase.size() and words.slice(0, phrase.size()) == phrase:
			var rest: Array[String] = []
			rest.assign(words.slice(phrase.size()))
			return rest
	return words


## Finds "hero <n>" (n = digit or spoken number, 1-based), returns the 0-based
## slot (-1 if absent) and the words with those two removed.
static func _extract_hero(words: Array[String]) -> Dictionary:
	for i in words.size() - 1:
		if words[i] == "hero" or _fuzzy_equal(words[i], "hero"):
			var number := _number(words[i + 1])
			if number > 0:
				var rest: Array[String] = []
				rest.assign(words.slice(0, i) + words.slice(i + 2))
				return {"slot": number - 1, "words": rest}
	return {"slot": -1, "words": words}


static func _number(word: String) -> int:
	if word.is_valid_int():
		return word.to_int()
	return NUMBER_WORDS.get(word, -1)


static func _is_attack_verb(word: String) -> bool:
	for verb in ATTACK_VERBS:
		# "attacks"/"attacking" and small mishearings still count.
		if _fuzzy_equal(word, verb) or (word.length() > verb.length() and word.begins_with(verb)):
			return true
	return false


static func _is_interact_verb(word: String) -> bool:
	for verb in INTERACT_VERBS:
		# "uses"/"using"-style suffixes and small mishearings still count.
		if _fuzzy_equal(word, verb) or (word.length() > verb.length() and word.begins_with(verb)):
			return true
	return false


static func _chip_for_word(word: String) -> int:
	for chip in MonsterChip.Chip.values():
		if _fuzzy_equal(word, MonsterChip.display_name(chip).to_lower()):
			return chip
	return -1


## True if every spoken name word matches a word of the monster's generic type
## name or its custom name (so "sister" finds a Blood Sister). No name words
## (colour only) matches every monster.
static func _name_matches(name_words: Array[String], monster: RuntimeMonster, phonetic: bool = false) -> bool:
	if name_words.is_empty():
		return true
	var candidates: Array[String] = _words(monster.display_name())
	candidates.append_array(_words(str(MonsterDisplay.find_monster(monster.folder).get("name", monster.folder))))
	for spoken in name_words:
		var found := false
		for candidate in candidates:
			if _fuzzy_equal(spoken, candidate) or (phonetic and _sounds_alike(spoken, candidate)):
				found = true
				break
		if not found:
			return false
	return true


## Same first letter and the same consonant skeleton ("mieke", "mikey", "micky"
## and "meeka" are all "mk"). Deliberately crude - only used as a fallback when
## the normal matching found nothing, so a collision needs a coincidence.
static func _sounds_alike(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty() or a[0] != b[0]:
		return false
	var key_a := _consonant_key(a)
	return key_a.length() >= 2 and key_a == _consonant_key(b)


static func _consonant_key(word: String) -> String:
	var w := word.to_lower().replace("ck", "k").replace("ph", "f").replace("c", "k").replace("q", "k")
	var key := ""
	for i in w.length():
		var ch := w[i]
		if "aeiouy".contains(ch):
			continue
		if key.is_empty() or key[key.length() - 1] != ch:
			key += ch
	return key


static func _target_words(chip: int, name_words: Array[String]) -> Array[String]:
	var shown: Array[String] = []
	if chip != -1:
		shown.append(MonsterChip.display_name(chip).to_lower())
	shown.append_array(name_words)
	return shown


## Equal, or - for words of 4+ letters - within a small edit distance (one
## edit up to 6 letters, two beyond), which absorbs plurals and typical
## recognition slips ("bandits", "zealout").
static func _fuzzy_equal(a: String, b: String) -> bool:
	if a == b:
		return true
	if a.length() < 4 or b.length() < 4:
		return false
	var allowed := 1 if maxi(a.length(), b.length()) <= 6 else 2
	return _levenshtein(a, b) <= allowed


static func _levenshtein(a: String, b: String) -> int:
	var previous: Array[int] = []
	for j in b.length() + 1:
		previous.append(j)
	for i in a.length():
		var current: Array[int] = [i + 1]
		for j in b.length():
			var cost := 0 if a[i] == b[j] else 1
			current.append(mini(mini(current[j] + 1, previous[j + 1] + 1), previous[j] + cost))
		previous = current
	return previous[b.length()]
