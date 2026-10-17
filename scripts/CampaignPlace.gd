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
## Id of the chapter that closes the place again once it is won ("" = never closes) - a pop-up shop, a travelling seller.
@export var closes_after_chapter: String = ""
@export var offers: Array[CampaignOffer] = []

## What the place is. OFFERS = the authored offers above (a camp, a special seller). MARKET = buy and sell crafting
## materials for gold. RECIPE_SHOP = sells recipes from a rotating stock (see ShopRotation). SMITHY = forges items from
## recipes the party owns and materials.
enum Kind { OFFERS, MARKET, RECIPE_SHOP, SMITHY }
@export var kind: Kind = Kind.OFFERS
## Recipe shop: how many recipes the rotating stock holds, and how many rotation steps (won chapters / side quests) a
## recipe is guaranteed to stay.
@export var stock_size: int = 4
@export var min_stay: int = 3
## Recipe shop: only offer recipes the party has reached in the game's own terms (XPRequiredForDrop <= the XP counter,
## and the recipe's act not beyond the campaign's current act). Off = every recipe may appear.
@export var respect_game_requirements: bool = true
## Recipe shop: recipes put in by hand next to the rotating ones (always on sale, or story recipes after a chapter).
@export var listed_recipes: Array[ShopListedRecipe] = []
