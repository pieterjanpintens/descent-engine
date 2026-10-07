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
## MissionPlayer stores how it went in `campaign_result` ({won, roster, chapter_id}, or {} when
## it was abandoned) and returns to the campaign screen, which applies it and clears all three.
const CAMPAIGN_SCENE := "res://ui/CampaignPlayer.tscn"
var campaign_folder: String = ""
## The key (file name) of the campaign save game being played, see CampaignIO.save_key().
var campaign_save: String = ""
## Which page the campaign screen opens on when no save game is given: "new" (pick a campaign book) or "load".
var campaign_screen: String = "new"
var campaign_chapter_id: String = ""
var campaign_result: Dictionary = {}


func clear_campaign() -> void:
	campaign_folder = ""
	campaign_save = ""
	campaign_chapter_id = ""
	campaign_result = {}
