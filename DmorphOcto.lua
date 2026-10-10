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

local VERSION = "1.6.0"
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
M.MODEL_FILTERS = {
	{ text = "All models" },
	{ text = "Creatures", kinds = { [0] = true, [2] = true } },
	{ text = "Bosses", tag = "boss" },
	{ text = "Rare creatures", tag = "rare" },
	{ text = "Mounts", tag = "mount" },
	{ text = "Other models", kinds = { [1] = true, [3] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true, [3] = true } },
}
-- Items and sets are kind 0 (stock 1.12.1) or 2 (added by Turtle WoW / OctoWoW).
M.ITEM_FILTERS = {
	{ text = "All items" },
	{ text = "1.12 items", kinds = { [0] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true } },
}
M.SET_FILTERS = {
	{ text = "All sets" },
	{ text = "1.12 sets", kinds = { [0] = true } },
	{ text = "New in OctoWoW", kinds = { [2] = true } },
}
-- Item and set quality, as GetItemInfo() numbers it.
M.QUALITY_FILTERS = {
	{ text = "Any quality" },
	{ text = "Poor", quality = 0 },
	{ text = "Common", quality = 1 },
	{ text = "Uncommon", quality = 2 },
	{ text = "Rare", quality = 3 },
	{ text = "Epic", quality = 4 },
	{ text = "Legendary", quality = 5 },
}

-- Creatures.lua (named creatures) and Models.lua (every other display ID the
-- client has) together list every model.
function M.GetCreatureCatalog()
	if creatures then
		return creatures
	end
	local named, other, n, m = {}, {}, 0, 0
	for id, name in string.gfind(DmorphOcto_CreatureData or "", "(%d+)\t([^\r\n]+)") do
		n = n + 1
		named[n] = { tonumber(id), name, strlower(name), 0, M.KIND_CREATURE }
	end
	for id, kind, name in string.gfind(DmorphOcto_ModelData or "", "(%d+)\t(%d)\t([^\r\n]+)") do
		m = m + 1
		other[m] = { tonumber(id), name, strlower(name), 0, tonumber(kind) }
	end
	DmorphOcto_CreatureData, DmorphOcto_ModelData = nil, nil -- the parsed tables replace the text
	creatures = Fill(NewCatalog(), Merge(named, n, other, m))
	-- Tags for the filters (Data/ModelTags.lua): bosses and rares by display and
	-- name, mounts by display.
	local byName, mounts = {}, {}
	for id, tag, name in string.gfind(DmorphOcto_TagData or "", "(%d+)\t(%a+)\t([^\r\n]*)") do
		if tag == "mount" then
			mounts[tonumber(id)] = true
		else
			byName[id .. "\t" .. strlower(name)] = tag
		end
	end
	DmorphOcto_TagData = nil
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

local function ParseItems(text, kind, list, n, skip)
	for id, quality, name in string.gfind(text or "", "(%d+)\t(%d)\t([^\r\n]+)") do
		id = tonumber(id)
		if not (skip and skip[id]) then
			n = n + 1
			list[n] = { id, name, strlower(name), tonumber(quality), kind }
		end
	end
	return list, n
end

-- Items the game told us about in this or an earlier session (see Item
-- lookup), saved as DmorphOctoAccount.itemInfo[id] = "slots<TAB>quality<TAB>name".
local function LearnedItems(slot, skip)
	local list, n = {}, 0
	for id, info in pairs(account.itemInfo) do
		if info and not skip[id] then
			local _, _, slots, quality, name = strfind(info, "^([%d,]+)\t(%-?%d+)\t(.+)$")
			if slots and strfind("," .. slots .. ",", "," .. slot .. ",", 1, true) then
				n = n + 1
				list[n] = { id, name, strlower(name), tonumber(quality), M.KIND_NEW }
			end
		end
	end
	table.sort(list, Before)
	return list, n
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
		items[slot] = Fill(NewCatalog(), Merge(both, count, learned, k))
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
		for i = 1, sets.count do
			local best
			for k = 1, table.getn(sets.pieces[i]) do
				local quality = ItemQuality(sets.pieces[i][k])
				if quality and (not best or quality > best) then
					best = quality
				end
			end
			sets.quality[i] = best
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
		local list, n = {}, 0
		local text = DmorphOcto_LookData and DmorphOcto_LookData[key] or ""
		for a, b, c, d, e, f, g, h in string.gfind(text, "(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)") do
			n = n + 1
			list[n] = { tonumber(a), tonumber(b), tonumber(c), tonumber(d), tonumber(e), tonumber(f), tonumber(g), tonumber(h) }
		end
		looks[key] = list
	end
	return looks[key]
end

-- The character creator's choices: look fields 2-6. Picking a value finds the
-- look with it that keeps the most of the other choices (skin first, then hair
-- style, hair colour, face and facial hair), in the fewest clothes.
M.LOOK_FEATURES = { "Skin colour", "Face", "Hair style", "Hair colour", "Facial hair" }
local FEATURE_WEIGHTS = { 16, 2, 8, 4, 1 }

-- The values feature f (1-5) has among a race and gender's looks, sorted.
function M.GetLookValues(race, gender, f)
	local list = M.GetLooks(race, gender)
	local seen, values = {}, {}
	for k = 1, table.getn(list) do
		local v = list[k][f + 1]
		if not seen[v] then
			seen[v] = true
			table.insert(values, v)
		end
	end
	table.sort(values)
	return values
end

