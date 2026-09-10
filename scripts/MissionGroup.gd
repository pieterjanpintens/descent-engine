class_name MissionGroup
extends Resource

## A purely organizational node in the Creator's outline tree (see
## CreatorOutline.gd) - groups things placed on the map (e.g. "everything
## in this room") so an effect can eventually target the whole set at
## once ("when the door opens, make this group visible") rather than each
## object individually. Has no mesh/footprint of its own - a group's
## "location" is just whatever its members' locations happen to be.
##
## `visible` is the one property meant to cascade to a group's members
## (InteractableEntry already has its own per-object `props["visible"]` -
## see that script's doc comment). Stored here now so authoring isn't
## blocked, but nothing computes the cascade or reacts to it yet - the
## Story layer has no runtime variable/trigger evaluator at all yet (see
## claude.md's Story layer section), so wiring a group's visibility into
## an actual Effect is future work, not this pass.

@export var id: String = ""
@export var name: String = ""

## Empty = directly under the mission root. Otherwise another
## MissionGroup's id - groups can nest inside groups, this falls straight
## out of using a parent pointer instead of a group-owned children list
## (see CreatorOutline.gd's doc comment for why parent pointers were
## chosen).
@export var parent_id: String = ""

@export var visible: bool = true
