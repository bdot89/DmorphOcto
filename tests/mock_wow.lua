-- A small, strict stand-in for the 1.12 client's UI API, for offline tests.
--
-- Widgets only have methods that exist in 1.12 (checked against Blizzard's
-- 1.12 FrameXML and 1.12-only addons); calling anything else, such as
-- SetSize, is an error. Templates, fonts, layers, anchor points and script
-- names are checked the same way. Scripts run like the client runs them:
-- with `this`, `event` and `arg1` set as globals.

Mock = {}

strfind, strsub, strlower, strupper, strlen, format, floor =
	string.find, string.sub, string.lower, string.upper, string.len, string.format, math.floor
tinsert, getn = table.insert, table.getn

function getglobal(name)
	return _G[name]
end

local POINTS = {
	TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 1, CENTER = 1, RIGHT = 1,
	BOTTOMLEFT = 1, BOTTOM = 1, BOTTOMRIGHT = 1,
}
local LAYERS = { BACKGROUND = 1, BORDER = 1, ARTWORK = 1, OVERLAY = 1, HIGHLIGHT = 1 }
local FONTS = {
	GameFontNormal = 1, GameFontNormalSmall = 1, GameFontNormalLarge = 1,
	GameFontHighlight = 1, GameFontHighlightSmall = 1, GameFontHighlightLarge = 1,
	GameFontDisable = 1, GameFontDisableSmall = 1, GameFontGreenSmall = 1, GameFontRedSmall = 1,
}
local FRAME_TYPES = { Frame = 1, Button = 1, EditBox = 1, ScrollFrame = 1, Model = 1, PlayerModel = 1, DressUpModel = 1, Slider = 1,
	GameTooltip = 1 }
