class_name NarratorVoices
extends RefCounted

## The catalogue of narration voices (Piper models, see PiperInstaller / Narrator). Never instantiated.
##
## A VOICE is a model plus - for the multi-speaker models - a speaker number, so one ~75 MB
## model carries many voices. The BASE voice (`BASE_ID`, installed together with the engine) is the
## default story teller; the EXTRA voices (accents: Irish, Scottish, Indian, Welsh, ... ) come with the
## one optional "extra voices" download (PiperInstaller.install_extras()).
##
## Two optional downloads: the STANDARD voices (plain American / British English - what throwaway characters are
## drawn from first) and the accent EXTRAS.
##
## The accent / gender labels of the extra voices come from the source corpora's speaker notes
## (remembered, not measured) - check them by ear and correct a label here if one is wrong.

const VOICE_DIR := "user://piper/voices/"
const BASE_ID := "lessac"
## A character's voice_id meaning "pick one from my name" (see Narrator).
const RANDOM_ID := ""
const BASE_MODEL := "en_US-lessac-medium"
## What the download button tells the player.
const EXTRAS_SIZE_TEXT := "about 340 MB"
const STANDARD_SIZE_TEXT := "about 580 MB"

const BASE := {"id": BASE_ID, "label": "Standard - American man", "model": BASE_MODEL, "speaker": -1, "plain": true}

## Plain English voices (`plain` = no marked accent). Gender labels are from memory - correct one here if it's wrong.
const STANDARD: Array[Dictionary] = [
	{"id": "amy", "label": "American - woman (Amy)", "model": "en_US-amy-medium", "speaker": -1, "plain": true},
	{"id": "kristin", "label": "American - woman (Kristin)", "model": "en_US-kristin-medium", "speaker": -1, "plain": true},
	{"id": "ryan", "label": "American - man (Ryan)", "model": "en_US-ryan-medium", "speaker": -1, "plain": true},
	{"id": "john", "label": "American - man (John)", "model": "en_US-john-medium", "speaker": -1, "plain": true},
	{"id": "alan", "label": "British - man (Alan)", "model": "en_GB-alan-medium", "speaker": -1, "plain": true},
	{"id": "cori", "label": "British - woman (Cori)", "model": "en_GB-cori-medium", "speaker": -1, "plain": true},
	{"id": "british_north_m", "label": "British (Northern) - man", "model": "en_GB-northern_english_male-medium", "speaker": -1, "plain": true},
	{"id": "british_south_f", "label": "British (Southern) - woman", "model": "en_GB-southern_english_female-low", "speaker": -1, "plain": true},
	# The four voices of the "semaine" model are acted moods (their speaker names): calm, cheerful, aggressive, gloomy.
	{"id": "semaine_prudence", "label": "British - woman (Prudence, calm)", "model": "en_GB-semaine-medium", "speaker": 0, "plain": true},
	{"id": "semaine_poppy", "label": "British - woman (Poppy, cheerful)", "model": "en_GB-semaine-medium", "speaker": 3, "plain": true},
	{"id": "semaine_spike", "label": "British - man (Spike, aggressive)", "model": "en_GB-semaine-medium", "speaker": 1, "plain": true},
	{"id": "semaine_obadiah", "label": "British - man (Obadiah, gloomy)", "model": "en_GB-semaine-medium", "speaker": 2, "plain": true},
]

const STANDARD_MODEL_PATHS := {
	"en_US-amy-medium": "en/en_US/amy/medium",
	"en_US-kristin-medium": "en/en_US/kristin/medium",
	"en_US-ryan-medium": "en/en_US/ryan/medium",
	"en_US-john-medium": "en/en_US/john/medium",
	"en_GB-alan-medium": "en/en_GB/alan/medium",
	"en_GB-cori-medium": "en/en_GB/cori/medium",
	"en_GB-northern_english_male-medium": "en/en_GB/northern_english_male/medium",
	"en_GB-southern_english_female-low": "en/en_GB/southern_english_female/low",
	"en_GB-semaine-medium": "en/en_GB/semaine/medium",
}

