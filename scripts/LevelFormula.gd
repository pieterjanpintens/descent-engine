class_name LevelFormula
extends RefCounted

## The "level shift" of a monster as a formula: a small arithmetic expression that returns a whole number, added to the level its author gave it
## (the result is the level the monster spawns at, never below 1). MissionData.level_formula is the mission's default, MonsterTemplate.level_formula
## overrides it for one monster ("" = use the mission's; "0" = ignore difficulty). With no formula at all, DEFAULT is used.
##
## Names the formula can use (`variables()`): difficulty (1-4), player_count, round_number, monsters_on_the_map, level (the monster's authored level) and the mission's
## own INT variables. Functions: min max clamp abs sign floor ceil round floori ceili roundi signi pow sqrt. Operators: + - * / % and ( ), comparisons
## (a bool counts as 1 / 0 in arithmetic through int()), and / or / not.  `/` between two whole numbers is a whole-number division.
## Examples:  difficulty - 2   |   0   |   difficulty - 2 + (player_count - 3) / 2   |   clamp(difficulty - 2, 0, 2)
##
## The text is run by Godot's Expression class, but ONLY after check() has verified every character and every name against a whitelist, so a
## formula inside a shared mission can never call anything but the functions above.

const DEFAULT := "difficulty - 2"
const MAX_LENGTH := 200
const MAX_SHIFT := 20  ## the result is clamped to +-this, so a typo cannot spawn level 9999 monsters

const FUNCTIONS: Array[String] = ["min", "max", "clamp", "abs", "sign", "floor", "ceil", "round", "floori", "ceili", "roundi", "signi", "pow", "sqrt", "int", "float"]
const BUILTIN_NAMES: Array[String] = ["difficulty", "player_count", "round_number", "monsters_on_the_map", "level"]
const KEYWORDS: Array[String] = ["and", "or", "not", "true", "false"]

## (name, formula, what it does) - the presets of the editor's picker.
static func presets() -> Array:
	return [
		[TranslationServer.translate("Follow the difficulty"), DEFAULT, TranslationServer.translate("One level less on Apprentice, as designed on Adventurer, one more on Veteran, two more on Nightmare.")],
		[TranslationServer.translate("Ignore the difficulty"), "0", TranslationServer.translate("The monster always has the level it was given.")],
		[TranslationServer.translate("Difficulty and party size"), "difficulty - 2 + (player_count - 3) / 2", TranslationServer.translate("The difficulty shift, plus a level for every two heroes above three (one fewer for small parties).")],
		[TranslationServer.translate("Party size only"), "(player_count - 3) / 2", TranslationServer.translate("Only the number of heroes matters.")],
		[TranslationServer.translate("Difficulty, but never easier"), "clamp(difficulty - 2, 0, 2)", TranslationServer.translate("Higher difficulties make it stronger; the easy one keeps the designed level.")],
	]


## The names a formula of `mission` can use: the built-ins plus every custom INT variable with a name that is a valid identifier.
static func variables(mission: MissionData) -> Array[String]:
	var names: Array[String] = BUILTIN_NAMES.duplicate()
	if mission != null:
		for variable in mission.custom_variables:
			if variable.type == MissionVariable.Type.INT and _is_identifier(variable.name) and not names.has(variable.name) \
					and not FUNCTIONS.has(variable.name) and not KEYWORDS.has(variable.name):
				names.append(variable.name)
	return names


## "" when `formula` is allowed, else why not. Only the whitelist is checked here - evaluate() also reports a formula that does not parse or run.
static func check(formula: String, names: Array[String]) -> String:
	var text := formula.strip_edges()
	if text == "":
		return ""
	if text.length() > MAX_LENGTH:
		return TranslationServer.translate("The formula is too long.")
	var index := 0
	while index < text.length():
		var ch := text[index]
		if ch == " " or ch == "\t":
			index += 1
		elif _is_digit(ch):
			index += 1
			var dots := 0
			while index < text.length() and (_is_digit(text[index]) or text[index] == "."):
				dots += int(text[index] == ".")
				index += 1
			if dots > 1:
				return TranslationServer.translate("A number has more than one decimal point.")
		elif _is_letter(ch):
			var start := index
			while index < text.length() and (_is_letter(text[index]) or _is_digit(text[index])):
				index += 1
			var word := text.substr(start, index - start)
			var next_char := _next_non_space(text, index)
			if FUNCTIONS.has(word):
				if next_char != "(":
					return TranslationServer.translate("'%s' is a function: write it like %s(...).") % [word, word]
			elif not names.has(word) and not KEYWORDS.has(word):
				return TranslationServer.translate("Unknown name '%s'. You can use: %s") % [word, ", ".join(names)]
		elif "+-*/%(),<>=!&|".contains(ch):
			index += 1
		else:
			return TranslationServer.translate("The character '%s' is not allowed in a formula.") % ch
	return ""


## Runs `formula` (the DEFAULT when blank) with `values` (name -> number) and returns {ok, shift, error}: `shift` is a whole number between
## -MAX_SHIFT and MAX_SHIFT. A formula that fails (not allowed, does not parse, does not give a number) is reported and shifts nothing.
static func evaluate(formula: String, values: Dictionary) -> Dictionary:
	var text := formula.strip_edges()
	if text == "":
		text = DEFAULT
	var names: Array[String] = []
	for name in values:
		names.append(str(name))
	var problem := check(text, names)
	if problem != "":
		return {"ok": false, "shift": 0, "error": problem}
	var expression := Expression.new()
	if expression.parse(text, PackedStringArray(names)) != OK:
		return {"ok": false, "shift": 0, "error": expression.get_error_text()}
	var inputs: Array = []
	for name in names:
		inputs.append(values[name])
	var result: Variant = expression.execute(inputs, null, false)
	if expression.has_execute_failed():
		return {"ok": false, "shift": 0, "error": TranslationServer.translate("The formula could not be calculated.")}
	if typeof(result) == TYPE_BOOL:
		result = int(result)
	if typeof(result) != TYPE_INT and typeof(result) != TYPE_FLOAT:
		return {"ok": false, "shift": 0, "error": TranslationServer.translate("The formula does not give a number.")}
	var number: float = float(result)
	if is_nan(number) or is_inf(number):
		return {"ok": false, "shift": 0, "error": TranslationServer.translate("The formula does not give a number.")}
	return {"ok": true, "shift": clampi(floori(number), -MAX_SHIFT, MAX_SHIFT), "error": ""}


## For a COUNT (the "random spawn" effect): `formula` ("" = 1) calculated with `values`, a whole number from 0 to MAX_SHIFT. Returns {ok, count, error}.
static func evaluate_count(formula: String, values: Dictionary) -> Dictionary:
	if formula.strip_edges() == "":
		return {"ok": true, "count": 1, "error": ""}
	var result := evaluate(formula, values)
	return {"ok": result["ok"], "count": maxi(0, int(result["shift"])), "error": result["error"]}


static func _is_identifier(text: String) -> bool:
	if text == "" or not (_is_letter(text[0])):
		return false
	for i in text.length():
		if not (_is_letter(text[i]) or _is_digit(text[i])):
			return false
	return true


static func _is_letter(ch: String) -> bool:
	return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_"


static func _is_digit(ch: String) -> bool:
	return ch >= "0" and ch <= "9"


static func _next_non_space(text: String, from: int) -> String:
	var i := from
	while i < text.length() and (text[i] == " " or text[i] == "\t"):
		i += 1
	return text[i] if i < text.length() else ""
