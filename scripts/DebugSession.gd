class_name DebugSession
extends RefCounted

## Mission debugging: a "Play" from the Creator starts a DEBUG SESSION (GameState.debug_session) - the Player then runs the
## editor's in-memory mission (unsaved tweaks included), offers snapshots (F9 take, F10 roll back, slots in the Debug panel)
## and returns to the editor with Ctrl+E, keeping everything the editor had. Snapshots live in user://debug/<mission key>/ and
## hold the PROGRESS of the play (see MissionProgress), not a copy of the mission, so a snapshot loads onto the edited mission.
##
## This class is the shared bookkeeping: where snapshots are stored, what a slot looks like, the remembered party, and the
## "fast start" switch.

const ROOT := "user://debug"
const SETTINGS_FILE := "user://debug/settings.cfg"
const PARTY_FILE := "user://debug/party.tres"
## The named slots. "quick" is F9/F10, "auto" is taken when the Player hands over to the editor, 1-5 are free slots.
const SLOTS: Array[String] = ["quick", "auto", "1", "2", "3", "4", "5"]

static var _fast_loaded := false
static var _fast := true


static func active() -> bool:
	return GameState.debug_session


## Fast start: skips the presentation dialogs (stage setup pages, spawn confirmation, monster placement, phase banners) and
## the narration while debugging. The state changes themselves still happen. On by default.
static func fast() -> bool:
	if not _fast_loaded:
		_fast_loaded = true
		var config := ConfigFile.new()
		if config.load(SETTINGS_FILE) == OK:
			_fast = bool(config.get_value("debug", "fast_start", true))
	return _fast


## What the presentation skips apply to: only while a debug session runs.
static func skipping() -> bool:
	return active() and fast()


static func set_fast(on: bool) -> void:
	_fast = on
	_fast_loaded = true
	DirAccess.make_dir_recursive_absolute(ROOT)
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value("debug", "fast_start", on)
	config.save(SETTINGS_FILE)


## The folder name of a mission's snapshots: its file name when it has one (stable per file), else its name.
static func mission_key(mission: MissionData, path: String) -> String:
	var base := path.get_file().get_basename() if path != "" else ""
	if base == "" and mission != null:
		base = mission.mission_name
	if base == "":
		base = "untitled"
	var key := ""
	for i in base.length():
		var c := base[i]
		key += c if (c.to_lower() != c.to_upper() or c.is_valid_int() or c == "_" or c == "-") else "_"
	return key


static func slot_path(key: String, slot: String) -> String:
	return "%s/%s/%s.tres" % [ROOT, key, slot]


## The text a slot shows in a menu: "Quick - round 3, 14:02:11", or "Quick - empty".
static func slot_label(key: String, slot: String) -> String:
	var title := "Auto (on leaving the Player)" if slot == "auto" else ("Quick (F9)" if slot == "quick" else "Slot " + slot)
	var path := slot_path(key, slot)
	if not FileAccess.file_exists(path):
		return title + " - empty"
	var save := MissionIO.load_game(path)
	if save == null:
		return title + " - unreadable"
	return "%s - round %d, %s" % [title, save.current_round, _short_time(save.saved_at)]


static func slot_exists(key: String, slot: String) -> bool:
	return FileAccess.file_exists(slot_path(key, slot))


## "20261011-140211" -> "14:02:11".
static func _short_time(stamp: String) -> String:
	if stamp.length() < 15:
		return stamp
	return "%s:%s:%s" % [stamp.substr(9, 2), stamp.substr(11, 2), stamp.substr(13, 2)]


# ---------------------------------------------------------------- the remembered party

## The party (heroes + weapons) picked at the last debug embark: {} when none is remembered.
static func load_party() -> Dictionary:
	if not FileAccess.file_exists(PARTY_FILE):
		return {}
	var save := MissionIO.load_game(PARTY_FILE)
	if save == null or save.player_roster.is_empty():
		return {}
	return {"roster": save.player_roster, "weapons": save.player_weapons, "trinkets": save.player_trinkets}


static func save_party(roster: Array[int], weapons: Dictionary, trinkets: Dictionary = {}) -> void:
	var save := SaveGame.new()
	save.player_roster = roster.duplicate()
	save.player_weapons = weapons.duplicate(true)
	save.player_trinkets = trinkets.duplicate(true)
	MissionIO.save_game(save, PARTY_FILE)


static func forget_party() -> void:
	if FileAccess.file_exists(PARTY_FILE):
		DirAccess.remove_absolute(PARTY_FILE)