## The extra voices. `speaker` = the speaker number inside a multi-speaker model, -1 for a single-speaker model.
const EXTRAS: Array[Dictionary] = [
	{"id": "irish_jenny", "label": "Irish - Jenny (F)", "model": "en_GB-jenny_dioco-medium", "speaker": -1},
	{"id": "irish_cork_f", "label": "Irish (Cork) - woman", "model": "en_GB-vctk-medium", "speaker": 8},
	{"id": "irish_m", "label": "Irish - man", "model": "en_GB-vctk-medium", "speaker": 106},
	{"id": "irish_f", "label": "Irish - woman", "model": "en_GB-vctk-medium", "speaker": 30},
	{"id": "scottish_alba", "label": "Scottish - Alba (F)", "model": "en_GB-alba-medium", "speaker": -1},
	{"id": "scottish_awb", "label": "Scottish - man (deep)", "model": "en_US-arctic-medium", "speaker": 0},
	{"id": "scottish_m", "label": "Scottish - man", "model": "en_GB-vctk-medium", "speaker": 16},
	{"id": "indian_ksp", "label": "Indian - man (calm)", "model": "en_US-arctic-medium", "speaker": 3},
	{"id": "indian_axb", "label": "Indian - woman", "model": "en_US-arctic-medium", "speaker": 15},
	{"id": "indian_gka", "label": "Indian - man", "model": "en_US-arctic-medium", "speaker": 17},
	{"id": "indian_f", "label": "Indian - woman (clear)", "model": "en_GB-vctk-medium", "speaker": 87},
	{"id": "welsh_f", "label": "Welsh - woman", "model": "en_GB-vctk-medium", "speaker": 88},
	{"id": "south_african_m", "label": "South African - man", "model": "en_GB-vctk-medium", "speaker": 32},
	{"id": "south_african_f", "label": "South African - woman", "model": "en_GB-vctk-medium", "speaker": 35},
	{"id": "australian_m", "label": "Australian - man", "model": "en_GB-vctk-medium", "speaker": 71},
	{"id": "new_zealand_f", "label": "New Zealand - woman", "model": "en_GB-vctk-medium", "speaker": 42},
	{"id": "yorkshire_m", "label": "Yorkshire - man", "model": "en_GB-vctk-medium", "speaker": 12},
	{"id": "arabic", "label": "Arabic accent", "model": "en_US-l2arctic-medium", "speaker": 21},
	{"id": "hindi", "label": "Hindi accent", "model": "en_US-l2arctic-medium", "speaker": 10},
	{"id": "korean", "label": "Korean accent", "model": "en_US-l2arctic-medium", "speaker": 11},
	{"id": "mandarin", "label": "Mandarin accent", "model": "en_US-l2arctic-medium", "speaker": 20},
	{"id": "spanish", "label": "Spanish accent", "model": "en_US-l2arctic-medium", "speaker": 22},
	{"id": "vietnamese", "label": "Vietnamese accent", "model": "en_US-l2arctic-medium", "speaker": 1},
	# More speakers of the same VCTK model (no extra download); accent/gender from the corpus notes, check by ear.
	{"id": "vctk_p225", "label": "English (Southern) - woman", "model": "en_GB-vctk-medium", "speaker": 107, "plain": true},
	{"id": "vctk_p226", "label": "English (Surrey) - man", "model": "en_GB-vctk-medium", "speaker": 95, "plain": true},
	{"id": "vctk_p227", "label": "English (Cumbria) - man", "model": "en_GB-vctk-medium", "speaker": 82},
	{"id": "vctk_p228", "label": "English (Southern) - woman", "model": "en_GB-vctk-medium", "speaker": 90, "plain": true},
	{"id": "vctk_p230", "label": "English (Teesside) - woman", "model": "en_GB-vctk-medium", "speaker": 74},
	{"id": "vctk_p232", "label": "English (Southern) - man", "model": "en_GB-vctk-medium", "speaker": 60, "plain": true},
	{"id": "vctk_p233", "label": "English (Staffordshire) - woman", "model": "en_GB-vctk-medium", "speaker": 89},
	{"id": "vctk_p234", "label": "Scottish (Dumfries) - woman", "model": "en_GB-vctk-medium", "speaker": 94},
	{"id": "vctk_p236", "label": "English (Manchester) - woman", "model": "en_GB-vctk-medium", "speaker": 1},
	{"id": "vctk_p237", "label": "Scottish (Fife) - man", "model": "en_GB-vctk-medium", "speaker": 102},
	{"id": "vctk_p238", "label": "Northern Irish (Belfast) - woman", "model": "en_GB-vctk-medium", "speaker": 17},
	{"id": "vctk_p239", "label": "English (South West) - woman", "model": "en_GB-vctk-medium", "speaker": 0},
	{"id": "vctk_p241", "label": "Scottish (Perth) - man", "model": "en_GB-vctk-medium", "speaker": 98},
	{"id": "vctk_p243", "label": "English (London) - man", "model": "en_GB-vctk-medium", "speaker": 81, "plain": true},
	{"id": "vctk_p245", "label": "Irish (Dublin) - man", "model": "en_GB-vctk-medium", "speaker": 97},
	{"id": "vctk_p246", "label": "Scottish (Selkirk) - man", "model": "en_GB-vctk-medium", "speaker": 93},
	{"id": "vctk_p247", "label": "Scottish (Argyll) - man", "model": "en_GB-vctk-medium", "speaker": 5},
	{"id": "vctk_p249", "label": "Scottish (Aberdeen) - woman", "model": "en_GB-vctk-medium", "speaker": 103},
	{"id": "vctk_p251", "label": "Indian - man", "model": "en_GB-vctk-medium", "speaker": 92},
	{"id": "vctk_p252", "label": "Scottish (Edinburgh) - man", "model": "en_GB-vctk-medium", "speaker": 79},
	{"id": "vctk_p254", "label": "English (Surrey) - man", "model": "en_GB-vctk-medium", "speaker": 76, "plain": true},
	{"id": "vctk_p255", "label": "Scottish (Galloway) - man", "model": "en_GB-vctk-medium", "speaker": 84},
	{"id": "vctk_p256", "label": "English (Birmingham) - man", "model": "en_GB-vctk-medium", "speaker": 104},
	{"id": "vctk_p257", "label": "English (Southern) - woman", "model": "en_GB-vctk-medium", "speaker": 18, "plain": true},
	{"id": "vctk_p258", "label": "English (Southern) - man", "model": "en_GB-vctk-medium", "speaker": 57, "plain": true},
	{"id": "vctk_p259", "label": "English (Nottingham) - man", "model": "en_GB-vctk-medium", "speaker": 4},
	{"id": "vctk_p260", "label": "Scottish (Orkney) - man", "model": "en_GB-vctk-medium", "speaker": 96},
	{"id": "vctk_p261", "label": "Northern Irish (Belfast) - woman", "model": "en_GB-vctk-medium", "speaker": 6},
	{"id": "vctk_p262", "label": "Scottish (Edinburgh) - woman", "model": "en_GB-vctk-medium", "speaker": 80},
	{"id": "vctk_p263", "label": "Scottish (Aberdeen) - man", "model": "en_GB-vctk-medium", "speaker": 7},
	{"id": "vctk_p264", "label": "Scottish (West Lothian) - woman", "model": "en_GB-vctk-medium", "speaker": 2},
	{"id": "vctk_p265", "label": "Scottish (Ross) - woman", "model": "en_GB-vctk-medium", "speaker": 100},
	{"id": "vctk_p266", "label": "Irish (Athlone) - woman", "model": "en_GB-vctk-medium", "speaker": 41},
	{"id": "vctk_p267", "label": "English (Yorkshire) - woman", "model": "en_GB-vctk-medium", "speaker": 54},
	{"id": "vctk_p269", "label": "English (Newcastle) - woman", "model": "en_GB-vctk-medium", "speaker": 77},
	{"id": "vctk_p273", "label": "English (Suffolk) - man", "model": "en_GB-vctk-medium", "speaker": 19},
	{"id": "vctk_p274", "label": "English (Essex) - man", "model": "en_GB-vctk-medium", "speaker": 10},
	{"id": "vctk_p276", "label": "English (Oxford) - woman", "model": "en_GB-vctk-medium", "speaker": 11, "plain": true},
	{"id": "vctk_p278", "label": "English (Cheshire) - man", "model": "en_GB-vctk-medium", "speaker": 64},
	{"id": "vctk_p279", "label": "English (Leicester) - man", "model": "en_GB-vctk-medium", "speaker": 69},
	{"id": "vctk_p282", "label": "English (Newcastle) - woman", "model": "en_GB-vctk-medium", "speaker": 91},
	{"id": "vctk_p286", "label": "English (Newcastle) - man", "model": "en_GB-vctk-medium", "speaker": 9},
	{"id": "vctk_p287", "label": "English (York) - man", "model": "en_GB-vctk-medium", "speaker": 23},
	{"id": "vctk_p288", "label": "Irish (Dublin) - woman", "model": "en_GB-vctk-medium", "speaker": 58},
	{"id": "vctk_p292", "label": "Northern Irish (Belfast) - man", "model": "en_GB-vctk-medium", "speaker": 61},
	{"id": "vctk_p294", "label": "American (San Francisco) - woman", "model": "en_GB-vctk-medium", "speaker": 39, "plain": true},
	{"id": "vctk_p297", "label": "American (New York) - woman", "model": "en_GB-vctk-medium", "speaker": 52, "plain": true},
	{"id": "vctk_p298", "label": "Irish (Tipperary) - man", "model": "en_GB-vctk-medium", "speaker": 67},
	{"id": "vctk_p299", "label": "American (California) - woman", "model": "en_GB-vctk-medium", "speaker": 68, "plain": true},
	{"id": "vctk_p301", "label": "American (North Carolina) - woman", "model": "en_GB-vctk-medium", "speaker": 59, "plain": true},
	{"id": "vctk_p302", "label": "Canadian (Montreal) - man", "model": "en_GB-vctk-medium", "speaker": 105, "plain": true},
	{"id": "vctk_p303", "label": "Canadian (Toronto) - woman", "model": "en_GB-vctk-medium", "speaker": 99, "plain": true},
	{"id": "vctk_p308", "label": "American (Alabama) - woman", "model": "en_GB-vctk-medium", "speaker": 34, "plain": true},
	{"id": "vctk_p311", "label": "American (Iowa) - man", "model": "en_GB-vctk-medium", "speaker": 38, "plain": true},
	{"id": "vctk_p313", "label": "Irish (County Down) - woman", "model": "en_GB-vctk-medium", "speaker": 46},
	{"id": "vctk_p323", "label": "South African (Pretoria) - woman", "model": "en_GB-vctk-medium", "speaker": 31},
	{"id": "vctk_p345", "label": "American (Florida) - man", "model": "en_GB-vctk-medium", "speaker": 75, "plain": true},
	{"id": "vctk_p360", "label": "American (New Jersey) - man", "model": "en_GB-vctk-medium", "speaker": 24, "plain": true},
	{"id": "vctk_p363", "label": "Canadian (Toronto) - man", "model": "en_GB-vctk-medium", "speaker": 50, "plain": true},
	{"id": "vctk_p376", "label": "Indian - man", "model": "en_GB-vctk-medium", "speaker": 26},
	{"id": "vctk_s5", "label": "Kenyan - woman", "model": "en_GB-vctk-medium", "speaker": 73},
]

