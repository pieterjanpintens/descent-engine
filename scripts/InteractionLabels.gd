class_name InteractionLabels
extends Node3D

## Floating name labels over the props a hero can currently interact with (an
## exploration token, a lever, a door...), so what can be interacted with - and
## what it is CALLED - is visible on the board. It is the first half of voice
## control for interaction: the names shown here are what will be spoken.
##
## Only props that are interactable right now get a label: not marked
## "interactible" = false, visible (stage revealed), and with at least one
## action whose conditions hold and that isn't an exhausted single-shot
## (MissionRuntime.first_available_action()). The label disappears the moment
## that stops being true (the door opened and was removed, a single-shot action
## was used up...), and follows a prop that gets moved.
##
## The set is re-evaluated a few times a second rather than wired to every
## place state can change (effects, removals, moves, stage reveals, round
## counter, ...) - cheap for a mission's handful of props and can't miss a case.
## Lives under LayeredMap, so it is hidden together with the world in the M
## monster view.
##
## Labels are billboards with no depth test (not hidden behind tall props/
## pillars). Their SIZE depends on the camera distance (see _process()): a
## constant on-screen size while zoomed in, then - past FULL_SIZE_DISTANCE -
## they stop growing in world terms and so shrink as you zoom out (zooming out
## is for an overview of the map, not for reading labels), and fade out
## completely between FADE_START_DISTANCE and HIDE_DISTANCE.

const REFRESH_SEC := 0.3
## Height above the prop's cell base, in world units (a cell is 3.6 tall).
const LABEL_LIFT := 2.2
## On-screen text size while zoomed in: a label's world pixel_size is
## PIXEL_SIZE * camera distance, which cancels perspective (about 0.0012 * 32 *
## 700 px = ~26 px tall text for a 75 degree camera). Tune here.
const PIXEL_SIZE := 0.0012
const FONT_SIZE := 32
## Camera distances (world units; one tile square is 3.2, the spawn view sits
## at ~30): constant screen size up to FULL_SIZE_DISTANCE, shrinking beyond it,
## fading from FADE_START_DISTANCE and gone at HIDE_DISTANCE.
const FULL_SIZE_DISTANCE := 25.0
const FADE_START_DISTANCE := 40.0
const HIDE_DISTANCE := 70.0

var layered_map: LayeredMap
var runtime: MissionRuntime

## entry id -> Label3D
var _labels: Dictionary = {}
## Currently shown, in the order the labels were numbered:
## [{"entry": InteractableEntry, "label": String}] - what a voice command
## ("interact with exploration two") will resolve against.
var _shown: Array[Dictionary] = []


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = REFRESH_SEC
	timer.autostart = true
	timer.timeout.connect(refresh)
	add_child(timer)


## The labelled props right now: [{"entry", "label"}]. Duplicate names carry a
## number ("exploration 1", "exploration 2") so each can be told apart.
func labelled() -> Array[Dictionary]:
	return _shown


## Unique object names as a person would say them (no numbering, underscores
## as spaces) - used to give speech recognition a vocabulary hint.
func spoken_names() -> Array[String]:
	var names: Array[String] = []
	for item in _shown:
		var name := _base_name(item["entry"]).replace("_", " ")
		if not names.has(name):
			names.append(name)
	return names


func refresh() -> void:
	if layered_map == null or runtime == null or layered_map.mission == null:
		return
	var mission := layered_map.mission

	# The debug prints in MissionRuntime's condition checks would fire on every
	# refresh - silence them for this pass only.
	var previous_logging := runtime.log_evaluations
	runtime.log_evaluations = false
	var entries: Array[InteractableEntry] = []
	for entry in mission.interactables:
		if entry.id == "" or not entry.props.get("interactible", true):
			continue
		if not mission.is_effectively_visible(entry):
			continue
		if runtime.first_available_action(entry) == null:
			continue
		entries.append(entry)
	runtime.log_evaluations = previous_logging

	# Number duplicates so each one has a distinct, speakable name.
	var counts: Dictionary = {}
	for entry in entries:
		var base := _base_name(entry)
		counts[base] = int(counts.get(base, 0)) + 1
	var seen: Dictionary = {}
	_shown = []
	var alive: Dictionary = {}
	for entry in entries:
		var base := _base_name(entry)
		var text := base
		if counts[base] > 1:
			seen[base] = int(seen.get(base, 0)) + 1
			text = "%s %d" % [base, seen[base]]
		_shown.append({"entry": entry, "label": text})
		alive[entry.id] = true

		var label: Label3D = _labels.get(entry.id)
		if label == null:
			label = _make_label()
			_labels[entry.id] = label
			add_child(label)
		label.text = text
		label.global_position = _label_position(entry)

	for id in _labels.keys():
		if not alive.has(id):
			_labels[id].queue_free()
			_labels.erase(id)


func _base_name(entry: InteractableEntry) -> String:
	return entry.reference_name if entry.reference_name != "" else entry.mesh_item_name


## Per frame: size and fade every label by its distance to the camera (a label
## is created at full size and corrected here before it is ever drawn).
func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for label: Label3D in _labels.values():
		var distance := camera.global_position.distance_to(label.global_position)
		label.pixel_size = PIXEL_SIZE * minf(distance, FULL_SIZE_DISTANCE)
		var fade := clampf((HIDE_DISTANCE - distance) / (HIDE_DISTANCE - FADE_START_DISTANCE), 0.0, 1.0)
		label.visible = fade > 0.02
		label.modulate.a = fade
		label.outline_modulate.a = 0.9 * fade


func _make_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = false  # size is set per frame by _process()
	label.pixel_size = PIXEL_SIZE * FULL_SIZE_DISTANCE
	label.no_depth_test = true
	label.font_size = FONT_SIZE
	label.outline_size = 10
	label.modulate = Color(1, 1, 1)
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.render_priority = 10
	label.outline_render_priority = 9
	return label


## Above the middle of the prop's footprint. GridMap's Center X/Y/Z are OFF, so
## map_to_local() returns a cell's CORNER - add half a cell to reach its middle.
func _label_position(entry: InteractableEntry) -> Vector3:
	var grid := layered_map.prop_grid
	var half := Vector3(grid.cell_size.x * 0.5, 0.0, grid.cell_size.z * 0.5)
	var cells: Array[Vector3i] = []
	if entry.footprint.is_empty():
		cells.append(entry.origin_cell)
	else:
		for offset in entry.footprint:
			cells.append(entry.origin_cell + offset)
	var sum := Vector3.ZERO
	for cell in cells:
		sum += grid.map_to_local(cell) + half
	var centre := sum / cells.size()
	centre.y = grid.map_to_local(entry.origin_cell).y + LABEL_LIFT
	return grid.to_global(centre)
