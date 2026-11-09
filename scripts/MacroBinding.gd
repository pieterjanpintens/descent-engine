class_name MacroBinding
extends Resource

## One "this field is an input" link of a MacroTemplate: the value of the input `param_id` is written into the field `path` of the data the
## template generates. Text fields do not need one - they use {tokens} (see MacroTokens); a binding is for what a token cannot reach: numbers,
## yes/no values, enum values and whole effects (a Loot or Monsters input).
##
## `path` starts with the key of a template part and then names fields, written like folders: "open/effects/0/required_successes" is the
## `required_successes` of the first effect of the action of the part "open". A segment is a property name, a list position or a dictionary
## key.
##
## A Resource-valued input (LOOT, MONSTERS) is copied in whole into the field (which holds a placeholder effect in the template); then
##   overrides   - properties set on the copy ALWAYS (an enum value such as the effect type; text values may hold tokens), and
##   fill_empty  - properties set on the copy only when it has nothing there yet (text values may hold tokens), e.g. a default sentence.

@export var path: String = ""
@export var param_id: String = ""
@export var overrides: Dictionary = {}
@export var fill_empty: Dictionary = {}


## The segments of `path` after the part key ([] for a path with no field).
func fields() -> PackedStringArray:
	var parts := path.split("/", false)
	return parts.slice(1) if parts.size() > 1 else PackedStringArray()


func part_key() -> String:
	var parts := path.split("/", false)
	return parts[0] if parts.size() > 0 else ""


## The thing the path ends at, starting from `root` (the part's data), or null when a segment does not exist.
static func read(root: Variant, fields: PackedStringArray) -> Variant:
	var current: Variant = root
	for field in fields:
		current = _step(current, field)
		if current == null:
			return null
	return current


## Whether the path leads to a field that write() could set (the last segment exists on what the rest of the path reaches).
static func can_write(root: Variant, fields: PackedStringArray) -> bool:
	if fields.is_empty():
		return false
	var holder: Variant = read(root, fields.slice(0, fields.size() - 1))
	var last := fields[fields.size() - 1]
	if holder is Object:
		return _has_property(holder, last)
	if holder is Array:
		return last.is_valid_int() and int(last) >= 0 and int(last) < (holder as Array).size()
	return holder is Dictionary


## Writes `value` at the end of the path. False when the path does not lead anywhere or the write is refused.
static func write(root: Variant, fields: PackedStringArray, value: Variant) -> bool:
	if fields.is_empty():
		return false
	var holder: Variant = read(root, fields.slice(0, fields.size() - 1))
	var last := fields[fields.size() - 1]
	if holder is Object:
		var object: Object = holder
		if not _has_property(object, last):
			return false
		object.set(last, value)
		return true
	if holder is Array:
		var list: Array = holder
		if not last.is_valid_int() or int(last) < 0 or int(last) >= list.size():
			return false
		list[int(last)] = value
		return true
	if holder is Dictionary:
		(holder as Dictionary)[last] = value
		return true
	return false


static func _step(current: Variant, field: String) -> Variant:
	if current is Object:
		var object: Object = current
		return object.get(field) if _has_property(object, field) else null
	if current is Array:
		var list: Array = current
		return list[int(field)] if field.is_valid_int() and int(field) >= 0 and int(field) < list.size() else null
	if current is Dictionary:
		return (current as Dictionary).get(field)
	return null


static func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property["name"] == property_name:
			return true
	return false
