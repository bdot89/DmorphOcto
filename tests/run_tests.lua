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
check(table.getn(Mock.sent) == 0 and contains(lastChat(), "your size"),
	".scale is answered locally and never sent as /say (without DmorphHelper it says it's needed)")

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
-- Dungeon bosses the database ranks as plain elites, and every mount spell's model.
result, count = DmorphOcto.FilterCatalog(creatures, "edwin vancleef", filterNamed("Bosses"))
local vancleef = count >= 1 and creatures.ids[result[1]] == 2029
result, count = DmorphOcto.FilterCatalog(creatures, "baron rivendare", filterNamed("Bosses"))
check(vancleef and count >= 1, "dungeon bosses are in the Bosses filter")
result, count = DmorphOcto.FilterCatalog(creatures, "hogger", filterNamed("Bosses"))
check(count == 0, "a named elite out in the world isn't a boss")
check(contains(creatures.tags[creatures.byID[2402]] or "", "mount"), "the Black Stallion's model is a mount")
check(bosses > 500, "bosses come from both the 1.12 database and OctoWoW's ranks")
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
-- Clicks the line of the open drop-down menu with that text (or, with
-- prefix set, the first line starting with it).
local function pickMenu(text, prefix)
	for i = 1, 20 do
		local row = getglobal("DmorphOctoMenuRow" .. i)
		if row:IsVisible() and (row.label.text == text or (prefix and strsub(row.label.text, 1, strlen(text)) == text)) then
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
-- Zoom: the mouse wheel over your character, or the + and - buttons, bring
-- it closer (and a little lower, towards the face); right-drag moves it; the
-- zoom stays when the preview reloads.
Mock.Tick(0.5)
front = previews()
local function at(model)
	return model.position or { 0, 0, 0 }
end
Mock.RunScript(DmorphOctoModelDrag, "OnMouseWheel", 1)
Mock.RunScript(DmorphOctoModelDrag, "OnMouseWheel", 1)
check(math.abs(at(front)[1] - 0.6) < 0.001 and at(front)[3] < 0, "two notches of the mouse wheel zoom in")
Mock.Click(DmorphOctoZoomIn)
check(math.abs(at(front)[1] - 0.9) < 0.001, "so does the + button")
Mock.Click(DmorphOctoZoomOut)
check(math.abs(at(front)[1] - 0.6) < 0.001, "and - zooms out")
for i = 1, 30 do
	Mock.Click(DmorphOctoZoomIn)
end
check(at(front)[1] <= 3, "zoom stops before the camera goes inside your character")
Mock.cursorX, Mock.cursorY = 100, 100
Mock.RunScript(DmorphOctoModelDrag, "OnMouseDown", "RightButton")
Mock.cursorX, Mock.cursorY = 140, 80
Mock.Tick(0.05)
Mock.RunScript(DmorphOctoModelDrag, "OnMouseUp", "RightButton")
local zoomed = at(front)
check(zoomed[2] > 0 and zoomed[1] <= 3, "right-dragging moves your character sideways")
local rotation = front.rotation
Mock.cursorX = 160
Mock.RunScript(DmorphOctoModelDrag, "OnMouseDown", "LeftButton")
Mock.cursorX = 200
Mock.Tick(0.05)
Mock.RunScript(DmorphOctoModelDrag, "OnMouseUp", "LeftButton")
check(front.rotation ~= rotation and at(front)[2] == zoomed[2], "dragging still turns it, without moving it")
say(".morph 4527")
Mock.Tick(0.15)
local _, loading = previews()
check(at(loading)[1] == zoomed[1] and at(loading)[2] == zoomed[2], "the new look loads already zoomed")
Mock.Tick(0.5)
local reloaded = previews()
check(reloaded ~= front and at(reloaded)[1] == zoomed[1] and at(reloaded)[2] == zoomed[2],
	"the zoom stays when the preview loads a new look")
Mock.Click(DmorphOctoZoomReset)
check(at(reloaded)[1] == 0 and at(reloaded)[2] == 0 and at(reloaded)[3] == 0, "Reset view shows the whole character again")
Mock.cursorX, Mock.cursorY = nil, nil
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
-- A flight path's bird keeps its own look, and nothing is stuck after landing.
local fortitude = "Interface\\Icons\\Spell_Holy_WordFortitude" -- a long buff
Mock.buffs = { fortitude }
Mock.Tick(0.15)
vh.serverMount, Mock.onTaxi = 1149, true -- flying: the mount field holds the bird
Mock.Fire("PLAYER_CONTROL_LOST")
Mock.Tick(0.3)
check(vh.mount == nil, "a flight path's bird doesn't get your mount skin")
vh.serverMount, Mock.onTaxi = 0, nil
Mock.Fire("PLAYER_CONTROL_GAINED")
Mock.Tick(0.3)
check(vh.mount == nil and UnitDisplayInfo("player") == vh.display, "and nothing is left on after landing")
vh.serverMount = 10671
Mock.Tick(0.3)
check(vh.mount == nil, "a mount with no new buff gets no skin (nothing would show when you dismount)")
Mock.buffs = { fortitude, "Interface\\Icons\\Ability_Mount_Undeadhorse" }
Mock.Tick(0.15)
check(vh.mount == skin, "once the mount's buff shows, the skin goes on")
Mock.Fire("PLAYER_CONTROL_GAINED") -- a stun ends while riding
check(vh.mount == nil, "getting control back takes it off")
Mock.Tick(0.15)
check(vh.mount == skin, "and it's back a tick later while you still ride")
vh.serverMount, Mock.buffs = 0, {}
Mock.Tick(0.15)
check(vh.mount == nil, "dismounting takes it off again")
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
-- Each < > always moves its own row to the next value the race's NPCs have;
-- other rows change only when no NPC has that value with them, and the
-- status line names them.
local FIELDS = { 2, 3, 4, 5, 6, 8 }
local NAMES = { "skin colour", "face", "hair style", "hair colour", "facial hair", "outfit" }
local function nextValue(f, value)
	local values = DmorphOcto.GetLookValues(8, 0, f)
	for i = 1, table.getn(values) do
		if values[i] == value then
			return values[math.mod(i, table.getn(values)) + 1]
		end
	end
end
local alwaysMoves, namesChanges, quietWhenAlone, clicks = true, true, true, 0
for f = 1, 6 do
	for n = 1, 4 do
		local before = lookOf(vh.display)
		press(getglobal("DmorphOctoCreatorNext" .. f))
		local now = lookOf(vh.display)
		clicks = clicks + 1
		if now[FIELDS[f]] ~= nextValue(f, before[FIELDS[f]]) then
			alwaysMoves = false
		end
		local others = 0
		for g = 1, 6 do
			-- A new face or hair nearly always comes in other clothes, so only
			-- the face and hair rows are named (all of them for the outfit row).
			if g ~= f and now[FIELDS[g]] ~= before[FIELDS[g]] and (f == 6 or g ~= 6) then
				others = others + 1
				if not contains(DmorphOctoFrameStatus.text, NAMES[g]) then
					namesChanges = false
				end
			end
		end
		if others == 0 and contains(DmorphOctoFrameStatus.text, "changed too") then
			quietWhenAlone = false
		end
	end
end
check(alwaysMoves and clicks == 24, "every > click moves its own row to the next value")
check(namesChanges, "when another row has to change, the status line names it")
check(quietWhenAlone, "a click that changes only its row doesn't say anything else changed")
-- StepLook keeps as much as any NPC look allows: no other look with the new
-- value keeps a row it dropped without dropping a more important one.
local WEIGHTS = { 32, 4, 16, 8, 2, 1 }
local function kept(a, b, f)
	local score = 0
	for g = 1, 6 do
		if g ~= f and a[FIELDS[g]] == b[FIELDS[g]] then
			score = score + WEIGHTS[g]
		end
	end
	return score
end
local closest, stepsOK = true, true
for k = 1, table.getn(trollLooks) do
	for f = 1, 6 do
		local to, pos, count, changed = DmorphOcto.StepLook(8, 0, f, k, 1)
		if to then
			local want = nextValue(f, trollLooks[k][FIELDS[f]])
			if trollLooks[to][FIELDS[f]] ~= want or pos < 1 or pos > count then
				stepsOK = false
			end
			local best = kept(trollLooks[to], trollLooks[k], f)
			for j = 1, table.getn(trollLooks) do
				if trollLooks[j][FIELDS[f]] == want and kept(trollLooks[j], trollLooks[k], f) > best then
					closest = false
				end
			end
			for i = 1, table.getn(changed) do
				local g = changed[i]
				if trollLooks[to][FIELDS[g]] == trollLooks[k][FIELDS[g]] then
					stepsOK = false
				end
			end
		end
	end
end
check(stepsOK, "StepLook moves to the next value and reports exactly the rows that changed, for every Troll look")
check(closest, "StepLook picks the look that keeps the most important other rows")
local values = DmorphOcto.GetLookChoices(8, 0, 3, 1)
check(table.getn(values) == table.getn(DmorphOcto.GetLookValues(8, 0, 3)), "every hair style is a choice")
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
-- Hovering an item: your character wearing it, nothing put on.
local itemsBefore = vh.calls
Mock.RunScript(itemRow, "OnEnter")
check(DmorphOctoItemCard:IsVisible() and DmorphOctoItemCardModel.unit == "player"
	and DmorphOctoItemCardModel.tried[1] == 2955 and DmorphOctoItemCardTitle.text == "First Mate Hat",
	"hovering an item shows your character wearing it")
