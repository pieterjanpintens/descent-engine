class_name NarratorVoices
extends RefCounted

## The catalogue of narration voices (Piper models, see PiperInstaller / Narrator). Never instantiated.
##
## A VOICE is a model plus - for the multi-speaker models - a speaker number, so one ~75 MB
## model carries many voices. The BASE voice (`BASE_ID`, installed together with the engine) is the
## default story teller; the EXTRA voices (accents: Irish, Scottish, Indian, Welsh, ... ) come with the
## one optional "extra voices" download (PiperInstaller.install_extras()).
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

const BASE := {"id": BASE_ID, "label": "Standard - American man", "model": BASE_MODEL, "speaker": -1}

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
]

## Where each extra model lives in the rhasspy/piper-voices repository (below the repo's root).
const EXTRA_MODEL_PATHS := {
	"en_GB-alba-medium": "en/en_GB/alba/medium",
	"en_GB-jenny_dioco-medium": "en/en_GB/jenny_dioco/medium",
	"en_GB-vctk-medium": "en/en_GB/vctk/medium",
	"en_US-arctic-medium": "en/en_US/arctic/medium",
	"en_US-l2arctic-medium": "en/en_US/l2arctic/medium",
}


## Every voice: the base one first, then the extras.
static func all() -> Array[Dictionary]:
	var found: Array[Dictionary] = [BASE]
	found.append_array(EXTRAS)
	return found


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


## Are all extra models there (the one optional download)?
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
