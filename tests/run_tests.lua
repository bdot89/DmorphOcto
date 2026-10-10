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
		items = {}, calls = 0, others = {},
	}
end

-- Another player (Mock.units): VanillaHelpers keeps their morph on their GUID
-- and refuses players it can't see or can't assist.
local function otherUnit(unit)
	local u = Mock.Unit(unit)
	if not u then
		error("Unit not found.")
	end
	if not u.friendly then
		error("Unit is not friendly.")
	end
	vh.others[u.guid] = vh.others[u.guid] or { items = {} }
	return vh.others[u.guid]
end

local function installMorphAPI()
	function SetUnitDisplayID(unit, displayID)
		if type(unit) ~= "string" then
			error("Usage: SetUnitDisplayID(unitToken [, displayID])")
		end
		if unit ~= "player" then
			otherUnit(unit).display = type(displayID) == "number" and displayID or nil
			return
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
		if unit ~= "player" then
			otherUnit(unit).items[slot] = type(itemID) == "number" and itemID or nil
			return
		end
		vh.calls = vh.calls + 1
		if type(itemID) == "number" then
			vh.items[slot] = itemID
		else
			vh.items[slot] = nil
		end
	end

	-- The mount field: what the server says (vh.serverMount, 0 = on foot),
	-- unless the override holds a model in place whatever the server says.
	function SetUnitMountDisplayID(unit, displayID)
		if type(unit) ~= "string" then
			error("Usage: SetUnitMountDisplayID(unitToken [, mountDisplayID])")
		end
		if unit ~= "player" then
			otherUnit(unit).mount = displayID
			return
		end
		vh.calls = vh.calls + 1
		vh.mount = displayID
	end

	function UnitDisplayInfo(unit)
		if unit ~= "player" then
			local u = Mock.Unit(unit)
			if not u then
				error("Unit not found.")
			end
			local o = vh.others[u.guid] or {}
			return o.display or u.display, u.display, o.mount or 0
		end
		return vh.display, vh.native, vh.mount or vh.serverMount or 0
	end

	VANILLAHELPERS_VERSION = 10102
end

local function removeMorphAPI()
	SetUnitDisplayID, SetUnitVisibleItemID, UnitDisplayInfo, SetUnitMountDisplayID = nil, nil, nil, nil
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


-- Mount skins from chat: shown only while you ride, so mounting and
-- dismounting work as usual.
local function mountUp(display)
	vh.serverMount = display
	Mock.buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude", "Interface\\Icons\\Ability_Mount_Undeadhorse" }
	Mock.Tick(0.15)
end
local function dismount()
	vh.serverMount = 0
	Mock.buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude" }
	Mock.Tick(0.15)
end
Mock.buffs = { "Interface\\Icons\\Spell_Holy_WordFortitude" }
Mock.Tick(0.15)
say(".mount 14334")
check(DmorphOctoDB.mount == 14334 and vh.mount == nil, ".mount sets a skin but doesn't put you on a mount")
check(contains(lastChat(), "shows when you mount"), "it says the skin shows when you mount")
mountUp(10671)
check(vh.mount == 14334, "mounting shows the skin")
dismount()
check(vh.mount == nil, "dismounting takes the skin off, so you're on foot")
mountUp(10671)
check(vh.mount == 14334, "and mounting again puts it back")
check(DmorphOctoDB.ridden[1] == 10671, "the mounts you ride are remembered")
DmorphOcto.SetMountSkin(15677, 10671)
Mock.Tick(0.15)
check(vh.mount == 15677, "a skin for one mount beats the skin for all mounts")
dismount()
mountUp(14348)
check(vh.mount == 14334, "other mounts keep the skin for all mounts")
say(".outfit save Rider")
DmorphOcto_ResetAll()
Mock.Tick(0.15)
check(vh.mount == nil and DmorphOctoDB.mount == nil and next(DmorphOctoDB.mountSkins) == nil,
	"reset-all takes every skin off")
say(".outfit rider")
Mock.Tick(0.15)
check(vh.mount == 14334, "outfits keep the skin")
dismount()
say(".mount 0")
check(DmorphOctoDB.mount == nil, ".mount 0 removes the skin")
say(".outfit delete rider")
DmorphOcto_ResetAll()
vh.serverMount = 0

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

-- Every display ID the client has: the named creatures plus Data/Models.lua.
local file = io.open("Data/Models.lua")
local modelText = file:read("*a")
file:close()
local fileModels, wrongKind, octo = 0, 0, 0
for id, kind in string.gfind(modelText, "\n(%d+)\t(%d)\t") do
	fileModels = fileModels + 1
	local index = creatures.byID[tonumber(id)]
	if not index then
		wrongKind = wrongKind + 1
	end
	if kind == "2" or kind == "3" then
		octo = octo + 1
	end
end
check(fileModels > 4000 and wrongKind == 0, "every model in Models.lua is in the catalogue")
check(octo > 2800, "the models OctoWoW added are in the catalogue")
local sorted = true
for i = 2, creatures.count do
	if creatures.lower[i - 1] > creatures.lower[i] then
		sorted = false
	end
end
check(sorted, "the merged catalogue is sorted by name")
local F = DmorphOcto.MODEL_FILTERS
local function filterNamed(text)
	for i = 1, table.getn(F) do
		if F[i].text == text then
			return F[i]
		end
	end
