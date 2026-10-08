# Descent Engine

Tools for designing and playing custom missions and campaigns for *Descent: Legends of the Dark*, built around the
game's physical tiles, pillars and stairs. Made with Godot 4.7.2 (GDScript).

Unofficial fan project, not affiliated with Fantasy Flight Games or Asmodee. It ships none of the game's art or sounds,
only placeholders.

## Video

A walkthrough of the campaign player:
[Campaign.mp4](https://github.com/pieterjanpintens/descent-engine/releases/download/v0.0.11/Campaign.mp4)

## What it does

- **Mission Creator** - paint floors, hazards, props and pillars on a grid with the real tile shapes, group them into
  rooms, and add a story: objectives, triggers, variables, prop actions, tests and monster spawns.
- **Mission Player** - plays a saved mission at the table: round and phase loop, rooms revealed as you explore, hero
  party and weapons, combat against monsters with weaknesses, resistances and conditions, wounds, and a quest log.
- **Campaigns** - missions as chapters on an act map, with branching paths, side quests, places to spend rewards, story
  chapters with questions and answers (that can branch), and variables shared with the missions.
- **Narration (optional)** - the story can be read aloud with offline voices, a voice per character and per hero, and
  the table can give spoken commands. Both are downloaded from inside the app on request.
