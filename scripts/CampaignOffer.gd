class_name CampaignOffer
extends Resource

## One thing a place on the campaign map sells: it costs gold and/or materials and gives the
## party a weapon attachment (AttachmentCatalog part id - the "weapon part / upgrade" of the
## campaign; other kinds of reward can follow). `once` offers can be bought a single time.

@export var id: String = ""
@export var title: String = "New offer"
@export_multiline var description: String = ""
@export var cost_gold: int = 0
## Crafting materials it costs: name -> count.
@export var cost_materials: Dictionary = {}
## Name of the weapon attachment it gives ("" = none yet).
@export var attachment: String = ""
## Part id of the rune it gives ("" = none) - WeaponData.runes(); the party can then equip it at embark.
@export var rune: String = ""
@export var once: bool = true
