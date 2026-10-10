-- Offline tests for DMorph for OctoWoW.
--
-- Loads the addon, in .toc order, into tests/mock_wow.lua's strict 1.12 UI
-- mock with a fake VanillaHelpers morph API that follows src/Morph.cpp in
-- isfir/VanillaHelpers. Then drives it the way the game does: events,
-- OnUpdate, chat, slash commands, clicks in the window, /reload and logins.
--
-- Run from the repository root with a Lua 5.0 interpreter (the client's
-- version): lua tests/run_tests.lua

dofile("tests/mock_wow.lua")

local failures, checks = 0, 0

local function check(cond, what)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL: " .. what)
	end
end

local RACIAL = {
	[49] = 1, [50] = 1, [51] = 1, [52] = 1, [53] = 1, [54] = 1, [55] = 1, [56] = 1,
	[57] = 1, [58] = 1, [59] = 1, [60] = 1, [1563] = 1, [1564] = 1, [1478] = 1,
	[1479] = 1, [6894] = 1, [6895] = 1, [15475] = 1, [15476] = 1,
}

-- Game state the fake VanillaHelpers works on. It outlives a /reload, as the
-- real DLL's overrides do.
local vh

local function newClient(serverDisplay)
	vh = {
		serverDisplay = serverDisplay, serverNative = serverDisplay,
		display = serverDisplay, native = serverDisplay,
		items = {}, calls = 0,
	}
end

local function installMorphAPI()
	function SetUnitDisplayID(unit, displayID)
		if type(unit) ~= "string" then
			error("Usage: SetUnitDisplayID(unitToken [, displayID])")
		end
		vh.calls = vh.calls + 1
		if type(displayID) == "number" then
			vh.display = displayID
			-- A racial model also replaces the native display ID.
			if RACIAL[displayID] then
				vh.native = displayID
			else
				vh.native = vh.serverNative
			end
		else
			vh.display, vh.native = vh.serverDisplay, vh.serverNative
		end
	end

	function SetUnitVisibleItemID(unit, slot, itemID)
		if type(unit) ~= "string" or type(slot) ~= "number" then
			error("Usage: SetUnitVisibleItemID(unitToken, inventorySlot [, itemID])")
		end
		if slot < 1 or slot > 19 then
			error("Unknown inventory slot.")
		end
		vh.calls = vh.calls + 1
		if type(itemID) == "number" then
			vh.items[slot] = itemID
		else
			vh.items[slot] = nil
		end
	end

	function UnitDisplayInfo(unit)
		return vh.display, vh.native, 0
	end

	VANILLAHELPERS_VERSION = 10102
end

local function removeMorphAPI()
	SetUnitDisplayID, SetUnitVisibleItemID, UnitDisplayInfo = nil, nil, nil
	VANILLAHELPERS_VERSION = nil
end

-- Loads the addon like a fresh UI (login or /reload) and enters the world.
local function loadUI()
	Mock.ResetUI()
	Mock.LoadAddon("DmorphOcto.toc")
	Mock.Fire("VARIABLES_LOADED")
	Mock.Fire("PLAYER_ENTERING_WORLD")
	Mock.Tick(0.3)
	Mock.Tick(0.3)
end

-- What the chat edit box does when you press Enter.
local function say(text)
	Mock.chat = {}
	SendChatMessage(text, "SAY")
end

local function slash(text)
	Mock.chat = {}
	SlashCmdList["DMORPHOCTO"](text)
end

local function lastChat()
	return Mock.chat[table.getn(Mock.chat)] or ""
end

local function allChat()
	return table.concat(Mock.chat, "\n")
end

local function contains(s, part)
	return strfind(s or "", part, 1, true) ~= nil
end

------------------------------------------------------------------------------
-- Chat commands

-- Fresh human male, nothing saved.
newClient(49)
installMorphAPI()
DmorphOctoDB, DmorphOctoAccount = nil, nil
loadUI()
check(vh.calls == 0, "an empty profile must not touch any morph on login")
check(type(DmorphOctoDB) == "table" and type(DmorphOctoAccount) == "table", "saved variables are created")
check(DmorphOctoMinimapButton ~= nil, "the minimap button is created")

