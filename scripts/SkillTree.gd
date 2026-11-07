class_name SkillTree
extends Resource

## A campaign's SKILL TREE: where a hero's 14 skill slots (the 11 skills and the 3 legends) sit and what it takes to buy them. Authored in the campaign editor (Skill tree...) and
## shared by every hero (slot N = skill N of each hero, see HeroData). A slot is a starting point (no parents) or opens as soon as ANY ONE of
## its parent skills is owned; it also has a skill-point cost and the first act it can be bought in. Skill points are earned by completing feats
## (`points_per_feat`) and every hero begins with `starting_points`. Campaign.skill_tree == null means the DEFAULT tree (default_tree()); nothing is stored until a campaign edits it.
##
## The defaults follow the game's own data where it has any: the costs (skills 1-4 cost 1, 5-7 cost 2, 8-10 cost 1/2/2, 11 costs 3, the legends 12-14 cost 1/2/3). The game has no
## skill-to-skill links, so the shape is ours: five starting points, three tier-2 skills each between two of them, two more skills and a capstone.
## The game's own acts are NOT used: a slot can be held back by ordinary conditions over the campaign's variables (`SkillTreeNode.conditions`, e.g.
## act_number >= 2 for "from the second act of this campaign"), and by default none is. Buying and owning skills is not built yet - this is the
## authored part only.

## The 11 skills of a hero and, as slots 12-14, the three legend cards (HeroData.slot_id()): a legend is bought like a skill, usually behind conditions.
const SLOTS := 14
const DEFAULT_COSTS: Array[int] = [1, 1, 1, 1, 2, 2, 2, 1, 2, 2, 3, 1, 2, 3]
## Slot -> its parents in the default tree; slots not listed are starting points.
const DEFAULT_PARENTS := {5: [1, 2], 6: [2, 3], 7: [3, 4], 9: [8, 5, 6, 7], 10: [8, 5, 6, 7], 11: [9, 10], 12: [5, 6, 7], 13: [12], 14: [13]}

@export var nodes: Array[SkillTreeNode] = []
## Skill points a completed feat pays.
@export var points_per_feat: int = 1
## Skill points every hero already has when the campaign starts (0 = none: they come from feats).
@export var starting_points: int = 0


static func default_tree() -> SkillTree:
	var tree := SkillTree.new()
	for number in range(1, SLOTS + 1):
		var node := SkillTreeNode.new()
		node.number = number
		node.cost = DEFAULT_COSTS[number - 1]
		for parent: int in DEFAULT_PARENTS.get(number, []):
			node.parents.append(parent)
		tree.nodes.append(node)
	return tree


## Whether this is exactly the default tree (nothing worth storing in a campaign).
func is_default() -> bool:
	var other := default_tree()
	if points_per_feat != other.points_per_feat or starting_points != other.starting_points or nodes.size() != other.nodes.size():
		return false
	for entry in nodes:
		var expected := other.node(entry.number)
		if expected == null or entry.cost != expected.cost or not entry.conditions.is_empty():
			return false
		var mine := entry.parents.duplicate()
		var wanted := expected.parents.duplicate()
		mine.sort()
		wanted.sort()
		if mine != wanted:
			return false
	return true


## The slot for a skill number, null when there is none.
func node(number: int) -> SkillTreeNode:
	for entry in nodes:
		if entry.number == number:
			return entry
	return null


## The skill numbers without parents (the starting points), in order.
func roots() -> Array[int]:
	var found: Array[int] = []
	for entry in nodes:
		if entry.parents.is_empty():
			found.append(entry.number)
	found.sort()
	return found


## What all slots cost together (what a hero spends to own every skill).
func total_cost() -> int:
	var total := 0
	for entry in nodes:
		total += entry.cost
	return total


## Whether a hero that owns the skill numbers `owned` may buy slot `number`: not owned yet, the slot's conditions hold, and it is a starting
## point or owns any one parent. `conditions_hold` is a Callable(conditions: Array[Condition]) -> bool that evaluates them against the campaign's
## variables (CampaignState.conditions_hold). The cost (skill points) is checked by whoever holds the points.
func can_learn(number: int, owned: Array, conditions_hold: Callable) -> bool:
	var entry := node(number)
	if entry == null or owned.has(number):
		return false
	if not entry.conditions.is_empty() and not conditions_hold.call(entry.conditions):
		return false
	if entry.parents.is_empty():
		return true
	for parent in entry.parents:
		if owned.has(parent):
			return true
	return false


