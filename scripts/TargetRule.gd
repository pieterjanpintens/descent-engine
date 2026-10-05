class_name TargetRule
extends Resource

## One "preferred target" rule of a monster: HOW it picks which hero to attack.
## A monster holds an ORDERED list of these (MonsterArchetype.target_rules, resolved
## onto RuntimeMonster.target_rules); MonsterTargeting.choose_target() tries them
## in order - the first rule that finds a hero wins - and falls back to a random
## hero when none does.

enum Kind {
	RANDOM,     ## a random hero
	RETALIATE,  ## the hero that most recently attacked this monster
	JUMP,       ## the hero whose weapon has the longest range
	TANK,       ## the hero whose weapon does the most damage
	SUPPRESS,   ## the hero that has attacked the most
	FOCUS,      ## the hero the monsters have targeted the most (pile on)
	SPREAD,     ## the hero the monsters have targeted the least
	FIXED_HERO, ## always one chosen hero (`hero_slot`)
	CASTER,     ## a hero with a magic-damage weapon
	FINISH,     ## the most wounded hero
	FRESH,      ## the least wounded hero
}

@export var kind: Kind = Kind.RANDOM
## FIXED_HERO only: the HeroCatalog slot of the hero to always target.
@export var hero_slot: int = 0


static func kind_name(kind: int) -> String:
	return str(Kind.keys()[kind]).capitalize()


## One-line explanation shown as the tooltip in the template editor.
static func description(kind: int) -> String:
	match kind:
		Kind.RANDOM:
			return "A random hero."
		Kind.RETALIATE:
			return "The hero that most recently attacked this monster (if any has)."
		Kind.JUMP:
			return "The hero whose weapon has the longest range (ties: random)."
		Kind.TANK:
			return "The hero whose weapon does the most damage (ties: random)."
		Kind.SUPPRESS:
			return "The hero that has attacked the most (ties: random; if nobody has attacked yet, the next rule decides)."
		Kind.FOCUS:
			return "The hero the monsters have targeted the most (ties: random; if none was targeted yet, the next rule decides)."
		Kind.SPREAD:
			return "The hero the monsters have targeted the least (ties: random)."
		Kind.FIXED_HERO:
			return "Always the chosen hero (if they are in play)."
		Kind.CASTER:
			return "A hero with a magic-damage weapon (ties: random; if nobody has one, the next rule decides)."
		Kind.FINISH:
			return "The most wounded hero (ties: random; if nobody is wounded, the next rule decides)."
		Kind.FRESH:
			return "The least wounded hero (ties: random)."
	return ""


func display_name() -> String:
	if kind == Kind.FIXED_HERO:
		return "Fixed hero (%s)" % HeroCatalog.slot_name(hero_slot)
	return kind_name(kind)


## Plain-data form for SaveGame (RuntimeMonster.to_dict()).
func to_dict() -> Dictionary:
	return {"kind": kind, "hero_slot": hero_slot}


static func from_dict(d: Dictionary) -> TargetRule:
	var rule := TargetRule.new()
	rule.kind = int(d.get("kind", Kind.RANDOM)) as Kind
	rule.hero_slot = int(d.get("hero_slot", 0))
	return rule


## Independent copies of `list` - a spawned monster must not share the
## design-time template's resources.
static func copies(list: Array[TargetRule]) -> Array[TargetRule]:
	var result: Array[TargetRule] = []
	for rule in list:
		result.append(from_dict(rule.to_dict()))
	return result
