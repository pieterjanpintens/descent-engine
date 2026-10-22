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
## Id of the chapter that opens a closed place again once it is won ("" = stays closed) - the shop is back after a mid-act fight. Its stock
## and rotation are kept while it is closed. Only used together with `closes_after_chapter`.
@export var reopens_after_chapter: String = ""
@export var offers: Array[CampaignOffer] = []

## What the place is. OFFERS = the authored offers above (a camp, a special seller). MARKET = buy and sell crafting
## materials for gold. RECIPE_SHOP = sells recipes from a rotating stock (see ShopRotation). SMITHY = forges items from
## recipes the party owns and materials. ALCHEMIST = the same for consumable (potion) recipes: brews potions.
enum Kind { OFFERS, MARKET, RECIPE_SHOP, SMITHY, ALCHEMIST }
@export var kind: Kind = Kind.OFFERS
## Recipe shop: how many recipes the rotating stock holds, and how many rotation steps (won chapters / side quests) a
## recipe is guaranteed to stay.
@export var stock_size: int = 4
@export var min_stay: int = 3
## Recipe shop: the chance of each tier (RecipeData.tier(): the game's XP gate, tier 1 = 4 XP, tier 2 = 5 XP...) to supply the rotating
## stock - index 0 is tier 1. Relative numbers, not percentages that have to add up to 100: 0 = that tier never appears. The party's XP
## counter and the game's act of a recipe play no part. Story-only recipes (tier 0) never rotate in by themselves; list them by hand.
@export var tier_weights: Array[int] = [50, 30, 15, 4, 1]  # mostly common recipes, now and then a rare one


func tier_weight(tier: int) -> int:
	return maxi(tier_weights[tier - 1], 0) if tier >= 1 and tier <= tier_weights.size() else 0
## Recipe shop: recipes put in by hand next to the rotating ones (always on sale, or story recipes after a chapter).
@export var listed_recipes: Array[ShopListedRecipe] = []
