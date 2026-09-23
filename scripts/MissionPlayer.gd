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
@onready var objective_label: RichTextLabel = %ObjectiveLabel  ## RichTextLabel (was Label) - _refresh_objective_label() needs two-colour BBCode text, see PlayerHud.gd's own class doc for the surrounding layout this is part of
@onready var phase_label: Label = %PhaseLabel
@onready var end_phase_button: Button = %EndPhaseButton
var hud: PlayerHud
@onready var darkness_overlay: ColorRect = %DarknessOverlay
@onready var dialog: PlayerDialog = %Dialog
@onready var embark_dialog: EmbarkDialog = %Embark
@onready var interaction_dock: PlayerInteractionController = %InteractionDock
@onready var camera: FreeLookCamera = $Camera3D  ## a direct child, not nested under CanvasLayer - no unique name needed, see _frame_camera_on_spawn_area()
@onready var monster_display: MonsterDisplay = %MonsterDisplay

## Minimum jump_to() distance for framing the spawn area (see
## _frame_camera_on_spawn_area()) - broader than FreeLookCamera.jump_to()'s
## own default (12.0), which otherwise leaves the camera sitting too close
## to actually see where the spawn area is relative to the rest of the map.
## Size of the figures shown on the map when monsters spawn, relative to the
## M-view stand size (see _run_monster_spawn()).
const SPAWN_FIGURE_SCALE: float = 2.75
const SPAWN_VIEW_MIN_DISTANCE: float = 30.0
## How far past the spawn area's own bounding radius to pull the camera
## back - scales the view out further for a larger authored spawn area
## rather than using one fixed distance regardless of size.
const SPAWN_VIEW_RADIUS_MULTIPLIER: float = 3.0

var mission: MissionData
var current_round: int = 1
var current_checkpoint: RoundCheckpoint.Checkpoint = RoundCheckpoint.Checkpoint.NONE
var _runtime: MissionRuntime
## Which HeroCatalog slot each player number maps to, in player-number order
## - set once by EmbarkDialog at the start of _ready(), see that class and
## PlayerInteractionController.set_roster(). Player count is just this
## array's size - there's no separate tracked count.
var player_roster: Array[int] = []
## {hero slot index: Array[Weapon]} - the two weapons each hero picked at embark.
var player_weapons: Dictionary = {}
var _command_runner: PlayerCommandRunner
var interaction_labels: InteractionLabels  ## names of the currently interactable props