say(".morph 4527")
check(vh.display == 4527, ".morph sets the display ID")
check(table.getn(Mock.sent) == 0, ".morph is not sent to the server")
check(DmorphOctoDB.display == 4527, ".morph is saved")
check(contains(lastChat(), "Thrall (4527)"), ".morph names the creature")

say(".race 4")
check(vh.display == 55, ".race 4 keeps the native gender (Night Elf male)")
check(DmorphOctoDB.display == nil, ".race replaces .morph")

say(".gender")
check(vh.display == 56, ".gender swaps to Night Elf female")
say(".race orc")
check(vh.display == 52, ".race keeps the morphed gender (Orc female)")
say(".race 1")
check(vh.display == 50, ".race 1 gives Human female")
say(".gender")
check(vh.display == 49 and DmorphOctoDB.race == nil,
	"back to the native race and gender clears the override")

say(".race 11")
check(contains(lastChat(), "Draenei"), ".race 11 explains Draenei are missing")
say(".race 99")
check(contains(lastChat(), "Usage"), "bad race shows usage")
check(vh.display == 49, "bad race changes nothing")

say(".item 1 2955")
check(vh.items[1] == 2955, ".item morphs the head")
check(contains(lastChat(), "First Mate Hat"), ".item names cached items")
say(".item chest |cffffffff|Hitem:6795:0:0:0|h[White Swashbuckler's Shirt]|h|r")
check(vh.items[5] == 6795, ".item accepts a slot name and an item link")
check(contains(lastChat(), "White Swashbuckler's Shirt"), "uncached items are named from the catalogue")
say(".item 2 1234")
check(vh.items[2] == nil and contains(lastChat(), "Neck"), ".item rejects invisible slots")
say(".item 1 abc")
check(contains(lastChat(), "Usage"), ".item rejects a bad item ID")
say(".item 1 0")
check(vh.items[1] == nil and DmorphOctoDB.items[1] == nil, ".item <slot> 0 resets the slot")
say(".item 1 2955")

say(".scale 0.5")
check(table.getn(Mock.sent) == 0 and contains(lastChat(), "scale"),
	".scale is answered locally and never sent as /say")

say("hello there")
check(Mock.sent[1] == "hello there", "normal chat goes through")
say(".help")
check(Mock.sent[2] == ".help", "unknown dot commands still reach the server")

slash("morph 1060")
check(vh.display == 1060, "/dmorph morph works")
slash("status")
check(contains(allChat(), "v1.1.2") and contains(allChat(), "1060") and contains(allChat(), "Head"),
	"/dmorph status reports version, model and items")
slash("help")
check(table.getn(Mock.chat) > 3, "/dmorph help shows help")

-- /reload with a race morph active: the fake DLL keeps its overrides, so the
-- native display it reports is the morphed one until we clear it.
say(".race 6")
say(".gender")
check(vh.display == 60 and vh.native == 60, "Tauren female applied before reload")
loadUI()
check(vh.display == 60, "race morph is re-applied after /reload")
slash("status")
check(contains(allChat(), "Your character: Human male"), "native race is read correctly after /reload")
say(".gender")
check(vh.display == 59, ".gender after /reload uses the morphed race")
check(vh.items[1] == 2955 and vh.items[5] == 6795, "item morphs survive /reload")

-- Zoning: the server resends the real model, the addon puts the morph back.
vh.display, vh.native, vh.items = 49, 49, {}
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(0.6)
check(vh.display == 59 and vh.items[1] == 2955, "morph is re-applied after a loading screen")

DmorphOcto_Reset()
check(vh.display == 49 and vh.items[1] == 2955, "reset binding keeps items")
DmorphOcto_ResetAll()
check(vh.items[1] == nil and vh.items[5] == nil, "reset-all binding clears items")
check(next(DmorphOctoDB.items) == nil and DmorphOctoDB.display == nil and DmorphOctoDB.race == nil,
	"reset-all clears the saved look")

------------------------------------------------------------------------------
-- Wardrobe from chat

