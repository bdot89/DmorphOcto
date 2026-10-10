-- DMorph for OctoWoW: morph state, wardrobe, catalogue search and the chat
-- commands. The window lives in UI.lua and calls the same DmorphOcto.*
-- functions as the commands.
--
-- DMorph itself is a DLL built for WotLK 3.3.5a (build 12340) with that
-- client's addresses hardcoded, so it can't run on OctoWoW's 1.12.1 client.
-- This addon drives the morph API of VanillaHelpers.dll (v1.1.0+) instead:
-- OctoLauncher ships it as the "vanillaHelpers" mod and it is built for the
-- 1.12.1 client.
--
-- The client runs Lua 5.0: no #, no %, no string.match, no select(), and
-- table.getn() counts element by element, so long lists keep their own count.

local VERSION = "1.1.0"
local PREFIX = "|cff33ff99DMorph|r: "
local MISSING_API = "VanillaHelpers v1.1.0 or newer is not loaded, so morphing is unavailable. "
	.. "Enable the 'vanillaHelpers' mod in OctoLauncher (or add VanillaHelpers.dll to dlls.txt) "
	.. "and restart the game."

-- Player model display IDs, indexed by race ID. VanillaHelpers recognises
-- exactly these and rewrites race and gender as well, so your own skin, face
-- and hair carry over. Race 10 is the High Elf on Turtle-based clients.
local RACES = {
	{ name = "Human",     male = 49,    female = 50 },
	{ name = "Orc",       male = 51,    female = 52 },
	{ name = "Dwarf",     male = 53,    female = 54 },
	{ name = "Night Elf", male = 55,    female = 56 },
	{ name = "Undead",    male = 57,    female = 58 },
	{ name = "Tauren",    male = 59,    female = 60 },
	{ name = "Gnome",     male = 1563,  female = 1564 },
	{ name = "Troll",     male = 1478,  female = 1479 },
	{ name = "Goblin",    male = 6894,  female = 6895 },
	{ name = "High Elf",  male = 15476, female = 15475 },
}
local RACE_ALIASES = {
	human = 1, orc = 2, dwarf = 3, nightelf = 4, ne = 4, undead = 5, scourge = 5,
	forsaken = 5, tauren = 6, gnome = 7, troll = 8, goblin = 9, highelf = 10,
	bloodelf = 10,
}
-- UnitRace() file tokens, only used when the native model isn't in RACES.
local RACE_TOKENS = {
	HUMAN = 1, ORC = 2, DWARF = 3, NIGHTELF = 4, SCOURGE = 5, TAUREN = 6,
	GNOME = 7, TROLL = 8, GOBLIN = 9, HIGHELF = 10, BLOODELF = 10,
}

