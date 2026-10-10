-- Offline tests for DmorphOcto.lua.
--
-- Loads the addon into a mocked 1.12 client with a fake VanillaHelpers morph
-- API that follows src/Morph.cpp in isfir/VanillaHelpers, then drives it the
-- way the game does (events, OnUpdate, chat, slash commands, /reload).
--
-- Run from the repository root with a Lua 5.0 interpreter (the client's
-- version): lua tests/run_tests.lua

local ADDON_FILE = "DmorphOcto.lua"
local failures, checks = 0, 0

local function check(cond, what)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL: " .. what)
	end
end

-- WoW's global aliases for the string library.
strfind, strsub, strlower, strupper, format =
	string.find, string.sub, string.lower, string.upper, string.format

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

local chat, sent, frames

local function setupUI()
	chat, sent, frames = {}, {}, {}
	DEFAULT_CHAT_FRAME = {
		AddMessage = function(self, msg) table.insert(chat, msg) end,
	}
	function SendChatMessage(msg, chatType)
		table.insert(sent, msg)
	end
	SlashCmdList = {}
	function CreateFrame()
		local f = { scripts = {}, events = {}, shown = true }
		function f:RegisterEvent(e) self.events[e] = true end
		function f:SetScript(name, fn) self.scripts[name] = fn end
		function f:Show() self.shown = true end
		function f:Hide() self.shown = false end
		table.insert(frames, f)
		return f
	end
	function UnitRace() return "Human", "Human" end
	function UnitSex() return 2 end
	function GetItemInfo(id)
		if id == 2955 then
			return "First Mate Hat"
		end
	end
end

local function fire(name, a1)
	for _, f in ipairs(frames) do
		if f.events[name] then
			this, event, arg1 = f, name, a1
			f.scripts.OnEvent()
		end
	end
end

local function tick(elapsed)
	for _, f in ipairs(frames) do
		if f.shown and f.scripts.OnUpdate then
			this, arg1 = f, elapsed
			f.scripts.OnUpdate()
		end
	end
end

-- Loads the addon like a fresh UI (login or /reload) and enters the world.
local function loadUI()
	setupUI()
	dofile(ADDON_FILE)
	fire("VARIABLES_LOADED")
	fire("PLAYER_ENTERING_WORLD")
	tick(0.3)
	tick(0.3)
end

-- What the chat edit box does when you press Enter.
local function say(text)
	chat = {}
	SendChatMessage(text, "SAY")
end

local function lastChat()
	return chat[table.getn(chat)] or ""
end

local function contains(s, part)
	return strfind(s, part, 1, true) ~= nil
end

-- Fresh human male, nothing saved.
newClient(49)
installMorphAPI()
DmorphOctoDB = nil
loadUI()
check(vh.calls == 0, "an empty profile must not touch any morph on login")
check(type(DmorphOctoDB) == "table", "saved variables are created")

say(".morph 4527")
check(vh.display == 4527, ".morph sets the display ID")
check(table.getn(sent) == 0, ".morph is not sent to the server")
check(DmorphOctoDB.display == 4527, ".morph is saved")
check(contains(lastChat(), "4527"), ".morph confirms in chat")

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
say(".item 2 1234")
check(vh.items[2] == nil and contains(lastChat(), "Neck"), ".item rejects invisible slots")
say(".item 1 abc")
check(contains(lastChat(), "Usage"), ".item rejects a bad item ID")
say(".item 1 0")
check(vh.items[1] == nil and DmorphOctoDB.items[1] == nil, ".item <slot> 0 resets the slot")
say(".item 1 2955")

say(".scale 0.5")
check(table.getn(sent) == 0 and contains(lastChat(), "scale"),
	".scale is answered locally and never sent as /say")

say("hello there")
check(sent[1] == "hello there", "normal chat goes through")
say(".help")
check(sent[2] == ".help", "unknown dot commands still reach the server")

SlashCmdList["DMORPHOCTO"]("morph 1060")
check(vh.display == 1060, "/dmorph morph works")
chat = {}
SlashCmdList["DMORPHOCTO"]("status")
local status = table.concat(chat, "\n")
check(contains(status, "v1.1.2") and contains(status, "1060") and contains(status, "Head"),
	"/dmorph status reports version, model and items")
chat = {}
SlashCmdList["DMORPHOCTO"]("")
check(table.getn(chat) > 3, "/dmorph alone shows help")

-- /reload with a race morph active: the fake DLL keeps its overrides, so the
-- native display it reports is the morphed one until we clear it.
say(".race 6")
say(".gender")
check(vh.display == 60 and vh.native == 60, "Tauren female applied before reload")
loadUI()
check(vh.display == 60, "race morph is re-applied after /reload")
chat = {}
SlashCmdList["DMORPHOCTO"]("status")
check(contains(table.concat(chat, "\n"), "Your character: Human male"),
	"native race is read correctly after /reload")
say(".gender")
check(vh.display == 59, ".gender after /reload uses the morphed race")
check(vh.items[1] == 2955 and vh.items[5] == 6795, "item morphs survive /reload")

-- Zoning: the server resends the real model, the addon puts the morph back.
vh.display, vh.native, vh.items = 49, 49, {}
fire("PLAYER_ENTERING_WORLD")
tick(0.6)
check(vh.display == 59 and vh.items[1] == 2955, "morph is re-applied after a loading screen")

DmorphOcto_Reset()
check(vh.display == 49 and vh.items[1] == 2955, "reset binding keeps items")
DmorphOcto_ResetAll()
check(vh.items[1] == nil and vh.items[5] == nil, "reset-all binding clears items")
check(next(DmorphOctoDB.items) == nil and DmorphOctoDB.display == nil and DmorphOctoDB.race == nil,
	"reset-all clears the saved profile")

-- A female Goblin: .gender without a race morph uses the native race.
newClient(6895)
DmorphOctoDB = nil
loadUI()
say(".gender")
check(vh.display == 6894, ".gender on a native Goblin female gives Goblin male")

-- Corrupt saved variables are dropped instead of being sent to the DLL.
newClient(49)
DmorphOctoDB = { display = "x", race = 42, gender = 7, items = { [2] = 5, [1] = -3, [5] = 10 } }
loadUI()
check(DmorphOctoDB.display == nil and DmorphOctoDB.race == nil, "bad body values are dropped")
check(DmorphOctoDB.items[2] == nil and DmorphOctoDB.items[1] == nil and DmorphOctoDB.items[5] == 10,
	"only valid item morphs are kept")
check(vh.items[5] == 10 and vh.display == 49, "valid saved items are applied")

newClient(49)
DmorphOctoDB = { display = "4527", items = { [1] = "2955" } }
loadUI()
check(DmorphOctoDB.display == 4527 and DmorphOctoDB.items[1] == 2955,
	"numeric strings in saved variables become numbers")
check(vh.display == 4527 and vh.items[1] == 2955, "normalised saved morphs are applied")

-- Without VanillaHelpers, commands explain what is missing and stay local.
newClient(49)
removeMorphAPI()
DmorphOctoDB = nil
loadUI()
check(contains(lastChat(), "VanillaHelpers"), "missing DLL is reported at login")
say(".morph 4527")
check(table.getn(sent) == 0 and contains(lastChat(), "VanillaHelpers"),
	"commands without the DLL explain instead of being sent")
chat = {}
SlashCmdList["DMORPHOCTO"]("")
check(contains(table.concat(chat, "\n"), "VanillaHelpers"), "help mentions the missing DLL")

print(format("%d checks, %d failures", checks, failures))
if failures > 0 then
	os.exit(1)
end
