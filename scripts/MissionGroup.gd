class_name MissionGroup
extends OutlineNode

## A purely organizational node in the Creator's outline tree (see
## CreatorOutline.gd) - groups things placed on the map (e.g. "everything
## in this room") so an effect can eventually target the whole set at
## once ("when the door opens, make this group visible") rather than each
## object individually. Has no mesh/footprint of its own - a group's
## "location" is just whatever its members' locations happen to be.
##
## Entirely OutlineNode fields, no fields of its own (see that script's
## own comments) - still its own distinct class rather than just using
## OutlineNode directly, so mission.groups: Array[MissionGroup] and the
## outline tree's own SelectionType.GROUP checks (`is MissionGroup`, etc.)
## stay meaningful.
##
## `visible` is the one property meant to cascade to a group's members
## (each member already has its own `visible` too, same field, same
## reasoning). Stored here now so authoring isn't blocked, but nothing
## computes the cascade or reacts to it yet - the Story layer has no
## runtime variable/trigger evaluator at all yet (see claude.md's Story
## layer section), so wiring a group's visibility into an actual Effect
## is future work, not this pass.