-- Inventory slots that show on the character model, numbered like DMorph
-- and GetInventorySlotInfo(). Neck, rings and trinkets have no model.
local SLOT_ORDER = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local SLOT_NAMES = {
	[1] = "Head", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist",
	[7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands", [15] = "Back",
	[16] = "Main hand", [17] = "Off hand", [18] = "Ranged", [19] = "Tabard",
}
local SLOT_ALIASES = {
	head = 1, shoulder = 3, shoulders = 3, shirt = 4, chest = 5, waist = 6,
	belt = 6, legs = 7, feet = 8, boots = 8, wrist = 9, wrists = 9, hands = 10,
	gloves = 10, back = 15, cloak = 15, mainhand = 16, offhand = 17,
	ranged = 18, tabard = 19,
}

DmorphOcto = {
	VERSION = VERSION,
	MISSING_API = MISSING_API,
	RACES = RACES,
	SLOT_ORDER = SLOT_ORDER,
	SLOT_NAMES = SLOT_NAMES,
}
local M = DmorphOcto

-- An outfit is { display, race, gender (0 male, 1 female), items[slot] }.
local db      -- DmorphOctoDB, per character: the outfit currently applied
local account -- DmorphOctoAccount, shared: saved outfits and the minimap button
local nativeRace, nativeGender
local sessionReady = false
local warnedMissingAPI = false
local pendingApply
local listeners = {}
local creatures
local items = {}

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function Report(ok, message)
	Print(message)
end

local function HasMorphAPI()
	return type(SetUnitDisplayID) == "function"
		and type(SetUnitVisibleItemID) == "function"
		and type(UnitDisplayInfo) == "function"
end
M.HasMorphAPI = HasMorphAPI

-- VanillaHelpers reports bad input with lua_error, so every call is guarded.
-- A nil value clears that override.
local function Morph(fn, a1, a2, a3)
	return pcall(fn, a1, a2, a3)
end

local function ParseID(text)
	local n = tonumber(text or "")
	if n and n >= 0 and n <= 2147483647 and n == math.floor(n) then
		return n
	end
end
M.ParseID = ParseID

local function Trim(text)
	local _, _, trimmed = strfind(text or "", "^%s*(.-)%s*$")
	return trimmed
end

local function RaceModel(race, gender)
	if gender == 1 then
		return RACES[race].female
	end
	return RACES[race].male
end

function M.DescribeBody(race, gender)
	if gender == 1 then
		return RACES[race].name .. " female"
	end
	return RACES[race].name .. " male"
end

local function RaceList()
	local list = ""
	for race = 1, table.getn(RACES) do
		list = list .. ", " .. race .. " " .. RACES[race].name
	end
	return strsub(list, 3)
end

local function SlotList()
	local list = ""
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		list = list .. ", " .. slot .. " " .. strlower(SLOT_NAMES[slot])
	end
	return strsub(list, 3)
end

-- Catalogue -----------------------------------------------------------------

-- Data/Creatures.lua and Data/Items.lua hold the catalogue as text so the
-- game loads it quickly; each list is parsed the first time it's needed.
local function NewCatalog()
	return { ids = {}, names = {}, lower = {}, quality = {}, byID = {}, count = 0 }
end

local function AddEntry(catalog, id, name, quality)
	local n = catalog.count + 1
	catalog.count = n
	catalog.ids[n], catalog.names[n], catalog.lower[n] = id, name, strlower(name)
	catalog.quality[n] = quality
	if not catalog.byID[id] then
		catalog.byID[id] = n
	end
end

function M.GetCreatureCatalog()
	if not creatures then
		creatures = NewCatalog()
		for id, name in string.gfind(DmorphOcto_CreatureData or "", "(%d+)\t([^\r\n]+)") do
			AddEntry(creatures, tonumber(id), name)
		end
		DmorphOcto_CreatureData = nil -- the parsed tables replace the text
	end
	return creatures
end

function M.GetItemCatalog(slot)
	if not items[slot] then
		local catalog = NewCatalog()
		local source = DmorphOcto_ItemData and DmorphOcto_ItemData[slot] or ""
		for id, quality, name in string.gfind(source, "(%d+)\t(%d)\t([^\r\n]+)") do
			AddEntry(catalog, tonumber(id), name, tonumber(quality))
		end
		if DmorphOcto_ItemData then
			DmorphOcto_ItemData[slot] = nil
		end
		items[slot] = catalog
	end
	return items[slot]
end

-- Positions of the catalogue entries matching the text, plus how many there
-- are: an exact ID first, then names starting with the text, then names
-- containing it.
function M.FilterCatalog(catalog, text)
	local query = strlower(Trim(text))
	local result, n = {}, 0
	if query == "" then
		for i = 1, catalog.count do
			result[i] = i
		end
		return result, catalog.count
	end
	local number = ParseID(query)
	local later, m = {}, 0
	for i = 1, catalog.count do
		local at = strfind(catalog.lower[i], query, 1, true)
		if catalog.ids[i] == number or at == 1 then
			n = n + 1
			result[n] = i
		elseif at then
			m = m + 1
			later[m] = i
		end
	end
	for i = 1, m do
		result[n + i] = later[i]
	end
	return result, n + m
end

function M.DescribeDisplay(displayID)
	local catalog = M.GetCreatureCatalog()
	local index = catalog.byID[displayID]
	if index then
		return catalog.names[index] .. " (" .. displayID .. ")"
	end
	return "display " .. displayID
end

-- The item's name from the client's cache, or else from the catalogue: the
-- slot's own list first, then the others (a shirt can be morphed onto the chest).
function M.DescribeItem(itemID, slot)
	local ok, name = pcall(GetItemInfo, itemID)
	if not (ok and name) then
		name = nil
		local lists = { slot }
		for i = 1, table.getn(SLOT_ORDER) do
			table.insert(lists, SLOT_ORDER[i])
		end
		for i = 1, table.getn(lists) do
			local catalog = SLOT_NAMES[lists[i]] and M.GetItemCatalog(lists[i])
			local index = catalog and catalog.byID[itemID]
			if index then
				name = catalog.names[index]
				break
			end
		end
	end
	if name then
		return "[" .. name .. "] (" .. itemID .. ")"
	end
	return "item " .. itemID
end

function M.DescribeOutfit(outfit)
	local look = "your own model"
	if outfit.display then
		look = M.DescribeDisplay(outfit.display)
	elseif outfit.race then
		look = M.DescribeBody(outfit.race, outfit.gender)
	end
	local count = 0
	for _ in pairs(outfit.items) do
		count = count + 1
	end
	if count == 1 then
		return look .. ", 1 item"
	end
	return look .. ", " .. count .. " items"
end

-- State ---------------------------------------------------------------------

-- Drops anything that isn't a usable ID, e.g. from a hand-edited file.
local function SanitizeOutfit(outfit)
	outfit.display = ParseID(outfit.display)
	if outfit.display == 0 then
		outfit.display = nil
	end
	if not (type(outfit.race) == "number" and RACES[outfit.race]) then
		outfit.race = nil
	end
	if outfit.gender ~= 1 then
		outfit.gender = 0
	end
	if type(outfit.items) ~= "table" then
		outfit.items = {}
	end
	for slot, itemID in pairs(outfit.items) do
		itemID = ParseID(itemID)
		if not SLOT_NAMES[slot] or itemID == 0 then
			itemID = nil
		end
		outfit.items[slot] = itemID
	end
	return outfit
end

local function CopyOutfit(outfit)
	local copy = { display = outfit.display, race = outfit.race, gender = outfit.gender, items = {} }
	for slot, itemID in pairs(outfit.items) do
		copy.items[slot] = itemID
	end
	return copy
end

local function InitDB()
	if db then
		return
	end
	if type(DmorphOctoDB) ~= "table" then
		DmorphOctoDB = {}
	end
	db = SanitizeOutfit(DmorphOctoDB)
	if type(DmorphOctoAccount) ~= "table" then
		DmorphOctoAccount = {}
	end
	account = DmorphOctoAccount
	if type(account.outfits) ~= "table" then
		account.outfits = {}
	end
	for name, outfit in pairs(account.outfits) do
		if type(name) == "string" and type(outfit) == "table" then
			SanitizeOutfit(outfit)
		else
			account.outfits[name] = nil
		end
	end
end

function M.GetState()
	InitDB()
	return db
end

function M.GetAccount()
	InitDB()
	return account
end

function M.GetNative()
	return nativeRace, nativeGender
end

-- Called after every change, so the window can redraw.
function M.RegisterListener(fn)
	table.insert(listeners, fn)
end

local function Notify()
	for i = 1, table.getn(listeners) do
		listeners[i]()
	end
end

local function CaptureNative()
	nativeRace, nativeGender = nil, nil
	local ok, _, native = pcall(UnitDisplayInfo, "player")
	if ok and native then
		for race = 1, table.getn(RACES) do
			if RACES[race].male == native then
				nativeRace, nativeGender = race, 0
			elseif RACES[race].female == native then
				nativeRace, nativeGender = race, 1
			end
		end
	end
	if not nativeRace then
		local _, token = UnitRace("player")
		nativeRace = RACE_TOKENS[strupper(token or "")]
		local sex = UnitSex("player")
		if sex == 3 then
			nativeGender = 1
		elseif sex == 2 then
			nativeGender = 0
		end
	end
end

-- Runs once per UI session, before the first morph is applied.
local function EnsureSession()
	if sessionReady then
		return
	end
	-- VanillaHelpers' overrides can outlive a /reload, and a race morph also
	-- replaces the native model ID, so drop ours before reading the real one.
	if db.display or db.race then
		Morph(SetUnitDisplayID, "player", nil)
	end
	CaptureNative()
	sessionReady = true
end

-- Every action that morphs starts here.
local function Begin()
	InitDB()
	if not HasMorphAPI() then
		return false
	end
	EnsureSession()
	return true
end

-- .morph and the race/gender morph share UNIT_FIELD_DISPLAYID: last one wins.
local function BodyDisplayID()
	if db.display then
		return db.display
	end
	if db.race then
		return RaceModel(db.race, db.gender)
	end
end

local function ApplyBody()
	return Morph(SetUnitDisplayID, "player", BodyDisplayID())
end

local function ApplyItem(slot)
	return Morph(SetUnitVisibleItemID, "player", slot, db.items[slot])
end

local function ApplySaved()
	if not Begin() then
		return
	end
	if BodyDisplayID() then
		ApplyBody()
	end
	for slot in pairs(db.items) do
		ApplyItem(slot)
	end
	Notify()
end

-- Turns the outcome of the VanillaHelpers calls into (ok, message).
local function Result(ok, err, message)
	Notify()
	if ok then
		return true, message
	end
	return false, "|cffff5555" .. tostring(err) .. "|r"
end

-- Actions: each returns ok, message -----------------------------------------

function M.ResetModel()
	if not Begin() then
		return false, MISSING_API
	end
	db.display, db.race, db.gender = nil, nil, 0
	local ok, err = ApplyBody()
	return Result(ok, err, "Model reset.")
end

function M.ResetAll()
	if not Begin() then
		return false, MISSING_API
	end
	db.display, db.race, db.gender = nil, nil, 0
	local ok, err = ApplyBody()
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		db.items[slot] = nil
		local slotOK, slotErr = ApplyItem(slot)
		if ok and not slotOK then
			ok, err = slotOK, slotErr
		end
	end
	return Result(ok, err, "Model and items reset.")
end

function M.SetDisplay(displayID)
	if not Begin() then
		return false, MISSING_API
	end
	displayID = ParseID(displayID)
	if not displayID then
		return false, "Display IDs are whole numbers."
	end
	if displayID == 0 then
		return M.ResetModel()
	end
	db.display, db.race, db.gender = displayID, nil, 0
	local ok, err = ApplyBody()
	return Result(ok, err, "Morphed into " .. M.DescribeDisplay(displayID) .. ".")
end

-- The race and gender your model shows now, morphed or your own.
function M.GetBodyRace()
	InitDB()
	if db.race then
		return db.race, db.gender
	end
	return nativeRace, nativeGender or 0
end

-- gender is 0 or 1; anything else keeps the current gender.
function M.SetRace(race, gender)
	if not Begin() then
		return false, MISSING_API
	end
	if not RACES[race] then
		return false, "Unknown race. Races: " .. RaceList()
	end
	if gender ~= 0 and gender ~= 1 then
		local _
		_, gender = M.GetBodyRace()
	end
	if race == nativeRace and gender == nativeGender then
		db.display, db.race, db.gender = nil, nil, 0
	else
		db.display, db.race, db.gender = nil, race, gender
	end
	local ok, err = ApplyBody()
	return Result(ok, err, "Race: " .. M.DescribeBody(race, gender) .. ".")
end

function M.ToggleGender()
	if not Begin() then
		return false, MISSING_API
	end
	local race, gender = M.GetBodyRace()
	if not race then
		return false, "Couldn't detect your race, pick one first."
	end
	return M.SetRace(race, 1 - gender)
end

-- itemID 0 resets the slot.
function M.SetItem(slot, itemID)
	if not Begin() then
		return false, MISSING_API
	end
	if not SLOT_NAMES[slot] then
		return false, "Neck, rings and trinkets don't show on your model. Slots: " .. SlotList()
	end
	itemID = ParseID(itemID)
	if not itemID then
		return false, "Item IDs are whole numbers."
	end
	if itemID == 0 then
		itemID = nil
	end
	db.items[slot] = itemID
	local ok, err = ApplyItem(slot)
	if itemID then
		return Result(ok, err, SLOT_NAMES[slot] .. ": " .. M.DescribeItem(itemID, slot) .. ".")
	end
	return Result(ok, err, SLOT_NAMES[slot] .. " reset.")
end

-- Wardrobe ------------------------------------------------------------------

function M.GetOutfitNames()
	InitDB()
	local names = {}
	for name in pairs(account.outfits) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		return strlower(a) < strlower(b)
	end)
	return names
