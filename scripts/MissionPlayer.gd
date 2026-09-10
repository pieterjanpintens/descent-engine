extends Node3D

## Root script for the Player scene. Expected scene layout:
##   MissionPlayer (Node3D, this script)
##    |- LayeredMap (Node3D with LayeredMap.gd, same Floor/Wall/PropGridMap
##    |   setup as the Creator - marked as Unique Name %LayeredMap)
##    |- UI (CanvasLayer or Control, containing at least a Label marked
##        %InfoLabel and a "Back" Button)
##
## Now implements the basic round loop (see claude.md's Story layer
## section for the full RoundCheckpoint.Checkpoint design) - Player phase,
## a manual "all players done" signal, Darkness phase, and back. Still
## intentionally minimal: no actual movement/LOS, no trigger/objective
## evaluation at any checkpoint yet (those hooks are commented where they'll
## go), no monster AI. Darkness phase is a flat timed pause standing in for
## real world-effect resolution.

@export var menu_scene_path: String = "res://ui/MainMenu.tscn"  ## <<< set to your actual menu scene
@export var darkness_phase_duration: float = 5.0  ## placeholder until real trigger/effect resolution exists

@onready var layered_map: LayeredMap = %LayeredMap
@onready var info_label: Label = %InfoLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var phase_label: Label = %PhaseLabel
@onready var end_phase_button: Button = %EndPhaseButton
@onready var darkness_overlay: ColorRect = %DarknessOverlay
@onready var dialog: PlayerDialog = %Dialog

var mission: MissionData
var current_round: int = 1
var current_checkpoint: RoundCheckpoint.Checkpoint = RoundCheckpoint.Checkpoint.NONE


func _ready() -> void:
	mission = MissionIO.load_mission(GameState.current_mission_path)
	if mission == null:
		info_label.text = "Failed to load mission: %s" % GameState.current_mission_path
		return

	layered_map.apply_mission(mission)

	var display_name := mission.mission_name if mission.mission_name != "" else GameState.current_mission_path.get_file()
	info_label.text = "%s  (tiles=%d, interactables=%d, underlays=%d)" % [display_name, mission.tiles.size(), mission.interactables.size(), mission.underlay_placements.size()]

	_show_objective()

	# Round 1's first entry into Player phase IS "players spawn" - the app
	# doesn't track real player positions (see claude.md's Story layer
	# section), so there's no digital spawn step beyond this: highlight the
	# authored starting area (if any), wait for confirmation, then remove
	# it - players place their tokens on it themselves.
	_set_checkpoint(RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE)
	# (future: fire BEFORE_PLAYER_PHASE triggers here)
	await _show_spawn_area_and_confirm()
	_enter_player_phase()


## No-op if the mission doesn't have a spawn area authored - not every
## mission needs this yet (see MissionData.player_spawn_cells).
func _show_spawn_area_and_confirm() -> void:
	if mission.player_spawn_cells.is_empty():
		return
	layered_map.set_spawn_overlay_cells(mission.player_spawn_cells)
	layered_map.set_spawn_overlay_visible(true)
	await dialog.ask_ok("Place your player figures in the highlighted area, then confirm.")
	layered_map.set_spawn_overlay_visible(false)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(menu_scene_path)


func _show_objective() -> void:
	for objective in mission.objectives:
		if objective.outcome == MissionObjective.Outcome.WIN:
			objective_label.text = "Objective: %s" % objective.description
			return
	objective_label.text = ""  # nothing authored yet


func _enter_player_phase() -> void:
	_set_checkpoint(RoundCheckpoint.Checkpoint.PLAYER_PHASE)
	if current_round == 1:
		phase_label.text = "Round 1 - players spawn. Place your tokens, then play."
	else:
		phase_label.text = "Round %d - player phase" % current_round
	darkness_overlay.visible = false
	end_phase_button.disabled = false


func _on_end_phase_button_pressed() -> void:
	_run_darkness_and_loop()


## Walks every remaining checkpoint for this round - after player phase,
## darkness itself, then after darkness - before looping back to a fresh
## player phase. Most of these are no-ops right now (commented where a
## future trigger/objective evaluation pass will hook in); the point is the
## loop itself is real and complete, not just the two visible phases.
func _run_darkness_and_loop() -> void:
	end_phase_button.disabled = true

	_set_checkpoint(RoundCheckpoint.Checkpoint.AFTER_PLAYER_PHASE)
	# (future: fire AFTER_PLAYER_PHASE triggers/objective checks here)

	_set_checkpoint(RoundCheckpoint.Checkpoint.BEFORE_DARKNESS_PHASE)
	# (future: fire BEFORE_DARKNESS_PHASE triggers here)

	_set_checkpoint(RoundCheckpoint.Checkpoint.DARKNESS_PHASE)
	phase_label.text = "Round %d - darkness phase..." % current_round
	darkness_overlay.visible = true
	# Stand-in for real world-effect resolution + monster AI - just proves
	# the phase transition and UI change work before either exists.
	await get_tree().create_timer(darkness_phase_duration).timeout

	_set_checkpoint(RoundCheckpoint.Checkpoint.AFTER_DARKNESS_PHASE)
	# (future: win/loss MissionObjective check happens here - first
	# objective in priority order whose conditions hold at this checkpoint
	# ends the game with its outcome)

	current_round += 1
	_set_checkpoint(RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE)
	# (future: fire BEFORE_PLAYER_PHASE triggers here)
	_enter_player_phase()


func _set_checkpoint(checkpoint: RoundCheckpoint.Checkpoint) -> void:
	current_checkpoint = checkpoint
