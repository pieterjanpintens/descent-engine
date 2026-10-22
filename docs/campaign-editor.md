# The campaign editor

Open it from the main menu: **Editors & Tools > Campaign Editor**. A campaign strings missions and short story chapters together into acts, with a map, a shop economy and variables that carry over. Each campaign lives in one folder (`campaigns/<name>/`) holding the campaign file, its missions and its pictures, so it can be shared as a unit.

Keys are in [hotkeys.md](hotkeys.md).

## Layout

- **Menu bar**: File (New, Open, Save, Release..., Playtest from the start, Continue playtest, Back to Menu) and Edit (Undo, Redo). On the right: the status text and the **Problems** button.
- **Map** (centre, large): the current act's map image with a pin for every chapter and place. Click a pin to select it, drag it to move it. Arrows show the links between chapters: green = on win, red = on lose, grey = always.
- **Toolbar** above the map: *Add chapter*, *Add place*, *Add side quest*, *Selection*.
- **Side panel** with three tabs: **General**, **Acts**, **Selection**.

**Problems** turns orange with a count when something is wrong (a chapter without a mission, an unreachable chapter, an act with no finale, a broken link, missing variables, an offer that gives nothing, and so on). Click it to read the list.

## Concepts

- A **campaign** has ordered **acts**.
- An **act** is a path of **chapters** from a start chapter to a finale, with its own map picture. Branching is allowed; a plain linear path is just a graph without branches.
- A **chapter** is either a **mission** (one mission file, played in the Player) or a **narrative** (a short story with questions, shown as a speech bubble on the map).
- **Links** say where to go next: *on win*, *on lose* or *always*. A lost mission with no "on lose" link is simply offered again.
- The party stands at a **frontier**: the chapters it may play now. Only those are shown on the map in the game. Winning the finale ends the act and starts the next; the last act ends the campaign.
- **Places** are points on the map where the party spends what it earns (markets, shops, smithy...).
- **Side quests** are optional missions that appear only while the party can play certain chapters and some conditions hold.

## General tab

- **Campaign**: name, introduction.
- **Book**: the cover picture (trimmed and scaled to a book cover).
- **Story**: *Writing workspace...* (see below), *Variables...*, *Starting equipment...*, *Characters...*, and *Markets pay (% of value)* (what a market gives for selling materials; 0 = no selling).
- *Consumables per player* and the optional **Tarnished Brooch** monster (leave it empty and the Brooch trinket is not in the game).

### Starting equipment
**Starting equipment...** sets what the party owns at the start: weapon cards (with a + to start them upgraded), parts B and C, runes, armor and trinkets. *Fill with the basic set* ticks the first weapon of every hero type. Every hero weapon type needs at least one, or the Problems list complains.

### Variables
Campaign variables work like mission variables. Built in: `experience`, `gold` (both writable) and `act_number` (read only). Chapters can write them when won or lost, hand them to a mission when it starts, and take them from the mission when it ends. Side quests and narrative steps can test them.

## Acts tab

The acts list (add, remove, move up / down), then for the selected act: name, introduction, the experience counter forced when the act begins (-1 keeps it), and the **Map image...** (your own picture; it is never shipped with the app).

## Selection tab

What you see depends on what is selected on the map.

### A chapter
- **Mission**: title, type (Mission or Narrative), the mission file (*Add mission...* copies one from your missions folder into the campaign), *start of act*, *act finale*.
- **Variables** (missions only): *Give to the mission when it starts* and *Take over from the mission when it ends*, as pairs of campaign and mission variable of the same type. Use this to carry results over, e.g. "was person A killed".
- **Links**: where the chapter leads on win / lose / always. *Wait for all chapters that lead here* makes a join; *Its links are a choice* closes the alternatives once one is won. Pins show small ALL / XOR tags for these.
- **Before mission** and **After mission**: story texts shown before and after. Voice tags work: `[Name]...[/Name]`.
- **After mission** also holds the effects when won / when lost (Set Variable and Math over the campaign variables) and the **Loot** (experience, gold, materials, cards, recipes) with an *Edit...* button that opens the loot dialog.

### A narrative chapter
**Edit story...** opens the full-screen story editor. The story is a list of **steps** on the left; for the selected step on the right:
1. the story text,
2. an optional question,
3. conditions: show this step only when...,
4. answers: each with its text, an optional reply, conditions (offered only when...), the effects of choosing it, and what happens next (continue, go to another step, or end the story).

The chosen answers' effects are applied together at the end, so quitting halfway changes nothing. A narrative chapter counts as won when finished.

### A place
Name, description, when it opens (after a chapter is won; "always" = from the start of the act), optionally when it closes and reopens, and its **type**:
- **Market**: buy and sell materials.
- **Recipe shop**: sells recipes from a rotating stock. Settings: stock size, the minimum stay of a recipe, a chance per tier (a tier is how rare a recipe is), and recipes you list by hand. The stock changes once per won chapter, is predictable from a saved seed (reloading doesn't reroll it), marks what leaves after the next chapter, and hints at what arrives next.
- **Smithy**: forge weapons, armor and trinkets from owned recipes and materials. Upgrades are recipes too.
- **Alchemist**: brew potions from owned potion recipes. Crafted potions are never used up.
- **Offers (authored)**: a hand-made list of things for gold and materials.

Changing a place's type deletes its offers and listed recipes (it asks first).

### A side quest
Mission, rewards, stories, the chapters it is offered at, and conditions on the campaign variables. A red *ENDING* tag on its star means that winning the chapter that offers it will make it disappear (switch the warning off per quest).

## Writing workspace

**Writing workspace...** (General tab) is a full-screen place to write your story outside the game data, with optional AI help.

- **Notes**: plain text notes per campaign (style guide, bible, characters, locations, outline, glossary) and **manuscripts**, one file per act, with a chapter per `##` heading. They stay private: they are never put in a released package.
- The writing box has character colours, spell check, **Dictate** and **AI** buttons.
- **Plan...** asks the AI to turn the manuscript and notes into a plan of acts, chapters, characters and variables. You tick what to keep, edit it, and **Build accepted items** creates them in the campaign (one undo step). Mission chapters get a **Brief...** (goal, objectives, monsters, map notes) and **Create the mission file** makes an empty skeleton mission with the objectives wired to variables; you draw the map in the mission editor. Chapters can be **combined** into one.
- **Sync** compares each built chapter with its manuscript section and shows differences word by word. Nothing changes without your say: update the chapter, update the manuscript, mark as reviewed, or stop tracking.

AI help is off until you turn it on in **Options > AI**.

## Testing

- **Playtest from the start** (**Ctrl+Enter**) opens the campaign player on a throwaway save called "Playtest". **Continue playtest** keeps going. In a playtest every chapter has *Count as won* / *Count as lost* buttons that run the normal rules (rewards, effects, links) without playing the mission. *Back to Editor* is in the Gear menu.
- Play a mission chapter in a playtest to see how it carries over, then come back.

## Releases, drafts and forks

- Everything you make is a **draft** and can be edited freely.
- **File > Release...** makes a frozen, versioned copy (a **release**), installed side by side with the draft. Releases are read-only; you can still Fork one to get a new editable draft. Saved games are bound to a release, so editing the draft can never break a player's save.
- A newer release of the same campaign offers **Update to vX...** on the Load page; it works on a copy of the save and tells you what would be lost first.
- The release can be saved as a `.descentpkg` file or published to the community list from the same dialog (see [other-tools.md](other-tools.md)).
