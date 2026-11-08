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
	## Appended (saved values keep their meaning): the variable modulo the value is 0, i.e. the variable is a whole multiple of
	## the value ("every 3rd round": round_number is a multiple of 3). Whole-number variables only; a value of 0 never holds.
	MULTIPLE_OF,
	## The opposite: the variable modulo the value is not 0 (round_number is not a multiple of 2 = every odd round).
	NOT_MULTIPLE_OF,
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
		Operator.MULTIPLE_OF:
			return _is_multiple(current, target) == 1
		Operator.NOT_MULTIPLE_OF:
			return _is_multiple(current, target) == 0
	return false


## 1 when `current` is a whole multiple of `target`, 0 when it is not, -1 when the question makes no sense
## (not whole numbers, or a divisor of 0) - then neither "multiple of" nor "not multiple of" holds.
static func _is_multiple(current: Variant, target: Variant) -> int:
	if typeof(current) != TYPE_INT or typeof(target) != TYPE_INT or int(target) == 0:
		return -1
	return 1 if int(current) % int(target) == 0 else 0
