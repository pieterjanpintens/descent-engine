class_name LevelValue
extends Resource

## One row of a level-scaling table (MonsterArchetype.hitpoints_scaling /
## attack_scaling / defense_scaling): "for monster level min_level..max_level (both
## INCLUSIVE) the value is `value`". For a BASE template the value is the stat
## itself; for an ADDITIVE template it is what gets added to the base (so it may
## be negative).

@export_range(0, 99) var min_level: int = 1
@export_range(0, 99) var max_level: int = 99
@export_range(-9999, 9999) var value: int = 0


## How far `level` is outside this row's range (0 = inside).
func distance_to(level: int) -> int:
	if level < min_level:
		return min_level - level
	if level > max_level:
		return level - max_level
	return 0


## Independent copies of `list`.
static func copies(list: Array[LevelValue]) -> Array[LevelValue]:
	var result: Array[LevelValue] = []
	for row in list:
		var copy := LevelValue.new()
		copy.min_level = row.min_level
		copy.max_level = row.max_level
		copy.value = row.value
		result.append(copy)
	return result


static func has_rows(list: Array[LevelValue]) -> bool:
	return not list.is_empty()


## The table's value for `level` (call only when has_rows()): the row covering it,
## or - if the level falls outside every row - the CLOSEST row by absolute
## distance (level 8 with rows 1-2 and 3-4 uses the 3-4 row). On a tie (several
## rows cover the level, or are equally close) the highest value wins.
static func pick(list: Array[LevelValue], level: int) -> int:
	var best_distance := 1 << 30
	var best_value := 0
	for row in list:
		var distance := row.distance_to(level)
		if distance < best_distance or (distance == best_distance and row.value > best_value):
			best_distance = distance
			best_value = row.value
	return best_value
