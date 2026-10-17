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
const _GAMEPLAY := "gameplay"
const _NARRATION := "narration"
const _COMMUNITY := "community"
const _UPDATES := "updates"
const _AI := "ai"

var voice_enabled: bool = true
var push_to_talk: bool = true
var show_voice_hints: bool = true
## "" = whatever AudioServer.input_device already defaults to (never
## explicitly chosen) - VoiceListener only overrides it when this is
## non-empty AND still a real device on this machine, see its own
## _setup_microphone().
var input_device: String = ""
## Gameplay: jump the camera to the player spawn area / newly spawned monsters.
var auto_camera_to_spawns: bool = true
## Narration: read the story aloud (Narrator, needs the Piper engine installed on demand).
var narration_enabled: bool = true
## The story teller: the voice (NarratorVoices id) that reads everything no character speaks. A player setting - never a
## mission's choice - and characters never get this voice.
var storyteller_voice: String = NarratorVoices.BASE_ID
## Community sharing: where the catalog of shared missions and campaigns is fetched from (see CommunityService), and the
## author name the export dialog starts with.
var community_catalog_url: String = CommunityService.DEFAULT_CATALOG_URL
var community_author: String = ""
## App updates: ask GitHub at the main menu whether a newer release exists (AppUpdater). Never installs anything by itself.
var check_updates: bool = true
## The version whose "What's new" the player has already been shown (so it opens by itself once after an update).
var last_seen_version: String = ""
## Optional AI writing help in the editors (AiClient / AiAssist). Off by default; the author's OWN Anthropic API key, kept in plain text
## in this file in their own user folder (never in a package, save game or release). Nothing is sent unless an AI button is pressed.
var ai_enabled: bool = false
var ai_api_key: String = ""
var ai_model: String = "claude-sonnet-5-5"
## Which way the AI is reached: "api" = the author's own API key; "claude_code" = the Claude Code program on this PC (it uses the author's own
## Claude sign-in, nothing is paid per request here). `ai_claude_path` = where that program is ("" = look for it).
var ai_provider: String = "api"
var ai_claude_path: String = ""


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
	auto_camera_to_spawns = config.get_value(_GAMEPLAY, "auto_camera_to_spawns", auto_camera_to_spawns)
	narration_enabled = config.get_value(_NARRATION, "narration_enabled", narration_enabled)
	storyteller_voice = config.get_value(_NARRATION, "storyteller_voice", storyteller_voice)
	community_catalog_url = config.get_value(_COMMUNITY, "catalog_url", community_catalog_url)
	if CommunityService.OLD_CATALOG_URLS.has(community_catalog_url):
		community_catalog_url = CommunityService.DEFAULT_CATALOG_URL  # saved by an earlier version, now moved
	community_author = config.get_value(_COMMUNITY, "author", community_author)
	check_updates = config.get_value(_UPDATES, "check_updates", check_updates)
	last_seen_version = config.get_value(_UPDATES, "last_seen_version", last_seen_version)
	ai_enabled = config.get_value(_AI, "enabled", ai_enabled)
	ai_api_key = config.get_value(_AI, "api_key", ai_api_key)
	ai_model = config.get_value(_AI, "model", ai_model)
	ai_provider = config.get_value(_AI, "provider", ai_provider)
	ai_claude_path = config.get_value(_AI, "claude_path", ai_claude_path)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value(_SECTION, "voice_enabled", voice_enabled)
	config.set_value(_SECTION, "push_to_talk", push_to_talk)
	config.set_value(_SECTION, "show_voice_hints", show_voice_hints)
	config.set_value(_SECTION, "input_device", input_device)
	config.set_value(_GAMEPLAY, "auto_camera_to_spawns", auto_camera_to_spawns)
	config.set_value(_NARRATION, "narration_enabled", narration_enabled)
	config.set_value(_NARRATION, "storyteller_voice", storyteller_voice)
	config.set_value(_COMMUNITY, "catalog_url", community_catalog_url)
	config.set_value(_COMMUNITY, "author", community_author)
	config.set_value(_UPDATES, "check_updates", check_updates)
	config.set_value(_UPDATES, "last_seen_version", last_seen_version)
	config.set_value(_AI, "enabled", ai_enabled)
	config.set_value(_AI, "api_key", ai_api_key)
	config.set_value(_AI, "model", ai_model)
	config.set_value(_AI, "provider", ai_provider)
	config.set_value(_AI, "claude_path", ai_claude_path)

	var dir := SETTINGS_PATH.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var err := config.save(SETTINGS_PATH)
	if err != OK:
		push_error("Failed to save player settings to %s: %s" % [SETTINGS_PATH, error_string(err)])
