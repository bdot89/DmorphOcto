<div align="center">

<img src="docs/banner.png" alt="DMorph for OctoWoW: become any creature, ride any mount, wear any item" width="100%">

# DMorph (OctoWoW)

**Become any creature, ride any mount, wear any item** · WoW 1.12 · OctoWoW

![Version](https://img.shields.io/badge/version-2.6.0-33ff99?style=flat-square)
![WoW 1.12.1](https://img.shields.io/badge/WoW-1.12.1-c79c6e?style=flat-square)
![Models](https://img.shields.io/badge/models-16%2C000%2B-b46bff?style=flat-square)
![Items](https://img.shields.io/badge/items-12%2C000%2B-a335ee?style=flat-square)
![Needs VanillaHelpers](https://img.shields.io/badge/needs-VanillaHelpers-2e8b57?style=flat-square)

**[⬇️ Download ZIP](https://github.com/bdot89/DmorphOcto/archive/refs/heads/main.zip)** · **[Project page](https://bdot89.github.io/DmorphOcto/)**

</div>

A morph window for the OctoWoW client, inspired by [DMorph](https://darksectordds.github.io/html/dmorph/index.html). Pick any creature, race, mount skin, weapon glow or item, see it on your character straight away, and save the looks you like.

Morphs only change what **you and other DMorph users** see. Everyone else, and the server, sees your real character.

---

## 📥 Install (5 minutes)

### Step 1: Turn on VanillaHelpers

1. Open **OctoLauncher**.
2. In its list of mods, tick **`vanillaHelpers`**.

DMorph uses it to change your model. Without it, nothing can morph.

### Step 2: Put DMorph in your AddOns folder

1. Click **[Download ZIP](https://github.com/bdot89/DmorphOcto/archive/refs/heads/main.zip)**.
2. Right-click the downloaded `DmorphOcto-main.zip` and choose **Extract All...**, then **Extract**.
3. In the extracted files, open folders until you see the **`DmorphOcto-main`** folder that has `DmorphOcto.toc` inside it, and **rename that folder to `DmorphOcto`** (exactly that, or the game won't load it).
4. Move it into your game's AddOns folder, so it ends up here:

```
...\OctoWoW\Interface\AddOns\DmorphOcto\DmorphOcto.toc
```

> ⚠️ The `.toc` file must be directly inside `DmorphOcto`. If you have `DmorphOcto\DmorphOcto-main\DmorphOcto.toc`, move the inner folder up one level.

### Step 3: Install DmorphHelper (weapon glows, real skin/face/hair, size)

DMorph comes with a small extra file, **DmorphHelper.dll**, for weapon glows, your real skin, face and hair, and the size slider. An addon can't copy files into the game folder by itself, so this is one double-click:

1. **Close the game completely.**
2. Open the folder `Interface\AddOns\DmorphOcto`.
3. Double-click **`Install DmorphHelper.bat`**.
4. If Windows shows a warning, let it run:
   - *"Windows protected your PC"*: click **More info**, then **Run anyway**.
   - *"Do you want to run this file?"*: click **Run**.
5. A black window opens and ends with **"DmorphHelper is installed."** Press any key to close it.

That's it. It found your game folder, copied the DLL next to `WoW.exe` and added it to `dlls.txt` after `VanillaHelpers.dll`.

> Skip this step and everything else still works; you just won't have glows, real looks or the size slider.

### Step 4: Play

1. Start the game **from OctoLauncher** (client mods only load that way, not from `WoW.exe`).
2. Click the **polymorph button** by the minimap, or type **`/dmorph`**.
3. Look at the **Setup** button at the bottom left of the window:
   - 🟢 **Setup OK**: you're ready.
   - 🔴 **Setup: fix me**: click it. It says what isn't running and how to fix it. (`/dmorph check` shows the same in chat.)

### Updating

1. Download the ZIP again and replace your `DmorphOcto` folder with the new one (Steps 2.1 to 2.4).
2. Close the game and double-click **`Install DmorphHelper.bat`** again. It only copies the DLL if it changed.
3. Start the game from OctoLauncher.

### Something wrong?

| Problem | Fix |
|---|---|
| **"VanillaHelpers isn't running"** | Close the game completely (check Task Manager), then press **Play in OctoLauncher**. Don't start `WoW.exe` directly. Make sure `vanillaHelpers` is ticked. |
| **Setup says DmorphHelper is "not running" or "older"** | Close the game and double-click `Install DmorphHelper.bat` (Step 3). |
| **The .bat says "The game is running"** | Close the game, wait a few seconds, try again. |
| **The .bat says it can't find the game folder** | DMorph isn't in `OctoWoW\Interface\AddOns`. Move it there (Step 2). |
| **The game won't start after Step 3** | Double-click **`Remove DmorphHelper.bat`** in the DmorphOcto folder. |
| **DMorph doesn't show in game** | Check the folder name and place (Step 2.3 and 2.4), then enable *DMorph* in the AddOns list on the character screen. |
| **Invisible after a morph** | That model can't show in your game. Press **Reset model**. |

Optional extras: [ClassicAPI](https://github.com/brues-code/ClassicAPI) gives the 3D previews (without it the Models tab is a list), and SuperWoW lets you see nearby DMorph users' morphs without targeting them.

---

## ✨ What it does

- 🐉 **Every creature model in the client:** 16,000+, including the 2,894 OctoWoW added. 3D previews, search, A-Z or ID, and filters for **Bosses** (560+), **Rare creatures**, **Mounts** and OctoWoW's new models.
- 🐎 **Mount skins:** give your mount any model's look (Ashes of Al'ar included). It shows only while you ride, so you mount and dismount with your keys as usual.
- 🎭 **Races and looks:** any race and gender, then change its real skin colour, face, hair style, hair colour and facial hair one at a time, with your gear still on.
- 📏 **Size:** make your character smaller or bigger, 25% to 300%: a tiny Ragnaros, a giant Tauren.
- ✨ **Weapon glows:** Crusader, Fiery, Icy, poisons and every other glow in the game, on main hand, off hand or ranged.
- ⚔️ **12,000+ weapons and armour:** everything in 1.12 plus Turtle WoW's and OctoWoW's, filtered by type and quality.
- 🛡️ **352 item sets** in one click, and a **Wardrobe** of saved outfits for all your characters.
- ⭐ **Favourites:** right-click any model or mount skin to keep it handy.
- 👥 **See each other's morphs:** DMorph users see each other's model, items and mount skins.
- 💬 **DMorph's chat commands:** `.morph`, `.race`, `.item`, `.mount`, `.glow`, `.scale` and more.
- 🔁 **Your look stays** after `/reload`, loading screens and logging in.

## 🖼️ Screenshots

<table>
<tr>
<td width="50%"><img src="docs/models.jpg" alt="Models tab"><br><b>Models</b>: every model, here the 549 bosses. Click one to become it.</td>
<td width="50%"><img src="docs/mounts.jpg" alt="Mounts tab"><br><b>Mounts</b>: pick a skin; the one you have on turns in the <b>Your skin</b> box.</td>
</tr>
<tr>
<td><img src="docs/races.jpg" alt="Races tab"><br><b>Races</b>: any race, then its real skin colour, face, hair and features.</td>
<td><img src="docs/glows.jpg" alt="Glows tab"><br><b>Glows</b>: every weapon enchant glow in the game.</td>
</tr>
<tr>
<td><img src="docs/items.jpg" alt="Items tab"><br><b>Items</b>: pick a slot, filter by type, quality and source.</td>
<td><img src="docs/sets.jpg" alt="Sets tab"><br><b>Sets</b>: one click puts on a whole set (here Armor of Might).</td>
</tr>
<tr>
<td><img src="docs/wardrobe.jpg" alt="Wardrobe tab"><br><b>Wardrobe</b>: save a look by name, for all your characters.</td>
<td><img src="docs/favourites.jpg" alt="Favourites tab"><br><b>Favourites</b>: your starred models and mount skins.</td>
</tr>
</table>

<img src="docs/world.jpg" alt="A Black Spectral Tiger mount skin and a Black Drake morph in Orgrimmar" width="100%">

<img src="docs/morphs.jpg" alt="Four creature morphs in Orgrimmar" width="100%">

---

## 🎮 Using DMorph

Open the window with the minimap button, `/dmorph`, or a key under *Key Bindings > DMorph*. Escape closes it.

| Part | What it does |
|---|---|
| **Dressing room** (left) | Your character. Drag to turn, mouse wheel or **+ / -** to zoom, right-drag to move, **Reset view** to see it all. The **Size** slider under it changes your size (right-click: normal size). |
| **Slots** round the model | Left-click: items for that slot. Right-click: back to your own gear. Morphed slots glow green. |
| **Reset model** / **Reset everything** | Your own body back (items stay) / clear every morph. |
| **Models** tab | Grid or list of every model. Filter, search, sort; type a display ID and press **Morph**, or step through IDs with < >. Right-click stars a model. |
| **Mounts** tab | Choose **Skin for** (all your mounts, or one you've ridden) and click a model. ▲ ▼ step through the list, **Remove skin** takes it off. |
| **Favourites** tab | Your starred models and mount skins. Click to wear, right-click to unstar. |
| **Races** tab | Click a portrait to become that race with your own face. The < > rows change skin colour, face, hair style, hair colour and facial hair; **NPC look** wears the game's dressed NPCs; the dice picks a random look. |
| **Glows** tab | Pick **Main hand**, **Off hand** or **Ranged**, then a glow. **No glow** hides it, **My own glow** puts yours back. |
| **Items** / **Sets** tabs | Filter by type, quality and source, then click to wear. Any item works by its ID too. |
| **Wardrobe** tab | Save, load and delete outfits (mount skin, glows and looks included). |
| **Setup** (bottom left) | Green when everything works; click it to see what's running and how to fix what isn't. |
| **Sharing** (bottom) | Whether others see your morph, and whether you see theirs. |
| **Corner grip** (bottom right) | Drag to resize the window. |

### Chat commands

Type them in the chat box, like in DMorph. They never reach the server, and each also works after `/dmorph` (e.g. `/dmorph morph 4527` in a macro).

| Command | What it does |
|---|---|
| `.morph <displayID>` | Become any creature, e.g. `.morph 4527`. `.morph 0` resets. |
| `.race <1-10>` or `.race nightelf` | `1` Human, `2` Orc, `3` Dwarf, `4` Night Elf, `5` Undead, `6` Tauren, `7` Gnome, `8` Troll, `9` Goblin, `10` High Elf. |
| `.gender` | Swap the gender of your race or race morph. |
| `.item <slot> <itemID>` | Morph one slot, e.g. `.item 1 2955` or `.item head` + a shift-clicked item link. `0` resets the slot. |
| `.mount <displayID>` | Skin for all your mounts. `.mount 0` removes it. |
| `.scale <size>` | Your size: `.scale 0.5`, `.scale 2` or `.scale 200%`. `.scale 0` resets. |
| `.glow <slot> <enchantID>` | A weapon glow, e.g. `.glow mainhand 1900` (Crusader). `0` = none, `own` = yours. |
| `.demorph` / `.demorph all` | Reset your model / reset everything. |
| `.outfit`, `.outfit <name>`, `.outfit save <name>`, `.outfit delete <name>` | List, wear, save or delete outfits. |
| `.share on/off` / `.share others on/off` | Whether others see your morph / whether you see theirs. |
| `.dmorph check` / `.dmorph status` / `/dmorph help` | Setup check / what's morphed / all commands. |

Slots: `1` head, `3` shoulder, `4` shirt, `5` chest, `6` waist, `7` legs, `8` feet, `9` wrist, `10` hands, `15` back, `16` main hand, `17` off hand, `18` ranged, `19` tabard.

---

## 💡 Good to know

- **Who sees what:** you and other DMorph users see your model, items, mount skin and size (friendly players only; seeing someone's size needs DmorphHelper). Glows and picked faces are only on your own screen for now.
- **Seeing other DMorph users:** their morph shows when you target or mouse over them, when you're grouped, or straight away with SuperWoW. DMorph only talks to players near you, through hidden messages that no chat window shows.
- **Mount skins** go on when you mount and come off when you dismount. Flight master birds keep their own look.
- **Race morphs keep your own character's rules:** with DmorphHelper, the game still knows you as your own race, so you understand your own languages (no garbled chat), speak them, and see all your flight paths and spells as usual; only the model is the other race. Without DmorphHelper, your own race comes back for a moment while the flight map or spellbook is open, and chat is sent in a language you know, but other players' chat may look garbled.
- **Fast clicking is safe:** a click right after another waits its turn, so two looks never mix.
- **Shapeshifting** shows your morph instead of the form; reset your model first if you want the form.
- **Later expansions aren't in this game:** models, glows and races from The Burning Crusade onwards (Draenei, Mongoose glow, Outland mounts...) aren't in the 1.12 files, so no addon can show them. Everything OctoWoW and Turtle WoW added is included.

---

## 🛠️ For the curious and for developers

<details>
<summary><b>Check the lists against your own game</b> (optional)</summary>

DMorph ships lists made from OctoWoW's files (11 October 2026). After an OctoWoW client update, you can rebuild them from your own game files: close the game, open PowerShell in the `DmorphOcto` folder and run:

```
powershell -ExecutionPolicy Bypass -File tools\update_from_game.ps1
```

It lists every model, item set, glow and look in your game and hides any model or item that can't show (missing model or texture files). Then `/reload` in game.

</details>

<details>
<summary><b>How it works</b></summary>

DMorph itself is a DLL for WotLK 3.3.5a and can't run on the 1.12 client. This addon uses **VanillaHelpers** (OctoLauncher's mod) through its `SetUnitDisplayID`, `SetUnitVisibleItemID`, `SetUnitMountDisplayID` and `UnitDisplayInfo` functions. The previews use ClassicAPI's `Model:SetDisplayInfo`, and each new model loads out of sight so nothing flashes white.

**DmorphHelper** (`helper/DmorphHelper.c`) adds `DmorphHelper_GetItemEnchants` / `SetItemEnchants` (weapon glows), `DmorphHelper_GetLook` / `SetLook` (skin, face, hair) and `DmorphHelper_GetScale` / `SetScale` (size). It writes those values on your client only and makes the game rebuild your model, the way VanillaHelpers does. It uses VanillaHelpers' own game addresses and only switches on once it sees VanillaHelpers' hooks there.

- `DmorphOcto.lua`: morph state, wardrobe, search, item lookup and chat commands. `Share.lua`: sharing with other DMorph users. `UI.lua`: the window and minimap button.
- `Data/`: creatures and items from the [cmangos classic-db](https://github.com/cmangos/classic-db) 1.12.1 database, Turtle WoW data from [ShellLab](https://github.com/oplancelot/ShellLab), and everything else read from the client's own files.
- Saved data: `WTF\Account\<account>\SavedVariables\DmorphOcto.lua` (outfits, favourites, window settings) and each character's `SavedVariables\DmorphOcto.lua` (current look).

</details>

<details>
<summary><b>Development</b></summary>

Written for the client's Lua 5.0: no `#`, no `%`, no `string.match`.

- **Tests:** `tests/run_tests.lua` drives the addon inside `tests/mock_wow.lua`, a strict mock of the 1.12 UI, VanillaHelpers and DmorphHelper. Run `lua tests/run_tests.lua` with Lua 5.0, or on Windows `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1` (builds `tools/LuaHost`, .NET 8, with OBS Studio's Lua runtime; `LUA51_DLL` picks another).
- **Data:** `python3 tools/build_data.py <ClassicDB_1_12_1_*.sql.gz> --shelllab <shelllab.db>` rebuilds `Creatures.lua`, `Items.lua`, `ClassicTags.lua` and `ItemTypes.lua`; then `tools\update_from_game.ps1` (on Windows, with the game) runs `build_models.ps1`, `build_items.ps1` and `build_options.ps1` against the client's MPQs. `python3 tests/make_game_fixture.py <dir>` builds a fake game folder to test those tools.
- **DmorphHelper:** `sh helper/build.sh` with `gcc-mingw-w64-i686` (on Windows: [winlibs](https://winlibs.com)' 32-bit MSVCRT build, `PATH=/c/path/to/mingw32/bin:$PATH sh helper/build.sh` in Git Bash). When it gains functions, raise `HELPER_VERSION` in `DmorphHelper.c` and `DmorphOcto.lua` so the Setup check asks players to run the installer again.
- **Pictures:** `docs/src` has the banner and galleries as HTML (rendered with headless Edge) and the in-game crops they use.

</details>

## Credits

- [DMorph](https://darksectordds.github.io/html/dmorph/index.html) by DDS (darksectordds), for the original commands.
- [VanillaHelpers](https://github.com/isfir/VanillaHelpers) by isfir, which does the morphing on the 1.12.1 client.
- [ClassicAPI](https://github.com/brues-code/ClassicAPI) by brues-code, whose `Model:SetDisplayInfo` draws the previews.
- [MinHook](https://github.com/TsudaKageyu/minhook) by Tsuda Kageyu (BSD 2-clause), which DmorphHelper hooks the game with.
- Creature and item names from the [cmangos classic-db](https://github.com/cmangos/classic-db); Turtle WoW data from [ShellLab](https://github.com/oplancelot/ShellLab) by oplancelot; loot-table item IDs from Atlas-CFM.
