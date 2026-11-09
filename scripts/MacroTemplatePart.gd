class_name MacroTemplatePart
extends Resource

## One piece of what a MacroTemplate generates: a variable, a prop action or a trigger, kept as ordinary mission data (`data`) that may contain
## {tokens} (MacroTokens) and fields set from inputs (MacroBinding). `key` names the part inside the template (tokens and bindings use it).

enum Kind { VARIABLE, ACTION, TRIGGER }

@export var kind: Kind = Kind.ACTION
## Unique inside the template; letters, digits and underscores.
@export var key: String = ""
## The name (variable) or id (prop action) the piece wants; may hold tokens ("{base}_progress"). A number is added when it is taken. Unused
## for a trigger (it gets a fresh id).
@export var wanted: String = ""
## A MissionVariable, a PropAction or a MissionTrigger, matching `kind`. A variable's name, an action's id and a trigger's id are ignored.
@export var data: Resource


## "" when the part is usable, else what is wrong.
func problem() -> String:
	if key == "" or MacroContext.identifier(key) != key:
		return "A part has no usable key ('%s'): letters, digits and underscores only." % key
	if data == null:
		return "Part '%s' has no data." % key
	match kind:
		Kind.VARIABLE:
			if not data is MissionVariable:
				return "Part '%s' is a variable but its data is not." % key
			if wanted == "":
				return "Part '%s' (a variable) needs a name." % key
		Kind.ACTION:
			if not data is PropAction:
				return "Part '%s' is a prop action but its data is not." % key
			if wanted == "":
				return "Part '%s' (a prop action) needs an id." % key
		Kind.TRIGGER:
			if not data is MissionTrigger:
				return "Part '%s' is a trigger but its data is not." % key
	return ""