func _ready() -> void:
	info_label.visible = false  # was a debug overlay (tile/interactable/underlay counts) - kept only for the load-failure message below
	# Genuinely disabled, not just hidden - until _enter_player_phase() first
	# runs (after embark + initial player positioning), so neither a click
	# nor the voice/typed "end phase" command (_voice_end_phase(), which
	# only checks .disabled) can skip straight to darkness phase before the
	# table has even placed their figures.
	end_phase_button.visible = false
	end_phase_button.disabled = true
	objective_label.visible = false  # shown again once _show_spawn_area_and_confirm() closes, below

	mission = MissionIO.load_mission(GameState.current_mission_path)
	if mission == null:
		info_label.text = "Failed to load mission: %s" % GameState.current_mission_path
		info_label.visible = true
		return

	layered_map.apply_mission(mission, true)
	_style_end_phase_button()

	# New HUD chrome (Quest/Threat icons top-right, Gear/Party menus
	# bottom-left - see PlayerHud.gd's own class doc) - added early so
	# it's present under the embark/spawn modal scrims exactly like every
	# other CanvasLayer child already is, not gated behind player phase the
	# way EndPhaseButton is above (nothing here can skip a phase early, so
	# there's no equivalent risk to guard against).
	hud = PlayerHud.new()
	dialog.get_parent().add_child(hud)
	dialog.get_parent().move_child(hud, 0)
	hud.dialog = dialog
	hud.back_to_menu = _on_back_button_pressed
	hud.show_map = _set_monster_display_visible.bind(false)
	hud.show_monsters = _set_monster_display_visible.bind(true)

	# Embark comes before anything else - the table picks its party before
	# there's any board state to interact with. Defines player count (the
	# roster's size) and which character is player 1/2/3/... - equipment
	# selection is explicitly deferred, see EmbarkDialog's own docstring.
	player_roster = await embark_dialog.ask_roster(mission)
	player_weapons = await embark_dialog.ask_loadouts(player_roster)
	interaction_dock.set_roster(player_roster)
	interaction_dock.hero_weapons = player_weapons

	_runtime = MissionRuntime.new(mission)
	_runtime.sync_builtins(current_round, player_roster.size())
	_runtime.dialog = dialog
	_runtime.monsters_changed.connect(func(): monster_display.refresh_monsters(_runtime.monsters))
	interaction_dock.mission_runtime = _runtime
	interaction_dock.monster_display = monster_display

	# Name labels over everything a hero can interact with right now (parented
	# to layered_map, so they hide with the world in the M monster view).
	interaction_labels = InteractionLabels.new()
	interaction_labels.layered_map = layered_map
	interaction_labels.runtime = _runtime
	layered_map.add_child(interaction_labels)

	# Typed commands ("attack green bandit") - the stand-in for voice control,
	# see VoiceCommandParser/PlayerCommandRunner.
	_command_runner = PlayerCommandRunner.new()
	_command_runner.runtime = _runtime
	_command_runner.dock = interaction_dock
	_command_runner.dialog = dialog
	_command_runner.roster = player_roster
	_command_runner.labels = interaction_labels
	_command_runner.end_phase = _voice_end_phase
	_command_runner.set_monster_view = _set_monster_display_visible
	var command_input := CommandInput.new()
	dialog.get_parent().add_child(command_input)
	dialog.get_parent().move_child(command_input, dialog.get_index())  # keep the modal dialog above it
	command_input.command_entered.connect(_command_runner.run)

	# Hands-free: "hey DM, attack green bandit" through the microphone (needs
	# the Godot Whisper addon, see VoiceListener; otherwise just a status line).
	var voice_listener := VoiceListener.new()
	dialog.get_parent().add_child(voice_listener)
	dialog.get_parent().move_child(voice_listener, dialog.get_index())
	voice_listener.command_heard.connect(_command_runner.run)
	voice_listener.vocabulary_provider = interaction_labels.spoken_names  # object names help recognition
	voice_listener.monster_name_provider = func() -> Array:
		var names: Array = []
		for monster in _runtime.monsters:
			if monster.custom_name != "" and not names.has(monster.custom_name):
				names.append(monster.custom_name)
		return names
	voice_listener.weapon_name_provider = func() -> Array:
		var names: Array = []
		for weapons: Array in player_weapons.values():
			for weapon: Weapon in weapons:
				if not names.has(weapon.weapon_name):
					names.append(weapon.weapon_name)
		return names
	voice_listener.context_prompt_provider = dialog.voice_prompt
	voice_listener.dialog_open_provider = func() -> bool: return dialog.visible  # skip "hey DM" while answering a dialog

	# Voice SETUP UI (Enable checkbox, "Show voice hints", device/mode, the
	# download button) now lives in its own dialog, opened from the Gear
	# menu's "Options" - see VoiceSettingsDialog.gd's own class doc for the
	# VoiceListener/dialog split. It now owns every write to
	# dialog.voice_hints_enabled itself (combining is_enabled() with its own
	# "Show voice hints" checkbox), so voice_ready connects to IT instead of
	# writing to dialog directly here.
	var voice_settings := VoiceSettingsDialog.new()
	dialog.get_parent().add_child(voice_settings)
	voice_settings.voice_listener = voice_listener
	voice_settings.dialog = dialog
	voice_listener.voice_ready.connect(func(_ready: bool): voice_settings._update_dialog_hints())
	hud.open_voice_settings = voice_settings.open

	voice_listener.start()
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
	objective_label.visible = true
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


## MOVE_OBJECT: the authored target is a tile-square coordinate. For a
## single-tile-square piece the origin cell is a pivot on the tile's far
## corner, so a rotated piece's origin is shifted (see
## FootprintRegistry.origin_shift_1x1()) - apply the same shift here so the
## piece lands IN the target tile, exactly like placing/moving it in the
## Creator does, rather than swinging into a neighbouring tile.
func _apply_object_move(move: Dictionary) -> void:
	var node := mission.find_node_by_id(move["id"])
	if node == null:
		push_warning("MOVE_OBJECT references an unknown object '%s' - skipped" % move["id"])
		return
	var target := FootprintRegistry.tile_square_to_fine_far_corner(move["cell"])
	var origin: Vector3i = node.get("origin_cell")
	var mesh_name: String = str(node.get("mesh_item_name"))
	var grid: GridMap = layered_map.prop_grid
	if node is TilePlacement:
		grid = layered_map.floor_grid if (node as TilePlacement).layer == TilePlacement.Layer.FLOOR else layered_map.underlay_grid
	var shift := FootprintRegistry.origin_shift_1x1(mesh_name, grid.get_cell_item_basis(origin))
	layered_map.move_node(move["id"], target - shift)


