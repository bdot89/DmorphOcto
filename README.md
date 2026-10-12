# DMorph for OctoWoW

Become any creature, ride any mount, wear any item. A morph window for WoW 1.12 (OctoWoW), version 2.14.0.

Morphs only change what you and other DMorph users see. Everyone else, and the server, sees your real character.

Download: https://github.com/bdot89/DmorphOcto/archive/refs/heads/main.zip


## How to install

### Step 1: Turn on VanillaHelpers

1. Open OctoLauncher.
2. In its list of mods, tick **vanillaHelpers**.

DMorph needs it. Without it, nothing can morph.

### Step 2: Put DMorph in your AddOns folder

1. Download the ZIP (link above).
2. Right-click the ZIP and choose **Extract All**, then **Extract**.
3. Open the extracted folders until you find the folder called **DmorphOcto-main** that has **DmorphOcto.toc** inside it.
4. Rename that folder to **DmorphOcto** (exactly that).
5. Move it into your game's AddOns folder. It must end up like this:

   OctoWoW\Interface\AddOns\DmorphOcto\DmorphOcto.toc

### Step 3: Run the installer (for glows, real skin, face and hair, size and weather and time of day)

1. Close the game completely.
2. Open the folder: OctoWoW\Interface\AddOns\DmorphOcto
3. Double-click **Install DmorphHelper.bat**
4. If Windows shows a warning:
   - "Windows protected your PC": click **More info**, then **Run anyway**.
   - "Do you want to run this file?": click **Run**.
5. A black window opens and ends with "DmorphHelper is installed". Press any key to close it.

You can skip this step: everything else still works, just without glows, real looks, size, weather and time of day.

### Step 4: Play

1. Start the game from **OctoLauncher** (not WoW.exe).
2. Click the polymorph button by the minimap, or type **/dmorph**
3. Check the **Setup** button at the bottom left of the window:
   - Green "Setup OK": you're ready. It also shows which DmorphHelper version is running (for example "Helper v10").
   - Yellow "Old helper": close the game and run Install DmorphHelper.bat again.
   - Red "Setup: fix me": click it. It tells you what isn't working and how to fix it.


## How to update

1. Download the ZIP again and replace your DmorphOcto folder with the new one (Step 2).
2. Close the game and double-click **Install DmorphHelper.bat** again (Step 3).
3. Start the game from OctoLauncher.


## If something goes wrong

- **"VanillaHelpers isn't running":** close the game completely (check Task Manager), then press Play in OctoLauncher. Don't start WoW.exe directly. Make sure vanillaHelpers is ticked.
- **Setup says DmorphHelper is "not running" or "older":** close the game and double-click Install DmorphHelper.bat.
- **The installer says "The game is running":** close the game, wait a few seconds, try again.
- **The installer can't find the game folder:** DmorphOcto isn't in OctoWoW\Interface\AddOns. Move it there.
- **The game won't start after installing:** double-click **Remove DmorphHelper.bat** in the DmorphOcto folder.
- **DMorph doesn't show in game:** check the folder name and place (Step 2), and that DMorph is ticked in the AddOns list on the character screen.
- **You turned invisible:** that model can't show in your game. Press Reset model.
- **The game crashes with ERROR #132 at 0x0069C... (often with UnitXP_SP3):** a view distance (farClip) above 777 overflows a buffer in the game. DmorphHelper (v7) makes that buffer big enough; without it, type /console farclip 777


## What it does

- Every creature model in the client (16,000+), with 3D previews, search, and filters for bosses, rare creatures, mounts and OctoWoW's new models.
- Mount skins: give your mount any model's look (Ashes of Al'ar included). You mount and dismount with your keys as usual.
- Races: any race and gender, with its real skin colour, face, hair style, hair colour and facial hair.
- Size: make your character smaller or bigger, 25% to 300%.
- Weather: clear skies, rain, snow or a sandstorm, from light to heavy, on your screen in every zone.
- Time of day: dawn, noon, dusk, midnight or any time, for the light, sky, sun and moon on your screen.
- Weapon glows: Crusader, Fiery, Icy and every other glow in the game.
- 12,000+ weapons and armour pieces, and 352 item sets in one click.
- Wardrobe of saved outfits and favourites, for all your characters.
- Other DMorph users see your model, items, mount skin and size, and you see theirs.
- Your look stays after /reload, loading screens and logging in.


## Using DMorph

Open the window with the minimap button, /dmorph, or a key under Key Bindings > DMorph. Escape closes it.

- **Dressing room (left):** your character. Drag to turn, mouse wheel to zoom, right-drag to move. The Size slider under it changes your size (right-click: normal size).
- **Item slots around the model:** left-click for items for that slot, right-click for your own gear.
- **Reset model / Reset everything:** your own body back / clear every morph.
- **Models tab:** every model. Click one to become it. Right-click to add it to Favourites.
- **Mounts tab:** pick which mount gets the skin, then click a model. The arrows step through the list. Remove skin takes it off.
- **Favourites tab:** your starred models and mount skins.
- **Races tab:** click a portrait to become that race with your own face. The arrow rows change skin colour, face, hair and facial hair. The dice picks a random look.
- **Glows tab:** pick main hand, off hand or ranged, then click a glow.
- **Items and Sets tabs:** filter by type, quality and source. Hover an item or set to see your character wearing it, then click to wear it.
- **Wardrobe tab:** save and load whole outfits.
- **Weather tab:** pick clear skies or light, normal or heavy rain, snow or sandstorm; the Strength slider fine-tunes it. Time of day: Dawn, Noon, Dusk, Midnight or the Time slider. Server's weather and Real time give the real ones back. Only you see them; weather shows outdoors only.
- **Setup (bottom left):** shows whether everything works, which DmorphHelper version is running, and how to fix what doesn't.
- **Sharing (bottom):** whether others see your morph, and whether you see theirs.

