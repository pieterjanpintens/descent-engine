class_name Injuries
extends RefCounted

## The game's injury cards (names from the game data; their effects are on the physical cards and resolved at the table). Never instantiated.
## A hero's first wound gives a random NORMAL injury (the single-word cards), the second wound flips that card to its major side. The Ironbound Rune
## ("when you are wounded, you gain a unique injury") makes the wearer draw from the UNIQUE ones instead.

const NORMAL: Array[String] = ["Cautious", "Slowed", "Tired", "Frustrated", "Frantic", "Hesitant", "Cauterization"]
const UNIQUE: Array[String] = ["Hardened Skin", "Heavy Heart", "Heavy Hands"]
## The trinket that makes its wearer's injury a unique one.
const UNIQUE_TRINKET_ID := "TRINKET5_ID"


static func random_injury(unique: bool) -> String:
	var pool: Array[String] = UNIQUE if unique else NORMAL
	return pool.pick_random()
