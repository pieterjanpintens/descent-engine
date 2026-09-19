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


## One-line description for lists, e.g. "Rex - HP 20, Lv 1" (generic type
## name when no custom name is set).
func summary() -> String:
	var shown := custom_name if custom_name != "" else str(MonsterDisplay.find_monster(folder).get("name", folder))
	return "%s - HP %d, Lv %d" % [shown, hitpoints, level]