### Chat commands

Type these in the chat box. They never reach the server. Each also works after /dmorph (for macros).

- **.morph 4527** - become a creature by its display ID (.morph 0 resets)
- **.race 1-10** or **.race nightelf** - 1 Human, 2 Orc, 3 Dwarf, 4 Night Elf, 5 Undead, 6 Tauren, 7 Gnome, 8 Troll, 9 Goblin, 10 High Elf
- **.gender** - swap the gender of your race
- **.item 1 2955** - morph one item slot (0 resets it)
- **.mount 4527** - skin for all your mounts (.mount 0 removes it)
- **.scale 1.5** - your size (.scale 0 resets)
- **.weather rain heavy** - the weather: clear, rain, snow or sandstorm, then light, heavy or 5-100 (.weather off: the server's)
- **.time 22:30** - the time of day on your screen, or dawn, noon, dusk, night (.time off: the real time)
- **.glow mainhand 1900** - a weapon glow (0 = none, own = yours)
- **.demorph** / **.demorph all** - reset your model / reset everything
- **.outfit save name** / **.outfit name** / **.outfit delete name** - save, wear or delete outfits
- **.share on/off** / **.share others on/off** - sharing with other DMorph users
- **.dmorph check** - is everything working, and how to fix it

Item slots: 1 head, 3 shoulder, 4 shirt, 5 chest, 6 waist, 7 legs, 8 feet, 9 wrist, 10 hands, 15 back, 16 main hand, 17 off hand, 18 ranged, 19 tabard.


## Good to know

- Only friendly players can be morphed on your screen. Other DMorph users' morphs show when you target them, mouse over them or group with them (straight away with SuperWoW).
- During a race morph your faction, languages, skills, flight paths, spells and reputation stay those of your own character (with DmorphHelper): NPCs of your faction stay friendly. Your model, skin and hair stay the other race's.
- With a race portrait you keep your own face and hair. If the other race doesn't have one of your values (say a Tauren hair style on a Gnome), the closest one that race has is used instead, so nothing shows up green.
- Mount skins go on when you mount and come off when you dismount. Flight master birds keep their own look.
- Glows and picked faces are only on your own screen for now.
- Shapeshifting shows your morph instead of the form. Reset your model first if you want the form.
- Models, glows and races from The Burning Crusade onwards aren't in the 1.12 game files, so no addon can show them.


## Sharing ported models with friends

If you've made ported models (later-expansion models in extra patch files), you can send the same set to friends:

1. Close the game and double-click **Pack Ported.bat** in the DmorphOcto folder. It copies the ported patches and the list into a **DmorphPorted** folder on your Desktop, with a manifest of every file's checksum.
2. Upload that whole folder (Google Drive, OneDrive or MEGA) and send the link. It's several GB.
3. Your friend installs DMorph as above, downloads the folder, closes the game and double-clicks **Install Ported.bat** in it. It checks every file first, never replaces OctoWoW's own patches, removes ported patches from an older pack, and installs DmorphHelper. **Remove Ported.bat** takes them out again.

Pack again after every porting run: friends need exactly the same pack. DMorph users with the same pack see each other's ported models, mounts and items; everyone else sees your normal look. These are Blizzard's files, so keep packs private, not on GitHub.


## Screenshots

![DMorph banner](docs/banner.png)

![Models tab](docs/models.jpg)
![Mounts tab](docs/mounts.jpg)
![Races tab](docs/races.jpg)
![Glows tab](docs/glows.jpg)
![Items tab](docs/items.jpg)
![Sets tab](docs/sets.jpg)
![Wardrobe tab](docs/wardrobe.jpg)
![Favourites tab](docs/favourites.jpg)
![In the world](docs/world.jpg)
![More morphs](docs/morphs.jpg)

Project page: https://bdot89.github.io/DmorphOcto/


## For developers

- **Files:** DmorphOcto.lua is the core (morphs, wardrobe, commands), Share.lua shares morphs between DMorph users, UI.lua is the window. Data/ holds the model, item and set lists. helper/ holds DmorphHelper (C source and DLL).
- **How it works:** DMorph uses VanillaHelpers (SetUnitDisplayID, SetUnitVisibleItemID, SetUnitMountDisplayID) to morph, and ClassicAPI for the 3D previews. DmorphHelper adds weapon glows, real skin, face and hair, size, weather, time of day, and keeps your own race (faction, languages, reputation) during race morphs. It only switches on when it finds VanillaHelpers' hooks in the game.
- **Tests:** powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1 (or lua tests/run_tests.lua with Lua 5.0).
- **Rebuilding the lists after an OctoWoW update:** close the game and run powershell -ExecutionPolicy Bypass -File tools\update_from_game.ps1
- **Building DmorphHelper:** sh helper/build.sh with 32-bit MinGW (on Windows: winlibs i686, from Git Bash).
- Written for the game's Lua 5.0: no #, no %, no string.match.

## Credits

- DMorph by DDS (darksectordds), for the original commands.
- VanillaHelpers by isfir, which does the morphing.
- ClassicAPI by brues-code, for the 3D previews.
- MinHook by Tsuda Kageyu, used by DmorphHelper.
- Creature and item names from the cmangos classic-db; Turtle WoW data from ShellLab by oplancelot; loot-table item IDs from Atlas-CFM.