-- The position of the look that has `value` for feature f and is closest to
-- look `from` (a position in the same list), or nil.
function M.FindLook(race, gender, f, value, from)
	local list = M.GetLooks(race, gender)
	local want = list[from]
	local best, bestScore
	for k = 1, table.getn(list) do
		local look = list[k]
		if look[f + 1] == value then
			local score = 0
			if want then
				for g = 1, 5 do
					if g ~= f and look[g + 1] == want[g + 1] then
						score = score + FEATURE_WEIGHTS[g]
					end
				end
			end
			score = score * 20 - look[7]
			if not best or score > bestScore then
				best, bestScore = k, score
			end
		end
	end
	return best
end

-- The choices for feature f (1-5) that keep look `from`'s other four features
-- exactly: NPC looks are fixed combinations, so only the values some NPC has
-- with all of them. For each value, the look in the same outfit if an NPC
-- wears it, else the closest in clothes. Returns the sorted values (the
-- current one included) and { [value] = position in the list }.
function M.GetLookChoices(race, gender, f, from)
	local list = M.GetLooks(race, gender)
	local cur = list[from]
	local values, at, gaps = {}, {}, {}
	if not cur then
		return values, at
	end
	for k = 1, table.getn(list) do
		local look = list[k]
		local same = true
		for g = 1, 5 do
			if g ~= f and look[g + 1] ~= cur[g + 1] then
				same = false
				break
			end
		end
		if same then
			local v = look[f + 1]
			local gap = math.abs(look[7] - cur[7])
			if k == from then
				gap = -2
			elseif look[8] == cur[8] then
				gap = -1
			end
			if not at[v] then
				table.insert(values, v)
			end
			if not at[v] or gap < gaps[v] then
				at[v], gaps[v] = k, gap
			end
		end
	end
	table.sort(values)
	return values, at
end

-- Feature f (1-5) of look `from` one choice along, in direction step: only f
-- changes. Returns the new look's position, or nil when no NPC has another
-- value of f with the other four features.
function M.StepLook(race, gender, f, from, step)
	local values, at = M.GetLookChoices(race, gender, f, from)
	local n = table.getn(values)
	if n < 2 then
		return nil
	end
	local cur = M.GetLooks(race, gender)[from][f + 1]
	local pos = 1
	for i = 1, n do
		if values[i] == cur then
			pos = i
		end
	end
	pos = math.mod(pos - 1 + step + n, n) + 1
	return at[values[pos]]
end

-- The positions of the looks with the same face, skin and hair as look
-- `from`: its outfits, the fewest clothes first.
function M.GetLookOutfits(race, gender, from)
	local list = M.GetLooks(race, gender)
	local want, out = list[from], {}
	if want then
		for k = 1, table.getn(list) do
			local look = list[k]
			if look[2] == want[2] and look[3] == want[3] and look[4] == want[4] and look[5] == want[5] and look[6] == want[6] then
				table.insert(out, k)
			end
		end
	end
	return out
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
local function Keep(catalog, i, filter, quality)
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
-- containing it. byID lists them by ID instead.
function M.FilterCatalog(catalog, text, filter, quality, byID)
	local query = strlower(Trim(text))
	local result, n = {}, 0
	local number = ParseID(query)
	local later, m = {}, 0
	for i = 1, catalog.count do
		if Keep(catalog, i, filter, quality) then
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
	local mount = ""
	if outfit.mount then
		mount = ", mount"
	end
	if count == 1 then
		return look .. ", 1 item" .. mount
	end
	return look .. ", " .. count .. " items" .. mount
end

-- State ---------------------------------------------------------------------

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
	return outfit
end

local function CopyOutfit(outfit)
	local copy = { display = outfit.display, race = outfit.race, gender = outfit.gender, mount = outfit.mount, items = {} }
	for slot, itemID in pairs(outfit.items) do
		copy.items[slot] = itemID
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
	-- The mount skin is put back on by the mount watcher once you ride.
	if type(SetUnitMountDisplayID) == "function" and (db.mount or next(db.mountSkins)) then
		Morph(SetUnitMountDisplayID, "player", nil)
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
local function WatchMount()
	if not (sessionReady and HasMountAPI()) then
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
		local skin = SkinFor(watch.real)
		if not skin then
			StopSkin()
		elseif skin ~= watch.skin then
			watch.skin = skin
			Morph(SetUnitMountDisplayID, "player", skin)
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
			if not found then
				candidates = buffs -- mounted before we could look: any buff going counts
			end
			if any then
				watch.candidates, watch.skin, watch.active = candidates, skin, true
				Morph(SetUnitMountDisplayID, "player", skin)
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

-- Gives your mount a skin: any creature model, shown whenever you ride. real
-- (a display ID from GetRiddenMounts) sets it for that mount only, else for
-- all your mounts. displayID 0 takes the skin off.
function M.SetMountSkin(displayID, real)
	if not Begin() then
		return false, MISSING_API
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
		return false, MISSING_API
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
	db.mount = outfit.mount
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
	if db.mount then
		Print("Mount skin: " .. M.DescribeDisplay(db.mount) .. ".")
	end
	for real, skin in pairs(db.mountSkins) do
		Print("Skin for " .. M.DescribeDisplay(real) .. ": " .. M.DescribeDisplay(skin) .. ".")
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

function commands.mount(args)
	local displayID = ParseID(args[1] or "0")
	if not displayID then
		return Print("Usage: .mount <displayID>  (.mount 0 resets)")
	end
	Report(M.SetMount(displayID))
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

-- The mount watcher: puts the mount skin on while you ride (see Mount skins).
local mountFrame = CreateFrame("Frame")
mountFrame:SetScript("OnUpdate", function()
	this.wait = (this.wait or 0) - arg1
	if this.wait <= 0 then
		this.wait = 0.1
		WatchMount()
	end
end)