say(".outfit")
check(contains(lastChat(), "No outfits"), ".outfit with nothing saved says so")
say(".race 8")
say(".item head 2955")
say(".outfit save Troll Pirate")
check(DmorphOctoAccount.outfits["Troll Pirate"] ~= nil, ".outfit save stores the look")
check(DmorphOctoAccount.outfits["Troll Pirate"].race == 8
	and DmorphOctoAccount.outfits["Troll Pirate"].items[1] == 2955, "the saved outfit has race and items")
DmorphOcto_ResetAll()
say(".outfit troll pirate")
check(vh.display == 1478 and vh.items[1] == 2955, ".outfit <name> puts it on, ignoring case")
say(".morph 4527")
say(".item 5 6795")
say(".outfit Troll Pirate")
check(vh.display == 1478 and vh.items[5] == nil, "loading an outfit replaces the whole look")
say(".outfit")
check(contains(lastChat(), "Troll Pirate"), ".outfit lists saved outfits")
say(".outfit delete troll pirate")
check(DmorphOctoAccount.outfits["Troll Pirate"] == nil, ".outfit delete removes it")
say(".outfit Nope")
check(contains(lastChat(), "no outfit"), "loading a missing outfit says so")
DmorphOcto_ResetAll()

------------------------------------------------------------------------------
-- Catalogue

local creatures = DmorphOcto.GetCreatureCatalog()
check(creatures.count > 10000, "the creature catalogue is loaded")
local result, count = DmorphOcto.FilterCatalog(creatures, "  THRALL ")
check(count >= 1 and creatures.names[result[1]] == "Thrall" and creatures.ids[result[1]] == 4527,
	"search ignores case and spaces and ranks names that start with the text first")
result, count = DmorphOcto.FilterCatalog(creatures, "11121")
check(count >= 1 and creatures.names[result[1]] == "Ragnaros", "searching an ID finds that model first")
local all
all, count = DmorphOcto.FilterCatalog(creatures, "")
check(count == creatures.count, "an empty search lists everything")
local heads = DmorphOcto.GetItemCatalog(1)
result, count = DmorphOcto.FilterCatalog(heads, "first mate")
check(count == 1 and heads.ids[result[1]] == 2955, "head items can be searched by name")
local offhands = DmorphOcto.GetItemCatalog(17)
check(offhands.count > 500, "off hand lists weapons and shields")

------------------------------------------------------------------------------
-- The window

slash("")
local window = DmorphOctoFrame
check(window ~= nil and window:IsVisible(), "/dmorph opens the window")
check(contains(UISpecialFrames[1], "DmorphOctoFrame"), "Escape closes the window")
check(Mock.modelRefreshes > 0 and DmorphOctoModel.unit == "player", "the preview shows your character")

-- Models tab: search, pick, step through IDs.
local modelSearch = DmorphOctoModelSearch
Mock.Type(modelSearch, "thrall")
local firstRow = DmorphOctoModelListRow1
check(firstRow:IsVisible() and firstRow.text.text == "Thrall" and firstRow.info.text == "4527",
	"searching models shows Thrall first")
Mock.Click(firstRow)
check(vh.display == 4527 and DmorphOctoDB.display == 4527, "clicking a model morphs you")
check(firstRow.locked, "the model you wear is highlighted")
check(contains(DmorphOctoFrameStatus.text, "Thrall"),
	"the status line confirms the morph")
Mock.Click(Mock.FindButton(">"))
check(vh.display == 4528, "> steps to the next model ID")
Mock.Click(Mock.FindButton("<"))
Mock.Click(Mock.FindButton("<"))
check(vh.display == 4526, "< steps back")

-- Scrolling a long list.
Mock.Type(modelSearch, "")
local bar = DmorphOctoModelListScrollBar
check(DmorphOctoModelList:IsShown(), "a long list shows its scroll bar")
Mock.RunScript(DmorphOctoModelListRow1, "OnMouseWheel", -1)
check(DmorphOctoModelList.offset == 3, "the mouse wheel over the rows scrolls the list")
check(DmorphOctoModelListRow1.text.text == creatures.names[4], "scrolled rows show later entries")