end

function M.GetOutfit(name)
	InitDB()
	return account.outfits[name]
end

-- The saved name matching text, ignoring case.
function M.FindOutfit(text)
	InitDB()
	text = strlower(Trim(text))
	for name in pairs(account.outfits) do
		if strlower(name) == text then
			return name
		end
	end
end

function M.SaveOutfit(name)
	InitDB()
	name = Trim(name)
	if name == "" then
		return false, "Type a name for the outfit first."
	end
	local replaced = account.outfits[name] ~= nil
	account.outfits[name] = CopyOutfit(db)
	Notify()
	if replaced then
		return true, "Updated outfit \"" .. name .. "\"."
	end
	return true, "Saved outfit \"" .. name .. "\"."
end

-- Puts on the whole outfit: slots it doesn't morph go back to your own gear.
function M.LoadOutfit(name)
	if not Begin() then
		return false, MISSING_API
	end
	local outfit = account.outfits[name]
	if not outfit then
		return false, "There is no outfit called \"" .. tostring(name) .. "\"."
	end
	db.display, db.race, db.gender = outfit.display, outfit.race, outfit.gender
	if db.race == nativeRace and db.gender == nativeGender then
		db.race, db.gender = nil, 0
	end
	local ok, err = ApplyBody()
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		db.items[slot] = outfit.items[slot]
		local slotOK, slotErr = ApplyItem(slot)
		if ok and not slotOK then
			ok, err = slotOK, slotErr
		end
	end
	return Result(ok, err, "Loaded outfit \"" .. name .. "\".")
