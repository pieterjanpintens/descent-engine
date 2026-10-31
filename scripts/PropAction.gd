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
##
## `single_shot`/`already_used` (new 2026-09-14) - same one_shot/
## already_fired shape as MissionTrigger, but deliberately a SEPARATE gate
## from `conditions` above rather than folded into it: `conditions` is
## author-defined state ("is the chest already searched"), this is
## intrinsic "has this specific action already fired" runtime bookkeeping,
## same distinction MissionTrigger already draws between its own
## `conditions` and `one_shot`/`already_fired`. Unlike `conditions` (which
## removes an action from every candidate list the moment it stops
## holding), an exhausted single-shot action still appears in
## MissionRuntime.available_actions() - PlayerInteractionController's
## picker shows it with its button disabled rather than hiding it, so the
## player can see it's been used. MissionRuntime.first_available_action()
## (the cheap existence check gating hover-highlight) DOES skip it, same
## as an action whose conditions don't hold - if every action on a prop is
## either condition-gated-off or an exhausted single-shot, the prop reads
## as not currently interactable at all. Defaults `false` (unlike
## MissionTrigger.one_shot's `true` default) - most prop actions (push,
## search, talk) are naturally repeatable; single-shot is an opt-in for
## the ones that aren't (e.g. opening a door that then removes itself via
## Effect.Type.REMOVE_OBJECT).
@export var single_shot: bool = false
## Applies by itself when a hero interacts with the prop: no choice dialog, the effects just happen (an exploration
## token). The app does not detect anyone walking next to it - the table drags the hero onto the prop as always.
@export var auto_apply: bool = false
@export var already_used: bool = false

@export var action_id: String = ""    ## short, stable id for triggers - e.g. "push" (not shown to the player)
## What the table sees as the thing to activate, and what voice control listens for - e.g. "Push the lever". Empty = the description is
## the choice itself (how actions without a name used to look).
@export var action_name_texts: Dictionary = {}
var action_name: String:
	get:
		return LText.pick(action_name_texts)
	set(value):
		LText.put(action_name_texts, value)
@export var description_texts: Dictionary = {} ## shown to the player - e.g. "You can push this lever"
var description: String:
	get:
		return LText.pick(description_texts)
	set(value):
		LText.put(description_texts, value)
@export var conditions: Array[Condition] = []  ## implicit AND - whether this action is currently offered
@export var effects: Array[Effect] = []
