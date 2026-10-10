<div align="center">

<img src="docs/banner.png" alt="DMorph for OctoWoW: become any creature in the game" width="100%">

# DMorph (OctoWoW)

**Become any creature in the game** · WoW 1.12 · OctoWoW

![WoW 1.12.1](https://img.shields.io/badge/WoW-1.12.1-c79c6e?style=flat-square)
![Lua 5.0](https://img.shields.io/badge/Lua-5.0-2c2d72?style=flat-square)
![Models](https://img.shields.io/badge/models-16%2C000%2B-b46bff?style=flat-square)
![Items](https://img.shields.io/badge/items-12%2C000%2B-a335ee?style=flat-square)
![Needs VanillaHelpers](https://img.shields.io/badge/needs-VanillaHelpers-2e8b57?style=flat-square)

</div>

A morph window for the OctoWoW client, inspired by [DMorph](https://darksectordds.github.io/html/dmorph/index.html).
Pick any creature, race or item, see it on your character straight away, and save the looks you like.
**Morphs are only on your screen:** nobody else sees them.

**What it does**

- 🐉 **Every creature model in the client:** 16,000+ entries covering all 13,423 usable display IDs, including the **2,894 models OctoWoW added** (named after their Turtle WoW creatures where there is one).
- 🖼️ **3D previews**, eight to a page, or a list that previews the row under your mouse. Filter **Bosses, Rare creatures, Mounts** or OctoWoW's new models, search by name or ID, sort **A-Z or by ID**.
- 🐎 **Mount skins:** give your mount any model's look, for all your mounts or one of them. It only shows while you ride, so you mount and dismount with your keys as usual. A **Your skin** box shows the one you have on, turning, and the ▲ ▼ arrows go to the previous or next model.
- ⭐ **Favourites:** right-click any model (Models tab) or mount skin (Mounts tab) to star it, then pick it from the Favourites tab every time you log in.
- 🎭 **Races and looks:** pick a race portrait to keep your own face, or step through skin colour, face, hair style, hair colour and facial hair from the game's NPC looks (8,068 of them): each click changes only the row you click. Or roll the dice.
- ⚔️ **12,000+ weapons and armour pieces:** everything in 1.12 plus Turtle WoW's and OctoWoW's, from the Tower of Karazhan sets and the tier variants to the Warglaives of Azzinoth. Filter by quality (**Rare, Epic, Legendary** ...).
- 🛡️ **352 item sets:** wear a whole set in one click.
- 👗 **Wardrobe:** save outfits and put them back on with one click. Shared by all your characters.
- 👥 **See each other's morphs:** players with DMorph see each other's model, item morphs and mount skins (friendly players). Switch either side off under **Sharing**.
- 💬 **DMorph's chat commands:** `.morph`, `.race`, `.gender`, `.item`, `.mount`, `.demorph`, `.outfit`.
- 🔁 **Your look stays** after `/reload`, loading screens and logging in. The window resizes and remembers how you left it.

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
| **Reset model** / **Reset everything** | Your own body back (items stay) / clear every morph, mount skins too. |
| **Sharing** (bottom) | **Others see my morph** / **I see their morphs**: both on to start with. Hover it to see how many DMorph users you've met. |
| **Corner grip** (bottom right) | Drag to make the window bigger or smaller. It remembers the size. |
| **Models** tab | Grid of previews (mouse wheel turns pages) or list view. Gold frame = the model you wear. **Right-click** stars a model. |
| Models: **filter** | All models · Creatures · Bosses · Rare creatures · Mounts · Other models (named after their model file, blue) · New in OctoWoW (green). |
| Models: **Sort** | List A-Z or by ID. |
| **Mounts** tab | **Skin for:** all your mounts, or one you've ridden. Click a mount model to use it as the skin, right-click to star it, **Remove skin** takes it off. The skin you have on is ticked in the list and shown in the **Your skin** box; ▲ ▼ put on the previous / next model. The line at the top says which mount you're riding and what it shows as. The skin shows only while you ride. |
| Models: **Display ID** | Type any ID and press Morph, or step through every ID with < and >. |
| **Favourites** tab | Your starred models and mounts, shared by all your characters. Click to wear, right-click to unstar, hover for a 3D preview. Filter models / mounts, sort A-Z or ID. |
| **Races** tab | A portrait = that race with your own face, skin and hair (your item morphs show). The < > rows step through the game's NPC looks of that race, and each click changes only that row. "2 of 5" means five choices with your other features; grey means no NPC has another (change another row first, or roll the dice). Dice = random look, **My own look** goes back, **Favourite** stars the look. |
| **Items** tab | Click the slot name for any slot. Items are coloured by quality; the filter picks all / 1.12 / new and a quality. **Item ID** + **Apply** takes any item. |
| **Sets** tab | Every item set. Hover to see the pieces, click to wear them all. Same filters as Items. |
| **Wardrobe** tab | Save, load and delete outfits (your mount skin included). Loading puts on the whole outfit. |

Open it with the minimap button, `/dmorph` or a key under *Key Bindings > DMorph*. Escape closes it.

## Chat commands

Type them in the chat box like in DMorph. They never reach the server. Each also works after `/dmorph`, e.g. `/dmorph morph 4527` in a macro.

| Command | What it does |
|---|---|
| `.morph <displayID>` | Become any creature, e.g. `.morph 4527`. `.morph 0` resets. |
| `.race <1-10>` or `.race nightelf` | `1` Human, `2` Orc, `3` Dwarf, `4` Night Elf, `5` Undead, `6` Tauren, `7` Gnome, `8` Troll, `9` Goblin, `10` High Elf. |
| `.gender` | Swap the gender of your race or race morph. |
| `.item <slot> <itemID>` | Morph one slot, e.g. `.item 1 2955` or `.item head` + a shift-clicked item link. `0` resets the slot. |
| `.mount <displayID>` | Skin for all your mounts: any creature, shown while you ride. `.mount 0` removes it. |
| `.demorph` / `.demorph all` | Reset your model / your model, items and mount skins. |
| `.outfit`, `.outfit <name>`, `.outfit save <name>`, `.outfit delete <name>` | List, put on, save or delete outfits. |
| `.share on/off` / `.share others on/off` | Whether other DMorph users see your morph / whether you see theirs. `.share` shows both and how many DMorph users you've met. |
| `.dmorph status` / `/dmorph help` | What's morphed and which VanillaHelpers is loaded / all commands. |

Slots: `1` head, `3` shoulder, `4` shirt, `5` chest, `6` waist, `7` legs, `8` feet, `9` wrist, `10` hands, `15` back, `16` main hand, `17` off hand, `18` ranged, `19` tabard.

## Good to know

- **Who sees your morph:** you, and other players running DMorph with VanillaHelpers. Everyone else, and the server, sees your real character.
- **Sharing works on friendly players.** VanillaHelpers can't morph the other faction. A DMorph user's morph shows once your game has a handle on them: when you target or mouse over them, when you're grouped, or straight away if you run SuperWoW. Mount skins show on group members (and with SuperWoW), because DMorph has to take them off the moment that player dismounts. The addon talks over its own hidden chat channel, *DmorphOcto*, which no chat window shows, and over addon messages in groups.
- **Invisible after a morph?** That display ID has no model in the game. Press **Reset model**. The lists only have IDs whose model exists.
- **NPC looks are fixed combinations.** No DLL can change your own character's skin, face or hair, so the < > rows morph you into the game's dressed NPCs of that race. Each click changes only the feature you picked, among the NPCs that share all your other choices, so some rows have only one choice until you change another row. Item morphs don't show on an NPC look: for your own face with gear, use a portrait. Only the customisations in this 1.12 client exist, not later expansions'.
- **Mount skins wait for you to mount.** VanillaHelpers would otherwise keep you on a mount after you dismount, so the skin goes on when you mount (the addon sees your mount's buff) and comes off when that buff goes.
- **OctoWoW-only items** that no list knows yet are looked up in the background after you log in (with ClassicAPI, a few a second, once per account). The Items and Sets tabs say how many are left. Any item also works by its ID.
- **Fast clicking is safe:** the game rebuilds your character after each change, so a click within a third of a second of the last one waits its turn instead of mixing two looks' textures.
- **"?" icon on a slot:** the game hasn't loaded that item yet. It turns into the icon after a moment.
- **Shapeshifting** (druid forms and the like) shows your morph instead of the form. Reset your model first if you want the form.
- No `.scale` (VanillaHelpers can't scale models), no Draenei (race 11 isn't in 1.12), and F5/F10 aren't taken over: set the reset keys under *Key Bindings > DMorph*.

---

## How it works

DMorph itself is a DLL for WotLK 3.3.5a and can't run on the 1.12 client. This addon uses **VanillaHelpers**, a 1.12 client mod that OctoLauncher ships, through its `SetUnitDisplayID`, `SetUnitVisibleItemID`, `SetUnitMountDisplayID` and `UnitDisplayInfo` functions. The previews use ClassicAPI's `Model:SetDisplayInfo`. Each new model loads out of sight and only shows once it's ready, so nothing flashes white.

- `DmorphOcto.lua`: morph state, wardrobe, search, item lookup and chat commands. `Share.lua`: sharing morphs with other DMorph users. `UI.lua`: the window and minimap button.
- `Data/Creatures.lua` and `Data/Items.lua`: the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 database. `Data/Models.lua`, `ModelTags.lua` and `Looks.lua`: every other display ID in the client's own data, its boss / rare / mount tags, and the NPC looks per race. `Data/ItemsExtra.lua` and `ItemSets.lua`: Turtle WoW's and OctoWoW's items and the client's item sets.
- Saved data: `WTF\Account\<account>\SavedVariables\DmorphOcto.lua` (outfits, favourites, window settings, looked-up items, minimap button) and each character's `SavedVariables\DmorphOcto.lua` (current look).

## Development

Written for the client's Lua 5.0: no `#`, no `%`, no `string.match`.

- **Tests:** `tests/run_tests.lua` drives the addon (chat, window, previews, filters, races and looks, mount skins, favourites, sets, item lookup, wardrobe, sharing with other users, `/reload`, logins) inside `tests/mock_wow.lua`, a strict mock of the 1.12 UI and of VanillaHelpers. Run `lua tests/run_tests.lua` with Lua 5.0, or on Windows `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (builds `tools/LuaHost`, .NET 8, and uses the Lua runtime OBS Studio installs; `LUA51_DLL` picks another).
- **Catalogue:** `python3 tools/build_data.py <ClassicDB_1_12_1_*.sql.gz>` rebuilds `Creatures.lua` and `Items.lua`. Then, on Windows with the game installed, `tools\build_models.ps1` rebuilds the model files and `tools\build_items.ps1` the extra items and sets, from the client's MPQs, its item cache, Atlas-CFM's loot tables and `tools/data` (Turtle WoW data exported from [ShellLab](https://github.com/oplancelot/ShellLab)). Run them after a client patch.
- **Pictures:** `docs/src` has the banner and gallery as HTML (rendered with headless Edge) and the in-game crops they use.

## Credits

- [DMorph](https://darksectordds.github.io/html/dmorph/index.html) by DDS (darksectordds), for the original commands.
- [VanillaHelpers](https://github.com/isfir/VanillaHelpers) by isfir, which does the morphing on the 1.12.1 client.
- [ClassicAPI](https://github.com/brues-code/ClassicAPI) by brues-code, whose `Model:SetDisplayInfo` draws the previews.
- Creature and item names from the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 world database.
- Turtle WoW creature, item and rank data from [ShellLab](https://github.com/oplancelot/ShellLab) by oplancelot; loot-table item IDs from Atlas-CFM.
