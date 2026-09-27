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
