class_name CampaignState
extends Resource

## A campaign in progress - the campaign save (CampaignIO.save_state()), separate from a
## mission save: where the party is on the campaign's map, which chapters are done, the heroes'
## progress and what the party owns. One save per campaign, in user://campaign_saves/.

@export var campaign_folder: String = ""
@export var current_act: int = 0
## Ids of the chapters the party has won.
@export var completed_chapters: Array[String] = []
@export var heroes: Array[HeroState] = []
@export var gold: int = 0
## Crafting materials: name -> count.
@export var materials: Dictionary = {}
## Names of the weapon attachments (AttachmentCatalog) the party owns.
@export var owned_attachments: Array[String] = []


## The state of hero `slot`, created (level 1, nothing equipped) the first time it is asked for.
func hero(slot: int) -> HeroState:
	for state in heroes:
		if state.hero_slot == slot:
			return state
	var created := HeroState.new()
	created.hero_slot = slot
	heroes.append(created)
	return created


## The party's level for the heroes in `roster` (HeroCatalog slots): their average level,
## rounded down. Missions can use it to scale their monsters up (planned).
func party_level(roster: Array[int], progression: HeroProgression) -> int:
	if roster.is_empty():
		return 1
	var total := 0
	for slot in roster:
		total += hero(slot).level(progression)
	@warning_ignore("integer_division")
	return total / roster.size()


func add_material(material_name: String, amount: int) -> void:
	materials[material_name] = maxi(int(materials.get(material_name, 0)) + amount, 0)


func mark_completed(chapter_id: String) -> void:
	if not completed_chapters.has(chapter_id):
		completed_chapters.append(chapter_id)
