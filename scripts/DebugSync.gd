extends Node

## TEMPORARY test harness - attach to any node in your LayeredMap scene
## (or paste into LayeredMap.gd's own script temporarily).
##   1 - sync everything and dump the resulting MissionData
##   2 - clear all four GridMap layers + MissionData
##   3 - save the current MissionData to SAVE_PATH
##   4 - load SAVE_PATH into a SEPARATE copy and dump it (doesn't touch
##       the live mission, so you can diff the two dumps by eye)
## Deliberately NOT using F5-F8 - those are Godot's own Run Project / Run
## Current Scene / Pause / Stop shortcuts and will get intercepted by the
## editor instead of reaching this script (Stop in particular will just
## instantly kill the running scene with no output, which looks exactly
## like a crash).
## Delete this once the Creator UI does all of this for real.

const SAVE_PATH := "res://missions/test_mission.tres"

@export var layered_map: LayeredMap


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_run_debug_sync()
			KEY_2:
				_clear_everything()
			KEY_3:
				_run_debug_save()
			KEY_4:
				_run_debug_load()


func _clear_everything() -> void:
	layered_map.floor_grid.clear()
	layered_map.wall_grid.clear()
	layered_map.prop_grid.clear()
	layered_map.underlay_grid.clear()
	layered_map.mission.tiles.clear()
	layered_map.mission.floor_placements.clear()
	layered_map.mission.floor_occupied_cells.clear()
	layered_map.mission.occupied_cells.clear()
	layered_map.mission.underlay_placements.clear()
	layered_map.mission.underlay_occupied_cells.clear()
	layered_map.mission.interactables.clear()
	print("Cleared all four GridMap layers and MissionData.")


func _run_debug_sync() -> void:
	layered_map.rebuild_floor_tiles()
	layered_map.rebuild_underlay_tiles()

	# Sync every painted prop cell - walks all used cells in PropGridMap
	# and re-registers each one's footprint into MissionData.
	for cell in layered_map.prop_grid.get_used_cells():
		layered_map.sync_prop_cell(cell)

	_print_mission_dump(layered_map.mission)


func _run_debug_save() -> void:
	MissionIO.save_mission(layered_map.mission, SAVE_PATH)


func _run_debug_load() -> void:
	var loaded := MissionIO.load_mission(SAVE_PATH)
	if loaded == null:
		return
	print("=== Loaded copy (compare against the last F5 dump above) ===")
	_print_mission_dump(loaded)


func _print_mission_dump(mission: MissionData) -> void:
	print("--- MissionData dump ---")
	print("tiles (%d):" % mission.tiles.size())
	for cell in mission.tiles:
		var entry: TileEntry = mission.tiles[cell]
		print("  %s -> mesh=%s walkable=%s blocks_los=%s" % [cell, entry.mesh_item_name, entry.walkable, entry.blocks_los])

	print("floor_occupied_cells (%d):" % mission.floor_occupied_cells.size())
	for cell in mission.floor_occupied_cells:
		print("  %s -> owned by %s" % [cell, mission.floor_occupied_cells[cell]])

	print("occupied_cells (%d):" % mission.occupied_cells.size())
	for cell in mission.occupied_cells:
		print("  %s -> owned by %s" % [cell, mission.occupied_cells[cell]])

	print("underlay_occupied_cells (%d):" % mission.underlay_occupied_cells.size())
	for cell in mission.underlay_occupied_cells:
		print("  %s -> owned by %s" % [cell, mission.underlay_occupied_cells[cell]])

	print("interactables (%d):" % mission.interactables.size())
	for entry in mission.interactables:
		print("  origin=%s mesh=%s footprint=%s orientation=%s" % [entry.origin_cell, entry.mesh_item_name, entry.footprint, entry.orientation])
	print("-------------------------")
