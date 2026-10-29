class_name Journal
extends RefCounted

## The quest log's data: a plain, ordered replay of what the table was told
## during play (messages, stage setups, monster spawns, objective changes,
## attack results, the ending). Runtime-only, never saved in the mission
## file, and deliberately NOT authored - PlayerDialog records into it
## automatically whenever a caller passes a `log_title` (see
## PlayerDialog.ask_ok()/ask_narrative()), so level designers write nothing.
## Entries are plain Dictionaries ({round, title, pages}, title and pages as language maps, see LogText) so a Save
## can serialise them as-is. Never log anything that leaks hidden
## information (e.g. a Test's required successes) - callers pick what to log.

signal changed

## MissionPlayer sets this to return the current round (1 before play starts).
var round_provider: Callable

var entries: Array[Dictionary] = []


## `title` is a msgid of the app's texts, or a Callable / language map; every page is a Callable (built once per language, see LogText), a
## language map or - for text that is already finished - a plain String. The entry is stored for every language of the content.
func add(title: Variant, pages: Array) -> void:
	var round_number := 1
	if round_provider.is_valid():
		round_number = int(round_provider.call())
	var recorded: Array = []
	for page in pages:
		recorded.append(LogText.record(page))
	entries.append({"round": round_number, "title": LogText.record_title(title), "pages": recorded})
	changed.emit()