end

function M.DeleteOutfit(name)
	InitDB()
	if not account.outfits[name] then
		return false, "There is no outfit called \"" .. tostring(name) .. "\"."
	end
	account.outfits[name] = nil
	Notify()
	return true, "Deleted outfit \"" .. name .. "\"."
end

-- Chat commands -------------------------------------------------------------

local function ShowHelp()
	Print("v" .. VERSION .. " - /dmorph opens the morph window. Chat commands:")
	Print(".morph <displayID> - morph into any model (.morph 0 resets)")
	Print(".race <1-10> - " .. RaceList())
	Print(".gender - swap the gender of your race or race morph")
	Print(".item <slot> <itemID or item link> - morph a visible item (itemID 0 resets the slot). Slots: " .. SlotList())
	Print(".demorph - reset your model (DMorph's F5); .demorph all - reset model and items (F10)")
	Print(".outfit [name] - list or put on saved outfits; .outfit save <name>; .outfit delete <name>")
	Print(".dmorph status - show what is morphed. Keys: Key Bindings > DMorph.")
	if not HasMorphAPI() then
		Print(MISSING_API)
	end
end

local function ShowStatus()
	if not HasMorphAPI() then
		Print(MISSING_API)
	elseif type(VANILLAHELPERS_VERSION) == "number" then
		local v = VANILLAHELPERS_VERSION
		Print(format("VanillaHelpers v%d.%d.%d is loaded.", math.floor(v / 10000),
			math.floor(math.mod(v, 10000) / 100), math.mod(v, 100)))
	end
	if nativeRace then
		Print("Your character: " .. M.DescribeBody(nativeRace, nativeGender) .. ".")
	end
	if db.display then
		Print("Model: " .. M.DescribeDisplay(db.display) .. ".")
	elseif db.race then
		Print("Model: " .. M.DescribeBody(db.race, db.gender) .. ".")
	else
		Print("Model: not morphed.")
	end
	local list = ""
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		if db.items[slot] then
			list = list .. ", " .. SLOT_NAMES[slot] .. " " .. M.DescribeItem(db.items[slot], slot)
		end
	end
	if list == "" then
		Print("Items: not morphed.")
	else
		Print("Items: " .. strsub(list, 3) .. ".")
	end