check(vh.calls == itemsBefore and vh.items[1] == nil, "without putting it on")
Mock.RunScript(itemRow, "OnLeave")
check(not DmorphOctoItemCard:IsVisible(), "the preview goes when the mouse leaves")
press(itemRow)
check(vh.items[1] == 2955, "clicking an item morphs that slot")
Mock.Type(itemSearch, "")
press(DmorphOctoItemListRow3)
local locked = {}
for i = 1, 14 do
	if getglobal("DmorphOctoItemListRow" .. i).locked then
		table.insert(locked, i)
	end
end
check(table.getn(locked) == 1 and locked[1] == 3, "only the item you wear is highlighted")
Mock.Click(DmorphOctoItemQuality)
pickMenu("Epic")
local headItems = DmorphOcto.GetItemCatalog(1)
-- Every row shown passes a test (on the catalogue entry), and some are shown.
local function allRows(test)
	local any = false
	for i = 1, 14 do
		local row = getglobal("DmorphOctoItemListRow" .. i)
		if row:IsVisible() then
			any = true
			if not test(headItems.byID[tonumber(row.info.text)]) then
				return false
			end
		end
	end
	return any
end
check(DmorphOctoItemQuality.text == "Epic" and allRows(function(i) return headItems.quality[i] == 4 end),
	"the quality filter shows only epic items")
Mock.Click(DmorphOctoItemSource)
pickMenu("New in OctoWoW")
check(DmorphOctoItemSource.text == "New in OctoWoW" and DmorphOctoItemQuality.text == "Epic"
	and allRows(function(i) return headItems.kind[i] == 2 and headItems.quality[i] == 4 end),
	"and the source filter on top: epic items OctoWoW added")
Mock.Click(DmorphOctoItemSource)
pickMenu("All items")
-- The type filter lists the slot's kinds with counts: epic cloth helmets.
Mock.Click(DmorphOctoItemType)
local typeMenu = {}
for i = 1, 20 do
	local row = getglobal("DmorphOctoMenuRow" .. i)
	if row:IsVisible() then
		table.insert(typeMenu, row.label.text)
	end
end
check(typeMenu[1] == "Any type" and strfind(typeMenu[2] or "", "^Cloth %(%d") and strfind(typeMenu[5] or "", "^Plate %("),
	"the type menu lists the head slot's armour types with counts")
pickMenu(typeMenu[2])
check(DmorphOctoItemType.text == "Cloth" and allRows(function(i) return headItems.types[i] == 401 and headItems.quality[i] == 4 end),
	"Cloth and Epic together: only epic cloth helmets")
check(DmorphOcto.GetItemType(16963) == 404 and DmorphOcto.GetItemType(2955) == 401, "items know their armour type")
Mock.Click(DmorphOctoItemQuality)
pickMenu("Any quality")
Mock.Click(DmorphOctoTabSets)
Mock.Click(DmorphOctoTabItems)
check(DmorphOctoItemType.text == "Cloth", "the slot keeps its type")
Mock.Click(Mock.FindButton(">"))
check(DmorphOctoItemType.text == "Any type", "each slot has its own type")
Mock.Click(Mock.FindButton("<"))
Mock.Click(DmorphOctoItemType)
pickMenu("Any type")
local testItems = 0
for slot, list in pairs({ DmorphOcto.GetItemCatalog(1), DmorphOcto.GetItemCatalog(16) }) do
	for i = 1, list.count do
		if strfind(list.lower[i], "test") and not strfind(list.lower[i], "%atest") and not strfind(list.lower[i], "test%a") then
			testItems = testItems + 1
		end
	end
end
check(testItems == 0, "developer test items aren't listed")
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
check(DmorphOctoItemCard:IsVisible() and DmorphOctoItemCardStatus.text == "Loading from the server..."
	and contains(" " .. table.concat(Mock.itemRequests, " ") .. " ", " 16966 "),
	"and shows you wearing it: pieces the game hasn't seen yet are asked for")
Mock.serverItems[16966] = { "Breastplate of Wrath", 4, "INVTYPE_CHEST" }
Mock.Tick(0.3)
local triedWrath = false
for _, id in ipairs(DmorphOctoItemCardModel.tried) do
	if id == 16966 then
		triedWrath = true
	end
end
check(triedWrath, "and put on once they arrive")
Mock.RunScript(DmorphOctoSetListRow1, "OnLeave")
Mock.serverItems[16966] = nil
press(DmorphOctoSetListRow1)
check(vh.items[5] == 16966 and vh.items[1] == 16963 and contains(DmorphOctoFrameStatus.text, "Battlegear of Wrath"),
	"clicking a set wears its pieces")
Mock.Type(DmorphOctoSetSearch, "")
Mock.Click(DmorphOctoSetSource)
pickMenu("New in OctoWoW")
check(DmorphOctoSetSource.text == "New in OctoWoW" and DmorphOctoSetListRow1:IsVisible(), "OctoWoW's own sets can be listed")
Mock.Click(DmorphOctoSetSource)
pickMenu("All sets")
Mock.Click(DmorphOctoSetType)
pickMenu("Plate (", true)
local setCatalog = DmorphOcto.GetSetCatalog()
Mock.Type(DmorphOctoSetSearch, "battlegear of wrath")
check(DmorphOctoSetType.text == "Plate" and DmorphOctoSetListRow1.text.text == "Battlegear of Wrath",
	"the set type filter finds plate sets")
Mock.Type(DmorphOctoSetSearch, "vestments of transcendence")
check(not DmorphOctoSetListRow1:IsVisible(), "and leaves out the cloth ones")
Mock.Type(DmorphOctoSetSearch, "")
Mock.Click(DmorphOctoSetType)
pickMenu("Any type")
-- A set's type is the armour most of its pieces are made of (a cloth cloak
-- doesn't make a plate set cloth).
local majority, mixed = true, 0
for i = 1, setCatalog.count do
	local counts, best = {}, nil
	for k = 1, table.getn(setCatalog.pieces[i]) do
		local kind = DmorphOcto.GetItemType(setCatalog.pieces[i][k])
		if kind and kind >= 401 and kind <= 404 then
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	local n = 0
	for kind, c in pairs(counts) do
		n = n + 1
		if not best or c > counts[best] then
			best = kind
		end
	end
	if n > 1 then
		mixed = mixed + 1
	end
	if setCatalog.types[i] and counts[setCatalog.types[i]] ~= counts[best] then
		majority = false
	end
end
check(majority and mixed > 0, "a set's type is its most common armour, also in sets of mixed armour")
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
-- Sharing: DMorph users see each other's morphs, with as few messages as
-- possible and none in any chat window.

newClient(49)
DmorphOctoDB, DmorphOctoAccount = nil, nil
Mock.channels.dmorphocto = 5 -- 1.7's channel, joined last session
loadUI()
ChatFrame1.channelList[2] = "DmorphShare" -- as if someone had /join'ed it
local function wait(seconds)
	for n = 1, math.ceil(seconds / 0.25) do
		Mock.Tick(0.25)
	end
end
local function said(list, part, distribution)
	local found, count = nil, 0
	for i = 1, table.getn(list) do
		local m = list[i]
		if contains(m.msg or m.text, part) and (not distribution or m.distribution == distribution) then
			found, count = m, count + 1
		end
	end
	return found, count
end
local function channelSays(part)
	return said(Mock.channelSent, part)
end
local function addonSays(part, distribution)
	return said(Mock.addonSent, part, distribution)
end
local function quiet()
	Mock.channelSent, Mock.addonSent = {}, {}
end
-- A message on the DMorph channel, with 1.12's CHAT_MSG_CHANNEL arguments.
local function hear(sender, text)
	Mock.Fire("CHAT_MSG_CHANNEL", "DMO2 " .. text, sender, "", "6. DmorphShare", "", "", 0, 6, "DmorphShare")
end
local function hearAddon(sender, text, distribution)
	Mock.Fire("CHAT_MSG_ADDON", "DMO2", text, distribution, sender)
end
local function morphOf(guid)
	return vh.others[guid] or { items = {} }
end
-- The same fingerprint Share.lua puts on a look.
local function fingerprint(look)
	local h, digits, text = 5381, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ", ""
	for i = 1, string.len(look) do
		h = math.mod(h * 33 + string.byte(look, i), 1679609)
	end
	while h > 0 do
		text = string.sub(digits, math.mod(h, 36) + 1, math.mod(h, 36) + 1) .. text
		h = math.floor(h / 36)
	end
	return text == "" and "0" or text
end
-- 4527 is "3HR" in base 36, 2955 "2A3", 10 "A"; slot 1 is "a", slot 5 "e".

wait(2)
check(Mock.channels.dmorphshare == nil, "the channel is joined once the login has settled")
wait(10)
check(Mock.channels.dmorphshare == 6 and Mock.channels.dmorphocto == nil,
	"DMorph joins its own channel and leaves 1.7's")
check(ChatFrame1.channelList[2] == nil and ChatFrame1.channelList[1] == "General",
	"and keeps it out of the chat windows")
check(table.getn(Mock.channelSent) == 0 and table.getn(Mock.addonSent) == 0,
	"logging in alone sends nothing: anyone who sees you asks")

