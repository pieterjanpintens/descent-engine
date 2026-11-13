class_name SaveUpdater
extends RefCounted

## Moving a campaign save game to a newer RELEASE of the same campaign - a deliberate action, never automatic, and never in place:
## the original save stays untouched on the version it was played on, and the update is a COPY saved next to the new release. If the
## new version turns out to be worse, the old save is still there. check() says first whether the new version fits the save.
## Never instantiated.


## The newest installed release of the campaign `folder` belongs to, when it is newer than `folder` itself ({} otherwise, and for drafts).
static func newer_release(folder: String) -> Dictionary:
	var entry := CampaignIO.release_entry(folder)
	if entry.is_empty():
		return {}
	var newest := CommunityLibrary.newest_version(str(entry["id"]))
	if newest != "" and CommunityLibrary.compare_versions(newest, str(entry["version"])) > 0:
		return CommunityLibrary.find(str(entry["id"]), newest)
	return {}


## Right after a new release of a campaign was installed: the save games on OLDER versions of it, as [{folder, key, name}] (empty = nothing to offer).
static func saves_to_update(new_entry: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if str(new_entry.get("type", "")) != SharePackage.TYPE_CAMPAIGN:
		return found
	for entry in CommunityLibrary.versions_of(str(new_entry.get("id", ""))):
		if CommunityLibrary.compare_versions(str(entry["version"]), str(new_entry.get("version", ""))) >= 0:
			continue
		var folder := str(entry["path"]).get_file()
		for key in CampaignIO.save_keys(folder):
			var saved := CampaignIO.load_state(folder, key)
			if saved != null:
				found.append({"folder": folder, "key": key, "name": saved.save_name if saved.save_name != "" else key})
	return found


## Moves every save in `candidates` (from saves_to_update()) to `new_entry` where check() allows it. {updated: Array[String] (save names), blocked: Array[String]
## ("name: first reason"), warnings: how many of the updated ones carry warnings}. Originals are never touched.
static func update_all(candidates: Array[Dictionary], new_entry: Dictionary) -> Dictionary:
	var updated: Array[String] = []
	var blocked: Array[String] = []
	var warned := 0
	var new_campaign := CampaignIO.load_campaign(str(new_entry["path"]).get_file())
	for candidate in candidates:
		var folder := str(candidate["folder"])
		var saved := CampaignIO.load_state(folder, str(candidate["key"]))
		var old_campaign := CampaignIO.load_campaign(folder)
		if new_campaign == null or saved == null or old_campaign == null:
			blocked.append("%s: %s" % [candidate["name"], TranslationServer.translate("the campaign could not be opened")])
			continue
		var report := check(saved, old_campaign, new_campaign, str(new_entry["path"]).get_file())
		var errors: Array = report["errors"]
		if not errors.is_empty():
			blocked.append("%s: %s" % [candidate["name"], str(errors[0])])
			continue
		if apply(saved, new_entry, new_campaign) == null:
			blocked.append("%s: %s" % [candidate["name"], TranslationServer.translate("the updated copy could not be saved")])
			continue
		updated.append(str(candidate["name"]))
		if not (report["warnings"] as Array).is_empty():
			warned += 1
	return {"updated": updated, "blocked": blocked, "warnings": warned}


## Does the new version fit this save? {errors: Array[String] (block the update), warnings: Array[String] (update possible, tell the player)}.
static func check(state: CampaignState, old_campaign: Campaign, new_campaign: Campaign, new_folder: String) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var new_chapters := {}
	for act in new_campaign.acts:
		for chapter in act.chapters:
			new_chapters[chapter.id] = chapter
	for id in state.completed_chapters:
		if not new_chapters.has(id):
			errors.append(TranslationServer.translate("Chapter \"%s\" that you already completed is not in the new version.") % _chapter_title(old_campaign, id))
	if not state.campaign_complete:
		if state.current_act < 0 or state.current_act >= new_campaign.acts.size():
			errors.append(TranslationServer.translate("The new version has no act %d (your save is in it).") % (state.current_act + 1))
		else:
			var act := new_campaign.acts[state.current_act]
			for id in state.available_chapters:
				var chapter := act.find_chapter(id)
				if chapter == null:
					errors.append(TranslationServer.translate("Chapter \"%s\", where you are now, is not in act %d of the new version.") % [_chapter_title(old_campaign, id), state.current_act + 1])
				elif not chapter.is_narrative and not chapter.coming_soon and not FileAccess.file_exists("%s/%s" % [CampaignIO.folder_path(new_folder), chapter.mission_file]):
					errors.append(TranslationServer.translate("The mission of chapter \"%s\" is missing from the new version.") % chapter.title)
	var new_quests := {}
	for quest in new_campaign.side_quests:
		new_quests[quest.id] = true
	for id in state.completed_side_quests:
		if not new_quests.has(id):
			warnings.append("A side quest you completed is not in the new version.")
	var new_offers := {}
	for act in new_campaign.acts:
		for place in act.places:
			for offer in place.offers:
				new_offers[offer.id] = true
	for id in state.purchased_offers:
		if not new_offers.has(id):
			warnings.append("A purchase you made is no longer offered in the new version (what you bought is kept).")
	var new_variables := {}
	for variable in new_campaign.variables:
		new_variables[variable.name] = variable
	for name in state.variables:
		if not new_variables.has(name):
			warnings.append(TranslationServer.translate("The variable \"%s\" no longer exists - its value is dropped.") % name)
	for name in new_variables:
		if not state.variables.has(name):
			warnings.append(TranslationServer.translate("The new variable \"%s\" starts at its default value.") % name)
	return {"errors": errors, "warnings": warnings}


## Writes the updated COPY of `state` for `new_entry` (a registry entry) and returns it (null when it could not be written).
## The original save is not touched.
static func apply(state: CampaignState, new_entry: Dictionary, new_campaign: Campaign) -> CampaignState:
	var copy := state.duplicate(true) as CampaignState
	var new_folder := str(new_entry["path"]).get_file()
	copy.campaign_folder = new_folder
	copy.campaign_id = str(new_entry["id"])
	copy.campaign_version = str(new_entry["version"])
	var base_name := "%s (v%s)" % [state.save_name, new_entry["version"]]
	var save_name := base_name
	var number := 2
	while CampaignIO.save_keys(new_folder).has(CampaignIO.save_key(save_name)):
		save_name = "%s %d" % [base_name, number]
		number += 1
	copy.save_name = save_name
	var variables := {}
	for variable in new_campaign.variables:
		variables[variable.name] = state.variables.get(variable.name, variable.default_value)
	copy.variables = variables
	var from_version: String = state.campaign_version if state.campaign_version != "" else "?"
	copy.add_log(func() -> String: return TranslationServer.translate("Moved to v%s") % new_entry["version"], [func() -> String: return TranslationServer.translate("This save game was moved from version %s of the campaign to version %s.") % [from_version, new_entry["version"]]])
	return copy if CampaignIO.save_state(copy) else null


static func _chapter_title(campaign: Campaign, id: String) -> String:
	if campaign != null:
		for act in campaign.acts:
			var chapter := act.find_chapter(id)
			if chapter != null:
				return chapter.title
	return id