end
result, count = DmorphOcto.FilterCatalog(creatures, "zul'jin", filterNamed("New in OctoWoW"))
check(count >= 1 and creatures.ids[result[1]] == 18082, "OctoWoW's models can be searched and filtered")
check(DmorphOcto.DescribeDisplay(18082) == "Zul'jin (18082)", "OctoWoW's models have Turtle WoW's creature names")
local _, named = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Creatures"))
local _, other = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Other models"))
local _, added = DmorphOcto.FilterCatalog(creatures, "", filterNamed("New in OctoWoW"))
check(named > 10000 and named + other == creatures.count and added == octo, "the filters split the catalogue")
result, count = DmorphOcto.FilterCatalog(creatures, "thrall", filterNamed("Other models"))
check(count == 0, "a filter hides the other kinds from a search")
result, count = DmorphOcto.FilterCatalog(creatures, "ragnaros", filterNamed("Bosses"))
check(count >= 1 and creatures.ids[result[1]] == 11121, "Ragnaros is a boss")
local _, bosses = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Bosses"))
local _, mounts = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Mounts"))
local _, rares = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Rare creatures"))
check(bosses > 100 and mounts > 300 and rares > 200, "bosses, mounts and rare creatures are tagged")
result, count = DmorphOcto.FilterCatalog(creatures, "", filterNamed("Mounts"), nil, true)
local byID = true
for i = 2, count do
	if creatures.ids[result[i - 1]] > creatures.ids[result[i]] then
		byID = false
	end
end
check(byID, "lists can be sorted by ID")

-- Items: Turtle WoW's and OctoWoW's join the 1.12 lists.
result, count = DmorphOcto.FilterCatalog(heads, "crown of prophecy")
check(count >= 1 and heads.kind[result[1]] == 2, "OctoWoW's items are in the slot lists, marked new")
local mainHands = DmorphOcto.GetItemCatalog(16)
result, count = DmorphOcto.FilterCatalog(mainHands, "warglaive of azzinoth")
check(count >= 1, "the Warglaives of Azzinoth are there")
local Q = DmorphOcto.QUALITY_FILTERS
result, count = DmorphOcto.FilterCatalog(heads, "", nil, Q[6].quality)
local epic = count > 50
for i = 1, count do
	if heads.quality[result[i]] ~= 4 then
		epic = false
	end
end
check(Q[6].text == "Epic" and epic, "the quality filter keeps only epic items")
check(DmorphOcto.GetItemSlots(16966)[1] == 5, "an item's slot can be looked up")

-- Sets and looks.
local sets = DmorphOcto.GetSetCatalog()
result, count = DmorphOcto.FilterCatalog(sets, "battlegear of wrath")
check(sets.count > 300 and count >= 1 and sets.names[result[1]] == "Battlegear of Wrath"
	and sets.quality[result[1]] == 4, "every item set is listed, with its quality")
local looks = DmorphOcto.GetLooks(4, 1)
check(table.getn(looks) > 300 and table.getn(looks[1]) == 8, "Night Elf females have hundreds of NPC looks")
local skins = DmorphOcto.GetLookValues(4, 1, 1)
local other = DmorphOcto.FindLook(4, 1, 1, skins[2], 1)
check(other and looks[other][2] == skins[2], "the creator finds a look with the chosen skin colour")

------------------------------------------------------------------------------
-- The window, with ClassicAPI's model previews

Mock.classicAPI = true
loadUI()
slash("")
local window = DmorphOctoFrame
check(window ~= nil and window:IsVisible(), "/dmorph opens the window")
check(contains(UISpecialFrames[1], "DmorphOctoFrame"), "Escape closes the window")
Mock.Tick(0.2)
Mock.Tick(0.5)

-- A click that morphs, then the gate's pause, so the next click goes through.
local function press(button, mouseButton)
	Mock.Click(button, mouseButton)
	Mock.Tick(0.4)
end

-- Clicks the line of the open drop-down menu with that text.
local function pickMenu(text)
	for i = 1, 14 do
		local row = getglobal("DmorphOctoMenuRow" .. i)
		if row:IsVisible() and row.label.text == text then
			return Mock.Click(row)
		end
	end
	error("no menu line \"" .. text .. "\"")
end

-- The character preview has two PlayerModels: the one in front is never
-- reloaded (a reloading model draws white), the new look loads behind the
-- backdrop and then takes its place.
local function previews()
	local a, b = DmorphOctoModel1, DmorphOctoModel2
	if b:IsShown() and (not a:IsShown() or b.level > a.level) then
		return b, a
	end
	return a, b
end
local front, back = previews()
check(front:IsShown() and front.unit == "player", "the preview shows your character")
check(DmorphOctoArt1.texture == "Interface\\DressUpFrame\\DressUpBackground-Human1",
	"the preview stands in your race's dressing room")
check(DmorphOctoLookName.text == "Tester" and DmorphOctoLookInfo.text == "Not morphed", "the name plate shows your own look")
local frontLoads = front.unitLoads
say(".morph 4527")
Mock.Tick(0.05)
check(front.unitLoads == frontLoads and not back:IsShown(), "a change doesn't touch the model you see")
Mock.Tick(0.1)
check(back:IsShown() and back.unit == "player" and back.level < front.level,
	"the new look loads behind the backdrop")
check(DmorphOctoArt1:GetParent().level > back.level and DmorphOctoArt1:GetParent().level < front.level,
	"the backdrop sits between the two models")
local refreshes = Mock.modelRefreshes
say(".morph 4528")
Mock.Tick(0.15)
check(Mock.modelRefreshes == refreshes, "a model that is still loading isn't loaded again")
Mock.Tick(0.5)
local newFront = previews()
check(newFront == back and front.unitLoads == frontLoads, "then it replaces the old one, which was never reloaded")
Mock.Tick(0.15)
check(Mock.modelRefreshes == refreshes + 1, "and the change made while it loaded follows straight after")
Mock.Tick(0.5)
check(DmorphOctoLookName.text == (DmorphOcto.GetDisplayName(4528) or "Unlisted model") and DmorphOctoLookInfo.text == "Display ID 4528",
	"the name plate names the morph")