-- Races tab.
Mock.Click(Mock.FindButton("Races"))
check(DmorphOctoModelListRow1:IsVisible() == false, "switching tabs hides the models list")
for i = 1, table.getn(Mock.frames) do
	local f = Mock.frames[i]
	if f.race == 4 and f.gender == 1 then
		Mock.Click(f)
	end
end
check(vh.display == 56, "the races tab morphs into Night Elf female")
Mock.Click(Mock.FindButton("Swap gender"))
check(vh.display == 55, "swap gender works from the window")

-- Items: click the head slot next to the model, search and pick.
Mock.Click(DmorphOctoSlot1)
check(DmorphOctoSlot1.locked, "the chosen slot is highlighted")
local itemSearch = DmorphOctoItemSearch
Mock.Type(itemSearch, "first mate")
local itemRow = DmorphOctoItemListRow1
check(itemRow:IsVisible() and itemRow.text.text == "First Mate Hat", "the head list finds the hat")
Mock.Click(itemRow)
check(vh.items[1] == 2955, "clicking an item morphs that slot")
Mock.Type(itemSearch, "")
Mock.Click(DmorphOctoItemListRow3)
local locked = {}
for i = 1, 14 do
	if getglobal("DmorphOctoItemListRow" .. i).locked then
		table.insert(locked, i)
	end
end
check(table.getn(locked) == 1 and locked[1] == 3, "only the item you wear is highlighted")
Mock.Type(itemSearch, "first mate")
Mock.Click(itemRow)
check(DmorphOctoSlot1.icon.texture == "Interface\\Icons\\INV_Misc_Bandana_03" and DmorphOctoSlot1.glow.shown,
	"the slot shows the morphed item's icon")
Mock.RunScript(DmorphOctoSlot1, "OnEnter")
check(contains(table.concat(GameTooltip.lines, "\n"), "First Mate Hat"), "the slot tooltip names the item")
Mock.Click(Mock.FindButton(">"))
check(DmorphOctoItemSlotLabel.text == "Items: Shoulder", "> moves to the next slot")
Mock.Click(DmorphOctoSlot1, "RightButton")
check(vh.items[1] == nil, "right-clicking a slot puts your own gear back")
check(DmorphOctoSlot5.icon.texture == "Interface\\Icons\\INV_Chest_Plate01", "unmorphed slots show your gear")
Mock.Click(DmorphOctoSlot1)
Mock.Type(DmorphOctoItemID, "2955")
Mock.Click(Mock.FindButton("Apply"))
check(vh.items[1] == 2955, "typing an item ID and pressing Apply works")

-- Wardrobe: save, reset, load, delete.
Mock.Click(Mock.FindButton("Wardrobe"))
check(DmorphOctoOutfitListRow1:IsVisible() == false, "the wardrobe starts empty")
Mock.Type(DmorphOctoOutfitName, "Elf Pirate")
Mock.Click(Mock.FindButton("Save current look"))
local outfit = DmorphOctoAccount.outfits["Elf Pirate"]
check(outfit and outfit.race == 4 and outfit.gender == 0 and outfit.items[1] == 2955,
	"saving stores the current look")
local outfitRow = DmorphOctoOutfitListRow1
check(outfitRow:IsVisible() and outfitRow.text.text == "Elf Pirate" and contains(outfitRow.info.text, "Night Elf male"),
	"the wardrobe lists the outfit with a summary")
Mock.Click(Mock.FindButton("Reset everything"))
check(vh.display == 49 and vh.items[1] == nil, "reset everything from the window")
Mock.Click(outfitRow)
check(outfitRow.locked, "clicking an outfit selects it")
Mock.Click(Mock.FindButton("Load"))
check(vh.display == 55 and vh.items[1] == 2955, "load puts the outfit back on")
DmorphOcto_ResetAll()
Mock.Click(outfitRow)
check(vh.display == 55, "clicking the selected outfit again puts it on")

-- Survives /reload and a fresh login.
loadUI()
check(vh.display == 55 and vh.items[1] == 2955, "the look survives /reload")
slash("")
Mock.Click(Mock.FindButton("Wardrobe"))
check(DmorphOctoOutfitListRow1:IsVisible() and DmorphOctoOutfitListRow1.text.text == "Elf Pirate",
	"saved outfits survive /reload")
