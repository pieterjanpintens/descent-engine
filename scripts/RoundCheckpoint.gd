class_name RoundCheckpoint
extends RefCounted

## Never instantiated - just a shared namespace for the Checkpoint enum so
## MissionTrigger and MissionObjective can both reference it without one
## depending on the other.
##
## The six points in the round loop a checkpoint-driven MissionTrigger or
## MissionObjective can be evaluated at:
##   Before player phase -> Player phase -> After player phase ->
##   Before darkness phase -> Darkness phase -> After darkness phase -> loop
## Darkness phase itself is mostly hardcoded monster AI, not condition/effect
## driven - it's listed here mainly so "before"/"after" have something to
## bracket. NONE means "not checkpoint-driven" - see MissionTrigger.event_id
## for the event-driven alternative (e.g. a player reporting a prop action
## live during Player phase, rather than waiting for a fixed checkpoint).
enum Checkpoint {
	NONE,
	BEFORE_PLAYER_PHASE,
	PLAYER_PHASE,
	AFTER_PLAYER_PHASE,
	BEFORE_DARKNESS_PHASE,
	DARKNESS_PHASE,
	AFTER_DARKNESS_PHASE,
}