refreshes = Mock.modelRefreshes
say(".morph 4527")
say(".item 1 2955")
say(".race 2")
Mock.Tick(0.15)
Mock.Tick(0.5)
check(Mock.modelRefreshes == refreshes + 1, "a burst of changes loads the preview once")
check(DmorphOctoArt1.texture == "Interface\\DressUpFrame\\DressUpBackground-Orc1", "a race morph moves to that race's room")
check(DmorphOctoLookInfo.text == "Race morph - 1 item morphed", "the name plate counts item morphs")
refreshes = Mock.modelRefreshes
Mock.Fire("UNIT_MODEL_CHANGED", "player")
Mock.Tick(0.15)
check(Mock.modelRefreshes == refreshes + 1, "the preview follows model changes from the game")
DmorphOcto_ResetAll()
Mock.Tick(0.15)
Mock.Tick(0.5)

-- Models tab: a grid of previews, 8 to a page.
local catalog = DmorphOcto.GetCreatureCatalog()
check(DmorphOctoModelGrid:IsVisible() and not DmorphOctoModelListRow1:IsVisible(),
	"with ClassicAPI the models tab shows previews")
check(DmorphOctoTile1Model.displayInfo == catalog.ids[1] and DmorphOctoTile1.title.text == catalog.names[1]
	and DmorphOctoTile8Model.displayInfo == catalog.ids[8], "the tiles preview the first 8 models")
check(DmorphOctoTile1Model.camera == 0, "previews use the model's portrait camera")
check(contains(DmorphOctoPagerText.text, "Page 1/2,0"), "the pager counts the pages")
Mock.Click(DmorphOctoNextPage)
check(DmorphOctoTile1Model.displayInfo == catalog.ids[9], "the next page shows the next 8")
check(DmorphOctoTile1Model.level == 2, "a new preview loads behind its cover")
Mock.Tick(0.5)
check(DmorphOctoTile1Model.level == 4, "and comes out once it has loaded")
Mock.RunScript(DmorphOctoTile3, "OnMouseWheel", 1)
check(DmorphOctoTile1Model.displayInfo == catalog.ids[1] and DmorphOctoPrevPage.disabled,
	"the mouse wheel turns pages, and the first page can't go back")
local loads = Mock.displayLoads
Mock.Click(DmorphOctoTabRaces)
Mock.Click(DmorphOctoTabModels)
check(Mock.displayLoads == loads, "previews that are already loaded aren't loaded again")
Mock.RunScript(DmorphOctoTile2, "OnEnter")
Mock.Tick(0.5)
check(DmorphOctoTile2Model.facing ~= 0 and GameTooltip.lines[1] == "Display ID " .. catalog.ids[2],
	"hovering a preview turns it and shows its ID")
Mock.RunScript(DmorphOctoTile2, "OnLeave")

local modelSearch = DmorphOctoModelSearch
Mock.Type(modelSearch, "thrall")
check(DmorphOctoTile1:IsVisible() and DmorphOctoTile1.title.text == "Thrall" and DmorphOctoTile1Model.displayInfo == 4527,
	"searching shows Thrall first")
press(DmorphOctoTile1)
check(vh.display == 4527 and DmorphOctoDB.display == 4527, "clicking a preview morphs you")
check(DmorphOctoTile1.border[1] == 1 and DmorphOctoTile1.border[2] == 0.82, "the model you wear has a gold frame")
check(contains(DmorphOctoFrameStatus.text, "Thrall"), "the status line confirms the morph")
press(Mock.FindButton(">"))
check(vh.display == 4528, "> steps to the next model ID")
press(Mock.FindButton("<"))
press(Mock.FindButton("<"))
check(vh.display == 4526, "< steps back")

-- Fast clicks wait their turn: the game rebuilds your character after each.
Mock.Type(modelSearch, "")
Mock.Click(DmorphOctoTile1)
Mock.Click(DmorphOctoTile2)
Mock.Click(DmorphOctoTile3)
check(vh.display == DmorphOctoTile1.displayID, "a quick second click waits while the first one rebuilds you")
Mock.Tick(0.4)
check(vh.display == DmorphOctoTile3.displayID, "then only the latest click is applied")
Mock.Tick(0.4)

-- Categories and sorting.
Mock.Click(DmorphOctoModelFilter)
check(DmorphOctoMenu:IsVisible(), "the filter button opens a menu")
pickMenu("Bosses")
check(DmorphOctoModelFilter.text == "Bosses" and contains(catalog.tags[DmorphOctoTile1.entry], "boss"),
	"the Bosses filter lists bosses")
Mock.Click(DmorphOctoModelFilter)
pickMenu("Mounts")
check(contains(catalog.tags[DmorphOctoTile1.entry], "mount") and DmorphOctoAccount.ui.filter == 5,
	"the Mounts filter lists mount models, and it's remembered")
Mock.Click(DmorphOctoModelSort)
check(DmorphOctoModelSort.text == "Sort: ID" and DmorphOctoTile1.displayID <= DmorphOctoTile2.displayID,
	"the sort button lists by ID")
Mock.Click(DmorphOctoModelSort)
Mock.Click(DmorphOctoModelFilter)
pickMenu("New in OctoWoW")
check(catalog.kind[DmorphOctoTile1.entry] >= 2, "the filter shows only OctoWoW's models")
Mock.Click(DmorphOctoModelFilter)
pickMenu("All models")
check(DmorphOctoModelFilter.text == "All models", "back to all models")

-- Mounts tab: skins for your mount.
Mock.Click(DmorphOctoTabMounts)
check(DmorphOctoMountListRow1:IsVisible()
	and contains(catalog.tags[catalog.byID[tonumber(DmorphOctoMountListRow1.info.text)]] or "", "mount"),
	"the mounts tab lists mount models")
