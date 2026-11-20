class_name MonsterTargeting
extends RefCounted

## Picks which hero a monster attacks, from its ordered target rules
## (RuntimeMonster.target_rules - see TargetRule.Kind for what each rule means).
## Never instantiated; pure functions over the data passed in, so it is easy to
## test. NOT wired into a monster turn yet (monsters don't attack in the Player);
## MissionRuntime.choose_target() is the entry point for when they do.

const _LOWEST := -(1 << 30)

## `roster`: the hero slots in play. `context`: the game state the rules read, all
## optional (missing = empty) - "weapons" (slot -> Array[Weapon], the two weapons
## each hero brought), "attacks_made" (slot -> attacks the hero made),
## "times_targeted" (slot -> times monsters targeted the hero), "wounds" (slot ->
## wound count), and - only when positions are tracked - "distances" (slot -> steps
## from the monster; the NEAREST rule uses it) and "prefer" (slots
## that win a tie, e.g. heroes standing next to a barricade). `rng` is optional (tests pass a seeded one). Returns the chosen hero
## slot, or -1 if the roster is empty. Rules are tried in order and the first one
## that finds a hero wins; if none does (e.g. Retaliate before anyone has attacked)
## the target is a random hero.
static func choose_target(monster: RuntimeMonster, roster: Array[int], context: Dictionary, rng: RandomNumberGenerator = null) -> int:
	if roster.is_empty():
		return -1
	var chosen := -1
	# a Monster Target effect (the mission's author asked for it) comes first
	if monster.forced_target_rule != null:
		chosen = _apply(monster.forced_target_rule, monster, roster, context, rng)
	# Duelist (defense ability): the last hero who attacked it first.
	if chosen == -1 and monster.defense_ability_off == 0 and DefenseRules.retaliates(monster) and roster.has(monster.last_attacker):
		chosen = monster.last_attacker
	for rule in monster.target_rules:
		if chosen != -1:
			break
		var picked := _apply(rule, monster, roster, context, rng)
		if picked != -1:
			chosen = picked
			break
	if chosen == -1:
		# nothing decided: a random hero (when positions are tracked, `roster` is already only the heroes it can attack this
		# activation, so the attacks spread over the party; a template that should gang up uses the Nearest or Focus rule)
		chosen = _random(roster, rng)
	# Shadowstone Bracers: a hero the monster is "less likely to target" - half the time the pick moves to another hero.
	if monster.shadowed_heroes.has(chosen) and roster.size() > 1:
		var roll := rng.randf() if rng != null else randf()
		if roll < 0.5:
			var others: Array[int] = []
			for slot in roster:
				if slot != chosen:
					others.append(slot)
			chosen = _random(others, rng)
	return chosen


static func _apply(rule: TargetRule, monster: RuntimeMonster, roster: Array[int], context: Dictionary, rng: RandomNumberGenerator) -> int:
	var weapons: Dictionary = context.get("weapons", {})
	var attacks_made: Dictionary = context.get("attacks_made", {})
	var times_targeted: Dictionary = context.get("times_targeted", {})
	var wounds: Dictionary = context.get("wounds", {})
	var prefer: Array = context.get("prefer", [])
	match rule.kind:
		TargetRule.Kind.RANDOM:
			return _random(roster, rng, prefer)
		TargetRule.Kind.NEAREST:
			return _nearest(roster, rng, context)
		TargetRule.Kind.RETALIATE:
			return monster.last_attacker if roster.has(monster.last_attacker) else -1
		TargetRule.Kind.JUMP:
			return _highest(roster, rng, func(slot: int) -> int: return _best_weapon_value(weapons.get(slot, []), true), prefer)
		TargetRule.Kind.TANK:
			return _highest(roster, rng, func(slot: int) -> int: return _best_weapon_value(weapons.get(slot, []), false), prefer)
		TargetRule.Kind.SUPPRESS:
			return _highest_if_any(roster, rng, attacks_made, prefer)
		TargetRule.Kind.FOCUS:
			return _highest_if_any(roster, rng, times_targeted, prefer)
		TargetRule.Kind.SPREAD:
			return _highest(roster, rng, func(slot: int) -> int: return -int(times_targeted.get(slot, 0)), prefer)
		TargetRule.Kind.FIXED_HERO:
			return rule.hero_slot if roster.has(rule.hero_slot) else -1
		TargetRule.Kind.CASTER:
			var casters: Array[int] = []
			for slot in roster:
				if _has_magic_weapon(weapons.get(slot, [])):
					casters.append(slot)
			return _random(casters, rng, prefer)
		TargetRule.Kind.FINISH:
			return _highest_if_any(roster, rng, wounds, prefer)
		TargetRule.Kind.FRESH:
			return _highest(roster, rng, func(slot: int) -> int: return -int(wounds.get(slot, 0)), prefer)
	return -1


## The highest range (`by_range`) or damage among a hero's weapons (0 if none).
static func _best_weapon_value(weapons: Array, by_range: bool) -> int:
	var best := 0
	for weapon: Weapon in weapons:
		best = maxi(best, weapon.weapon_range if by_range else weapon.damage)
	return best


static func _has_magic_weapon(weapons: Array) -> bool:
	for weapon: Weapon in weapons:
		for kind in weapon.damage_types:
			if Vulnerability.is_magic(kind):
				return true
	return false


## The slot with the highest count in `counts` (slot -> int), a random one among
## those tied - or -1 if every count is 0 (the rule has nothing to go on).
static func _highest_if_any(roster: Array[int], rng: RandomNumberGenerator, counts: Dictionary, prefer: Array = []) -> int:
	var most := 0
	for slot in roster:
		most = maxi(most, int(counts.get(slot, 0)))
	if most == 0:
		return -1
	return _highest(roster, rng, func(slot: int) -> int: return int(counts.get(slot, 0)), prefer)


## The slot with the highest `score` - a random one among those tied.
static func _highest(roster: Array[int], rng: RandomNumberGenerator, score: Callable, prefer: Array = []) -> int:
	var best_score := _LOWEST
	var tied: Array[int] = []
	for slot in roster:
		var value: int = score.call(slot)
		if value > best_score:
			best_score = value
			tied = [slot]
		elif value == best_score:
			tied.append(slot)
	return _random(tied, rng, prefer)


## The hero the fewest steps away (context "distances", slot -> steps) - a random one among those tied; -1 when positions are not tracked.
static func _nearest(roster: Array[int], rng: RandomNumberGenerator, context: Dictionary) -> int:
	if not context.has("distances"):
		return -1
	var distances: Dictionary = context["distances"]
	return _highest(roster, rng, func(slot: int) -> int: return -int(distances.get(slot, 1 << 20)), context.get("prefer", []))


## A random one of `slots`; when some of them are in `prefer` only those are considered.
static func _random(slots: Array[int], rng: RandomNumberGenerator, prefer: Array = []) -> int:
	if slots.is_empty():
		return -1
	if not prefer.is_empty():
		var preferred: Array[int] = []
		for slot in slots:
			if prefer.has(slot):
				preferred.append(slot)
		if not preferred.is_empty():
			slots = preferred
	var index := rng.randi_range(0, slots.size() - 1) if rng != null else randi() % slots.size()
	return slots[index]