## The slots a hero may buy right now.
func learnable(owned: Array, conditions_hold: Callable) -> Array[int]:
	var found: Array[int] = []
	for entry in nodes:
		if can_learn(entry.number, owned, conditions_hold):
			found.append(entry.number)
	found.sort()
	return found


## The slots that can be reached at all: starting points and everything that has a reachable parent (conditions and cost ignored).
func reachable() -> Array[int]:
	var found: Array[int] = []
	var changed := true
	while changed:
		changed = false
		for entry in nodes:
			if found.has(entry.number):
				continue
			var open := entry.parents.is_empty()
			for parent in entry.parents:
				open = open or found.has(parent)
			if open:
				found.append(entry.number)
				changed = true
	found.sort()
	return found


## The slots in rows for drawing: row 0 = the starting points, every other slot below ALL of its reachable parents (the longest way from a
## starting point; capped so a loop cannot run away); slots that cannot be reached go in a last row. Each row is sorted by number.
func layers() -> Array[Array]:
	var limit := nodes.size()
	var depth: Dictionary = {}
	for number in roots():
		depth[number] = 0
	for _pass in limit:
		var changed := false
		for entry in nodes:
			var best := -1
			for parent in entry.parents:
				if depth.has(parent):
					best = maxi(best, int(depth[parent]))
			if best >= 0 and not entry.parents.is_empty():
				var level := mini(best + 1, limit)
				if int(depth.get(entry.number, -1)) != level:
					depth[entry.number] = level
					changed = true
		if not changed:
			break
	var last := 0
	for level in depth.values():
		last = maxi(last, int(level))
	var rows: Array[Array] = []
	for entry in nodes:
		var level: int = depth.get(entry.number, last + 1)
		while rows.size() <= level:
			rows.append([])
		rows[level].append(entry.number)
	for list in rows:
		list.sort()
	return rows


## What is wrong with the tree: slots missing or doubled, a parent that does not exist or is the slot itself, negative cost, a slot that can
## never be bought (no way in from a starting point), a condition on a variable that does not exist (it would never hold), no starting point at all.
## `known_variables` = the campaign's variable names (empty = conditions not checked).
func problems(known_variables: Array[String] = []) -> Array[String]:
	var found: Array[String] = []
	var seen: Array[int] = []
	for entry in nodes:
		if seen.has(entry.number):
			found.append("Skill tree: slot %d appears twice" % entry.number)
		seen.append(entry.number)
		if entry.number < 1 or entry.number > SLOTS:
			found.append("Skill tree: slot %d does not exist (the heroes have slots 1-%d)" % [entry.number, SLOTS])
	for number in range(1, SLOTS + 1):
		if not seen.has(number):
			found.append("Skill tree: slot %d is missing" % number)
	if points_per_feat < 0:
		found.append("Skill tree: a feat cannot pay negative skill points")
	if starting_points < 0:
		found.append("Skill tree: the heroes cannot start with negative skill points")
	var reached := reachable()
	if not nodes.is_empty() and roots().is_empty():
		found.append("Skill tree: no starting point - every skill needs another one first")
	for entry in nodes:
		if entry.cost < 0:
			found.append("Skill tree: skill %d has a negative cost" % entry.number)
		for parent in entry.parents:
			if parent == entry.number:
				found.append("Skill tree: skill %d needs itself" % entry.number)
			elif node(parent) == null:
				found.append("Skill tree: skill %d needs skill %d, which does not exist" % [entry.number, parent])
		if not known_variables.is_empty():
			for condition in entry.conditions:
				if not known_variables.has(condition.variable_name):
					found.append("Skill tree: skill %d has a condition on \"%s\", a variable the campaign does not have" % [entry.number, condition.variable_name])
		if not reached.has(entry.number):
			found.append("Skill tree: skill %d can never be bought - nothing leads to it from a starting point" % entry.number)
	return found
