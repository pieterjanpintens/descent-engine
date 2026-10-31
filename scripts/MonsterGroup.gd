class_name MonsterGroup
extends Resource

## A named, reusable list of monsters of a mission (MissionData.monster_groups). Several "Spawn Monsters" effects can point at the same group
## (Effect.spawn_group_id), each at its own MonsterSpawn, so the same encounter can appear in two places without being built twice - and an edit
## to the group changes all of them. An effect uses EITHER its own list (Effect.spawn_monsters) OR one group, never both.
## The monsters are in spawn-tile order like an effect's own list: the first goes on tile 1 of the spawn it is used with.

@export var id: String = ""
@export var group_name: String = ""
@export var monsters: Array[MonsterTemplate] = []


func display_name() -> String:
	return group_name if group_name != "" else id
