class_name CampaignPlace
extends Resource

## A point of interest on an act's map (a camp, a smith, a market...): the party can visit it
## to spend gold and materials on its offers. It shows on the map once its chapter is won
## (`unlocked_by_chapter`; "" = from the start of the act). `map_position` is a fraction (0..1)
## of the map image, like a chapter's.

@export var id: String = ""
@export var title: String = "New place"
@export_multiline var description: String = ""
@export var map_position: Vector2 = Vector2(0.5, 0.5)
## Id of the chapter that must be won first ("" = always available).
@export var unlocked_by_chapter: String = ""
@export var offers: Array[CampaignOffer] = []
