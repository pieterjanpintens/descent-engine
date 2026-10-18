class_name TextDiff
extends RefCounted

## A word-level comparison of two texts, for showing what changed in a manuscript section or a chapter (PlanSync / SyncWindow).
## `diff()` returns the words in reading order as {op: "same"|"del"|"add", text}; line breaks are kept as their own "\n" words.
## Texts that are too long to compare cheaply give an empty result (the caller shows both texts instead). Never instantiated.

const MAX_CELLS := 9000000


## Words (and "\n" for a line break) of a text.
static func tokens(text: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("\\n|[^\\s]+")
	for match in regex.search_all(text):
		result.append(match.get_string())
	return result


## [] when the texts are too long to compare (or both are empty).
static func diff(old_text: String, new_text: String) -> Array[Dictionary]:
	var a := tokens(old_text)
	var b := tokens(new_text)
	var result: Array[Dictionary] = []
	# The common start and end need no comparing - most edits touch only a small part.
	var start := 0
	while start < a.size() and start < b.size() and a[start] == b[start]:
		start += 1
	var end_a := a.size()
	var end_b := b.size()
	while end_a > start and end_b > start and a[end_a - 1] == b[end_b - 1]:
		end_a -= 1
		end_b -= 1
	var n := end_a - start
	var m := end_b - start
	if (n + 1) * (m + 1) > MAX_CELLS:
		return result
	for idx in start:
		result.append({"op": "same", "text": a[idx]})
	# Longest common subsequence table over the middle part.
	var width := m + 1
	var table := PackedInt32Array()
	table.resize((n + 1) * width)
	for p in range(n - 1, -1, -1):
		for q in range(m - 1, -1, -1):
			if a[start + p] == b[start + q]:
				table[p * width + q] = table[(p + 1) * width + q + 1] + 1
			else:
				table[p * width + q] = maxi(table[(p + 1) * width + q], table[p * width + q + 1])
	var i := 0
	var j := 0
	while i < n and j < m:
		if a[start + i] == b[start + j]:
			result.append({"op": "same", "text": a[start + i]})
			i += 1
			j += 1
		elif table[(i + 1) * width + j] >= table[i * width + j + 1]:
			result.append({"op": "del", "text": a[start + i]})
			i += 1
		else:
			result.append({"op": "add", "text": b[start + j]})
			j += 1
	while i < n:
		result.append({"op": "del", "text": a[start + i]})
		i += 1
	while j < m:
		result.append({"op": "add", "text": b[start + j]})
		j += 1
	for k in range(end_a, a.size()):
		result.append({"op": "same", "text": a[k]})
	return result


## Whether anything differs.
static func changed(ops: Array[Dictionary]) -> bool:
	for op in ops:
		if op["op"] != "same":
			return true
	return false


## The comparison as BBCode for a RichTextLabel: removed words red and struck through, added words green.
static func to_bbcode(ops: Array[Dictionary], removed_color: String = "#e06c6c", added_color: String = "#7fcf7f") -> String:
	var out := ""
	var at_line_start := true
	for op in ops:
		var word: String = op["text"]
		if word == "\n":
			out += "\n"
			at_line_start = true
			continue
		var escaped := word.replace("[", "[lb]")
		if not at_line_start:
			out += " "
		at_line_start = false
		match op["op"]:
			"del":
				out += "[color=%s][s]%s[/s][/color]" % [removed_color, escaped]
			"add":
				out += "[color=%s]%s[/color]" % [added_color, escaped]
			_:
				out += escaped
	return out


## Plain text safe for a RichTextLabel (brackets escaped).
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")
