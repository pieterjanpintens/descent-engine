class_name FeatureFlags
extends RefCounted

## Switches for unfinished features, kept in the game but hidden until they are good enough. Read from FILE in the user folder,
## a JSON object of flag name -> true/false, e.g. {"table_camera": true}. A missing file, a missing flag or anything that is not
## `true` means OFF, so players never see these. Read once per run (restart the game after editing the file).
##
## Flags:
## - "table_camera": the phone that photographs the table (Options > Table camera, Gear > Table camera, the camera part of the
##   table setup sheet, the camera's guess of where the heroes stand). Off: the hero finder was right less than half the time.

const FILE := "user://feature_flags.json"
const TABLE_CAMERA := "table_camera"

static var _flags: Dictionary = {}
static var _loaded := false


static func enabled(flag: String) -> bool:
	if not _loaded:
		_loaded = true
		_flags = {}
		if FileAccess.file_exists(FILE):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
			if data is Dictionary:
				_flags = data
			else:
				push_warning("%s is not a JSON object - every feature flag is off" % FILE)
	return _flags.get(flag, false) == true
