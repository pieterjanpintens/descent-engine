class_name SaveGame
extends Resource

## A saved Player session. Most of the actual progress lives on `mission`
## itself for free - MissionData is mutated IN PLACE all through play
## (a fired MissionTrigger's already_fired, a used PropAction's
## already_used, a reached MissionObjective's already_achieved, a
## MissionGroup's visible flag once revealed, a removed/moved prop/tile's
## entry - see claude.md's Story layer section for each of these), so
## saving the live mission resource carries all of that across without any
## extra bookkeeping - **but only as a path-less deep COPY** (see
## MissionPlayer.save_game()): the live mission was loaded from a file, and
## ResourceSaver writes any resource that still has a resource_path as an
## external reference to that file instead of embedding it, which silently
## dropped every bit of that progress on load. This resource only adds what genuinely lives OUTSIDE
## the mission: round/checkpoint, the chosen party, and MissionRuntime's own
## ephemeral state (custom variable values, the monster registry, which
## DAG branch is currently active) - plus the quest log, which is already
## nothing more than a plain list (Journal.entries), so it's carried as-is.
##
## MissionIO.save_game()/load_game() write/read this the same way
## MissionData itself is saved - see that class's own doc.

@export var mission: MissionData
@export var current_round: int = 1
@export var current_checkpoint: int = 0  ## RoundCheckpoint.Checkpoint, stored as a plain int
@export var player_roster: Array[int] = []
@export var player_weapons: Dictionary = {}  ## hero slot -> Array[Weapon]
@export var runtime_variables: Dictionary = {}  ## MissionRuntime.get_variables_state()
@export var hero_wounds: Dictionary = {}  ## MissionRuntime.hero_wounds (hero slot -> wounds)
@export var hero_times_targeted: Dictionary = {}  ## MissionRuntime.hero_times_targeted
@export var hero_attacks_made: Dictionary = {}  ## MissionRuntime.hero_attacks_made (hero slot -> attacks made)
@export var monsters: Array[Dictionary] = []  ## RuntimeMonster.to_dict() per live monster
@export var current_objective_ids: Array = []  ## Array[Array[String]] - MissionObjective.id per watched candidate group
@export var journal_entries: Array[Dictionary] = []  ## Journal.entries, verbatim
@export var saved_at: String = ""  ## for the load picker/display only
