class_name PlayerCommandRunner
extends RefCounted

## Runs a typed or spoken command in the Player: parses it with
## VoiceCommandParser, asks the table about anything missing or ambiguous
## (which monster/object? which hero?), then calls the same
## PlayerInteractionController method a portrait drag ends in - attack() for
## "attack green bandit", interact() for "use the pile of dirt". Text in,
## dialogs and game actions out - the only piece that knows both sides.
##
## Wired by MissionPlayer once the runtime exists (plain vars, same
## post-construction pattern as PlayerInteractionController.mission_runtime).

var runtime: MissionRuntime
var dock: PlayerInteractionController
var dialog: PlayerDialog
var labels: InteractionLabels  ## the objects that can be interacted with right now
var roster: Array[int] = []  ## HeroCatalog slots in the party
## Provided by MissionPlayer (they need scene access this class doesn't have):
var end_phase: Callable  ## () -> void, may await
var set_monster_view: Callable  ## (shown: bool) -> void


## CONTEXT: while a dialog is open the speech is an ANSWER to it ("sword",
## "three", "ok" - see PlayerDialog.try_voice_answer()), not a new command, so
## a command can never stack on top of another question.
func run(text: String) -> void:
	if text.strip_edges() == "" or runtime == null:
		return
	if dialog.visible:
		dialog.try_voice_answer(text)
		return

	var objects: Array = []
	if labels != null:
		labels.refresh()  # up to date, not up to 0.3 s stale
		objects = labels.labelled()
	var command := VoiceCommandParser.parse(text, runtime.monsters, objects)
	if command["error"] != "":
		await dialog.ask_ok(command["error"])
		return
	match command["verb"]:
		"interact":
			await _run_interact(command)
		"end_phase":
			await end_phase.call()
		"show_monsters":
			set_monster_view.call(true)
		"show_map":
			set_monster_view.call(false)
		_:
			await _run_attack(command)


func _run_attack(command: Dictionary) -> void:
	# Which monster - several can match ("attack bandit" with two bandits).
	var matches: Array = command["monsters"]
	var monster: RuntimeMonster = matches[0]
	if matches.size() > 1:
		var names: Array[String] = []
		for candidate: RuntimeMonster in matches:
			names.append(_monster_label(candidate))
		var picked: int = await dialog.ask_choice("Which monster?", names)
		if picked < 0:
			return
		monster = matches[picked]

	var slot := await _pick_hero(command["hero_slot"], "Who attacks the %s?" % _monster_label(monster))
	if slot == -1:
		return
	# No confirmation step: the point of voice control is to avoid mouse
	# clutter. (A misheard target is still caught by the "Which monster?" /
	# "Who attacks?" questions when the command is ambiguous, and by the parser
	# refusing anything that doesn't match a live monster.)
	await dock.attack(slot, monster, command["weapon_text"], command["successes"])


func _run_interact(command: Dictionary) -> void:
	# Which object - "use exploration" with two exploration tokens matches both.
	var matches: Array = command["objects"]
	var item: Dictionary = matches[0]
	if matches.size() > 1:
		var names: Array[String] = []
		for candidate: Dictionary in matches:
			names.append(candidate["label"])
		var picked: int = await dialog.ask_choice("Which one?", names)
		if picked < 0:
			return
		item = matches[picked]

	var slot := await _pick_hero(command["hero_slot"], "Who uses the %s?" % item["label"])
	if slot == -1:
		return
	# The prop's own picker (if it has several available actions) follows.
	await dock.interact(slot, item["entry"])


## The acting hero: the one spoken ("hero two"), the only one in the party, or
## asked. Returns the HeroCatalog slot, or -1 to abort (cancelled / not in the
## party).
func _pick_hero(spoken_slot: int, question: String) -> int:
	if spoken_slot != -1:
		if roster.has(spoken_slot):
			return spoken_slot
		await dialog.ask_ok("%s is not in the party." % HeroCatalog.slot_name(spoken_slot))
		return -1
	if roster.size() == 1:
		return roster[0]
	var hero_labels: Array[String] = []
	for hero_slot in roster:
		hero_labels.append(HeroCatalog.slot_name(hero_slot))
	var picked: int = await dialog.ask_choice(question, hero_labels)
	return roster[picked] if picked >= 0 else -1


## "Green Bandit" - chip colour plus the monster's display name.
func _monster_label(monster: RuntimeMonster) -> String:
	return "%s %s" % [MonsterChip.display_name(monster.chip), monster.display_name()]
