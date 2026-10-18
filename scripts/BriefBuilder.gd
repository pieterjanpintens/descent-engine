class_name BriefBuilder
extends RefCounted

## Turns a mission BRIEF (MissionBrief) into an empty SKELETON MISSION file in the campaign folder and gives the chapter that file:
## a MissionData with the brief's objectives and variables and NO map - the author opens it in the mission editor and draws the
## map. No AI is involved; it is plain code on what the author reviewed.
##
## Objectives become the usual DAG: the 'win' objectives in the order given as a chain (the last one is the WIN leaf), each 'lose'
## objective as an independent LOSE root, the 'optional' ones on the first win objective. Every objective waits on its own bool
## variable (`objective_1_done`, `failure_1`, `optional_1_done`, default false) - an objective with no condition would count as
## reached at once - and the author wires those variables up (a prop action or trigger that sets them). The brief's own variables
## are declared too. A chapter that already has a mission is never touched. Never instantiated.


## Why a mission can't be made for this chapter ("" = it can).
static func problem(chapter: CampaignChapter, brief: Dictionary, folder: String) -> String:
	if chapter == null:
		return "The chapter is not in the campaign (build it from the plan first)."
	if chapter.is_narrative:
		return "This is a narrative chapter - it has no mission."
	if chapter.mission_file != "":
		return "The chapter already has a mission (%s)." % chapter.mission_file
	if CampaignIO.is_release(folder):
		return "A release cannot be changed."
	var has_win := false
	for objective in brief.get("objectives", []):
		if objective["kind"] == "win":
			has_win = true
	if not has_win:
		return "The brief needs at least one win objective (or a goal)."
	return ""


## Makes the skeleton mission from the brief, saves it in the campaign folder and sets `chapter.mission_file`; also records the file
## in the brief (`built_file`). Returns {ok, file, error}.
static func create_mission(chapter: CampaignChapter, brief: Dictionary, campaign: Campaign, folder: String) -> Dictionary:
	var blocked := problem(chapter, brief, folder)
	if blocked != "":
		return {"ok": false, "file": "", "error": blocked}
	var mission := skeleton(chapter.title, brief)
	var file_name := _free_file_name(folder, chapter.title)
	if not MissionIO.save_mission(mission, "%s/%s" % [CampaignIO.folder_path(folder), file_name]):
		return {"ok": false, "file": "", "error": "The mission file could not be saved."}
	chapter.mission_file = file_name
	brief["built_file"] = file_name
	return {"ok": true, "file": file_name, "error": ""}


## The skeleton MissionData (no file is written).
static func skeleton(mission_name: String, brief: Dictionary) -> MissionData:
	var mission := MissionData.new()
	mission.mission_name = mission_name
	var wins: Array[MissionObjective] = []
	var failures: Array[MissionObjective] = []
	var optionals: Array[MissionObjective] = []
	var win_number := 0
	var failure_number := 0
	var optional_number := 0
	for entry in brief.get("objectives", []):
		var variable_name := ""
		match entry["kind"]:
			"lose":
				failure_number += 1
				variable_name = "failure_%d" % failure_number
			"optional":
				optional_number += 1
				variable_name = "optional_%d_done" % optional_number
			_:
				win_number += 1
				variable_name = "objective_%d_done" % win_number
		var objective := MissionObjective.new()
		objective.id = mission.allocate_object_id()
		objective.description = entry["description"]
		var condition := Condition.new()
		condition.variable_name = variable_name
		condition.operator = Condition.Operator.EQUALS
		condition.value = true
		objective.conditions.append(condition)
		var variable := MissionVariable.new()
		variable.name = variable_name
		variable.type = MissionVariable.Type.BOOL
		variable.default_value = false
		mission.custom_variables.append(variable)
		match entry["kind"]:
			"lose":
				objective.outcome = MissionObjective.Outcome.LOSE
				failures.append(objective)
			"optional":
				optionals.append(objective)
			_:
				wins.append(objective)
	for i in wins.size():
		if i + 1 < wins.size():
			wins[i].children.append(wins[i + 1])
		else:
			wins[i].outcome = MissionObjective.Outcome.WIN
	if not wins.is_empty():
		for optional in optionals:
			wins[0].optional_objectives.append(optional)
		mission.objectives.append(wins[0])
	for failure in failures:
		mission.objectives.append(failure)
	for variable_raw in brief.get("variables", []):
		var variable := MissionVariable.new()
		variable.name = variable_raw["name"]
		variable.type = _type(variable_raw["type"])
		variable.default_value = variable_raw["default"]
		mission.custom_variables.append(variable)
	return mission


static func _type(type: String) -> MissionVariable.Type:
	match type:
		"int":
			return MissionVariable.Type.INT
		"float":
			return MissionVariable.Type.FLOAT
		"string":
			return MissionVariable.Type.STRING
	return MissionVariable.Type.BOOL


## A mission file name from the chapter title that doesn't exist in the campaign folder yet.
static func _free_file_name(folder: String, title: String) -> String:
	var base := CampaignIO.key_for(title)
	if base == "":
		base = "mission"
	var file_name := base + ".tres"
	var number := 2
	var existing := CampaignIO.mission_files(folder)
	while existing.has(file_name):
		file_name = "%s_%d.tres" % [base, number]
		number += 1
	return file_name
