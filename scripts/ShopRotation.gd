class_name ShopRotation
extends RefCounted

## The rotating stock of a recipe shop (never instantiated). A rotation step happens when the party wins a chapter or a
## side quest. Every recipe that appears stays for at least `min_stay` steps; after that it may leave. What leaves and what
## arrives next is decided ONE STEP AHEAD, so the shop can say honestly "this leaves after the next chapter" and give a
## vague rumour about what is coming - and the same seed + step always gives the same stock (reloading never rerolls).
##
## A shop is {"stock": [{id, since, leaving}], "incoming": [ids]}.

const LEAVE_CHANCE := 0.5


## Moves `shop` to `step`. `pool` = the recipe ids that may appear (not owned, not listed by hand, eligible), in a stable order.
static func rotate(shop: Dictionary, step: int, pool: Array[String], size: int, min_stay: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1000003 + step
	var stock: Array[Dictionary] = []
	var present: Array[String] = []
	var removed: Array[String] = []
	# 1. the ones announced as leaving go, and so does anything no longer in the pool (bought, owned...)
	for entry: Dictionary in shop.get("stock", []):
		var id := str(entry["id"])
		if bool(entry.get("leaving", false)) or not pool.has(id):
			removed.append(id)
			continue
		stock.append({"id": id, "since": int(entry["since"]), "leaving": false})
		present.append(id)
	# 2. the announced arrivals come in (if they still can)
	for id: String in shop.get("incoming", []):
		if stock.size() < size and pool.has(id) and not present.has(id):
			stock.append({"id": id, "since": step, "leaving": false})
			present.append(id)
	# 3. still short (first fill, or an announced recipe fell through): draw at random
	for id in _shuffled(_candidates(pool, present, removed), rng):
		if stock.size() >= size:
			break
		stock.append({"id": id, "since": step, "leaving": false})
		present.append(id)
	# 4. decide who leaves at the NEXT rotation: only recipes that will have stayed min_stay steps by then
	var leaving := 0
	for entry in stock:
		if step + 1 - int(entry["since"]) >= min_stay and rng.randf() < LEAVE_CHANCE:
			entry["leaving"] = true
			leaving += 1
	# 5. announce the arrivals for the next rotation: one for every slot that opens up
	var incoming: Array[String] = []
	var slots := size - (stock.size() - leaving)
	for id in _shuffled(_candidates(pool, present, []), rng):
		if incoming.size() >= slots:
			break
		incoming.append(id)
	return {"stock": stock, "incoming": incoming}


static func _candidates(pool: Array[String], present: Array[String], excluded: Array[String]) -> Array[String]:
	var list: Array[String] = []
	for id in pool:
		if not present.has(id) and not excluded.has(id):
			list.append(id)
	return list


static func _shuffled(list: Array[String], rng: RandomNumberGenerator) -> Array[String]:
	var result := list.duplicate()
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: String = result[i]
		result[i] = result[j]
		result[j] = swap
	return result
