<div align="center">

<img src="docs/banner.png" alt="DMorph for OctoWoW: become any creature in the game" width="100%">

# DMorph (OctoWoW)

**Become any creature in the game** · WoW 1.12 · OctoWoW

![WoW 1.12.1](https://img.shields.io/badge/WoW-1.12.1-c79c6e?style=flat-square)
![Lua 5.0](https://img.shields.io/badge/Lua-5.0-2c2d72?style=flat-square)
![Models](https://img.shields.io/badge/models-16%2C296-b46bff?style=flat-square)
![Needs VanillaHelpers](https://img.shields.io/badge/needs-VanillaHelpers-2e8b57?style=flat-square)

</div>

A morph window for the OctoWoW client, inspired by [DMorph](https://darksectordds.github.io/html/dmorph/index.html).
Pick any creature, race or item, see it on your character straight away, and save the looks you like.
**Morphs are only on your screen:** nobody else sees them.

**What it does**

- 🐉 **Every creature model in the client:** 16,000+ entries covering all 13,423 usable display IDs, including the **2,894 models OctoWoW added**.
- 🖼️ **3D previews**, eight to a page, or a list that previews the row under your mouse. Search by name or display ID.
- 🧝 **All 10 races**, male and female. Your own face, skin and hair carry over.
- ⚔️ **Any armour or weapon** on any visible slot, from every item in 1.12 (NPC weapons too), or any item ID.
- 👗 **Wardrobe:** save outfits and put them back on with one click. Shared by all your characters.
- 💬 **DMorph's chat commands:** `.morph`, `.race`, `.gender`, `.item`, `.demorph`, `.outfit`.
- 🔁 **Your look stays** after `/reload`, loading screens and logging in.

## Screenshots

<table>
<tr>
<td width="50%"><img src="docs/models.jpg" alt="Models tab"><br><b>Models</b>: browse or search every model. Click one to become it, or type any display ID and step through with &lt; &gt;.</td>
<td width="50%"><img src="docs/races.jpg" alt="Races tab"><br><b>Races</b>: click a portrait to wear that race and gender. Your own race is marked.</td>
</tr>
<tr>
<td><img src="docs/items.jpg" alt="Items tab"><br><b>Items</b>: click a slot by the model, search, and click an item. Morphed slots glow green.</td>
<td><img src="docs/wardrobe.jpg" alt="Wardrobe tab"><br><b>Wardrobe</b>: name your look and save it. Click an outfit twice to put it on.</td>
</tr>
</table>

**In the world.** Four morphs in Orgrimmar:

<img src="docs/morphs.jpg" alt="Four creature morphs in Orgrimmar" width="100%">

---

## Install

1. In **OctoLauncher**, enable the **`vanillaHelpers`** mod. DMorph needs it to change your model.
2. Put the addon folder in `Interface\AddOns\` so that you have `Interface\AddOns\DmorphOcto\DmorphOcto.toc`.
   - Used **Code > Download ZIP**? The folder is called `DmorphOcto-main`. Rename it to **`DmorphOcto`** or the game won't load it.
3. Start the game. Click the polymorph button by the minimap, or type **`/dmorph`**.

Optional: [ClassicAPI](https://github.com/brues-code/ClassicAPI) (`ClassicAPI.dll` in `dlls.txt`) for the 3D previews.
Without it the Models tab is a plain list and everything else works the same.
Not using OctoLauncher? Put `VanillaHelpers.dll` (v1.1.0+, [releases](https://github.com/isfir/VanillaHelpers/releases)) in the game folder and add it to `dlls.txt`.

---

## The window at a glance

| Part | What it does |
|---|---|
| **Dressing room** (left) | Your character in your race's dress-up room. Drag to turn it. The plate underneath names your look. |
| **Slots** around the model | Left-click: browse items for that slot. Right-click: back to your own gear. Morphed slots glow green. |
| **Reset model** / **Reset everything** | Your own body back (items stay) / clear every morph. |
| **Models** tab | Grid of previews (mouse wheel turns pages) or list view. Gold frame = the model you wear. |
| **Filter** button | All models · Creatures (white) · Other models, named after their model file (blue) · New in OctoWoW (green). Right-click goes back. |
| **Display ID** | Type any ID and press Morph, or step through every ID with < and >. |
| **Races** tab | Male and female portraits for all 10 races. **Swap gender** flips the current one. |
| **Items** tab | Items for the chosen slot, coloured by quality. **Item ID** + **Apply** takes any item. **Use my own gear** clears the slot. |
| **Wardrobe** tab | Save, load and delete outfits. Loading puts on the whole outfit. |

Open it with the minimap button, `/dmorph` or a key under *Key Bindings > DMorph*. Escape closes it.

## Chat commands

Type them in the chat box like in DMorph. They never reach the server. Each also works after `/dmorph`, e.g. `/dmorph morph 4527` in a macro.

| Command | What it does |
|---|---|
| `.morph <displayID>` | Become any creature, e.g. `.morph 4527`. `.morph 0` resets. |
| `.race <1-10>` or `.race nightelf` | `1` Human, `2` Orc, `3` Dwarf, `4` Night Elf, `5` Undead, `6` Tauren, `7` Gnome, `8` Troll, `9` Goblin, `10` High Elf. |
| `.gender` | Swap the gender of your race or race morph. |
| `.item <slot> <itemID>` | Morph one slot, e.g. `.item 1 2955` or `.item head` + a shift-clicked item link. `0` resets the slot. |
| `.demorph` / `.demorph all` | Reset your model / your model and all items. |
| `.outfit`, `.outfit <name>`, `.outfit save <name>`, `.outfit delete <name>` | List, put on, save or delete outfits. |
| `.dmorph status` / `/dmorph help` | What's morphed and which VanillaHelpers is loaded / all commands. |

Slots: `1` head, `3` shoulder, `4` shirt, `5` chest, `6` waist, `7` legs, `8` feet, `9` wrist, `10` hands, `15` back, `16` main hand, `17` off hand, `18` ranged, `19` tabard.

## Good to know

- **Only you see morphs.** They change your own client's picture, nothing else.
- **Invisible after a morph?** That display ID has no model in the game. Press **Reset model**. The list itself only has IDs whose model exists.
- **Shapeshifting** (druid forms and the like) shows your morph instead of the form. Reset your model first if you want the form.
- **OctoWoW's custom items** aren't in the item lists (they come from the 1.12 database), but work by item ID.
- **"?" icon on a slot:** the game hasn't loaded that item yet. It turns into the icon after a moment.
- No `.scale` (VanillaHelpers can't scale models), no Draenei (race 11 isn't in 1.12), and F5/F10 aren't taken over: set the reset keys under *Key Bindings > DMorph*.

---

## How it works

DMorph itself is a DLL for WotLK 3.3.5a and can't run on the 1.12 client. This addon uses **VanillaHelpers**, a 1.12 client mod that OctoLauncher ships, through its `SetUnitDisplayID`, `SetUnitVisibleItemID` and `UnitDisplayInfo` functions. The previews use ClassicAPI's `Model:SetDisplayInfo`. Each new model loads out of sight and only shows once it's ready, so nothing flashes white.

- `DmorphOcto.lua`: morph state, wardrobe, search and chat commands. `UI.lua`: the window and minimap button.
- `Data/Creatures.lua` and `Data/Items.lua`: names from the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 database. `Data/Models.lua`: every other display ID in the client's own `CreatureDisplayInfo.dbc`, named after its model file.
- Saved data: `WTF\Account\<account>\SavedVariables\DmorphOcto.lua` (outfits, window settings, minimap button) and each character's `SavedVariables\DmorphOcto.lua` (current look).

## Development

Written for the client's Lua 5.0: no `#`, no `%`, no `string.match`.

- **Tests:** `tests/run_tests.lua` drives the addon (chat, window, previews, wardrobe, `/reload`, logins) inside `tests/mock_wow.lua`, a strict mock of the 1.12 UI and of VanillaHelpers. Run `lua tests/run_tests.lua` with Lua 5.0, or on Windows `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (builds `tools/LuaHost`, .NET 8, and uses the Lua runtime OBS Studio installs; `LUA51_DLL` picks another).
- **Catalogue:** `python3 tools/build_data.py <ClassicDB_1_12_1_*.sql.gz>` rebuilds `Creatures.lua` and `Items.lua`. `powershell -ExecutionPolicy Bypass -File tools\build_models.ps1 -GameDir C:\Games\OctoWoW` rebuilds `Models.lua` from the client's MPQs; run it after a client patch.
- **Pictures:** `docs/src` has the banner and gallery as HTML (rendered with headless Edge) and the in-game crops they use.

## Credits

- [DMorph](https://darksectordds.github.io/html/dmorph/index.html) by DDS (darksectordds), for the original commands.
- [VanillaHelpers](https://github.com/isfir/VanillaHelpers) by isfir, which does the morphing on the 1.12.1 client.
- [ClassicAPI](https://github.com/brues-code/ClassicAPI) by brues-code, whose `Model:SetDisplayInfo` draws the previews.
- Creature and item names from the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 world database.
