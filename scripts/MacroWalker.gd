class_name MacroWalker
extends RefCounted

## Visits every text inside mission data (the saved String fields of Resources, recursively, the strings in arrays and the values of
## dictionaries - the per-language text maps among them) and may replace them in place. Used by macro capture to find which variables the
## pieces mention and to rewrite their names into {tokens} (see MacroTokens). Dictionary keys are never touched.


## Calls `visit(text) -> String` for every text under `value`; a different returned text replaces the original. `skip` names properties
## (of any Resource) that are not entered.
static func map_strings(value: Variant, visit: Callable, skip: PackedStringArray = PackedStringArray(), seen: Dictionary = {}) -> void:
	if value is Resource:
		var resource: Resource = value
		if seen.has(resource.get_instance_id()):
			return
		seen[resource.get_instance_id()] = true
		for property in resource.get_property_list():
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_STORAGE == 0:
				continue
			if skip.has(property["name"]):
				continue
			var current: Variant = resource.get(property["name"])
			if current is String:
				var replaced: String = visit.call(current)
				if replaced != current:
					resource.set(property["name"], replaced)
			elif current is Array or current is Dictionary or current is Resource:
				map_strings(current, visit, skip, seen)
	elif value is Array:
		var list: Array = value
		for index in list.size():
			var item: Variant = list[index]
			if item is String:
				var replaced: String = visit.call(item)
				if replaced != item:
					list[index] = replaced
			else:
				map_strings(item, visit, skip, seen)
	elif value is Dictionary:
		var map: Dictionary = value
		for key in map.keys():
			var item: Variant = map[key]
			if item is String:
				var replaced: String = visit.call(item)
				if replaced != item:
					map[key] = replaced
			else:
				map_strings(item, visit, skip, seen)


## How often each text of `wanted` (a set: text -> anything) appears as a whole text under any of `roots`.
static func count_texts(roots: Array, wanted: Dictionary, skip: PackedStringArray = PackedStringArray()) -> Dictionary:
	var counts := {}
	var visit := func(text: String) -> String:
		if wanted.has(text):
			counts[text] = int(counts.get(text, 0)) + 1
		return text
	var seen := {}
	for root in roots:
		map_strings(root, visit, skip, seen)
	return counts
