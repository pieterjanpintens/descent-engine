class_name MissionGroup
extends OutlineNode

## A purely organizational node in the Creator's outline tree (see
## CreatorOutline.gd) - groups things placed on the map (e.g. "everything
## in this room") so an effect can target the whole set at once ("when
## the door opens, make this group visible"). Has no mesh/footprint of its
## own - a group's "location" is just whatever its members' locations
## happen to be.
##
## Entirely OutlineNode fields, no fields of its own (see that script's
## own comments) - still its own distinct class rather than just using
## OutlineNode directly, so mission.groups: Array[MissionGroup] and the
## outline tree's own SelectionType.GROUP checks (`is MissionGroup`, etc.)
## stay meaningful.
##
## `visible` cascades to a group's members for real now (2026-09-14, see
## OutlineNode.visible's own doc) - MissionData.is_effectively_visible()
## walks a node's parent_id chain checking every ancestor GROUP's own
## visible too, so a group set invisible hides everything under it
## regardless of each individual member's own flag. Effect.Type.SHOW_STAGE
## ("the 'Show Stage' effect", see claude.md's Story layer section) is
## what flips a group's own visible to true as part of play - fired
## automatically for the starting room and authorable via a
## PropAction/MissionObjective's effects otherwise.
