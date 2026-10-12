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

local VERSION = "2.12.0"
local PREFIX = "|cff33ff99DMorph|r: "
-- VANILLAHELPERS_VERSION is major * 10000 + minor * 100 + patch; morphing
-- came in v1.1.0. Older versions load and set it, but can't morph.
local MORPH_VERSION = 10100

local function VersionText(v)
	return format("%d.%d.%d", math.floor(v / 10000), math.floor(math.mod(v, 10000) / 100), math.mod(v, 100))
end

-- The other client mods that load the same way as VanillaHelpers. If none
-- of them runs either, the game wasn't started through OctoLauncher.
local function OtherClientMods()
	local mods = {}
	if SUPERWOW_VERSION then
		table.insert(mods, "SuperWoW")
	end
	if type(C_Item) == "table" then
		table.insert(mods, "ClassicAPI")
	end
	if type(GetNampowerVersion) == "function" then
		table.insert(mods, "nampower")
	end
	if type(UnitXP) == "function" then
		table.insert(mods, "UnitXP")
	end
	return mods
end

-- Why morphing doesn't work, and how to fix it (one chat-sized message).
local function MissingAPI()
	if type(VANILLAHELPERS_VERSION) == "number" and VANILLAHELPERS_VERSION < MORPH_VERSION then
		return "VanillaHelpers v" .. VersionText(VANILLAHELPERS_VERSION) .. " is running, but morphing needs v1.1.0 or newer. "
			.. "Update the 'vanillaHelpers' mod in OctoLauncher, close the game and start it again."
	elseif type(VANILLAHELPERS_VERSION) == "number" then
		return "VanillaHelpers is running but its morph functions are missing: reinstall the 'vanillaHelpers' mod in OctoLauncher "
			.. "and restart the game."
	elseif table.getn(OtherClientMods()) > 0 then
		return "VanillaHelpers isn't running, so morphing is unavailable (your other client mods are, so only it is missing). "
			.. "Tick the 'vanillaHelpers' mod in OctoLauncher, close the game completely and press Play again."
	end
	return "VanillaHelpers isn't running, so morphing is unavailable. No client mods are running at all: start the game "
		.. "from OctoLauncher (not WoW.exe), with the 'vanillaHelpers' mod ticked. Close the game completely first."
end

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
-- The slots whose enchant glow DmorphHelper can change.
local GLOW_SLOT = { [16] = true, [17] = true, [18] = true }
local SLOT_ALIASES = {
	head = 1, shoulder = 3, shoulders = 3, shirt = 4, chest = 5, waist = 6,
	belt = 6, legs = 7, feet = 8, boots = 8, wrist = 9, wrists = 9, hands = 10,
	gloves = 10, back = 15, cloak = 15, mainhand = 16, offhand = 17,
	ranged = 18, tabard = 19,
}

