extends Node3D

## Root script for the Player scene. Expected scene layout:
##   MissionPlayer (Node3D, this script)
##    |- LayeredMap (Node3D with LayeredMap.gd, same Floor/PropGridMap
##    |   setup as the Creator - marked as Unique Name %LayeredMap)
##    |- UI (CanvasLayer or Control, containing at least a Label marked
##        %InfoLabel and a "Back" Button)
##
## Now implements the basic round loop (see claude.md's Story layer
## section for the full RoundCheckpoint.Checkpoint design) - Player phase,
## a manual "all players done" signal, Darkness phase, and back. Every
## checkpoint transition now actually fires triggers/checks objectives via
## MissionRuntime (see _advance_to() below) - still intentionally minimal
## in other ways: no actual movement/LOS, no monster AI. Darkness phase is
## a flat timed pause standing in for real world-effect resolution.

@export var menu_scene_path: String = "res://ui/MainMenu.tscn"  ## <<< set to your actual menu scene
@export var darkness_phase_duration: float = 5.0  ## placeholder until real trigger/effect resolution exists

@onready var layered_map: LayeredMap = %LayeredMap
@onready var info_label: Label = %InfoLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var phase_label: Label = %PhaseLabel
@onready var end_phase_button: Button = %EndPhaseButton
@onready var darkness_overlay: ColorRect = %DarknessOverlay
@onready var dialog: PlayerDialog = %Dialog
@onready var embark_dialog: EmbarkDialog = %Embark
@onready var interaction_dock: PlayerInteractionController = %InteractionDock
@onready var camera: FreeLookCamera = $Camera3D  ## a direct child, not nested under CanvasLayer - no unique name needed, see _frame_camera_on_spawn_area()

## Minimum jump_to() distance for framing the spawn area (see
## _frame_camera_on_spawn_area()) - broader than FreeLookCamera.jump_to()'s
## own default (12.0), which otherwise leaves the camera sitting too close
## to actually see where the spawn area is relative to the rest of the map.
const SPAWN_VIEW_MIN_DISTANCE: float = 20.0
## How far past the spawn area's own bounding radius to pull the camera
## back - scales the view out further for a larger authored spawn area
## rather than using one fixed distance regardless of size.
const SPAWN_VIEW_RADIUS_MULTIPLIER: float = 2.2

var mission: MissionData
var current_round: int = 1
var current_checkpoint: RoundCheckpoint.Checkpoint = RoundCheckpoint.Checkpoint.NONE
var _runtime: MissionRuntime
## Which HeroCatalog slot each player number maps to, in player-number order
## - set once by EmbarkDialog at the start of _ready(), see that class and
## PlayerInteractionController.set_roster(). Player count is just this
## array's size - there's no separate tracked count.
var player_roster: Array[int] = []


func _ready() -> void:
	mission = MissionIO.load_mission(GameState.current_mission_path)
	if mission == null:
		info_label.text = "Failed to load mission: %s" % GameState.current_mission_path
		return

	layered_map.apply_mission(mission, true)

	var display_name := mission.mission_name if mission.mission_name != "" else GameState.current_mission_path.get_file()
	info_label.text = "%s  (tiles=%d, interactables=%d, underlays=%d)" % [display_name, mission.tiles.size(), mission.interactables.size(), mission.underlay_placements.size()]

	# Embark comes before anything else - the table picks its party before
	# there's any board state to interact with. Defines player count (the
	# roster's size) and which character is player 1/2/3/... - equipment
	# selection is explicitly deferred, see EmbarkDialog's own docstring.
	player_roster = await embark_dialog.ask_roster(mission)
	interaction_dock.set_roster(player_roster)

	_runtime = MissionRuntime.new(mission)
	_runtime.sync_builtins(current_round, player_roster.size())
	interaction_dock.mission_runtime = _runtime
	interaction_dock.game_over_requested.connect(_on_game_over_requested)
	interaction_dock.objectives_progressed.connect(_on_objectives_progressed)
	_refresh_objective_label()

	# Before players are placed, tell the table what physical pieces the
	# starting room needs and reveal it - see show_stage(). Whichever
	# group contains the tile under a player_spawn_cells entry, found via
	# MissionData.find_starting_group_ids(); a mission with no groups
	# authored (or no group under its spawn cells) contributes nothing
	# here, same as before this feature existed.
	for group_id in mission.find_starting_group_ids():
		await show_stage(group_id)

	# Round 1's first entry into Player phase IS "players spawn" - the app
	# doesn't track real player positions (see claude.md's Story layer
	# section), so there's no digital spawn step beyond this: highlight the
	# authored starting area (if any), wait for confirmation, then remove
	# it - players place their tokens on it themselves.
	if not await _advance_to(RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE):
		return
	await _show_spawn_area_and_confirm()
	await _enter_player_phase()