-- Nothing of the channel reaches a chat window, whatever it listens to.
Mock.shown = {}
arg1, arg4, arg9 = "DMO2 L 0 0 - -", "6. DmorphShare", "DmorphShare"
ChatFrame_OnEvent("CHAT_MSG_CHANNEL")
arg1 = "YOU_JOINED"
ChatFrame_OnEvent("CHAT_MSG_CHANNEL_NOTICE")
arg1, arg4, arg9 = "hello", "1. General", "General"
ChatFrame_OnEvent("CHAT_MSG_CHANNEL")
arg1, arg4, arg9 = nil, nil, nil
check(table.getn(Mock.shown) == 1 and Mock.shown[1].msg == "hello",
	"the channel's messages and notices are hidden, other channels still show")

say(".morph 4527")
say(".item head 2955")
wait(3)
check(table.getn(Mock.channelSent) == 0 and table.getn(Mock.sent) == 0,
	"with no DMorph users around, your changes go nowhere")

-- Someone else's morph shows on them once you have a unit token for them.
local ally = "0x00000000000A0001"
Mock.units.target = { name = "Ally", guid = ally, friendly = true, display = 50 }
hear("Ally", "L 3HR 0 a2A3eA " .. ally)
check(morphOf(ally).display == 4527 and morphOf(ally).items[1] == 2955 and morphOf(ally).items[5] == 10,
	"a DMorph user you target shows their morph and items")
hear("Ally", "L ZZZZZ 0 - " .. ally)
wait(1.5)
check(morphOf(ally).display == nil and morphOf(ally).items[1] == nil,
	"a display ID the client doesn't have is ignored, and dropped items come off")
hear("Ally", "L 3HR 3HR - " .. ally)
wait(1.5)
check(morphOf(ally).display == 4527 and morphOf(ally).mount == nil,
	"a mount skin isn't put on through the target (it couldn't come off when they dismount)")
hear("Ally", "L 4527 0 1:2955 -")
wait(0.5)
check(morphOf(ally).display == 4527, "messages that don't read as a look are ignored")
Mock.units.mouseover = { name = "Foe", guid = "0x00000000000B0001", friendly = false, display = 50 }
hear("Foe", "L 3HR 0 - -")
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
check(vh.others["0x00000000000B0001"] == nil, "hostile players aren't morphed, and nothing errors")
Mock.units.mouseover = nil

-- Ally is around with DMorph, so your changes now go out: once they stand
-- still, in one message.
quiet()
say(".item head 0")
wait(0.5)
say(".item head 2955")
say(".item chest 10")
wait(0.75)
check(table.getn(Mock.channelSent) == 0, "changes wait until they stand still")
wait(1)
local sent, count = channelSays("DMO2 L 3HR 0 a2A3eA -")
check(sent and sent.channel == 6 and count == 1 and table.getn(Mock.channelSent) == 1,
	"then go to the channel in one short message")
check(table.getn(Mock.sent) == 0, "nothing is said in any chat you can see")
quiet()
for n = 1, 8 do
	say(".item chest " .. (10 + n))
	wait(0.5)
end
wait(1.5)
check(table.getn(Mock.channelSent) == 2, "changing gear nonstop still sends at most every few seconds")
say(".item chest 10")
wait(2)

-- In a group, party tokens stay put, so mount skins come and go with them.
local pal = "0x00000000000C0001"
Mock.party = 1
Mock.units.party1 = { name = "Pal", guid = pal, friendly = true, display = 51 }
hearAddon("Pal", "L 0 3HR - -", "PARTY")
check(morphOf(pal).mount == 4527 and morphOf(pal).display == nil, "a party member's mount skin shows while they ride")
hearAddon("Pal", "M 0", "PARTY")
check(morphOf(pal).mount == nil, "and comes off when they dismount, from a tiny message")
hearAddon("Pal", "M 3HR", "PARTY")
check(morphOf(pal).mount == 4527, "and goes on again")
hearAddon("Pal", "M 0", "PARTY")
quiet()
Mock.Fire("PARTY_MEMBERS_CHANGED")
wait(2)
check(addonSays("L 3HR 0 a2A3eA", "PARTY") and table.getn(Mock.channelSent) == 0,
	"joining a group sends your look to it, hidden, and not to the channel")

-- With only your group around, changes are hidden addon messages.
Mock.units.target = nil
wait(181)
quiet()
say(".item chest 0")
wait(2)
check(addonSays("L 3HR 0 a2A3", "PARTY") and table.getn(Mock.channelSent) == 0,
	"with only group members around, changes go to the group alone")

-- Guild mates around you hear through the guild, not the channel.
Mock.guild = { "Tester", "Guildie" }
wait(125)
check(Mock.rosterRequests > 0, "the guild list is asked for")
Mock.Fire("GUILD_ROSTER_UPDATE")
local guildie = "0x00000000000F0001"
Mock.units.mouseover = { name = "Guildie", guid = guildie, friendly = true, display = 54 }
hearAddon("Guildie", "L 3HR 0 - -", "GUILD")
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
check(morphOf(guildie).display == 4527, "a guild mate's morph comes through the guild")
quiet()
say(".item chest 10")
wait(2)
check(addonSays("L 3HR 0 a2A3eA", "GUILD") and addonSays("L 3HR 0 a2A3eA", "PARTY")
	and table.getn(Mock.channelSent) == 0, "and they hear your changes through the guild")
Mock.units.mouseover = nil

