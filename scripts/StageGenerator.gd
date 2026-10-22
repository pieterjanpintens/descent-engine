class_name StageGenerator
extends Node

## Asks the AI (optional - AiClient.is_configured()) to design ONE area of a mission - a "stage" - from a description in words ("the first
## area is a crossroad, on each end a staircase with a door"). The answer is a map plan (see MapPlanValidator); every answer is checked by
## the validator and, when it has errors, handed back to the AI with the exact problems and a picture of what it built, up to MAX_ATTEMPTS
## times. Nothing is built into a mission here (StageBuilder does that) and nothing is sent unless the author presses the button.
## Experimental (branch experiment/stage-generation).

const MAX_TOKENS := 6000
const MAX_ATTEMPTS := 4
const TIMEOUT_SEC := 240.0

## Tests give this a stub that overrides ask().
var client: AiClient

var _busy := false
var _cancelled := false
## Progress for the dialog: called with a short status line before every attempt.
var on_status: Callable = Callable()


func is_busy() -> bool:
	return _busy or (client != null and client.is_busy())


func cancel() -> void:
	_cancelled = true
	if client != null:
		client.cancel()


## options: {name: String, heroes_start: bool, max_players: int (1-6), used: Dictionary (physical group -> copies the rest of the mission uses)}.
## Returns {ok (no errors left), plan, result (the validator's), picture, issues, attempts, error, cancelled}; `plan` and `result` are the best
## attempt even when it still has errors, so the author can see what the AI got stuck on.
func generate(description: String, options: Dictionary = {}) -> Dictionary:
	if _busy:
		return _fail("A stage is already being made.")
	if description.strip_edges() == "":
		return _fail("Describe the area first.")
	if client == null:
		client = AiClient.new()
		client.timeout_sec = TIMEOUT_SEC
		add_child(client)
	_busy = true
	_cancelled = false
	var heroes_start: bool = options.get("heroes_start", false)
	var validation := {"require_start": heroes_start, "used": options.get("used", {})}
	var system := system_prompt(options.get("used", {}))
	var user := user_prompt(description, options)
	var best: Dictionary = {}
	var last_error := ""
	var tries := 0
	for attempt in MAX_ATTEMPTS:
		tries += 1
		if on_status.is_valid():
			on_status.call("Asking the AI (attempt %d of %d)..." % [attempt + 1, MAX_ATTEMPTS])
		var answer := await client.ask(system, user, MAX_TOKENS)
		if _cancelled or answer.get("cancelled", false):
			_busy = false
			var cancelled := _fail("Cancelled.")
			cancelled["cancelled"] = true
			return cancelled
		if not answer["ok"]:
			_busy = false
			return _fail(str(answer["error"]))
		var plan := parse_plan(str(answer["text"]))
		if plan.is_empty():
			last_error = "The AI's answer was not a map plan (no JSON found)."
			user = user_prompt(description, options) + "\n\nYour previous answer was not a JSON object. Answer with ONE JSON object and nothing else."
			continue
		plan["max_players"] = clampi(int(options.get("max_players", 6)), 1, 6)
		if not heroes_start:
			plan.erase("player_start")
		plan.erase("spawns")
		var result := MapPlanValidator.validate(plan, validation)
		var errors: Array = result["errors"]
		var entry := {"plan": plan, "result": result, "errors": errors.size()}
		if best.is_empty() or errors.size() < int(best["errors"]):
			best = entry
		if errors.is_empty():
			break
		user = repair_prompt(description, options, plan, result)
	_busy = false
	if best.is_empty():
		return _fail(last_error if last_error != "" else "The AI did not answer with a map plan.")
	var final_result: Dictionary = best["result"]
	return {
		"ok": (final_result["errors"] as Array).is_empty(), "plan": best["plan"], "result": final_result,
		"picture": MapPlanValidator.render_stack(final_result), "issues": MapPlanValidator.format_issues(final_result),
		"attempts": tries, "error": "", "cancelled": false,
	}


## The JSON object in the AI's answer (fences or a sentence around it are fine), or {}.
static func parse_plan(answer: String) -> Dictionary:
	var text := answer.strip_edges()
	var first := text.find("{")
	var last := text.rfind("}")
	if first == -1 or last <= first:
		return {}
	var parsed: Variant = JSON.parse_string(text.substr(first, last - first + 1))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("pieces", null)) != TYPE_ARRAY:
		return {}
	return parsed


static func system_prompt(used: Dictionary = {}) -> String:
	return "\n\n".join([
		"You design ONE area (a \"stage\") of a tactical board-game mission for a digital companion of a physical tile game. The board is built from the physical pieces listed below; the players build exactly what you describe. From the author's description, answer with a MAP PLAN: ONE JSON object and nothing else (no markdown, no explanation).",
		"The shape:\n{\"pieces\": [{\"mesh\": \"7a\", \"x\": 0, \"z\": 0, \"rotation\": 0, \"height\": 0, \"name\": \"\"}, ...], \"player_start\": [{\"x\": 1, \"z\": 1, \"height\": 0}, ...]}\n- mesh: a piece name from the lists below.\n- x, z: tile-square coordinates (whole numbers; pillars also half units). A piece's position is the top-left corner of the area it covers. Use coordinates around 0..30.\n- rotation: quarter turns 0-3. height: 0 for the ground (see the rules for raised floors). name: optional short label (e.g. \"north door\").\n- player_start: only when the author says the heroes start here: one square for every hero that may play (the number is given), on floor.",
		"How to build: lay FLOOR tiles edge to edge so the walkable area has the shape the author describes (tiles may only touch, never overlap; leave out tiles you do not need; use only free copies). Then add props (doors, stairs, furniture, ...) standing ON that floor. Everything walkable must be connected. Prefer few, simple pieces; when a tile has the right shape (a cross for a crossroad) use it.",
		"RULES OF THE GAME BOARD:\n" + BuildRules.describe(),
		"PIECES:\n" + MapPieceCatalog.describe(used),
	])


static func user_prompt(description: String, options: Dictionary) -> String:
	var lines: Array[String] = []
	var name_text := str(options.get("name", "")).strip_edges()
	if name_text != "":
		lines.append("Stage name: " + name_text)
	lines.append("Description of the area:\n" + description.strip_edges())
	if options.get("heroes_start", false):
		lines.append("The heroes START in this area: give %d player_start squares (up to %d heroes may play)." % [int(options.get("max_players", 6)), int(options.get("max_players", 6))])
	else:
		lines.append("The heroes do NOT start here - do not give player_start.")
	return "\n\n".join(lines)


static func repair_prompt(description: String, options: Dictionary, plan: Dictionary, result: Dictionary) -> String:
	return "\n\n".join([
		user_prompt(description, options),
		"Your previous plan:\n" + JSON.stringify(plan),
		"The checker found these problems:\n" + MapPlanValidator.format_issues(result),
		"This is what your plan builds (height 0 first; '.' floor, '#' solid piece, 'x' removable solid (door), 'o' walkable piece, 'S' hero start):\n" + MapPlanValidator.render_stack(result),
		"Fix ALL the errors and answer with the complete corrected plan as ONE JSON object and nothing else.",
	])


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "plan": {}, "result": {}, "picture": "", "issues": "", "attempts": 0, "error": message, "cancelled": false}
