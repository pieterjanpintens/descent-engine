## v0.0.29 - 2026-10-20
- Campaign editor: the side panel now has three tabs - General (campaign, book cover, story tools), Acts and Selection. The Problems list moved to a button in the menu bar that shows how many there are and opens a dialog.
- Campaign editor: the Selection tab is grouped into sections - Mission, Variables, Links, Before mission and After mission (story, when won / lost, loot). Side quests got the same layout.
- Campaign editor: materials (what a chapter gives, what an offer costs) are edited in an inventory-style dialog with a picture and a counter per material.
- Narration: 61 more voices (more English regional, Scottish, Irish, American, Canadian, Indian and other accents) from the model of the extra voices - no extra download, so campaigns with many characters get distinct voices.

## v0.0.28 - 2026-10-20
- New props: a big and a small ladder (both 1x1), in the Prop tab of the mission editor.
- Fixed a harmless "Unicode parsing error / Unexpected NUL character" message that Godot printed on every start.

## v0.0.27 - 2026-10-19
- The smithy shows your material stock as pictures with amounts on top, and each recipe shows how much you have of every material it needs (green = enough, red = too few). The popup of a place is now a fixed, narrow width and uses nearly the whole height of the window; lists grow downwards and scroll.
- The recipe shop and the smithy show their recipes as cards: the picture of the item on the left, the tier, what an armor does, the materials it needs as small pictures (red when you have too few) and the Buy recipe / Forge button.
- The market looks like the inventory: a grid of material tiles with their pictures, how many the party has, and Buy / Sell buttons with the prices under each.
- Recipe shops now use tiers instead of the game's XP numbers (tier 1 = the game's 4 XP, tier 2 = 5 XP, and so on; story-only recipes are no tier). Each shop has a chance per tier (default 50 / 30 / 15 / 4 / 1: mostly common recipes, now and then a rare one; 0 = never) and the party's XP no longer matters, so shops are no longer empty at 0 XP. Recipes show their tier in the shop.
- Campaign: the narrator now reads the campaign introduction, the act introductions and a chapter's story after it is won (and a 'Read aloud' button next to a chapter's or side quest's story), in the story teller's and the characters' voices, when narration is set up and on. Voice tags are no longer shown in these texts.
- Campaign inventory: every item is a tile with its picture (weapons, runes and parts, armor, recipes, materials with counts). The pictures come from your own game files: run the asset import again (Item data) to get the armor and material pictures; without them a tile shows a coloured placeholder.
- Campaign: a popup with the act's introduction opens at the beginning of every act (also in a playtest), after the campaign introduction in a new game and after the result of the chapter that ended the previous act.
- Campaign player: the map now fills the whole screen (centred), the right sidebar is gone and clicking a chapter, side quest or place opens its panel in a popup. The menu is the same as in the mission player (Gear: Back to Menu, Options, Rules Reference; Party: Campaign Log, Inventory), the campaign and act name sit over the map top-left, XP and gold top-right, and the playtest tools stay on top.
- Campaign: a new Inventory button opens a dialog with gold always on top and tabs for weapons, armor, consumables, recipes and materials. The materials and owned-item lists are gone from the top bar and the shop panels.
- While playtesting a campaign from the editor the play page has no 'Main menu' button, only 'Back to editor'.
- Changing the type of a place deletes the offers / listed recipes that only the old type used (after a confirmation), and the type list starts with Market, which is also what a new place is.
- A place can close after one chapter and open again after a later one (the shop is gone during a mid-act fight and keeps its stock).
- The recipe shop no longer uses the game's act for a recipe, only its XP requirement.
## v0.0.26 - 2026-10-18
- Playtest a campaign from the campaign editor: File > Playtest from the start (Ctrl+Enter) or Continue playtest opens it in the player on a 'Playtest' save, with a 'Back to editor' button. For campaigns you are editing (not releases) the player also has 'Auto-win missions' and, on every chapter and side quest, 'Count as won' / 'Count as lost' (a lost one follows the 'on lose' link) so you can click through a campaign and test both ways.
- A choice with many or long answers (a narrative question with 8 answers) now shows them one per line, wrapped, in a wider box that scrolls when needed, with Cancel always visible. Short choices (up to 3 short answers) stay in one row.
- The campaign introduction dialog is no longer wider than the screen: long texts wrap, and the dialog is titled with the campaign's name.
- Making a new plan no longer risks the old one: the previous plan is kept (button 'Previous plan' swaps back), and if the AI finds nothing new for the chapters your plan stays and only new characters and variables are added.
- In the plan you can now combine several chapters of one act into one (tick 'combine', then 'Combine selected'), also chapters that are already built into the campaign (missions with a drawn map cannot be merged; empty ones are replaced by one new empty mission): their summaries, manuscript sections and mission briefs are merged, and the links around the group stay. Handy for a long mission that was split into many chapters; keep the narrative chapters before and after as the intro and outro.
- Winning a chapter or side quest gives no experience by default any more (experience is rare); set the reward in the editor when a win should give some. Rewards read "no reward" when there is none.

