class_name MonsterTemplate
extends Resource

## Design-time definition of ONE monster an Effect.Type.SPAWN_MONSTERS
## effect spawns (Effect.spawn_monsters). Its properties are copied onto the
## RuntimeMonster registered at play time (MissionRuntime.register_monster()).
## More properties will follow.

## MonsterDisplay.REAL_MONSTERS `folder`, e.g. "bandit", "blood sister".
@export var folder: String = "bandit"
## Optional; empty = use the monster type's generic name ("Bandit").
@export var custom_name: String = ""
@export_range(0, 9999) var hitpoints: int = 20
@export_range(0, 9999) var level: int = 1
## Defense modifier: each hit the engine rolls 0..defense and subtracts it
## from the damage (see MissionRuntime.resolve_attack()).
@export_range(0, 9999) var defense: int = 0
## Lists of Vulnerability.Kind values (not used by combat yet).
@export var weaknesses: Array[int] = []
@export var resistances: Array[int] = []
@export var immunities: Array[int] = []


## One-line description for lists, e.g. "Rex - HP 20, Lv 1" (generic type
## name when no custom name is set).
func summary() -> String:
	var shown := custom_name if custom_name != "" else str(MonsterDisplay.find_monster(folder).get("name", folder))
	return "%s - HP %d, Lv %d, Def %d" % [shown, hitpoints, level, defense]
