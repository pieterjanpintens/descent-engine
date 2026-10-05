class_name TargetRule
extends Resource

## One "preferred target" rule of a monster: how it picks WHO to attack - a
## specific hero, "the hero that did the most damage", ... A monster holds an
## ORDERED list of these (`MonsterTemplate`/`RuntimeMonster.target_rules`,
## presumably first rule that yields a target wins - the evaluation isn't
## designed yet).
##
## Placeholder for now: only a name. Nothing reads these yet; the rule kinds and
## their parameters (which hero, ...) will follow once monster attacks exist.

@export var rule_name: String = ""


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"name": rule_name}


static func from_dict(d: Dictionary) -> TargetRule:
	var rule := TargetRule.new()
	rule.rule_name = str(d.get("name", ""))
	return rule


## Independent copies of `list` - a spawned monster must not share the
## design-time template's resources.
static func copies(list: Array[TargetRule]) -> Array[TargetRule]:
	var result: Array[TargetRule] = []
	for rule in list:
		result.append(from_dict(rule.to_dict()))
	return result
