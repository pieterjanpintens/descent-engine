class_name MissionTrigger
extends Resource

## Watches for something happening - a round-loop checkpoint, or a named
## event - and fires a list of Effects when its Conditions all hold.
##
## Reworked from an earlier version built around a fixed TriggerType enum
## (ON_ENTER_REGION/ON_DOOR_OPENED/ON_MONSTER_GROUP_DEFEATED/ON_INTERACT/
## ON_MANUAL) and a free-text effect_notes field - that's replaced by the
## Condition/Effect language shared with MissionObjective, so any future
## improvement to conditions/effects (nesting, cross-object queries, ...)
## benefits both at once instead of needing two parallel systems. What the
## old enum's cases become here: ON_INTERACT is event_id matching a
## PropAction's action_id; ON_ENTER_REGION/ON_DOOR_OPENED/
## ON_MONSTER_GROUP_DEFEATED become a Condition against whatever variable
## tracks that state once region/door/monster tracking exists; ON_MANUAL is
## just checkpoint == NONE with an author-chosen event_id fired by hand.

@export var id: String = ""

## NONE if this trigger is event-driven instead (see event_id below) -
## otherwise one of the six round-loop checkpoints. A trigger is one or the
## other, never both: exactly one of checkpoint/event_id should be set.
@export var checkpoint: RoundCheckpoint.Checkpoint = RoundCheckpoint.Checkpoint.NONE

## Non-empty = event-driven: fires live the instant this event happens,
## instead of waiting for a checkpoint. Currently the only event source is a
## PropAction's action_id (a player reporting they did something), but the
## same mechanism will cover "a player dies"/"a monster dies" and similar
## once those exist - see the game-flow discussion this system came from.
@export var event_id: String = ""

@export var conditions: Array[Condition] = []  ## implicit AND across all entries
@export var effects: Array[Effect] = []

## Tie-break among triggers sharing the same checkpoint or event_id - lower
## fires first. Matters when one trigger's effect writes a variable another
## trigger's condition (at that same checkpoint/event) depends on.
@export var priority: int = 0

@export var one_shot: bool = true
@export var already_fired: bool = false
