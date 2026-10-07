class_name MissionVariableMap
extends Resource

## One "take over from the mission" row of a chapter or side quest: when its mission ends, the final value
## of the mission variable `mission_variable` (a MissionData.custom_variables entry of that mission) is
## copied into the campaign variable `campaign_variable` (Campaign.writable_variables(), same type), before
## the chapter's win/lose effects run. That is how something that happened in a mission (an optional
## objective killed person A) steers the campaign (a side quest that needs person A never appears).

@export var mission_variable: String = ""
@export var campaign_variable: String = ""
