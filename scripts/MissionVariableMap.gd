class_name MissionVariableMap
extends Resource

## One row linking a variable of a chapter's / side quest's mission with a campaign variable of the same
## type, in one of two directions (which list of the chapter it sits in says which):
## - `mission_outputs` ("take over from the mission"): when the mission ends, the final value of
##   `mission_variable` (a MissionData.custom_variables entry of that mission) is copied into the campaign
##   variable `campaign_variable` (Campaign.writable_variables()), before the chapter's win/lose effects run.
##   That is how something that happened in a mission (an optional objective killed person A) steers the
##   campaign (a side quest that needs person A never appears).
## - `mission_inputs` ("give to the mission"): when the mission starts, the current value of the campaign
##   variable `campaign_variable` (Campaign.all_variables()) is preset into `mission_variable`.

@export var mission_variable: String = ""
@export var campaign_variable: String = ""
