class_name ShopListedRecipe
extends Resource

## A recipe an author puts in a recipe shop by hand (CampaignPlace.listed_recipes): it does not rotate. With a chapter it
## is a story recipe - on sale once that chapter has been won; without one it is always on sale. Gone once bought.

@export var recipe_id: String = ""
## Id of the chapter that must be won first ("" = always on sale).
@export var unlocked_by_chapter: String = ""