DmorphOcto = {
	VERSION = VERSION,
	MissingAPI = MissingAPI,
	RACES = RACES,
	SLOT_ORDER = SLOT_ORDER,
	SLOT_NAMES = SLOT_NAMES,
	GLOW_SLOTS = { 16, 17, 18 },
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
local sets
local looks = {}
local InitDB -- defined under State; the catalogue needs it first

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

-- Data/*.lua hold the catalogue as text so the game loads it quickly; each
-- list is parsed the first time it's needed. An entry is
-- { id, name, lowercase name, quality, kind }.
local function NewCatalog()
	return { ids = {}, names = {}, lower = {}, quality = {}, kind = {}, byID = {}, count = 0 }
end

local function AddEntry(catalog, id, name, quality, kind)
	local n = catalog.count + 1
	catalog.count = n
	catalog.ids[n], catalog.names[n], catalog.lower[n] = id, name, strlower(name)
	catalog.quality[n], catalog.kind[n] = quality, kind
	if not catalog.byID[id] then
		catalog.byID[id] = n
	end
end

local function Before(a, b)
	return a[3] < b[3] or (a[3] == b[3] and a[1] < b[1])
end

-- Merges two name-sorted lists. The data files are sorted the way Lua
-- compares strings, so this is one pass.
local function Merge(a, n, b, m)
	local out, k, i, j = {}, 0, 1, 1
	while i <= n or j <= m do
		local x, y = a[i], b[j]
		if not y or (x and not Before(y, x)) then
			i = i + 1
		else
			x, j = y, j + 1
		end
		k = k + 1
		out[k] = x
	end
	return out, k
end

local function Fill(catalog, list, count)
	for i = 1, count do
		local e = list[i]
		AddEntry(catalog, e[1], e[2], e[4], e[5])
	end
	return catalog
end

-- Creature models by kind: a creature's name, or named after the model file;
-- 2 and 3 are the same for the models OctoWoW added to the stock 1.12.1 client.
M.KIND_CREATURE, M.KIND_MODEL, M.KIND_NEW, M.KIND_NEW_MODEL = 0, 1, 2, 3
-- Models brought over from later expansions by the porting tool, listed in
-- Data/Ported.lua (only on a PC that has the tool's patch-Z.mpq).
M.KIND_PORTED = 4
M.MODEL_FILTERS = {
	{ text = "All models" },
	{ text = "Creatures", kinds = { [0] = true, [2] = true } },
	{ text = "Bosses", tag = "boss" },
	{ text = "Rare creatures", tag = "rare" },
	{ text = "Mounts", tag = "mount" },
	{ text = "Other models", kinds = { [1] = true, [3] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true, [3] = true } },
	{ text = "Ported (later expansions)", kinds = { [4] = true } },
}
-- Items and sets are kind 0 (stock 1.12.1) or 2 (added by Turtle WoW / OctoWoW).
M.ITEM_FILTERS = {
	{ text = "All items" },
	{ text = "1.12 items", kinds = { [0] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true } },
	{ text = "Ported (later expansions)", kinds = { [4] = true } },
}
M.SET_FILTERS = {
	{ text = "All sets" },
	{ text = "1.12 sets", kinds = { [0] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true } },
}
-- Item and set quality, as GetItemInfo() numbers it.
-- Item kinds (class * 100 + subclass, Data/ItemTypes.lua), in the order the
-- filter lists them: armour by material, then weapons.
M.ITEM_TYPES = {
	{ 401, "Cloth" }, { 402, "Leather" }, { 403, "Mail" }, { 404, "Plate" }, { 406, "Shield" },
	{ 400, "Miscellaneous" }, { 407, "Libram" }, { 408, "Idol" }, { 409, "Totem" },
	{ 215, "Dagger" }, { 213, "Fist weapon" }, { 200, "One-handed axe" }, { 204, "One-handed mace" },
	{ 207, "One-handed sword" }, { 201, "Two-handed axe" }, { 205, "Two-handed mace" },
	{ 208, "Two-handed sword" }, { 206, "Polearm" }, { 210, "Staff" }, { 217, "Spear" }, { 202, "Bow" },
	{ 218, "Crossbow" }, { 203, "Gun" }, { 216, "Thrown" }, { 219, "Wand" }, { 214, "Miscellaneous weapon" },
	{ 220, "Fishing pole" },
}
M.ITEM_TYPE_NAMES = {}
for i = 1, table.getn(M.ITEM_TYPES) do
	M.ITEM_TYPE_NAMES[M.ITEM_TYPES[i][1]] = M.ITEM_TYPES[i][2]
end
-- GetItemInfo's English sub-types, for items no data file knows.
local SUBTYPES = {
	Armor = { Miscellaneous = 400, Cloth = 401, Leather = 402, Mail = 403, Plate = 404, Shields = 406,
		Librams = 407, Idols = 408, Totems = 409 },
	Weapon = { ["One-Handed Axes"] = 200, ["Two-Handed Axes"] = 201, Bows = 202, Guns = 203,
		["One-Handed Maces"] = 204, ["Two-Handed Maces"] = 205, Polearms = 206, ["One-Handed Swords"] = 207,
		["Two-Handed Swords"] = 208, Staves = 210, ["Fist Weapons"] = 213, Miscellaneous = 214, Daggers = 215,
		Thrown = 216, Spears = 217, Crossbows = 218, Wands = 219, ["Fishing Pole"] = 220 },
}

M.QUALITY_FILTERS = {
	{ text = "Any quality" },
	{ text = "Poor", quality = 0 },
	{ text = "Common", quality = 1 },
	{ text = "Uncommon", quality = 2 },
	{ text = "Rare", quality = 3 },
	{ text = "Epic", quality = 4 },
	{ text = "Legendary", quality = 5 },
}

-- Display and item IDs that can't show in this client: Data/HiddenModels.lua
-- and Data/HiddenItems.lua, written by tools/build_models.ps1 and
-- tools/build_items.ps1 from the game's own files.
local hiddenModels, hiddenItems

local function ReadIDs(text)
	local set = {}
	for id in string.gfind(text or "", "%d+") do
		set[tonumber(id)] = true
	end
	return set
end

local function HiddenModels()
	if not hiddenModels then
		hiddenModels = ReadIDs(DmorphOcto_HiddenModels)
		DmorphOcto_HiddenModels = nil
	end
	return hiddenModels
end

local function HiddenItems()
	if not hiddenItems then
		hiddenItems = ReadIDs(DmorphOcto_HiddenItems)
		DmorphOcto_HiddenItems = nil
	end
	return hiddenItems
end

-- Display IDs from Data/Ported.lua: only this PC has their models, so they
-- are never sent to or taken from other DMorph users.
local portedIDs = {}
function M.IsPorted(displayID)
	M.GetCreatureCatalog()
	return portedIDs[tonumber(displayID or 0)] == true
end

-- Creatures.lua (named creatures) and Models.lua (every other display ID the
-- client has) together list every model, less the ones that can't show.
function M.GetCreatureCatalog()
	if creatures then
		return creatures
	end
	local hidden = HiddenModels()
	local named, other, n, m = {}, {}, 0, 0
	for id, name in string.gfind(DmorphOcto_CreatureData or "", "(%d+)\t([^\r\n]+)") do
		id = tonumber(id)
		if not hidden[id] then
			n = n + 1
			named[n] = { id, name, strlower(name), 0, M.KIND_CREATURE }
		end
	end
	for id, kind, name in string.gfind(DmorphOcto_ModelData or "", "(%d+)\t(%d)\t([^\r\n]+)") do
		id = tonumber(id)
		if not hidden[id] then
			m = m + 1
			other[m] = { id, name, strlower(name), 0, tonumber(kind) }
		end
	end
	DmorphOcto_CreatureData, DmorphOcto_ModelData = nil, nil -- the parsed tables replace the text
	local all, count = Merge(named, n, other, m)
	-- Data/Ported.lua: displayID<TAB>name<TAB>tags ("mount").
	local ported, p, portedMounts = {}, 0, {}
	for id, name, tags in string.gfind(DmorphOcto_PortedData or "", "(%d+)\t([^\t\r\n]+)\t?([^\r\n]*)") do
		id = tonumber(id)
		p = p + 1
		ported[p] = { id, name, strlower(name), 0, M.KIND_PORTED }
		portedIDs[id] = true
		if strfind(tags, "mount") then
			portedMounts[id] = true
		end
	end
	DmorphOcto_PortedData = nil
	table.sort(ported, Before)
	creatures = Fill(NewCatalog(), Merge(all, count, ported, p))
	-- Tags for the filters: bosses and rares by display and name, mounts by
	-- display. Data/ModelTags.lua (OctoWoW's client and Turtle WoW's ranks) and
	-- Data/ClassicTags.lua (the 1.12.1 database); a boss stays a boss.
	local byName, mounts = {}, {}
	for _, text in ipairs({ DmorphOcto_TagData or "", DmorphOcto_ClassicTagData or "" }) do
		for id, tag, name in string.gfind(text, "(%d+)\t(%a+)\t([^\r\n]*)") do
			if tag == "mount" then
				mounts[tonumber(id)] = true
			else
				local key = id .. "\t" .. strlower(name)
				if byName[key] ~= "boss" then
					byName[key] = tag
				end
			end
		end
	end
	DmorphOcto_TagData, DmorphOcto_ClassicTagData = nil, nil
	for id in pairs(portedMounts) do
		mounts[id] = true
	end
	creatures.tags = {}
	for i = 1, creatures.count do
		local tag = byName[creatures.ids[i] .. "\t" .. creatures.lower[i]]
		if mounts[creatures.ids[i]] then
			tag = (tag and (tag .. " ") or "") .. "mount"
		end
		creatures.tags[i] = tag
	end
	return creatures
end

-- Inventory slots by the INVTYPE_ name GetItemInfo() returns.
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_CLOAK = { 15 }, INVTYPE_TABARD = { 19 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
}

-- Developers' test items ("Kazgrim Test Helm", "1000 Test dagger 60 blue"):
-- "test" as a word in the name.
local function IsTestItem(lower)
	local at, stop = strfind(lower, "test", 1, true)
	while at do
		if not strfind(strsub(lower, at - 1, at - 1), "%a") and not strfind(strsub(lower, stop + 1, stop + 1), "%a") then
			return true
		end
		at, stop = strfind(lower, "test", stop + 1, true)
	end
	return false
end

local function ParseItems(text, kind, list, n, skip)
	local hidden = HiddenItems()
	for id, quality, name in string.gfind(text or "", "(%d+)\t(%d)\t([^\r\n]+)") do
		id = tonumber(id)
		if not ((skip and skip[id]) or hidden[id] or IsTestItem(strlower(name))) then
			n = n + 1
			list[n] = { id, name, strlower(name), tonumber(quality), kind }
		end
	end
	return list, n
end

-- Items the game told us about in this or an earlier session (see Item
-- lookup), saved as DmorphOctoAccount.itemInfo[id] = "slots<TAB>quality<TAB>name".
local function LearnedItems(slot, skip)
	local list, n, hidden = {}, 0, HiddenItems()
	for id, info in pairs(account.itemInfo) do
		if info and not skip[id] and not hidden[id] then
			local _, _, slots, quality, name = strfind(info, "^([%d,]+)\t(%-?%d+)\t(.+)$")
			if slots and strfind("," .. slots .. ",", "," .. slot .. ",", 1, true) and not IsTestItem(strlower(name)) then
				n = n + 1
				list[n] = { id, name, strlower(name), tonumber(quality), M.KIND_NEW }
			end
		end
	end
	table.sort(list, Before)
	return list, n
end

-- itemID -> kind, from Data/ItemTypes.lua and ItemsExtra.lua's item cache
-- kinds, read once.
local itemTypes
local function ReadItemTypes()
	itemTypes = {}
	for _, text in ipairs({ DmorphOcto_ItemTypeData or "", DmorphOcto_ItemTypeExtra or "" }) do
		for kind, list in string.gfind(text, "(%d+)\t([%d,]+)") do
			kind = tonumber(kind)
			for id in string.gfind(list, "%d+") do
				itemTypes[tonumber(id)] = kind
			end
		end
	end
	DmorphOcto_ItemTypeData, DmorphOcto_ItemTypeExtra = nil, nil
end

-- Ported weapons (Data/Ported.lua, DmorphOcto_PortedItems): item IDs only this
-- PC has. DmorphHelper v10 answers the game's item cache for them with a real
-- item of the same kind (the template: held and sheathed the same) showing
-- the ported model. Kind -> the slots it fits.
local PORTED_SLOTS = {
	[200] = { 16, 17 }, [204] = { 16, 17 }, [207] = { 16, 17 }, [213] = { 16, 17 }, [215] = { 16, 17 },
	[201] = { 16 }, [205] = { 16 }, [206] = { 16 }, [208] = { 16 }, [210] = { 16 },
	[202] = { 18 }, [203] = { 18 }, [216] = { 18 }, [218] = { 18 }, [219] = { 18 },
	[214] = { 17 }, [406] = { 17 },
}
local portedItems
local function PortedItems()
	if not portedItems then
		portedItems = {}
		for id, display, kind, template, name in string.gfind(DmorphOcto_PortedItems or "",
			"(%d+)\t(%d+)\t(%d+)\t(%d+)\t([^\r\n]+)") do
			portedItems[tonumber(id)] = { display = tonumber(display), kind = tonumber(kind), template = tonumber(template),
				name = name }
		end
		DmorphOcto_PortedItems = nil
	end
	return portedItems
end

function M.IsPortedItem(itemID)
	return PortedItems()[tonumber(itemID or 0)] ~= nil
end

local function HasVirtualItems()
	return type(DmorphHelper_SetVirtualItem) == "function"
end
M.HasVirtualItems = HasVirtualItems

-- Tells DmorphHelper about every ported weapon, and asks the server for the
-- template items the game hasn't seen (their records are copied).
local portedRegistered
local function RegisterPortedItems()
	if portedRegistered or not HasVirtualItems() or not next(PortedItems()) then
		return
	end
	portedRegistered = true
	local asked = {}
	for id, p in pairs(PortedItems()) do
		pcall(DmorphHelper_SetVirtualItem, id, p.template, p.display)
		if not asked[p.template] then
			asked[p.template] = true
			local ok, name = pcall(GetItemInfo, p.template)
			if not (ok and name) and type(C_Item) == "table" then
				pcall(C_Item.RequestLoadItemDataByID, p.template)
			end
		end
	end
end
M.RegisterPortedItems = RegisterPortedItems

-- An item's kind (401 cloth, 215 dagger, ...: M.ITEM_TYPES), or nil. Items no
-- data file knows are asked from the game, which knows the ones it has seen.
function M.GetItemType(itemID)
	local ported = PortedItems()[itemID]
	if ported then
		return ported.kind
	end
	if not itemTypes then
		ReadItemTypes()
	end
	local kind = itemTypes[itemID]
	if not kind then
		local ok, _, _, _, _, class, subclass = pcall(GetItemInfo, itemID)
		kind = ok and SUBTYPES[class or ""] and SUBTYPES[class][subclass or ""]
		if kind then
			itemTypes[itemID] = kind
		end
	end
	return kind
end

-- The kinds a catalogue's entries have, in M.ITEM_TYPES' order, each with how
-- many: { { kind, name, count }, ... }.
function M.GetCatalogTypes(catalog)
	local counts = {}
	for i = 1, catalog.count do
		local kind = catalog.types and catalog.types[i]
		if kind then
			counts[kind] = (counts[kind] or 0) + 1
		end
	end
	local list = {}
	for i = 1, table.getn(M.ITEM_TYPES) do
		local kind = M.ITEM_TYPES[i][1]
		if counts[kind] then
			table.insert(list, { kind, M.ITEM_TYPES[i][2], counts[kind] })
		end
	end
	return list
end

-- Every item that fits the slot: Items.lua (the 1.12.1 database), then
-- ItemsExtra.lua (Turtle WoW and OctoWoW) and the items looked up in game.
function M.GetItemCatalog(slot)
	if not items[slot] then
		InitDB()
		local base, n = ParseItems(DmorphOcto_ItemData and DmorphOcto_ItemData[slot], 0, {}, 0)
		local seen = {}
		for i = 1, n do
			seen[base[i][1]] = true
		end
		local extra, m = ParseItems(DmorphOcto_ItemExtra and DmorphOcto_ItemExtra[slot], M.KIND_NEW, {}, 0, seen)
		for i = 1, m do
			seen[extra[i][1]] = true
		end
		local learned, k = LearnedItems(slot, seen)
		local both, count = Merge(base, n, extra, m)
		local all, total = Merge(both, count, learned, k)
		-- Ported weapons that fit the slot (shown as epic).
		local ported, p = {}, 0
		for id, item in pairs(PortedItems()) do
			local slots = PORTED_SLOTS[item.kind] or {}
			for i = 1, table.getn(slots) do
				if slots[i] == slot then
					p = p + 1
					ported[p] = { id, item.name, strlower(item.name), 4, M.KIND_PORTED }
				end
			end
		end
		table.sort(ported, Before)
		local catalog = Fill(NewCatalog(), Merge(all, total, ported, p))
		catalog.types = {}
		for i = 1, catalog.count do
			catalog.types[i] = M.GetItemType(catalog.ids[i])
		end
		items[slot] = catalog
	end
	return items[slot]
end

-- The slots an item can be morphed into, or nil if it isn't known.
local itemSlots
function M.GetItemSlots(itemID)
	if not itemSlots then
		itemSlots = {}
		for i = 1, table.getn(SLOT_ORDER) do
			local slot = SLOT_ORDER[i]
			for id in pairs(M.GetItemCatalog(slot).byID) do
				local list = itemSlots[id]
				if not list then
					list = {}
					itemSlots[id] = list
				end
				table.insert(list, slot)
			end
		end
	end
	return itemSlots[itemID]
end

-- Item lists are rebuilt the next time they're needed (after a lookup).
local function ForgetItemLists()
	items, itemSlots = {}, nil
	if sets then
		sets.qualityKnown = nil
	end
end

-- An item's quality from the item lists, or nil.
local function ItemQuality(itemID)
	local slots = M.GetItemSlots(itemID)
	if slots then
		local catalog = M.GetItemCatalog(slots[1])
		return catalog.quality[catalog.byID[itemID]]
	end
end

-- Every item set in the client, with the pieces that show on a character. A
-- set's quality is that of its best known piece.
function M.GetSetCatalog()
	if not sets then
		sets = NewCatalog()
		sets.pieces = {}
		for id, kind, name, list in string.gfind(DmorphOcto_SetData or "", "(%d+)\t(%d)\t([^\t\r\n]+)\t([%d,]+)") do
			AddEntry(sets, tonumber(id), name, nil, tonumber(kind))
			local pieces = {}
			for piece in string.gfind(list, "%d+") do
				table.insert(pieces, tonumber(piece))
			end
			sets.pieces[sets.count] = pieces
		end
		DmorphOcto_SetData = nil
	end
	if not sets.qualityKnown then
		sets.qualityKnown = true
		sets.types = {}
		for i = 1, sets.count do
			-- Quality: the best piece's. Kind: the armour most pieces are made of.
			local best, materials, kind = nil, {}, nil
			for k = 1, table.getn(sets.pieces[i]) do
				local quality = ItemQuality(sets.pieces[i][k])
				if quality and (not best or quality > best) then
					best = quality
				end
				local piece = M.GetItemType(sets.pieces[i][k])
				if piece and piece >= 401 and piece <= 404 then
					materials[piece] = (materials[piece] or 0) + 1
					if not kind or materials[piece] > materials[kind] then
						kind = piece
					end
				end
			end
			sets.quality[i], sets.types[i] = best, kind
		end
	end
	return sets
end

-- The game's dressed NPCs of a race and gender (Data/Looks.lua), the fewest
-- clothes first. Each look is { displayID, skin, face, hair style, hair
-- colour, facial hair, pieces of clothing, outfit number }.
function M.GetLooks(race, gender)
	local key = race .. ":" .. gender
	if not looks[key] then
		local list, n, hidden = {}, 0, HiddenModels()
		local text = DmorphOcto_LookData and DmorphOcto_LookData[key] or ""
		for a, b, c, d, e, f, g, h in string.gfind(text, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
			if not hidden[tonumber(a)] then
				n = n + 1
				list[n] = { tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e), tonumber(f), tonumber(g), tonumber(h) }
			end
		end
		looks[key] = list
	end
	return looks[key]
end

-- The character creator's rows and the look field each one reads. NPC looks
-- are fixed combinations, so a row's < > goes to the next value some NPC of
-- that race has, in the look that keeps the most of the other rows.
M.LOOK_FEATURES = { "Skin colour", "Face", "Hair style", "Hair colour", "Facial hair", "Outfit" }
local LOOK_FIELDS = { 2, 3, 4, 5, 6, 8 }
-- What keeping each row is worth when another one changes. Each outweighs
-- all the ones below it: skin colour, hair style, hair colour, face, facial
-- hair, outfit.
local FEATURE_WEIGHTS = { 32, 4, 16, 8, 2, 1 }

-- The values row f (1-6) has among a race and gender's looks, sorted.
function M.GetLookValues(race, gender, f)
	local list = M.GetLooks(race, gender)
	local field = LOOK_FIELDS[f]
	local seen, values = {}, {}
	for k = 1, table.getn(list) do
		local v = list[k][field]
		if not seen[v] then
			seen[v] = true
			table.insert(values, v)
		end
	end
	table.sort(values)
	return values
end

-- Row f's value in a look.
function M.LookValue(look, f)
	return look[LOOK_FIELDS[f]]
end

-- The position of the look that has `value` in row f and keeps the most of
-- look `from`'s other rows (then the most similar clothes), or nil.
function M.FindLook(race, gender, f, value, from)
	local list = M.GetLooks(race, gender)
	local field, want = LOOK_FIELDS[f], list[from]
	local best, bestScore
	for k = 1, table.getn(list) do
		local look = list[k]
		if look[field] == value then
			local keep, pieces = 0, 0
			if want then
				for g = 1, 6 do
					if g ~= f and look[LOOK_FIELDS[g]] == want[LOOK_FIELDS[g]] then
						keep = keep + FEATURE_WEIGHTS[g]
					end
				end
				pieces = math.abs(look[7] - want[7])
			end
			local score = keep * 1000 - pieces * 20 - look[7]
			if not best or score > bestScore then
				best, bestScore = k, score
			end
		end
	end
	return best
end

-- Every value of row f and, for each, the look FindLook picks from look `from`.
function M.GetLookChoices(race, gender, f, from)
	local values, at = M.GetLookValues(race, gender, f), {}
	for i = 1, table.getn(values) do
		at[values[i]] = M.FindLook(race, gender, f, values[i], from)
	end
	return values, at
end

-- Row f of look `from` one value along (step 1 or -1, wrapping around). Returns
-- the new look's position, its place among the row's values, how many values
-- there are, and the other rows that had to change with it ({} if none); or
-- nil when every NPC of the race has the same value.
function M.StepLook(race, gender, f, from, step)
	local list = M.GetLooks(race, gender)
	local values = M.GetLookValues(race, gender, f)
	local n, cur = table.getn(values), list[from]
	if n < 2 or not cur then
		return nil
	end
	local pos = 1
	for i = 1, n do
		if values[i] == cur[LOOK_FIELDS[f]] then
			pos = i
		end
	end
	pos = math.mod(pos - 1 + step + n, n) + 1
	local k = M.FindLook(race, gender, f, values[pos], from)
	local changed = {}
	for g = 1, 6 do
		if g ~= f and list[k][LOOK_FIELDS[g]] ~= cur[LOOK_FIELDS[g]] then
			table.insert(changed, g)
		end
	end
	return k, pos, n, changed
end

-- Item lookup -------------------------------------------------------------------

-- ItemsExtra.lua lists items whose slot isn't known offline: OctoWoW items
-- from Atlas-CFM's loot tables and the item sets. In the background, a few a
-- second, the addon reads them from the client's cache or (with ClassicAPI)
-- asks the server, and saves the answers account-wide. Found ones join the
-- item lists and the sets.
local LOOKUP_STEP, LOOKUP_TIMEOUT, LOOKUP_PARALLEL = 0.25, 20, 4
local lookup = { pos = 1, count = 0, ids = {}, waiting = {}, waitCount = 0, left = 0, version = 0 }

local function CanAskServer()
	return type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function"
end

-- "slots<TAB>quality<TAB>name" for an item the client knows, false if it
-- doesn't show on a character, nil if the client doesn't know it yet.
local function ReadItemInfo(itemID)
	local ok, name, _, quality, _, _, _, _, equipLoc = pcall(GetItemInfo, itemID)
	if not (ok and name) then
		return nil
	end
	local slots = EQUIP_SLOTS[equipLoc or ""]
	if not slots then
		return false
	end
	return table.concat(slots, ",") .. "\t" .. (quality or 1) .. "\t" .. string.gsub(name, "\t", " ")
end

local function Record(itemID, info)
	if account.itemInfo[itemID] == nil and info ~= nil then
		account.itemInfo[itemID] = info
		lookup.left = lookup.left - 1
		if info then
			lookup.changed = true
		end
	end
end

-- How many items are still to be looked up, and how many there were.
function M.GetLookupStatus()
	return lookup.left, lookup.count
end

-- Bumped whenever looked-up items join the lists, so the window can redraw.
function M.GetItemsVersion()
	return lookup.version
end

local function StartLookup()
	if lookup.started then
		return
	end
	lookup.started = true
	for id in string.gfind(DmorphOcto_ItemPending or "", "(%d+)\t") do
		id = tonumber(id)
		lookup.count = lookup.count + 1
		lookup.ids[lookup.count] = id
		if account.itemInfo[id] == nil then
			lookup.left = lookup.left + 1
		end
	end
	DmorphOcto_ItemPending = nil
end

local function LookupTick(elapsed)
	for id, wait in pairs(lookup.waiting) do
		if wait <= elapsed then
			-- No answer: try again next session.
			lookup.waiting[id] = nil
			lookup.waitCount = lookup.waitCount - 1
		else
			lookup.waiting[id] = wait - elapsed
		end
	end
	local askServer = CanAskServer()
	local checked = 0
	while lookup.pos <= lookup.count and checked < 40 and lookup.waitCount < LOOKUP_PARALLEL do
		local id = lookup.ids[lookup.pos]
		lookup.pos = lookup.pos + 1
		if account.itemInfo[id] == nil and not lookup.waiting[id] then
			checked = checked + 1
			local info = ReadItemInfo(id)
			if info ~= nil then
				Record(id, info)
			elseif askServer then
				lookup.waiting[id] = LOOKUP_TIMEOUT
				lookup.waitCount = lookup.waitCount + 1
				pcall(C_Item.RequestLoadItemDataByID, id)
				break -- one question per step
			end
		end
	end
	if lookup.changed then
		lookup.changed = nil
		lookup.version = lookup.version + 1
		ForgetItemLists()
	end
	return lookup.pos > lookup.count and lookup.waitCount == 0
end

-- ClassicAPI's ITEM_DATA_LOAD_RESULT(itemID, success).
local function LookupAnswer(itemID, success)
	if not lookup.waiting[itemID] then
		return
	end
	lookup.waiting[itemID] = nil
	lookup.waitCount = lookup.waitCount - 1
	if success then
		Record(itemID, ReadItemInfo(itemID))
	else
		Record(itemID, false) -- the server has no such item
	end
end

-- Whether entry i passes a filter from the *_FILTERS lists ({ kinds = ..., tag
-- = ... }) and a quality from QUALITY_FILTERS. Both are optional.
local function Keep(catalog, i, filter, quality, kind)
	if kind and not (catalog.types and catalog.types[i] == kind) then
		return false
	end
	if filter then
		if filter.kinds and not filter.kinds[catalog.kind[i]] then
			return false
		end
		if filter.tag then
			local tags = catalog.tags and catalog.tags[i]
			if not (tags and strfind(tags, filter.tag, 1, true)) then
				return false
			end
		end
	end
	return not quality or catalog.quality[i] == quality
end

-- Positions of the catalogue entries matching the text, plus how many there
-- are: an exact ID first, then names starting with the text, then names
-- containing it. byID lists them by ID instead; kind keeps only one item kind.
function M.FilterCatalog(catalog, text, filter, quality, byID, kind)
	local query = strlower(Trim(text))
	local result, n = {}, 0
	local number = ParseID(query)
	local later, m = {}, 0
	for i = 1, catalog.count do
		if Keep(catalog, i, filter, quality, kind) then
			local at = query == "" or strfind(catalog.lower[i], query, 1, true)
			if query == "" or catalog.ids[i] == number or at == 1 then
				n = n + 1
				result[n] = i
			elseif at then
				m = m + 1
				later[m] = i
			end
		end
	end
	for i = 1, m do
		result[n + i] = later[i]
	end
	n = n + m
	if byID then
		local ids = catalog.ids
		table.sort(result, function(a, b)
			return ids[a] < ids[b] or (ids[a] == ids[b] and a < b)
		end)
	end
	return result, n
end

-- The catalogue's name for a display ID and what kind of entry it is, or nil.
function M.GetDisplayName(displayID)
	local catalog = M.GetCreatureCatalog()
	local index = catalog.byID[displayID]
	if index then
		return catalog.names[index], catalog.kind[index]
	end
end

function M.DescribeDisplay(displayID)
	local name = M.GetDisplayName(displayID)
	if name then
		return name .. " (" .. displayID .. ")"
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
	local extra = ""
	if outfit.look then
		extra = extra .. ", own face"
	end
	if outfit.glows and next(outfit.glows) then
		extra = extra .. ", glows"
	end
	if outfit.mount then
		extra = extra .. ", mount"
	end
	if count == 1 then
		return look .. ", 1 item" .. extra
	end
	return look .. ", " .. count .. " items" .. extra
end

-- State ---------------------------------------------------------------------

-- Five look values (skin colour, face, hair style, hair colour, facial hair),
-- copied, or nil if look isn't one.
local function ValidLook(look)
	if type(look) ~= "table" then
		return nil
	end
	for i = 1, 5 do
		local v = look[i]
		if type(v) ~= "number" or v < 0 or v > 255 or v ~= math.floor(v) then
			return nil
		end
	end
	return { look[1], look[2], look[3], look[4], look[5] }
end

-- Drops anything that isn't a usable ID, e.g. from a hand-edited file.
local function SanitizeOutfit(outfit)
	outfit.display = ParseID(outfit.display)
	if outfit.display == 0 then
		outfit.display = nil
	end
	outfit.mount = ParseID(outfit.mount)
	if outfit.mount == 0 then
		outfit.mount = nil
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
	-- Weapon glows (DmorphHelper): slot -> enchant ID, 0 for none.
	if type(outfit.glows) ~= "table" then
		outfit.glows = {}
	end
	for slot, enchantID in pairs(outfit.glows) do
		enchantID = ParseID(enchantID)
		if not GLOW_SLOT[slot] or (enchantID and enchantID > 1000000) then
			enchantID = nil
		end
		outfit.glows[slot] = enchantID
	end
	-- An outfit's own look: { race, gender, the five values }.
	local look = outfit.look
	if type(look) == "table" and RACES[look.race] and (look.gender == 0 or look.gender == 1) and ValidLook(look) then
		outfit.look = ValidLook(look)
		outfit.look.race, outfit.look.gender = look.race, look.gender
	else
		outfit.look = nil
	end
	return outfit
end

-- The current look as an outfit: db, plus the look picked for your body.
local function CopyOutfit(outfit)
	local copy = { display = outfit.display, race = outfit.race, gender = outfit.gender, mount = outfit.mount,
		items = {}, glows = {} }
	for slot, itemID in pairs(outfit.items) do
		copy.items[slot] = itemID
	end
	for slot, enchantID in pairs(outfit.glows) do
		copy.glows[slot] = enchantID
	end
	local race, gender = M.GetBodyRace()
	local look = race and ValidLook(outfit.looks[race .. ":" .. gender])
	if look then
		look.race, look.gender = race, gender
		copy.look = look
	end
	return copy
end

function InitDB()
	if db then
		return
	end
	if type(DmorphOctoDB) ~= "table" then
		DmorphOctoDB = {}
	end
	db = SanitizeOutfit(DmorphOctoDB)
	-- Mount skins per mount (own display -> skin) and the mounts ridden.
	if type(db.mountSkins) ~= "table" then
		db.mountSkins = {}
	end
	for real, skin in pairs(db.mountSkins) do
		if type(real) ~= "number" or not ParseID(skin) or ParseID(skin) == 0 then
			db.mountSkins[real] = nil
		end
	end
	local ridden = {}
	if type(db.ridden) == "table" then
		for i = 1, table.getn(db.ridden) do
			local id = ParseID(db.ridden[i])
			if id and id > 0 then
				table.insert(ridden, id)
			end
		end
	end
	db.ridden = ridden
	-- DmorphHelper: the look picked per body ("race:gender" -> five values),
	-- and per weapon slot and for the look, the real values last seen and
	-- what was last written.
	local picked = {}
	if type(db.looks) == "table" then
		for key, look in pairs(db.looks) do
			local _, _, race = strfind(type(key) == "string" and key or "", "^(%d+):[01]$")
			if race and RACES[tonumber(race)] then
				picked[key] = ValidLook(look)
			end
		end
	end
	db.looks = picked
	db.lookReal, db.lookWritten = ValidLook(db.lookReal), ValidLook(db.lookWritten)
	-- Your size (DmorphHelper v2): the picked one, the real one last seen and
	-- what was last written, each 0.1-10.
	-- The languages your character speaks (CaptureNative): names, or nil.
	if type(db.languages) == "table" then
		local names = {}
		for i = 1, table.getn(db.languages) do
			if type(db.languages[i]) == "string" then
				table.insert(names, db.languages[i])
			end
		end
		db.languages = table.getn(names) > 0 and names or nil
	else
		db.languages = nil
	end
	if type(db.defaultLanguage) ~= "string" then
		db.defaultLanguage = nil
	end
	local time = tonumber(db.time)
	db.time = time and time >= 0 and time < 1440 and math.floor(time) or nil
	local weatherKind = type(db.weather) == "table" and tonumber(db.weather[1])
	local weatherStrength = type(db.weather) == "table" and tonumber(db.weather[2])
	if weatherKind and weatherStrength and weatherKind >= 0 and weatherKind <= 3 and weatherStrength >= 0
		and weatherStrength <= 1 then
		db.weather = { weatherKind, weatherStrength }
	else
		db.weather = nil
	end
	for _, key in ipairs({ "scale", "scaleReal", "scaleWritten" }) do
		local v = tonumber(db[key])
		if not (v and v >= 0.1 and v <= 10) then
			v = nil
		end
		db[key] = v
	end
	for _, key in ipairs({ "glowReal", "glowWritten" }) do
		local kept = {}
		if type(db[key]) == "table" then
			for slot, pair in pairs(db[key]) do
				if GLOW_SLOT[slot] and type(pair) == "table" and type(pair[1]) == "number" and type(pair[2]) == "number" then
					kept[slot] = { pair[1], pair[2] }
				end
			end
		end
		db[key] = kept
	end
	if type(DmorphOctoAccount) ~= "table" then
		DmorphOctoAccount = {}
	end
	account = DmorphOctoAccount
	if type(account.outfits) ~= "table" then
		account.outfits = {}
	end
	-- Items looked up in game: id -> "slots<TAB>quality<TAB>name", or false.
	if type(account.itemInfo) ~= "table" then
		account.itemInfo = {}
	end
	for id, info in pairs(account.itemInfo) do
		if type(id) ~= "number" or (info ~= false and type(info) ~= "string") then
			account.itemInfo[id] = nil
		end
	end
	for name, outfit in pairs(account.outfits) do
		if type(name) == "string" and type(outfit) == "table" then
			SanitizeOutfit(outfit)
		else
			account.outfits[name] = nil
		end
	end
	-- Favourites: { id = displayID, mount = true or nil }, oldest first, each once.
	local favourites, seen = {}, {}
	if type(account.favourites) == "table" then
		for i = 1, table.getn(account.favourites) do
			local fav = account.favourites[i]
			local id = type(fav) == "table" and ParseID(fav.id)
			if id and id > 0 then
				local mount = fav.mount and true or nil
				local key = (mount and "mount" or "model") .. id
				if not seen[key] then
					seen[key] = true
					table.insert(favourites, { id = id, mount = mount })
				end
			end
		end
	end
	account.favourites = favourites
	-- Sharing with other DMorph users (Share.lua): on unless switched off.
	account.shareOff = account.shareOff == true or nil
	account.othersOff = account.othersOff == true or nil
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
	-- The game lists the languages of the race it thinks you are, and a race
	-- morph changes that (a Gnome morph lists Common and Gnomish), so the
	-- ones your character speaks are read now, with your own race showing,
	-- and kept for chat (see SpeakableLanguage).
	local languages = {}
	for i = 1, 20 do
		local got, name = pcall(GetLanguageByIndex, i)
		if not (got and type(name) == "string") then
			break
		end
		table.insert(languages, name)
	end
	if table.getn(languages) > 0 then
		local got, default = pcall(GetDefaultLanguage)
		db.languages = languages
		db.defaultLanguage = got and default or nil
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
	-- The mount skin is put back on by the mount watcher once you ride.
	if type(SetUnitMountDisplayID) == "function" and (db.mount or next(db.mountSkins)) then
		Morph(SetUnitMountDisplayID, "player", nil)
	end
	CaptureNative()
	RegisterPortedItems()
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

-- After a body change the game is still building the model, and a look or
-- glow written into it then could mix with the old one; so DmorphHelper's
-- watcher holds off this long, then runs (see Glows and your own look).
local helperHold, helperWait = 0, 0

-- A race morph makes VanillaHelpers tell the game you are that race (the
-- model's skin needs it), and two windows go by that race: the flight map (a
-- Horde character morphed into a Human sees no Horde flight paths) and the
-- spellbook (spells change places). While one of them is open your own race
-- is back, and the morph returns when it closes. raceHeld: why ("taxi",
-- "spellbook").
local raceHeld = {}

local function DisplayRace(display)
	for race = 1, table.getn(RACES) do
		if RACES[race].male == display or RACES[race].female == display then
			return race
		end
	end
end

-- A race morph's race stays in the game's race byte (the game textures your
-- model from it, so it has to). DmorphHelper (v6+) puts your own race in only
-- while the game reads an incoming chat message (so it understands your
-- languages) or works out your base reputations (built once from your race:
-- with another faction's race, NPCs of your own faction turn hostile), and
-- the addon does below while the flight map, spellbook or reputation list is
-- open: the byte alone, no rebuild, so your model doesn't change. The helper
-- is told your own race all the time, not only during a race morph, so a
-- loading screen during one can't build your reputations with the wrong
-- race. raceKept: the race it was told (0: none yet).
local raceKept = 0
local raceSwapped = {} -- reasons the byte holds your own race (HoldRace)

local function MorphRace()
	local morph = DisplayRace(BodyDisplayID() or 0)
	if sessionReady and morph and nativeRace and morph ~= nativeRace then
		return morph
	end
end

local function KeepRace()
	if type(DmorphHelper_SetOwnRace) ~= "function" then
		return
	end
	local want = sessionReady and nativeRace or 0
	if want ~= raceKept and pcall(DmorphHelper_SetOwnRace, want) then
		raceKept = want
	end
end

local function ApplyBody()
	helperHold, helperWait = 0.5, 0.5
	if next(raceHeld) then
		return true -- it goes on when the flight map or spellbook closes
	end
	local ok, err = Morph(SetUnitDisplayID, "player", BodyDisplayID())
	KeepRace()
	if next(raceSwapped) and MorphRace() then
		pcall(DmorphHelper_SetRace, "player", nativeRace) -- still open
	end
	return ok, err
end

-- Holds (on) or releases your own race for a reason. Returns whether the
-- race was changed back just now, so the window can redraw.
function M.HoldRace(reason, on)
	-- With DmorphHelper: only the race byte, for as long as the window is open.
	if type(DmorphHelper_SetRace) == "function" then
		if on then
			local morph = MorphRace()
			if not morph or not pcall(DmorphHelper_SetRace, "player", nativeRace) then
				return false
			end
			local first = not next(raceSwapped)
			raceSwapped[reason] = true
			return first
		end
		if raceSwapped[reason] then
			raceSwapped[reason] = nil
			local morph = MorphRace()
			if not next(raceSwapped) and morph then
				pcall(DmorphHelper_SetRace, "player", morph)
			end
		end
		return false
	end
	-- Without it: your own model while the window is open.
	if on then
		local held = next(raceHeld) ~= nil
		if held then
			raceHeld[reason] = true
			return false
		end
		local race = DisplayRace(BodyDisplayID() or 0)
		if not (sessionReady and race and race ~= nativeRace and HasMorphAPI()) then
			return false
		end
		raceHeld[reason] = true
		helperHold = 1000000 -- no picked look on your own race meanwhile
		if M.HasHelper() and db.lookWritten and db.lookReal then
			local l = db.lookReal
			if pcall(DmorphHelper_SetLook, "player", l[1], l[2], l[3], l[4], l[5]) then
				db.lookWritten = nil
			end
		end
		Morph(SetUnitDisplayID, "player", nil)
		return true
	end
	if raceHeld[reason] then
		raceHeld[reason] = nil
		if not next(raceHeld) then
			ApplyBody()
		end
	end
	return false
end

local function ApplyItem(slot)
	local id = db.items[slot]
	if id and M.IsPortedItem(id) then
		if not HasVirtualItems() then
			return false, "Ported weapons need DmorphHelper v10: close the game, double-click \"Install DmorphHelper.bat\" "
				.. "in Interface\\AddOns\\DmorphOcto, then start the game from OctoLauncher."
		end
		RegisterPortedItems()
	end
	return Morph(SetUnitVisibleItemID, "player", slot, id)
end

-- Mount morphs need VanillaHelpers' SetUnitMountDisplayID (v1.1.0 has it).
local function HasMountAPI()
	return type(SetUnitMountDisplayID) == "function"
end
M.HasMountAPI = HasMountAPI

-- Mount skins -----------------------------------------------------------------

-- A skin is a display ID your mount shows instead of its own: db.mount for all
-- your mounts, db.mountSkins[real display] for one of them. VanillaHelpers'
-- mount override holds the model whatever the server says, so it would keep
-- you on a mount after you dismount. So the skin is only put on while you
-- ride: when the mount field turns non-zero you mounted, and the buff that
-- came with it is the mount's; when that buff goes, you dismounted and the
-- override comes off, which lets the game's own mount and dismount through.
local watch = {}

local function BuffTextures()
	local set, any = {}, false
	for i = 1, 32 do
		local ok, texture = pcall(UnitBuff, "player", i)
		if not (ok and texture) then
			break
		end
		set[texture], any = true, true
	end
	return set, any
end

local function SkinFor(real)
	return db.mountSkins[real] or db.mount
end

local function StopSkin()
	if watch.active then
		watch.active, watch.skin = nil, nil
		Morph(SetUnitMountDisplayID, "player", nil)
	end
end

local function RememberRidden(real)
	for i = 1, table.getn(db.ridden) do
		if db.ridden[i] == real then
			return
		end
	end
	table.insert(db.ridden, real)
	if table.getn(db.ridden) > 20 then
		table.remove(db.ridden, 1)
	end
end

-- Runs every tenth of a second.
local function OnTaxi()
	local ok, flying = pcall(UnitOnTaxi, "player")
	return ok and flying and true or false
end

local function WatchMount()
	if not (sessionReady and HasMountAPI()) then
		return
	end
	-- A flight path's bird is the game's, not your mount: no skin on it (and
	-- one already on comes off as the flight starts).
	if OnTaxi() then
		if watch.active then
			StopSkin()
			Notify()
		end
		watch.real = nil
		return
	end
	if watch.active then
		local buffs = BuffTextures()
		for texture in pairs(watch.candidates) do
			if not buffs[texture] then
				-- The mount's buff is gone: you dismounted.
				StopSkin()
				watch.last, watch.real = buffs, nil
				Notify()
				return
			end
		end
		-- Each change tells the listeners (the window, and Share.lua so other
		-- DMorph users see the skin come and go).
		local skin = SkinFor(watch.real)
		if not skin then
			StopSkin()
			Notify()
		elseif skin ~= watch.skin then
			watch.skin = skin
			Morph(SetUnitMountDisplayID, "player", skin)
			Notify()
		end
		return
	end
	local ok, _, _, field = pcall(UnitDisplayInfo, "player")
	if not ok then
		return
	end
	if field and field > 0 then
		if watch.real ~= field then
			watch.real = field
			RememberRidden(field)
			Notify()
		end
		local skin = SkinFor(field)
		if skin and skin ~= field then
			local buffs, any = BuffTextures()
			local candidates, found = {}, false
			for texture in pairs(buffs) do
				if not (watch.last and watch.last[texture]) then
					candidates[texture], found = true, true
				end
			end
			-- The mount's buff comes with it. Without a new one there's
			-- nothing that would say when you dismount (a skin would then
			-- stay on, and the game would think you still ride), so wait
			-- for it; only if you were mounted before we could look (a
			-- login or /reload in the saddle) does any buff going count.
			if not found and not watch.last then
				candidates, found = buffs, any
			end
			if found then
				watch.candidates, watch.skin, watch.active = candidates, skin, true
				Morph(SetUnitMountDisplayID, "player", skin)
				Notify()
			end
		end
	else
		if watch.real then
			watch.real = nil
			Notify()
		end
		if db.mount or next(db.mountSkins) then
			watch.last = BuffTextures()
		end
	end
end

-- Whether you ride, the display ID of your own mount, and the skin it shows.
function M.GetMountState()
	InitDB()
	if watch.real then
		return true, watch.real, watch.skin
	end
	return false
end

-- The mounts you've ridden on this character (their own display IDs).
function M.GetRiddenMounts()
	InitDB()
	return db.ridden
end

function M.GetMountSkin(real)
	InitDB()
	if real then
		return db.mountSkins[real]
	end
	return db.mount
end

-- What other DMorph users should see: your body's display ID (nil when you
-- aren't morphed), your item morphs (slot -> item ID), and the mount skin
-- showing now (nil on foot or without a skin).
function M.GetSharedLook()
	InitDB()
	local mount
	if watch.active then
		mount = watch.skin
	end
	-- Ported models are only on this PC: others would see nothing, so they
	-- see your own model or mount instead.
	local display = BodyDisplayID()
	if display and M.IsPorted(display) then
		display = nil
	end
	if mount and M.IsPorted(mount) then
		mount = nil
	end
	local items = {}
	for slot, id in pairs(db.items) do
		if not M.IsPortedItem(id) then
			items[slot] = id
		end
	end
	return display, items, mount
end

-- Glows and your own look (DmorphHelper.dll) ----------------------------------

-- DmorphHelper.dll (helper/ in this folder) does two things VanillaHelpers
-- can't, on your screen only like every morph: it rewrites a weapon slot's
-- enchant IDs, which the game draws the enchant's glow from, and your skin
-- colour, face, hair style, hair colour and facial hair (the values character
-- creation sets). The server sends the real values again now and then (a new
-- enchant, a loading screen), so a watcher puts the chosen ones back once a
-- second. Whatever it reads that it didn't write is the real value, kept so
-- "your own" can put it back.
-- How to install it: the .bat in the addon folder copies the DLL into the
-- game folder and adds it to dlls.txt (an addon can't write files there).
local INSTALL_HELPER = "Close the game, double-click \"Install DmorphHelper.bat\" in Interface\\AddOns\\DmorphOcto, "
	.. "then start the game from OctoLauncher."
local MISSING_HELPER = "DmorphHelper.dll isn't loaded, so weapon glows, your size and real skin, face and hair changes "
	.. "are unavailable. " .. INSTALL_HELPER
M.MISSING_HELPER = MISSING_HELPER
-- The DmorphHelper_Version() the DLL in helper\ reports. An older one in the
-- game folder (DMorph was updated, the DLL wasn't copied again) is flagged.
local HELPER_VERSION = 10
-- Rows 1-5 of the Races tab, in DmorphHelper_GetLook's order.
local OWN_LOOK_NPC = { "npcSkin", "npcFace", "npcHairStyle", "npcHairColour" }

local function HasHelper()
	return type(DmorphHelper_GetItemEnchants) == "function" and type(DmorphHelper_SetItemEnchants) == "function"
		and type(DmorphHelper_GetLook) == "function" and type(DmorphHelper_SetLook) == "function"
end
M.HasHelper = HasHelper

-- The DmorphHelper version running (nil: none), and the one this DMorph
-- comes with.
function M.GetHelperVersion()
	if not HasHelper() then
		return nil, HELPER_VERSION
	end
	local ok, version = pcall(DmorphHelper_Version)
	return ok and tonumber(version) or 0, HELPER_VERSION
end

-- What DMorph needs and what it can use, for the window's Setup check and
-- /dmorph check: { name, state = "ok" / "bad" / "off" (optional, missing), text }.
function M.GetSetupReport()
	local report = {}
	local function Add(name, state, text)
		table.insert(report, { name = name, state = state, text = text })
	end
	if HasMorphAPI() then
		local version = ""
		if type(VANILLAHELPERS_VERSION) == "number" then
			version = " v" .. VersionText(VANILLAHELPERS_VERSION)
		end
		Add("VanillaHelpers", "ok", "Running" .. version .. ": morphing works.")
	else
		Add("VanillaHelpers", "bad", MissingAPI())
	end
	local helperVersion = M.GetHelperVersion()
	if helperVersion and helperVersion < HELPER_VERSION then
		Add("DmorphHelper", "bad", "An older DmorphHelper (v" .. helperVersion .. ") is in the game folder; this DMorph "
			.. "comes with v" .. HELPER_VERSION .. ". " .. INSTALL_HELPER)
	elseif HasHelper() then
		Add("DmorphHelper", "ok", "Running v" .. helperVersion .. " (this DMorph comes with v" .. HELPER_VERSION .. "): weapon "
			.. "glows, size, real skin, face and hair, and your own faction and languages during race morphs work.")
	else
		Add("DmorphHelper", "off", "Optional, not running: weapon glows and real skin, face and hair need it. "
			.. INSTALL_HELPER)
	end
	if type(C_Item) == "table" then
		Add("ClassicAPI", "ok", "Running: 3D previews of models work.")
	else
		Add("ClassicAPI", "off", "Optional, not running: the Models tab shows a list instead of 3D previews.")
	end
	if SUPERWOW_VERSION then
		Add("SuperWoW", "ok", "Running: other DMorph users' morphs show without targeting them.")
	else
		Add("SuperWoW", "off", "Optional, not running: target or mouse over other DMorph users to see their morphs.")
	end
	return report
end

-- Every glow the client can draw (Data/Glows.lua): per glow its visual ID, an
-- enchant ID that shows it, its name (the shortest enchant name), all the
-- enchant names and its effect models.
local glows
function M.GetGlows()
	local text = DmorphOcto_GlowData or ""
	if not glows or glows.text ~= text then
		glows = { text = text, count = 0, visual = {}, enchant = {}, name = {}, names = {}, models = {}, search = {} }
		for visual, enchant, names, models in string.gfind(text, "(%d+)\t(%d+)\t([^\t\n]*)\t([^\t\n]*)") do
			local n = glows.count + 1
			glows.count = n
			glows.visual[n], glows.enchant[n] = tonumber(visual), tonumber(enchant)
			local _, _, first = strfind(names, "^([^;]+)")
			glows.name[n] = first or ("Glow " .. visual)
			glows.names[n], glows.models[n] = names, models
			glows.search[n] = strlower(names .. " " .. models .. " " .. visual .. " " .. enchant)
		end
	end
	return glows
end

-- The glows whose names, effect models or IDs have every word of text.
function M.FilterGlows(text)
	local all, words = M.GetGlows(), {}
	for word in string.gfind(strlower(text or ""), "%S+") do
		table.insert(words, word)
	end
	local result, count = {}, 0
	for i = 1, all.count do
		local keep = true
		for k = 1, table.getn(words) do
			if not strfind(all.search[i], words[k], 1, true) then
				keep = false
				break
			end
		end
		if keep then
			count = count + 1
			result[count] = i
		end
	end
	return result, count
end

function M.DescribeGlow(enchantID)
	if enchantID == 0 then
		return "no glow"
	end
	local all = M.GetGlows()
	for i = 1, all.count do
		if all.enchant[i] == enchantID then
			return all.name[i]
		end
	end
	return "enchant " .. enchantID
end

-- The glow picked for a weapon slot (an enchant ID, 0 for none, nil for your
-- own) and the slot's real permanent enchant, if seen.
function M.GetGlow(slot)
	InitDB()
	local real = db.glowReal[slot]
	return db.glows[slot], real and real[1]
end

-- The skin colours, faces and hair a race and gender can wear
-- (Data/CharOptions.lua), or nil.
function M.GetLookOptions(race, gender)
	local all = DmorphOcto_CharOptions
	local o = type(all) == "table" and race and all[race .. ":" .. gender]
	if type(o) == "table" and type(o.skin) == "table" and table.getn(o.skin) > 0 then
		return o
	end
end

-- The values row f (1-5) can have with the rest of look, sorted: a face needs
-- its skin colour, a hair colour its hair style.
local function LookChoices(o, look, f)
	local list
	if f == 1 then
		list = o.skin
	elseif f == 2 then
		list = o.face and o.face[look[1]]
	elseif f == 3 then
		list = o.hairStyle
	elseif f == 4 then
		list = o.hairColour and o.hairColour[look[3]] or o.anyHairColour
	else
		list = o.facialHair
	end
	return type(list) == "table" and list or {}
end

local function Nearest(list, value)
	local best
	for i = 1, table.getn(list) do
		local v = list[i]
		if v == value then
			return v
		end
		if not best or math.abs(v - value) < math.abs(best - value) then
			best = v
		end
	end
	return best or value
end

-- Makes look one the race can wear, row by row; returns the rows changed.
local function ClampLook(o, look)
	local changed = {}
	for f = 1, 5 do
		local v = Nearest(LookChoices(o, look, f), look[f])
		if v ~= look[f] then
			look[f] = v
			table.insert(changed, f)
		end
	end
	return changed
end

-- Row f of a look: its choices, the value's place among them (0 if it isn't
-- one), and whether only NPCs have that value.
function M.LookRow(o, look, f)
	local values = LookChoices(o, look, f)
	local pos = 0
	for i = 1, table.getn(values) do
		if values[i] == look[f] then
			pos = i
		end
	end
	local npc = OWN_LOOK_NPC[f] and type(o[OWN_LOOK_NPC[f]]) == "table" and o[OWN_LOOK_NPC[f]][look[f]] and true
	return values, pos, npc or false
end

local function SameValues(a, b)
	if not (a and b) then
		return false
	end
	for i = 1, 5 do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function CopyLook(look)
	return { look[1], look[2], look[3], look[4], look[5] }
end

local function ReadLook()
	local ok, a, b, c, d, e = pcall(DmorphHelper_GetLook, "player")
	if ok and type(a) == "number" then
		return { a, b, c, d, e }
	end
end

-- Your real look: what the game has, unless that's what we wrote.
local function RealLook()
	local current = HasHelper() and ReadLook()
	if current and not SameValues(current, db.lookWritten) then
		return current
	end
	return db.lookReal or current
end

-- The body your look shows on (race, gender), its options, the look it has
-- (5 values, or nil when unknown) and whether that's one you picked.
function M.GetLookState()
	InitDB()
	local race, gender = M.GetBodyRace()
	local o = M.GetLookOptions(race, gender)
	local picked = race and db.looks[race .. ":" .. gender]
	if picked then
		return race, gender, o, picked, true
	end
	return race, gender, o, M.FittedLook(o, RealLook()), false
end

-- Your own look as the body's race can wear it: a value that race doesn't
-- have (a Tauren's hair style on a Gnome) has no texture, and the game
-- draws it green, so it moves to the closest one that race has.
function M.FittedLook(o, look)
	if not (o and look) then
		return look
	end
	local fitted = CopyLook(look)
	ClampLook(o, fitted)
	return fitted
end

-- Your size needs DmorphHelper v2.
local function HasScale()
	return type(DmorphHelper_GetScale) == "function" and type(DmorphHelper_SetScale) == "function"
end
M.HasScale = HasScale

-- Puts the picked size on (the server sends the real one again now and
-- then), and the real one back once nothing is picked.
local function WatchScale()
	if not HasScale() then
		return
	end
	local ok, current = pcall(DmorphHelper_GetScale, "player")
	if not (ok and type(current) == "number") then
		return
	end
	local written = db.scaleWritten
	if not (written and math.abs(current - written) < 0.001) then
		db.scaleReal = current
	end
	local want = db.scale or (written and db.scaleReal)
	if want and math.abs(current - want) >= 0.001 and pcall(DmorphHelper_SetScale, "player", want) then
		db.scaleWritten = want
	end
	if not db.scale then
		db.scaleWritten = nil
	end
end

-- Puts the picked glows and look on, and puts the real ones back where
-- nothing is picked any more.
local function WatchHelper()
	if not (sessionReady and HasHelper()) or helperHold > 0 then
		return
	end
	WatchScale()
	local current = ReadLook()
	if current then
		if not SameValues(current, db.lookWritten) then
			db.lookReal = current
		end
		local race, gender = M.GetBodyRace()
		local want = race and db.looks[race .. ":" .. gender]
		if not want and race then
			-- Your own look, fitted to the race (see M.FittedLook).
			local real = db.lookReal or current
			local fitted = M.FittedLook(M.GetLookOptions(race, gender), real)
			if fitted and not SameValues(fitted, real) then
				want = fitted
			end
		end
		local restore = not want and db.lookWritten
		if restore then
			want = db.lookReal
		end
		if want and not SameValues(current, want) then
			if pcall(DmorphHelper_SetLook, "player", want[1], want[2], want[3], want[4], want[5]) then
				db.lookWritten = CopyLook(want)
			end
		end
		if restore then
			db.lookWritten = nil
		end
	end
	for slot in pairs(GLOW_SLOT) do
		local ok, p, t = pcall(DmorphHelper_GetItemEnchants, "player", slot)
		if ok and type(p) == "number" then
			local written = db.glowWritten[slot]
			if not (written and written[1] == p and written[2] == t) then
				db.glowReal[slot] = { p, t }
			end
			local want
			if db.glows[slot] then
				want = { db.glows[slot], 0 }
			elseif written then
				want = db.glowReal[slot]
			end
			if want and (want[1] ~= p or want[2] ~= t) then
				if pcall(DmorphHelper_SetItemEnchants, "player", slot, want[1], want[2]) then
					db.glowWritten[slot] = { want[1], want[2] }
				end
			end
			if not db.glows[slot] then
				db.glowWritten[slot] = nil
			end
		end
	end
end

-- Glow and look actions need both DLLs.
local function HelperBegin()
	if not Begin() then
		return false, MissingAPI()
	end
	if not HasHelper() then
		return false, MISSING_HELPER
	end
	return true
end

-- Your size, 0.1-10 (1 = normal), or nil for your own. It works on any
-- model: a small Ragnaros, a giant Tauren.
function M.SetScale(scale)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	if not HasScale() then
		return false, "Changing your size needs DmorphHelper v2 (this DMorph comes with it). " .. INSTALL_HELPER
	end
	if scale ~= nil then
		scale = tonumber(scale)
		if not (scale and scale >= 0.1 and scale <= 10) then
			return false, "Size is a number from 0.1 to 10 (1 is normal)."
		end
		scale = math.floor(scale * 100 + 0.5) / 100
	end
	db.scale = scale
	WatchScale()
	Notify()
	if scale then
		return true, format("Size: %d%%. Only you see it.", math.floor(scale * 100 + 0.5))
	end
	return true, "Your own size again."
end

-- The size you picked (nil: your own) and the real one last seen.
function M.GetScale()
	InitDB()
	return db.scale, db.scaleReal
end

-- Weather (DmorphHelper v8) ---------------------------------------------------------

-- The game draws four kinds of weather, each from 0 to 1 strong (the server
-- picks per zone). A picked one stays on in every zone, on your screen only,
-- until you go back to the server's.
M.WEATHER_KINDS = { [0] = "Clear skies", "Rain", "Snow", "Sandstorm" }
M.WEATHERS = {
	{ key = "Clear", kind = 0, intensity = 0, text = "Clear skies" },
	{ key = "LightRain", kind = 1, intensity = 0.25, text = "Light rain" },
	{ key = "Rain", kind = 1, intensity = 0.55, text = "Rain" },
	{ key = "HeavyRain", kind = 1, intensity = 1, text = "Heavy rain" },
	{ key = "LightSnow", kind = 2, intensity = 0.25, text = "Light snow" },
	{ key = "Snow", kind = 2, intensity = 0.55, text = "Snow" },
	{ key = "HeavySnow", kind = 2, intensity = 1, text = "Blizzard" },
	{ key = "LightSandstorm", kind = 3, intensity = 0.25, text = "Light sandstorm" },
	{ key = "Sandstorm", kind = 3, intensity = 0.55, text = "Sandstorm" },
	{ key = "HeavySandstorm", kind = 3, intensity = 1, text = "Heavy sandstorm" },
}
local WEATHER_WORDS = { clear = 0, sun = 0, sunny = 0, fine = 0, none = 0, rain = 1, snow = 2, sand = 3,
	sandstorm = 3, storm = 3, dust = 3 }
local WEATHER_STRENGTH = { light = 0.25, medium = 0.55, normal = 0.55, heavy = 1, strong = 1 }

local function HasWeather()
	return type(DmorphHelper_SetWeather) == "function" and type(DmorphHelper_ClearWeather) == "function"
		and type(DmorphHelper_GetWeather) == "function"
end
M.HasWeather = HasWeather

-- "Heavy rain (100%)", "Clear skies".
function M.DescribeWeather(kind, intensity)
	local name = M.WEATHER_KINDS[kind] or "Unknown weather"
	if not kind or kind == 0 then
		return name
	end
	return format("%s (%d%%)", name, math.floor((intensity or 0) * 100 + 0.5))
end

-- Time of day (DmorphHelper v9): the world's light, sky, sun and moon at a
-- picked time; the clock and the server keep the real one.
M.TIMES = {
	{ key = "Dawn", minutes = 360, text = "Dawn" },
	{ key = "Noon", minutes = 720, text = "Noon" },
	{ key = "Dusk", minutes = 1170, text = "Dusk" },
	{ key = "Night", minutes = 0, text = "Midnight" },
}
local TIME_WORDS = { dawn = 360, sunrise = 360, morning = 540, day = 720, noon = 720, midday = 720,
	afternoon = 900, dusk = 1170, sunset = 1170, evening = 1260, night = 0, midnight = 0 }

local function HasTime()
	return type(DmorphHelper_SetTime) == "function" and type(DmorphHelper_GetTime) == "function"
end
M.HasTime = HasTime

-- "22:30".
function M.DescribeTime(minutes)
	minutes = math.floor(minutes or 0)
	return format("%d:%02d", math.floor(minutes / 60), math.mod(minutes, 60))
end

-- Puts the picked weather and time on (after a loading screen or zone
-- change, the helper has usually kept them; this is the backup).
local function ApplyWeather()
	if db and db.weather and HasWeather() then
		pcall(DmorphHelper_SetWeather, db.weather[1], db.weather[2])
	end
	if db and db.time and HasTime() then
		pcall(DmorphHelper_SetTime, db.time)
	end
end

-- minutes after midnight (0-1439), or nil for the real time.
function M.SetTime(minutes)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	if not HasTime() then
		return false, "Changing the time of day needs DmorphHelper v9 (this DMorph comes with it). " .. INSTALL_HELPER
	end
	if minutes ~= nil then
		minutes = tonumber(minutes)
		if not minutes then
			return false, "The time is hours and minutes, e.g. 22:30."
		end
		minutes = math.mod(math.floor(minutes + 0.5), 1440)
		if minutes < 0 then
			minutes = minutes + 1440
		end
	end
	if not pcall(DmorphHelper_SetTime, minutes or -1) then
		return false, "DmorphHelper couldn't change the time of day."
	end
	db.time = minutes
	Notify()
	if minutes then
		return true, "Time of day: " .. M.DescribeTime(minutes) .. ". Only you see it."
	end
	return true, "The real time of day again."
end

-- The time you picked (minutes; nil: the real time) and the real time
-- (nil without DmorphHelper v9).
function M.GetTime()
	InitDB()
	local real
	if HasTime() then
		local ok, _, _, r = pcall(DmorphHelper_GetTime)
		if ok then
			real = r
		end
	end
	return db.time, real
end

-- kind: 0 clear, 1 rain, 2 snow, 3 sandstorm, or nil for the server's
-- weather; intensity 0-1 (rain, snow and sandstorm need more than 0).
function M.SetWeather(kind, intensity)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	if not HasWeather() then
		return false, "Changing the weather needs DmorphHelper v8 (this DMorph comes with it). " .. INSTALL_HELPER
	end
	if kind == nil then
		if not pcall(DmorphHelper_ClearWeather) then
			return false, "There's no weather to change outside the world."
		end
		db.weather = nil
		Notify()
		return true, "The server's weather again."
	end
	kind = tonumber(kind)
	if not (kind and kind >= 0 and kind <= 3 and kind == math.floor(kind)) then
		return false, "Weather is 0 (clear), 1 (rain), 2 (snow) or 3 (sandstorm)."
	end
	intensity = tonumber(intensity) or 0.55
	if kind == 0 then
		intensity = 0
	elseif not (intensity >= 0.05 and intensity <= 1) then
		return false, "Weather strength is 5% to 100%."
	end
	intensity = math.floor(intensity * 100 + 0.5) / 100
	if not pcall(DmorphHelper_SetWeather, kind, intensity) then
		return false, "There's no weather to change outside the world."
	end
	db.weather = { kind, intensity }
	Notify()
	return true, "Weather: " .. M.DescribeWeather(kind, intensity) .. ". Only you see it, outdoors."
end

-- The weather you picked (kind, intensity; nil: the server's) and the
-- server's (kind, intensity; nil without DmorphHelper v8).
function M.GetWeather()
	InitDB()
	local serverKind, serverIntensity
	if HasWeather() then
		local ok, _, _, _, k, i = pcall(DmorphHelper_GetWeather)
		if ok then
			serverKind, serverIntensity = k, i
		end
	end
	if db.weather then
		return db.weather[1], db.weather[2], serverKind, serverIntensity
	end
	return nil, nil, serverKind, serverIntensity
end

-- enchantID: an enchant whose glow the slot shows, 0 for no glow, nil for
-- your own.
function M.SetGlow(slot, enchantID)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	if not GLOW_SLOT[slot] then
		return false, "Glows show on weapons: main hand (16), off hand (17) or ranged (18)."
	end
	if enchantID ~= nil then
		enchantID = ParseID(enchantID)
		if not enchantID or enchantID > 1000000 then
			return false, "Enchant IDs are whole numbers."
		end
	end
	db.glows[slot] = enchantID
	WatchHelper()
	Notify()
	if not enchantID then
		return true, SLOT_NAMES[slot] .. ": your own glow."
	end
	return true, SLOT_NAMES[slot] .. ": " .. M.DescribeGlow(enchantID) .. "."
end

M.LOOK_ROWS = { "Skin colour", "Face", "Hair style", "Hair colour", "Facial hair" }

local function RowName(f, gender)
	if f == 5 and gender == 1 then
		return "Features"
	end
	return M.LOOK_ROWS[f]
end
M.LookRowName = RowName

local function NoOptions(race, gender)
	if not race then
		return "Couldn't detect your race, pick one first."
	end
	return "There's no skin, face and hair list for " .. M.DescribeBody(race, gender)
		.. " yet. Close the game and run tools\\update_from_game.ps1, then try again."
end

-- "the face and hair colour"
local function JoinRows(rows, gender)
	local names = {}
	for i = 1, table.getn(rows) do
		table.insert(names, strlower(RowName(rows[i], gender)))
	end
	local n = table.getn(names)
	if n == 1 then
		return names[1]
	end
	return table.concat(names, ", ", 1, n - 1) .. " and " .. names[n]
end

local function PickLook(race, gender, look)
	db.looks[race .. ":" .. gender] = CopyLook(look)
	WatchHelper()
	Notify()
end

-- Your model (race morph or your own) with these five values, made valid for
-- it. Returns ok, message.
function M.SetOwnLook(values)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	local race, gender, o = M.GetLookState()
	if not o then
		return false, NoOptions(race, gender)
	end
	local look = CopyLook(values)
	local changed = ClampLook(o, look)
	PickLook(race, gender, look)
	if table.getn(changed) > 0 then
		return true, M.DescribeBody(race, gender) .. " has no such " .. JoinRows(changed, gender)
			.. ", so the closest one is on."
	end
	return true, "Look set."
end

-- Row f (1-5) of your model's look one value along (step 1 or -1, wrapping).
-- A row whose new value doesn't go with another row (a face is per skin
-- colour, a hair colour per hair style) moves that one to its closest value.
function M.StepOwnLook(f, step)
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	local race, gender, o, current = M.GetLookState()
	if not o then
		return false, NoOptions(race, gender)
	end
	if not current then
		return false, "Couldn't read your look from the game."
	end
	local look = CopyLook(current)
	ClampLook(o, look)
	local values = LookChoices(o, look, f)
	local n = table.getn(values)
	if n < 2 then
		return false, M.DescribeBody(race, gender) .. " has just one " .. strlower(RowName(f, gender)) .. "."
	end
	local pos = 1
	for i = 1, n do
		if values[i] == look[f] then
			pos = i
		end
	end
	pos = math.mod(pos - 1 + step + n, n) + 1
	look[f] = values[pos]
	local changed = ClampLook(o, look)
	PickLook(race, gender, look)
	local message = RowName(f, gender) .. " " .. pos .. " of " .. n
	local _, _, npc = M.LookRow(o, look, f)
	if npc then
		message = message .. " (an NPC-only one)"
	end
	message = message .. "."
	if table.getn(changed) > 0 then
		message = message .. " The " .. JoinRows(changed, gender) .. " changed too: this one doesn't come with the old one."
	end
	return true, message
end

-- A random look for your model, from everything its race can wear.
function M.RandomOwnLook()
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	local race, gender, o, current = M.GetLookState()
	if not o then
		return false, NoOptions(race, gender)
	end
	local look = CopyLook(current or { 0, 0, 0, 0, 0 })
	for try = 1, 5 do
		for f = 1, 5 do
			local values = LookChoices(o, look, f)
			if table.getn(values) > 0 then
				look[f] = values[math.random(table.getn(values))]
			end
		end
		if not SameValues(look, current) then
			break
		end
	end
	PickLook(race, gender, look)
	return true, "A random " .. M.DescribeBody(race, gender) .. " look."
end

-- Back to your real skin, face and hair on the model you show.
function M.ResetOwnLook()
	local ok, err = HelperBegin()
	if not ok then
		return false, err
	end
	local race, gender = M.GetBodyRace()
	if race then
		db.looks[race .. ":" .. gender] = nil
	end
	WatchHelper()
	Notify()
	return true, "Your own face, skin and hair."
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
	WatchHelper()
	ApplyWeather()
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
		return false, MissingAPI()
	end
	db.display, db.race, db.gender = nil, nil, 0
	db.looks = {}
	local ok, err = ApplyBody()
	WatchHelper()
	return Result(ok, err, "Model reset.")
end

function M.ResetAll()
	if not Begin() then
		return false, MissingAPI()
	end
	db.display, db.race, db.gender = nil, nil, 0
	db.looks, db.glows, db.scale = {}, {}, nil
	local ok, err = ApplyBody()
	WatchHelper()
	db.mount, db.mountSkins = nil, {}
	StopSkin()
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
		return false, MissingAPI()
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
		return false, MissingAPI()
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
		return false, MissingAPI()
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
		return false, MissingAPI()
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

-- Gives your mount a skin: any creature model, shown whenever you ride. real
-- (a display ID from GetRiddenMounts) sets it for that mount only, else for
-- all your mounts. displayID 0 takes the skin off.
function M.SetMountSkin(displayID, real)
	if not Begin() then
		return false, MissingAPI()
	end
	if not HasMountAPI() then
		return false, "This VanillaHelpers can't morph mounts: update it to v1.1.0 or newer."
	end
	displayID = ParseID(displayID)
	if not displayID then
		return false, "Display IDs are whole numbers."
	end
	if displayID == 0 then
		displayID = nil
	end
	local target = "all your mounts"
	if real then
		db.mountSkins[real] = displayID
		target = M.DescribeDisplay(real)
	else
		db.mount = displayID
	end
	WatchMount()
	Notify()
	if not displayID then
		return true, "Skin for " .. target .. " removed."
	end
	local when = " It shows when you mount."
	if watch.active then
		when = ""
	end
	return true, "Skin for " .. target .. ": " .. M.DescribeDisplay(displayID) .. "." .. when
end

-- The skin for all your mounts (.mount, favourites).
function M.SetMount(displayID)
	return M.SetMountSkin(displayID)
end

-- Puts on every piece of set `index` (its position in GetSetCatalog) whose
-- slot is known. Slots the set has no piece for keep what they show.
function M.WearSet(index)
	if not Begin() then
		return false, MissingAPI()
	end
	local catalog = M.GetSetCatalog()
	local pieces = catalog.pieces[index]
	if not pieces then
		return false, "Pick a set in the list first."
	end
	local used, worn, unknown = {}, 0, 0
	local ok, err = true, nil
	for i = 1, table.getn(pieces) do
		local slots = M.GetItemSlots(pieces[i])
		local slot
		if slots then
			-- A second one-hand weapon goes in the off hand.
			for k = 1, table.getn(slots) do
				if not used[slots[k]] then
					slot = slots[k]
					break
				end
			end
		else
			unknown = unknown + 1
		end
		if slot then
			used[slot] = true
			worn = worn + 1
			db.items[slot] = pieces[i]
			local slotOK, slotErr = ApplyItem(slot)
			if ok and not slotOK then
				ok, err = slotOK, slotErr
			end
		end
	end
	local later = ""
	if unknown > 0 then
		later = " " .. unknown .. " more still being looked up: try again in a minute."
	end
	if worn == 0 then
		Notify()
		return false, "None of " .. catalog.names[index] .. "'s pieces are known yet." .. later
	end
	local count = worn .. " pieces"
	if worn == 1 then
		count = "1 piece"
	end
	return Result(ok, err, "Wearing " .. catalog.names[index] .. " (" .. count .. ")." .. later)
end

-- Favourites ----------------------------------------------------------------

-- Models and mounts kept at hand, shared by all your characters: a list of
-- { id = displayID, mount = true or nil }, oldest first.
function M.GetFavourites()
	InitDB()
	return account.favourites
end

local function FindFavourite(displayID, mount)
	local list = account.favourites
	for i = 1, table.getn(list) do
		if list[i].id == displayID and list[i].mount == mount then
			return i
		end
	end
end

function M.IsFavourite(displayID, mount)
	InitDB()
	return FindFavourite(displayID, mount and true or nil) ~= nil
end

-- Adds the model (or, with mount set, the mount) to the favourites, or takes
-- it off if it's there already.
function M.ToggleFavourite(displayID, mount)
	InitDB()
	displayID = ParseID(displayID)
	if not displayID or displayID == 0 then
		return false, "Pick a model first."
	end
	mount = mount and true or nil
	local what = "favourite models"
	if mount then
		what = "favourite mounts"
	end
	local index = FindFavourite(displayID, mount)
	if index then
		table.remove(account.favourites, index)
		return true, "Removed " .. M.DescribeDisplay(displayID) .. " from your " .. what .. "."
	end
	table.insert(account.favourites, { id = displayID, mount = mount })
	return true, "Added " .. M.DescribeDisplay(displayID) .. " to your " .. what .. "."
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
		return false, MissingAPI()
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
	db.mount = outfit.mount
	-- The outfit's glows, and its look for its body (else your own).
	db.glows = {}
	for slot, enchantID in pairs(outfit.glows) do
		db.glows[slot] = enchantID
	end
	local race, gender = M.GetBodyRace()
	if race then
		db.looks[race .. ":" .. gender] = nil
	end
	local look = outfit.look
	if look and look.race == race and look.gender == gender then
		db.looks[race .. ":" .. gender] = ValidLook(look)
	end
	WatchHelper()
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
	Print(".mount <displayID> - morph your mount (.mount 0 resets)")
	Print(".scale <size> - your size, e.g. .scale 0.5 or .scale 2 (.scale 0 resets; needs DmorphHelper)")
	Print(".weather <clear/rain/snow/sandstorm> [light/heavy/5-100%] - the weather on your screen (.weather off: the server's; needs DmorphHelper)")
	Print(".time <hh:mm or dawn/noon/dusk/night> - the time of day on your screen (.time off: the real one; needs DmorphHelper)")
	Print(".glow <mainhand/offhand/ranged> <enchantID> - a weapon's enchant glow (0 none, own your own); needs DmorphHelper.dll")
	Print(".share on/off - whether other DMorph users see your morph; .share others on/off - whether you see theirs")
	Print(".dmorph status - show what is morphed; .dmorph check - is everything DMorph needs running, and how to fix it. Keys: Key Bindings > DMorph.")
	if not HasMorphAPI() then
		Print(MissingAPI())
	end
end

local function ShowStatus()
	if not HasMorphAPI() then
		Print(MissingAPI())
	elseif type(VANILLAHELPERS_VERSION) == "number" then
		Print("VanillaHelpers v" .. VersionText(VANILLAHELPERS_VERSION) .. " is loaded.")
	end
	local helperVersion = M.GetHelperVersion()
	if helperVersion and helperVersion < HELPER_VERSION then
		Print("DmorphHelper v" .. helperVersion .. " is loaded, an older one: this DMorph comes with v" .. HELPER_VERSION .. ". "
			.. INSTALL_HELPER)
	elseif helperVersion then
		Print("DmorphHelper v" .. helperVersion .. " is loaded: weapon glows, size and real skin, face and hair work.")
	else
		Print("DmorphHelper.dll is not loaded: weapon glows and real skin, face and hair changes need it. " .. INSTALL_HELPER)
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
	for i = 1, table.getn(M.GLOW_SLOTS) do
		local slot = M.GLOW_SLOTS[i]
		if db.glows[slot] then
			Print("Glow, " .. strlower(SLOT_NAMES[slot]) .. ": " .. M.DescribeGlow(db.glows[slot]) .. ".")
		end
	end
	local bodies = {}
	for key in pairs(db.looks) do
		local _, _, race, gender = strfind(key, "^(%d+):(%d)$")
		table.insert(bodies, M.DescribeBody(tonumber(race), tonumber(gender)))
	end
	if table.getn(bodies) > 0 then
		table.sort(bodies)
		Print("Own face, skin and hair picked for: " .. table.concat(bodies, ", ") .. ".")
	end
	if db.mount then
		Print("Mount skin: " .. M.DescribeDisplay(db.mount) .. ".")
	end
	if db.scale then
		Print(format("Size: %d%%.", math.floor(db.scale * 100 + 0.5)))
	end
	if db.weather then
		Print("Weather: " .. M.DescribeWeather(db.weather[1], db.weather[2]) .. ".")
	end
	if db.time then
		Print("Time of day: " .. M.DescribeTime(db.time) .. ".")
	end
	for real, skin in pairs(db.mountSkins) do
		Print("Skin for " .. M.DescribeDisplay(real) .. ": " .. M.DescribeDisplay(skin) .. ".")
	end
end

local commands = {}
-- Other files (Share.lua) add their own chat commands here.
M.commands = commands

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

function commands.mount(args)
	local displayID = ParseID(args[1] or "0")
	if not displayID then
		return Print("Usage: .mount <displayID>  (.mount 0 resets)")
	end
	Report(M.SetMount(displayID))
end

-- .glow mainhand 1900, .glow offhand 0 (no glow), .glow ranged own.
function commands.glow(args)
	local word = strlower(args[1] or "")
	local slot = SLOT_ALIASES[word] or ({ mh = 16, oh = 17 })[word] or ParseID(word)
	local value = strlower(args[2] or "")
	local enchantID = ParseID(value)
	if not (slot and GLOW_SLOT[slot]) or not (enchantID or value == "own") then
		return Print("Usage: .glow <mainhand/offhand/ranged> <enchantID>  (0 for no glow, own for your own)")
	end
	Report(M.SetGlow(slot, enchantID))
end
commands.enchant = commands.glow

function commands.scale(args)
	local word = strlower(args[1] or "")
	if word == "" or word == "0" or word == "reset" or word == "own" then
		return Report(M.SetScale(nil))
	end
	-- .scale 1.5 or .scale 150%
	local _, _, number, percent = strfind(word, "^([%d%.]+)(%%?)$")
	local scale = tonumber(number or "")
	if scale and percent == "%" then
		scale = scale / 100
	end
	if not scale then
		return Print("Usage: .scale <size>, e.g. .scale 0.5 (half), .scale 2 or .scale 200% (double); .scale 0 resets.")
	end
	Report(M.SetScale(scale))
end

-- .time 22:30, .time 9, .time night, .time off
function commands.time(args)
	local word = strlower(args[1] or "")
	if word == "off" or word == "real" or word == "server" or word == "reset" then
		return Report(M.SetTime(nil))
	end
	local minutes = TIME_WORDS[word]
	if not minutes then
		local _, _, hours, mins = strfind(word, "^(%d%d?)[:%.]?(%d?%d?)$")
		hours, mins = tonumber(hours or ""), tonumber(mins ~= "" and mins or "0")
		if hours and mins and hours < 24 and mins < 60 then
			minutes = hours * 60 + mins
		end
	end
	if not minutes then
		return Print("Usage: .time <hh:mm or dawn/noon/dusk/night>, e.g. .time 22:30; .time off for the real time.")
	end
	Report(M.SetTime(minutes))
end

-- .weather rain heavy, .weather snow 40, .weather 3 0.8, .weather off
function commands.weather(args)
	local word = strlower(args[1] or "")
	if word == "off" or word == "server" or word == "reset" or word == "own" then
		return Report(M.SetWeather(nil))
	end
	local kind = WEATHER_WORDS[word] or tonumber(word)
	local strength = strlower(args[2] or "")
	local intensity = WEATHER_STRENGTH[strength]
	if not intensity and strength ~= "" then
		local _, _, number, percent = strfind(strength, "^([%d%.]+)(%%?)$")
		intensity = tonumber(number or "")
		if intensity and (percent == "%" or intensity > 1) then
			intensity = intensity / 100
		end
	end
	if not kind or (strength ~= "" and not intensity) then
		return Print("Usage: .weather <clear/rain/snow/sandstorm> [light/heavy or 5-100%], e.g. .weather rain heavy; "
			.. ".weather off for the server's weather.")
	end
	Report(M.SetWeather(kind, intensity))
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

-- /dmorph check: is everything DMorph uses running, and how to fix what isn't.
local CHECK_COLOURS = { ok = "|cff33ff99", bad = "|cffff5555", off = "|cffaaaaaa" }
local CHECK_WORDS = { ok = "OK", bad = "NOT WORKING", off = "not running" }

local function ShowCheck()
	local report = M.GetSetupReport()
	for i = 1, table.getn(report) do
		local entry = report[i]
		Print(entry.name .. ": " .. CHECK_COLOURS[entry.state] .. CHECK_WORDS[entry.state] .. "|r - " .. entry.text)
	end
end

function commands.dmorph(args)
	local action = strlower(args[1] or "")
	if action == "status" then
		return ShowStatus()
	elseif action == "check" then
		return ShowCheck()
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

-- Chat that is spoken in a language (the rest, like emotes, isn't).
local SPOKEN = {
	SAY = true, YELL = true, PARTY = true, RAID = true, RAID_WARNING = true, GUILD = true,
	OFFICER = true, WHISPER = true, CHANNEL = true, BATTLEGROUND = true,
}

-- A race morph also changes your race in VanillaHelpers, and the game then
-- speaks that race's language by default and lists that race's languages: as
-- an Undead morphed into a Gnome, "You don't know that language" (Common).
-- So chat goes out in a language your own character speaks (read with your
-- own race showing, see CaptureNative): the one asked for if you speak it,
-- else your own default, else your faction's (Orcish / Common), else the first.
local function SpeakableLanguage(language)
	local list, default = db and db.languages, db and db.defaultLanguage
	if not list then
		-- Not read yet (no morph this session): the game's own list is right.
		list = {}
		for i = 1, 20 do
			local ok, name = pcall(GetLanguageByIndex, i)
			if not (ok and name) then
				break
			end
			table.insert(list, name)
		end
		local ok, live = pcall(GetDefaultLanguage)
		default = ok and live or nil
	end
	local known, count = {}, table.getn(list)
	for i = 1, count do
		known[list[i]] = true
	end
	if count == 0 or (language and known[language]) then
		return language
	end
	if default and known[default] then
		return default
	end
	local faction = UnitFactionGroup("player")
	if faction == "Horde" and known["Orcish"] then
		return "Orcish"
	elseif faction == "Alliance" and known["Common"] then
		return "Common"
	end
	return list[1]
end

-- DMorph's interface: commands typed into chat with a leading dot. Anything
-- that isn't one of our commands still goes to the server as before, in a
-- language you know (see above).
local orig_SendChatMessage = SendChatMessage
function SendChatMessage(msg, chatType, language, channel)
	if type(msg) == "string" then
		local _, _, line = strfind(msg, "^%s*%.(.*)$")
		if line and RunCommand(line) then
			return
		end
	end
	if SPOKEN[strupper(chatType or "SAY")] then
		language = SpeakableLanguage(language)
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
			Print(MissingAPI())
			Print("Open the window (/dmorph) and click Setup, or type /dmorph check, to see what's running.")
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
		raceHeld = {} -- a loading screen closed the windows that held it
		ApplySaved()
	end
end)

-- Your own race while the flight map, spellbook or reputation list is open
-- (see HoldRace). Blizzard's TaxiFrame handles TAXIMAP_OPENED before us, so
-- once the race is back it draws the flight paths again; the spellbook and
-- reputation list are held before they read their spells and standings.
local held = {}
local function HoldWhileShown(frame, reason)
	if not frame or held[reason] then
		return
	end
	held[reason] = true
	local onShow, onHide = frame:GetScript("OnShow"), frame:GetScript("OnHide")
	frame:SetScript("OnShow", function()
		M.HoldRace(reason, true)
		if onShow then
			onShow()
		end
	end)
	frame:SetScript("OnHide", function()
		if onHide then
			onHide()
		end
		M.HoldRace(reason, false)
	end)
end

local raceFrame = CreateFrame("Frame")
raceFrame:RegisterEvent("TAXIMAP_OPENED")
raceFrame:RegisterEvent("TAXIMAP_CLOSED")
raceFrame:RegisterEvent("PLAYER_LOGIN")
raceFrame:SetScript("OnEvent", function()
	if event == "TAXIMAP_OPENED" then
		if M.HoldRace("taxi", true) and TaxiFrame and type(TaxiFrame_OnEvent) == "function" then
			local saved = this
			this = TaxiFrame
			pcall(TaxiFrame_OnEvent, "TAXIMAP_OPENED")
			this = saved
		end
	elseif event == "TAXIMAP_CLOSED" then
		M.HoldRace("taxi", false)
	elseif event == "PLAYER_LOGIN" then
		HoldWhileShown(SpellBookFrame, "spellbook")
		HoldWhileShown(ReputationFrame, "reputation")
	end
end)

-- Item lookup runs in the background from shortly after login until every
-- pending item has an answer.
local lookupFrame = CreateFrame("Frame")
lookupFrame:Hide()
lookupFrame:SetScript("OnUpdate", function()
	this.elapsed = this.elapsed + arg1
	if this.elapsed >= LOOKUP_STEP then
		if LookupTick(this.elapsed) then
			this:Hide()
		end
		this.elapsed = 0
	end
end)
lookupFrame:SetScript("OnEvent", function()
	LookupAnswer(arg1, arg2)
end)

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loginFrame:SetScript("OnEvent", function()
	this:UnregisterEvent("PLAYER_ENTERING_WORLD")
	InitDB()
	StartLookup()
	if CanAskServer() then
		pcall(lookupFrame.RegisterEvent, lookupFrame, "ITEM_DATA_LOAD_RESULT")
	end
	lookupFrame.elapsed = -15 -- let the login settle first
	lookupFrame:Show()
end)

-- A picked weather: the helper keeps it when the server sends a zone's
-- weather; entering a new zone puts it on again in case none came.
local weatherFrame = CreateFrame("Frame")
weatherFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
weatherFrame:SetScript("OnEvent", function()
	ApplyWeather()
end)

-- The mount watcher: puts the mount skin on while you ride (see Mount skins).
local mountFrame = CreateFrame("Frame")
mountFrame:SetScript("OnUpdate", function()
	this.wait = (this.wait or 0) - arg1
	if this.wait <= 0 then
		this.wait = 0.1
		WatchMount()
		KeepRace()
	end
end)
-- Losing and getting back control (a flight path starts and lands, a fear,
-- a stun) takes the skin off: if you're still on your mount, the watcher
-- sees its buff and puts the skin on again a tenth of a second later.
mountFrame:RegisterEvent("PLAYER_CONTROL_LOST")
mountFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
mountFrame:SetScript("OnEvent", function()
	if watch.active then
		StopSkin()
		watch.real = nil
		Notify()
	end
end)

-- The DmorphHelper watcher: keeps the picked glows and look on (see Glows and
-- your own look).
local helperFrame = CreateFrame("Frame")
helperFrame:SetScript("OnUpdate", function()
	helperHold = helperHold - arg1
	helperWait = helperWait - arg1
	if helperWait <= 0 then
		helperWait = 1
		WatchHelper()
	end
end)
