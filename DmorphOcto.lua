-- DMorph for OctoWoW
--
-- Brings DMorph's chat commands (.morph, .race, .gender, .item) to the
-- OctoWoW 1.12.1 client. DMorph itself is a DLL built for WotLK 3.3.5a
-- (build 12340) with that client's addresses hardcoded, so it can't run on a
-- 1.12 client. This addon drives the morph API of VanillaHelpers.dll
-- (v1.1.0+) instead: OctoLauncher ships it as the "vanillaHelpers" mod and it
-- is built for the 1.12.1 client.
--
-- The client runs Lua 5.0: no #, no %, no string.match, no select().

local VERSION = "1.0.0"
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

local db -- DmorphOctoDB: display, race, gender (0 male, 1 female), items[slot]
local nativeRace, nativeGender
local sessionReady = false
local warnedMissingAPI = false
local pendingApply

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function HasMorphAPI()
	return type(SetUnitDisplayID) == "function"
		and type(SetUnitVisibleItemID) == "function"
		and type(UnitDisplayInfo) == "function"
end

-- VanillaHelpers reports bad input with lua_error, so every call is guarded.
-- A nil value clears that override.
local function Morph(fn, a1, a2, a3)
	local ok, err = pcall(fn, a1, a2, a3)
	if not ok then
		Print("|cffff5555" .. tostring(err) .. "|r")
	end
	return ok
end

local function ParseID(text)
	local n = tonumber(text or "")
	if n and n >= 0 and n <= 2147483647 and n == math.floor(n) then
		return n
	end
end

local function RaceModel(race, gender)
	if gender == 1 then
		return RACES[race].female
	end
	return RACES[race].male
end

local function DescribeBody(race, gender)
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

local function ItemLabel(itemID)
	local ok, name = pcall(GetItemInfo, itemID)
	if ok and name then
		return "[" .. name .. "] (" .. itemID .. ")"
	end
	return "item " .. itemID
end

local function InitDB()
	if db then
		return
	end
	if type(DmorphOctoDB) ~= "table" then
		DmorphOctoDB = {}
	end
	db = DmorphOctoDB
	if type(db.items) ~= "table" then
		db.items = {}
	end
	-- Drop anything that isn't a usable ID, e.g. from a hand-edited file.
	db.display = ParseID(db.display)
	if db.display == 0 then
		db.display = nil
	end
	if not (type(db.race) == "number" and RACES[db.race]) then
		db.race = nil
	end
	if db.gender ~= 1 then
		db.gender = 0
	end
	for slot, itemID in pairs(db.items) do
		itemID = ParseID(itemID)
		if not SLOT_NAMES[slot] or itemID == 0 then
			itemID = nil
		end
		db.items[slot] = itemID
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
	if not HasMorphAPI() then
		return
	end
	EnsureSession()
	if BodyDisplayID() then
		ApplyBody()
	end
	for slot in pairs(db.items) do
		ApplyItem(slot)
	end
end

local function SetRace(race, gender)
	if race == nativeRace and gender == nativeGender then
		db.display, db.race, db.gender = nil, nil, 0
	else
		db.display, db.race, db.gender = nil, race, gender
	end
	if ApplyBody() then
		Print("Race: " .. DescribeBody(race, gender) .. ".")
	end
end

local function ShowHelp()
	Print("v" .. VERSION .. " - type these in chat, or after /dmorph:")
	Print(".morph <displayID> - morph into any model (.morph 0 resets)")
	Print(".race <1-10> - " .. RaceList())
	Print(".gender - swap the gender of your race or race morph")
	Print(".item <slot> <itemID or item link> - morph a visible item (itemID 0 resets the slot). Slots: " .. SlotList())
	Print(".demorph - reset your model (DMorph's F5); .demorph all - reset model and items (F10)")
	Print(".dmorph status - show what is morphed. Reset keys: Key Bindings > DMorph.")
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
		Print("Your character: " .. DescribeBody(nativeRace, nativeGender) .. ".")
	end
	if db.display then
		Print("Model: display " .. db.display .. ".")
	elseif db.race then
		Print("Model: " .. DescribeBody(db.race, db.gender) .. ".")
	else
		Print("Model: not morphed.")
	end
	local list = ""
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		if db.items[slot] then
			list = list .. ", " .. SLOT_NAMES[slot] .. " " .. ItemLabel(db.items[slot])
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
	if displayID == 0 then
		return commands.demorph({})
	end
	db.display, db.race, db.gender = displayID, nil, 0
	if ApplyBody() then
		Print("Morphed into display " .. displayID .. ".")
	end
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
	local gender = nativeGender or 0
	if db.race then
		gender = db.gender
	end
	SetRace(race, gender)
end

function commands.gender()
	local race, gender = nativeRace, nativeGender
	if db.race then
		race, gender = db.race, db.gender
	end
	if not race then
		return Print("Couldn't detect your race, pick one with .race first.")
	end
	SetRace(race, 1 - (gender or 0))
end

function commands.item(args, line)
	local word = strlower(args[1] or "")
	local slot = SLOT_ALIASES[word] or ParseID(word)
	if slot and slot >= 1 and slot <= 19 and not SLOT_NAMES[slot] then
		return Print("Neck, rings and trinkets don't show on your model. Slots: " .. SlotList())
	end
	if not slot or not SLOT_NAMES[slot] then
		return Print("Usage: .item <slot> <itemID>  (slots: " .. SlotList() .. ")")
	end
	-- Accept a shift-clicked item link as well as a plain ID.
	local _, _, linkID = strfind(line, "item:(%d+)")
	local itemID = ParseID(linkID or args[2] or "0")
	if not itemID then
		return Print("Usage: .item <slot> <itemID>  (itemID 0 resets the slot)")
	end
	if itemID == 0 then
		itemID = nil
	end
	db.items[slot] = itemID
	if ApplyItem(slot) then
		if itemID then
			Print(SLOT_NAMES[slot] .. ": " .. ItemLabel(itemID) .. ".")
		else
			Print(SLOT_NAMES[slot] .. " reset.")
		end
	end
end

function commands.scale()
	Print(".scale isn't available on OctoWoW: VanillaHelpers has no API for model scale.")
end

function commands.demorph(args)
	db.display, db.race, db.gender = nil, nil, 0
	local ok = Morph(SetUnitDisplayID, "player", nil)
	if strlower(args[1] or "") ~= "all" then
		if ok then
			Print("Model reset.")
		end
		return
	end
	for i = 1, table.getn(SLOT_ORDER) do
		local slot = SLOT_ORDER[i]
		db.items[slot] = nil
		ok = Morph(SetUnitVisibleItemID, "player", slot, nil) and ok
	end
	if ok then
		Print("Model and items reset.")
	end
end

function commands.dmorph(args)
	if strlower(args[1] or "") == "status" then
		return ShowStatus()
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
	elseif name ~= "dmorph" then
		Print(MISSING_API)
		return true
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

-- Key bindings (Bindings.xml) standing in for DMorph's F5 and F10 hotkeys.
BINDING_HEADER_DMORPHOCTO = "DMorph"
BINDING_NAME_DMORPHOCTO_RESET = "Reset model (DMorph F5)"
BINDING_NAME_DMORPHOCTO_RESETALL = "Reset model and items (DMorph F10)"

function DmorphOcto_Reset()
	RunCommand("demorph")
end

function DmorphOcto_ResetAll()
	RunCommand("demorph all")
end

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
