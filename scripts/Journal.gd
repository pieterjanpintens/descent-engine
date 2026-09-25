class_name Journal
extends RefCounted

## The quest log's data: a plain, ordered replay of what the table was told
## during play (messages, stage setups, monster spawns, objective changes,
## attack results, the ending). Runtime-only, never saved in the mission
## file, and deliberately NOT authored - PlayerDialog records into it
## automatically whenever a caller passes a `log_title` (see
## PlayerDialog.ask_ok()/ask_narrative()), so level designers write nothing.
## Entries are plain Dictionaries ({round, title, pages}) so a future Save
## can serialise them as-is. Never log anything that leaks hidden
## information (e.g. a Test's required successes) - callers pick what to log.

signal changed

## MissionPlayer sets this to return the current round (1 before play starts).
var round_provider: Callable

var entries: Array[Dictionary] = []


func add(title: String, pages: Array[String]) -> void:
	var round_number := 1
	if round_provider.is_valid():
		round_number = int(round_provider.call())
	entries.append({"round": round_number, "title": title, "pages": pages.duplicate()})
	changed.emit()
