# Descent Engine

Tools for designing and playing custom missions and campaigns for *Descent: Legends of the Dark*, built around the
game's physical tiles, pillars and stairs. Made with Godot 4.7.2 (GDScript).

Unofficial fan project, not affiliated with Fantasy Flight Games or Asmodee. It ships none of the game's art or sounds,
only placeholders.

## Video

A walkthrough of the campaign player (click to watch on YouTube):

[![Campaign walkthrough](https://img.youtube.com/vi/Ha-fwiLSWd0/hqdefault.jpg)](https://youtu.be/Ha-fwiLSWd0)

A getting started guide for players - installing, importing the game's art, and playing your first campaign:

[![Getting started guide](https://img.youtube.com/vi/uQX28RRIPms/hqdefault.jpg)](https://youtu.be/uQX28RRIPms)

## Getting started

1. **Install the game on Steam** - *Descent: Legends of the Dark*. You only need it for the real art and data (step 5); without it the app works
   with plain placeholder pictures.
2. **Download the zip for your computer** from the [Releases page](../../releases/latest): `Descent-Engine-windows.zip`, `Descent-Engine-linux.zip`
   or `Descent-Engine-macos.zip`.
3. **Extract everything** from the zip into a folder of your own (keep the files together).
4. **Run it.** The builds are not code-signed (signing certificates cost money and this project is free), so your computer warns about an
   "unknown" program the first time. It is safe to run it anyway:
   - **Windows**: run `Descent-Engine.exe`. SmartScreen says "Windows protected your PC": click **More info**, then **Run anyway**.
   - **macOS**: open `Descent-Engine.app`. macOS refuses it once: open **System Settings > Privacy & Security**, scroll down and press **Open Anyway**
     (older macOS: right-click the app > Open). Or run `xattr -dr com.apple.quarantine Descent-Engine.app` in a terminal once.
   - **Linux**: make the file executable (`chmod +x Descent-Engine.x86_64`) and run it.

   To check that a download is what we published, compare it with `SHA256SUMS.txt` from the same release: `sha256sum -c SHA256SUMS.txt --ignore-missing`
   (Linux), `shasum -a 256 -c SHA256SUMS.txt --ignore-missing` (macOS), or `certutil -hashfile <file> SHA256` on Windows.
5. **Import the game's art and data** (optional, needs the Steam install of step 1): in the main menu choose **Game assets** and press
   **Import game assets**. The app finds the game by itself (or lets you pick its folder), downloads a small import tool the first time (about 25 MB)
   and reads the art, monsters, weapons and items out of **your own copy**. It takes a few minutes; **restart the app** when it is done. Nothing of
   the game is downloaded or shared - the copies stay on your computer (please do not share them either). On an Intel Mac the in-app import is not
   available yet; the scripts in `tools/asset_import/` do the same by hand.
6. **Voice and narration** (optional): in the main menu choose **Options** (in a mission: the gear menu > Options). There you can download:
   - **Whisper** - speech recognition, so the table can give spoken commands ("hey DM, attack the green bandit"),
   - **Piper** - narration, so the story is read aloud, with one base voice,
   - extra **voice packs** (accents, plain English) so every hero and character can sound different.

   Each is a download of its own, started from that dialog; nothing is installed until you ask for it.

### Where the files end up

The app keeps everything it creates or downloads in its user folder (paste the path into the Explorer address bar / Finder's Go > Go to Folder):

| | Folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\Descent-Engine\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Descent-Engine/` |
| Linux | `~/.local/share/godot/app_userdata/Descent-Engine/` |

In it: `missions/`, `campaigns/`, `saves/` and `campaign_saves/` (your own work and games), `official_assets/`, `monster_assets/`, `hero_assets/`, `weapon_data/`,
`item_data/`, `monster_data/` (the game's art and data from step 5 - delete these folders to go back to the placeholders), `importer/` (the import tool),
`whisper/` (speech recognition) and `piper/` (narration engine and voices).

### How much disk space

Roughly what the full experience takes:

| | Size |
|---|---|
| The app (extracted from the zip; the zip is 54-86 MB) | ~170 MB |
| The game's art and data (step 5) | ~65 MB |
| The import tool it downloads (can be deleted afterwards) | ~45 MB |
| Whisper (speech recognition) | ~220 MB |
| Piper (engine + base voice) | ~100 MB |
| All extra voice packs (accents + plain English) | ~860 MB |
| **Everything in the user folder** | **~1.3 GB** (plus the ~170 MB app) |

Without voices it is about 0.3 GB; the voice packs are what make it big, and each one is optional.

## Sharing missions and campaigns

Main menu > **Community** installs missions and campaigns made by other players: import a package file (`.descentpkg`), paste a web address, or browse the
[community list](https://github.com/pieterjanpintens/descent-engine-community). Packages are only game data - every file is checked before anything is installed - and each version is installed next to the
others, so your own work and saved games are never touched. To share your own: **File > Export package...** in the mission or campaign editor, then
**Publish to the community...** - the app submits it under your GitHub account (you sign in once with a code on github.com) and it appears for everyone once it
is approved. Playing and installing never needs an account. Details: the [community repository](https://github.com/pieterjanpintens/descent-engine-community).

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
- **AI writing help (optional, off by default)** - with your own Anthropic API key, an AI menu on the story text boxes can
  fix, improve or continue your writing. You always see the suggestion first; text is only sent when you choose an action.
  Either paste an API key, or use Claude Code on your PC (install it once with `npm install -g @anthropic-ai/claude-code`, then
  run `claude auth login`) to use your own Claude account.

## License

[MIT](LICENSE): free to use, copy, change and redistribute, with no warranty - nobody can hold the author responsible if it does not work.
This covers the project's own code and art only. Third-party parts keep their own terms: the spell-check word list (`data/words_en.LICENSE.txt`), the
concrete floor texture (ambientCG, CC0), the Godot engine (MIT) and the Godot git plugin in `addons/` (MIT). *Descent: Legends of the Dark* and
everything of the game is the property of its owners; nothing of it is included here.

## Credits

Created by **Arutha**. Main menu concept art by **Ikkante** (used with their permission). The same list is in the app under Credits.
