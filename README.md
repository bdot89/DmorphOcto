# DMorph for OctoWoW

A morph window for the **OctoWoW** client (1.12.1, build 5875, "Mysteries of Azeroth"), inspired by [DMorph](https://darksectordds.github.io/html/dmorph/index.html). Browse **every creature model the client has** (over 16,000 entries covering all 13,423 usable display IDs, including the 2,894 models OctoWoW added) as 3D previews, plus every playable race and every visible weapon and armour piece. Try them on your character, save the result as an outfit in your **wardrobe**, and put it back on any time, even after `/reload` or logging out.

DMorph's chat commands (`.morph`, `.race`, `.gender`, `.item`) still work too.

## Requirements

- The OctoWoW client.
- **VanillaHelpers v1.1.0 or newer**, loaded by the game. Either:
  - in **OctoLauncher**, enable the `vanillaHelpers` mod, or
  - add `VanillaHelpers.dll` from the [VanillaHelpers releases](https://github.com/isfir/VanillaHelpers/releases) to the game folder and list it in `dlls.txt` (VanillaFixes).
- Optional, for the **3D model previews**: [ClassicAPI](https://github.com/brues-code/ClassicAPI), loaded the same way (`ClassicAPI.dll` in `dlls.txt`). Without it the Models tab is a plain list and everything else works the same.

## Install

1. Close the game.
2. Put the addon in `Interface\AddOns\DmorphOcto\` inside your OctoWoW folder, so that `Interface\AddOns\DmorphOcto\DmorphOcto.toc` exists. Pick one:
   - **Package ZIP** (`DmorphOcto-<version>.zip`): extract it into `Interface\AddOns\`. It already contains the `DmorphOcto` folder.
   - **GitHub ZIP** (*Code > Download ZIP*): extract it, then rename the folder (for example `DmorphOcto-main`) to `DmorphOcto`. 1.12 only loads an addon whose folder name matches its `.toc`.
   - **git**: `git clone https://github.com/bdot89/DmorphOcto.git Interface/AddOns/DmorphOcto`
3. Start the game. On the character screen, open *AddOns* and check that **DMorph (OctoWoW)** is enabled.
4. Log in. You'll see a polymorph-sheep button on the minimap.

## The morph window

Open it with the **minimap button**, by typing **`/dmorph`**, or with a key you set under *Key Bindings > DMorph*. Escape closes it. Drag the window by its background to move it.

Every change shows on your character straight away. The window is the "try it on" view, so there's no separate preview step.

### Dressing room (left)

- Your character, standing in your race's dressing room (the dress-up backdrop of the race you look like). **Drag** the model to turn it. The plate underneath names your current look.
- The **slots** you can morph sit around it: head, shoulder, back, chest, shirt, tabard, wrist, hands, waist, legs, feet, main hand, off hand and ranged.
  - A morphed slot glows green and shows the morph's icon.
  - An unmorphed slot shows the gear you really wear, dimmed.
  - **Left-click** a slot to browse items for it. **Right-click** it to go back to your own gear.
  - Hover over a slot to see what's on it.
- **Reset model** puts your own body back but keeps item morphs (DMorph's F5). **Reset everything** clears all morphs (DMorph's F10).
- A new look loads out of sight and only appears once it's ready, so the model never flashes white.

### Models tab

- A grid of **3D previews**, eight to a page. Turn pages with the arrows or the **mouse wheel**. Hover over a preview to turn it and see its display ID; **click** it to become it. The model you wear has a gold frame.
- **Search** by name (`thrall`, `ragnaros`, `murloc`…) or by display ID.
- The **filter** button picks what's listed (right-click goes back):
  - **All models**
  - **Creatures**: models with a creature's name, from the world database (white).
  - **Other models**: every look no creature uses, named after its model file, for example "Tiger (Turquoise)" or "High Elf Female NPC" (blue).
  - **New in OctoWoW**: the models OctoWoW added to 1.12 (green).
- **List view** shows the same models as a list; hover over a row to see a preview next to it. The window remembers which view you used.
- Under the grid, type any display ID and press **Morph**, or use **<** and **>** to step through IDs one at a time.

### Races tab

- Pick any race as **male** or **female** by its portrait: Human, Orc, Dwarf, Night Elf, Undead, Tauren, Gnome, Troll, Goblin and High Elf. The race you wear is ringed in gold.
- Your own skin, face and hair carry over. **Swap gender** flips the current one.

### Items tab

- Shows the items that fit the selected slot, coloured by quality. Search by name or item ID, and click one to wear its look.
- Use **<** and **>**, or click a slot by the model, to change slot.
- Weapon slots list everything that fits that hand, including the NPC-only "Monster" weapons.
- **Item ID** + **Apply** takes any item ID. **Use my own gear** clears the slot.

### Wardrobe tab

- Build a look, type a name and press **Save current look**. Saving under an existing name updates that outfit.
- Click an outfit to select it, then click it again (or press **Load**) to put it on. Loading puts on the whole outfit: slots the outfit doesn't morph go back to your own gear.
- **Delete** asks before removing an outfit.
- Outfits are saved account-wide, so every character can use them. They survive `/reload`, logging out and restarting the game.

Your current look is also remembered per character and re-applied after loading screens, `/reload` and logins.

## Chat commands

Type them in the chat box like in DMorph. They're handled locally and never sent to chat. Each one also works after `/dmorph` (for example `/dmorph morph 4527`), which is handy in macros.

| Command | What it does |
|---|---|
| `/dmorph` | Open or close the morph window. |
| `.morph <displayID>` | Morph into any creature model, e.g. `.morph 4527`. `.morph 0` resets. |
| `.race <1-10>` | Morph into a race, keeping your gender, skin, face and hair. `1` Human, `2` Orc, `3` Dwarf, `4` Night Elf, `5` Undead, `6` Tauren, `7` Gnome, `8` Troll, `9` Goblin, `10` High Elf. Names work too: `.race nightelf`. |
| `.gender` | Swap the gender of your race, or of your race morph. |
| `.item <slot> <itemID>` | Morph the item in a visible slot, e.g. `.item 1 2955`. A shift-clicked item link works in place of the ID. `.item <slot> 0` resets that slot. |
| `.demorph` / `.demorph all` | Reset your model / your model and all items. |
| `.outfit` | List your saved outfits. |
| `.outfit <name>` | Put on a saved outfit. |
| `.outfit save <name>` / `.outfit delete <name>` | Save your current look / delete an outfit. |
| `.dmorph status` | Show what's morphed and which VanillaHelpers version is loaded. `/dmorph help` lists the commands. |

Item slots follow DMorph's numbering: `1` head, `3` shoulder, `4` shirt, `5` chest, `6` waist, `7` legs, `8` feet, `9` wrist, `10` hands, `15` back, `16` main hand, `17` off hand, `18` ranged, `19` tabard. Slot names such as `head` or `mainhand` work too.

Dot commands that aren't DMorph's (for example `.help`) still go to the server as before.

## Differences from DMorph

- **No `.scale`.** VanillaHelpers has no API for model scale. The command only prints a notice, and it never ends up in `/say`.
- **No Draenei.** DMorph's race 11 doesn't exist in 1.12. Race 10 is the High Elf on OctoWoW.
- **F5/F10 aren't grabbed automatically.** Your existing key bindings stay as they are; set the reset keys under *Key Bindings > DMorph* if you want them.
- **`.morph` and `.race` share one slot.** Whichever you used last wins.

## Good to know

- The models list is built from the client's own model table, so it has every display ID the client can show. 25 IDs whose model file is missing from the game data are left out, because they would make you invisible.
- Previews show a creature's portrait view. Dressed NPCs (the "… NPC" models) appear in their outfits but without weapons: the game only sends NPC weapons for creatures you meet.
- OctoWoW's custom items aren't in the item lists (they come from the 1.12 database), but you can still use them by item ID.
- An item the client hasn't seen this session shows as "?" until its details arrive. If it doesn't appear on your character, click it again after a moment.
- Item morphs make VanillaHelpers rebuild your character in the world, which can blink for a moment there. The window's own preview doesn't.
- While your model is morphed, shapeshift and transform visuals (druid forms and the like) show your morph instead. Reset your model before shapeshifting if you want to see the form.
- A display ID that doesn't exist in the client's data can leave you invisible. Press **Reset model** to recover. Your look is only saved to disk on logout or `/reload`, so a morph that crashes the client won't come back on the next login.
- Morphs are visual changes on your own client only. VanillaHelpers is a launcher-shipped mod, but check OctoWoW's rules if you're unsure about client mods.

## How it works

DMorph itself is a DLL built for WotLK 3.3.5a (build 12340) that calls that client's code at fixed addresses, so it can't run on OctoWoW's 1.12 client. This addon instead uses **VanillaHelpers**, a 1.12.1 client mod that OctoLauncher ships, which has a morph API since v1.1.0.

- `DmorphOcto.lua` keeps the morph state and the wardrobe, searches the catalogue and handles the chat commands. It calls VanillaHelpers' `SetUnitDisplayID`, `SetUnitVisibleItemID` and `UnitDisplayInfo` for the `player` unit. VanillaHelpers hooks the client's object updates, so the server can't overwrite a morph. For player race models it also swaps race and gender, which keeps your own customisation.
- `UI.lua` is the window and the minimap button. It calls the same functions as the chat commands. The previews use ClassicAPI's `Model:SetDisplayInfo`.
- `Data/Creatures.lua`, `Data/Models.lua` and `Data/Items.lua` are the catalogue. They're stored as text and only parsed the first time you open the window.
- Saved data lives in `WTF\Account\<account>\SavedVariables\DmorphOcto.lua` (`DmorphOctoAccount`: outfits, window settings and minimap button) and in each character's `SavedVariables\DmorphOcto.lua` (`DmorphOctoDB`: the current look). To start over, delete those files while the game is closed.

## Development

The addon is written for the client's Lua 5.0: no `#`, no `%`, no `string.match`, and `table.getn` counts element by element.

- **Tests:** `tests/run_tests.lua` loads the addon in `.toc` order into `tests/mock_wow.lua`, a strict mock of the 1.12 UI. The mock only accepts widget methods, templates, fonts and script names that exist in 1.12, and its fake VanillaHelpers follows its `Morph.cpp`. The tests then drive the chat commands, the window (previews, search, filters, paging, clicks, scrolling, slots, races, wardrobe, the minimap button), `/reload` and logins. Run them from the repository root with a Lua 5.0 interpreter:

  ```sh
  lua tests/run_tests.lua
  ```

  On Windows without Lua, `tools/run_tests.ps1` builds `tools/LuaHost` (.NET 8 SDK) and runs the tests on the Lua 5.1 runtime that OBS Studio installs, with the 5.0 names added (set `LUA51_DLL` to use another `lua51.dll`):

  ```powershell
  powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
  ```

- **Catalogue:** `tools/build_data.py` regenerates `Data/Creatures.lua` and `Data/Items.lua` from a 1.12.1 world database dump, such as `Full_DB/ClassicDB_1_12_1_*.sql.gz` from [cmangos/classic-db](https://github.com/cmangos/classic-db):

  ```sh
  python3 tools/build_data.py ClassicDB_1_12_1_z2815.sql.gz
  ```

  `tools/build_models.ps1` then writes `Data/Models.lua` from the client's own `CreatureDisplayInfo.dbc` (read straight from the MPQs, newest patch first): every display ID that `Creatures.lua` doesn't name. Run it again after a client patch:

  ```powershell
  powershell -ExecutionPolicy Bypass -File tools\build_models.ps1 -GameDir C:\Games\OctoWoW
  ```

## Credits

- [DMorph](https://darksectordds.github.io/html/dmorph/index.html) by DDS (darksectordds), for the original commands.
- [VanillaHelpers](https://github.com/isfir/VanillaHelpers) by isfir, which does the actual morphing on the 1.12.1 client.
- [ClassicAPI](https://github.com/brues-code/ClassicAPI) by brues-code, whose `Model:SetDisplayInfo` draws the previews.
- Creature and item names come from the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 world database.