## Where each extra model lives in the rhasspy/piper-voices repository (below the repo's root).
const EXTRA_MODEL_PATHS := {
	"en_GB-alba-medium": "en/en_GB/alba/medium",
	"en_GB-jenny_dioco-medium": "en/en_GB/jenny_dioco/medium",
	"en_GB-vctk-medium": "en/en_GB/vctk/medium",
	"en_US-arctic-medium": "en/en_US/arctic/medium",
	"en_US-l2arctic-medium": "en/en_US/l2arctic/medium",
}


## Every voice: the base one first, then the standard ones, then the accent extras.
static func all() -> Array[Dictionary]:
	var found: Array[Dictionary] = [BASE]
	found.append_array(STANDARD)
	found.append_array(EXTRAS)
	return found


## "m", "f" or "" (unknown - the accent voices that don't say), read from the label ("... man", "... woman", "(F)").
static func gender(voice: Dictionary) -> String:
	var label: String = voice["label"]
	if label.contains("woman") or label.contains("(F)"):
		return "f"
	if label.contains("man"):
		return "m"
	return ""


## The voice with this id; an empty Dictionary if there is none.
static func find(voice_id: String) -> Dictionary:
	for voice in all():
		if voice["id"] == voice_id:
			return voice
	return {}


## The absolute OS path of a model file (the .onnx), whether or not it exists.
static func model_path(model: String) -> String:
	return ProjectSettings.globalize_path(VOICE_DIR + model + ".onnx")


static func model_installed(model: String) -> bool:
	return FileAccess.file_exists(VOICE_DIR + model + ".onnx") and FileAccess.file_exists(VOICE_DIR + model + ".onnx.json")


static func is_installed(voice_id: String) -> bool:
	var voice := find(voice_id)
	return not voice.is_empty() and model_installed(voice["model"])


static func installed() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for voice in all():
		if model_installed(voice["model"]):
			found.append(voice)
	return found


## Are all standard-voice models there?
static func standard_installed() -> bool:
	for model in STANDARD_MODEL_PATHS:
		if not model_installed(model):
			return false
	return true


## Are all extra (accent) models there?
static func extras_installed() -> bool:
	for model in EXTRA_MODEL_PATHS:
		if not model_installed(model):
			return false
	return true


## The first installed voice that is not `avoid_id` - what a character gets when its own voice is the story
## teller's (characters never sound like the story teller) or is not installed. The story teller's own
## voice if nothing else is installed.
static func alternative_to(avoid_id: String) -> Dictionary:
	for voice in installed():
		if voice["id"] != avoid_id:
			return voice
	return find(avoid_id)