## SPAWN_MONSTERS effect, in two steps: (1) tell the table which monsters
## to take out of the box (grouped, e.g. "2x Wolf"), then (2) show those
## monsters as figures on the map at their spawn tiles - monster N on tile
## N of the MonsterSpawn, so the tile positions themselves are never
## revealed, only the figures - with an OK button to confirm they've been
## placed. A 2x2 monster (size_units 2, the Centurion) uses its tile as its
## far corner and covers the tiles toward -X/-Z (FootprintRegistry's
## footprint convention). Monsters beyond the spawn's tile count are listed
## as having no free tile.
func _run_monster_spawn(request: Dictionary) -> void:
	var spawn := mission.find_node_by_id(request["spawn_id"]) as MonsterSpawn
	if spawn == null:
		push_warning("SPAWN_MONSTERS references an unknown monster spawn '%s' - skipped" % request["spawn_id"])
		return
	var templates: Array = request["monsters"]
	if templates.is_empty():
		return

	# Register every spawned monster first (random colour chip, see
	# MissionRuntime.register_monster()) - the dialogs below tell the table
	# which chip goes on which figure. A monster with no valid chip left is
	# not registered/placed.
	var spawned: Array[RuntimeMonster] = []
	var no_chip: Array[String] = []
	for template: MonsterTemplate in templates:
		if MonsterDisplay.find_monster(template.folder).is_empty():
			push_warning("SPAWN_MONSTERS lists unknown monster '%s' - skipped" % template.folder)
			continue
		var registered := _runtime.register_monster(template)
		if registered == null:
			no_chip.append(MonsterDisplay.find_monster(template.folder)["name"])
			continue
		spawned.append(registered)
	if spawned.is_empty() and no_chip.is_empty():
		return

	# Step 1 - what to take out of the box, one line per monster with its
	# chip colour. Uses the generic TYPE name (Bandit, Zealot, ...) - custom
	# names are story flavour and mean nothing for finding the miniature.
	var lines: Array[String] = ["Take these monsters out of the box:"]
	for monster in spawned:
		lines.append("%s - %s chip" % [MonsterDisplay.find_monster(monster.folder)["name"], MonsterChip.display_name(monster.chip)])
	if not no_chip.is_empty():
		lines.append("No colour chip left for: %s - not spawned." % ", ".join(no_chip))
	await dialog.ask_ok("
".join(lines))
	if spawned.is_empty():
		return

	# Step 2 - figures (with their chips) on the map.
	var tile_corners := layered_map.get_tile_square_world_corners(Vector3i.ZERO)
	var tile_size: float = tile_corners[0].distance_to(tile_corners[1])
	var holder := MonsterDisplay.new()
	holder.standalone = true
	# Sized relative to the M-view stand (a 1-unit base = ~85% of a tile),
	# at 275% of that so the figures - which have no plinth on the map -
	# read clearly (1.5x and 4.5x were tried and judged too small/too big).
	holder.scale = Vector3.ONE * (tile_size * 0.85 * SPAWN_FIGURE_SCALE / MonsterDisplay.BASE_SIZE.x)
	add_child(holder)

	var placed_centers: Array[Vector3] = []
	var unplaced: Array[String] = []
	for i in spawned.size():
		var monster := spawned[i]
		var info := MonsterDisplay.find_monster(monster.folder).duplicate()
		info["name"] = monster.display_name()
		if i >= spawn.cells.size():
			unplaced.append(MonsterDisplay.find_monster(monster.folder)["name"])
			continue
		var size_tiles := int(round(info.get("size_units", 1.0)))
		var anchor := spawn.cells[i]
		var min_corners := layered_map.get_tile_square_world_corners(anchor - Vector3i(size_tiles - 1, 0, size_tiles - 1))
		var max_corners := layered_map.get_tile_square_world_corners(anchor)
		var center := (min_corners[0] + max_corners[2]) * 0.5
		placed_centers.append(center)
		holder.place_stand(center / holder.scale.x, info, i, MonsterChip.color(monster.chip))

	if not placed_centers.is_empty():
		var centroid := Vector3.ZERO
		for c in placed_centers:
			centroid += c
		centroid /= placed_centers.size()
		var radius := 0.0
		for c in placed_centers:
			radius = max(radius, c.distance_to(centroid))
		camera.jump_to(centroid, max(SPAWN_VIEW_MIN_DISTANCE, (radius + tile_size) * SPAWN_VIEW_RADIUS_MULTIPLIER))

	var place_text := "Place the monsters on the map as shown."
	if not unplaced.is_empty():
		place_text += "
No free spawn tile for: %s - place them next to the others." % ", ".join(unplaced)
	await dialog.ask_ok(place_text, false)
	holder.queue_free()


## TEMPORARY - "M" toggles the monster display mockup on/off so it can
## actually be seen in a running Player, since no real combat trigger
## exists yet to switch views on its own (see MonsterDisplay.gd's own doc).
## Remove/replace once something real drives this.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_set_monster_display_visible(not monster_display.visible)


## Swaps which "scene" is rendered while leaving every CanvasLayer UI child
## (InteractionDock, Dialog, labels, buttons, ...) completely untouched -
## they already render independently on top regardless of what's in the 3D
## scene behind them. Only one Camera3D should ever be `current` at a time;
## also pauses whichever FreeLookCamera ISN'T currently shown (both the
## world one and, since 2026-09-16, MonsterDisplay's own) so its _input()
## doesn't react to right-click-drag while off-screen
## (FreeLookCamera._input() fires unconditionally for every node that
## defines it, per claude.md's own Hard-won lessons).
func _set_monster_display_visible(shown: bool) -> void:
	monster_display.visible = shown
	layered_map.visible = not shown
	monster_display.camera.current = shown
	monster_display.camera.set_process_input(shown)
	monster_display.camera.set_process_unhandled_input(shown)
	camera.current = not shown
	camera.set_process_input(not shown)
	camera.set_process_unhandled_input(not shown)


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(menu_scene_path)


## A plain flat red theme for the "End Phase" button (no real art - see
## PlayerHud.gd's own class doc for why nothing here uses copyrighted game
## assets), called once from _ready(). `disabled` gets its own dimmer style
## since Godot's default StyleBoxFlat override doesn't otherwise change look
## on disabled - without this the button would look identically pressable
## while genuinely disabled (see _ready()'s own hiding/disabling of it).
func _style_end_phase_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.55, 0.12, 0.1)
	normal.set_corner_radius_all(6)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.68, 0.16, 0.12)
	hover.set_corner_radius_all(6)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.3, 0.28, 0.27)
	disabled.set_corner_radius_all(6)
	end_phase_button.add_theme_stylebox_override("normal", normal)
	end_phase_button.add_theme_stylebox_override("hover", hover)
	end_phase_button.add_theme_stylebox_override("pressed", hover)
	end_phase_button.add_theme_stylebox_override("disabled", disabled)
	end_phase_button.add_theme_color_override("font_color", Color.WHITE)
	end_phase_button.add_theme_color_override("font_color_disabled", Color(0.7, 0.68, 0.65))


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
	if descriptions.is_empty():
		objective_label.text = ""
		return
	# [lb] escapes a literal "[" - a mission-authored description could
	# otherwise contain one and get misread as a BBCode tag.
	var body := ", ".join(descriptions).replace("[", "[lb]")
	objective_label.text = "[color=#8ecae6][b]Current Objective:[/b][/color]\n%s" % body


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
		phase_label.text = "Players spawn. Place your tokens, then play."
	else:
		phase_label.text = "Player phase"
	darkness_overlay.visible = false
	end_phase_button.visible = true
	end_phase_button.disabled = false