## No-op if the mission doesn't have a spawn area authored - not every
## mission needs this yet (see MissionData.player_spawn_cells).
func _show_spawn_area_and_confirm() -> void:
	if mission.player_spawn_cells.is_empty():
		return
	layered_map.set_spawn_overlay_cells(mission.player_spawn_cells)
	layered_map.set_spawn_overlay_visible(true)
	_frame_camera_on_spawn_area()
	await dialog.ask_ok("Place your player figures in the highlighted area, then confirm.")
	layered_map.set_spawn_overlay_visible(false)


## The scene's own starting Camera3D transform is just wherever it happened
## to be left in the editor - fine once the table is actually playing (free
## look takes over from there), but it can easily leave the spawn area out
## of frame entirely, or sitting too close to tell where it actually is
## relative to the rest of the map. Jumps to the spawn cells' own centroid
## instead, with a distance scaled to the spawn area's bounding radius (not
## a single fixed distance regardless of size) so a small authored area
## doesn't get an unnecessarily distant view and a large one still fits.
func _frame_camera_on_spawn_area() -> void:
	var corners: Array[Vector3] = []
	for cell in mission.player_spawn_cells:
		corners.append_array(layered_map.get_tile_square_world_corners(cell))
	if corners.is_empty():
		return

	var centroid := Vector3.ZERO
	for corner in corners:
		centroid += corner
	centroid /= corners.size()

	var radius := 0.0
	for corner in corners:
		radius = max(radius, corner.distance_to(centroid))

	camera.jump_to(centroid, max(SPAWN_VIEW_MIN_DISTANCE, radius * SPAWN_VIEW_RADIUS_MULTIPLIER))


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(menu_scene_path)


## Shows only the CURRENTLY ACTIVE objective node(s)' descriptions, via
## MissionRuntime.get_current_objective_descriptions() - NOT mission's full
## DAG. Used to read mission.objectives (the DAG's static roots) directly
## and show every root's description unconditionally, which spoiled any
## branch/leaf the players hadn't actually reached yet. Re-called after
## every checkpoint transition (_advance_to()) and every prop action
## (PlayerInteractionController.objectives_progressed) since either can
## advance the DAG frontier mid-game, not just once at mission start.
func _refresh_objective_label() -> void:
	var descriptions := _runtime.get_current_objective_descriptions()
	objective_label.text = "Objective: %s" % ", ".join(descriptions) if not descriptions.is_empty() else ""


## Reveals a MissionGroup as part of play - the "Show Stage" effect (see
## Effect.Type.SHOW_STAGE and MissionRuntime.apply_effect()). Used both
## automatically at game start (for the starting room, see _ready() above)
## and for an authored Show Stage effect firing mid-game (see
## drain_pending_stage_reveals() calls below) - one mechanism, not a
## special case either way. Idempotent: a group already visible (already
## revealed) is a silent no-op, so a duplicate starting-group id or a
## re-fired trigger can't show the setup dialog twice.
func show_stage(group_id: String) -> void:
	var group := _find_group(group_id)
	if group == null or group.visible:
		return
	# Flip FIRST - MissionData.is_effectively_visible()'s ancestor walk
	# needs to see this group as visible when get_stage_requirements()
	# below checks this group's own (now-reachable) descendants.
	group.visible = true
	var pages := _format_stage_pages(group, mission.get_stage_requirements(group_id))
	if not pages.is_empty():
		await dialog.ask_narrative(pages)
	layered_map.repaint_visible_entries()


func _find_group(group_id: String) -> MissionGroup:
	for group in mission.groups:
		if group.id == group_id:
			return group
	return null


## One narrative page per non-empty requirement bucket, floor -> pillar ->
## prop -> hazard order (see MissionData.get_stage_requirements()) -
## dialog.ask_narrative() (PlayerDialog.gd) already exists for exactly
## this and has never had a real caller until now.
func _format_stage_pages(group: MissionGroup, requirements: Dictionary) -> Array[String]:
	var stage_name := group.reference_name if group.reference_name != "" else "(unnamed group)"
	var bucket_labels := {"floor": "Floor tiles", "pillar": "Pillars", "prop": "Props", "underlay": "Hazards"}
	var pages: Array[String] = []
	for bucket_key in ["floor", "pillar", "prop", "underlay"]:
		var bucket: Dictionary = requirements.get(bucket_key, {})
		if bucket.is_empty():
			continue
		var lines: Array[String] = []
		for mesh_name in bucket:
			lines.append("%dx %s" % [bucket[mesh_name], mesh_name])
		pages.append("Setting up '%s'\n%s needed:\n%s" % [stage_name, bucket_labels[bucket_key], "\n".join(lines)])
	return pages


