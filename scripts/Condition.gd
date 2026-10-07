class_name Condition
extends Resource

## A single comparison against a named variable in the mission's runtime
## variable registry (see MissionVariable, MissionData.custom_variables, and
## the runtime's own built-ins like round_number/player_count). Deliberately
## basic for now - one variable, one operator, one value, no AND/OR nesting
## and no querying other objects' state yet.
##
## The shared comparison primitive behind both MissionTrigger and
## MissionObjective - conditions[] on either is an implicit AND across every
## entry. Improving this later (nesting, cross-object queries) improves both
## at once instead of needing two parallel systems.

enum Operator {
	EQUALS,
	NOT_EQUALS,
	GREATER,
	GREATER_EQUAL,
	LESS,
	LESS_EQUAL,
}

@export var variable_name: String = ""
@export var operator: Operator = Operator.EQUALS
## Checked against the target variable's declared MissionVariable.type at
## evaluation time, not in the Inspector - a per-variable-typed Inspector
## widget would need a custom EditorInspectorPlugin, more tooling than this
## needs right now. A type mismatch is a push_warning() and the condition
## evaluates to false rather than silently coercing.
@export var value: Variant = null


## Whether `current` (a variable's live value) satisfies this condition's operator against `target`
## (the condition's value, already coerced to the variable's type by the caller).
func holds_for(current: Variant, target: Variant) -> bool:
	match operator:
		Operator.EQUALS:
			return current == target
		Operator.NOT_EQUALS:
			return current != target
		Operator.GREATER:
			return current > target
		Operator.GREATER_EQUAL:
			return current >= target
		Operator.LESS:
			return current < target
		Operator.LESS_EQUAL:
			return current <= target
	return false