## "End phase" by voice: exactly a press of the End Phase button, so it obeys
## the same rules (it's only enabled in the player phase).
func _voice_end_phase() -> void:
	if end_phase_button.disabled:
		await dialog.ask_ok("The phase can't be ended right now.")
		return
	end_phase_button.pressed.emit()


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
	phase_label.text = "Darkness phase..."
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
	var objective := await _runtime.evaluate_checkpoint(checkpoint)
	_refresh_objective_label()
	for group_id in _runtime.drain_pending_stage_reveals():
		await show_stage(group_id)
	for removed_id in _runtime.drain_pending_object_removals():
		layered_map.remove_node(removed_id)
	for move in _runtime.drain_pending_object_moves():
		_apply_object_move(move)
	for spawn_request in _runtime.drain_pending_monster_spawns():
		await _run_monster_spawn(spawn_request)
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
## Stage reveal, a Remove Object removal, or a Move Object relocation
## without necessarily ending the game (game_over_requested alone wouldn't
## cover any of those) - refreshes the objective label and drains all
## three pending queues the same way _advance_to() does for the
## checkpoint-driven path.
func _on_objectives_progressed() -> void:
	_refresh_objective_label()
	for group_id in _runtime.drain_pending_stage_reveals():
		await show_stage(group_id)
	for removed_id in _runtime.drain_pending_object_removals():
		layered_map.remove_node(removed_id)
	for move in _runtime.drain_pending_object_moves():
		_apply_object_move(move)
	for spawn_request in _runtime.drain_pending_monster_spawns():
		await _run_monster_spawn(spawn_request)
