extends Node

## Persisted Creator preferences - currently just the autosave/backup
## system (CreatorAutosave.gd, requested 2026-09-10: "one of the most
## frustrating things in editors is that you can lose data"). An autoload
## (not a MissionData field) since these are per-USER-MACHINE tool
## preferences, not part of any mission - same reasoning OfficialAssetMap/
## OfficialAssetOverrides already established for user:// data in this
## project.
##
## Named CreatorSettings, NOT EditorSettings - Godot 4 itself has a
## built-in engine class literally called EditorSettings (the real
## editor's own preferences singleton, part of the editor API). Autoloading
## a custom global under that same name collides with the built-in
## identifier and the autoload doesn't resolve/expose correctly - caught
## after the fact when it "didn't appear," see git history. Any future
## autoload/class name should be checked against Godot's built-in class
## list first.
##
## Saved to `user://configuration/editor-settings.cfg` via Godot's
## built-in ConfigFile - NOT res://, even though the original request
## asked for res://configuration/editor-settings - this project's Creator
## ships as an exported Windows .exe (see claude.md's CI/Release section),
## and res:// is packed into a read-only .pck in an exported build. Writes
## there work fine from inside the Godot editor but silently fail (or are
## undefined) from the actual shipped tool - user:// is Godot's dedicated
## writable-everywhere location for exactly this, already used by
## OfficialAssetOverrides for the same category of reason.

signal settings_changed

const SETTINGS_PATH := "user://configuration/editor-settings.cfg"
const _SECTION := "autosave"

## Starts OFF - an opt-in safety net shouldn't start writing files before
## the user has actually seen and confirmed the settings, even once,
## regardless of what the other fields default to.
var enabled: bool = false
var backup_location: String = "user://missions/backup"

## "Recent" tier - frequent, shallow history.
var copies: int = 10
var save_interval_minutes: int = 1

## "Checkpoint" tier - infrequent, deeper history.
var checkpoint_copies: int = 2
var checkpoint_interval_minutes: int = 15

## The real table (TableAreaOverlay, View > Table Area): its size in cm and how big one tile square is on it. TABLE_PRESETS are the
## suggested sizes ([name, width, depth]); any other size can be typed in the Settings dialog.
const TABLE_PRESETS := [["Large", 175.0, 95.0], ["Medium", 120.0, 90.0], ["Small", 120.0, 75.0]]
const _TABLE_SECTION := "table"
var table_overlay: bool = true
var table_width_cm: float = 175.0
var table_depth_cm: float = 95.0
## One tile square of the floor tiles on the table, in cm (3.2, measured by the author on the real tiles).
var square_cm: float = 3.2


## The smallest preset table ([name, width, depth]) a board of `squares` (long side, short side) fits on; empty when none does.
func smallest_table_for(squares: Vector2i) -> Array:
	var long_cm := squares.x * square_cm
	var short_cm := squares.y * square_cm
	var best: Array = []
	for preset: Array in TABLE_PRESETS:
		if long_cm <= maxf(preset[1], preset[2]) + 0.01 and short_cm <= minf(preset[1], preset[2]) + 0.01:
			if best.is_empty() or float(preset[1]) * float(preset[2]) < float(best[1]) * float(best[2]):
				best = preset
	return best


func _ready() -> void:
	load_settings()


## Falls back silently to the defaults above if the file doesn't exist yet
## (first run) - not an error, just means nobody has saved settings before.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	enabled = config.get_value(_SECTION, "enabled", enabled)
	backup_location = config.get_value(_SECTION, "backup_location", backup_location)
	copies = config.get_value(_SECTION, "copies", copies)
	save_interval_minutes = config.get_value(_SECTION, "save_interval_minutes", save_interval_minutes)
	checkpoint_copies = config.get_value(_SECTION, "checkpoint_copies", checkpoint_copies)
	checkpoint_interval_minutes = config.get_value(_SECTION, "checkpoint_interval_minutes", checkpoint_interval_minutes)
	table_overlay = config.get_value(_TABLE_SECTION, "show", table_overlay)
	table_width_cm = float(config.get_value(_TABLE_SECTION, "width_cm", table_width_cm))
	table_depth_cm = float(config.get_value(_TABLE_SECTION, "depth_cm", table_depth_cm))
	square_cm = float(config.get_value(_TABLE_SECTION, "square_cm", square_cm))


## Called by CreatorSettingsDialog.gd's Save button. Emits settings_changed
## so CreatorAutosave (or anything else live) can pick up the new values
## immediately without needing a scene reload.
func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "enabled", enabled)
	config.set_value(_SECTION, "backup_location", backup_location)
	config.set_value(_SECTION, "copies", copies)
	config.set_value(_SECTION, "save_interval_minutes", save_interval_minutes)
	config.set_value(_SECTION, "checkpoint_copies", checkpoint_copies)
	config.set_value(_SECTION, "checkpoint_interval_minutes", checkpoint_interval_minutes)
	config.set_value(_TABLE_SECTION, "show", table_overlay)
	config.set_value(_TABLE_SECTION, "width_cm", table_width_cm)
	config.set_value(_TABLE_SECTION, "depth_cm", table_depth_cm)
	config.set_value(_TABLE_SECTION, "square_cm", square_cm)

	var dir := SETTINGS_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save editor settings to %s: %s" % [SETTINGS_PATH, error_string(err)])

	settings_changed.emit()
