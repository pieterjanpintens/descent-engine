# Other tools and dialogs

The mission editor and campaign editor have their own pages: [mission-editor.md](mission-editor.md), [campaign-editor.md](campaign-editor.md). All keys: [hotkeys.md](hotkeys.md).

## Main menu

| Entry | Opens |
|---|---|
| Load game / New game | the campaign player: your save games to resume, or a shelf of books to start |
| Editor | Mission Editor, Campaign Editor, play a single mission, load a mission save |
| Quit | closes the app |
| Cog (bottom left) | the Options dialog (below) |
| Community (bottom left) | installed packages and the online list (see below) |
| Credits, What's new (bottom right) | credits and the changelog; a version label and an update button appear next to them when a new version exists |

## Options

Four tabs:
- **General**: camera behaviour in the Player, the line of sight rule (centre to corner is the default and recommended; corner to corner is looser, as in Descent 2; centre to centre is strict), and the update check.
- **Voice**: voice control (microphone, push to talk or hands-free, show / hide the voice hints) and **narration** (the story is read aloud; pick the story teller voice, download more voices).
- **AI**: optional writing and design help. Either your own Anthropic API key (pay per use) or Claude Code installed on this PC (uses your Claude account). Off by default, and nothing is sent until you use an AI button.
- **Game assets**: imports the pictures, models and data from your own copy of the game (below).

Voice and narration are downloaded on demand from here; they are not part of the app.

## Game assets

The app ships without the game's art. The **Game assets** tab of Options finds your installed copy of the official game and imports the textures, monster and hero models, and item / weapon / monster data into your user folder. Run it again after the game updates. Without it the app still runs with placeholder pictures, but the weapon, armor, recipe and monster data come from this import.

## Monster template editor

Open from the mission editor: **File > Monster Templates...**. The library is shared by all missions; every change is saved at once.

A monster in a mission is built from templates:
- one **base** template (required) that defines the monster: hitpoints, defense, attack, speed, range, abilities, how it picks its target, tactics, loot, what it does when confused, and a text shown when it is defeated;
- any number of **additive** templates that add on top (a tougher variant, a prefix like "Shady").

Each stat has a **scaling table** by level (rows from level to level with a value; for an additive template the value is added and may be negative; a level outside every row uses the closest row). The preview shows the result at a chosen level.

Other things in the form: name prefix / postfix, weaknesses, resistances, immunities and condition immunities, tags, the game's own abilities (pick one from the list), target rules (ordered, first match wins), tactics, loot, and the confused-action list.

Buttons:
- **Update all missions...**: when a template changes, the mission open in the editor is updated at once (one undo step); this updates the copies stored in all your other missions. The Player always uses the copies stored in the mission file.
- **Import the game's monsters...**: creates base templates from the game's own data (needs the game assets import first). Existing templates are never overwritten.

## Releases and the community

- **File > Release...** (mission or campaign editor) packs a draft into a versioned package, checks it, and installs it as a read-only release. If it contains pictures you must confirm you may share them. The package id needs an author name.
- From the result you can **save the package file** or **publish to the community**. Publishing signs in with GitHub (a short code you type on github.com) and opens a pull request on the community repository; someone merges it.
- **Community** (main menu): *Installed* (play, open, remove, import a package file or address), *Browse online* (the catalog; install a version), *Import*. Every package is checked as plain text before anything is loaded from it. Versions are installed side by side; nothing is updated in place.

## The Player

- **Gear menu** (bottom left): Line of Sight, Options, Rules Reference, Save, Debug (test runs only), Back to Menu.
- **Party menu**: Quest Log (everything you were told), Campaign Log, Heroes (wounds), Inventory.
- **Quest / Threat** (top right): switch between the map and the monster view.
- Drag a **hero portrait** onto a prop to use it, or onto a monster to attack.
- **Voice**: with voice control on, say "hey DM, attack the green bandit", "hero two use the pile of dirt", "end phase", "show monsters". While a dialog is open you can just answer it ("yes", "three", a weapon name); no wake word needed. The typed box (**Tab**) takes the same commands.

## The AI and dictation buttons

In the story, question, answer, reply and writing boxes:
- **AI**: fix spelling and grammar, improve, shorten, make more dramatic, continue the story, or any instruction. You see the suggestion next to your text and nothing changes until you press Apply (one undo step).
- **Dictate**: click, speak, click again.