func _enter_player_phase() -> void:
	if not await _advance_to(RoundCheckpoint.Checkpoint.PLAYER_PHASE):
		return
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
## player phase. Every checkpoint now actually fires triggers/checks
## objectives via _advance_to(); the loop bails out early (`return`) the
## moment one of those calls reports the game has ended.
func _run_darkness_and_loop() -> void:
	end_phase_button.disabled = true

	if not await _advance_to(RoundCheckpoint.Checkpoint.AFTER_PLAYER_PHASE):
		return

	if not await _advance_to(RoundCheckpoint.Checkpoint.BEFORE_DARKNESS_PHASE):
		return

	if not await _advance_to(RoundCheckpoint.Checkpoint.DARKNESS_PHASE):
		return
	phase_label.text = "Round %d - darkness phase..." % current_round
	darkness_overlay.visible = true
	# Stand-in for real world-effect resolution + monster AI - just proves
	# the phase transition and UI change work before either exists.
	await get_tree().create_timer(darkness_phase_duration).timeout

	if not await _advance_to(RoundCheckpoint.Checkpoint.AFTER_DARKNESS_PHASE):
		return

	current_round += 1
	_runtime.sync_builtins(current_round, player_roster.size())
	if not await _advance_to(RoundCheckpoint.Checkpoint.BEFORE_PLAYER_PHASE):
		return
	await _enter_player_phase()


## Updates current_checkpoint, then hands off to MissionRuntime to fire
## whatever triggers/objectives are due at this checkpoint. If an objective
## fires, shows its outcome and returns to the main menu - callers must
## check the return value and stop advancing the round loop when it's
## false (see _run_darkness_and_loop()). Deliberately NOT a signal
## (objective_reached.emit() + a connected async handler): GDScript signal
## emission only runs a connected handler synchronously up to ITS first
## await, then returns control to the emitter regardless of whether the
## handler finished - the round loop would keep advancing underneath the
## still-open win/loss dialog. A synchronous computation + bool-returning
## coroutine, checked at every call site, has no such race - and it's the
## same "caller awaits and branches on the return value" pattern
## embark_dialog.ask_roster()/dialog.ask_yes_no() already use throughout
## this file.
func _advance_to(checkpoint: RoundCheckpoint.Checkpoint) -> bool:
	current_checkpoint = checkpoint
	var objective := _runtime.evaluate_checkpoint(checkpoint)
	_refresh_objective_label()
	for group_id in _runtime.drain_pending_stage_reveals():
		await show_stage(group_id)
	if objective == null:
		return true
	await _handle_game_over(objective)
	return false


## Shared by both ends of the objectives DAG: the checkpoint-driven path
## above (which needs the synchronous-return-value dance to avoid racing
## the round loop, see _advance_to()'s own comment) and the event-driven
## path (_on_game_over_requested() below, triggered by a PropAction firing
## mid-Player-phase) - a signal is safe there specifically because nothing
## in PlayerInteractionController continues an internal loop afterward
## that would need to wait on this finishing.
func _handle_game_over(objective: MissionObjective) -> void:
	end_phase_button.disabled = true
	var outcome_text := "Victory!" if objective.outcome == MissionObjective.Outcome.WIN else "Defeat."
	await dialog.ask_ok("%s\n%s" % [outcome_text, objective.description])
	get_tree().change_scene_to_file(menu_scene_path)


## PlayerInteractionController.fire_prop_action() can end the game live,
## the instant a player reports finding/doing something - not just at a
## checkpoint boundary (see MissionRuntime.fire_event()'s own doc).
func _on_game_over_requested(objective: MissionObjective) -> void:
	await _handle_game_over(objective)


## A fired PropAction can advance the DAG frontier and/or queue a Show
## Stage reveal without necessarily ending the game (game_over_requested
## alone wouldn't cover either) - refreshes the objective label and drains
## any pending stage reveals the same way _advance_to() does for the
## checkpoint-driven path.
func _on_objectives_progressed() -> void:
	_refresh_objective_label()
	for group_id in _runtime.drain_pending_stage_reveals():
		await show_stage(group_id)