check(contains(DmorphOctoMountState.text, "Not riding"), "it says whether you ride")
local skin = tonumber(DmorphOctoMountListRow1.info.text)
press(DmorphOctoMountListRow1)
check(DmorphOctoDB.mount == skin and vh.mount == nil, "clicking a model makes it the skin for all your mounts")
check(DmorphOctoMountListRow1.tick.shown and DmorphOctoMountListRow1.locked and not DmorphOctoMountListRow2.tick.shown,
	"the skin you have on is ticked and lit in the list")
check(DmorphOctoMountSkinID.text == "Display ID " .. skin and DmorphOctoMountSkinFor.text == "For: All my mounts"
	and DmorphOctoMountPanelModel.displayInfo == skin, "the Your skin box shows it, turning, and which mounts it is for")
local second = tonumber(DmorphOctoMountListRow2.info.text)
press(DmorphOctoMountNext)
check(DmorphOctoDB.mount == second and DmorphOctoMountListRow2.tick.shown, "the down arrow puts on the next model")
press(DmorphOctoMountPrev)
check(DmorphOctoDB.mount == skin and DmorphOctoMountListRow1.tick.shown, "the up arrow goes back")
for n = 1, 20 do
	press(DmorphOctoMountNext)
end
local pickRow
for i = 1, 15 do
	if getglobal("DmorphOctoMountListRow" .. i).tick.shown then
		pickRow = getglobal("DmorphOctoMountListRow" .. i)
	end
end
check(pickRow and tonumber(pickRow.info.text) == DmorphOctoDB.mount, "the list scrolls to keep your skin in view")
for n = 1, 20 do
	press(DmorphOctoMountPrev)
end
check(DmorphOctoDB.mount == skin, "and back up to the first")
vh.serverMount = 10671
Mock.buffs = { "Interface\\Icons\\Ability_Mount_Undeadhorse" }
Mock.Tick(0.15)
check(vh.mount == skin and contains(DmorphOctoMountState.text, "riding"), "riding shows the skin, and the tab says so")
local ownName = DmorphOcto.GetDisplayName(10671) or "Mount 10671"
Mock.Click(DmorphOctoMountFor)
pickMenu(ownName)
check(DmorphOctoMountFor.text == ownName, "the mount you ride can get its own skin")
press(DmorphOctoMountListRow2)
check(DmorphOctoDB.mountSkins[10671] == tonumber(DmorphOctoMountListRow2.info.text)
	and vh.mount == DmorphOctoDB.mountSkins[10671], "its own skin shows at once")
Mock.Click(DmorphOctoMountListRow3, "RightButton")
check(DmorphOcto.IsFavourite(tonumber(DmorphOctoMountListRow3.info.text), true) and DmorphOctoMountListRow3.star.shown,
	"right-clicking a mount model stars it as a mount")
Mock.Click(DmorphOctoMountListRow3, "RightButton")
check(not DmorphOctoMountListRow3.star.shown, "a second right-click takes the star off")
press(Mock.FindButton("Remove skin"))
check(DmorphOctoDB.mountSkins[10671] == nil and vh.mount == skin, "removing its own skin goes back to the skin for all")
vh.serverMount = 0
Mock.buffs = {}
Mock.Tick(0.15)
check(vh.mount == nil, "dismounting takes the skin off")
Mock.Click(DmorphOctoMountFor)
pickMenu("All my mounts")
press(Mock.FindButton("Remove skin"))
check(DmorphOctoDB.mount == nil, "the skin for all mounts can be removed too")
Mock.Click(DmorphOctoTabModels)

-- Favourites: right-click stars a model.
Mock.Type(modelSearch, "thrall")
Mock.Click(DmorphOctoTile1, "RightButton")
check(DmorphOcto.IsFavourite(4527) and DmorphOctoTile1.star.shown and contains(DmorphOctoFrameStatus.text, "favourite models"),
	"right-clicking a model stars it")
Mock.RunScript(DmorphOctoTile1, "OnEnter")
check(contains(table.concat(GameTooltip.lines, "\n"), "Right-click to take it off"), "the tooltip says a right-click unstars it")
Mock.RunScript(DmorphOctoTile1, "OnLeave")
DmorphOcto.ToggleFavourite(4527, true)
check(DmorphOcto.IsFavourite(4527, true) and DmorphOcto.IsFavourite(4527), "a model and a mount can both be starred")
Mock.Type(modelSearch, "ragnaros")
Mock.Click(DmorphOctoTile1, "RightButton")
Mock.Click(DmorphOctoTile1, "RightButton")
check(not DmorphOcto.IsFavourite(11121) and not DmorphOctoTile1.star.shown, "a second right-click takes the star off")
Mock.Click(DmorphOctoTile1, "RightButton")
Mock.Type(modelSearch, "")

Mock.Click(DmorphOctoTabFavourites)
check(DmorphOctoFavListRow1:IsVisible() and DmorphOctoFavCount.text == "3 favourites"
	and DmorphOctoFavListRow1.text.text == "Ragnaros", "the favourites tab lists them, A-Z")
Mock.Click(DmorphOctoFavFilter)
pickMenu("Mounts")
check(DmorphOctoFavCount.text == "1 favourite" and DmorphOctoFavListRow1.info.text == "Mount 4527", "the filter shows only mounts")
press(DmorphOctoFavListRow1)
check(DmorphOctoDB.mount == 4527, "clicking a favourite mount makes it your mount skin")
Mock.Click(DmorphOctoFavFilter)
pickMenu("Models")
press(DmorphOctoFavListRow1)
check(vh.display == 11121, "clicking a favourite model morphs you")
Mock.RunScript(DmorphOctoFavListRow1, "OnEnter")
check(DmorphOctoPreviewCard:IsVisible() and DmorphOctoPreviewCardModel.displayInfo == 11121, "hovering a favourite previews it")
Mock.RunScript(DmorphOctoFavListRow1, "OnLeave")
Mock.Click(DmorphOctoFavListRow1, "RightButton")
check(not DmorphOcto.IsFavourite(11121) and DmorphOctoFavCount.text == "1 favourite", "right-clicking a favourite takes it off")
Mock.Click(DmorphOctoFavFilter)
pickMenu("All favourites")
Mock.Click(DmorphOctoFavSort)
check(DmorphOctoFavSort.text == "Sort: ID", "favourites sort by ID too")
Mock.Click(DmorphOctoFavSort)
Mock.Click(DmorphOctoTabModels)

