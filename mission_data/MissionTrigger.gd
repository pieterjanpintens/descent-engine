class_name MissionTrigger
extends Resource

enum TriggerType {
	ON_ENTER_REGION,
	ON_DOOR_OPENED,
	ON_MONSTER_GROUP_DEFEATED,
	ON_INTERACT,
	ON_MANUAL,   ## fired by narration/app step rather than a player action
}

@export var id: String = ""
@export var type: TriggerType = TriggerType.ON_ENTER_REGION
@export var region_id: String = ""
@export var source_id: String = ""     ## door id / monster group id / interactable id, depending on type
@export var one_shot: bool = true
@export var already_fired: bool = false
@export var effect_notes: String = ""  ## human-readable for now; formal effect system comes later
