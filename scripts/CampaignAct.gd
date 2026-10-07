class_name CampaignAct
extends Resource

## One act of a campaign: a map with its chapters pinned on it, forming a (possibly
## branching) path from `start_chapter_id` to the act's finale(s). Winning a finale ends
## the act and the campaign moves on to the next act.

@export var act_name: String = "New act"
@export_multiline var intro: String = ""
## File name (not a path) of the map image inside the campaign folder; "" = no map (the
## editor shows a plain grid).
@export var map_image: String = ""
@export var start_chapter_id: String = ""
@export var chapters: Array[CampaignChapter] = []


func find_chapter(chapter_id: String) -> CampaignChapter:
	for chapter in chapters:
		if chapter.id == chapter_id:
			return chapter
	return null


## Ids of every chapter reachable from the start chapter by following links.
func reachable_ids() -> Array[String]:
	var seen: Array[String] = []
	var queue: Array[String] = []
	if find_chapter(start_chapter_id) != null:
		queue.append(start_chapter_id)
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if seen.has(current):
			continue
		seen.append(current)
		var chapter := find_chapter(current)
		if chapter == null:
			continue
		for link in chapter.links:
			if find_chapter(link.target_id) != null and not seen.has(link.target_id):
				queue.append(link.target_id)
	return seen


## Whether winning `chapter` leads somewhere (a link "on win" or "always").
func _has_way_forward(chapter: CampaignChapter) -> bool:
	for link in chapter.links:
		if link.outcome != CampaignLink.Outcome.LOSE and find_chapter(link.target_id) != null:
			return true
	return false


## Human-readable problems with this act's path - `mission_files` is what exists in the
## campaign folder. Empty = fine.
func problems(mission_files: Array[String]) -> Array[String]:
	var found: Array[String] = []
	if chapters.is_empty():
		found.append("has no chapters")
		return found
	if find_chapter(start_chapter_id) == null:
		found.append("has no start chapter")
	var reachable := reachable_ids()
	var finale_reachable := false
	for chapter in chapters:
		if chapter.mission_file == "":
			found.append("'%s' has no mission" % chapter.title)
		elif not mission_files.has(chapter.mission_file):
			found.append("'%s': mission file '%s' is missing" % [chapter.title, chapter.mission_file])
		for link in chapter.links:
			if find_chapter(link.target_id) == null:
				found.append("'%s' links to a chapter that no longer exists" % chapter.title)
		if not chapter.is_finale and not _has_way_forward(chapter):
			found.append("'%s' has no way forward (link it on win, or make it a finale)" % chapter.title)
		if not reachable.has(chapter.id):
			found.append("'%s' cannot be reached from the start" % chapter.title)
		elif chapter.is_finale:
			finale_reachable = true
	if not finale_reachable:
		found.append("has no finale that can be reached")
	return found
