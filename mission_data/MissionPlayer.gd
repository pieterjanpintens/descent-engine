extends Node3D

## Root script for the Player scene. Expected scene layout:
##   MissionPlayer (Node3D, this script)
##    |- LayeredMap (Node3D with LayeredMap.gd, same Floor/Wall/PropGridMap
##    |   setup as the Creator - marked as Unique Name %LayeredMap)
##    |- UI (CanvasLayer or Control, containing at least a Label marked
##        %InfoLabel and a "Back" Button)
##
## This is intentionally minimal for now - it proves the load -> apply ->
## render pipeline works. Actual gameplay (movement, LOS, turn order) is a
## separate, much bigger piece to build once this is confirmed working.

@export var menu_scene_path: String = "res://ui/MainMenu.tscn"  ## <<< set to your actual menu scene

@onready var layered_map: LayeredMap = %LayeredMap
@onready var info_label: Label = %InfoLabel


func _ready() -> void:
	var mission := MissionIO.load_mission(GameState.current_mission_path)
	if mission == null:
		info_label.text = "Failed to load mission: %s" % GameState.current_mission_path
		return

	layered_map.apply_mission(mission)

	var display_name := mission.mission_name if mission.mission_name != "" else GameState.current_mission_path.get_file()
	info_label.text = "%s  (tiles=%d, interactables=%d)" % [display_name, mission.tiles.size(), mission.interactables.size()]


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file(menu_scene_path)
