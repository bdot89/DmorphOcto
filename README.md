# DMorph for OctoWoW

[DMorph](https://darksectordds.github.io/html/dmorph/index.html)'s chat commands (`.morph`, `.race`, `.gender`, `.item`) for the **OctoWoW** client (1.12.1, build 5875, "Mysteries of Azeroth").

## Why DMorph itself doesn't work on OctoWoW

DMorph is a DLL plus `Injector.exe` built for **WotLK 3.3.5a (build 12340)**. It calls that client's code at hardcoded addresses (object manager `0x4D4DB0`, `CGUnit_C::UpdateDisplayInfo` `0x73E410`, and so on). OctoWoW runs a modified **1.12.1** client, where those addresses hold unrelated code. Injecting DMorph there crashes the game or does nothing. DMorph's source isn't published, so it can't be recompiled for 1.12 either.

This project brings DMorph's commands to OctoWoW as a normal 1.12 addon instead. The morphing itself is done by **VanillaHelpers** ([isfir/VanillaHelpers](https://github.com/isfir/VanillaHelpers)). VanillaHelpers is a 1.12.1 client mod that OctoLauncher already ships as its `vanillaHelpers` mod, and since v1.1.0 it has a morph API. That means:

- No injector and no new DLL. OctoWoW's custom exe breaks many third-party DLLs, but VanillaHelpers is one the launcher ships for it.
- Morphs survive server updates, gear changes and loading screens. They are saved per character.
- Everything is client-side: only you see the morph.

## Requirements

- The OctoWoW client.
- **VanillaHelpers v1.1.0 or newer**, loaded by the game. Either:
  - in **OctoLauncher**, enable the `vanillaHelpers` mod, or
  - add `VanillaHelpers.dll` from the [VanillaHelpers releases](https://github.com/isfir/VanillaHelpers/releases) to the game folder and list it in `dlls.txt` (VanillaFixes).

## Install

1. Put this repository in `Interface\AddOns\DmorphOcto\` inside your OctoWoW folder, so that `Interface\AddOns\DmorphOcto\DmorphOcto.toc` exists.
   - With git: `git clone https://github.com/bdot89/DmorphOcto.git Interface/AddOns/DmorphOcto`
   - From a GitHub ZIP, rename the extracted folder (for example `DmorphOcto-main`) to `DmorphOcto`. 1.12 only loads an addon whose folder name matches its `.toc`.
2. Start the game and log in. Type `/dmorph status`. It should say `VanillaHelpers v1.x.x is loaded`.

## Commands

Type them in the chat box like in DMorph. They are handled locally and never sent to chat. Each one also works after `/dmorph` (for example `/dmorph morph 4527`), which is handy in macros.

| Command | What it does |
|---|---|
| `.morph <displayID>` | Morph into any creature model, e.g. `.morph 4527`. `.morph 0` resets. |
| `.race <1-10>` | Morph into a race, keeping your current gender and your own skin, face and hair. `1` Human, `2` Orc, `3` Dwarf, `4` Night Elf, `5` Undead, `6` Tauren, `7` Gnome, `8` Troll, `9` Goblin, `10` High Elf. Names work too: `.race nightelf`. |
| `.gender` | Swap the gender of your race, or of your race morph. |
| `.item <slot> <itemID>` | Morph the item in a visible slot, e.g. `.item 1 2955`. A shift-clicked item link works in place of the ID. `.item <slot> 0` resets that slot. |
| `.demorph` | Reset your model (DMorph's **F5**). |
| `.demorph all` | Reset your model and all items (DMorph's **F10**). |
| `.dmorph status` | Show what is morphed and which VanillaHelpers version is loaded. `.dmorph` alone shows help. |

Item slots follow DMorph's numbering: `1` head, `3` shoulder, `4` shirt, `5` chest, `6` waist, `7` legs, `8` feet, `9` wrist, `10` hands, `15` back, `16` main hand, `17` off hand, `18` ranged, `19` tabard. Slot names such as `head`, `chest` or `mainhand` work too. Neck, rings and trinkets have no model, so they are refused.

Dot commands that aren't DMorph's (for example `.help`) still go to the server as before.

### Differences from DMorph

- **`.scale` is not supported.** VanillaHelpers has no API for model scale, so the command only prints a notice. It is still intercepted, so it never ends up in `/say`.
- **F5 and F10 aren't grabbed automatically**, so your existing key bindings stay as they are. Bind "Reset model (DMorph F5)" and "Reset model and items (DMorph F10)" under *Key Bindings > DMorph*, or use `.demorph` / `.demorph all`.
- **Races follow the 1.12 client.** Race 10 is the High Elf (Turtle-based clients), and Draenei (DMorph's race 11) don't exist in 1.12.
- **`.morph` and `.race` share one slot:** whichever you used last wins, and `.demorph` clears both.
- **Morphs are saved per character** and re-applied after login, `/reload` and loading screens.

## Good to know

- While your model is morphed, shapeshift and transform visuals (druid forms and the like) show your morph instead. Use `.demorph` before shapeshifting if you want to see the form.
- An item you haven't seen this session may not be in the client's item cache yet. If it doesn't appear, run the same `.item` command again after a moment.
- A display ID that doesn't exist in the client's data can leave you invisible. Use `.demorph` to recover. Morphs are only saved to disk on logout or `/reload`, so a morph that crashes the client won't come back on the next login.
- These are visual changes on your own client only. VanillaHelpers is a launcher-shipped mod, but check OctoWoW's rules if you are unsure about client mods.

## How it works

- `DmorphOcto.lua` wraps `SendChatMessage`. A chat line that starts with `.` followed by one of the commands above is handled by the addon instead of being sent.
- Commands call VanillaHelpers' Lua functions `SetUnitDisplayID`, `SetUnitVisibleItemID` and `UnitDisplayInfo` for the `player` unit. VanillaHelpers hooks the client's descriptor updates, so the server can't overwrite the morph. When the display ID is a player race model, it also swaps race and gender, which keeps your own customisation.
- The saved state lives in `WTF\Account\<account>\<realm>\<character>\SavedVariables\DmorphOcto.lua` (`DmorphOctoDB`). To start over, delete that file while the game is closed.

## Development

The addon is written for the client's Lua 5.0 (no `#`, no `%`, no `string.match`).

`tests/run_tests.lua` loads the addon into a mocked 1.12 client, with a fake VanillaHelpers that follows its `Morph.cpp`. It then drives the addon through chat, slash commands, events, `/reload` and loading screens. Run it from the repository root with a Lua 5.0 interpreter:

```sh
lua tests/run_tests.lua
```

## Credits

- [DMorph](https://darksectordds.github.io/html/dmorph/index.html) by DDS (darksectordds), for the original commands.
- [VanillaHelpers](https://github.com/isfir/VanillaHelpers) by isfir, which does the actual morphing on the 1.12.1 client.
