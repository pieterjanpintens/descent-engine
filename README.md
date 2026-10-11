# Descent Engine

Tools for designing and playing custom missions and campaigns for *Descent: Legends of the Dark*, built around the
game's physical tiles, pillars and stairs. Made with Godot 4.7.2 (GDScript).

Unofficial fan project, not affiliated with Fantasy Flight Games or Asmodee. It ships none of the game's art or sounds,
only placeholders.

## Video

A walkthrough of the campaign player (click to watch on YouTube):

[![Campaign walkthrough](https://img.youtube.com/vi/Ha-fwiLSWd0/hqdefault.jpg)](https://youtu.be/Ha-fwiLSWd0)

## Setup for friends

Want the real game art and the game's own monster, weapon and item data in the app? Follow the step-by-step guide for
friends: [tools/asset_import/FRIENDS_GUIDE.md](tools/asset_import/FRIENDS_GUIDE.md). Every release has a small
`Descent-Engine-asset-tools.zip` with the tools it needs. You need your own copy of the game;
nothing is downloaded or shared.

## What it does

- **Mission Creator** - paint floors, hazards, props and pillars on a grid with the real tile shapes, group them into
  rooms, and add a story: objectives, triggers, variables, prop actions, tests and monster spawns.
- **Mission Player** - plays a saved mission at the table: round and phase loop, rooms revealed as you explore, hero
  party and weapons, combat against monsters with weaknesses, resistances and conditions, wounds, and a quest log.
- **Debugging missions** - *Play* in the Creator runs the mission you are editing without saving; in the Player F9 takes a snapshot, F10 rolls back to it,
  Ctrl+E returns to the editor, and a snapshot loads onto the mission as you changed it.
- **Campaigns** - missions as chapters on an act map, with branching paths, side quests, places to spend rewards, story
  chapters with questions and answers (that can branch), and variables shared with the missions.
- **Narration (optional)** - the story can be read aloud with offline voices, a voice per character and per hero, and
  the table can give spoken commands. Both are downloaded from inside the app on request.