## v0.0.25 - 2026-10-18
- A writing workspace for campaigns (button in the campaign editor): private notes (story bible, style, characters...) and one manuscript per act, saved as you type.
- From the manuscript, an optional AI can propose a plan of acts, chapters, characters and variables. You review it, then build the accepted items into the campaign in one undo step; narrative chapters get their story pages from the manuscript, and mission chapters get a brief and an empty mission file with objectives and variables (no map).
- A sync check tells you when the manuscript and the chapters made from it drift apart, shows what changed, and never overwrites anything without asking.
- Optional AI writing help in the story texts (fix, improve, shorten, continue...). Off by default; use your own Anthropic API key or the Claude Code program on your PC. Set it up in Options, which now has General, Voice and AI tabs.
- The story editor now uses the whole window, and its condition and effect rows wrap instead of running off the screen.
- New props for missions: small table (1x1) and barricade (2x1).
- Chapter pins from a built plan are laid out left to right along the story.
- Downloads (updates, voices, tools) now stop with a clear message after 30 seconds without data, and only one runs at a time, so a dropped connection no longer hangs the app.

## v0.0.24 - 2026-10-16
- New props for missions: fence (a see-through gate), cart, chest, pot, table and well.
- Campaign shop (first version): places on the map can be a market (buy and sell materials), a recipe shop with a rotating stock, or a smithy where you forge weapon cards and parts from recipes and materials. Needs the game's data import.
- Armor cards: part of a campaign's starting equipment, given by authored offers, sold in the recipe shop (with upgrades forged at the smithy). Their effects stay at the table.
- Places can close again after a chapter, and a bought recipe disappears from every shop.

## v0.0.23 - 2026-10-16
- New logo on the main menu, and the credits now list the 2D art (logo and background).

## v0.0.22 - 2026-10-15
- Releasing needs an author (your name or GitHub name): no more "anonymous" packages. The author is prefilled from your last name or GitHub sign-in.
- The message after releasing wraps properly (it was very wide and cut off), and "Publish to the community" now comes before "Save package file".

## v0.0.21 - 2026-10-15
- Fixed: a forked campaign is editable again (the editor stayed read-only after a fork).
- The Community page is for getting packages: importing a file or web address now has its own "Import" tab, and the publish button is gone from that page (publishing stays in the Release dialog).

## v0.0.20 - 2026-10-15
- A "What's new" page in the main menu; it opens by itself once after an update.
- New main menu background.

## v0.0.19 - 2026-10-15
- The app can update itself: when a newer version exists the main menu shows "Update available" and one click downloads, checks and installs it.
- Releases: a campaign or mission can be released as a frozen, numbered version. Released versions are read-only and save games stay on the version they were started on.
- Fork a release to make your own editable copy (campaign editor, mission editor and the Community page).
- Updating a save game to a newer release is an explicit action that writes a copy and tells you what would change; your original save is never touched.
- Saves are written safely and keep a backup of the previous state; removing an installed release moves its saves aside instead of deleting them.
- Weapon choice no longer shows the ability text, the embark loadout page scrolls, and Vaerix starts with a spear.

## v0.0.18 - 2026-10-13
- Community: share missions and campaigns as packages, browse the online catalog, and publish from inside the app with a GitHub sign-in.
- Packages are checked before anything is installed; every version is installed next to the others.
- Fixes to publishing for the owner of the community repository.

## Earlier
- In-app import of the game's own art and data, on Windows, macOS and Linux.
- Voice control and narration (Piper) on all platforms, with accent voices and per-character voices.
- Campaigns with acts, chapters, branching, side quests, a shop and a campaign log; narrative chapters with questions and answers.
- Monsters with templates, conditions, attack and defense abilities, tactics; weapons with real parts and abilities.
