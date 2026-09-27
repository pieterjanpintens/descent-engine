class_name MissionIO
extends RefCounted

## Static save/load helpers for MissionData. Used by the Creator (save) and
## by both Creator and Player (load). Not an autoload - just call
## MissionIO.save_mission(...) / MissionIO.load_mission(...) directly.

static func save_mission(mission: MissionData, path: String) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_error("Failed to create directory %s: %s" % [dir, error_string(err)])
			return false

	var err := ResourceSaver.save(mission, path)
	if err != OK:
		push_error("Failed to save mission to %s: %s" % [path, error_string(err)])
		return false

	print("Saved mission to %s" % path)
	return true


## CACHE_MODE_IGNORE forces a fresh read from disk instead of returning a
## cached in-memory copy - important while iterating/testing round-trips,
## since otherwise a stale cached resource can silently mask save bugs.
static func load_mission(path: String) -> MissionData:
	if not ResourceLoader.exists(path):
		push_error("Mission file not found: %s" % path)
		return null

	var loaded: Resource = ResourceLoader.load(path, "MissionData", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not (loaded is MissionData):
		push_error("Failed to load a valid MissionData from %s" % path)
		return null

	print("Loaded mission from %s" % path)
	return loaded


## Same round trip as save_mission()/load_mission() above, for a Player
## SaveGame - see that class's own doc for what it holds and why. The
## SaveGame's own `mission` field is a full, independent sub-resource (not
## a path to a separate mission file), so it round-trips through the exact
## same ResourceSaver/ResourceLoader call as everything else here.
static func save_game(save: SaveGame, path: String) -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			push_error("Failed to create directory %s: %s" % [dir, error_string(err)])
			return false

	var err := ResourceSaver.save(save, path)
	if err != OK:
		push_error("Failed to save game to %s: %s" % [path, error_string(err)])
		return false

	print("Saved game to %s" % path)
	return true


static func load_game(path: String) -> SaveGame:
	if not ResourceLoader.exists(path):
		push_error("Save file not found: %s" % path)
		return null

	var loaded: Resource = ResourceLoader.load(path, "SaveGame", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded == null or not (loaded is SaveGame):
		push_error("Failed to load a valid SaveGame from %s" % path)
		return null

	print("Loaded game from %s" % path)
	return loaded
