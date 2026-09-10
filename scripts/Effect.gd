class_name Effect
extends Resource

## Writes a single named variable in the mission's runtime variable
## registry - the one write primitive behind PropAction and MissionTrigger.
## Deliberately just a SET for now (no increment/expression support),
## matching Condition's "basic power first" scope - see that class for the
## read-side equivalent and why value is a loosely-typed Variant.

@export var variable_name: String = ""
@export var value: Variant = null