newClient(49)
loadUI()
check(vh.display == 55 and vh.items[1] == 2955, "the look comes back after logging in again")

slash("")
Mock.Click(Mock.FindButton("Wardrobe"))
Mock.Click(DmorphOctoOutfitListRow1)
Mock.Click(Mock.FindButton("Delete"))
check(Mock.popups[1] and Mock.popups[1].which == "DMORPHOCTO_DELETE_OUTFIT", "delete asks first")
StaticPopupDialogs["DMORPHOCTO_DELETE_OUTFIT"].OnAccept()
check(DmorphOctoAccount.outfits["Elf Pirate"] == nil and not DmorphOctoOutfitListRow1:IsVisible(),
	"confirming deletes the outfit")

-- Closing and the minimap button.
Mock.Click(DmorphOctoFrameClose)
check(not DmorphOctoFrame:IsVisible(), "the close button hides the window")
Mock.Click(DmorphOctoMinimapButton)
check(DmorphOctoFrame:IsVisible(), "the minimap button opens the window")
Mock.cursorX, Mock.cursorY = 600, 400
Mock.RunScript(DmorphOctoMinimapButton, "OnDragStart")
Mock.Tick(0.1)
Mock.RunScript(DmorphOctoMinimapButton, "OnDragStop")
check(DmorphOctoAccount.minimap.x == 80 and DmorphOctoAccount.minimap.y == 0,
	"dragging moves the minimap button around the edge")
DmorphOcto_ToggleUI()
check(not DmorphOctoFrame:IsVisible(), "the key binding closes the window")

------------------------------------------------------------------------------
-- Saved data from older versions or hand edits

newClient(49)
DmorphOctoDB = { display = "x", race = 42, gender = 7, items = { [2] = 5, [1] = -3, [5] = 10 } }
DmorphOctoAccount = { outfits = { good = { race = 2, items = { [1] = "2955" } }, [3] = {}, bad = "x" } }
loadUI()
check(DmorphOctoDB.display == nil and DmorphOctoDB.race == nil, "bad body values are dropped")
check(DmorphOctoDB.items[2] == nil and DmorphOctoDB.items[1] == nil and DmorphOctoDB.items[5] == 10,
	"only valid item morphs are kept")
check(vh.items[5] == 10 and vh.display == 49, "valid saved items are applied")
check(DmorphOctoAccount.outfits.good.items[1] == 2955 and DmorphOctoAccount.outfits[3] == nil
	and DmorphOctoAccount.outfits.bad == nil, "bad outfits are dropped, good ones cleaned up")

newClient(49)
DmorphOctoDB = { display = "4527", items = { [1] = "2955" } }
loadUI()
check(DmorphOctoDB.display == 4527 and DmorphOctoDB.items[1] == 2955,
	"numeric strings in saved variables become numbers")
check(vh.display == 4527 and vh.items[1] == 2955, "normalised saved morphs are applied")

-- A female Goblin: .gender without a race morph uses the native race.
newClient(6895)
DmorphOctoDB = nil
loadUI()
say(".gender")
check(vh.display == 6894, ".gender on a native Goblin female gives Goblin male")

------------------------------------------------------------------------------
-- Without VanillaHelpers, everything explains what is missing and stays local.

newClient(49)
removeMorphAPI()
DmorphOctoDB = nil
loadUI()
check(contains(lastChat(), "VanillaHelpers"), "missing DLL is reported at login")
say(".morph 4527")
check(table.getn(Mock.sent) == 0 and contains(lastChat(), "VanillaHelpers"),
	"commands without the DLL explain instead of being sent")
slash("help")
check(contains(allChat(), "VanillaHelpers"), "help mentions the missing DLL")
slash("")
check(DmorphOctoFrame:IsVisible() and contains(DmorphOctoFrameStatus.text, "VanillaHelpers"),
	"the window opens and says the DLL is missing")
Mock.Type(DmorphOctoModelSearch, "thrall")
Mock.Click(DmorphOctoModelListRow1)
check(contains(DmorphOctoFrameStatus.text, "VanillaHelpers"), "clicking a model without the DLL explains")

print(format("%d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
