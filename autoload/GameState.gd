extends Node

## Autoload singleton. Add as "GameState" in Project Settings > Autoload.
## Godot's change_scene_to_file() doesn't take parameters, so this is the
## simplest way to hand data (which mission to load) from one scene to the
## next without wiring up a signal bus for one value.

var current_mission_path: String = ""
