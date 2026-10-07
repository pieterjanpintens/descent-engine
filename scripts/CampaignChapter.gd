class_name CampaignChapter
extends Resource

## One step of an act's path: the players play `mission_file` (a mission inside the
## campaign's folder) and, depending on how it ends, follow a link to the next chapter.
## A finale chapter ends the act when it is won. `map_position` is where its pin sits on
## the act's map, as a fraction of the map image (0..1 on both axes).

@export var id: String = ""
@export var title: String = "New chapter"
## File name (not a path) of the mission inside the campaign folder; "" = none chosen yet.
@export var mission_file: String = ""
@export_multiline var story_before: String = ""
@export_multiline var story_after: String = ""
@export var map_position: Vector2 = Vector2(0.5, 0.5)
@export var is_finale: bool = false
@export var links: Array[CampaignLink] = []