-- List view, with a preview card for the row under the mouse.
Mock.Click(DmorphOctoModelView)
check(not DmorphOctoModelGrid:IsVisible() and DmorphOctoModelListRow1:IsVisible(), "list view swaps the grid for a list")
check(DmorphOctoAccount.ui.list == true, "the view is remembered")
Mock.RunScript(DmorphOctoModelListRow2, "OnEnter")
check(DmorphOctoPreviewCard:IsVisible() and DmorphOctoPreviewCardModel.displayInfo == catalog.ids[2],
	"hovering a row previews its model")
Mock.RunScript(DmorphOctoModelListRow2, "OnLeave")
check(not DmorphOctoPreviewCard:IsVisible(), "the preview card goes when the mouse does")
Mock.Type(modelSearch, "thrall")
local firstRow = DmorphOctoModelListRow1
check(firstRow:IsVisible() and firstRow.text.text == "Thrall" and firstRow.info.text == "4527",
	"searching the list shows Thrall first")
press(firstRow)
check(vh.display == 4527 and firstRow.locked, "clicking a row morphs you, and the model you wear is highlighted")

-- Scrolling a long list, then back to the grid at the same place.
Mock.Type(modelSearch, "")
check(DmorphOctoModelList:IsShown(), "a long list shows its scroll bar")
Mock.RunScript(DmorphOctoModelListRow1, "OnMouseWheel", -1)
check(DmorphOctoModelList.offset == 3, "the mouse wheel over the rows scrolls the list")
check(DmorphOctoModelListRow1.text.text == creatures.names[4], "scrolled rows show later entries")
Mock.RunScript(DmorphOctoModelListRow1, "OnMouseWheel", -2)
Mock.Click(DmorphOctoModelView)
check(DmorphOctoModelGrid:IsVisible() and DmorphOctoTile1Model.displayInfo == catalog.ids[9],
	"the grid opens on the page the list was showing")

-- Races tab: portraits for your own face, < > for the game's NPC looks.
Mock.Click(DmorphOctoTabRaces)
check(not DmorphOctoModelGrid:IsVisible(), "switching tabs hides the models")
check(DmorphOctoTabRaces.label.color[2] == 0.82, "the open tab is lit")
press(DmorphOctoRace4Female)
check(vh.display == 56, "a portrait morphs into that race (Night Elf female)")
check(DmorphOctoRace4Female.ring.shown and not DmorphOctoRace4Male.ring.shown, "the race you wear is ringed")
check(DmorphOctoRace1Male.ring.shown == false, "other races aren't")
check(DmorphOctoCreatorValue1.text == "yours" and contains(DmorphOctoCreatorTitle.text, "your own face"),
	"with a portrait you keep your own face, skin and hair")
Mock.Tick(0.15)
check(DmorphOctoArt1.texture == "Interface\\DressUpFrame\\DressUpBackground-NightElf1", "the room follows the race")
press(Mock.FindButton("Swap gender"))
check(vh.display == 55, "swap gender works from the window")

local trollLooks = DmorphOcto.GetLooks(8, 0)
press(DmorphOctoRace8Male)
press(DmorphOctoCreatorNext3)
check(vh.display == trollLooks[1][1] and contains(DmorphOctoCreatorTitle.text, "NPC look 1 of"),
	"the first < > starts at the race's plainest NPC look")
local function lookOf(display)
	for i = 1, table.getn(trollLooks) do
		if trollLooks[i][1] == display then
			return trollLooks[i]
		end
	end
end
-- Each < > changes only its own row, or nothing (and says why).
local onlyThat, moved, stuck = true, 0, 0
for f = 1, 5 do
	for n = 1, 4 do
		local before = lookOf(vh.display)
		press(getglobal("DmorphOctoCreatorNext" .. f))
		local now = lookOf(vh.display)
		for g = 1, 5 do
			if g ~= f and now[g + 1] ~= before[g + 1] then
				onlyThat = false
			end
		end
		if now[f + 1] ~= before[f + 1] then
			moved = moved + 1
			if not contains(DmorphOctoFrameStatus.text, "nothing else") then
				onlyThat = false
			end
		elseif contains(DmorphOctoFrameStatus.text, "has another") then
			stuck = stuck + 1
		end
	end
end
check(onlyThat, "each < > click changes only the feature you clicked")
check(moved + stuck == 20, "every click either changes its feature or says no NPC has another")
local values = DmorphOcto.GetLookChoices(8, 0, 3, 1)
local strict = true
for k = 1, table.getn(trollLooks) do
	for f = 1, 5 do
		local to = DmorphOcto.StepLook(8, 0, f, k, 1)
		if to then
			for g = 1, 5 do
				if (g == f) == (trollLooks[to][g + 1] == trollLooks[k][g + 1]) then
					strict = false
				end
			end
		end
	end
end
check(strict and table.getn(values) >= 1, "StepLook only ever changes the one feature, for every Troll look")
check(contains(DmorphOctoCreatorValue3.text, " of "), "each row shows how many choices it has")
press(DmorphOctoCreatorRandom)
check(lookOf(vh.display) ~= nil, "the dice rolls a random look of that race")
press(DmorphOctoCreatorFavourite)
check(DmorphOcto.IsFavourite(vh.display), "the NPC look you wear can be starred")
press(DmorphOctoOwnLook)
check(vh.display == 1478, "My own look goes back to the race with your own face")

