class_name PropAction
extends Resource

## One thing a player can DO to a prop - push a lever, search a bookshelf.
## Reported through the app during Player phase, since the app never sees
## player positions/actions on the physical board directly (see
## InteractableEntry.actions) - firing an action applies every one of its
## effects immediately. This is the event-driven half of the trigger system:
## a MissionTrigger with event_id == this action's action_id fires live the
## moment it's reported, rather than waiting for a round-loop checkpoint.

@export var action_id: String = ""    ## short, stable id - e.g. "push"
@export var description: String = "" ## shown to the player - e.g. "You can push this lever"
@export var effects: Array[Effect] = []
