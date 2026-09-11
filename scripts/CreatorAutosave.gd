class_name CreatorAutosave
extends Node

## Two-tier autosave/backup driver for the Creator - requested 2026-09-10
## ("one of the most frustrating things in editors is that you can lose
## data"). Settings live in the CreatorSettings autoload (enabled/backup
## location/copies/intervals for both tiers), persisted across sessions -
## this script just drives two Timers off those settings and does the
## actual save+prune work. See CreatorSettings.gd's own doc comment for
## why backups land under user://, not res://.
##
## STATELESS rotation: rather than tracking a rotation index in memory
## (which would reset confusingly across app restarts), each backup is
## named `<mission_name>_<tier>_<timestamp>.tres` with a zero-padded
## sortable timestamp. After writing a new one, the whole directory is
## re-scanned for files matching that mission+tier's own prefix, sorted,
## and the oldest deleted until back at the configured count - simple,
## self-healing, and works the same whether this is the first save of a
## fresh session or the fiftieth.
##
## Reuses MissionIO.save_mission() (already exists, already verified
## round-trip correctness) for the actual write - autosave is just a
## scheduled call to the same save path a manual Save uses, writing to a
## different file each time instead of overwriting the mission's own file.

@export var layered_map: LayeredMap

const _AUTOSAVE_TIER := "autosave"
const _CHECKPOINT_TIER := "checkpoint"

var _autosave_timer: Timer
var _checkpoint_timer: Timer


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)

	_checkpoint_timer = Timer.new()
	_checkpoint_timer.timeout.connect(_on_checkpoint_timeout)
	add_child(_checkpoint_timer)

	CreatorSettings.settings_changed.connect(apply_settings)
	apply_settings()


## The one place "do nothing if not enabled" actually happens - called
## once at startup and again whenever CreatorSettingsDialog saves new
## values (via CreatorSettings.settings_changed). Stops both timers
## entirely when disabled, rather than leaving them running and just
## skipping the save inside the callback - disabled should mean no timers
## ticking in the background at all, not a checked-but-still-running one.
func apply_settings() -> void:
	if not CreatorSettings.enabled:
		_autosave_timer.stop()
		_checkpoint_timer.stop()
		return

	# Defensive clamp - the settings dialog's SpinBoxes already enforce
	# min_value = 1, this just guards against a hand-edited config file
	# (Timer.wait_time <= 0 is invalid).
	_autosave_timer.wait_time = max(1.0, CreatorSettings.save_interval_minutes * 60.0)
	_checkpoint_timer.wait_time = max(1.0, CreatorSettings.checkpoint_interval_minutes * 60.0)
	_autosave_timer.start()
	_checkpoint_timer.start()


func _on_autosave_timeout() -> void:
	_run_tier(_AUTOSAVE_TIER, CreatorSettings.copies)


func _on_checkpoint_timeout() -> void:
	_run_tier(_CHECKPOINT_TIER, CreatorSettings.checkpoint_copies)


func _run_tier(tier: String, max_copies: int) -> void:
	if layered_map == null or layered_map.mission == null:
		return

	var mission_name := layered_map.mission.mission_name if layered_map.mission.mission_name != "" else "untitled"
	var filename := "%s_%s_%s.tres" % [mission_name, tier, _timestamp()]
	var path := CreatorSettings.backup_location.path_join(filename)

	if MissionIO.save_mission(layered_map.mission, path):
		_prune(mission_name, tier, max_copies)


## Zero-padded so plain string sort == chronological sort (used by
## _prune() below) and so it's Windows-filename-safe - unlike
## Time.get_datetime_string_from_system()'s default "HH:MM:SS", a literal
## colon isn't valid in a Windows filename, and this project's Creator
## ships as a Windows .exe (see claude.md's CI/Release section).
func _timestamp() -> String:
	var d := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d-%02d%02d%02d" % [d.year, d.month, d.day, d.hour, d.minute, d.second]


## Deletes the oldest files beyond max_copies among THIS mission+tier's
## own backups only - a different mission's autosaves, or the OTHER
## tier's, are untouched (the filename prefix scopes the match).
func _prune(mission_name: String, tier: String, max_copies: int) -> void:
	var dir := DirAccess.open(CreatorSettings.backup_location)
	if dir == null:
		return

	var prefix := "%s_%s_" % [mission_name, tier]
	var matches: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(prefix):
			matches.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	matches.sort()  # zero-padded timestamp in the name -> lexicographic sort is chronological
	while matches.size() > max_copies:
		var oldest: String = matches.pop_front()
		dir.remove(oldest)