-- Items: click the head slot next to the model, search and pick.
press(DmorphOctoSlot1)
check(DmorphOctoSlot1.locked and DmorphOctoItemSlotLabel.text == "Head", "a slot opens its items")
local itemSearch = DmorphOctoItemSearch
Mock.Type(itemSearch, "first mate")
local itemRow = DmorphOctoItemListRow1
check(itemRow:IsVisible() and itemRow.text.text == "First Mate Hat", "the head list finds the hat")
check(DmorphOctoItemCount.text == "1 item", "one result says \"1 item\"")
press(itemRow)
check(vh.items[1] == 2955, "clicking an item morphs that slot")
Mock.Type(itemSearch, "")
press(DmorphOctoItemListRow3)
local locked = {}
for i = 1, 15 do
	if getglobal("DmorphOctoItemListRow" .. i).locked then
		table.insert(locked, i)
	end
end
check(table.getn(locked) == 1 and locked[1] == 3, "only the item you wear is highlighted")
Mock.Click(DmorphOctoItemFilter)
pickMenu("Epic")
local headItems = DmorphOcto.GetItemCatalog(1)
local allEpic = DmorphOctoItemListRow1:IsVisible()
for i = 1, 15 do
	local row = getglobal("DmorphOctoItemListRow" .. i)
	if row:IsVisible() and headItems.quality[headItems.byID[tonumber(row.info.text)]] ~= 4 then
		allEpic = false
	end
end
check(DmorphOctoItemFilter.text == "Epic" and allEpic, "the quality filter shows only epic items")
Mock.Click(DmorphOctoItemFilter)
pickMenu("New in OctoWoW")
check(DmorphOctoItemFilter.text == "Epic, new" and headItems.kind[headItems.byID[tonumber(DmorphOctoItemListRow1.info.text)]] == 2,
	"and the source filter on top: epic items OctoWoW added")
Mock.Click(DmorphOctoItemFilter)
pickMenu("Any quality")
Mock.Click(DmorphOctoItemFilter)
pickMenu("All items")
Mock.Click(DmorphOctoItemSlotButton)
pickMenu("Main hand")
check(DmorphOctoItemSlotLabel.text == "Main hand" and contains(DmorphOctoItemCount.text, "NPC weapons included"),
	"the slot menu jumps to any slot")
Mock.Click(DmorphOctoSlot1)
Mock.Type(itemSearch, "first mate")
press(itemRow)
check(DmorphOctoSlot1.icon.texture == "Interface\\Icons\\INV_Misc_Bandana_03" and DmorphOctoSlot1.glow.shown,
	"the slot shows the morphed item's icon")
Mock.RunScript(DmorphOctoSlot1, "OnEnter")
check(contains(table.concat(GameTooltip.lines, "\n"), "First Mate Hat"), "the slot tooltip names the item")
Mock.Click(Mock.FindButton(">"))
check(DmorphOctoItemSlotLabel.text == "Shoulder", "> moves to the next slot")
press(DmorphOctoSlot1, "RightButton")
check(vh.items[1] == nil, "right-clicking a slot puts your own gear back")
check(DmorphOctoSlot5.icon.texture == "Interface\\Icons\\INV_Chest_Plate01", "unmorphed slots show your gear")
Mock.Click(DmorphOctoSlot1)
Mock.Type(DmorphOctoItemID, "2955")
press(Mock.FindButton("Apply"))
check(vh.items[1] == 2955, "typing an item ID and pressing Apply works")

-- Sets: wear every piece at once.
Mock.Click(DmorphOctoTabSets)
Mock.Type(DmorphOctoSetSearch, "battlegear of wrath")
check(DmorphOctoSetListRow1:IsVisible() and DmorphOctoSetListRow1.text.text == "Battlegear of Wrath",
	"the sets tab finds a set")
Mock.RunScript(DmorphOctoSetListRow1, "OnEnter")
check(contains(table.concat(GameTooltip.lines, "\n"), "Breastplate of Wrath"), "hovering a set lists its pieces")
press(DmorphOctoSetListRow1)
check(vh.items[5] == 16966 and vh.items[1] == 16963 and contains(DmorphOctoFrameStatus.text, "Battlegear of Wrath"),
	"clicking a set wears its pieces")
Mock.Type(DmorphOctoSetSearch, "")
Mock.Click(DmorphOctoSetFilter)
pickMenu("New in OctoWoW")
check(DmorphOctoSetFilter.text == "New in OctoWoW" and DmorphOctoSetListRow1:IsVisible(), "OctoWoW's own sets can be listed")
Mock.Click(DmorphOctoSetFilter)
pickMenu("All sets")
DmorphOcto_ResetAll()
Mock.Tick(0.4)
say(".item 1 2955")

-- Wardrobe: save, reset, load, delete.
Mock.Click(DmorphOctoTabWardrobe)
say(".race 4")
check(DmorphOctoOutfitListRow1:IsVisible() == false, "the wardrobe starts empty")
Mock.Type(DmorphOctoOutfitName, "Elf Pirate")
Mock.Click(Mock.FindButton("Save current look"))
local outfit = DmorphOctoAccount.outfits["Elf Pirate"]
check(outfit and outfit.race == 4 and outfit.gender == 0 and outfit.items[1] == 2955,
	"saving stores the current look")
local outfitRow = DmorphOctoOutfitListRow1
check(outfitRow:IsVisible() and outfitRow.text.text == "Elf Pirate" and contains(outfitRow.info.text, "Night Elf male"),
	"the wardrobe lists the outfit with a summary")
press(Mock.FindButton("Reset everything"))
check(vh.display == 49 and vh.items[1] == nil, "reset everything from the window")
Mock.Click(outfitRow)
check(outfitRow.locked, "clicking an outfit selects it")
press(Mock.FindButton("Load"))
check(vh.display == 55 and vh.items[1] == 2955, "load puts the outfit back on")
DmorphOcto_ResetAll()
press(outfitRow)
check(vh.display == 55, "clicking the selected outfit again puts it on")

