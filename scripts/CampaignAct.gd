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
## Points of interest on the map (see CampaignPlace).
@export var places: Array[CampaignPlace] = []
## The experience counter is set to this when the act begins ("levels the board again");
## -1 = leave it as it is.
@export var start_experience: int = -1


func find_chapter(chapter_id: String) -> CampaignChapter:
	for chapter in chapters:
		if chapter.id == chapter_id:
			return chapter
	return null


func find_place(place_id: String) -> CampaignPlace:
	for place in places:
		if place.id == place_id:
			return place
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
## Every chapter of this act that has a link to `chapter_id`.
func predecessors(chapter_id: String) -> Array[CampaignChapter]:
	var found: Array[CampaignChapter] = []
	for chapter in chapters:
		for link in chapter.links:
			if link.target_id == chapter_id:
				found.append(chapter)
				break
	return found


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
		if chapter.wait_for_all:
			for before in predecessors(chapter.id):
				if not reachable.has(before.id):
					found.append("'%s' waits for '%s', which cannot be reached" % [chapter.title, before.title])
		if not reachable.has(chapter.id):
			found.append("'%s' cannot be reached from the start" % chapter.title)
		elif chapter.is_finale:
			finale_reachable = true
	if not finale_reachable:
		found.append("has no finale that can be reached")
	var attachment_names: Array[String] = []
	for attachment in AttachmentCatalog.all():
		attachment_names.append(attachment.attachment_name)
	for place in places:
		if place.unlocked_by_chapter != "" and find_chapter(place.unlocked_by_chapter) == null:
			found.append("place '%s' is unlocked by a chapter that no longer exists" % place.title)
		elif place.unlocked_by_chapter != "" and find_chapter(place.unlocked_by_chapter).is_finale:
			found.append("place '%s' is unlocked by a finale - winning it ends the act, so it could never be visited" % place.title)
		for offer in place.offers:
			if offer.attachment == "":
				found.append("'%s' (at '%s') gives nothing" % [offer.title, place.title])
			elif not attachment_names.has(offer.attachment):
				found.append("'%s' (at '%s') gives an unknown attachment '%s'" % [offer.title, place.title, offer.attachment])
	return found