-- New faces are asked about, a few at a time, and not again for a while.
quiet()
Mock.units.mouseover = { name = "Stranger", guid = "0x00000000000D0001", friendly = true, display = 52 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(4)
check(channelSays("DMO2 Q Stranger"), "a friendly player you don't know is asked about")
quiet()
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(4)
check(table.getn(Mock.channelSent) == 0, "and not asked about again soon")
Mock.units.mouseover = { name = "Newbie", guid = "0x00000000000D0002", friendly = true, display = 52 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
hear("Someone", "Q Newbie")
wait(4)
check(table.getn(Mock.channelSent) == 0, "nor when someone else just asked the same on the channel")
Mock.units.mouseover = nil

-- Only players near you are asked.
quiet()
Mock.units.mouseover = { name = "Faraway", guid = "0x00000000000D0003", friendly = true, display = 52, distant = true }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(12)
check(table.getn(Mock.channelSent) == 0, "a player you can see but who is out of range isn't asked")
Mock.units.mouseover = nil
Mock.units.targettarget = { name = "Bystander", guid = "0x00000000000D0004", friendly = true, display = 52 }
wait(12)
check(table.getn(Mock.channelSent) == 0, "nor is whoever your target is targeting")
Mock.units.targettarget = nil
check(DmorphOctoAccount.noDmorph.OctoWoW.Stranger and DmorphOctoAccount.noDmorph.OctoWoW.Newbie,
	"players who didn't answer are remembered as having no DMorph")

-- Questions about you: the whole look, or just its fingerprint if the asker
-- already has it. One answer covers everyone who asked.
local look = "3HR 0 a2A3eA"
quiet()
hear("Someone", "Q Bob,Tester")
hear("Other", "Q Tester:" .. fingerprint(look))
wait(4)
sent, count = channelSays("DMO2 L " .. look)
check(sent and count == 1 and table.getn(Mock.channelSent) == 1, "a question about you is answered once")
quiet()
hear("Other", "Q Tester:" .. fingerprint(look))
wait(4)
check(channelSays("DMO2 H " .. fingerprint(look)) and table.getn(Mock.channelSent) == 1,
	"an asker with your current look gets only its fingerprint")
quiet()
hearAddon("Pal", "Q Tester:" .. fingerprint(look), "PARTY")
wait(4)
check(addonSays("H " .. fingerprint(look), "PARTY") and table.getn(Mock.channelSent) == 0,
	"a question from the group is answered in the group")

-- A player who leaves your sight is built afresh without their look when
-- they come back: it goes straight back on.
hearAddon("Pal", "L 3HR 0 a2A3 -", "PARTY")
check(morphOf(pal).display == 4527, "a party member's model shows")
Mock.units.party1.far = true
wait(0.5)
vh.others[pal] = nil -- the game drops their model while they're away
Mock.units.party1.far = nil
wait(0.3)
check(morphOf(pal).display == 4527 and morphOf(pal).items[1] == 2955,
	"back in sight, their look is on again within a fifth of a second")

-- Your mount skin goes out the moment it goes on, and when it comes off.
say(".mount 4527")
wait(2)
quiet()
vh.serverMount = 10671
Mock.buffs = { "Interface\\Icons\\Ability_Mount_Undeadhorse" }
wait(0.3)
check(channelSays("DMO2 M 3HR"), "mounting sends your mount skin at once, in a tiny message (players who asked about you hear it)")
quiet()
vh.serverMount = 0
Mock.buffs = {}
wait(0.3)
check(channelSays("DMO2 M 0"), "and dismounting sends that it's off")
say(".mount 0")

-- SuperWoW: GUIDs work as unit tokens, so players need no target or mouseover.
Mock.superWoW, Mock.playerGUID = true, "0x0000000000000042"
local far = "0x00000000000E0001"
Mock.units.nearby = { name = "Far", guid = far, friendly = true, display = 53 }
hear("Far", "L 3HR 3HR - " .. far)
check(morphOf(far).display == 4527 and morphOf(far).mount == 4527, "with SuperWoW a player's GUID is enough")
quiet()
say(".item head 0")
wait(3)
check(channelSays("DMO2 L 3HR 0 eA 0x0000000000000042"), "and your messages carry your GUID")
Mock.superWoW = nil

-- Your changes only reach DMorph users in range.
Mock.units.nearby = nil
Mock.units.target = { name = "Ally", guid = ally, friendly = true, display = 50, distant = true }
Mock.Fire("PLAYER_TARGET_CHANGED")
wait(61)
quiet()
say(".item head 2955")
wait(3)
check(not channelSays("DMO2 L") and morphOf(ally).display == 4527,
	"a DMorph user in sight but out of range still shows their look, but doesn't get your changes")
Mock.units.target.distant = nil
wait(0.5)
quiet()
say(".item head 0")
wait(3)
check(channelSays("DMO2 L 3HR 0 eA"), "once they come into range, your changes reach them")

-- Sizes are shared too (put on with DmorphHelper).
local sized = {}
function DmorphHelper_SetScale(unit, scale)
	local u = Mock.Unit(unit)
	if not u then
		error("Unit not found.")
	end
	sized[u.guid] = scale
end
function DmorphHelper_GetScale(unit)
	return 1
end
hear("Ally", "L 3HR 0 - " .. ally .. " s150")
check(sized[ally] == 1.5 and morphOf(ally).display == 4527, "a DMorph user's size shows on them")
hear("Ally", "S 50")
check(sized[ally] == 0.5, "a size message changes only the size")
hear("Ally", "S 100")
check(sized[ally] == 1, "and their own size goes back when they reset it")
hear("Ally", "L 3HR 0 - " .. ally)
check(sized[ally] == 1, "a look without a size (or from DMorph before 2.6) means normal size")
quiet()
DmorphOctoDB.scale = 2
say(".item head 0") -- any change tells the sharing code
wait(3)
check(channelSays("DMO2 S 200"), "your size goes out to DMorph users around you")
quiet()
hear("Someone", "Q Tester")
wait(4)
check(channelSays(" s200"), "and with your look when someone asks")
DmorphOctoDB.scale = nil
say(".item head 0")
wait(3)
hear("Ally", "L 3HR 3HR - " .. ally) -- Ally's look as the tests below remember it
DmorphHelper_SetScale, DmorphHelper_GetScale = nil, nil
Mock.units.target = nil

-- Looks are remembered: after a /reload a known player shows at once, and is
-- only asked whether they changed.
loadUI()
quiet()
Mock.units.target = { name = "Ally", guid = ally, friendly = true, display = 50 }
Mock.Fire("PLAYER_TARGET_CHANGED")
check(morphOf(ally).display == 4527, "a remembered player's look goes on at once")
wait(10)
check(channelSays("DMO2 Q Ally:" .. fingerprint("3HR 3HR -")), "and they are asked with its fingerprint")
hear("Ally", "H " .. fingerprint("3HR 3HR -") .. " " .. ally)
wait(25)
check(morphOf(ally).display == 4527, "a matching fingerprint keeps it")
DmorphOctoAccount.peerCache.OctoWoW.Gone = { look = "3HR 0 -", guid = "0x0000000000100001", seen = Mock.now }
Mock.units.mouseover = { name = "Gone", guid = "0x0000000000100001", friendly = true, display = 55 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
check(morphOf("0x0000000000100001").display == 4527, "another remembered player shows")
wait(30)
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
check(morphOf("0x0000000000100001").display == nil and DmorphOctoAccount.peerCache.OctoWoW.Gone == nil,
	"but if they don't answer, they're forgotten and their look comes off")
Mock.units.mouseover = nil
hear("Ally", "M 3HR")
quiet()
hear("Ally", "H ZZZZ " .. ally)
wait(4)
check(channelSays("DMO2 Q Ally") and not channelSays("Q Ally:"), "a fingerprint that doesn't match asks for the whole look")
quiet()
Mock.units.mouseover = { name = "Stranger", guid = "0x00000000000D0001", friendly = true, display = 52 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(12)
check(not channelSays("Stranger"), "a player without DMorph isn't asked again after a /reload")
Mock.now = Mock.now + 86401
loadUI()
wait(15)
quiet()
Mock.units.mouseover = { name = "Stranger", guid = "0x00000000000D0001", friendly = true, display = 52 }
Mock.Fire("UPDATE_MOUSEOVER_UNIT")
wait(4)
check(channelSays("DMO2 Q Stranger"), "but is asked again a day later")
Mock.units.mouseover = nil
Mock.now = Mock.now + 15 * 86400
loadUI()
check(DmorphOctoAccount.peerCache.OctoWoW.Ally == nil, "looks are forgotten after two weeks")

-- Switching it off.
Mock.units.target = { name = "Ally", guid = ally, friendly = true, display = 50 }
hear("Ally", "L 3HR 0 - " .. ally)
wait(12)
quiet()
slash("share off")
wait(2)
check(DmorphOctoAccount.shareOff == true and channelSays("DMO2 L 0 0 -"),
	".share off tells the others to take your morph off")
quiet()
hear("Someone", "Q Tester")
wait(8)
check(table.getn(Mock.channelSent) == 0, "and questions about you go unanswered")
slash("share others off")
wait(1.5)
check(morphOf(ally).display == nil, ".share others off takes their morphs off as you see them")
slash("share")
check(contains(allChat(), "Others see your morph: off") and contains(allChat(), "DMorph users seen: 1")
	and contains(allChat(), "Messages sent this session: 1 on the channel"),
	".share shows the settings, how many DMorph users you've seen and the messages sent")
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
Mock.guild = nil

------------------------------------------------------------------------------
-- Race morphs: the flight map and the spellbook go by your own race.

newClient(49) -- a Human
DmorphOctoDB = nil
loadUI()
local drawnAs, listedAs = {}, nil
TaxiFrame = CreateFrame("Frame", "TaxiFrame")
function TaxiFrame_OnEvent(e)
	table.insert(drawnAs, vh.display)
end
SpellBookFrame = CreateFrame("Frame", "SpellBookFrame")
SpellBookFrame:SetScript("OnShow", function()
	listedAs = vh.display
end)
SpellBookFrame:Hide()
Mock.Fire("PLAYER_LOGIN")
say(".race orc")
check(vh.display == 51, "a race morph to an Orc")
TaxiFrame_OnEvent("TAXIMAP_OPENED") -- Blizzard's flight map handles it first
Mock.Fire("TAXIMAP_OPENED")
check(vh.display == 49 and drawnAs[2] == 49, "the flight map is drawn again with your own race")
say(".morph 4527")
check(vh.display == 49, "a morph picked meanwhile waits for the map to close")
Mock.Fire("TAXIMAP_CLOSED")
check(vh.display == 4527, "closing the map puts the morph on")
say(".race orc")
SpellBookFrame:Show()
check(listedAs == 49 and vh.display == 49, "the spellbook opens with your own race")
SpellBookFrame:Hide()
check(vh.display == 51, "and the race morph comes back when it closes")
say(".race human")
say(".gender")
SpellBookFrame:Show()
check(vh.display == 50, "your own race in the other gender isn't held")
SpellBookFrame:Hide()
say(".morph 4527")
drawnAs = {}
Mock.Fire("TAXIMAP_OPENED")
check(vh.display == 4527 and table.getn(drawnAs) == 0, "nor is a creature morph")
Mock.Fire("TAXIMAP_CLOSED")
TaxiFrame, TaxiFrame_OnEvent, SpellBookFrame = nil, nil, nil

------------------------------------------------------------------------------
-- Chat language: a race morph makes the game speak and list the morph's
-- languages, which the character may not know ("You don't know that language").

newClient(1478) -- a Troll (Horde)
DmorphOctoDB = nil
Mock.faction = "Horde"
-- What the game lists and speaks by default for the race it thinks you are.
local LANGUAGES = {
	[1478] = { { "Orcish", "Troll" }, "Orcish" },
	[49] = { { "Common" }, "Common" },
	[1563] = { { "Common", "Gnomish" }, "Common" },
	[6894] = { { "Orcish", "Goblin" }, "Orcish" },
}
Mock.raceLanguages = function()
	local l = LANGUAGES[vh.display] or LANGUAGES[1478]
	return l[1], l[2]
end
loadUI()
say(".race human")
SendChatMessage("hello", "SAY")
check(Mock.lastLanguage == "Orcish" and Mock.sent[table.getn(Mock.sent)] == "hello",
	"as a Human morph, /say goes out in Orcish instead of Common")
SendChatMessage("hello", "GUILD", "Common")
check(Mock.lastLanguage == "Orcish", "a language you don't know is swapped for one you do")
say(".race gnome")
SendChatMessage("hello", "SAY")
check(Mock.lastLanguage == "Orcish", "as a Gnome morph too, though the game lists Common and Gnomish")
SendChatMessage("hello", "SAY", "Gnomish")
check(Mock.lastLanguage == "Orcish", "a Gnome's language picked from the game's menu isn't sent either")
say(".race goblin")
SendChatMessage("hello", "SAY")
check(Mock.lastLanguage == "Orcish", "a Goblin morph speaks Orcish, the Horde's language you know")
SendChatMessage("hello", "SAY", "Troll")
check(Mock.lastLanguage == "Troll", "a language you picked and know is kept")
SendChatMessage("waves", "EMOTE")
check(Mock.lastLanguage == nil, "emotes aren't spoken, so they're left alone")
loadUI() -- VanillaHelpers keeps the morph over a /reload
Mock.Tick(0.6)
SendChatMessage("hello", "SAY", "Goblin")
check(vh.display == 6894 and Mock.lastLanguage == "Orcish" and DmorphOctoDB.languages[2] == "Troll",
	"after a /reload your own languages are read again with your own race showing")
say(".demorph")
SendChatMessage("hello", "SAY")
check(Mock.lastLanguage == "Orcish", "unmorphed, your own default is used")
Mock.raceLanguages, Mock.faction = nil, nil

------------------------------------------------------------------------------
-- Without VanillaHelpers, everything explains what is missing and stays local.

newClient(49)
removeMorphAPI()
DmorphOctoDB = nil
loadUI()
check(contains(allChat(), "VanillaHelpers isn't running") and contains(allChat(), "No client mods are running at all")
	and contains(allChat(), "from OctoLauncher (not WoW.exe)"),
	"missing DLL is reported at login: no client mod runs, so start the game from the launcher")
check(contains(allChat(), "/dmorph check"), "and it points to the setup check")
SUPERWOW_VERSION = "1.5"
slash("dmorph check")
check(contains(allChat(), "VanillaHelpers: |cffff5555NOT WORKING") and contains(allChat(), "only it is missing")
	and contains(allChat(), "Tick the 'vanillaHelpers' mod"),
	"with other client mods running, the check says only VanillaHelpers is missing")
check(contains(allChat(), "SuperWoW: |cff33ff99OK") and contains(allChat(), "ClassicAPI: |cffaaaaaanot running"),
	"and lists the optional parts")
SUPERWOW_VERSION = nil
VANILLAHELPERS_VERSION = 10001
slash("dmorph check")
check(contains(allChat(), "VanillaHelpers v1.0.1 is running, but morphing needs v1.1.0"),
	"an old VanillaHelpers is named, with the version morphing needs")
VANILLAHELPERS_VERSION = nil
say(".morph 4527")
check(table.getn(Mock.sent) == 0 and contains(lastChat(), "VanillaHelpers"),
	"commands without the DLL explain instead of being sent")
slash("help")
check(contains(allChat(), "VanillaHelpers"), "help mentions the missing DLL")
slash("")
check(DmorphOctoFrame:IsVisible() and contains(DmorphOctoFrameStatus.text, "VanillaHelpers"),
	"the window opens and says the DLL is missing")
check(DmorphOctoSetup:IsVisible() and DmorphOctoSetupName1.text == "VanillaHelpers"
	and DmorphOctoSetupState1.text == "Not working" and contains(DmorphOctoSetupText1.text, "OctoLauncher"),
	"and opens the setup check, with how to fix it")
check(contains(DmorphOctoSetupButton.text, "fix me"), "the Setup button is red")
installMorphAPI()
Mock.Click(DmorphOctoSetupRecheck)
check(DmorphOctoSetupState1.text == "OK" and contains(DmorphOctoSetupButton.text, "Setup OK")
	and contains(DmorphOctoSetupSummary.text, "Morphing works"), "Check again sees VanillaHelpers once it runs")
check(contains(DmorphOctoSetupButton.text, "No helper"), "the Setup button says no DmorphHelper is running")
Mock.Click(DmorphOctoSetupClose)
check(not DmorphOctoSetup:IsVisible(), "Close hides the check")
removeMorphAPI()
Mock.Type(DmorphOctoModelSearch, "thrall")
Mock.Click(DmorphOctoModelListRow1)
check(contains(DmorphOctoFrameStatus.text, "VanillaHelpers"), "clicking a model without the DLL explains")

------------------------------------------------------------------------------
-- What tools/build_models.ps1 and build_items.ps1 found can't show in this
-- client (Data/HiddenModels.lua, Data/HiddenItems.lua) is left out everywhere.

newClient(49)
installMorphAPI()
Mock.ResetUI()
Mock.LoadAddon("DmorphOcto.toc")
DmorphOcto_HiddenModels, DmorphOcto_HiddenItems = "4527,18088", "2955"
local shown = DmorphOcto.GetCreatureCatalog()
check(shown.byID[4527] == nil and shown.byID[11121] ~= nil, "hidden models are left out of the model list")
check(DmorphOcto.GetItemCatalog(1).byID[2955] == nil and DmorphOcto.GetItemCatalog(1).count > 100,
	"hidden items are left out of the item lists")
local stillThere = false
local humanLooks = DmorphOcto.GetLooks(1, 1)
for i = 1, table.getn(humanLooks) do
	if humanLooks[i][1] == 18088 then
		stillThere = true
	end
end
check(not stillThere and table.getn(humanLooks) > 100, "hidden NPC looks are left out of the Races tab")


------------------------------------------------------------------------------
-- DmorphHelper.dll: weapon glows and your own skin, face and hair. The fake
-- keeps the player's look and weapon enchants the way the game's fields do,
-- and like the real DLL it survives a /reload. The data is what
-- tests/make_game_fixture.py's game gives tools/build_options.ps1.

local GLOWS = "25\t1900\tCrusader; Holy Power\tHolyGlow\n26\t803\tFiery Weapon\tFireGlow\n"
	.. "28\t20\tFrost\tFrostGlow\n29\t30\t\tHolyGlow\n"
local OPTIONS = {
	["1:0"] = {
		skin = { 0, 1, 2, 3 }, npcSkin = { [3] = true },
		face = { [0] = { 0, 1, 2 }, [1] = { 0 }, [2] = { 0 }, [3] = { 0 } }, npcFace = {},
		hairStyle = { 0, 1, 2 }, npcHairStyle = {},
		hairColour = { [0] = { 0, 1 }, [1] = { 0 }, [2] = { 0 } }, anyHairColour = { 0, 1 }, npcHairColour = {},
		facialHair = { 0, 1, 2 },
	},
	["2:0"] = {
		skin = { 0, 1 }, npcSkin = {},
		face = { [0] = { 0 }, [1] = { 0 } }, npcFace = {},
		hairStyle = { 0, 1 }, npcHairStyle = {},
		hairColour = { [0] = { 0 } }, anyHairColour = { 0 }, npcHairColour = {},
		facialHair = { 0 },
	},
}

local game
local function installHelper(look)
	game = { look = look, real = look, enchants = { [16] = { 803, 0 }, [17] = { 0, 0 }, [18] = { 0, 0 } }, lookWrites = 0,
		scale = 1, race = 1, ownRace = 0, rebuilds = 0,
		weather = { 0, 0 }, serverWeather = { 1, 0.3 }, weatherOn = false, inWorld = true, time = -1, realTime = 600 }
	local function whole(v, max)
		return type(v) == "number" and v >= 0 and v <= max and v == math.floor(v)
	end
	function DmorphHelper_Version()
		return 11
	end
	-- The race byte: VanillaHelpers writes the morph's race there (tests set
	-- game.race); DmorphHelper_SetRace writes it without a rebuild, and
	-- DmorphHelper_SetOwnRace is the race chat and reactions use (0: the byte's).
	function DmorphHelper_GetRace(unit)
		return game.race
	end
	function DmorphHelper_SetRace(unit, race)
		if unit ~= "player" or not whole(race, 20) or race < 1 then
			error("Usage: DmorphHelper_SetRace(unit, race 1-20)")
		end
		game.race = race
	end
	function DmorphHelper_SetOwnRace(race)
		if not whole(race, 20) then
			error("Usage: DmorphHelper_SetOwnRace(race 0-20)")
		end
		game.ownRace = race
	end
	function DmorphHelper_Rebuild(unit)
		game.rebuilds = game.rebuilds + 1
	end
	-- Weather: what shows, and the server's (rain at 30% here).
	function DmorphHelper_SetWeather(kind, intensity)
		if not whole(kind, 3) or type(intensity) ~= "number" or intensity < 0 or intensity > 1 then
			error("Usage: DmorphHelper_SetWeather(type 0-3, intensity 0-1)")
		end
		if not game.inWorld then
			error("There's no weather outside the world.")
		end
		game.weather, game.weatherOn = { kind, intensity }, true
	end
	function DmorphHelper_ClearWeather()
		game.weather, game.weatherOn = { game.serverWeather[1], game.serverWeather[2] }, false
	end
	function DmorphHelper_GetWeather()
		return game.weather[1], game.weather[2], game.weatherOn and 1 or 0, game.serverWeather[1], game.serverWeather[2]
	end
	-- Time of day: -1 is the real time (10:00 here).
	function DmorphHelper_SetTime(minutes)
		if type(minutes) ~= "number" or not (minutes == -1 or (minutes >= 0 and minutes < 1440)) then
			error("Usage: DmorphHelper_SetTime(minutes 0-1439, or -1 for the real time)")
		end
		game.time = minutes
	end
	function DmorphHelper_GetTime()
		if game.time >= 0 then
			return game.time, 1, game.realTime
		end
		return game.realTime, 0, game.realTime
	end
	-- Virtual items: item IDs only this PC has (ported weapons).
	game.virtual = {}
	function DmorphHelper_SetVirtualItem(id, template, display)
		if not (whole(id, 2147483647) and whole(template, 2147483647) and whole(display, 2147483647)) then
			error("Usage: DmorphHelper_SetVirtualItem(itemID, templateItemID, displayID)")
		end
		game.virtual[id] = { template, display }
	end
	function DmorphHelper_GetScale(unit)
		return game.scale
	end
	function DmorphHelper_SetScale(unit, scale)
		if unit ~= "player" or type(scale) ~= "number" or scale < 0.1 or scale > 10 then
			error("Usage: DmorphHelper_SetScale(unit, scale 0.1-10)")
		end
		game.scale = scale
	end
	function DmorphHelper_GetItemEnchants(unit, slot)
		if unit ~= "player" or not whole(slot, 19) or slot < 1 then
			error("Usage: DmorphHelper_GetItemEnchants(unit, slot 1-19)")
		end
		local e = game.enchants[slot] or { 0, 0 }
		return e[1], e[2]
	end
	function DmorphHelper_SetItemEnchants(unit, slot, permanent, temporary)
		if unit ~= "player" or not whole(slot, 19) or not whole(permanent, 1000000) or not whole(temporary, 1000000) then
			error("Usage: DmorphHelper_SetItemEnchants(unit, slot 1-19, permanent, temporary)")
		end
		game.enchants[slot] = { permanent, temporary }
	end
	function DmorphHelper_GetLook(unit)
		local l = game.look
		return l[1], l[2], l[3], l[4], l[5]
	end
	function DmorphHelper_SetLook(unit, a, b, c, d, e)
		for _, v in ipairs({ a, b, c, d, e }) do
			if not whole(v, 255) then
				error("Usage: DmorphHelper_SetLook(unit, skin, face, hairStyle, hairColour, facialHair)")
			end
		end
		game.look = { a, b, c, d, e }
		game.lookWrites = game.lookWrites + 1
	end
end

local function removeHelper()
	DmorphHelper_Version, DmorphHelper_GetItemEnchants, DmorphHelper_SetItemEnchants = nil, nil, nil
	DmorphHelper_GetLook, DmorphHelper_SetLook = nil, nil
	DmorphHelper_GetScale, DmorphHelper_SetScale = nil, nil
	DmorphHelper_GetRace, DmorphHelper_SetRace, DmorphHelper_SetOwnRace, DmorphHelper_Rebuild = nil, nil, nil, nil
	DmorphHelper_SetWeather, DmorphHelper_ClearWeather, DmorphHelper_GetWeather = nil, nil, nil
	DmorphHelper_SetTime, DmorphHelper_GetTime = nil, nil
	DmorphHelper_SetVirtualItem = nil
end

local function sameLook(a, b)
	for i = 1, 5 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- Whether a look is one the race and gender can wear (OPTIONS).
local function wearable(look, key)
	local o = OPTIONS[key]
	local function has(list, v)
		for i = 1, table.getn(list or {}) do
			if list[i] == v then
				return true
			end
		end
	end
	return has(o.skin, look[1]) and has(o.face[look[1]], look[2]) and has(o.hairStyle, look[3])
		and has(o.hairColour[look[3]] or o.anyHairColour, look[4]) and has(o.facialHair, look[5])
end

local function loadWithHelper()
	loadUI()
	DmorphOcto_GlowData, DmorphOcto_CharOptions = GLOWS, OPTIONS
end

-- Without the DLL the glow and look actions say what's missing.
newClient(49)
installMorphAPI()
removeHelper()
DmorphOctoDB, DmorphOctoAccount = nil, nil
loadWithHelper()
check(not DmorphOcto.HasHelper(), "without DmorphHelper.dll it isn't detected")
slash("glow mainhand 1900")
check(contains(lastChat(), "DmorphHelper.dll isn't loaded"), ".glow without the DLL says it's missing")
slash("dmorph status")
check(contains(allChat(), "DmorphHelper.dll is not loaded"), "status says the helper isn't loaded")
slash("dmorph check")
check(contains(allChat(), "DmorphHelper: |cffaaaaaanot running") and contains(allChat(), "Install DmorphHelper.bat"),
	"the check says to double-click the installer")
slash("")
Mock.Click(DmorphOctoTabGlows)
check(contains(DmorphOctoGlowState.text, "isn't loaded"), "the Glows tab says the helper isn't loaded")
check(DmorphOctoGlowCount.text == "4 glows" and DmorphOctoGlowListRow1.text.text == "Crusader",
	"the Glows tab lists the game's glows")
press(DmorphOctoGlowListRow1)
check(contains(DmorphOctoFrameStatus.text, "DmorphHelper.dll isn't loaded"), "clicking a glow without the DLL explains")
Mock.Click(DmorphOctoTabRaces)
check(DmorphOctoCreatorValue1.text == "yours" and contains(DmorphOctoRacesHint.text, "an NPC has"),
	"without the DLL the Races rows go through NPC looks")

-- With it: glows.
local REAL = { 0, 1, 0, 1, 2 }
installHelper(REAL)
DmorphOctoDB, DmorphOctoAccount = nil, nil
loadWithHelper()
Mock.Tick(1.1)
slash("dmorph status")
check(contains(allChat(), "DmorphHelper v11 is loaded"), "status shows the helper's version")
slash("dmorph check")
check(contains(allChat(), "DmorphHelper: |cff33ff99OK"), "the check says the helper runs")
check(contains(allChat(), "Running v11 (this DMorph comes with v11)"), "and which version runs")
local openedForSetup = not (DmorphOctoFrame and DmorphOctoFrame:IsVisible())
if openedForSetup then
	slash("")
end
Mock.Click(DmorphOctoSetupButton)
check(contains(DmorphOctoSetupButton.text, "Helper v11") and contains(DmorphOctoSetupText2.text, "Running v11"),
	"the Setup button and panel show the helper version")
Mock.Click(DmorphOctoSetupClose)
local currentVersion = DmorphHelper_Version
DmorphHelper_Version = function() return 3 end
slash("dmorph status")
check(contains(lastChat(), "DmorphHelper v3 is loaded, an older one") or contains(allChat(), "DmorphHelper v3 is loaded, an older one"),
	"status flags an older helper")
Mock.Click(DmorphOctoSetupButton)
check(contains(DmorphOctoSetupButton.text, "Old helper v3"), "the Setup button flags an older helper")
Mock.Click(DmorphOctoSetupClose)
if openedForSetup then
	DmorphOcto_ToggleUI()
end
slash("dmorph check")
check(contains(allChat(), "An older DmorphHelper (v3)") and contains(allChat(), "Install DmorphHelper.bat"),
	"an older DLL in the game folder is flagged, with how to update it")
DmorphHelper_Version = currentVersion

-- Weather (DmorphHelper v8).
slash("weather rain heavy")
check(game.weatherOn and game.weather[1] == 1 and game.weather[2] == 1 and contains(lastChat(), "Rain (100%)"),
	".weather rain heavy makes it pour")
slash("weather snow 40")
check(game.weather[1] == 2 and math.abs(game.weather[2] - 0.4) < 0.001, ".weather snow 40 snows at 40%")
slash("weather sandstorm light")
check(game.weather[1] == 3 and game.weather[2] == 0.25, ".weather sandstorm light")
slash("weather clear")
check(game.weatherOn and game.weather[1] == 0 and contains(lastChat(), "Clear skies"), ".weather clear clears the sky")
slash("weather fog")
check(game.weather[1] == 0 and contains(lastChat(), "Usage: .weather"), "an unknown weather explains the command")
slash("weather rain 0")
check(game.weather[1] == 0 and contains(lastChat(), "5% to 100%"), "rain with no strength is refused")
slash("weather rain")
slash("dmorph status")
check(contains(allChat(), "Weather: Rain (55%)"), "status shows the picked weather")
game.weather = { 1, 0.3 } -- a loading screen: the game shows the server's weather
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(0.6)
check(game.weather[1] == 1 and game.weather[2] == 0.55, "the picked weather comes back after a loading screen")
game.weather = { 0, 0 }
Mock.Fire("ZONE_CHANGED_NEW_AREA")
check(game.weather[1] == 1 and game.weather[2] == 0.55, "and in a new zone")
game.inWorld = false
slash("weather snow")
check(game.weather[1] == 1 and contains(lastChat(), "outside the world"), "no weather change outside the world")
game.inWorld = true
local openedForWeather = not (DmorphOctoFrame and DmorphOctoFrame:IsVisible())
if openedForWeather then
	slash("")
end
press(DmorphOctoTabWeather)
check(DmorphOctoPageWeather:IsVisible() and DmorphOctoWeatherRain.locked and not DmorphOctoWeatherMissing:IsVisible()
	and contains(DmorphOctoWeatherState.text, "Rain (55%)") and contains(DmorphOctoWeatherState.text, "Rain (30%)"),
	"the Weather tab shows the picked weather and the server's")
check(DmorphOctoTabWeather:GetWidth() > 0 and DmorphOctoTabFavourites:GetWidth() > DmorphOctoTabSets:GetWidth(),
	"tabs are as wide as their names")
press(DmorphOctoWeatherHeavySnow)
check(game.weather[1] == 2 and game.weather[2] == 1 and DmorphOctoWeatherHeavySnow.locked
	and not DmorphOctoWeatherRain.locked, "a weather button puts that weather on")
DmorphOctoWeatherStrength:SetValue(0.5)
Mock.Tick(0.4)
check(game.weather[1] == 2 and game.weather[2] == 0.5 and DmorphOctoWeatherStrengthLabel.text == "Strength 50%",
	"the slider sets how strong it is")
Mock.Tick(1.1)
press(DmorphOctoWeatherServer)
check(not game.weatherOn and game.weather[1] == 1 and DmorphOcto.GetWeather() == nil
	and contains(DmorphOctoWeatherState.text, "Weather: the server's"), "Server's weather gives it back")
Mock.Tick(1.1)
DmorphOctoWeatherStrength:SetValue(0.9)
Mock.Tick(0.4)
check(not game.weatherOn and contains(DmorphOctoFrameStatus.text, "Pick rain, snow"),
	"the slider needs a weather first")
-- Time of day (DmorphHelper v9).
Mock.Tick(1.1)
press(DmorphOctoTimeNight)
check(game.time == 0 and DmorphOctoTimeNight.locked and contains(DmorphOctoWeatherState.text, "0:00")
	and contains(DmorphOctoWeatherState.text, "the real time is 10:00"), "Midnight makes it night")
Mock.Tick(1.1)
DmorphOctoTimeSlider:SetValue(1350)
Mock.Tick(0.4)
check(game.time == 1350 and DmorphOctoTimeLabel.text == "Time 22:30" and not DmorphOctoTimeNight.locked,
	"the time slider picks any time")
Mock.Tick(1.1)
press(DmorphOctoTimeReal)
check(game.time == -1 and DmorphOcto.GetTime() == nil and contains(DmorphOctoWeatherState.text, "Time: the real time"),
	"Real time gives it back")
if openedForWeather then
	DmorphOcto_ToggleUI()
end

slash("time 21:15")
check(game.time == 1275 and contains(lastChat(), "21:15"), ".time 21:15")
slash("time dusk")
check(game.time == 1170, ".time dusk")
slash("time 25")
check(game.time == 1170 and contains(lastChat(), "Usage: .time"), "a time that isn't one explains the command")
slash("dmorph status")
check(contains(allChat(), "Time of day: 19:30"), "status shows the picked time")
game.time = -1 -- the helper forgot (a new game session)
Mock.Fire("ZONE_CHANGED_NEW_AREA")
check(game.time == 1170, "the picked time is put back")
slash("time off")
check(game.time == -1 and contains(lastChat(), "real time"), ".time off")

-- Your size.
slash("scale 2")
check(game.scale == 2 and contains(lastChat(), "Size: 200%"), ".scale 2 doubles your size")
game.scale = 1 -- the server sends your real size again
Mock.Tick(1.1)
check(game.scale == 2, "the watcher puts the size back")
slash("scale 50%")
check(game.scale == 0.5, ".scale 50% halves it")
slash("scale 20")
check(game.scale == 0.5 and contains(lastChat(), "0.1 to 10"), "a size out of range is refused")
slash("")
check(DmorphOctoSize:GetValue() == 0.5 and DmorphOctoSizeLabel.text == "Size 50%" and contains(DmorphOctoLookInfo.text, "size 50%"),
	"the window's size slider and plate show the size")
DmorphOctoSize:SetValue(1.5)
Mock.Tick(0.4)
check(game.scale == 1.5 and DmorphOctoSizeLabel.text == "Size 150%", "dragging the slider sets your size once it stands still")
Mock.RunScript(DmorphOctoSize, "OnMouseUp", "RightButton")
Mock.Tick(0.4)
check(game.scale == 1 and DmorphOcto.GetScale() == nil, "right-click puts your own size back")
DmorphOcto_ToggleUI()
slash("scale 3")
slash("demorph all")
Mock.Tick(1.1)
check(game.scale == 1, "resetting everything puts your own size back")
slash("")
Mock.Click(DmorphOctoTabGlows)
check(DmorphOctoGlowState.text == "Main hand: your own (Fiery Weapon)", "the tab shows your own glow by name")
Mock.Type(DmorphOctoGlowSearch, "holy power")
check(DmorphOctoGlowCount.text == "1 glow" and DmorphOctoGlowListRow1.text.text == "Crusader",
	"search finds a glow by any enchant that shows it")
Mock.Type(DmorphOctoGlowSearch, "holyglow")
check(DmorphOctoGlowCount.text == "2 glows", "or by its effect model")
Mock.Type(DmorphOctoGlowSearch, "")
check(DmorphOctoGlowListRow4.text.text == "Glow 29", "a glow no enchant names is called by its number")
press(DmorphOctoGlowListRow1)
check(game.enchants[16][1] == 1900 and game.enchants[16][2] == 0, "clicking a glow puts its enchant on the main hand")
check(DmorphOctoGlowListRow1.tick.shown and DmorphOctoGlowState.text == "Main hand: Crusader",
	"the glow you picked is ticked and named")
game.enchants[16] = { 803, 5 } -- the server sends the real enchant (and an oil) again
Mock.Tick(1.1)
check(game.enchants[16][1] == 1900 and game.enchants[16][2] == 0, "the watcher puts the glow back after the server resends")
local picked, real = DmorphOcto.GetGlow(16)
check(picked == 1900 and real == 803, "the real enchant is remembered")
press(DmorphOctoGlowSlot17)
press(DmorphOctoGlowListRow3)
check(game.enchants[17][1] == 20 and game.enchants[16][1] == 1900, "the off hand gets its own glow")
press(DmorphOctoGlowNone)
check(game.enchants[17][1] == 0 and game.enchants[17][2] == 0, "No glow clears the slot")
slash("glow ranged 30")
check(game.enchants[18][1] == 30, ".glow ranged sets the ranged slot")
slash("glow mh 99999999")
check(contains(lastChat(), "Usage") or contains(lastChat(), "whole numbers"), "a bad enchant ID is refused")
-- A /reload keeps the glows and what's real.
loadWithHelper()
game.enchants[16] = { 803, 5 }
Mock.Tick(1.1)
check(game.enchants[16][1] == 1900, "glows come back after a /reload")
slash("glow mainhand own")
check(game.enchants[16][1] == 803 and game.enchants[16][2] == 5, "your own glow puts the real enchant back")
Mock.Tick(1.1)
check(game.enchants[16][1] == 803, "and the watcher leaves it alone afterwards")
slash("dmorph status")
check(contains(allChat(), "Glow, ranged: Glow 29"), "status lists the glows")

-- Your own skin, face and hair (Races tab).
slash("")
Mock.Click(DmorphOctoTabRaces)
check(DmorphOctoCreatorValue1.text == "1 of 4" and DmorphOctoCreatorValue2.text == "2 of 3"
	and DmorphOctoCreatorValue4.text == "2 of 2", "the rows show where your own look is among the race's")
check(contains(DmorphOctoRacesHint.text, "real skin"), "the hint says the rows change your real look")
press(DmorphOctoCreatorNext1)
check(game.look[1] == 1 and game.look[2] == 0 and vh.display == 49,
	"skin colour > changes only your model's skin (and a face it doesn't have)")
check(contains(DmorphOctoFrameStatus.text, "face changed too"), "the status says the face had to change")
check(DmorphOctoCreatorValue1.text == "2 of 4", "the row shows the new skin colour")
press(DmorphOctoCreatorNext1)
press(DmorphOctoCreatorNext1)
check(game.look[1] == 3 and DmorphOctoCreatorValue1.text == "4 of 4 (NPC)" and contains(DmorphOctoFrameStatus.text, "NPC-only"),
	"an NPC-only skin colour is marked")
press(DmorphOctoCreatorNext2)
check(contains(DmorphOctoFrameStatus.text, "just one face"), "a row with one choice says so")
press(DmorphOctoCreatorNext3)
check(game.look[3] == 1 and game.look[4] == 0, "a hair style without your hair colour takes the closest one")
check(contains(DmorphOctoFrameStatus.text, "hair colour changed too"), "and says so")
check(wearable(game.look, "1:0"), "every picked look is one the race can wear")
local mine = { game.look[1], game.look[2], game.look[3], game.look[4], game.look[5] }
game.look = REAL -- the server sends your real look again
Mock.Tick(1.1)
check(sameLook(game.look, mine), "the watcher puts the picked look back")
loadWithHelper()
game.look = REAL
Mock.Tick(1.1)
check(sameLook(game.look, mine), "and after a /reload")
slash("")
Mock.Click(DmorphOctoTabRaces)
check(contains(DmorphOctoCreatorTitle.text, "a look you picked"), "the title says the look is one you picked")
-- Outfits keep the look and the glows.
slash("outfit save Ghost")
check(contains(DmorphOcto.DescribeOutfit(DmorphOcto.GetOutfit("Ghost")), "own face"), "outfits note a picked look")
press(DmorphOctoOwnLook)
Mock.Tick(0.2)
check(sameLook(game.look, REAL), "My own look puts your real face, skin and hair back")
Mock.Tick(1.1)
check(sameLook(game.look, REAL), "and the watcher leaves it")
slash("outfit Ghost")
Mock.Tick(0.6)
check(sameLook(game.look, mine) and game.enchants[18][1] == 30, "loading the outfit brings the look and glows back")
-- Another race: its own look, made to fit.
press(DmorphOctoRace2Male)
check(sameLook(game.look, mine), "a look isn't written while the game still builds the new model")
Mock.Tick(0.2)
Mock.Tick(1.1)
check(vh.display == 51 and wearable(game.look, "2:0") and sameLook(game.look, { 0, 0, 0, 0, 0 }),
	"another race shows your real look, moved to the closest values that race has (no green textures)")
Mock.Click(DmorphOctoTabRaces)
check(not contains(DmorphOctoCreatorValue2.text, "?"), "and the rows show those values")
press(DmorphOctoCreatorNext1)
check(wearable(game.look, "2:0"), "a look picked on another race fits that race")
local orc = { game.look[1], game.look[2], game.look[3], game.look[4], game.look[5] }
press(DmorphOctoRace1Male)
Mock.Tick(0.2)
check(sameLook(game.look, mine), "each race keeps its own picked look")
press(DmorphOctoRace2Male)
Mock.Tick(0.2)
check(sameLook(game.look, orc), "and gets it back")
SpellBookFrame = CreateFrame("Frame", "SpellBookFrame")
SpellBookFrame:Hide()
ReputationFrame = CreateFrame("Frame", "ReputationFrame")
ReputationFrame:Hide()
Mock.Fire("PLAYER_LOGIN")
-- DmorphHelper v6: the race byte keeps the morph's race (the game textures
-- your model from it), and your own race is used while the game reads chat
-- and while the spellbook or flight map is open (the byte only, no rebuild).
game.race = 2 -- VanillaHelpers wrote the Orc race
Mock.Tick(0.2)
check(game.ownRace == 1, "during an Orc race morph, chat and reputations use your own race (Human)")
SpellBookFrame:Show()
Mock.Tick(1.1)
check(game.race == 1 and vh.display == 51 and sameLook(game.look, orc),
	"the spellbook opens with your own race, and your model stays the Orc")
SpellBookFrame:Hide()
check(game.race == 2 and vh.display == 51, "the Orc race goes back when it closes")
ReputationFrame:Show()
check(game.race == 1 and vh.display == 51, "the reputation list opens with your own race, so your standings are right")
SpellBookFrame:Show()
ReputationFrame:Hide()
check(game.race == 1, "the race stays yours while the spellbook is still open")
SpellBookFrame:Hide()
check(game.race == 2 and vh.display == 51, "and the Orc race goes back when both close")
SpellBookFrame, ReputationFrame = nil, nil
press(DmorphOctoCreatorRandom)
check(wearable(game.look, "2:0") and vh.display == 51, "the dice picks a look the race can wear, on your model")
-- From an NPC look: the rows take you back to your own model with its face.
press(DmorphOctoRace1Male)
press(DmorphOctoCreatorNext6)
check(contains(DmorphOctoCreatorTitle.text, "NPC look"), "the NPC look row wears whole NPC looks")
local npcDisplay = vh.display
press(DmorphOctoCreatorNext1)
check(vh.display == 49 and npcDisplay ~= 49 and wearable(game.look, "1:0"),
	"from an NPC look, a row goes back to your model with a look that fits")
check(contains(DmorphOctoFrameStatus.text, "Your own model now"), "and says so")
slash("demorph all")
Mock.Tick(1.1)
check(sameLook(game.look, REAL) and game.enchants[16][1] == 803 and game.enchants[18][1] == 0,
	"resetting everything puts your real look and glows back")
check(game.ownRace == 1, "the helper keeps your own race without a race morph too (loading screens)")
-- A race with no list (High Elf here) keeps the NPC rows.
press(DmorphOctoRace10Male)
check(contains(DmorphOctoRacesHint.text, "an NPC has"), "a race with no look list uses NPC looks")
removeHelper()

------------------------------------------------------------------------------
-- Ported models (Data/Ported.lua, made by the porting tool on one PC).
Mock.portedData = "60001\tPandaren Yeti Mount (Brown)\tmount\n60011\tTest Ported Thing\t\n"
Mock.portedItems = "900001\t90001\t207\t647\tWarglaive of Azzinoth\t0\t5\n900002\t90002\t208\t647\tBig Ported Sword\n"
	.. "900003\t90003\t406\t647\tPorted Shield\n"
	.. "901001\t120001\t404\t647\tPorted Plate Helm\t1\n901002\t120002\t404\t647\tPorted Plate Chest\t5\n"
Mock.portedSets = "Ported Plate Set\t901001,901002\n"
loadUI()
installMorphAPI()
local pc = DmorphOcto.GetCreatureCatalog()
local yeti = pc.byID[60001]
check(yeti and pc.names[yeti] == "Pandaren Yeti Mount (Brown)" and pc.kind[yeti] == DmorphOcto.KIND_PORTED
	and contains(pc.tags[yeti] or "", "mount"), "a ported mount is in the catalogue, as a mount")
local thing = pc.byID[60011]
check(thing and not contains(pc.tags[thing] or "", "mount"), "a ported model without the mount tag isn't one")
check(DmorphOcto.IsPorted(60001) and not DmorphOcto.IsPorted(49), "IsPorted knows them")
local sortedOK = true
for i = 2, pc.count do
	if pc.lower[i - 1] > pc.lower[i] then
		sortedOK = false
	end
end
check(sortedOK, "the catalogue stays sorted by name")
slash("")
Mock.Click(DmorphOctoTabMounts)
Mock.Click(DmorphOctoMountFilter)
pickMenu("Ported", true)
check(DmorphOctoMountFilter.text == "Ported (later expansions)" and tonumber(DmorphOctoMountListRow1.info.text) == 60001
	and tonumber(DmorphOctoMountListRow2.info.text) == 60011 and not DmorphOctoMountListRow3:IsVisible(),
	"the Mounts tab's Ported filter lists the ported models")
Mock.Click(DmorphOctoMountFilter)
pickMenu("Mount models")
DmorphOcto_ToggleUI()
slash("morph 60001")
local sharedDisplay, _, sharedMount = DmorphOcto.GetSharedLook()
check(vh.display == 60001 and sharedDisplay == nil, "you can morph into it, and others aren't sent it")
slash("demorph all")
-- Ported weapons (DmorphOcto_PortedItems, DmorphHelper v11 virtual items).
local mh = DmorphOcto.GetItemCatalog(16)
local glaive = mh.byID[900001]
check(glaive and mh.names[glaive] == "Warglaive of Azzinoth" and mh.kind[glaive] == DmorphOcto.KIND_PORTED
	and mh.byID[900002] and not mh.byID[900003], "ported weapons are in the slots their kind fits")
check(DmorphOcto.GetItemCatalog(17).byID[900001] and DmorphOcto.GetItemCatalog(17).byID[900003]
	and not DmorphOcto.GetItemCatalog(17).byID[900002], "one-handers and shields in the off hand, not two-handers")
check(DmorphOcto.GetItemType(900001) == 207 and DmorphOcto.IsPortedItem(900001), "they know their kind")
check(mh.quality[glaive] == 5 and mh.quality[mh.byID[900002]] == 4,
	"a ported item has its Retail quality (slot 0 = by kind), epic without one")
local legendary = DmorphOcto.FilterCatalog(mh, "", nil, 5)
local hasGlaive, hasArtifact = false, false
for i = 1, table.getn(legendary) do
	if legendary[i] == glaive then
		hasGlaive = true
	end
	if mh.quality[legendary[i]] == 6 then
		hasArtifact = true
	end
end
check(hasGlaive and hasArtifact, "Legendary lists legendaries and artifacts (quality 6)")
slash("item 16 900001")
check(vh.items[16] ~= 900001 and contains(lastChat(), "DmorphHelper v11"), "without DmorphHelper v11 a ported weapon explains")
installHelper(REAL)
local SHIELD = 876   -- a shield in Data/ItemTypes.lua (kind 406)
-- The template (a real item the record is copied from) must be known to the
-- game: wearing a ported item without it turned the player white (guns, thrown).
slash("item 17 900003")
check(vh.items[17] ~= 900003 and contains(lastChat(), "hasn't loaded an item to copy"),
	"a ported item whose template the game doesn't know yet isn't worn, and says why")
Mock.serverItems[SHIELD] = { "Some Shield", 1, "INVTYPE_SHIELD" }
slash("item 17 900003")
check(vh.items[17] == 900003 and game.virtual[900003] and game.virtual[900003][1] == SHIELD,
	"it borrows another item of its kind the game knows")
slash("item 17 0")
Mock.serverItems[SHIELD] = nil
Mock.serverItems[647] = { "Arcanite Reaper", 4, "INVTYPE_2HWEAPON" }
slash("item 16 900001")
check(vh.items[16] == 900001 and game.virtual[900001] and game.virtual[900001][1] == 647
	and game.virtual[900001][2] == 90001 and game.virtual[900002], "with it, the weapon is registered and worn")
local _, sharedItems = DmorphOcto.GetSharedLook()
check(sharedItems[16] == nil, "and others aren't sent it")
-- Ported armour names its slot; ported sets come from DmorphOcto_PortedSets.
local helm = DmorphOcto.GetItemCatalog(1)
check(helm.byID[901001] and helm.kind[helm.byID[901001]] == DmorphOcto.KIND_PORTED and not helm.byID[901002]
	and DmorphOcto.GetItemCatalog(5).byID[901002] and not DmorphOcto.GetItemCatalog(16).byID[901001],
	"ported armour is only in its own slot")
local sc = DmorphOcto.GetSetCatalog()
local ps = sc.byID[900001]
check(ps and sc.names[ps] == "Ported Plate Set" and sc.kind[ps] == DmorphOcto.KIND_PORTED
	and sc.types[ps] == 404, "a ported set is in the Sets list, as plate")
local setsSorted = true
for i = 2, sc.count do
	if sc.lower[i - 1] > sc.lower[i] then
		setsSorted = false
	end
end
check(setsSorted, "the sets stay sorted by name")
local wore = DmorphOcto.WearSet(ps)
check(wore and vh.items[1] == 901001 and vh.items[5] == 901002, "wearing it puts both pieces on")
slash("demorph all")
removeHelper()
Mock.portedData, Mock.portedItems, Mock.portedSets = nil, nil, nil
Mock.serverItems[647] = nil
loadUI()
check(not DmorphOcto.GetCreatureCatalog().byID[60001], "without Data/Ported.lua there are no ported models")

print(format("%d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
