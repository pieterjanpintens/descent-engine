class_name HighlightArea
extends OutlineNode

## A set of floor squares the author drew for an effect to light up (2026-11-15): "climb the tree - on a success you land on one of the
## highlighted squares". Tile squares (1-based "game unit" coordinates, same as MonsterSpawn.cells / LosBlocker.cells; the y is the level the
## square was drawn on). Nothing is shown to the players until a Highlight Area effect (Effect.Type.HIGHLIGHT_AREA) points at it - then the
## squares light up on the map, the table is told what to do (place the hero on one of them) and the lighting goes out again when they
## confirm. An OutlineNode entity like the spawn areas, so it can sit in a group (a stage) and moves / turns with it. Drawn in the Creator
## with the Palette Misc tab's Highlight Area tool.
@export var cells: Array[Vector3i] = []
