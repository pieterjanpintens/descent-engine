extends Node

## Persisted PLAYER (not Creator) preferences - currently just voice
## control's own configuration (see VoiceSettingsDialog.gd), named
## generically rather than e.g. VoiceSettings so future real (non-mock)
## Options items can land here too without a rename. Direct answer to "do
## we store options somewhere so they persist over restarts" - no, nothing
## did until this autoload; every voice setting used to just live as
## in-memory state (VoiceListener.push_to_talk, a checkbox's own
## button_pressed, ...), reset to its hardcoded default every time the
## Player scene loaded.
##
## Same ConfigFile-at-user:// pattern as CreatorSettings (see that
## autoload's own doc for the full res://-is-read-only-in-an-exported-build
## reasoning - identical here, this project's Player ships as an exported
## build too).
##
## Unlike CreatorSettingsDialog (an explicit Save button, since that form
## has several numeric fields prone to accidental mid-edit changes),
## VoiceSettingsDialog's toggles/picker are simple enough to save()
## immediately on every change - see that script's own handlers.

const SETTINGS_PATH := "user://configuration/player-settings.cfg"
const _SECTION := "voice"

var voice_enabled: bool = true
var push_to_talk: bool = true
var show_voice_hints: bool = true
## "" = whatever AudioServer.input_device already defaults to (never
## explicitly chosen) - VoiceListener only overrides it when this is
## non-empty AND still a real device on this machine, see its own
## _setup_microphone().
var input_device: String = ""


func _ready() -> void:
	load_settings()


## Falls back silently to the defaults above if the file doesn't exist yet
## (first run) - not an error, just means nobody has saved settings before.
func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	voice_enabled = config.get_value(_SECTION, "voice_enabled", voice_enabled)
	push_to_talk = config.get_value(_SECTION, "push_to_talk", push_to_talk)
	show_voice_hints = config.get_value(_SECTION, "show_voice_hints", show_voice_hints)
	input_device = config.get_value(_SECTION, "input_device", input_device)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "voice_enabled", voice_enabled)
	config.set_value(_SECTION, "push_to_talk", push_to_talk)
	config.set_value(_SECTION, "show_voice_hints", show_voice_hints)
	config.set_value(_SECTION, "input_device", input_device)

	var dir := SETTINGS_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save player settings to %s: %s" % [SETTINGS_PATH, error_string(err)])
