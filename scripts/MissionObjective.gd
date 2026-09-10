class_name MissionObjective
extends Resource

## A win OR loss condition, checked at a specific round-loop checkpoint (see
## RoundCheckpoint.Checkpoint). Folding win and loss into one resource is
## deliberate: "round counter exceeded N" and "the final goal is achieved"
## are the exact same shape - a checkpoint plus a set of conditions - just
## opposite outcomes. MissionData.objectives is evaluated in priority order
## at each objective's checkpoint; the first one whose conditions all hold
## ends the game with that outcome.
##
## Some conditions can't be computed automatically - the app never sees
## real player positions on the physical board, so e.g. "is a player on
## tile 2a" has to be posed to the table as a yes/no question instead. That
## doesn't need a different Condition shape: the answer just gets written
## into a MissionVariable the normal way (by whatever UI poses the
## question), and the objective's condition reads it like any other
## variable - "asked" is a source a variable's value can come from, not a
## separate kind of condition.

enum Outcome {
	WIN,
	LOSE,
}

@export var id: String = ""
@export var description: String = ""
@export var outcome: Outcome = Outcome.WIN
@export var checkpoint: RoundCheckpoint.Checkpoint = RoundCheckpoint.Checkpoint.AFTER_DARKNESS_PHASE
@export var conditions: Array[Condition] = []  ## implicit AND across all entries

## Tie-break when multiple objectives share a checkpoint - lower is
## evaluated first, same convention as MissionTrigger.priority.
@export var priority: int = 0
