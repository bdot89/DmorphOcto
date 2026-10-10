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
local FRAME_TYPES = { Frame = 1, Button = 1, EditBox = 1, ScrollFrame = 1, Model = 1, PlayerModel = 1, Slider = 1 }
local TEMPLATES = {
	UIPanelButtonTemplate = 1, InputBoxTemplate = 1, FauxScrollFrameTemplate = 1, UIPanelCloseButton = 1,
}
local SCRIPTS = {
	OnClick = 1, OnEnter = 1, OnLeave = 1, OnMouseWheel = 1, OnVerticalScroll = 1,
	OnTextChanged = 1, OnEnterPressed = 1, OnEscapePressed = 1, OnUpdate = 1, OnEvent = 1,
	OnShow = 1, OnHide = 1, OnDragStart = 1, OnDragStop = 1, OnMouseDown = 1, OnMouseUp = 1,
	OnValueChanged = 1,
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
end
function methods:ClearAllPoints() self.point = nil end
function methods:SetAllPoints(target) self.point = { "ALL", target } end
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
function methods:GetText()
	if self.kind == "EditBox" then
		return self.text or ""
	end
	return self.text
end
function methods:SetTextColor(r, g, b) self.color = { r, g, b } end
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
	assert(self.kind == "PlayerModel", "SetUnit needs a PlayerModel")
	self.unit = unit
	self.unitLoads = (self.unitLoads or 0) + 1
	Mock.modelRefreshes = (Mock.modelRefreshes or 0) + 1
end
-- Blizzard's 1.12 FrameXML only turns PlayerModels with SetRotation; addons
-- here turn plain Models with SetFacing.
function methods:SetRotation(r)
	assert(self.kind == "PlayerModel", "SetRotation is a PlayerModel method; use SetFacing")
	self.rotation = r
end
function methods:SetCamera(n) self.camera = n end
function methods:SetLight() end
function methods:SetModelScale(s) self.scale = s end
function methods:SetPosition() end
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
	function SendChatMessage(msg) table.insert(Mock.sent, msg) end
	SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
	function StaticPopup_Show(which, a1) table.insert(Mock.popups, { which = which, arg = a1 }) end
	YES, NO = "Yes", "No"
	function TEXT(s) return s end
	function PlaySound() end
	function GetCursorPosition() return Mock.cursorX or 0, Mock.cursorY or 0 end
	function UnitRace() return "Human", "Human" end
	function UnitName() return "Tester" end
	function UnitBuff(unit, index) return Mock.buffs and Mock.buffs[index] end
	function UnitSex() return 2 end
	function GetInventoryItemTexture(unit, slot)
		if slot == 5 then
			return "Interface\\Icons\\INV_Chest_Plate01"
		end
	end
	function GetInventorySlotInfo(key) return 0, "Interface\\Paperdoll\\UI-PaperDoll-Slot-" .. key end
	function GetItemInfo(id)
		if id == 2955 then
			return "First Mate Hat", "item:2955:0:0:0", 2, 1, "Armor", "Cloth", 1, "INVTYPE_HEAD",
				"Interface\\Icons\\INV_Misc_Bandana_03"
		end
		-- Items the fake server has sent: { name, quality, equipLoc }.
		local item = Mock.serverItems[id]
		if item then
			return item[1], "item:" .. id .. ":0:0:0", item[2], 60, "Armor", "Plate", 1, item[3],
				"Interface\\Icons\\INV_Misc_QuestionMark"
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
			dofile((string.gsub(line, "\\", "/")))
		end
	end
end

function Mock.Fire(name, a1, a2)
	local frames = Mock.frames
	for i = 1, table.getn(frames) do
		local frame = frames[i]
		if frame.events[name] then
			event, arg2 = name, a2
			RunScript(frame, "OnEvent", a1)
			arg2 = nil
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