-- Resizing: drag the corner grip.
Mock.cursorX = 100
Mock.RunScript(DmorphOctoResize, "OnMouseDown")
Mock.cursorX = 100 + 846 * 0.25
Mock.Tick(0.1)
Mock.RunScript(DmorphOctoResize, "OnMouseUp")
check(DmorphOctoFrame.scale > 1.2 and DmorphOctoFrame.scale < 1.3 and DmorphOctoAccount.ui.scale == DmorphOctoFrame.scale,
	"dragging the grip makes the window bigger, and the size is remembered")
Mock.cursorX = 100
Mock.RunScript(DmorphOctoResize, "OnMouseDown")
Mock.cursorX = 100 - 846 * 5
Mock.Tick(0.1)
Mock.RunScript(DmorphOctoResize, "OnMouseUp")
check(DmorphOctoFrame.scale == 0.6, "it can't get smaller than 60%")

-- Survives /reload and a fresh login.
loadUI()
check(vh.display == 55 and vh.items[1] == 2955, "the look survives /reload")
slash("")
check(DmorphOctoModelGrid:IsVisible(), "the window opens in the view you left it in")
check(DmorphOctoFrame.scale == 0.6, "and at the size you left it")
check(DmorphOcto.IsFavourite(4527) and DmorphOcto.IsFavourite(4527, true), "favourites survive /reload")
Mock.Click(DmorphOctoTabWardrobe)
check(DmorphOctoOutfitListRow1:IsVisible() and DmorphOctoOutfitListRow1.text.text == "Elf Pirate",
	"saved outfits survive /reload")

-- Looking up OctoWoW items in the background, once the login has settled.
Mock.Tick(16)
Mock.Tick(0.3)
local asked = Mock.itemRequests[1]
check(asked ~= nil, "unknown OctoWoW items are asked about after login")
Mock.serverItems[asked] = { "Helm of Testing", 4, "INVTYPE_HEAD" }
Mock.Fire("ITEM_DATA_LOAD_RESULT", asked, 1)
Mock.Tick(0.3)
check(type(DmorphOctoAccount.itemInfo[asked]) == "string" and DmorphOcto.GetItemCatalog(1).byID[asked] ~= nil,
	"an answer puts the item in its slot's list, saved for next time")
local second = Mock.itemRequests[2]
Mock.Fire("ITEM_DATA_LOAD_RESULT", second, nil)
Mock.Tick(0.3)
check(DmorphOctoAccount.itemInfo[second] == false, "items the server doesn't have aren't asked about again")
local left = DmorphOcto.GetLookupStatus()
check(left > 0, "the lookup reports how many are left")

newClient(49)
loadUI()
check(vh.display == 55 and vh.items[1] == 2955, "the look comes back after logging in again")
check(DmorphOcto.GetItemCatalog(1).byID[asked] ~= nil, "looked-up items are still there after logging in")

slash("")
Mock.Click(DmorphOctoTabWardrobe)
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

-- Without ClassicAPI there are no previews: the models tab is a list, and the
-- grid is still chosen for when ClassicAPI is back.
Mock.classicAPI = nil
loadUI()
slash("")
check(DmorphOctoModelListRow1:IsVisible() and not DmorphOctoModelGrid:IsVisible() and not DmorphOctoModelView:IsVisible(),
	"without ClassicAPI the models tab is a list")
Mock.RunScript(DmorphOctoModelListRow1, "OnEnter")
check(not DmorphOctoPreviewCard:IsVisible(), "and rows have no preview card")
check(DmorphOctoAccount.ui.list == false, "the grid stays chosen for later")
DmorphOcto_ToggleUI()

------------------------------------------------------------------------------
-- Saved data from older versions or hand edits

newClient(49)
DmorphOctoDB = { display = "x", race = 42, gender = 7, items = { [2] = 5, [1] = -3, [5] = 10 } }
DmorphOctoAccount = { outfits = { good = { race = 2, items = { [1] = "2955" } }, [3] = {}, bad = "x" },
	favourites = { { id = "4527" }, { id = 4527 }, { id = 0 }, "x", { id = 5, mount = 1 } } }
loadUI()
check(DmorphOctoDB.display == nil and DmorphOctoDB.race == nil, "bad body values are dropped")
check(DmorphOctoDB.items[2] == nil and DmorphOctoDB.items[1] == nil and DmorphOctoDB.items[5] == 10,
	"only valid item morphs are kept")
check(vh.items[5] == 10 and vh.display == 49, "valid saved items are applied")
check(DmorphOctoAccount.outfits.good.items[1] == 2955 and DmorphOctoAccount.outfits[3] == nil
	and DmorphOctoAccount.outfits.bad == nil, "bad outfits are dropped, good ones cleaned up")
check(table.getn(DmorphOctoAccount.favourites) == 2 and DmorphOctoAccount.favourites[1].id == 4527
	and DmorphOctoAccount.favourites[2].mount == true, "favourites are cleaned up: numbers, once each")

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
-- Sharing: DMorph users see each other's morphs.

newClient(49)
DmorphOctoDB, DmorphOctoAccount = nil, nil
loadUI()
ChatFrame1.channelList[2] = "DmorphOcto" -- as if someone had /join'ed it
local function wait(seconds)
	for n = 1, math.ceil(seconds / 0.25) do
		Mock.Tick(0.25)
	end
end
local function channelSays(part)
	local found, count = nil, 0
	for i = 1, table.getn(Mock.channelSent) do
		if contains(Mock.channelSent[i].msg, part) then
			found, count = Mock.channelSent[i], count + 1
		end
	end
	return found, count
