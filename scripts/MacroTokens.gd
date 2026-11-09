class_name MacroTokens
extends RefCounted

## The {placeholders} of a user-defined macro template (see MacroTemplate): replaced in every text of the data the macro generates.
##
## A token is {name}, {name.part} or {kind:key}. What the template builder (UserMacro) provides:
##   {base}              the target's name made safe as an identifier ("chest", "front_door") - the same as MacroContext.base_name()
##   {var:KEY}           the name that was really given to the generated variable of the template part KEY
##   {action:KEY}        the id that was really given to the generated prop action of the part KEY (a trigger's event id)
##   {PARAM}             the value of the input PARAM as text (a number, a text, yes/no)
##   {PARAM.label}       for a CHOICE input: the label of the chosen entry; {PARAM.value} its value; {PARAM.other} one of the extra texts
##                       of the entry (the optional third element, a Dictionary)
## A token nobody knows is left exactly as written, so ordinary text with braces is safe.

static var _regex: RegEx


static func _pattern() -> RegEx:
	if _regex == null:
		_regex = RegEx.new()
		_regex.compile("\\{([A-Za-z_][A-Za-z0-9_]*(?:[.:][A-Za-z0-9_]+)?)\\}")
	return _regex


## `text` with every known token replaced.
static func text(text: String, tokens: Dictionary) -> String:
	if not text.contains("{"):
		return text
	var out := ""
	var from := 0
	for found in _pattern().search_all(text):
		var key := found.get_string(1)
		out += text.substr(from, found.get_start() - from)
		out += str(tokens[key]) if tokens.has(key) else found.get_string(0)
		from = found.get_end()
	return out + text.substr(from)


## Replaces tokens in every text inside `value`, in place: the saved String fields of a Resource (recursively), the strings of arrays and
## the values of dictionaries (the per-language maps of translated texts are such dictionaries; keys are never touched). Returns `value`
## (for a String: the new text).
static func substitute(value: Variant, tokens: Dictionary, seen: Dictionary = {}) -> Variant:
	if value is String:
		return text(value, tokens)
	if value is Resource:
		var resource: Resource = value
		if seen.has(resource.get_instance_id()):
			return value
		seen[resource.get_instance_id()] = true
		for property in resource.get_property_list():
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_STORAGE == 0:
				continue
			var current: Variant = resource.get(property["name"])
			if current is String:
				var replaced := text(current, tokens)
				if replaced != current:
					resource.set(property["name"], replaced)
			elif current is Array or current is Dictionary or current is Resource:
				substitute(current, tokens, seen)
	elif value is Array:
		var list: Array = value
		for index in list.size():
			var item: Variant = list[index]
			if item is String:
				list[index] = text(item, tokens)
			else:
				substitute(item, tokens, seen)
	elif value is Dictionary:
		var map: Dictionary = value
		for key in map.keys():
			var item: Variant = map[key]
			if item is String:
				map[key] = text(item, tokens)
			else:
				substitute(item, tokens, seen)
	return value
