extends Node

## Autoload singleton. Add as "GameState" in Project Settings > Autoload.
## Godot's change_scene_to_file() doesn't take parameters, so this is the
## simplest way to hand data (which mission to load) from one scene to the
## next without wiring up a signal bus for one value.

var current_mission_path: String = ""
## Set instead of current_mission_path to resume a saved session - see
## MissionPlayer._ready(). Consumed (cleared) the moment the Player reads it,
## same one-shot handoff shape as current_mission_path itself.
var load_save_path: String = ""

## Set while a mission is played as a chapter of a campaign (CampaignPlayer sets them before
## starting the mission): the campaign's folder and the chapter. When the mission ends,
## MissionPlayer stores how it went in `campaign_result` ({won, chapter_id, mission_variables (the mission's final variable values)}, or {} when
## it was abandoned) and returns to the campaign screen, which applies it and clears all three.
const CAMPAIGN_SCENE := "res://ui/CampaignPlayer.tscn"
var campaign_folder: String = ""
## The key (file name) of the campaign save game being played, see CampaignIO.save_key().
var campaign_save: String = ""
## Mission variable name -> value handed over by the campaign when the mission starts (MissionPlayer presets them).
var campaign_mission_inputs: Dictionary = {}
## Which page the campaign screen opens on when no save game is given: "new" (pick a campaign book) or "load".
var campaign_screen: String = "new"
var campaign_chapter_id: String = ""
var campaign_result: Dictionary = {}


## Mission debugging (see DebugSession): a Play from the Creator hands its in-memory mission to the Player and gets it back
## on return. `editor_mission` is the editor's own, never edited by the Player (that works on a copy), so rolling back or
## returning to the editor always finds it as it was.
const CREATOR_SCENE := "res://map/MissionMap.tscn"
const PLAYER_SCENE := "res://player/MissionPlayer.tscn"
var debug_session: bool = false
var editor_mission: MissionData = null
var editor_mission_path: String = ""  ## the file the editor has the mission from ("" = never saved)
var editor_history: Dictionary = {}  ## OperationHistory.export_state(), so undo survives the round trip
var editor_view: Dictionary = {}  ## the editor camera, FreeLookCamera.export_view()
var editor_returning: bool = false  ## true from "back to the editor" until the Creator has taken the mission back


func clear_debug() -> void:
	debug_session = false
	editor_mission = null
	editor_mission_path = ""
	editor_history = {}
	editor_view = {}
	editor_returning = false


func clear_campaign() -> void:
	campaign_folder = ""
	campaign_save = ""
	campaign_mission_inputs = {}
	campaign_chapter_id = ""
	campaign_result = {}
