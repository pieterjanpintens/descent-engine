# Community catalog

`index.json` is the list of missions and campaigns that players shared. The game downloads it from this repository
(Community > Browse online) and shows what is in it. Changes to it go through a pull request, so somebody looks at every addition.

## Share something

1. In the mission editor or campaign editor choose **File > Export package…**, fill in the details and save the `.descentpkg` file.
   The dialog ends with a ready-made catalog entry (also copied to your clipboard).
2. Upload the `.descentpkg` somewhere that serves the file directly over https - a **GitHub release asset** of your own repository is ideal
   (`https://github.com/<you>/<repo>/releases/download/<tag>/<file>.descentpkg`).
3. Open a pull request that adds your entry to the `packages` list in `index.json`:

```json
{
  "id": "yourname.the-lost-scroll",
  "type": "campaign",
  "name": "The Lost Scroll",
  "author": "yourname",
  "description": "A short description (max 600 characters).",
  "version": "1.0.0",
  "url": "https://github.com/yourname/descent-missions/releases/download/v1.0.0/yourname.the-lost-scroll-1.0.0.descentpkg",
  "sha256": "<the sha256 of the file>",
  "size_bytes": 1234567
}
```

- `id` stays the same between versions; `version` goes up when you share an update. Every version is installed **next to** the others
  on a player's computer - nothing is ever updated in place, so saved games and edits are never touched.
- Add an update as a **new entry** (same `id`, higher `version`) - keep the older entries so players can still get them.
- `sha256` is checked after the download; a file that does not match is refused.
- Packages with pictures: only share pictures you made or may share. The export dialog asks you to confirm this.

## What a package may contain

A package is only **data**: one mission file, or a campaign (its mission files and pictures). Before anything is installed the app reads every
file as plain text and refuses anything that could load code or other files (other scripts, scenes, embedded scripts, objects), and checks the
zip itself (sizes, names, file types). If you build a package by hand and it is refused, the message says why.
