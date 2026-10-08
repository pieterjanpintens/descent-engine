class_name NarratorCharacter
extends Resource

## A named speaker of a campaign or a mission (Campaign.characters / MissionData.characters). Text wrapped in
## `[Name]...[/Name]` (see NarrationMarkup) is read in this character's voice; the editors color it with `color`.
## Everything not wrapped is read by the story teller - the player's own choice in the options, never a
## character's voice (Narrator swaps a character's voice if it happens to be the story teller's).

@export var character_name: String = "Character"
## A NarratorVoices id.
@export var voice_id: String = NarratorVoices.BASE_ID
@export var color: Color = Color(0.95, 0.75, 0.3)