end

local commands = {}

function commands.morph(args)
	local displayID = ParseID(args[1] or "0")
	if not displayID then
		return Print("Usage: .morph <displayID>  (.morph 0 resets)")
	end
	Report(M.SetDisplay(displayID))
end

function commands.race(args)
	local word = strlower(args[1] or "")
	local race = RACE_ALIASES[word] or ParseID(word)
	if race == 11 then
		return Print("Draenei don't exist in the 1.12 client. Races: " .. RaceList())
	end
	if not race or not RACES[race] then
		return Print("Usage: .race <1-10>  (" .. RaceList() .. ")")
	end
	Report(M.SetRace(race))
end

function commands.gender()
	Report(M.ToggleGender())
end

function commands.item(args, line)
	local word = strlower(args[1] or "")
	local slot = SLOT_ALIASES[word] or ParseID(word)
	if not slot or slot < 1 or slot > 19 then
		return Print("Usage: .item <slot> <itemID>  (slots: " .. SlotList() .. ")")
	end
	-- Accept a shift-clicked item link as well as a plain ID.
	local _, _, linkID = strfind(line, "item:(%d+)")
	local itemID = ParseID(linkID or args[2] or "0")
	if not itemID then
		return Print("Usage: .item <slot> <itemID>  (itemID 0 resets the slot)")
	end
	Report(M.SetItem(slot, itemID))