end
-- A message on the DMorph channel, with 1.12's CHAT_MSG_CHANNEL arguments.
local function hear(sender, text)
	Mock.Fire("CHAT_MSG_CHANNEL", "DMO1 " .. text, sender, "", "6. DmorphOcto", "", "", 0, 6, "DmorphOcto")
end
local function morphOf(guid)
	return vh.others[guid] or { items = {} }
end

wait(4)
check(Mock.channels.dmorphocto == nil, "the channel is joined once the login has settled")
wait(22)
check(Mock.channels.dmorphocto == 6, "DMorph joins its own channel")
check(ChatFrame1.channelList[2] == nil and ChatFrame1.channelList[1] == "General",
	"and keeps it out of the chat windows")
check(channelSays("DMO1 L 0 0 - -"), "after login it says it has DMorph and no morph")
Mock.channelSent = {}
say(".morph 4527")
say(".item head 2955")
wait(3)
local sent, count = channelSays("DMO1 L 4527 0 1:2955 -")
check(sent and sent.channel == 6 and count == 1 and table.getn(Mock.channelSent) == 1,
	"your changes go to the channel a moment later, in one message")
check(table.getn(Mock.sent) == 0, "nothing is said in any chat you can see")

-- Someone else's morph shows on them once you have a unit token for them.
local ally = "0x00000000000A0001"
Mock.units.target = { name = "Ally", guid = ally, friendly = true, display = 50 }
hear("Ally", "L 4527 0 1:2955,5:10 " .. ally)
check(morphOf(ally).display == 4527 and morphOf(ally).items[1] == 2955 and morphOf(ally).items[5] == 10,
	"a DMorph user you target shows their morph and items")
hear("Ally", "L 99999999 0 - " .. ally)
wait(1.5)
check(morphOf(ally).display == nil and morphOf(ally).items[1] == nil,
	"a display ID the client doesn't have is ignored, and dropped items come off")
hear("Ally", "L 4527 4527 - " .. ally)
wait(1.5)
check(morphOf(ally).display == 4527 and morphOf(ally).mount == nil,
	"a mount skin isn't put on through the target (it couldn't come off when they dismount)")
Mock.units.mouseover = { name = "Foe", guid = "0x00000000000B0001", friendly = false, display = 50 }
hear("Foe", "L 4527 0 - -")
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
check(vh.others["0x00000000000B0001"] == nil, "hostile players aren't morphed, and nothing errors")
Mock.units.mouseover = nil

-- In a group, party tokens stay put, so mount skins come and go with them.
local pal = "0x00000000000C0001"
Mock.party = 1
Mock.units.party1 = { name = "Pal", guid = pal, friendly = true, display = 51 }
Mock.Fire("CHAT_MSG_ADDON", "DMO1", "L 0 4527 - -", "PARTY", "Pal")
check(morphOf(pal).mount == 4527 and morphOf(pal).display == nil, "a party member's mount skin shows while they ride")
Mock.Fire("CHAT_MSG_ADDON", "DMO1", "L 0 0 - -", "PARTY", "Pal")
check(morphOf(pal).mount == nil, "and comes off when they dismount")
Mock.addonSent = {}
Mock.Fire("PARTY_MEMBERS_CHANGED")
wait(4)
local last = Mock.addonSent[table.getn(Mock.addonSent)]
check(last and last.prefix == "DMO1" and last.distribution == "PARTY" and contains(last.text, "L 4527 0 1:2955"),
	"joining a group sends your look to it")

-- New faces are asked about, a few at a time, and not again for a while.
Mock.channelSent = {}
Mock.units.mouseover = { name = "Stranger", guid = "0x00000000000D0001", friendly = true, display = 52 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(11)
check(channelSays("DMO1 Q Stranger"), "a friendly player you don't know is asked about")
Mock.channelSent = {}
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(11)
check(table.getn(Mock.channelSent) == 0, "and not asked about again soon")
hear("Someone", "Q Bob,Tester")
hear("Other", "Q Tester")
wait(4)
sent, count = channelSays("DMO1 L 4527 0 1:2955")
check(sent and count == 1, "a question about you is answered once")

-- SuperWoW: GUIDs work as unit tokens, so players need no target or mouseover.
Mock.superWoW, Mock.playerGUID = true, "0x0000000000000042"
local far = "0x00000000000E0001"
Mock.units.nearby = { name = "Far", guid = far, friendly = true, display = 53 }
hear("Far", "L 4527 4527 - " .. far)
check(morphOf(far).display == 4527 and morphOf(far).mount == 4527, "with SuperWoW a player's GUID is enough")
Mock.channelSent = {}
say(".item head 0")
wait(3)
check(channelSays("DMO1 L 4527 0 - 0x0000000000000042"), "and your messages carry your GUID")
Mock.superWoW = nil

-- Switching it off.
Mock.channelSent = {}
slash("share off")
wait(2)
check(DmorphOctoAccount.shareOff == true and channelSays("DMO1 L 0 0 -"),
	".share off tells the others to take your morph off")
Mock.channelSent = {}
hear("Someone", "Q Tester")
wait(8)
check(table.getn(Mock.channelSent) == 0, "and questions about you go unanswered")
slash("share others off")
wait(1.5)
check(morphOf(ally).display == nil, ".share others off takes their morphs off as you see them")
slash("share")
check(contains(allChat(), "Others see your morph: off") and contains(allChat(), "DMorph users seen: 4"),
	".share shows the settings and how many DMorph users you've seen")
slash("")
Mock.Click(DmorphOctoShare)
pickMenu("Others see my morph")
check(DmorphOctoAccount.shareOff == nil, "the window's Sharing menu switches it back on")
Mock.Click(DmorphOctoShare)
pickMenu("I see their morphs")
wait(1.5)
check(DmorphOctoAccount.othersOff == nil and morphOf(ally).display == 4527, "and their morphs come back")
DmorphOcto_ToggleUI()
Mock.party = 0

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