local TEMPLATES = {
	UIPanelButtonTemplate = 1, InputBoxTemplate = 1, FauxScrollFrameTemplate = 1, UIPanelCloseButton = 1,
	GameTooltipTemplate = 1,
}
local SCRIPTS = {
	OnClick = 1, OnEnter = 1, OnLeave = 1, OnMouseWheel = 1, OnVerticalScroll = 1,
	OnTextChanged = 1, OnEnterPressed = 1, OnEscapePressed = 1, OnUpdate = 1, OnEvent = 1,
	OnShow = 1, OnHide = 1, OnDragStart = 1, OnDragStop = 1, OnMouseDown = 1, OnMouseUp = 1,
	OnValueChanged = 1,
	-- Edit box focus (OctoBG's flat edit boxes use them in game).
	OnEditFocusGained = 1, OnEditFocusLost = 1,
}

-- Methods a DLL adds to the client (ClassicAPI): missing unless the test
-- installs them, and probing for them is allowed, as in the client.
local OPTIONAL = { SetDisplayInfo = "classicAPI" }

local methods = {}
local meta = {
	__index = function(widget, key)
		local first = strsub(key, 1, 1)
		if OPTIONAL[key] and not Mock[OPTIONAL[key]] then
			return nil
		end
		if first == strupper(first) and first ~= "_" then
			local method = methods[key]
			if not method then
				error("1.12 has no " .. widget.kind .. ":" .. key .. "()", 2)
			end
			return method
		end
	end,
}

Mock.frames = {}

local function NewWidget(kind, name, parent)
	local widget = setmetatable({ kind = kind, name = name, parent = parent, shown = true, scripts = {},
		events = {}, children = {} }, meta)
	if name then
		_G[name] = widget
	end
	if parent then
		table.insert(parent.children, widget)
	end
	return widget
end

-- Regions and frames
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 0 end
function methods:GetHeight() return self.height or 0 end
function methods:SetPoint(point, relativeTo, relativePoint, x, y)
	assert(POINTS[point], "bad anchor point " .. tostring(point))
	assert(relativePoint == nil or POINTS[relativePoint], "bad relative point " .. tostring(relativePoint))
	assert(relativeTo == nil or type(relativeTo) == "table" or type(relativeTo) == "string", "bad relativeTo")
	self.point = { point, relativeTo, relativePoint, x, y }
	-- Every anchor, for layout checks (tests/layout.lua).
	self.points = self.points or {}
	self.points[point] = { relativeTo, relativePoint or point, x or 0, y or 0 }
end
function methods:ClearAllPoints() self.point, self.points = nil, nil end
function methods:SetAllPoints(target) self.point, self.points = { "ALL", target }, { ALL = target or self.parent } end
function methods:GetName() return self.name end
function methods:GetParent() return self.parent end
function methods:IsShown() return self.shown end
function methods:IsVisible()
	local widget = self
	while widget do
		if not widget.shown then
			return false
		end
		widget = widget.parent
	end
	return true
end
local function RunScript(widget, name, a1)
	local fn = widget.scripts[name]
	if fn then
		local oldThis, oldArg1 = this, arg1
		this, arg1 = widget, a1
		fn()
		this, arg1 = oldThis, oldArg1
	end
end
Mock.RunScript = RunScript
function methods:Show()
	if not self.shown then
		self.shown = true
		if self:IsVisible() then
			RunScript(self, "OnShow")
		end
	end
end
function methods:Hide()
	if self.shown then
		local wasVisible = self:IsVisible()
		self.shown = false
		if wasVisible then
			RunScript(self, "OnHide")
		end
	end
end
function methods:SetScript(name, fn)
	assert(SCRIPTS[name], "unknown script " .. tostring(name))
	assert(fn == nil or type(fn) == "function", name .. " handler must be a function")
	self.scripts[name] = fn
end
function methods:GetScript(name) return self.scripts[name] end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:UnregisterEvent(e) self.events[e] = nil end
function methods:SetBackdrop(backdrop) self.backdrop = backdrop end
function methods:SetBackdropColor() end
function methods:SetBackdropBorderColor(r, g, b) self.border = { r, g, b } end
function methods:EnableMouse(on) self.mouse = on end
function methods:EnableMouseWheel(on) self.wheel = on end
function methods:SetMovable(on) self.movable = on end
function methods:SetClampedToScreen() end
function methods:RegisterForDrag() end
function methods:RegisterForClicks() end
function methods:StartMoving() end
function methods:StopMovingOrSizing() end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetAlpha() end
function methods:SetScale(s) self.scale = s end
function methods:GetScale() return self.scale or 1 end
function methods:GetLeft() return 100 end
function methods:GetTop() return 700 end
function methods:GetCenter() return 500, 400 end
function methods:GetEffectiveScale() return 1 end
function methods:CreateTexture(name, layer)
	assert(layer == nil or LAYERS[layer], "bad layer " .. tostring(layer))
	local texture = NewWidget("Texture", name, self)
	texture.layer = layer
	return texture
end
function methods:CreateFontString(name, layer, font)
	assert(layer == nil or LAYERS[layer], "bad layer " .. tostring(layer))
	assert(font == nil or FONTS[font], "unknown font " .. tostring(font))
	return NewWidget("FontString", name, self)
end

-- Buttons, font strings, edit boxes
function methods:SetText(text)
	assert(text == nil or type(text) == "string" or type(text) == "number", "SetText needs text")
	local old = self.text
	if text ~= nil then
		text = tostring(text)
	end
	self.text = text
	if self.kind == "EditBox" and old ~= text then
		RunScript(self, "OnTextChanged")
	end
end
-- About the width of GameFontNormalSmall text.
function methods:GetStringWidth() return strlen(self.text or "") * 5.5 end
function methods:GetText()
	if self.kind == "EditBox" then
		return self.text or ""
	end
	return self.text
end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
-- The flat look (2.21.0) as OctoBG uses it, seen working in game on 17 Oct 2026:
-- a font file per string, a shadow, a button's own font string, edit box
-- insets and a scroll bar's thumb texture.
function methods:SetFont(file, size, flags)
	assert(type(file) == "string" and type(size) == "number", "SetFont needs a file and a size")
	self.font = { file, size, flags }
end
function methods:GetFont()
	local f = self.font or { "Fonts\\FRIZQT__.TTF", 12, "" }
	return f[1], f[2], f[3]
end
function methods:SetShadowColor() end
function methods:SetShadowOffset() end
function methods:SetFontString(fs)
	assert(self.kind == "Button", "SetFontString is a Button method")
	self.fontString = fs
end
function methods:SetTextInsets()
	assert(self.kind == "EditBox", "SetTextInsets is an EditBox method")
end
function methods:GetThumbTexture()
	assert(self.kind == "Slider", "GetThumbTexture is a Slider method")
	self.thumbTexture = self.thumbTexture or NewWidget("Texture", nil, self)
	return self.thumbTexture
end
function methods:SetJustifyH(j) assert(j == "LEFT" or j == "RIGHT" or j == "CENTER") end
function methods:SetJustifyV(j) assert(j == "TOP" or j == "MIDDLE" or j == "BOTTOM") end
function methods:LockHighlight() self.locked = true end
function methods:UnlockHighlight() self.locked = false end
function methods:Enable() self.disabled = false end
function methods:Disable() self.disabled = true end
function methods:SetAutoFocus() end
function methods:SetMaxLetters(n) self.maxLetters = n end
function methods:ClearFocus() self.focus = false end
function methods:SetFocus() self.focus = true end
function methods:HighlightText() end

-- Textures (SetTexture also takes r, g, b, a for a solid colour)
function methods:SetTexture(path) self.texture = path end
function methods:SetGradientAlpha(orientation)
	assert(orientation == "VERTICAL" or orientation == "HORIZONTAL", "bad gradient orientation")
end
function methods:SetNormalTexture(path) self.normal = path end
function methods:SetPushedTexture(path) self.pushed = path end
function methods:SetDisabledTexture(path) self.disabledTexture = path end
function methods:SetHighlightTexture(path) self.highlight = path end
function methods:SetTexCoord() end
function methods:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function methods:SetBlendMode(mode) assert(mode == "ADD" or mode == "BLEND" or mode == "DISABLE") end

-- Models
function methods:SetUnit(unit)
	assert(self.kind == "PlayerModel" or self.kind == "DressUpModel", "SetUnit needs a PlayerModel")
	self.unit = unit
	self.unitLoads = (self.unitLoads or 0) + 1
	Mock.modelRefreshes = (Mock.modelRefreshes or 0) + 1
end
-- Blizzard's 1.12 FrameXML only turns PlayerModels with SetRotation; addons
-- here turn plain Models with SetFacing.
function methods:SetRotation(r)
	assert(self.kind == "PlayerModel" or self.kind == "DressUpModel", "SetRotation is a PlayerModel method; use SetFacing")
	self.rotation = r
end
-- DressUpModel (the Dressing Room's): TryOn an item ID, Dress = back to your gear.
function methods:TryOn(item)
	assert(self.kind == "DressUpModel", "TryOn is a DressUpModel method")
	self.tried = self.tried or {}
	table.insert(self.tried, item)
end
function methods:Dress()
	assert(self.kind == "DressUpModel", "Dress is a DressUpModel method")
	self.tried = {}
end
function methods:SetCamera(n) self.camera = n end
function methods:SetLight() end
function methods:SetModelScale(s) self.scale = s end
function methods:SetPosition(x, y, z) self.position = { x or 0, y or 0, z or 0 } end
function methods:SetFacing(f) self.facing = f end
function methods:SetModel(path) self.modelPath = path end
function methods:ClearModel() self.modelPath = nil end
-- ClassicAPI (OPTIONAL above)
function methods:SetDisplayInfo(id)
	assert(type(id) == "number", "Usage: Model:SetDisplayInfo(creatureDisplayID)")
	self.displayInfo = id
	Mock.displayLoads = (Mock.displayLoads or 0) + 1
end

-- Scroll bars and scroll frames
function methods:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function methods:GetMinMaxValues() return self.min or 0, self.max or 0 end
function methods:SetValueStep() end
function methods:SetOrientation(o)
	assert(o == "HORIZONTAL" or o == "VERTICAL", "SetOrientation: HORIZONTAL or VERTICAL")
	self.orientation = o
end
function methods:SetThumbTexture(path) self.thumb = path end
function methods:GetValue() return self.value or 0 end
function methods:SetValue(v)
	local lo, hi = self:GetMinMaxValues()
	if v < lo then v = lo end
	if v > hi then v = hi end
	if v ~= self.value then
		self.value = v
		RunScript(self, "OnValueChanged", v)
	end
end
function methods:SetVerticalScroll(v) RunScript(self, "OnVerticalScroll", v) end

-- Tooltip
function methods:SetOwner(owner) self.owner = owner; self.lines = {} end
function methods:AddLine(text) table.insert(self.lines, text) end
-- A GameTooltipTemplate tooltip's lines are <name>TextLeft1..; SetInventoryItem
-- fills them from Mock.gear ({ itemID, count, durability, max durability }).
function methods:ClearLines()
	for i = 1, 30 do
		getglobal(self.name .. "TextLeft" .. i).text = nil
	end
	self.numLines = 0
end
function methods:NumLines() return self.numLines or 0 end
function methods:SetInventoryItem(unit, slot)
	self:ClearLines()
	local g = unit == "player" and Mock.gear[slot]
	if not g then
		return nil
	end
	local lines = { "Item " .. g[1] }
	if g[3] then
		table.insert(lines, "Armor")
		table.insert(lines, format(DURABILITY_TEMPLATE, g[3], g[4] or 100))
	end
	for i, text in ipairs(lines) do
		getglobal(self.name .. "TextLeft" .. i).text = text
	end
	self.numLines = table.getn(lines)
	return 1
end

local function ApplyTemplate(widget, template)
	local name = widget.name
	if template == "FauxScrollFrameTemplate" then
		local bar = NewWidget("Slider", name .. "ScrollBar", widget)
		NewWidget("Button", name .. "ScrollBarScrollUpButton", bar)
		NewWidget("Button", name .. "ScrollBarScrollDownButton", bar)
		NewWidget("Frame", name .. "ScrollChildFrame", widget)
		bar:SetScript("OnValueChanged", function()
			this:GetParent():SetVerticalScroll(arg1)
		end)
	elseif template == "GameTooltipTemplate" then
		for i = 1, 30 do
			NewWidget("FontString", name .. "TextLeft" .. i, widget)
		end
	elseif template == "UIPanelCloseButton" then
		widget:SetScript("OnClick", function()
			this:GetParent():Hide()
		end)
	end
end

function CreateFrame(kind, name, parent, template)
	assert(FRAME_TYPES[kind], "unknown frame type " .. tostring(kind))
	assert(template == nil or TEMPLATES[template], "unknown template " .. tostring(template))
	-- Templates name their parts "$parent...", so templated frames need a name.
	assert(template == nil or name, template and (template .. " needs a frame name") or "")
	local widget = NewWidget(kind, name, parent)
	ApplyTemplate(widget, template)
	table.insert(Mock.frames, widget)
	return widget
end

-- FrameXML helpers, as in 1.12's UIPanelTemplates.lua.
function FauxScrollFrame_Update(frame, numItems, numToDisplay, valueStep)
	local bar = getglobal(frame:GetName() .. "ScrollBar")
	if numItems > numToDisplay then
		frame:Show()
	else
		bar:SetValue(0)
		frame:Hide()
	end
	local range = (numItems - numToDisplay) * valueStep
	if range < 0 then
		range = 0
	end
	bar:SetMinMaxValues(0, range)
end
function FauxScrollFrame_OnVerticalScroll(itemHeight, updateFunction)
	local bar = getglobal(this:GetName() .. "ScrollBar")
	bar:SetValue(arg1)
	this.offset = floor((arg1 / itemHeight) + 0.5)
	updateFunction()
end
function FauxScrollFrame_GetOffset(frame) return frame.offset end
function FauxScrollFrame_SetOffset(frame, offset) frame.offset = offset end

-- Resets the client UI, as a /reload or login does. Saved variables and the
-- fake VanillaHelpers state are kept.
function Mock.ResetUI()
	for key in pairs(_G) do
		if type(key) == "string" and strfind(key, "^DmorphOcto") and key ~= "DmorphOctoDB"
			and key ~= "DmorphOctoAccount" then
			_G[key] = nil
		end
	end
	Mock.frames, Mock.chat, Mock.sent, Mock.popups = {}, {}, {}, {}
	Mock.serverItems = Mock.serverItems or {}
	Mock.modelRefreshes = 0
	UIParent = NewWidget("Frame", "UIParent")
	Minimap = NewWidget("Frame", "Minimap", UIParent)
	GameTooltip = NewWidget("Frame", "GameTooltip", UIParent)
	DEFAULT_CHAT_FRAME = { AddMessage = function(self, msg) table.insert(Mock.chat, msg) end }
	-- Channel messages (Share.lua) are kept apart from what you type.
	Mock.channelSent, Mock.addonSent, Mock.channels = {}, {}, {}
	function SendChatMessage(msg, chatType, language, channel)
		Mock.lastLanguage = language
		if chatType == "CHANNEL" then
			table.insert(Mock.channelSent, { msg = msg, channel = channel })
		else
			table.insert(Mock.sent, msg)
		end
	end
	-- Languages: the ones the character knows (from its skills) and the
	-- race's default, which a race morph changes (Mock.defaultLanguage).
	Mock.languages = Mock.languages or { "Common" }
	-- Mock.raceLanguages(), when set, gives the list and default of the race
	-- the game thinks you are (a race morph changes it, as in the client).
	local function Languages()
		if Mock.raceLanguages then
			return Mock.raceLanguages()
		end
		return Mock.languages, Mock.defaultLanguage
	end
	function GetLanguageByIndex(i)
		local list = Languages()
		return list[i]
	end
	function GetDefaultLanguage()
		local list, default = Languages()
		return default or list[1]
	end
	function UnitFactionGroup() return Mock.faction or "Alliance", Mock.faction or "Alliance" end
	function SendAddonMessage(prefix, text, distribution)
		assert(distribution == "PARTY" or distribution == "RAID" or distribution == "GUILD" or distribution == "BATTLEGROUND",
			"SendAddonMessage: 1.12 has no " .. tostring(distribution))
		table.insert(Mock.addonSent, { prefix = prefix, text = text, distribution = distribution })
	end
	function JoinChannelByName(name)
		Mock.channels[strlower(name)] = 6
	end
	function LeaveChannelByName(name)
		Mock.channels[strlower(name)] = nil
	end
	function GetChannelName(name)
		local id = Mock.channels[strlower(name)]
		if id then
			return id, name
		end
		return 0
	end
	NUM_CHAT_WINDOWS = 7
	-- What the chat windows were given to show: { event, arg1, channel }.
	Mock.shown = {}
	function ChatFrame_OnEvent(event)
		table.insert(Mock.shown, { event = event, msg = arg1, channel = arg9 })
	end
	-- Guild: Mock.guild = { names }; the roster arrives with GUILD_ROSTER_UPDATE.
	Mock.guild, Mock.rosterRequests = nil, 0
	function IsInGuild() return Mock.guild and 1 or nil end
	function GuildRoster() Mock.rosterRequests = Mock.rosterRequests + 1 end
	function GetNumGuildMembers() return Mock.guild and table.getn(Mock.guild) or 0 end
	function GetGuildRosterInfo(index)
		local name = Mock.guild and Mock.guild[index]
		if name then
			return name, "Member", 1, 60, "Warrior", "Orgrimmar", "", "", 1
		end
	end
	function GetRealmName() return "OctoWoW" end
	Mock.now = Mock.now or 1700000000
	function time() return Mock.now end
	ChatFrame1 = { channelList = { "General" }, zoneChannelList = {} }
	function ChatFrame_RemoveChannel(chatFrame, channel)
		for index, value in pairs(chatFrame.channelList) do
			if strupper(value) == strupper(channel) then
				chatFrame.channelList[index] = nil
			end
		end
	end
	-- Other players: Mock.units[token] = { name, guid, friendly }. With
	-- Mock.superWoW set, GUIDs work as unit tokens too.
	Mock.units = {}
	Mock.party, Mock.raid = 0, 0
	function GetNumPartyMembers() return Mock.party end
	function GetNumRaidMembers() return Mock.raid end
	MAX_BATTLEFIELD_QUEUES = 3
	function GetBattlefieldStatus() return "none" end
	function UnitExists(unit)
		if unit == "player" then
			return 1, Mock.superWoW and Mock.playerGUID or nil
		end
		local u = Mock.Unit(unit)
		if u then
			return 1, Mock.superWoW and u.guid or nil
		end
	end
	function UnitIsPlayer(unit) return unit == "player" or Mock.Unit(unit) ~= nil end
	-- A group member out of sight has a token but no model (u.far).
	function UnitIsVisible(unit)
		local u = Mock.Unit(unit)
		return u and not u.far and 1 or nil
	end
	-- Distance check 4 is "within follow range" (about 28 yards); u.distant
	-- is a player you can see but who is further away.
	function CheckInteractDistance(unit, index)
		assert(index >= 1 and index <= 4, "CheckInteractDistance: index 1-4")
		local u = Mock.Unit(unit)
		return u and not u.far and not u.distant and 1 or nil
	end
	function UnitCanAssist(unit, other)
		local u = Mock.Unit(other)
		return u and u.friendly and 1 or nil
	end
	SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
	function StaticPopup_Show(which, a1) table.insert(Mock.popups, { which = which, arg = a1 }) end
	YES, NO = "Yes", "No"
	function TEXT(s) return s end
	function PlaySound() end
	function GetCursorPosition() return Mock.cursorX or 0, Mock.cursorY or 0 end
	function UnitRace() return "Human", "Human" end
	function UnitName(unit)
		if unit == "player" then
			return "Tester"
		end
		local u = Mock.Unit(unit)
		return u and u.name
	end
	function UnitBuff(unit, index) return Mock.buffs and Mock.buffs[index] end
	function UnitOnTaxi(unit) return Mock.onTaxi and 1 or nil end
	function UnitSex() return 2 end
	function GetInventoryItemTexture(unit, slot)
		if slot == 5 then
			return "Interface\\Icons\\INV_Chest_Plate01"
		end
	end
	function GetInventorySlotInfo(key) return 0, "Interface\\Paperdoll\\UI-PaperDoll-Slot-" .. key end
	-- Your real gear (Mock.gear = { [slot] = { itemID, count } }; slot 0 = ammo).
	Mock.gear = Mock.gear or {}
	function GetInventoryItemLink(unit, slot)
		local g = unit == "player" and Mock.gear[slot]
		if g then
			return "|cffffffff|Hitem:" .. g[1] .. ":0:0:0|h[Item " .. g[1] .. "]|h|r"
		end
	end
	function GetInventoryItemCount(unit, slot)
		local g = unit == "player" and Mock.gear[slot]
		return g and (g[2] or 1) or 0
	end
	function GetItemInfo(id)
		if id == 2955 then
			return "First Mate Hat", "item:2955:0:0:0", 2, 1, "Armor", "Cloth", 1, "INVTYPE_HEAD",
				"Interface\\Icons\\INV_Misc_Bandana_03"
		end
		-- Items the fake server has sent: { name, quality, equipLoc }.
		local item = Mock.serverItems[id]
		if item then
			return item[1], "item:" .. id .. ":0:0:0", item[2], 60, item[4] or "Armor", item[5] or "Plate", 1, item[3],
				"Interface\\Icons\\INV_Misc_QuestionMark"
		end
		-- DmorphHelper's virtual items (Mock.virtualItems = { [id] = { template, display } }):
		-- the template's record, once the game knows the template.
		local v = Mock.virtualItems and Mock.virtualItems[id]
		if v and v[1] ~= id then
			return GetItemInfo(v[1])
		end
	end
	-- ClassicAPI's item loading, only while the test installs ClassicAPI.
	Mock.itemRequests = {}
	if Mock.classicAPI then
		C_Item = { RequestLoadItemDataByID = function(id)
			table.insert(Mock.itemRequests, id)
			return true
		end }
	else
		C_Item = nil
	end
	DURABILITY_TEMPLATE = "Durability %d / %d"
	ITEM_QUALITY_COLORS = {}
	for q = -1, 6 do
		ITEM_QUALITY_COLORS[q] = { r = 1, g = 1, b = 1, hex = "|cffffffff" }
	end
end

-- Loads the addon's files in .toc order.
function Mock.LoadAddon(toc)
	for line in io.lines(toc) do
		line = string.gsub(line, "\r", "")
		if line ~= "" and not strfind(line, "^##") then
			-- Like the client, a file the .toc lists but that isn't there
			-- (Data\Ported.lua on most PCs) is skipped.
			-- Data\Ported.lua is never read: tests give its contents (Mock.portedData).
			local path = string.gsub(line, "\\", "/")
			local f = io.open(path, "r")
			if strfind(path, "Data/Ported%.lua$") then
				if f then
					f:close()
				end
				DmorphOcto_PortedData = Mock.portedData
				DmorphOcto_PortedItems = Mock.portedItems
				DmorphOcto_PortedSets = Mock.portedSets
				DmorphOcto_PortedGlows = Mock.portedGlows
			elseif f then
				f:close()
				dofile(path)
			end
		end
	end
end

-- The unit a token (or, with SuperWoW, a GUID) stands for, or nil.
function Mock.Unit(token)
	if type(token) ~= "string" then
		return nil
	end
	if Mock.units[token] then
		return Mock.units[token]
	end
	if Mock.superWoW then
		for _, u in pairs(Mock.units) do
			if u.guid == token then
				return u
			end
		end
	end
end

function Mock.Fire(name, a1, a2, a3, a4, a5, a6, a7, a8, a9)
	local frames = Mock.frames
	for i = 1, table.getn(frames) do
		local frame = frames[i]
		if frame.events[name] then
			event, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 = name, a2, a3, a4, a5, a6, a7, a8, a9
			RunScript(frame, "OnEvent", a1)
			arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9 = nil, nil, nil, nil, nil, nil, nil, nil
		end
	end
end

function Mock.Tick(elapsed)
	local frames = Mock.frames
	for i = 1, table.getn(frames) do
		local frame = frames[i]
		if frame:IsVisible() then
			RunScript(frame, "OnUpdate", elapsed)
		end
	end
end

function Mock.Click(button, mouseButton)
	assert(button:IsVisible(), "clicked a hidden " .. (button.name or button.kind))
	RunScript(button, "OnClick", mouseButton or "LeftButton")
end

-- Types into an edit box and lets any search delay run out.
function Mock.Type(box, text)
	box:SetText(text)
	Mock.Tick(0.3)
end

-- The visible button whose label is text.
function Mock.FindButton(text, root)
	local frames = Mock.frames
	for i = 1, table.getn(frames) do
		local frame = frames[i]
		if frame.kind == "Button" and frame.text == text and frame:IsVisible() then
			return frame
		end
	end
	error("no visible button \"" .. text .. "\"")
end
