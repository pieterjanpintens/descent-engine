class_name MonsterSpawn
extends Resource

@export var monster_type: String = ""
@export var group_id: String = ""
@export var cell: Vector3i = Vector3i.ZERO
@export var facing: int = 0            ## 0-3, quarter turns
@export var starts_hidden: bool = false
@export var activation_trigger_id: String = ""  ## empty = present from mission start
