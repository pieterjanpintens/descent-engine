class_name MissionVariable
extends Resource

## Declares one custom variable a mission author can reference from a
## Condition or Effect (see MissionData.custom_variables). Built-in
## variables the runtime always provides regardless of mission (round_number,
## player_count, ...) use this same shape but aren't authored here - the
## runtime declares those itself, not the mission file.

enum Type {
	BOOL,
	INT,
	FLOAT,
	STRING,
}

@export var name: String = ""
@export var type: Type = Type.BOOL
## Checked against `type` when the mission loads (push_warning() + fallback
## to a zero-value if mismatched) - see Condition.value's note on why this
## is a runtime check rather than a typed Inspector widget per variable.
@export var default_value: Variant = false
