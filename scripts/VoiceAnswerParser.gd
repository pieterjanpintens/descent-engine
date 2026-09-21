class_name VoiceAnswerParser
extends RefCounted

## Interprets speech as an ANSWER to the dialog that is currently open (the
## "context" half of voice control - VoiceCommandParser handles commands when
## no dialog is open). Never instantiated: static, pure text in / data out, so
## it is testable without audio or a scene. PlayerDialog.try_voice_answer()
## uses it to press the right button for the question it is asking.

const OK_WORDS: Array[String] = ["ok", "okay", "continue", "next", "done", "close", "fine", "alright", "confirm", "proceed", "yes"]
const YES_WORDS: Array[String] = ["yes", "yeah", "yep", "yup", "correct", "sure", "ok", "okay", "confirm"]
const NO_WORDS: Array[String] = ["no", "nope", "negative", "nah"]
const CANCEL_WORDS: Array[String] = ["cancel", "never", "nevermind", "stop", "abort", "nothing"]
const BACK_WORDS: Array[String] = ["back", "previous"]
## Words that carry no information when picking an option ("use the sword").
const FILLER_WORDS: Array[String] = ["the", "a", "an", "please", "use", "with", "pick", "choose", "select", "take", "weapon", "option", "number", "i", "want", "go", "for"]

const ORDINALS: Dictionary = {
	"first": 0, "second": 1, "third": 2, "fourth": 3, "fifth": 4, "sixth": 5,
	"1st": 0, "2nd": 1, "3rd": 2, "4th": 3, "5th": 4, "6th": 5,
}

const ONES: Dictionary = {
	"zero": 0, "none": 0, "one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3,
	"four": 4, "for": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "ate": 8, "nine": 9,
	"ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
	"fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
}
const TENS: Dictionary = {
	"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
	"sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
}

## match_choice() results other than an option index.
const CHOICE_CANCEL := -1
const CHOICE_NONE := -2  ## nothing recognised
const CHOICE_AMBIGUOUS := -3  ## several options fit equally well


static func is_ok(text: String) -> bool:
	return _has_any(text, OK_WORDS)


static func is_yes(text: String) -> bool:
	return _has_any(text, YES_WORDS) and not _has_any(text, NO_WORDS)


static func is_no(text: String) -> bool:
	return _has_any(text, NO_WORDS)


static func is_cancel(text: String) -> bool:
	return _has_any(text, CANCEL_WORDS)


static func is_back(text: String) -> bool:
	return _has_any(text, BACK_WORDS)


## Number words that are also ordinary words ("I rolled it FOR three").
const HOMOPHONES: Array[String] = ["to", "too", "for", "won", "ate"]
## A reply this short may be nothing but a homophone ("to" = 2).
const HOMOPHONE_MAX_WORDS := 3


## A whole number 0-99 spoken as digits ("3", "12") or words ("three",
## "twenty five", "twenty-five") ANYWHERE in the text - "I rolled three", "I got
## a four", "that's 2 successes" - so it doesn't depend on the verb. The FIRST
## number wins. The homophones ("to", "for", "won", "ate") only count when no
## real number is present AND the text is short, so "I rolled it for three"
## reads 3, not 4. -1 if there is no number.
static func parse_number(text: String) -> int:
	var words := VoiceCommandParser._words(text)
	var number := _first_number(words, false)
	if number == -1 and words.size() <= HOMOPHONE_MAX_WORDS:
		number = _first_number(words, true)
	return number


static func _first_number(words: Array[String], allow_homophones: bool) -> int:
	for i in words.size():
		var word := words[i]
		if not allow_homophones and HOMOPHONES.has(word):
			continue
		if word.is_valid_int():
			return word.to_int()
		if TENS.has(word):
			var value: int = TENS[word]
			if i + 1 < words.size() and ONES.has(words[i + 1]) and ONES[words[i + 1]] < 10 and ONES[words[i + 1]] > 0:
				value += ONES[words[i + 1]]
			return value
		if ONES.has(word):
			return ONES[word]
	return -1


## True if the spoken word means the label/name word: equal, a close
## misrecognition (see VoiceCommandParser._fuzzy_equal), or a spoken number for
## a digit word ("two"/"to" -> "2"), so "exploration two" finds "exploration 2".
static func word_matches(spoken: String, candidate: String) -> bool:
	if VoiceCommandParser._fuzzy_equal(spoken, candidate):
		return true
	if candidate.is_valid_int():
		var number := parse_number(spoken)
		return number >= 0 and str(number) == candidate
	return false


## The option (index into `names`) the speech picks: by ordinal/number
## ("first", "two"), by name ("sword" picks "Sword" over "Sword of Light";
## an exact name always beats a longer one containing it), or CHOICE_CANCEL.
## `names` are just the option names (no "(damage 3...)" details - see
## option_name()). Returns CHOICE_NONE / CHOICE_AMBIGUOUS when it can't tell.
static func match_choice(text: String, names: Array[String]) -> int:
	var words: Array[String] = []
	for word in VoiceCommandParser._words(text):
		if not FILLER_WORDS.has(word):
			words.append(word)
	if words.is_empty():
		return CHOICE_NONE
	if _has_any_word(words, CANCEL_WORDS) or _has_any_word(words, BACK_WORDS):
		return CHOICE_CANCEL

	# "first", "second", "last", or a bare number ("two" = option 2).
	if words.size() == 1 or words.size() == 2:
		for word in words:
			if word == "last":
				return names.size() - 1
			if ORDINALS.has(word) and ORDINALS[word] < names.size():
				return ORDINALS[word]
		var number := parse_number(" ".join(words))
		if number >= 1 and number <= names.size() and _all_number_words(words):
			return number - 1

	# By name: every spoken word must match a word of the option's name.
	var best := CHOICE_NONE
	var best_score := -1
	var tied := false
	for i in names.size():
		var name_words: Array[String] = VoiceCommandParser._words(names[i])
		var matched := true
		for spoken in words:
			var found := false
			for candidate in name_words:
				if word_matches(spoken, candidate):
					found = true
					break
			if not found:
				matched = false
				break
		if not matched:
			continue
		# Fewer unspoken words = a closer match ("sword" -> "Sword" beats
		# "Sword of Light"); identical names tie and stay ambiguous.
		var score := 100 - (name_words.size() - words.size())
		if score > best_score:
			best_score = score
			best = i
			tied = false
		elif score == best_score:
			tied = true
	if best == CHOICE_NONE:
		return CHOICE_NONE
	return CHOICE_AMBIGUOUS if tied else best


## "Sword of Light (damage 3, Slash, Lumos)" -> "Sword of Light": just the
## part of an option label a person would say.
static func option_name(label: String) -> String:
	var paren := label.find(" (")
	return label.substr(0, paren) if paren != -1 else label


static func _has_any(text: String, vocabulary: Array[String]) -> bool:
	return _has_any_word(VoiceCommandParser._words(text), vocabulary)


static func _has_any_word(words: Array[String], vocabulary: Array[String]) -> bool:
	for word in words:
		if vocabulary.has(word):
			return true
	return false


static func _all_number_words(words: Array[String]) -> bool:
	for word in words:
		if not (word.is_valid_int() or ONES.has(word) or TENS.has(word)):
			return false
	return true