end

function commands.scale()
	Print(".scale isn't available on OctoWoW: VanillaHelpers has no API for model scale.")
end

function commands.demorph(args)
	if strlower(args[1] or "") == "all" then
		return Report(M.ResetAll())
	end
	Report(M.ResetModel())
end

function commands.outfit(args, line)
	local _, _, rest = strfind(line, "^%S+%s*(.-)%s*$")
	local action = strlower(args[1] or "")
	local _, _, name = strfind(rest, "^%S+%s*(.-)$")
	if rest == "" then
		local names = M.GetOutfitNames()
		if table.getn(names) == 0 then
			return Print("No outfits saved yet. Save your current look with .outfit save <name>.")
		end
		return Print("Outfits: " .. table.concat(names, ", ") .. ".")
	elseif action == "save" then
		return Report(M.SaveOutfit(name))
	elseif action == "delete" then
		return Report(M.DeleteOutfit(M.FindOutfit(name) or name))
	end
	Report(M.LoadOutfit(M.FindOutfit(rest) or rest))
end

function commands.dmorph(args)
	local action = strlower(args[1] or "")
	if action == "status" then
		return ShowStatus()
	elseif action == "" and M.ToggleUI then
		return M.ToggleUI()
	end
	ShowHelp()
end

-- Runs a command line such as "morph 4527". Returns false when the first word
-- isn't one of ours, so the caller can pass the text on untouched.
local function RunCommand(line)
	local args = {}
	for word in string.gfind(line, "%S+") do
		table.insert(args, word)
	end
	local name = strlower(table.remove(args, 1) or "")
	local handler = commands[name]
	if not handler then
		return false
	end
	InitDB()
	if HasMorphAPI() then
		EnsureSession()
	end
	handler(args, line)
	return true
end

-- DMorph's interface: commands typed into chat with a leading dot. Anything
-- that isn't one of our commands still goes to the server as before.
local orig_SendChatMessage = SendChatMessage
function SendChatMessage(msg, chatType, language, channel)
	if type(msg) == "string" then
		local _, _, line = strfind(msg, "^%s*%.(.*)$")
		if line and RunCommand(line) then
			return
		end
	end
	return orig_SendChatMessage(msg, chatType, language, channel)
end

SLASH_DMORPHOCTO1 = "/dmorph"
SlashCmdList["DMORPHOCTO"] = function(msg)
	local _, _, line = strfind(msg or "", "^%s*%.?(.*)$")
	if not RunCommand(line) then
		RunCommand("dmorph " .. line)
	end
end

-- Key bindings (Bindings.xml); the reset keys stand in for DMorph's F5/F10.
BINDING_HEADER_DMORPHOCTO = "DMorph"
BINDING_NAME_DMORPHOCTO_TOGGLE = "Open or close the DMorph window"
BINDING_NAME_DMORPHOCTO_RESET = "Reset model (DMorph F5)"
BINDING_NAME_DMORPHOCTO_RESETALL = "Reset model and items (DMorph F10)"

function DmorphOcto_ToggleUI()
	RunCommand("dmorph")
end

function DmorphOcto_Reset()
	RunCommand("demorph")
end

function DmorphOcto_ResetAll()
	RunCommand("demorph all")
end

-- Events --------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:Hide()
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	InitDB()
	if event ~= "PLAYER_ENTERING_WORLD" then
		return
	end
	if not HasMorphAPI() then
		if not warnedMissingAPI then
			warnedMissingAPI = true
			Print(MISSING_API)
		end
		return
	end
	-- Fires after every loading screen; give the client a moment to build the
	-- player model before re-applying the saved morph.
	pendingApply = 0.5
	frame:Show()
end)
frame:SetScript("OnUpdate", function()
	pendingApply = pendingApply - arg1
	if pendingApply <= 0 then
		frame:Hide()
		ApplySaved()
	end
end)
