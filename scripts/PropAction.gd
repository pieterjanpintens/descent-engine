class_name PropAction
extends Resource

## One thing a player can DO to a prop - push a lever, search a bookshelf.
## Reported through the app during Player phase, since the app never sees
## player positions/actions on the physical board directly (see
## InteractableEntry.actions) - firing an action applies every one of its
## effects immediately. This is the event-driven half of the trigger system:
## a MissionTrigger with event_id == this action's action_id fires live the
## moment it's reported, rather than waiting for a round-loop checkpoint.
##
## `conditions` (new 2026-09-14) gates whether this action is currently
## OFFERED at all - implicit AND, empty = always available, same
## convention as every other conditions list in this project. Checked via
## MissionRuntime.first_available_action() - PlayerInteractionController
## only highlights/fires an action whose conditions currently hold, so a
## prop can offer different actions (or none) depending on runtime state,
## e.g. "search" only while `chest.searched` is false. This is a separate,
## automatic mechanism from InteractableEntry.props["interactible"] (a
## manual designer on/off switch for the WHOLE prop) - both apply
## together, conditions just add finer-grained, state-driven control per
## action.

@export var action_id: String = ""    ## short, stable id - e.g. "push"
@export var description: String = "" ## shown to the player - e.g. "You can push this lever"
@export var conditions: Array[Condition] = []  ## implicit AND - whether this action is currently offered
@export var effects: Array[Effect] = []
