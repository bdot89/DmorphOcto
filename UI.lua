-- DMorph for OctoWoW: the morph window.
--
-- Left: your character in a dressing room (your race's dress-up backdrop),
-- with the morphable slots around it. Right: tabs to browse every creature
-- model (a grid of 3D previews, or a list), skins for your mount, favourites, races and NPC looks,
-- weapon glows, items per slot, item sets and a wardrobe of saved outfits. Everything goes
-- through the DmorphOcto.* functions in DmorphOcto.lua, the same ones the chat
-- commands use.
--
-- No white flashes: a model frame draws its model white until the textures
-- have loaded. So every model here loads out of sight first, below an opaque
-- layer, and is raised above it once it has had time to finish. The character
-- preview keeps two PlayerModels for this and swaps them, and never reloads
-- one that is still loading.
--
-- 1.12 API: scripts read `this`/`arg1` instead of taking arguments, there is
-- no SetSize, lists use FauxScrollFrameTemplate, and regions that share a draw
-- layer have no fixed order, so whatever must stack sits on child frames with
-- explicit frame levels. 3D previews by display ID need ClassicAPI's
-- Model:SetDisplayInfo; without it the Models tab shows a list.

local M = DmorphOcto

local W, H = 922, 534
local ART_W, ART_H, PLATE_H = 318, 383, 44
local PAGE_X, PAGE_Y, PAGE_W, PAGE_H = 352, -74, 550, 382
local ROW_HEIGHT, LIST_ROWS, LIST_WIDTH = 18, 15, 510
-- Every list tab (2.21.0, user: "all tabs with lists should have this same
-- layout"): the list on the left, a preview box on the right.
local BOX_W, LIST_W = 178, 330
local TILE_W, TILE_H, TILE_GAP, GRID_COLS = 128, 132, 6, 4
-- ClassicAPI dresses at most 8 NPC preview models at a time, so 8 tiles.
local PAGE_SIZE = 8
-- How long a model loads out of sight before it's shown.
local REVEAL = 0.45
-- The least time between two model changes in one preview (see LoadView).
local SETTLE = 0.6
-- After a morph the game rebuilds your character; a second change before it
-- has finished can mix the two looks' textures. Clicks closer than this wait.
local GATE = 0.35
local MIN_SCALE, MAX_SCALE = 0.6, 1.6
-- Zooming the character: how far it comes towards you (model units, about a
-- yard each), per mouse wheel notch and at most.
local ZOOM_STEP, ZOOM_MIN, ZOOM_MAX = 0.3, -1.5, 3
local MENU_ROWS, MENU_WIDTH = 20, 170
local WHITE = "Interface\\Buttons\\WHITE8X8"
local RACE_ICONS_FILE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"

-- GetInventorySlotInfo() names, for the empty-slot icons.
local SLOT_KEYS = {
	[1] = "HeadSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
	[6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot",
	[10] = "HandsSlot", [15] = "BackSlot", [16] = "MainHandSlot",
	[17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}
-- Paper-doll layout: slots down the left and right of the model.
local LEFT_SLOTS = { 1, 3, 15, 5, 4, 19, 9 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 16, 17, 18 }

-- Per race ID (DmorphOcto.RACES): the dress-up backdrop, and the male icon's
-- cell { left, right, top } in the character-create race icons, from the
-- client's CharacterCreate.lua. The female icon sits half the sheet lower.
local RACE_ART = { "Human", "Orc", "Dwarf", "NightElf", "Scourge", "Tauren", "Gnome", "Troll", "Goblin", "BloodElf" }
local RACE_ICONS = {
	{ 0, 0.125, 0 }, { 0.375, 0.5, 0.25 }, { 0.125, 0.25, 0 }, { 0.375, 0.5, 0 }, { 0.125, 0.25, 0.25 },
	{ 0, 0.125, 0.25 }, { 0.25, 0.375, 0 }, { 0.25, 0.375, 0.25 }, { 0.5, 0.625, 0 }, { 0.5, 0.625, 0.25 },
}
-- UnitRace() tokens whose dress-up backdrop has another name.
local ART_TOKENS = { HighElf = "BloodElf" }

-- Creature model entries by kind (DmorphOcto.KIND_*). Items and sets use 0 and 2.
local KIND_COLORS = { [0] = { 1, 1, 1 }, [1] = { 0.62, 0.76, 0.92 }, [2] = { 0.45, 1, 0.6 }, [3] = { 0.45, 1, 0.6 }, [4] = { 1, 0.82, 0.3 } }
local KIND_NOTES = {
	[0] = "A creature from the world database.",
	[1] = "No creature has this look, so it's named after its model file.",
	[2] = "New in OctoWoW: a creature from Turtle WoW's database.",
	[3] = "New in OctoWoW, named after its model file.",
	[4] = "Ported from a later expansion: only on this PC (patch-Z.mpq), others see your own look.",
}

local TABS = {
	{ key = "models", text = "Models" },
	{ key = "mounts", text = "Mounts" },
	{ key = "favourites", text = "Favourites" },
	{ key = "races", text = "Races" },
	{ key = "glows", text = "Glows" },
	{ key = "extra", text = "Extra wear" },
	{ key = "items", text = "Items" },
	{ key = "slutmog", text = "Slutmog" },
	{ key = "sets", text = "Sets" },
	{ key = "wardrobe", text = "Wardrobe" },
	{ key = "weather", text = "Weather" },
}
local TAB_GAP = 3
-- The gold star of the raid target icons marks favourites.
local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local FAV_FILTERS = {
	{ text = "All favourites" },
	{ text = "Models", mount = false },
	{ text = "Mounts", mount = true },
}

local frame -- the window, built the first time it opens
local ui = {
	tabs = {}, pages = {}, slots = {}, raceButtons = {}, raceCells = {}, tiles = {}, page = 1,
	creator = {}, creatorRows = {}, mountRows = {}, glowSlots = {}, iconAsked = {}, boxes = {},
}
-- Helpers of the preview boxes and the list tabs (one table: Lua 5.0 allows
-- 200 locals in a chunk and 32 upvalues in a function).
local P = {}
local currentTab = "models"
local itemSlot = 1 -- the slot the Items tab is browsing
local selectedOutfit
local pendingDelete
local buttonCount = 0

local function SetStatus(ok, message)
	if not frame then
		return
	end
	ui.status:SetText(message or "")
	if ok then
		ui.status:SetTextColor(0.6, 1, 0.6)
	else
		ui.status:SetTextColor(1, 0.4, 0.4)
	end
end

-- 16296 -> "16,296"
local function Commas(n)
	local text, out = tostring(n), ""
	while strlen(text) > 3 do
		out = "," .. strsub(text, -3) .. out
		text = strsub(text, 1, -4)
	end
	return text .. out
end

-- 1 -> "1 item", 1234 -> "1,234 items"
local function Count(n, word)
	if n == 1 then
		return "1 " .. word
	end
	return Commas(n) .. " " .. word .. "s"
end

-- Steps through n positions, wrapping round.
local function Wrap(pos, step, n)
	return math.mod(pos - 1 + step + n * 4, n) + 1
end

-- Window settings shared by all characters: views, filters, sorting, size.
local function Prefs()
	local account = M.GetAccount()
	if type(account.ui) ~= "table" then
		account.ui = {}
	end
	local p = account.ui
	if not M.MODEL_FILTERS[p.filter] then
		p.filter = 1
	end
	if not M.ITEM_FILTERS[p.itemFilter] then
		p.itemFilter = 1
	end
	if not M.SET_FILTERS[p.setFilter] then
		p.setFilter = 1
	end
	if not M.QUALITY_FILTERS[p.itemQuality] then
		p.itemQuality = 1
	end
	if not M.QUALITY_FILTERS[p.setQuality] then
		p.setQuality = 1
	end
	-- The item kind per slot (cloth, dagger, ...), and the sets' armour.
	if type(p.itemTypes) ~= "table" then
		p.itemTypes = {}
	end
	for slot, kind in pairs(p.itemTypes) do
		if not (M.SLOT_NAMES[slot] and M.ITEM_TYPE_NAMES[kind]) then
			p.itemTypes[slot] = nil
		end
	end
	if not M.ITEM_TYPE_NAMES[p.setType or 0] then
		p.setType = nil
	end
	if not FAV_FILTERS[p.favFilter] then
		p.favFilter = 1
	end
	if type(p.scale) ~= "number" or p.scale < MIN_SCALE or p.scale > MAX_SCALE then
		p.scale = 1
	end
	return p
end

-- The look -------------------------------------------------------------------

-- 2.21.0, user: "neat like OctoBG and ShootyEPGP, but more vibrant". Flat dark
-- panels with 1 px borders (OctoBG's flat style, seen working in game),
-- DMorph's purple (the project page's #b46bff) for what's picked and hovered,
-- gold for what you have on, and Roboto once the client says it loaded.
local C = {
	bg = { 0.05, 0.05, 0.06 }, panel = { 0.075, 0.075, 0.09 }, card = { 0.1, 0.095, 0.125 },
	field = { 0.045, 0.045, 0.055 }, btn = { 0.15, 0.13, 0.2 }, line = { 0.25, 0.22, 0.32 },
	lineHi = { 0.5, 0.38, 0.7 }, text = { 0.94, 0.93, 0.96 }, dim = { 0.62, 0.6, 0.68 },
	accent = { 0.71, 0.42, 1 }, deep = { 0.29, 0.15, 0.5 }, gold = { 1, 0.82, 0.3 },
}
local FONTS = { friz = "Fonts\\FRIZQT__.TTF", roboto = "Interface\\AddOns\\DmorphOcto\\media\\fonts\\Roboto.ttf" }
-- A failed SetFont keeps the old font, so GetFont tells whether Roboto loaded.
local function UIFont()
	if not FONTS.ui then
		FONTS.ui = FONTS.friz
		local probe = UIParent:CreateFontString(nil, "OVERLAY")
		probe:SetFont(FONTS.roboto, 12, "")
		local now = probe:GetFont()
		if type(now) == "string" and strlower(string.gsub(now, "/", "\\")) == strlower(FONTS.roboto) then
			FONTS.ui = FONTS.roboto
		end
	end
	return FONTS.ui
end

local function Font(fs, size, col)
	fs:SetFont(UIFont(), size or 11, "")
	fs:SetShadowColor(0, 0, 0, 0.85)
	fs:SetShadowOffset(1, -1)
	col = col or C.text
	fs:SetTextColor(col[1], col[2], col[3])
	return fs
end

-- A frame drawn flat: a colour inside a 1 px line.
local function Flat(f, col, line, alpha)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, tile = false, tileSize = 0, edgeSize = 1,
		insets = { left = 1, right = 1, top = 1, bottom = 1 } })
	col, line = col or C.panel, line or C.line
	f:SetBackdropColor(col[1], col[2], col[3], alpha or 1)
	f:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

-- A purple wash that shows on hover and while locked (LockHighlight).
local function Hover(f, alpha)
	local hl = f:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(WHITE)
	hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], alpha or 0.22)
	hl:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
	hl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	return hl
end

-- Widget helpers --------------------------------------------------------------

-- The template names are only for the size and colour they imply.
local LABEL_LOOK = {
	GameFontNormalLarge = { 15, C.accent }, GameFontNormal = { 12, C.gold },
	GameFontHighlight = { 12, C.text }, GameFontHighlightSmall = { 11, C.text },
	GameFontNormalSmall = { 11, C.gold }, GameFontDisableSmall = { 10, C.dim },
	GameFontRedSmall = { 11, { 1, 0.42, 0.42 } },
}
local function Label(parent, text, font, x, y, name)
	local label = parent:CreateFontString(name, "OVERLAY", font or "GameFontNormalSmall")
	local look = LABEL_LOOK[font or "GameFontNormalSmall"]
	if look then
		Font(label, look[1], look[2])
	end
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

-- A flat button; b:SetText works (its own font string), LockHighlight keeps
-- the purple wash on (the picked one of a row of buttons).
local function FlatButton(button, text, size)
	Flat(button, C.btn, C.line)
	local label = button:CreateFontString(nil, "OVERLAY")
	Font(label, size or 11)
	label:SetPoint("LEFT", button, "LEFT", 3, 0)
	label:SetPoint("RIGHT", button, "RIGHT", -3, 0)
	button:SetFontString(label)
	button.label = label
	Hover(button)
	button:SetScript("OnMouseDown", function()
		this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end)
	button:SetScript("OnMouseUp", function()
		this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
	end)
	button:SetText(text)
	return button
end

local function Button(parent, text, width, x, y, onClick, name)
	buttonCount = buttonCount + 1
	local button = CreateFrame("Button", name or ("DmorphOctoButton" .. buttonCount), parent)
	button:SetWidth(width)
	button:SetHeight(22)
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	FlatButton(button, text)
	button:SetScript("OnClick", onClick)
	return button
end

-- Greys a flat button out (it still shows its tooltip).
local function SetEnabled(button, on)
	if on then
		button:Enable()
		button.label:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		button:Disable()
		button.label:SetTextColor(0.4, 0.38, 0.45)
	end
end

local function EditBox(parent, name, width, x, y, maxLetters)
	local box = CreateFrame("EditBox", name, parent)
	box:SetWidth(width)
	box:SetHeight(20)
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	Flat(box, C.field, C.line)
	box:SetTextInsets(6, 6, 0, 0)
	box:SetFont(UIFont(), 11, "")
	box:SetTextColor(C.text[1], C.text[2], C.text[3])
	box:EnableMouse(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters or 40)
	box:SetScript("OnEscapePressed", function()
		this:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function()
		this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end)
	box:SetScript("OnEditFocusLost", function()
		this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
	end)
	return box
end

-- A flat panel in a colour (r, g, b), else the card colour.
local function Panel(f, r, g, b)
	Flat(f, r and { r, g, b } or C.card, C.line)
end

-- A FauxScrollFrame's bar made flat: no arrow buttons, a thin track to the
-- right of the list and a purple thumb (OctoBG's FlatScroll). The mouse
-- wheel still scrolls.
local function FlatScroll(scroll)
	local name = scroll:GetName()
	local bar = getglobal(name .. "ScrollBar")
	getglobal(name .. "ScrollBarScrollUpButton"):Hide()
	getglobal(name .. "ScrollBarScrollDownButton"):Hide()
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	bar:SetWidth(6)
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(WHITE)
	track:SetVertexColor(C.field[1], C.field[2], C.field[3], 1)
	track:SetAllPoints(bar)
	bar:SetThumbTexture(WHITE)
	local thumb = bar:GetThumbTexture()
	if thumb then
		thumb:SetWidth(6)
		thumb:SetHeight(36)
		thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.85)
	end
end

-- A texture with a vertical gradient, bottom colour first.
local function Gradient(parent, layer, r1, g1, b1, a1, r2, g2, b2, a2)
	local texture = parent:CreateTexture(nil, layer)
	texture:SetTexture(WHITE)
	texture:SetGradientAlpha("VERTICAL", r1, g1, b1, a1, r2, g2, b2, a2)
	return texture
end

-- A child frame at a fixed level above its parent (see the header).
local function Layer(parent, level)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(parent:GetFrameLevel() + level)
	return f
end

local function Tooltip(owner, title, line1, line2, line3)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText(title)
	if line1 then
		GameTooltip:AddLine(line1, 1, 1, 1)
	end
	if line2 then
		GameTooltip:AddLine(line2, 0.8, 0.8, 0.8)
	end
	if line3 then
		GameTooltip:AddLine(line3, 0.2, 1, 0.6)
	end
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

-- Runs fn once typing has paused, so long lists aren't filtered per key.
local function Debounce(timer, delay, fn)
	timer.wait = delay
	timer.callback = fn
	timer:Show()
end

local function NewTimer()
	local timer = CreateFrame("Frame", nil, frame)
	timer:Hide()
	timer:SetScript("OnUpdate", function()
		this.wait = this.wait - arg1
		if this.wait <= 0 then
			this:Hide()
			this.callback()
		end
	end)
	return timer
end

-- Every morph from the window goes through here. The game rebuilds your
-- character after each change, and a change that lands while it is still
-- rebuilding can leave the earlier look's textures on it. So a click within
-- GATE seconds of the last one waits, and only the latest waiting one runs.
local function Morph(fn, a1, a2)
	if ui.gateBusy then
		ui.gateNext = { fn, a1, a2 }
		return
	end
	ui.gateBusy = true
	SetStatus(fn(a1, a2))
	Debounce(ui.gateTimer, GATE, function()
		ui.gateBusy = nil
		local nextCall = ui.gateNext
		ui.gateNext = nil
		if nextCall then
			Morph(nextCall[1], nextCall[2], nextCall[3])
		end
	end)
end

-- A drop-down menu shared by every filter button. options: a list of
-- { text = ..., checked = true/nil, header = true/nil }; pick(option) runs when
-- one is clicked. Clicking the same button again closes it.
local function OpenMenu(anchor, options, pick, above)
	local menu = ui.menu
	if menu:IsShown() and menu.anchor == anchor then
		menu:Hide()
		return
	end
	menu.anchor, menu.pick = anchor, pick
	local count = math.min(table.getn(options), MENU_ROWS)
	for i = 1, MENU_ROWS do
		local row, option = menu.rows[i], options[i]
		if option then
			row.option = option
			row.label:SetText(option.text)
			if option.header then
				row.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
				row:Disable()
			else
				row.label:SetTextColor(C.text[1], C.text[2], C.text[3])
				row:Enable()
			end
			if option.checked then
				row.check:Show()
			else
				row.check:Hide()
			end
			row:Show()
		else
			row:Hide()
		end
	end
	menu:SetHeight(count * 18 + 12)
	menu:ClearAllPoints()
	if above then
		menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
	else
		menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	end
	menu:Show()
end

local function BuildMenu()
	local menu = CreateFrame("Frame", "DmorphOctoMenu", frame)
	menu:Hide()
	menu:SetFrameLevel(frame:GetFrameLevel() + 40)
	menu:SetWidth(MENU_WIDTH)
	menu:EnableMouse(true)
	Flat(menu, C.panel, C.accent)
	menu.rows = {}
	for i = 1, MENU_ROWS do
		local row = CreateFrame("Button", "DmorphOctoMenuRow" .. i, menu)
		row:SetFrameLevel(menu:GetFrameLevel() + 1)
		row:SetWidth(MENU_WIDTH - 12)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * 18)
		Hover(row, 0.3)
		row.check = row:CreateTexture(nil, "ARTWORK")
		row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row.check:SetWidth(16)
		row.check:SetHeight(16)
		row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.label = Font(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
		row.label:SetPoint("LEFT", row, "LEFT", 18, 0)
		row:SetScript("OnClick", function()
			ui.menu:Hide()
			ui.menu.pick(this.option)
		end)
		menu.rows[i] = row
	end
	return menu
end

-- A scrolling list of LIST_ROWS rows over a FauxScrollFrame. fill(row, index)
-- draws entry `index` (row.text, row.info), click(index, mouseButton) handles
-- a click, enter(index, row) a hover. infoWidth is the right-hand column.
local function List(parent, name, x, y, infoWidth, fill, click, enter, width, rows)
	local list = { rows = {}, count = 0 }
	local LIST_ROWS = rows or LIST_ROWS
	width = width or LIST_WIDTH
	local scroll = CreateFrame("ScrollFrame", name, parent, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	scroll:SetWidth(width)
	scroll:SetHeight(LIST_ROWS * ROW_HEIGHT)
	FlatScroll(scroll)
	-- The list sits on a dark well, a line round it.
	local well = CreateFrame("Frame", nil, parent)
	well:SetPoint("TOPLEFT", scroll, "TOPLEFT", -1, 1)
	well:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 1, -1)
	well:SetFrameLevel(scroll:GetFrameLevel())
	Flat(well, C.field, C.line)

	function list.Refresh()
		local offset = FauxScrollFrame_GetOffset(scroll) or 0
		for i = 1, LIST_ROWS do
			local row = list.rows[i]
			local index = offset + i
			if index <= list.count then
				row.index = index
				row:UnlockHighlight()
				row.star:Hide()
				row.tick:Hide()
				row.text:SetTextColor(C.text[1], C.text[2], C.text[3])
				fill(row, index)
				row:Show()
			else
				row:Hide()
			end
		end
		FauxScrollFrame_Update(scroll, list.count, LIST_ROWS, ROW_HEIGHT)
	end

	-- Scrolls so that entry `index` is the top row.
	function list.ScrollTo(index)
		local offset = index - 1
		if offset > list.count - LIST_ROWS then
			offset = list.count - LIST_ROWS
		end
		if offset < 0 then
			offset = 0
		end
		FauxScrollFrame_SetOffset(scroll, offset)
		getglobal(name .. "ScrollBar"):SetValue(offset * ROW_HEIGHT)
		list.Refresh()
	end

	-- Scrolls entry `index` into view (about the middle) if it isn't.
	function list.Show(index)
		local top = list.GetOffset() + 1
		if index < top or index > top + LIST_ROWS - 1 then
			list.ScrollTo(index - math.floor(LIST_ROWS / 2))
		else
			list.Refresh()
		end
	end

	-- New contents: back to the top, unless keep is set.
	function list.SetCount(count, keep)
		list.count = count
		if keep then
			list.Refresh()
		else
			list.ScrollTo(1)
		end
	end

	function list.GetOffset()
		return FauxScrollFrame_GetOffset(scroll) or 0
	end

	scroll:SetScript("OnVerticalScroll", function()
		FauxScrollFrame_OnVerticalScroll(ROW_HEIGHT, list.Refresh)
	end)

	for i = 1, LIST_ROWS do
		local row = CreateFrame("Button", name .. "Row" .. i, parent)
		-- Above the scroll frame, so clicks reach the rows.
		row:SetFrameLevel(scroll:GetFrameLevel() + 1)
		row:SetWidth(width)
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - (i - 1) * ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		if math.mod(i, 2) == 0 then
			local stripe = row:CreateTexture(nil, "BACKGROUND")
			stripe:SetTexture(WHITE)
			stripe:SetVertexColor(1, 1, 1, 0.03)
			stripe:SetAllPoints(row)
		end
		Hover(row, 0.24)
		row.text = Font(row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
		row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.text:SetWidth(width - infoWidth - 14)
		row.text:SetHeight(ROW_HEIGHT)
		row.text:SetJustifyH("LEFT")
		row.info = Font(row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 10, C.dim)
		row.info:SetPoint("RIGHT", row, "RIGHT", -6, 0)
		row.info:SetWidth(infoWidth)
		row.info:SetHeight(ROW_HEIGHT)
		row.info:SetJustifyH("RIGHT")
		row.star = row:CreateTexture(nil, "OVERLAY")
		row.star:SetTexture(STAR)
		row.star:SetTexCoord(0, 0.25, 0, 0.25)
		row.star:SetWidth(12)
		row.star:SetHeight(12)
		row.star:SetPoint("RIGHT", row, "RIGHT", -infoWidth - 10, 0)
		row.star:Hide()
		-- The tick marks the entry you have on (the Mounts tab's skin).
		row.tick = row:CreateTexture(nil, "OVERLAY")
		row.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row.tick:SetWidth(16)
		row.tick:SetHeight(16)
		row.tick:SetPoint("RIGHT", row, "RIGHT", -infoWidth - 24, 0)
		row.tick:Hide()
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function()
			local bar = getglobal(name .. "ScrollBar")
			bar:SetValue(bar:GetValue() - arg1 * ROW_HEIGHT * 3)
		end)
		row:SetScript("OnClick", function()
			click(this.index, arg1)
		end)
		if enter then
			row:SetScript("OnEnter", function()
				enter(this.index, this)
			end)
			-- The preview box keeps the last row hovered, so the mouse can go over
			-- to it (user, 19 Oct: it went back as soon as the mouse left the row).
			-- It shows what you have on again after a change (list.leave).
			row:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
		end
		list.rows[i] = row
	end
	return list
end

-- Sorting by name or by ID: a toggle button for every list that has one.
local function SortButton(page, name, x, y, key, refilter)
	local button = Button(page, "", 92, x, y, function()
		local prefs = Prefs()
		prefs[key] = not prefs[key]
		this:SetText(prefs[key] and "Sort: ID" or "Sort: A-Z")
		refilter()
	end, name)
	button:SetText(Prefs()[key] and "Sort: ID" or "Sort: A-Z")
	button:SetScript("OnEnter", function()
		Tooltip(this, "Sort order", "Click to list by name (A-Z) or by ID.")
	end)
	button:SetScript("OnLeave", HideTooltip)
	return button
end

-- Creature previews -------------------------------------------------------------

-- A view is a Model that shows a display ID. It loads at level `low`, below
-- an opaque layer, and moves up to `high` once REVEAL has passed. aspect:
-- the model frame's width / height. zoom (steps), panX / panY (parts of the
-- view's height) are the user's (preview boxes).
-- 2.21.8 (user: "I can't drag the model around or zoom in myself, use the
-- same controls as the character window"): a plain Model with a camera set
-- ignores SetPosition and SetFacing, the dressing room's PlayerModel moves
-- and turns. So views are PlayerModels when ClassicAPI's SetDisplayInfo works
-- on one (ui.playerViews, checked once), else Models as before.
local function NewView(parent, name, low, high, aspect)
	local model = CreateFrame(ui.playerViews and "PlayerModel" or "Model", name, parent)
	model:SetFrameLevel(low)
	return { model = model, low = low, high = high, facing = 0, aspect = aspect or 1, zoom = 0, panX = 0, panY = 0,
		player = ui.playerViews }
end

-- Turns a view (PlayerModels turn with SetRotation, Models with SetFacing).
function P.TurnView(view)
	if view.player then
		view.model:SetRotation(view.facing or 0)
	else
		view.model:SetFacing(view.facing or 0)
	end
end

-- The whole model in view (2.21.0; user: the previews were "zoomed in too
-- much"). Seen in game with /dmorph frametest (19 Oct): while a model camera
-- is set, this client draws the model where the camera says and ignores
-- SetPosition and SetFacing (only the scale shows), so 2.21.0-2.21.6's
-- "scale to fit and move the middle to the camera" left models cut off or
-- out of view. Now nothing is moved: a model with a full-body camera
-- ("character info", type 1, Blizzard's own framing of the whole model:
-- 2,918 of 2,984 ported models, 389 of 679 stock ones, Data/ModelFrames.lua)
-- is shown through it; the rest keep the portrait camera (the head), as
-- before 2.21. Zoom is the scale on top. While a model loads (view.fresh)
-- the camera and the scale (a hair off every other frame) are sent again:
-- the client seems to drop them when loading ends.
P.ZOOM_FACTOR = 1.25
-- The client's trig functions take degrees or radians depending on its build.
P.ANGLE = math.sin(math.pi / 2) > 0.99 and 1 or 180 / math.pi
-- The camera a display is shown through: 1 (full body) if it has one, else 0.
function P.ViewCamera(displayID)
	local _, _, _, _, _, _, _, _, _, full = M.GetModelFrame(displayID)
	return full and 1 or 0
end
P.PLAYER_SIZE = 2.2 -- about a player's height in model units
local function FrameView(view)
	local zoom = math.pow(P.ZOOM_FACTOR, view.zoom or 0)
	if view.fresh then
		view.flip = not view.flip
		if view.flip then
			zoom = zoom * 1.001
		end
	end
	-- 2.21.9 (user: still no drag or zoom with 2.21.8): a PlayerModel gets no
	-- camera of the model's (an explicit SetCamera locks it, as in the frame
	-- test); like the dressing room it keeps its own player-sized view, where
	-- moving and turning work. The model is scaled to a player's height
	-- (P.PLAYER_SIZE) from Data/ModelFrames.lua, so it fits that view as you do
	-- (a big creature morph filled the dressing room before), then zoom and
	-- pan move it as the dressing room does.
	if view.player then
		local _, _, _, _, _, _, _, height, width = M.GetModelFrame(view.loaded)
		local fit = 1
		if height then
			fit = P.PLAYER_SIZE / math.max(height, width * 0.75)
		end
		view.model:SetModelScale(fit * ((view.fresh and view.flip) and 1.001 or 1))
		view.model:SetPosition((view.zoom or 0) * 0.3, (view.panX or 0) * 2, (view.panY or 0) * 2)
		return
	end
	view.model:SetModelScale(zoom)
end

local function StartView(view, displayID)
	local model = view.model
	view.loaded = displayID
	view.settle = SETTLE
	-- Seconds the framing is pushed through while the model loads (FrameView).
	view.fresh = 4
	-- Drop the old model and its skins first, so none carry over to the new one.
	pcall(model.ClearModel, model)
	model:SetDisplayInfo(displayID)
	-- Its full-body camera if it has one, else the portrait camera (P.ViewCamera);
	-- a Model has no light of its own.
	if not view.player then
		view.camera = P.ViewCamera(displayID)
		pcall(model.SetCamera, model, view.camera)
	end
	pcall(model.SetLight, model, 1, 0, 0, -0.7, -0.7, 0.7, 1, 1, 1, 0.8, 1, 1, 1)
	P.TurnView(view)
	FrameView(view)
end

-- Clearing a model whose textures are still loading frees them twice (the
-- game's Texture.cpp "Memory Invalid Block" crash, from ClearModel, when
-- hovering or paging fast). So a view changes model at most once per SETTLE;
-- a newer ID waits, and only the latest one is loaded.
local function LoadView(view, displayID)
	view.displayID = displayID
	if not view.manual then
		view.facing = 0
	end
	view.wait = REVEAL
	view.model:SetFrameLevel(view.low)
	if view.settle then
		view.pending = displayID
		return
	end
	view.pending = nil
	StartView(view, displayID)
end

-- Per frame: start a waiting model once the last one has settled, reveal a
-- loaded model, and turn it slowly while `spin` is set.
-- (Plain Model frames turn with SetFacing; SetRotation is PlayerModel's.)
local function TickView(view, elapsed, spin)
	if view.settle then
		view.settle = view.settle - elapsed
		if view.settle <= 0 then
			view.settle = nil
			local pending = view.pending
			view.pending = nil
			if pending and pending ~= view.loaded then
				view.wait = REVEAL
				StartView(view, pending)
			end
		end
	end
	if view.settle and view.pending then
		return
	end
	if view.wait then
		view.wait = view.wait - elapsed
		if view.wait <= 0 then
			view.wait = nil
			view.model:SetFrameLevel(view.high)
		end
	end
	if not view.loaded then
		return
	end
	-- A loading model forgets its scale, place and camera, so they go on every
	-- frame, and are pushed through while it is fresh.
	if view.fresh then
		view.fresh = view.fresh - elapsed
		if view.fresh <= 0 then
			view.fresh = nil
		end
		if not view.player then
			pcall(view.model.SetCamera, view.model, view.camera or 0)
		end
	end
	FrameView(view)
	if spin and view.displayID and not view.manual then
		view.facing = view.facing + elapsed * 1.6
	end
	P.TurnView(view)
end

local function KindColor(kind)
	return KIND_COLORS[kind] or KIND_COLORS[0]
end

local function QualityColor(quality)
	local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
	return color.r, color.g, color.b
end

-- Character preview ---------------------------------------------------------------

-- The dress-up backdrop of the race you look like: your race morph, else your own.
local function ShowArt()
	local state = M.GetState()
	local art = state.race and RACE_ART[state.race]
	if not art then
		local _, token = UnitRace("player")
		art = ART_TOKENS[token or ""] or token or "Human"
	end
	if art ~= ui.artName then
		ui.artName = art
		for i = 1, 4 do
			ui.art[i]:SetTexture("Interface\\DressUpFrame\\DressUpBackground-" .. art .. i)
		end
	end
end

local function UpdatePlate()
	local state = M.GetState()
	local title, info
	if state.display then
		title = M.GetDisplayName(state.display) or "Unlisted model"
		info = "Display ID " .. state.display
	elseif state.race then
		title = M.DescribeBody(state.race, state.gender)
		info = "Race morph"
	else
		title = UnitName("player") or "Your character"
		info = "Not morphed"
	end
	local count = 0
	for _ in pairs(state.items) do
		count = count + 1
	end
	-- Short words: the line wrapped into the name above it (user, 18 Oct).
	if count == 1 then
		info = info .. " - 1 item"
	elseif count > 1 then
		info = info .. " - " .. count .. " items"
	end
	if state.mount then
		info = info .. " - mount skin"
	end
	if state.scale then
		info = info .. " - size " .. math.floor(state.scale * 100 + 0.5) .. "%"
	end
	ui.plateTitle:SetText(title)
	ui.plateInfo:SetText(info)
	-- The size slider shows the picked size without picking it again.
	if ui.sizeSlider then
		ui.sizeSync = true
		ui.sizeSlider:SetValue(state.scale or 1)
		ui.sizeSync = nil
	end
end

local RequestPreview

-- The new look has loaded behind the backdrop: bring it to the front.
-- Puts a preview model where the zoom and the panning say. Closer also means
-- a little lower, so zooming in heads for the face rather than the belt.
local function ApplyView(model)
	local p = ui.preview
	model:SetPosition(p.zoom, p.panX, p.panY - p.zoom * 0.28)
	-- The creature view (P.StageCreature) follows the same zoom, turn and pan.
	local v = ui.stageView
	if v then
		v.zoom, v.facing, v.manual = p.zoom / ZOOM_STEP, p.rotation, true
		v.panX, v.panY = p.panX / 3, p.panY / 3
	end
end

-- 2.21.3 (user's screenshots: a big creature morph filled the dressing room):
-- morphed into a creature with frame data, the stage shows that display in a
-- creature view framed like the preview boxes, not your character (item
-- morphs don't show on creatures anyway).
function P.StageCreature()
	local display = M.GetState().display
	if ui.canPreview and ui.stageView and display and M.GetModelFrame(display) then
		return display
	end
end

local function Zoom(step)
	local p = ui.preview
	p.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, p.zoom + step * ZOOM_STEP))
	ApplyView(p.models[p.front])
end

local function ResetView()
	local p = ui.preview
	p.zoom, p.panX, p.panY = 0, 0, 0
	ApplyView(p.models[p.front])
end

local function SwapPreview()
	local p = ui.preview
	p.front = 3 - p.front
	local front, back = p.models[p.front], p.models[3 - p.front]
	front:SetRotation(p.rotation)
	ApplyView(front)
	front:SetFrameLevel(p.high)
	back:SetFrameLevel(p.low)
	back:Hide()
	p.loading = nil
	if p.again then
		p.again = nil
		RequestPreview()
	end
end

-- A model is only reloaded once it has finished loading: changes made while
-- it loads are picked up by one more load afterwards. Reloading it half way
-- can leave textures from the earlier look on it.
local function LoadPreview()
	local p = ui.preview
	local creature = P.StageCreature()
	local v = ui.stageView
	if creature then
		p.models[1]:Hide()
		p.models[2]:Hide()
		v.model:Show()
		ApplyView(v.model)
		if v.displayID ~= creature then
			LoadView(v, creature)
		end
		return
	end
	if v then
		v.model:Hide()
		v.displayID = nil
	end
	if p.loading then
		p.again = true
		return
	end
	p.loading = true
	local back = p.models[3 - p.front]
	back:SetFrameLevel(p.low)
	back:Show()
	back:SetUnit("player")
	back:SetRotation(p.rotation)
	ApplyView(back)
	Debounce(ui.revealTimer, REVEAL, SwapPreview)
end

-- After any change: the new look loads in the hidden model and replaces the
-- shown one when it's ready. A burst of changes loads once.
RequestPreview = function()
	Debounce(ui.previewTimer, 0.1, LoadPreview)
end

local function UpdateSlots()
	local state = M.GetState()
	for slot, button in pairs(ui.slots) do
		local itemID = state.items[slot]
		if itemID == 0 then
			-- Shows nothing (Invisible, Birthday suit, own gear hidden under a set):
			-- the empty slot, purple. It showed a question mark (user, 18 Oct).
			-- 2.26.0 (user: "icons on the item slots"): the game's Lesser
			-- Invisibility icon, so invisible slots read at a glance.
			button.icon:SetTexture("Interface\\Icons\\Spell_Magic_LesserInvisibilty")
			button.icon:SetVertexColor(1, 1, 1)
			button.glow:Show()
		elseif itemID then
			local ok, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, itemID)
			if not ok then
				texture = nil
			end
			-- A ported piece: the icon of the item it copies.
			if not texture and M.IsPortedItem(itemID) then
				texture = M.GetPortedIcon(itemID)
			end
			-- Not in the client's cache yet: asked for once (ported items copy a
			-- known item's record, the server knows nothing of their own IDs).
			if not texture and not ui.iconAsked[itemID] and not M.IsPortedItem(itemID)
				and type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
				ui.iconAsked[itemID] = true
				pcall(C_Item.RequestLoadItemDataByID, itemID)
			end
			button.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
			button.icon:SetVertexColor(1, 1, 1)
			button.glow:Show()
		else
			-- Not morphed: show the gear you really wear, dimmed.
			local texture = GetInventoryItemTexture("player", slot)
			if texture then
				button.icon:SetTexture(texture)
				button.icon:SetVertexColor(0.45, 0.45, 0.45)
			else
				local _, empty = GetInventorySlotInfo(SLOT_KEYS[slot])
				button.icon:SetTexture(empty)
				button.icon:SetVertexColor(1, 1, 1)
			end
			button.glow:Hide()
		end
		if currentTab == "items" and slot == itemSlot then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

local function SlotTooltip()
	local slot = this.slot
	local itemID = M.GetState().items[slot]
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	GameTooltip:SetText(M.SLOT_NAMES[slot])
	if itemID then
		GameTooltip:AddLine("Morphed into " .. M.DescribeItem(itemID, slot), 0.6, 1, 0.6)
	else
		GameTooltip:AddLine("Showing your own gear.", 0.8, 0.8, 0.8)
	end
	GameTooltip:AddLine("Left-click: browse items for this slot", 1, 1, 1)
	GameTooltip:AddLine("Right-click: back to your own gear", 1, 1, 1)
	GameTooltip:Show()
end

-- Models tab ------------------------------------------------------------------------

local ShowTab -- defined below; the slot buttons switch to the Items tab

local function PageCount()
	local pages = math.ceil((ui.modelTotal or 0) / PAGE_SIZE)
	if pages < 1 then
		pages = 1
	end
	return pages
end

local function UpdatePager()
	local total = Count(ui.modelTotal or 0, "model")
	if ui.listMode then
		ui.pagerText:SetText(total)
		ui.prevPage:Hide()
		ui.nextPage:Hide()
		return
	end
	local pages = PageCount()
	ui.pagerText:SetText("Page " .. Commas(ui.page) .. "/" .. Commas(pages) .. "  (" .. total .. ")")
	ui.prevPage:Show()
	ui.nextPage:Show()
	SetEnabled(ui.prevPage, ui.page > 1)
	SetEnabled(ui.nextPage, ui.page < pages)
end

-- The display ID you're morphed into, if any.
local function TargetDisplay()
	return M.GetState().display
end

local function TileBorder(tile)
	local line = C.line
	if tile.hover then
		line = C.accent
	elseif tile.displayID and tile.displayID == TargetDisplay() then
		line = C.gold
	end
	tile:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

local function FillTiles()
	if ui.listMode or not ui.modelResult then
		return
	end
	local catalog = M.GetCreatureCatalog()
	local first = (ui.page - 1) * PAGE_SIZE
	for i = 1, PAGE_SIZE do
		local tile = ui.tiles[i]
		local entry = ui.modelResult[first + i]
		if entry then
			local id = catalog.ids[entry]
			local color = KindColor(catalog.kind[entry])
			tile.entry, tile.displayID = entry, id
			tile.title:SetText(catalog.names[entry])
			tile.title:SetTextColor(color[1], color[2], color[3])
			tile.idText:SetText(id)
			if M.IsFavourite(id) then
				tile.star:Show()
			else
				tile.star:Hide()
			end
			if tile.view.displayID ~= id then
				LoadView(tile.view, id)
			end
			TileBorder(tile)
			tile:Show()
		else
			tile.entry, tile.displayID = nil, nil
			tile:Hide()
		end
	end
	UpdatePager()
end

local function RefreshModels()
	if ui.listMode then
		ui.modelList.Refresh()
		P.RefreshModelBox()
	else
		FillTiles()
	end
end

local function FilterModels()
	local prefs = Prefs()
	local count
	ui.modelResult, count = M.FilterCatalog(M.GetCreatureCatalog(), ui.modelSearch:GetText(),
		M.MODEL_FILTERS[prefs.filter], nil, prefs.sortModels)
	ui.modelTotal = count
	ui.page = 1
	ui.modelList.SetCount(count)
	FillTiles()
	UpdatePager()
end

local function TurnPage(step)
	local page = ui.page + step
	if page > PageCount() then
		page = PageCount()
	end
	if page < 1 then
		page = 1
	end
	if page ~= ui.page then
		ui.page = page
		FillTiles()
	end
end

-- Grid or list. Each picks up where the other was.
local function SetListMode(listMode)
	if not ui.canPreview then
		listMode = true
	end
	if listMode and not ui.listMode then
		ui.modelList.ScrollTo((ui.page - 1) * PAGE_SIZE + 1)
	elseif ui.listMode and not listMode then
		ui.page = math.floor(ui.modelList.GetOffset() / PAGE_SIZE) + 1
		-- The list's preview box may have taken one of ClassicAPI's 8 NPC
		-- dressing slots from a tile, so the tiles load afresh.
		for i = 1, PAGE_SIZE do
			ui.tiles[i].view.displayID = nil
		end
	end
	ui.listMode = listMode
	-- Without ClassicAPI the list is forced; keep the choice for when it is back.
	if ui.canPreview then
		Prefs().list = listMode
	end
	if listMode then
		ui.grid:Hide()
		ui.listBox:Show()
		ui.viewButton:SetText("Grid view")
	else
		ui.listBox:Hide()
		ui.grid:Show()
		ui.viewButton:SetText("List view")
	end
	RefreshModels()
	UpdatePager()
end

-- Click a model: become it.
local function MorphInto(displayID)
	ui.displayBox:SetText(displayID)
	Morph(M.SetDisplay, displayID)
end

local function ModelTooltip(owner, entry)
	local catalog = M.GetCreatureCatalog()
	local color = KindColor(catalog.kind[entry])
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(catalog.names[entry], color[1], color[2], color[3])
	GameTooltip:AddLine("Display ID " .. catalog.ids[entry], 1, 1, 1)
	local tags = catalog.tags[entry]
	if tags then
		local words = {}
		if strfind(tags, "boss", 1, true) then
			table.insert(words, "Boss")
		end
		if strfind(tags, "rare", 1, true) then
			table.insert(words, "Rare creature")
		end
		if strfind(tags, "mount", 1, true) then
			table.insert(words, "Mount")
		end
		GameTooltip:AddLine(table.concat(words, ", "), 1, 0.82, 0)
	end
	GameTooltip:AddLine(KIND_NOTES[catalog.kind[entry] or 0], 0.7, 0.7, 0.7)
	GameTooltip:AddLine("Click to morph into it.", 0.6, 1, 0.6)
	if M.IsFavourite(catalog.ids[entry]) then
		GameTooltip:AddLine("Right-click to take it off your favourites.", 1, 0.82, 0)
	else
		GameTooltip:AddLine("Right-click to add it to your favourites.", 1, 0.82, 0)
	end
	GameTooltip:Show()
end

-- Right-click on a model: star it, or take the star off.
local function ToggleFavourite(displayID)
	SetStatus(M.ToggleFavourite(displayID))
	RefreshModels()
end

local function NewTile(parent, i)
	local col, row = math.mod(i - 1, GRID_COLS), math.floor((i - 1) / GRID_COLS)
	local tile = CreateFrame("Button", "DmorphOctoTile" .. i, parent)
	tile:SetWidth(TILE_W)
	tile:SetHeight(TILE_H)
	tile:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (TILE_W + TILE_GAP), -row * (TILE_H + TILE_GAP))
	Flat(tile, C.card, C.line)
	local base = tile:GetFrameLevel()
	-- Levels: model while loading (+1) < cover (+2) < model once loaded (+3) < text (+4).
	tile.view = NewView(tile, "DmorphOctoTile" .. i .. "Model", base + 1, base + 3, (TILE_W - 8) / (TILE_H - 34))
	tile.view.model:SetPoint("TOPLEFT", tile, "TOPLEFT", 4, -4)
	tile.view.model:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -4, 30)
	local cover = Layer(tile, 2)
	cover:SetAllPoints(tile.view.model)
	Gradient(cover, "BACKGROUND", 0.04, 0.035, 0.06, 1, 0.16, 0.1, 0.24, 1):SetAllPoints(cover)
	local text = Layer(tile, 4)
	text:SetAllPoints(tile)
	tile.title = Font(text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), 11)
	tile.title:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 5, 4)
	tile.title:SetWidth(TILE_W - 10)
	tile.title:SetHeight(26)
	tile.title:SetJustifyH("CENTER")
	tile.idText = Font(text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 10, C.dim)
	tile.idText:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -6, -6)
	tile.idText:SetJustifyH("RIGHT")
	tile.star = text:CreateTexture(nil, "OVERLAY")
	tile.star:SetTexture(STAR)
	tile.star:SetTexCoord(0, 0.25, 0, 0.25)
	tile.star:SetWidth(16)
	tile.star:SetHeight(16)
	tile.star:SetPoint("TOPLEFT", tile, "TOPLEFT", 5, -5)
	tile.star:Hide()
	tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	tile:EnableMouseWheel(true)
	tile:SetScript("OnMouseWheel", function()
		TurnPage(-arg1)
	end)
	tile:SetScript("OnClick", function()
		if arg1 == "RightButton" then
			ToggleFavourite(this.displayID)
			if this.hover then
				ModelTooltip(this, this.entry)
			end
		else
			MorphInto(this.displayID)
		end
	end)
	tile:SetScript("OnEnter", function()
		this.hover = true
		TileBorder(this)
		ModelTooltip(this, this.entry)
	end)
	tile:SetScript("OnLeave", function()
		this.hover = nil
		TileBorder(this)
		GameTooltip:Hide()
	end)
	tile:SetScript("OnUpdate", function()
		TickView(this.view, arg1, this.hover)
	end)
	return tile
end

-- Preview boxes ----------------------------------------------------------------

-- Every list tab has one beside its list (2.21.0, user: "a box on the side and
-- an arrow up and down for scrolling through items one at a time"; it took
-- the place of the cards that floated next to a hovered row). It shows what
-- you hover, else what you have on. A creature shows whole in a Model (kind
-- "model", see FrameView); items, sets and outfits on your character in a
-- DressUpModel (kind "dress", the Dressing Room's model: SetUnit("player")
-- once per opening of the window, then Dress() and TryOn(item) per look, as
-- OctoWoW's DressUpFrame.lua does). Mouse wheel or + / - zoom, drag turns it,
-- right-drag moves it, Reset puts the view back. Previous / Next wear the
-- entry above or below the one you have on in the list.
P.ZOOM_MIN, P.ZOOM_MAX = -6, 10

-- The try-on. The game can only put on items it knows: one it hasn't seen yet
-- is asked for (ClassicAPI) and goes on when it arrives. A ported piece copies
-- a real item's record (its template): if the server hasn't sent that one, a
-- known item of the same slot stands in, as when you wear it (the card waited
-- for the template forever: user, 16 Oct). After P.CARD_WAIT seconds the box
-- says what didn't come.
P.CARD_WAIT = 8
function P.TryOnAll(box)
	local missing = 0
	for i = 1, table.getn(box.items) do
		local id = box.items[i]
		if not box.on[id] then
			local ported = M.IsPortedItem(id)
			if ported and not GetItemInfo(id) and M.CanShowPortedItem then
				M.CanShowPortedItem(id)
			end
			if GetItemInfo(id) then
				pcall(box.model.TryOn, box.model, id)
				P.ApplyBoxView(box) -- trying on resets the model's place: keep your zoom (Khijazi)
				box.on[id] = true
			else
				missing = missing + 1
				-- A ported item's own ID means nothing to the server.
				if not ported and not box.asked[id] and type(C_Item) == "table"
					and type(C_Item.RequestLoadItemDataByID) == "function" then
					box.asked[id] = true
					pcall(C_Item.RequestLoadItemDataByID, id)
				end
			end
		end
	end
	box.pending = missing > 0 or nil
	if missing == 0 then
		box.status:SetText("")
	elseif (box.waited or 0) < P.CARD_WAIT then
		box.status:SetText("Loading from the server...")
	elseif missing == table.getn(box.items) then
		box.status:SetText("The server didn't send this.")
	else
		box.status:SetText(missing .. (missing == 1 and " piece" or " pieces") .. " didn't load.")
	end
end

-- Where the zoom and the panning put a box's model. A creature is framed by
-- FrameView (every frame, from TickView); your character as on the stage:
-- closer is also a little lower, towards the face.
function P.ApplyBoxView(box)
	if box.kind == "model" then
		local view = box.view
		view.zoom, view.panX, view.panY = box.zoom, box.panX, box.panY
		return
	end
	local zoom = box.zoom * ZOOM_STEP
	box.model:SetPosition(zoom, box.panX, box.panY - zoom * 0.28)
	box.model:SetRotation(box.facing)
end

function P.BoxZoom(box, step)
	box.zoom = math.max(P.ZOOM_MIN, math.min(P.ZOOM_MAX, box.zoom + step))
	P.ApplyBoxView(box)
end

function P.BoxResetView(box)
	box.zoom, box.panX, box.panY, box.manual, box.facing = 0, 0, 0, nil, 0
	if box.view then
		box.view.manual, box.view.facing = nil, 0
	end
	P.ApplyBoxView(box)
end

-- Text under the model: the name (in its colour) and a line about it.
function P.BoxText(box, title, color, info)
	box.title:SetText(title or "")
	color = color or C.gold
	box.title:SetTextColor(color[1], color[2], color[3])
	box.info:SetText(info or "")
end

-- A creature (kind "model"), or nothing (displayID nil).
function P.BoxShowModel(box, displayID, title, color, info)
	P.BoxText(box, title, color, info)
	local view = box.view
	if not displayID then
		view.displayID, view.wait = nil, nil
		view.model:SetFrameLevel(view.low)
		box.status:SetText("")
		return
	end
	if not ui.canPreview then
		box.status:SetText("3D previews need ClassicAPI.")
		return
	end
	box.status:SetText("")
	if view.displayID ~= displayID then
		LoadView(view, displayID)
	end
end

-- Your character wearing items (kind "dress"); no items: as you are.
function P.BoxShowItems(box, items, title, color, info)
	P.BoxText(box, title, color, info)
	if not box.loaded then
		-- Your character as it is now (once per opening of the window).
		box.loaded, box.dressed = true, nil
		box.model:SetFrameLevel(box.base + 1)
		box.model:SetUnit("player")
		box.wait = REVEAL
		P.ApplyBoxView(box)
	end
	-- The same items again (a click refreshes the window several times): left
	-- as they are. Dressing a model again while its textures load drew your
	-- character white until the next hover (user, 19 Oct).
	items = items or {}
	local same = table.getn(items) == table.getn(box.items)
	for i = 1, table.getn(items) do
		if items[i] ~= box.items[i] then
			same = false
		end
	end
	if same and box.dressed then
		return
	end
	box.dressed = true
	box.model:Dress()
	-- Dressing again put the model back where it started; your zoom, turn and
	-- move stay from item to item and set to set (Khijazi, 29 Oct).
	P.ApplyBoxView(box)
	box.items, box.on, box.waited, box.retry = items, {}, 0, 0.25
	P.TryOnAll(box)
end

function P.BoxButton(parent, text, width, name, onClick, title, line)
	local button = Button(parent, text, width, 0, 0, onClick, name)
	button:SetHeight(18)
	button:SetScript("OnEnter", function()
		Tooltip(this, title, line)
	end)
	button:SetScript("OnLeave", HideTooltip)
	return button
end

-- A box on the right of a page, from y down `rows` list rows (as tall as the
-- list beside it). step(-1 / 1) wears the previous / next entry.
function P.NewBox(page, key, kind, y, rows, heading, step)
	local height = rows * ROW_HEIGHT
	local name = "DmorphOcto" .. key .. "Box"
	local box = CreateFrame("Frame", name, page)
	box:SetPoint("TOPLEFT", page, "TOPLEFT", PAGE_W - BOX_W - 8, y)
	box:SetWidth(BOX_W)
	box:SetHeight(height)
	Flat(box, C.card, C.line)
	box.kind = kind
	box.zoom, box.panX, box.panY, box.facing = 0, 0, 0, 0
	local base = box:GetFrameLevel()
	box.base = base
	-- Levels: model while loading (+1) < cover (+2) < model shown (+3) < drag
	-- area (+4) < text and buttons (+5).
	local modelHeight = height - 22 - 70
	if kind == "model" then
		box.view = NewView(box, name .. "Model", base + 1, base + 3, (BOX_W - 10) / modelHeight)
		box.model = box.view.model
	else
		box.model = CreateFrame("DressUpModel", name .. "Model", box)
		box.model:SetFrameLevel(base + 1)
		box.items, box.on, box.asked = {}, {}, {}
	end
	box.model:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -22)
	box.model:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 70)
	local cover = Layer(box, 2)
	cover:SetAllPoints(box.model)
	Gradient(cover, "BACKGROUND", 0.04, 0.035, 0.06, 1, 0.16, 0.1, 0.24, 1):SetAllPoints(cover)

	-- Over the model: wheel zooms, drag turns, right-drag moves.
	local drag = Layer(box, 4)
	drag:SetAllPoints(box.model)
	drag:EnableMouse(true)
	drag:EnableMouseWheel(true)
	drag:SetScript("OnMouseWheel", function()
		P.BoxZoom(box, arg1)
	end)
	drag:SetScript("OnMouseDown", function()
		local x, y = GetCursorPosition()
		if arg1 == "RightButton" then
			this.panX, this.panY = x, y
		else
			this.dragX = x
		end
	end)
	drag:SetScript("OnMouseUp", function()
		this.dragX, this.panX, this.panY = nil, nil, nil
	end)
	drag:SetScript("OnUpdate", function()
		if ui.stageView.model:IsShown() then
			TickView(ui.stageView, arg1, false)
		end
		if this.dragX then
			local x = GetCursorPosition()
			local turn = (x - this.dragX) * 0.02
			this.dragX = x
			box.manual = true
			box.facing = box.facing + turn
			if box.view then
				box.view.manual = true
				box.view.facing = box.view.facing + turn
			end
			P.ApplyBoxView(box)
		elseif this.panX then
			-- Creatures move by parts of the box's height, your character in yards.
			local x, y = GetCursorPosition()
			local scale = frame:GetEffectiveScale()
			local step = 1 / (modelHeight * scale)
			if kind ~= "model" then
				step = 0.006 / (scale * (1 + math.max(box.zoom * ZOOM_STEP, 0) * 0.45))
			end
			box.panX = box.panX + (x - this.panX) * step
			box.panY = box.panY + (y - this.panY) * step
			this.panX, this.panY = x, y
			P.ApplyBoxView(box)
		end
	end)

	local text = Layer(box, 5)
	text:SetAllPoints(box)
	box.heading = Font(text:CreateFontString(name .. "Heading", "OVERLAY"), 12, C.accent)
	box.heading:SetPoint("TOPLEFT", box, "TOPLEFT", 7, -5)
	box.heading:SetText(heading)
	local reset = P.BoxButton(text, "Reset", 40, name .. "ZoomReset", function()
		P.BoxResetView(box)
	end, "Reset view", "The whole model again, turning.")
	reset:ClearAllPoints()
	reset:SetPoint("TOPRIGHT", box, "TOPRIGHT", -4, -2)
	local zoomIn = P.BoxButton(text, "+", 18, name .. "ZoomIn", function()
		P.BoxZoom(box, 1)
	end, "Zoom in", "Or: mouse wheel over the model. Drag turns it, right-drag moves it.")
	zoomIn:ClearAllPoints()
	zoomIn:SetPoint("TOPRIGHT", reset, "TOPLEFT", -2, 0)
	local zoomOut = P.BoxButton(text, "-", 18, name .. "ZoomOut", function()
		P.BoxZoom(box, -1)
	end, "Zoom out", "Or: mouse wheel over the model. Drag turns it, right-drag moves it.")
	zoomOut:ClearAllPoints()
	zoomOut:SetPoint("TOPRIGHT", zoomIn, "TOPLEFT", -2, 0)

	box.title = Font(text:CreateFontString(name .. "Title", "OVERLAY"), 12, C.gold)
	box.title:SetPoint("BOTTOM", box, "BOTTOM", 0, 44)
	box.title:SetWidth(BOX_W - 12)
	box.title:SetHeight(26)
	box.info = Font(text:CreateFontString(name .. "Info", "OVERLAY"), 10, C.dim)
	box.info:SetPoint("BOTTOM", box, "BOTTOM", 0, 32)
	box.info:SetWidth(BOX_W - 12)
	box.status = Font(text:CreateFontString(name .. "Status", "OVERLAY"), 11)
	box.status:SetPoint("CENTER", box.model, "CENTER", 0, 0)
	box.status:SetWidth(BOX_W - 20)

	local half = math.floor((BOX_W - 14) / 2)
	local prev = Button(text, "Previous", half, 5, -(height - 26), function()
		step(-1)
	end, "DmorphOcto" .. key .. "Prev")
	prev:SetScript("OnEnter", function()
		Tooltip(this, "Previous", "Puts on the one above yours in the list.")
	end)
	prev:SetScript("OnLeave", HideTooltip)
	local nextButton = Button(text, "Next", half, BOX_W - 5 - half, -(height - 26), function()
		step(1)
	end, "DmorphOcto" .. key .. "Next")
	nextButton:SetScript("OnEnter", function()
		Tooltip(this, "Next", "Puts on the one below yours in the list.")
	end)
	nextButton:SetScript("OnLeave", HideTooltip)

	box:SetScript("OnUpdate", function()
		if this.view then
			TickView(this.view, arg1, true)
			return
		end
		if this.wait then
			this.wait = this.wait - arg1
			if this.wait <= 0 then
				this.wait = nil
				this.model:SetFrameLevel(this.base + 3)
			end
		end
		if not this.manual then
			this.facing = this.facing + arg1 * 0.8
		end
		P.ApplyBoxView(this)
		if this.pending then
			this.waited = (this.waited or 0) + arg1
			this.retry = (this.retry or 0) - arg1
			if this.retry <= 0 then
				-- Quick at first, then once a second (looking for a stand-in goes through a slot's items).
				this.retry = this.waited < 2 and 0.25 or 1
				P.TryOnAll(this)
			end
		end
	end)
	ui.boxes[key] = box
	return box
end

-- The entry `step` away from position `pos` (nil: none worn) in a list of
-- `count`, wrapping round; nil if the list is empty.
function P.StepPosition(pos, step, count)
	if count == 0 then
		return nil
	end
	if pos then
		return Wrap(pos, step, count)
	end
	return step > 0 and 1 or count
end

-- Where `value` is in a filtered list (ids[result[k]] == value), or nil.
function P.FindPosition(result, count, ids, value)
	if not (value and result) then
		return nil
	end
	for k = 1, count or 0 do
		if ids[result[k]] == value then
			return k
		end
	end
end

local function ModelFilterMenu()
	local prefs, options = Prefs(), {}
	for i = 1, table.getn(M.MODEL_FILTERS) do
		table.insert(options, { text = M.MODEL_FILTERS[i].text, index = i, checked = prefs.filter == i })
	end
	OpenMenu(this, options, function(option)
		Prefs().filter = option.index
		ui.modelFilter:SetText(option.text)
		FilterModels()
	end)
end

-- The list view's box: the model you hover, else the one you have on.
function P.RefreshModelBox()
	local box = ui.modelBox
	if not box then
		return
	end
	local id = TargetDisplay()
	if id then
		local name, kind = M.GetDisplayName(id)
		P.BoxShowModel(box, id, name or "Unlisted model", KindColor(kind), "Display ID " .. id .. " - you have it on")
	else
		P.BoxShowModel(box, nil, "Your own model", C.dim, "Hover a model to see it here.")
	end
end

function P.ShowModelEntry(index)
	local entry = ui.modelResult[index]
	if entry then
		local catalog = M.GetCreatureCatalog()
		P.BoxShowModel(ui.modelBox, catalog.ids[entry], catalog.names[entry], KindColor(catalog.kind[entry]),
			"Display ID " .. catalog.ids[entry] .. " - click to morph")
	end
end

-- Previous / Next: the model above or below yours in the list.
function P.StepModel(step)
	local catalog = M.GetCreatureCatalog()
	local pos = P.FindPosition(ui.modelResult, ui.modelTotal, catalog.ids, TargetDisplay())
	pos = P.StepPosition(pos, step, ui.modelTotal or 0)
	if not pos then
		return SetStatus(false, "No models in the list: clear the search or pick another filter.")
	end
	MorphInto(catalog.ids[ui.modelResult[pos]])
	ui.modelList.Show(pos)
	P.RefreshModelBox()
end

local function BuildModelsPage(page)
	local prefs = Prefs()
	Label(page, "Search", "GameFontNormalSmall", 10, -12)
	ui.modelSearch = EditBox(page, "DmorphOctoModelSearch", 150, 52, -8)
	ui.modelSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterModels)
	end)
	ui.modelSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterModels()
	end)
	ui.modelFilter = Button(page, M.MODEL_FILTERS[prefs.filter].text, 150, 210, -7, ModelFilterMenu, "DmorphOctoModelFilter")
	ui.modelFilter:SetScript("OnEnter", function()
		Tooltip(this, "Which models to list", "Creatures, bosses, rare creatures, mounts, models no creature uses,",
			"or only the ones OctoWoW added.")
	end)
	ui.modelFilter:SetScript("OnLeave", HideTooltip)
	ui.viewButton = Button(page, "List view", 82, 364, -7, function()
		SetListMode(not ui.listMode)
	end, "DmorphOctoModelView")
	SortButton(page, "DmorphOctoModelSort", PAGE_W - 92 - 8, -7, "sortModels", FilterModels)

	-- Pager (grid view) or how many (list view).
	ui.prevPage = Button(page, "<", 24, 8, -33, function()
		TurnPage(-1)
	end, "DmorphOctoPrevPage")
	ui.nextPage = Button(page, ">", 24, 210, -33, function()
		TurnPage(1)
	end, "DmorphOctoNextPage")
	ui.pagerText = Font(page:CreateFontString("DmorphOctoPagerText", "OVERLAY", "GameFontHighlightSmall"), 11, C.dim)
	ui.pagerText:SetPoint("TOP", page, "TOPLEFT", 121, -38)

	-- Grid of previews.
	ui.grid = CreateFrame("Frame", "DmorphOctoModelGrid", page)
	ui.grid:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -60)
	ui.grid:SetWidth(GRID_COLS * TILE_W + (GRID_COLS - 1) * TILE_GAP)
	ui.grid:SetHeight(2 * TILE_H + TILE_GAP)
	ui.grid:EnableMouseWheel(true)
	ui.grid:SetScript("OnMouseWheel", function()
		TurnPage(-arg1)
	end)
	for i = 1, PAGE_SIZE do
		ui.tiles[i] = NewTile(ui.grid, i)
	end

	-- Or a list, with the preview box.
	ui.listBox = CreateFrame("Frame", "DmorphOctoModelListBox", page)
	ui.listBox:SetAllPoints(page)
	ui.modelList = List(ui.listBox, "DmorphOctoModelList", 8, -60, 52, function(row, index)
		local catalog = M.GetCreatureCatalog()
		local i = ui.modelResult[index]
		local color = KindColor(catalog.kind[i])
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(color[1], color[2], color[3])
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == TargetDisplay() then
			row:LockHighlight()
			row.tick:Show()
			row.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		end
		if M.IsFavourite(catalog.ids[i]) then
			row.star:Show()
		end
	end, function(index, button)
		local displayID = M.GetCreatureCatalog().ids[ui.modelResult[index]]
		if button == "RightButton" then
			ToggleFavourite(displayID)
		else
			MorphInto(displayID)
		end
	end, P.ShowModelEntry, LIST_W)
	ui.modelList.leave = P.RefreshModelBox
	ui.modelBox = P.NewBox(ui.listBox, "Models", "model", -60, LIST_ROWS, "Preview", P.StepModel)

	-- Any display ID, including ones no list has.
	local y = -346
	Label(page, "Display ID", "GameFontNormalSmall", 10, y - 5)
	ui.displayBox = EditBox(page, "DmorphOctoDisplayID", 70, 76, y, 9)
	local function Apply(step)
		local displayID = M.ParseID(ui.displayBox:GetText()) or TargetDisplay()
		if not displayID then
			if step == 0 then
				return SetStatus(false, "Type a display ID first.")
			end
			displayID = 0
		end
		displayID = displayID + step
		if displayID < 1 then
			displayID = 1
		end
		ui.displayBox:ClearFocus()
		MorphInto(displayID)
	end
	ui.displayBox:SetScript("OnEnterPressed", function()
		Apply(0)
	end)
	Button(page, "<", 24, 152, y, function()
		Apply(-1)
	end, "DmorphOctoDisplayPrev")
	Button(page, ">", 24, 178, y, function()
		Apply(1)
	end, "DmorphOctoDisplayNext")
	Button(page, "Morph", 70, 206, y, function()
		Apply(0)
	end)
	Label(page, "< and > step through every ID.", "GameFontDisableSmall", 284, y - 6)

	if not ui.canPreview then
		ui.viewButton:Hide()
		Label(page, "3D previews need ClassicAPI.", "GameFontDisableSmall", 366, -13)
	end
	ui.listMode = nil
	SetListMode(prefs.list)
end

-- Favourites tab --------------------------------------------------------------------

local MOUNT_COLOR = { 1, 0.82, 0.4 }

local function FilterFavourites(keep)
	local prefs = Prefs()
	local filter = FAV_FILTERS[prefs.favFilter]
	local query = strlower(ui.favSearch:GetText() or "")
	query = string.gsub(query, "^%s+", "")
	query = string.gsub(query, "%s+$", "")
	local favourites, list, n = M.GetFavourites(), {}, 0
	for i = 1, table.getn(favourites) do
		local fav = favourites[i]
		if filter.mount == nil or filter.mount == (fav.mount == true) then
			local name = M.GetDisplayName(fav.id) or ("Display " .. fav.id)
			if query == "" or tostring(fav.id) == query or strfind(strlower(name), query, 1, true) then
				n = n + 1
				list[n] = { id = fav.id, mount = fav.mount, name = name, lower = strlower(name) }
			end
		end
	end
	if prefs.sortFavs then
		table.sort(list, function(a, b)
			return a.id < b.id or (a.id == b.id and a.lower < b.lower)
		end)
	else
		table.sort(list, function(a, b)
			return a.lower < b.lower or (a.lower == b.lower and a.id < b.id)
		end)
	end
	ui.favResult = list
	ui.favCount:SetText(Count(n, "favourite"))
	ui.favList.SetCount(n, keep)
	if table.getn(favourites) == 0 then
		ui.favEmpty:Show()
	else
		ui.favEmpty:Hide()
	end
end

local function RefreshFavourites()
	FilterFavourites(true)
	P.RefreshFavBox()
end

local function FavouriteMenu()
	local prefs, options = Prefs(), {}
	for i = 1, table.getn(FAV_FILTERS) do
		table.insert(options, { text = FAV_FILTERS[i].text, index = i, checked = prefs.favFilter == i })
	end
	OpenMenu(this, options, function(option)
		Prefs().favFilter = option.index
		ui.favFilter:SetText(option.text)
		FilterFavourites()
	end)
end

-- The favourite you have on: your model, else your mount's skin.
function P.WornFavourite()
	local state = M.GetState()
	for k = 1, table.getn(ui.favResult or {}) do
		local fav = ui.favResult[k]
		if (fav.mount and state.mount == fav.id) or (not fav.mount and state.display == fav.id) then
			return k
		end
	end
end

function P.ShowFavourite(fav, info)
	P.BoxShowModel(ui.favBox, fav.id, fav.name, fav.mount and MOUNT_COLOR or KIND_COLORS[0], info)
end

function P.RefreshFavBox()
	local k = P.WornFavourite()
	if k then
		local fav = ui.favResult[k]
		P.ShowFavourite(fav, (fav.mount and "Mount " or "Model ") .. fav.id .. " - you have it on")
	else
		P.BoxShowModel(ui.favBox, nil, "No favourite on", C.dim, "Hover one to see it here.")
	end
end

function P.WearFavourite(fav)
	if fav.mount then
		Morph(M.SetMount, fav.id)
	else
		Morph(M.SetDisplay, fav.id)
	end
end

function P.StepFavourite(step)
	local n = table.getn(ui.favResult or {})
	local pos = P.StepPosition(P.WornFavourite(), step, n)
	if not pos then
		return SetStatus(false, "No favourites in the list.")
	end
	P.WearFavourite(ui.favResult[pos])
	ui.favList.Show(pos)
	P.ShowFavourite(ui.favResult[pos], "Click a row to wear it")
end

local function BuildFavouritesPage(page)
	local prefs = Prefs()
	Label(page, "Search", "GameFontNormalSmall", 10, -12)
	ui.favSearch = EditBox(page, "DmorphOctoFavSearch", 150, 52, -8)
	ui.favSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterFavourites)
	end)
	ui.favSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterFavourites()
	end)
	ui.favFilter = Button(page, FAV_FILTERS[prefs.favFilter].text, 150, 210, -7, FavouriteMenu, "DmorphOctoFavFilter")
	SortButton(page, "DmorphOctoFavSort", PAGE_W - 92 - 8, -7, "sortFavs", FilterFavourites)

	ui.favList = List(page, "DmorphOctoFavList", 8, -36, 80, function(row, index)
		local fav = ui.favResult[index]
		local state = M.GetState()
		row.text:SetText(fav.name)
		local worn
		if fav.mount then
			row.text:SetTextColor(MOUNT_COLOR[1], MOUNT_COLOR[2], MOUNT_COLOR[3])
			row.info:SetText("Mount " .. fav.id)
			worn = state.mount == fav.id
		else
			row.info:SetText("Model " .. fav.id)
			worn = state.display == fav.id
		end
		if worn then
			row:LockHighlight()
			row.tick:Show()
		end
	end, function(index, button)
		local fav = ui.favResult[index]
		if button == "RightButton" then
			SetStatus(M.ToggleFavourite(fav.id, fav.mount))
			FilterFavourites(true)
			P.RefreshFavBox()
		else
			P.WearFavourite(fav)
		end
	end, function(index)
		local fav = ui.favResult[index]
		if fav then
			P.ShowFavourite(fav, (fav.mount and "Mount " or "Model ") .. fav.id .. " - click to wear it")
		end
	end, LIST_W, 16)
	ui.favList.leave = P.RefreshFavBox
	ui.favBox = P.NewBox(page, "Favourites", "model", -36, 16, "Preview", P.StepFavourite)
	ui.favCount = Label(page, "", "GameFontDisableSmall", 10, -334, "DmorphOctoFavCount")
	ui.favEmpty = Label(page, "No favourites yet. Right-click a model in the Models tab to star it.",
		"GameFontDisableSmall", 14, -44)
	ui.favEmpty:SetWidth(LIST_W - 12)
	Label(page, "Click to wear it. Right-click to take it off the list.", "GameFontDisableSmall", 10, -350)
	Label(page, "Star more: right-click a model (Models tab) or a mount skin (Mounts tab).",
		"GameFontDisableSmall", 10, -364)
end

-- Races tab ------------------------------------------------------------------------

-- One tab for both ways of changing race. A portrait morphs you into that race
-- with your own face, skin and hair, and your gear shows (VanillaHelpers' race
-- morph). With DmorphHelper.dll and the game's list of looks
-- (Data/CharOptions.lua), the first five < > rows change that model's real
-- skin colour, face and hair, one row at a time, and the last one wears whole
-- NPC looks. Without them every row steps through the faces, skin colours and
-- hair of the game's own NPCs of that race (Data/Looks.lua); item morphs don't
-- show on an NPC look.

local function RaceIcon(button, race, gender)
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	icon:SetTexture(RACE_ICONS_FILE)
	local c = RACE_ICONS[race]
	icon:SetTexCoord(c[1], c[2], c[3] + gender * 0.5, c[3] + gender * 0.5 + 0.25)
	button.ring = button:CreateTexture(nil, "OVERLAY")
	button.ring:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	button.ring:SetBlendMode("ADD")
	button.ring:SetVertexColor(1, 0.82, 0.2)
	button.ring:SetWidth(button:GetWidth() * 1.8)
	button.ring:SetHeight(button:GetHeight() * 1.8)
	button.ring:SetPoint("CENTER", button, "CENTER", 0, 0)
	button.ring:Hide()
	Hover(button, 0.3)
	button.race, button.gender = race, gender
end

local function GenderName(gender)
	if gender == 1 then
		return "Female"
	end
	return "Male"
end

-- The race and gender the tab works on, and the NPC look you wear (its
-- position in that race's looks), or nil when you wear your own face.
local function RaceTarget()
	local c = ui.creator
	local state = M.GetState()
	if c.index and c.race then
		local look = M.GetLooks(c.race, c.gender)[c.index]
		if not (look and state.display == look[1]) then
			c.index = nil -- you've morphed into something else since
		end
	end
	if not c.index then
		local race, gender = M.GetBodyRace()
		c.race, c.gender = race or c.race or 1, gender or c.gender or 0
	end
	return c.race, c.gender, c.index
end

-- Whether rows 1-5 change your own model's look (DmorphHelper) for a race.
local function OwnLookMode(race, gender)
	return M.HasHelper() and M.GetLookOptions(race, gender) ~= nil
end

local function Position(list, value)
	for i = 1, table.getn(list) do
		if list[i] == value then
			return i
		end
	end
	return 1
end

local function RefreshRaces()
	local race, gender, index = RaceTarget()
	local state = M.GetState()
	local nativeRace, nativeGender = M.GetNative()
	if nativeRace then
		ui.nativeLabel:SetText("Your character: " .. M.DescribeBody(nativeRace, nativeGender))
	else
		ui.nativeLabel:SetText("")
	end
	for _, button in pairs(ui.raceButtons) do
		if button.race == race and button.gender == gender and (index or not state.display) then
			button.ring:Show()
			button:LockHighlight()
		else
			button.ring:Hide()
			button:UnlockHighlight()
		end
	end
	local list = M.GetLooks(race, gender)
	local look = index and list[index]
	if look then
		ui.creatorTitle:SetText(M.DescribeBody(race, gender) .. ": NPC look " .. Commas(index) .. " of "
			.. Commas(table.getn(list)) .. " (display " .. look[1] .. ")")
	elseif state.display then
		ui.creatorTitle:SetText("Morphed into a creature. Pick a portrait to go back to a race.")
	else
		ui.creatorTitle:SetText(M.DescribeBody(race, gender) .. ": your own face, skin and hair")
	end
	local own = OwnLookMode(race, gender)
	local options, values5 = own and M.GetLookOptions(race, gender)
	if own and look then
		values5 = { look[2], look[3], look[4], look[5], look[6] }
	elseif own and not state.display then
		local _, _, _, current, picked = M.GetLookState()
		values5 = current
		if picked then
			ui.creatorTitle:SetText(M.DescribeBody(race, gender) .. ": your model, with a look you picked")
		end
	end
	for f = 1, 6 do
		local row = ui.creatorRows[f]
		local text, n = "yours", 2
		if own and f <= 5 then
			-- Your model's look among everything the race can wear.
			text = "?"
			if values5 then
				local choices, pos, npc = M.LookRow(options, values5, f)
				n = table.getn(choices)
				text = (pos > 0 and pos or "?") .. " of " .. n
				if npc then
					text = text .. " (NPC)"
				end
			end
		elseif look then
			-- Each row counts every value the race's NPCs have for it.
			local values = M.GetLookValues(race, gender, f)
			n = table.getn(values)
			text = Position(values, M.LookValue(look, f)) .. " of " .. n
			if f == 6 then
				text = text .. "  (" .. Count(look[7], "piece") .. ")"
			end
		elseif f == 6 then
			text = "your gear"
		end
		row.value:SetText(text)
		if n < 2 then
			row.value:SetTextColor(0.5, 0.5, 0.5)
		else
			row.value:SetTextColor(1, 1, 1)
		end
		if f == 5 then
			if gender == 1 then
				row.label:SetText("Features")
			else
				row.label:SetText("Facial hair")
			end
		elseif f == 6 then
			if own then
				row.label:SetText("NPC look")
			else
				row.label:SetText("Outfit")
			end
		end
	end
	if own then
		ui.racesHint:SetText("< > change your model's real skin, face and hair; NPC look wears a whole NPC.")
	else
		ui.racesHint:SetText("< > go to the next value an NPC has; other rows change only if they must.")
	end
end

local function WearLook(race, gender, index, message)
	local list = M.GetLooks(race, gender)
	if not (index and list[index]) then
		return SetStatus(false, "The game has no " .. M.DescribeBody(race, gender) .. " NPC looks.")
	end
	local c = ui.creator
	c.race, c.gender, c.index = race, gender, index
	Morph(function()
		local ok, text = M.SetDisplay(list[index][1])
		if ok and message then
			text = message
		end
		return ok, text
	end)
end

-- A row's name as the Races tab shows it ("Features" on women).
local function FeatureName(f, gender)
	if f == 5 and gender == 1 then
		return "Features"
	end
	return M.LOOK_FEATURES[f]
end

-- Row f (1-6) one value along. It always changes, to the next value an NPC of
-- this race has; if none has it with your other rows, the closest look is
-- worn and the status says which rows came along.
-- Your own model of the race the tab shows, from an NPC look or a creature.
local function ToOwnModel(race, gender, index)
	if index or M.GetState().display then
		return M.SetRace(race, gender)
	end
	return true
end

local function StepFeature(f, step)
	local race, gender, index = RaceTarget()
	local list = M.GetLooks(race, gender)
	if f <= 5 and OwnLookMode(race, gender) then
		local npc = index and list[index]
		ui.creator.index = nil
		return Morph(function()
			local ok, message = ToOwnModel(race, gender, index)
			if not ok then
				return ok, message
			end
			if npc then
				-- Start from the NPC's face, skin and hair.
				M.SetOwnLook({ npc[2], npc[3], npc[4], npc[5], npc[6] })
			end
			ok, message = M.StepOwnLook(f, step)
			if ok and npc then
				message = "Your own model now, with that NPC's face, skin and hair, so your gear shows. " .. message
			end
			return ok, message
		end)
	end
	if table.getn(list) == 0 then
		return WearLook(race, gender, nil)
	end
	if not index then
		-- From your own look, start at the plainest NPC look of this race.
		if OwnLookMode(race, gender) then
			return WearLook(race, gender, 1, "The plainest " .. M.DescribeBody(race, gender)
				.. " NPC. NPC look < > goes through the others; the rows above take you back to your model.")
		end
		return WearLook(race, gender, 1, "Your own face can't be changed bit by bit, so this is the plainest "
			.. M.DescribeBody(race, gender) .. " NPC. Now use the < > rows.")
	end
	local k, pos, n, changed = M.StepLook(race, gender, f, index, step)
	if not k then
		return SetStatus(false, "Every " .. M.DescribeBody(race, gender) .. " NPC has the same " .. strlower(FeatureName(f, gender)) .. ".")
	end
	local message = FeatureName(f, gender) .. " " .. pos .. " of " .. n .. "."
	-- Each NPC wears its own clothes, so the outfit nearly always changes with
	-- a face or hair row; only the other face and hair rows are worth naming.
	local names = {}
	for i = 1, table.getn(changed) do
		if f == 6 or changed[i] ~= 6 then
			table.insert(names, strlower(FeatureName(changed[i], gender)))
		end
	end
	if table.getn(names) > 0 then
		local joined = names[1]
		if table.getn(names) > 1 then
			joined = table.concat(names, ", ", 1, table.getn(names) - 1) .. " and " .. names[table.getn(names)]
		end
		message = message .. " No NPC has it with your other choices, so the " .. joined .. " changed too."
	end
	WearLook(race, gender, k, message)
end

local function BuildRacesPage(page)
	Label(page, "Races and looks", "GameFontNormal", 10, -10)
	ui.nativeLabel = Label(page, "", "GameFontDisableSmall", 130, -12, "DmorphOctoNativeLabel")
	for race = 1, table.getn(M.RACES) do
		for gender = 0, 1 do
			local button = CreateFrame("Button", "DmorphOctoRace" .. race .. GenderName(gender), page)
			button:SetWidth(36)
			button:SetHeight(36)
			-- Spread over the page's width.
			local gap = math.floor((PAGE_W - 28 - 36) / (table.getn(M.RACES) - 1))
			button:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + (race - 1) * gap, -30 - gender * 40)
			RaceIcon(button, race, gender)
			button:SetScript("OnClick", function()
				local c = ui.creator
				c.race, c.gender, c.index = this.race, this.gender, nil
				Morph(M.SetRace, this.race, this.gender)
			end)
			button:SetScript("OnEnter", function()
				local after = "Then the < > rows go through the game's " .. M.DescribeBody(this.race, this.gender) .. " NPC looks."
				if OwnLookMode(this.race, this.gender) then
					after = "Then the < > rows change its skin colour, face and hair."
				end
				Tooltip(this, M.DescribeBody(this.race, this.gender), "Click: this race with your own face, skin and hair.", after)
			end)
			button:SetScript("OnLeave", HideTooltip)
			table.insert(ui.raceButtons, button)
		end
	end
	ui.creatorTitle = Label(page, "", "GameFontHighlight", 14, -114, "DmorphOctoCreatorTitle")
	for f = 1, 6 do
		local y = -136 - (f - 1) * 26
		local row = {}
		row.label = Label(page, M.LOOK_FEATURES[f], "GameFontNormal", 20, y - 4)
		Button(page, "<", 26, 190, y, function()
			StepFeature(this.feature, -1)
		end, "DmorphOctoCreatorPrev" .. f).feature = f
		row.value = Font(page:CreateFontString("DmorphOctoCreatorValue" .. f, "OVERLAY", "GameFontHighlight"), 12)
		row.value:SetPoint("TOP", page, "TOPLEFT", 320, y - 4)
		Button(page, ">", 26, 424, y, function()
			StepFeature(this.feature, 1)
		end, "DmorphOctoCreatorNext" .. f).feature = f
		ui.creatorRows[f] = row
	end

	local dice = CreateFrame("Button", "DmorphOctoCreatorRandom", page)
	dice:SetWidth(28)
	dice:SetHeight(28)
	dice:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -296)
	dice:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
	dice:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down")
	dice:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight")
	dice:SetScript("OnClick", function()
		local race, gender, index = RaceTarget()
		if OwnLookMode(race, gender) then
			ui.creator.index = nil
			return Morph(function()
				local ok, message = ToOwnModel(race, gender, index)
				if not ok then
					return ok, message
				end
				return M.RandomOwnLook()
			end)
		end
		local count = table.getn(M.GetLooks(race, gender))
		if count == 0 then
			return WearLook(race, gender, nil)
		end
		local pick = math.random(count)
		if count > 1 and pick == index then
			pick = Wrap(pick, 1, count)
		end
		WearLook(race, gender, pick)
	end)
	dice:SetScript("OnEnter", function()
		local race, gender = RaceTarget()
		if OwnLookMode(race, gender) then
			Tooltip(this, "Random look", "Any skin colour, face and hair this race can have, on your model.")
		else
			Tooltip(this, "Random look", "Any NPC face, skin, hair and outfit of this race.")
		end
	end)
	dice:SetScript("OnLeave", HideTooltip)
	Button(page, "My own look", 100, 48, -299, function()
		local race, gender = RaceTarget()
		ui.creator.index = nil
		Morph(function()
			local ok, message = M.SetRace(race, gender)
			if ok and M.HasHelper() then
				local _, _, _, _, picked = M.GetLookState()
				if picked then
					return M.ResetOwnLook()
				end
			end
			return ok, message
		end)
	end, "DmorphOctoOwnLook")
	Button(page, "Swap gender", 100, 152, -299, function()
		local race, gender, index = RaceTarget()
		if index then
			-- From an NPC look, the other gender's plainest look.
			return WearLook(race, 1 - gender, 1)
		end
		Morph(M.ToggleGender)
	end)
	local star = Button(page, "Favourite", 92, PAGE_W - 102, -299, function()
		local race, gender, index = RaceTarget()
		local look = index and M.GetLooks(race, gender)[index]
		if not look then
			return SetStatus(false, "Pick an NPC look first: your own look is always one portrait away.")
		end
		SetStatus(M.ToggleFavourite(look[1]))
	end, "DmorphOctoCreatorFavourite")
	star:SetScript("OnEnter", function()
		Tooltip(this, "Favourite this look", "Adds the NPC look you wear to the Favourites tab.")
	end)
	star:SetScript("OnLeave", HideTooltip)
	Label(page, "Portraits keep your own face, skin and hair, and your item morphs show.", "GameFontDisableSmall", 14, -340)
	ui.racesHint = Label(page, "", "GameFontDisableSmall", 14, -354, "DmorphOctoRacesHint")
end

-- Mounts tab -------------------------------------------------------------------------

-- Pick a skin for your mount: any model, shown only while you ride, so you
-- mount and dismount as usual. "Skin for" picks all your mounts or one you've
-- ridden on this character.

-- Mounts only, but for "All models" (any model can be a skin). OctoWoW's and
-- the ported ones were every model of their kind, so the Mounts tab listed
-- all 6,399 ported models like the Models tab (user, 17 Oct). Saved by index.
local MOUNT_FILTERS = {
	{ text = "Mount models", tag = "mount" },
	{ text = "All models" },
	{ text = "OctoWoW's new mounts", tag = "mount", kinds = { [2] = true, [3] = true } },
	-- Models from later expansions (Data/Ported.lua), only on the PC that has them.
	{ text = "Ported mounts", tag = "mount", kinds = { [4] = true } },
}

local function MountName(displayID)
	return M.GetDisplayName(displayID) or ("Mount " .. displayID)
end

-- The skin you picked last for the "Skin for" choice: the one on, or the one
-- a click waiting at the gate is putting on.
local function MountPick()
	local pick = ui.mountPick
	if pick and pick.target == ui.mountFor then
		return pick.id
	end
	return M.GetMountSkin(ui.mountFor)
end

-- The position of a display ID in the filtered mount list, or nil.
local function MountPosition(displayID)
	if not (displayID and ui.mountResult) then
		return nil
	end
	local catalog = M.GetCreatureCatalog()
	for index = 1, ui.mountTotal or 0 do
		if catalog.ids[ui.mountResult[index]] == displayID then
			return index
		end
	end
end

-- Scrolls the skin you have on into view (about the middle of the list).
local function ShowMountPick()
	local pos = MountPosition(MountPick())
	if pos then
		ui.mountList.Show(pos)
	else
		ui.mountList.Refresh()
	end
end

local function PickMount(displayID)
	ui.mountPick = { target = ui.mountFor, id = displayID }
	Morph(M.SetMountSkin, displayID, ui.mountFor)
end

local function RefreshMountState()
	local riding, real, skin = M.GetMountState()
	local target = ui.mountFor and MountName(ui.mountFor) or "All my mounts"
	ui.mountForButton:SetText(target)
	if riding and skin then
		ui.mountState:SetText("You're riding |cffffffff" .. MountName(real) .. "|r, shown as |cffffd100" .. MountName(skin) .. "|r.")
	elseif riding then
		ui.mountState:SetText("You're riding |cffffffff" .. MountName(real) .. "|r, with no skin on it.")
	else
		ui.mountState:SetText("Not riding. The skin goes on when you mount and comes off when you dismount.")
	end
	local chosen = MountPick()
	if chosen then
		P.BoxShowModel(ui.mountBox, chosen, MountName(chosen), C.gold, "Display ID " .. chosen .. " - for " .. target)
	else
		P.BoxShowModel(ui.mountBox, nil, "No skin", C.dim, "Your mount looks as usual.")
	end
end

local function FilterMounts(keep)
	local prefs = Prefs()
	local count
	ui.mountResult, count = M.FilterCatalog(M.GetCreatureCatalog(), ui.mountSearch:GetText(),
		MOUNT_FILTERS[prefs.mountFilter or 1], nil, prefs.sortMounts)
	ui.mountTotal = count
	ui.mountCount:SetText(Count(count, "model"))
	ui.mountList.SetCount(count, keep)
	if not keep then
		ShowMountPick()
	end
	RefreshMountState()
end

local function RefreshMounts()
	ui.mountList.Refresh()
	RefreshMountState()
end

-- The next (step 1) or previous (-1) model in the list as your skin.
local function StepMount(step)
	local count = ui.mountTotal or 0
	if count == 0 then
		return SetStatus(false, "No models in the list: clear the search or pick another filter.")
	end
	local pos = MountPosition(MountPick())
	if pos then
		pos = Wrap(pos, step, count)
	elseif step > 0 then
		pos = 1
	else
		pos = count
	end
	PickMount(M.GetCreatureCatalog().ids[ui.mountResult[pos]])
	ShowMountPick()
	RefreshMountState()
end

local function MountForMenu()
	local options = { { text = "All my mounts", checked = ui.mountFor == nil } }
	local ridden = M.GetRiddenMounts()
	if table.getn(ridden) > 0 then
		table.insert(options, { text = "Mounts you've ridden", header = true })
	end
	for i = 1, table.getn(ridden) do
		local skin = M.GetMountSkin(ridden[i])
		local text = MountName(ridden[i])
		if skin then
			text = text .. " *"
		end
		table.insert(options, { text = text, real = ridden[i], checked = ui.mountFor == ridden[i] })
	end
	OpenMenu(this, options, function(option)
		ui.mountFor = option.real
		ShowMountPick()
		RefreshMountState()
	end)
end

local function MountFilterMenu()
	local prefs, options = Prefs(), {}
	for i = 1, table.getn(MOUNT_FILTERS) do
		table.insert(options, { text = MOUNT_FILTERS[i].text, index = i, checked = (prefs.mountFilter or 1) == i })
	end
	OpenMenu(this, options, function(option)
		Prefs().mountFilter = option.index
		ui.mountFilter:SetText(option.text)
		FilterMounts()
	end)
end

local function BuildMountsPage(page)
	local prefs = Prefs()
	if not MOUNT_FILTERS[prefs.mountFilter] then
		prefs.mountFilter = 1
	end
	Label(page, "Skin for", "GameFontNormal", 10, -12)
	ui.mountForButton = Button(page, "All my mounts", 200, 70, -7, MountForMenu, "DmorphOctoMountFor")
	ui.mountForButton:SetScript("OnEnter", function()
		Tooltip(this, "Which mount gets the skin", "All your mounts, or one you've ridden on this character.",
			"Ride a mount once and it appears in this menu.")
	end)
	ui.mountForButton:SetScript("OnLeave", HideTooltip)
	Button(page, "Remove skin", 110, 276, -7, function()
		ui.mountPick = { target = ui.mountFor }
		Morph(M.SetMountSkin, 0, ui.mountFor)
	end, "DmorphOctoMountReset")
	ui.mountState = Label(page, "", "GameFontHighlightSmall", 10, -36, "DmorphOctoMountState")
	ui.mountState:SetWidth(PAGE_W - 20)

	Label(page, "Search", "GameFontNormalSmall", 10, -62)
	ui.mountSearch = EditBox(page, "DmorphOctoMountSearch", 150, 52, -58)
	ui.mountSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterMounts)
	end)
	ui.mountSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterMounts()
	end)
	ui.mountFilter = Button(page, MOUNT_FILTERS[prefs.mountFilter].text, 150, 210, -57, MountFilterMenu, "DmorphOctoMountFilter")
	SortButton(page, "DmorphOctoMountSort", PAGE_W - 92 - 8, -57, "sortMounts", FilterMounts)

	ui.mountList = List(page, "DmorphOctoMountList", 8, -84, 44, function(row, index)
		local catalog = M.GetCreatureCatalog()
		local i = ui.mountResult[index]
		local color = KindColor(catalog.kind[i])
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(color[1], color[2], color[3])
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == MountPick() then
			-- The skin you have on: ticked, lit and gold.
			row:LockHighlight()
			row.tick:Show()
			row.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		end
		if M.IsFavourite(catalog.ids[i], true) then
			row.star:Show()
		end
	end, function(index, button)
		local displayID = M.GetCreatureCatalog().ids[ui.mountResult[index]]
		if button == "RightButton" then
			SetStatus(M.ToggleFavourite(displayID, true))
			ui.mountList.Refresh()
		else
			PickMount(displayID)
			RefreshMounts()
		end
	end, function(index)
		local catalog = M.GetCreatureCatalog()
		local i = ui.mountResult[index]
		if i then
			P.BoxShowModel(ui.mountBox, catalog.ids[i], catalog.names[i], KindColor(catalog.kind[i]),
				"Display ID " .. catalog.ids[i] .. " - click to use it")
		end
	end, LIST_W, 14)
	ui.mountList.leave = RefreshMountState
	ui.mountBox = P.NewBox(page, "Mounts", "model", -84, 14, "Your skin", StepMount)
	ui.mountCount = Label(page, "", "GameFontDisableSmall", 10, -346, "DmorphOctoMountCount")
	Label(page, "Click: use it as the skin. Right-click: star it. Previous / Next: the one above or below.",
		"GameFontDisableSmall", 10, -362)
end

-- Glows tab ---------------------------------------------------------------------------

-- A weapon's enchant glow: any glow the client can draw (Data/Glows.lua), on
-- the main hand, off hand or ranged slot. Needs DmorphHelper.dll.

local glowSlot = 16

local function FilterGlows(keep)
	local count
	ui.glowResult, count = M.FilterGlows(ui.glowSearch:GetText())
	ui.glowCount:SetText(Count(count, "glow"))
	ui.glowList.SetCount(count, keep)
end

local function RefreshGlows()
	for slot, button in pairs(ui.glowSlots) do
		if slot == glowSlot then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	local picked, real = M.GetGlow(glowSlot)
	local text = "your own"
	if picked then
		text = M.DescribeGlow(picked)
	elseif real and real > 0 then
		text = "your own (" .. M.DescribeGlow(real) .. ")"
	end
	ui.glowState:SetText(M.SLOT_NAMES[glowSlot] .. ": " .. text)
	if M.HasHelper() then
		ui.glowState:SetTextColor(1, 1, 1)
	else
		ui.glowState:SetText("DmorphHelper.dll isn't loaded, so glows can't show: see /dmorph status.")
		ui.glowState:SetTextColor(1, 0.4, 0.4)
	end
	if M.GetGlows().count == 0 then
		ui.glowEmpty:Show()
	else
		ui.glowEmpty:Hide()
	end
	ui.glowList.Refresh()
	ui.glowList.leave()
end

local function GlowTooltip(index, row)
	local all = M.GetGlows()
	local i = ui.glowResult[index]
	if not i then
		return
	end
	P.BoxText(ui.glowBox, all.name[i], C.accent, "Showing on you - click to keep it")
	-- The glow goes on your character for a look (a preview model can't draw
	-- enchants); it stays until another row, a click, or leaving the tab.
	M.PreviewGlow(glowSlot, all.enchant[i])
	Debounce(ui.glowTimer, 0.7, P.ReloadGlowBox)
	-- On the left, off the preview box.
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:SetText(all.name[i])
	local shown = 0
	for name in string.gfind(all.names[i], "[^;]+") do
		shown = shown + 1
		if shown > 8 then
			GameTooltip:AddLine("...", 0.8, 0.8, 0.8)
			break
		end
		local _, _, trimmed = strfind(name, "^%s*(.-)%s*$")
		GameTooltip:AddLine(trimmed, 1, 1, 1)
	end
	if all.models[i] ~= "" then
		GameTooltip:AddLine("Effect: " .. all.models[i], 0.8, 0.8, 0.8)
	end
	if all.ported[i] then
		GameTooltip:AddLine("From a later expansion: needs the ported pack to show.", 0.75, 0.55, 1)
	end
	GameTooltip:AddLine("Glow " .. all.visual[i] .. ", shown with enchant " .. all.enchant[i] .. ".", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Click: on your " .. strlower(M.SLOT_NAMES[glowSlot]) .. ".", 0.6, 1, 0.6)
	GameTooltip:Show()
end

-- The glow on the picked slot, in the box (a preview model can't draw an
-- enchant, so the box shows you and names it; the glow is on the stage).
-- The glow box's model again from your character (with the glow now on it),
-- and the dressing room too.
function P.ReloadGlowBox()
	local box = ui.glowBox
	box.model:SetFrameLevel(box.base + 1)
	box.model:SetUnit("player")
	box.wait, box.loaded, box.dressed = REVEAL, true, nil
	RequestPreview()
end

-- Takes hovered glows off (leaving the tab, closing the window, a click).
function P.EndGlowPreview()
	for i = 1, table.getn(M.GLOW_SLOTS) do
		M.PreviewGlow(M.GLOW_SLOTS[i], nil)
	end
end

function P.RefreshGlowBox()
	local picked = M.GetGlow(glowSlot)
	local where = "on your " .. strlower(M.SLOT_NAMES[glowSlot]) .. " - see it on the left"
	if picked then
		P.BoxShowItems(ui.glowBox, nil, M.DescribeGlow(picked), C.accent, where)
	else
		P.BoxShowItems(ui.glowBox, nil, "Your own glow", C.dim, where)
	end
end

function P.StepGlow(step)
	local all = M.GetGlows()
	local n = table.getn(ui.glowResult or {})
	local pos = P.StepPosition(P.FindPosition(ui.glowResult, n, all.enchant, M.GetGlow(glowSlot)), step, n)
	if not pos then
		return SetStatus(false, "No glows in the list.")
	end
	Morph(M.SetGlow, glowSlot, all.enchant[ui.glowResult[pos]])
	ui.glowList.Show(pos)
end

local function BuildGlowsPage(page)
	Label(page, "Weapon glows", "GameFontNormal", 10, -12)
	for i = 1, table.getn(M.GLOW_SLOTS) do
		local slot = M.GLOW_SLOTS[i]
		local button = Button(page, M.SLOT_NAMES[slot], 96, 150 + (i - 1) * 100, -7, function()
			P.EndGlowPreview()
			glowSlot = this.slot
			RefreshGlows()
		end, "DmorphOctoGlowSlot" .. slot)
		button.slot = slot
		ui.glowSlots[slot] = button
	end
	Label(page, "Search", "GameFontNormalSmall", 10, -40)
	ui.glowSearch = EditBox(page, "DmorphOctoGlowSearch", 150, 52, -36)
	ui.glowSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterGlows)
	end)
	ui.glowSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterGlows()
	end)
	ui.glowCount = Label(page, "", "GameFontDisableSmall", 212, -40, "DmorphOctoGlowCount")

	ui.glowList = List(page, "DmorphOctoGlowList", 8, -62, 70, function(row, index)
		local all = M.GetGlows()
		local i = ui.glowResult[index]
		row.text:SetText(all.name[i])
		if all.ported[i] then
			row.info:SetText("TBC-MoP")
		else
			row.info:SetText("glow " .. all.visual[i])
		end
		if M.GetGlow(glowSlot) == all.enchant[i] then
			row:LockHighlight()
			row.tick:Show()
			row.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
		end
	end, function(index)
		local all = M.GetGlows()
		Morph(M.SetGlow, glowSlot, all.enchant[ui.glowResult[index]])
	end, GlowTooltip, LIST_W, 14)
	ui.glowList.leave = P.RefreshGlowBox
	ui.glowBox = P.NewBox(page, "Glows", "dress", -62, 14, "Glow", P.StepGlow)
	ui.glowEmpty = Label(page, "No glow list yet. Close the game, run tools\\update_from_game.ps1 from the "
		.. "DmorphOcto folder (it reads every glow from the game files), and start the game again.",
		"GameFontDisableSmall", 14, -72, "DmorphOctoGlowEmpty")
	ui.glowEmpty:SetWidth(LIST_W - 12)

	ui.glowState = Label(page, "", "GameFontHighlightSmall", 10, -324, "DmorphOctoGlowState")
	Button(page, "No glow", 90, 8, -346, function()
		Morph(M.SetGlow, glowSlot, 0)
	end, "DmorphOctoGlowNone")
	Button(page, "My own glow", 110, 102, -346, function()
		Morph(M.SetGlow, glowSlot, nil)
	end, "DmorphOctoGlowOwn")
	Label(page, "DMorph users (2.23+) see it too.", "GameFontDisableSmall", 222, -351)
end

-- Items tab -------------------------------------------------------------------------

-- The three filter buttons of the Items and Sets tabs: the kind (cloth,
-- plate, dagger, ...), the quality and where the item comes from.
local function TypeText(kind)
	return kind and M.ITEM_TYPE_NAMES[kind] or "Any type"
end

local function QualityText(quality)
	if quality > 1 then
		return M.QUALITY_FILTERS[quality].text
	end
	return "Any quality"
end

-- The kinds a catalogue has, with how many of each.
local function TypeMenu(anchor, catalog, current, pick)
	local options = { { text = "Any type", checked = not current } }
	local kinds = M.GetCatalogTypes(catalog)
	for i = 1, table.getn(kinds) do
		local k = kinds[i]
		table.insert(options, { text = k[2] .. " (" .. Commas(k[3]) .. ")", kind = k[1], checked = current == k[1] })
	end
	OpenMenu(anchor, options, function(option)
		pick(option.kind)
	end)
end

local function QualityMenu(anchor, key, done)
	local options = {}
	for i = 1, table.getn(M.QUALITY_FILTERS) do
		table.insert(options, { text = M.QUALITY_FILTERS[i].text, quality = i, checked = Prefs()[key] == i })
	end
	OpenMenu(anchor, options, function(option)
		Prefs()[key] = option.quality
		done()
	end)
end

local function SourceMenu(anchor, filters, key, done)
	local options = {}
	for i = 1, table.getn(filters) do
		table.insert(options, { text = filters[i].text, source = i, checked = Prefs()[key] == i })
	end
	OpenMenu(anchor, options, function(option)
		Prefs()[key] = option.source
		done()
	end)
end

local function FilterItems(keep)
	local prefs = Prefs()
	local count
	local kind = prefs.itemTypes[itemSlot]
	ui.itemResult, count = M.FilterCatalog(M.GetItemCatalog(itemSlot), ui.itemSearch:GetText(),
		M.ITEM_FILTERS[prefs.itemFilter], M.QUALITY_FILTERS[prefs.itemQuality].quality, prefs.sortItems, kind)
	ui.itemTypeButton:SetText(TypeText(kind))
	ui.itemQualityButton:SetText(QualityText(prefs.itemQuality))
	ui.itemSourceButton:SetText(M.ITEM_FILTERS[prefs.itemFilter].text)
	ui.itemSlotLabel:SetText(M.SLOT_NAMES[itemSlot])
	if itemSlot == 16 or itemSlot == 17 then
		local style = M.GetWeaponStyle(itemSlot)
		for i = 1, table.getn(M.WEAPON_STYLES) do
			if M.WEAPON_STYLES[i].key == style then
				ui.itemHoldButton:SetText(M.WEAPON_STYLES[i].text)
			end
		end
		ui.itemHoldButton:Show()
		local sheath = M.GetWeaponSheath(itemSlot)
		for i = 1, table.getn(M.WEAPON_SHEATHS) do
			if M.WEAPON_SHEATHS[i].key == sheath then
				ui.itemSheathButton:SetText(M.WEAPON_SHEATHS[i].text)
			end
		end
		ui.itemSheathButton:Show()
	else
		ui.itemHoldButton:Hide()
		ui.itemSheathButton:Hide()
	end
	local note = Count(count, "item")
	if itemSlot >= 16 and itemSlot <= 18 then
		note = note .. ", NPC weapons included"
	end
	ui.itemCount:SetText(note)
	local _, empty = GetInventorySlotInfo(SLOT_KEYS[itemSlot])
	ui.itemSlotIcon:SetTexture(empty)
	ui.itemList.SetCount(count, keep)
end

local function RefreshItems()
	ui.itemList.Refresh()
	ui.itemList.leave()
end

local function ShowItemSlot(slot)
	itemSlot = slot
	ui.itemBox:SetText(M.GetState().items[slot] or "")
	ShowTab("items")
end

local function CycleSlot(step)
	local order = M.SLOT_ORDER
	local count = table.getn(order)
	for i = 1, count do
		if order[i] == itemSlot then
			ShowItemSlot(order[Wrap(i, step, count)])
			return
		end
	end
end

local function SlotMenu()
	local options = {}
	for i = 1, table.getn(M.SLOT_ORDER) do
		local slot = M.SLOT_ORDER[i]
		table.insert(options, { text = M.SLOT_NAMES[slot], slot = slot, checked = slot == itemSlot })
	end
	OpenMenu(this, options, function(option)
		ShowItemSlot(option.slot)
	end)
end

-- One item on you in a box (kind "dress"): its name, and a line about it.
function P.ShowItemIn(box, itemID, slot, info)
	if itemID == 0 then
		P.BoxShowItems(box, nil, "Invisible", C.accent, info or (M.SLOT_NAMES[slot] .. " shows nothing"))
		return
	end
	local catalog = M.GetItemCatalog(slot)
	local index = catalog.byID and catalog.byID[itemID]
	local r, g, b = QualityColor(index and catalog.quality[index])
	-- The plain name (DescribeItem gives "[name] (id)", the id is on the line below).
	local name = index and catalog.names[index] or M.DescribeItem(itemID, slot)
	P.BoxShowItems(box, { itemID }, name, { r, g, b }, info or ("Item " .. itemID))
end

-- The slot's item you have on, else your own gear.
function P.RefreshItemBox()
	local worn = M.GetState().items[itemSlot]
	if worn then
		P.ShowItemIn(ui.itemPreview, worn, itemSlot, (worn == 0 and "Shows nothing" or ("Item " .. worn)) .. " - you have it on")
	else
		P.BoxShowItems(ui.itemPreview, nil, "Your own gear", C.dim, "Hover an item to try it on.")
	end
end

function P.StepItem(step)
	local catalog = M.GetItemCatalog(itemSlot)
	local pos = P.FindPosition(ui.itemResult, ui.itemList.count, catalog.ids, M.GetState().items[itemSlot])
	pos = P.StepPosition(pos, step, ui.itemList.count)
	if not pos then
		return SetStatus(false, "No items in the list: clear the search or pick other filters.")
	end
	local itemID = catalog.ids[ui.itemResult[pos]]
	ui.itemBox:SetText(itemID)
	Morph(M.SetItem, itemSlot, itemID)
	ui.itemList.Show(pos)
end

local function BuildItemsPage(page)
	local prefs = Prefs()
	-- The slot: click it for a menu of every slot.
	local slotButton = CreateFrame("Button", "DmorphOctoItemSlotButton", page)
	slotButton:SetWidth(230)
	slotButton:SetHeight(30)
	slotButton:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -4)
	Hover(slotButton)
	slotButton:SetScript("OnClick", SlotMenu)
	slotButton:SetScript("OnEnter", function()
		Tooltip(this, "Slot", "Click to pick another slot.")
	end)
	slotButton:SetScript("OnLeave", HideTooltip)
	ui.itemSlotIcon = slotButton:CreateTexture(nil, "ARTWORK")
	ui.itemSlotIcon:SetWidth(26)
	ui.itemSlotIcon:SetHeight(26)
	ui.itemSlotIcon:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 2, -2)
	ui.itemSlotLabel = Label(slotButton, "", "GameFontNormal", 34, -3, "DmorphOctoItemSlotLabel")
	ui.itemCount = Label(slotButton, "", "GameFontDisableSmall", 34, -18, "DmorphOctoItemCount")
	ui.itemLookup = Label(page, "", "GameFontDisableSmall", 244, -24, "DmorphOctoItemLookup")
	-- Hold as (main and off hand only): one-hand at your side, two-hand on your back.
	ui.itemHoldButton = Button(page, "Hold: as it is", 112, PAGE_W - 178, -8, function()
		local styles, now = M.WEAPON_STYLES, M.GetWeaponStyle(itemSlot)
		local nextKey
		for i = 1, table.getn(styles) do
			if styles[i].key == now then
				nextKey = styles[math.mod(i, table.getn(styles)) + 1].key
			end
		end
		Morph(M.SetWeaponStyle, itemSlot, nextKey)
		FilterItems(true)
	end, "DmorphOctoItemHold")
	ui.itemHoldButton:SetScript("OnEnter", function()
		Tooltip(this, "Hold as", "Click: as the weapon is, one-hand (sheathed at your side) or two-hand (on your back).",
			"The sheathe follows it unless Sheathe picks one. Needs DmorphHelper; DMorph users (2.28+) see it too.")
	end)
	ui.itemHoldButton:SetScript("OnLeave", HideTooltip)
	-- Sheathe on (2.28.0): your back or your side, whatever the stance.
	ui.itemSheathButton = Button(page, "Sheathe: as it is", 120, 262, -39, function()
		local ways, now = M.WEAPON_SHEATHS, M.GetWeaponSheath(itemSlot)
		local nextKey
		for i = 1, table.getn(ways) do
			if ways[i].key == now then
				nextKey = ways[math.mod(i, table.getn(ways)) + 1].key
			end
		end
		Morph(M.SetWeaponSheath, itemSlot, nextKey)
		FilterItems(true)
	end, "DmorphOctoItemSheath")
	ui.itemSheathButton:SetScript("OnEnter", function()
		Tooltip(this, "Sheathe on", "Click: as the weapon is, on your back or at your side.",
			"DMorph users (2.28+) with DmorphHelper v17 see it too.")
	end)
	ui.itemSheathButton:SetScript("OnLeave", HideTooltip)
	Button(page, "<", 24, PAGE_W - 60, -8, function()
		CycleSlot(-1)
	end)
	Button(page, ">", 24, PAGE_W - 32, -8, function()
		CycleSlot(1)
	end)

	Label(page, "Search", "GameFontNormalSmall", 10, -44)
	ui.itemSearch = EditBox(page, "DmorphOctoItemSearch", 200, 52, -40)
	ui.itemSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterItems)
	end)
	ui.itemSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterItems()
	end)
	SortButton(page, "DmorphOctoItemSort", PAGE_W - 92 - 8, -39, "sortItems", FilterItems)

	-- Type, quality, source: e.g. Cloth + Epic for every epic cloth helmet.
	ui.itemTypeButton = Button(page, "Any type", 170, 8, -66, function()
		TypeMenu(this, M.GetItemCatalog(itemSlot), Prefs().itemTypes[itemSlot], function(kind)
			Prefs().itemTypes[itemSlot] = kind
			FilterItems()
		end)
	end, "DmorphOctoItemType")
	ui.itemTypeButton:SetScript("OnEnter", function()
		Tooltip(this, "Type", "Cloth, leather, mail or plate; or the kind of weapon.",
			"Only the types this slot has are listed, with how many of each.")
	end)
	ui.itemTypeButton:SetScript("OnLeave", HideTooltip)
	ui.itemQualityButton = Button(page, "Any quality", 170, 190, -66, function()
		QualityMenu(this, "itemQuality", FilterItems)
	end, "DmorphOctoItemQuality")
	ui.itemSourceButton = Button(page, "All items", 170, 372, -66, function()
		SourceMenu(this, M.ITEM_FILTERS, "itemFilter", FilterItems)
	end, "DmorphOctoItemSource")
	ui.itemSourceButton:SetScript("OnEnter", function()
		Tooltip(this, "Which items", "All, 1.12's own, or the ones Turtle WoW and OctoWoW added.")
	end)
	ui.itemSourceButton:SetScript("OnLeave", HideTooltip)

	ui.itemList = List(page, "DmorphOctoItemList", 8, -94, 52, function(row, index)
		local catalog = M.GetItemCatalog(itemSlot)
		local i = ui.itemResult[index]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(QualityColor(catalog.quality[i]))
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == M.GetState().items[itemSlot] then
			row:LockHighlight()
			row.tick:Show()
		end
	end, function(index)
		local itemID = M.GetItemCatalog(itemSlot).ids[ui.itemResult[index]]
		ui.itemBox:SetText(itemID)
		Morph(M.SetItem, itemSlot, itemID)
	end, function(index)
		-- Hover: your character wearing it, without putting it on.
		local catalog = M.GetItemCatalog(itemSlot)
		local i = ui.itemResult[index]
		if i then
			local r, g, b = QualityColor(catalog.quality[i])
			P.BoxShowItems(ui.itemPreview, { catalog.ids[i] }, catalog.names[i], { r, g, b },
				"Item " .. catalog.ids[i] .. " - click to wear it")
		end
	end, LIST_W, 13)
	ui.itemList.leave = P.RefreshItemBox
	ui.itemPreview = P.NewBox(page, "Items", "dress", -94, 13, "Try on", P.StepItem)

	local y = -346
	Label(page, "Item ID", "GameFontNormalSmall", 10, y - 5)
	ui.itemBox = EditBox(page, "DmorphOctoItemID", 70, 56, y, 9)
	local function Apply()
		ui.itemBox:ClearFocus()
		Morph(M.SetItem, itemSlot, M.ParseID(ui.itemBox:GetText()) or -1)
	end
	ui.itemBox:SetScript("OnEnterPressed", Apply)
	Button(page, "Apply", 64, 132, y, Apply)
	Button(page, "Use my own gear", 124, 202, y, function()
		ui.itemBox:SetText("")
		Morph(M.SetItem, itemSlot, 0)
	end)
	-- Nothing in this slot: the piece is invisible (armour slots only).
	ui.itemHideButton = Button(page, "Invisible", 90, 332, y, function()
		ui.itemBox:SetText("")
		Morph(M.HideItem, itemSlot)
	end, "DmorphOctoItemHide")
	ui.itemHideButton:SetScript("OnEnter", function()
		Tooltip(this, "Invisible", "Shows nothing in this slot: no piece and none of your own gear.",
			"Use my own gear brings yours back.")
	end)
	ui.itemHideButton:SetScript("OnLeave", HideTooltip)
end

-- Slutmog tab (user, 18 Oct: "its own tab"): every revealing piece and OctoWoW's
-- invisible Unseen Fashion items, all slots in one list; buttons narrow it to a slot.
local SLUTMOG_SHOW = {
	{ text = "All" }, { text = "Chest", slot = 5 }, { text = "Shirt", slot = 4 },
	{ text = "Legs", slot = 7 }, { text = "Feet", slot = 8 }, { text = "Unseen", unseen = true },
}
local slutmogShow = 1

local function FilterSlutmog(keep)
	local catalog = M.GetSlutmogCatalog()
	local found, n = M.FilterCatalog(catalog, ui.slutSearch:GetText())
	local show = SLUTMOG_SHOW[slutmogShow]
	local result, m = {}, 0
	for k = 1, n do
		local i = found[k]
		if (not show.slot or catalog.slots[i] == show.slot)
			and (not show.unseen or strfind(catalog.lower[i], "unseen fashion", 1, true)) then
			m = m + 1
			result[m] = i
		end
	end
	ui.slutResult = result
	for i = 1, table.getn(SLUTMOG_SHOW) do
		if i == slutmogShow then
			ui.slutButtons[i]:LockHighlight()
		else
			ui.slutButtons[i]:UnlockHighlight()
		end
	end
	local note = Count(m, "piece")
	if show.unseen and m == 0 then
		note = "none yet: OctoWoW's Unseen Fashion items show once the server has sent them"
	end
	ui.slutCount:SetText(note)
	ui.slutList.SetCount(m, keep)
end

local function RefreshSlutmog()
	ui.slutList.Refresh()
	ui.slutList.leave()
end

-- The piece of the list you have on: the one stepped to or clicked last if
-- still on, else the first one on.
function P.WornSlutmog()
	local catalog, items = M.GetSlutmogCatalog(), M.GetState().items
	local result, n = ui.slutResult or {}, ui.slutList.count
	local function Worn(k)
		local i = result[k]
		return i and items[catalog.slots[i]] == catalog.ids[i]
	end
	if ui.slutPos and Worn(ui.slutPos) then
		return ui.slutPos
	end
	for k = 1, n do
		if Worn(k) then
			return k
		end
	end
end

function P.ShowSlutmog(k, info)
	local catalog = M.GetSlutmogCatalog()
	local i = ui.slutResult[k]
	local r, g, b = QualityColor(catalog.quality[i])
	P.BoxShowItems(ui.slutBox, { catalog.ids[i] }, catalog.names[i], { r, g, b },
		M.SLOT_NAMES[catalog.slots[i]] .. ", item " .. catalog.ids[i] .. info)
end

function P.RefreshSlutBox()
	local k = P.WornSlutmog()
	if k then
		P.ShowSlutmog(k, " - you have it on")
	else
		P.BoxShowItems(ui.slutBox, nil, "Your look", C.dim, "Hover a piece to try it on.")
	end
end

function P.WearSlutmog(k)
	local catalog = M.GetSlutmogCatalog()
	local i = ui.slutResult[k]
	ui.slutPos = k
	Morph(M.SetItem, catalog.slots[i], catalog.ids[i])
end

function P.StepSlutmog(step)
	local pos = P.StepPosition(P.WornSlutmog() or ui.slutPos, step, ui.slutList.count)
	if not pos then
		return SetStatus(false, "No pieces in the list: clear the search or pick another slot.")
	end
	P.WearSlutmog(pos)
	ui.slutList.Show(pos)
end

local function BuildSlutmogPage(page)
	ui.slutButtons = {}
	for i = 1, table.getn(SLUTMOG_SHOW) do
		local index = i
		ui.slutButtons[i] = Button(page, SLUTMOG_SHOW[i].text, 84, 8 + (i - 1) * 88, -8, function()
			slutmogShow = index
			FilterSlutmog()
		end, "DmorphOctoSlutmogShow" .. i)
	end
	Label(page, "Search", "GameFontNormalSmall", 10, -42)
	ui.slutSearch = EditBox(page, "DmorphOctoSlutmogSearch", 200, 52, -38)
	ui.slutSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterSlutmog)
	end)
	ui.slutSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterSlutmog()
	end)
	ui.slutCount = Label(page, "", "GameFontDisableSmall", 262, -42, "DmorphOctoSlutmogCount")
	ui.slutList = List(page, "DmorphOctoSlutmogList", 8, -66, 60, function(row, index)
		local catalog = M.GetSlutmogCatalog()
		local i = ui.slutResult[index]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(QualityColor(catalog.quality[i]))
		row.info:SetText(M.SLOT_NAMES[catalog.slots[i]])
		if catalog.ids[i] == M.GetState().items[catalog.slots[i]] then
			row:LockHighlight()
			row.tick:Show()
		end
	end, P.WearSlutmog, function(index)
		if ui.slutResult[index] then
			P.ShowSlutmog(index, " - click to wear it")
		end
	end, LIST_W, 15)
	ui.slutList.leave = P.RefreshSlutBox
	ui.slutBox = P.NewBox(page, "Slutmog", "dress", -66, 15, "Try on", P.StepSlutmog)
	local y = -346
	Button(page, "Birthday suit", 120, 8, y, function()
		Morph(M.BirthdaySuit)
	end, "DmorphOctoSlutmogBirthday")
	Label(page, "Revealing pieces, by how much body they cover.", "GameFontDisableSmall", 136, y - 6)
end

-- Extra wear tab (2.29.0): spell looks worn on top of everything (Shadowform,
-- shields, glows...), up to M.EXTRA_MAX at once; click to put on or take off.
-- Category buttons (user, 30 Oct: "CLEANED UP INTO CATs"): the ported looks' names
-- start with their category ("Wings: ..."); the client's own are spell looks.
P.EXTRA_CATS = {
	{ text = "All" }, { text = "Wings", prefix = "Wings: " }, { text = "Bags", prefix = "Bag: " },
	{ text = "Quivers", prefix = "Quiver: " }, { text = "Banners", prefix = "Banner: " },
	{ text = "Cloaks", prefix = "Cloak: " }, { text = "Shadow", prefix = "Shadow: " }, { text = "Trails", prefix = "Trail: " },
	{ text = "Spells", spells = true },
}
P.extraCat = 1
function P.FilterExtra(keep)
	local catalog = M.GetExtraWearCatalog()
	local text = strlower(ui.extraSearch:GetText() or "")
	local result, m = {}, 0
	local cat = P.EXTRA_CATS[P.extraCat]
	for i = 1, catalog.count do
		local name = catalog.names[i]
		local inCat = (not cat.prefix or strsub(name, 1, strlen(cat.prefix)) == cat.prefix) and (not cat.spells or not catalog.ported[i])
		if inCat and (text == "" or strfind(strlower(name .. " " .. catalog.others[i] .. " " .. catalog.models[i]), text, 1, true)) then
			m = m + 1
			result[m] = i
		end
	end
	ui.extraResult = result
	ui.extraCount:SetText(Count(m, "look") .. ", " .. table.getn(M.GetExtraWear()) .. " of " .. M.EXTRA_MAX .. " worn")
	ui.extraList.SetCount(m, keep)
end

function P.RefreshExtra()
	if ui.extraResult then
		P.FilterExtra(true)
	end
	ui.extraList.Refresh()
end

function P.BuildExtraPage(page)
	ui.extraCats = {}
	for i = 1, table.getn(P.EXTRA_CATS) do
		local index = i
		ui.extraCats[i] = Button(page, P.EXTRA_CATS[i].text, 57, 8 + (i - 1) * 60, -8, function()
			P.extraCat = index
			for k = 1, table.getn(ui.extraCats) do
				if k == index then ui.extraCats[k]:LockHighlight() else ui.extraCats[k]:UnlockHighlight() end
			end
			P.FilterExtra()
		end, "DmorphOctoExtraCat" .. i)
	end
	Label(page, "Search", "GameFontNormalSmall", 10, -42)
	ui.extraSearch = EditBox(page, "DmorphOctoExtraSearch", 200, 52, -38)
	ui.extraSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, P.FilterExtra)
	end)
	ui.extraSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		P.FilterExtra()
	end)
	ui.extraCount = Label(page, "", "GameFontDisableSmall", 262, -42, "DmorphOctoExtraCount")
	ui.extraList = List(page, "DmorphOctoExtraList", 8, -66, 220, function(row, index)
		local catalog = M.GetExtraWearCatalog()
		local i = ui.extraResult[index]
		row.text:SetText(catalog.names[i])
		row.info:SetText(catalog.ported[i] and "Retail (ported pack)" or catalog.others[i])
		if M.IsWearingExtra(catalog.ids[i]) then
			row:LockHighlight()
			row.tick:Show()
		end
	end, function(index)
		local catalog = M.GetExtraWearCatalog()
		Morph(M.ToggleExtraWear, catalog.ids[ui.extraResult[index]])
		P.FilterExtra(true)
	end, nil, PAGE_W - 24, 15)
	local y = -346
	Button(page, "Take all off", 120, 8, y, function()
		Morph(M.ClearExtraWear)
		P.FilterExtra(true)
	end, "DmorphOctoExtraClear")
	Label(page, "Spell looks worn on top of your morph; DMorph users (2.29+) see them too.", "GameFontDisableSmall", 136, y - 6)
end

-- Sets tab --------------------------------------------------------------------------

local function FilterSets(keep)
	local prefs = Prefs()
	local count
	ui.setResult, count = M.FilterCatalog(M.GetSetCatalog(), ui.setSearch:GetText(),
		M.SET_FILTERS[prefs.setFilter], M.QUALITY_FILTERS[prefs.setQuality].quality, prefs.sortSets, prefs.setType)
	ui.setTypeButton:SetText(TypeText(prefs.setType))
	ui.setQualityButton:SetText(QualityText(prefs.setQuality))
	ui.setSourceButton:SetText(M.SET_FILTERS[prefs.setFilter].text)
	ui.setCount:SetText(Count(count, "set"))
	ui.setList.SetCount(count, keep)
end

local function RefreshSetGear()
	if ui.setGearButton then
		ui.setGearButton:SetText(M.GetHideGearUnderSets() and "Own gear: hidden" or "Own gear: shown")
	end
end

function P.ShowSet(i, info)
	local catalog = M.GetSetCatalog()
	local r, g, b = QualityColor(catalog.quality[i])
	P.BoxShowItems(ui.setBox, catalog.pieces[i], catalog.names[i], { r, g, b },
		Count(table.getn(catalog.pieces[i]), "piece") .. info)
end

-- The set you put on last, else your look.
function P.RefreshSetBox()
	if ui.selectedSet then
		P.ShowSet(ui.selectedSet, " - you have it on")
	else
		P.BoxShowItems(ui.setBox, nil, "Your look", C.dim, "Hover a set to try it on.")
	end
end

local function RefreshSets()
	RefreshSetGear()
	ui.setList.Refresh()
	P.RefreshSetBox()
end

local function SetTooltip(index, row)
	local catalog = M.GetSetCatalog()
	local i = ui.setResult[index]
	if not i then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	GameTooltip:SetText(catalog.names[i], QualityColor(catalog.quality[i]))
	local pieces = catalog.pieces[i]
	for k = 1, table.getn(pieces) do
		local slots = M.GetItemSlots(pieces[k])
		if slots then
			GameTooltip:AddLine(M.SLOT_NAMES[slots[1]] .. ": " .. M.DescribeItem(pieces[k], slots[1]), 1, 1, 1)
		else
			GameTooltip:AddLine("Item " .. pieces[k] .. ": still being looked up", 0.6, 0.6, 0.6)
		end
	end
	GameTooltip:AddLine("Click to wear every piece.", 0.6, 1, 0.6)
	GameTooltip:Show()
	-- And your character wearing the whole set.
	P.ShowSet(i, " - click to wear them")
end

function P.WearSetAt(pos)
	ui.selectedSet = ui.setResult[pos]
	ui.setList.Refresh()
	Morph(M.WearSet, ui.selectedSet)
	P.RefreshSetBox()
end

function P.StepSet(step)
	local pos
	for k = 1, ui.setList.count do
		if ui.setResult[k] == ui.selectedSet then
			pos = k
		end
	end
	pos = P.StepPosition(pos, step, ui.setList.count)
	if not pos then
		return SetStatus(false, "No sets in the list: clear the search or pick other filters.")
	end
	P.WearSetAt(pos)
	ui.setList.Show(pos)
end

local function BuildSetsPage(page)
	Label(page, "Search", "GameFontNormalSmall", 10, -12)
	ui.setSearch = EditBox(page, "DmorphOctoSetSearch", 200, 52, -8)
	ui.setSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterSets)
	end)
	ui.setSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterSets()
	end)
	SortButton(page, "DmorphOctoSetSort", PAGE_W - 92 - 8, -7, "sortSets", FilterSets)
	ui.setTypeButton = Button(page, "Any type", 170, 8, -34, function()
		TypeMenu(this, M.GetSetCatalog(), Prefs().setType, function(kind)
			Prefs().setType = kind
			FilterSets()
		end)
	end, "DmorphOctoSetType")
	ui.setTypeButton:SetScript("OnEnter", function()
		Tooltip(this, "Type", "Cloth, leather, mail or plate: what most of the set's armour is made of.")
	end)
	ui.setTypeButton:SetScript("OnLeave", HideTooltip)
	ui.setQualityButton = Button(page, "Any quality", 170, 190, -34, function()
		QualityMenu(this, "setQuality", FilterSets)
	end, "DmorphOctoSetQuality")
	ui.setSourceButton = Button(page, "All sets", 170, 372, -34, function()
		SourceMenu(this, M.SET_FILTERS, "setFilter", FilterSets)
	end, "DmorphOctoSetSource")

	ui.setList = List(page, "DmorphOctoSetList", 8, -62, 70, function(row, index)
		local catalog = M.GetSetCatalog()
		local i = ui.setResult[index]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(QualityColor(catalog.quality[i]))
		row.info:SetText(Count(table.getn(catalog.pieces[i]), "piece"))
		if i == ui.selectedSet then
			row:LockHighlight()
			row.tick:Show()
		end
	end, P.WearSetAt, SetTooltip, LIST_W, 14)
	ui.setList.leave = P.RefreshSetBox
	ui.setBox = P.NewBox(page, "Sets", "dress", -62, 14, "Try on", P.StepSet)
	ui.setCount = Label(page, "", "GameFontDisableSmall", 10, -322, "DmorphOctoSetCount")
	ui.setLookup = Label(page, "", "GameFontDisableSmall", 110, -322, "DmorphOctoSetLookup")
	-- Your own gear in the slots a set has no piece for: hidden (the default) or shown.
	ui.setGearButton = Button(page, "", 140, 8, -346, function()
		Morph(M.SetHideGearUnderSets, not M.GetHideGearUnderSets())
		RefreshSetGear()
	end, "DmorphOctoSetGear")
	ui.setGearButton:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_TOP")
		GameTooltip:SetText("Your own gear under sets")
		GameTooltip:AddLine("Hidden: the slots a set has no piece for show nothing,", 1, 1, 1)
		GameTooltip:AddLine("so your real gear doesn't show through the set.", 1, 1, 1)
		GameTooltip:AddLine("Shown: those slots keep your own gear.", 1, 1, 1)
		GameTooltip:AddLine("Click to switch. It applies from the next set you wear.", 0.6, 1, 0.6)
		GameTooltip:Show()
	end)
	ui.setGearButton:SetScript("OnLeave", HideTooltip)
	RefreshSetGear()
	Label(page, "Click a set to wear every piece. Hover: the pieces.", "GameFontDisableSmall", 156, -351)
end

-- Wardrobe tab ------------------------------------------------------------------------

-- An outfit's items on your character (a creature or race look can't be
-- tried on, so the line under it says which).
function P.ShowOutfit(name, info)
	local outfit = M.GetOutfit(name)
	if not outfit then
		return
	end
	local items = {}
	for _, id in pairs(outfit.items) do
		if id ~= 0 then
			table.insert(items, id)
		end
	end
	P.BoxShowItems(ui.outfitBox, items, name, C.gold, M.DescribeOutfit(outfit) .. info)
end

function P.RefreshOutfitBox()
	if selectedOutfit and M.GetOutfit(selectedOutfit) then
		P.ShowOutfit(selectedOutfit, "")
	else
		P.BoxShowItems(ui.outfitBox, nil, "No outfit picked", C.dim, "Hover an outfit to try it on.")
	end
end

local function RefreshWardrobe()
	ui.outfitNames = M.GetOutfitNames()
	local count = table.getn(ui.outfitNames)
	if count == ui.outfitList.count then
		ui.outfitList.Refresh()
	else
		ui.outfitList.SetCount(count)
	end
	if count == 0 then
		ui.outfitEmpty:Show()
	else
		ui.outfitEmpty:Hide()
	end
	P.RefreshOutfitBox()
end

local function LoadSelected()
	if not selectedOutfit then
		return SetStatus(false, "Pick an outfit in the list first.")
	end
	Morph(M.LoadOutfit, selectedOutfit)
end

function P.StepOutfit(step)
	local names = ui.outfitNames or {}
	local pos
	for k = 1, table.getn(names) do
		if names[k] == selectedOutfit then
			pos = k
		end
	end
	pos = P.StepPosition(pos, step, table.getn(names))
	if not pos then
		return SetStatus(false, "No outfits yet: build a look, type a name and press Save.")
	end
	selectedOutfit = names[pos]
	ui.outfitName:SetText(selectedOutfit)
	ui.outfitList.Show(pos)
	LoadSelected()
end

local function BuildWardrobePage(page)
	Label(page, "Wardrobe", "GameFontNormal", 10, -12)
	Label(page, "Outfits are shared by all your characters.", "GameFontDisableSmall", 86, -14)
	Label(page, "Name", "GameFontNormalSmall", 10, -42)
	ui.outfitName = EditBox(page, "DmorphOctoOutfitName", 200, 52, -38, 32)
	local function Save()
		ui.outfitName:ClearFocus()
		local ok, message = M.SaveOutfit(ui.outfitName:GetText())
		if ok then
			selectedOutfit = M.FindOutfit(ui.outfitName:GetText())
		end
		SetStatus(ok, message)
	end
	ui.outfitName:SetScript("OnEnterPressed", Save)
	Button(page, "Save current look", 140, 260, -37, Save)

	ui.outfitList = List(page, "DmorphOctoOutfitList", 8, -66, 150, function(row, index)
		local name = ui.outfitNames[index]
		row.text:SetText(name)
		row.info:SetText(M.DescribeOutfit(M.GetOutfit(name)))
		if name == selectedOutfit then
			row:LockHighlight()
			row.tick:Show()
		end
	end, function(index)
		local name = ui.outfitNames[index]
		if name == selectedOutfit then
			-- A second click on the chosen outfit puts it on.
			return LoadSelected()
		end
		selectedOutfit = name
		ui.outfitName:SetText(name)
		ui.outfitList.Refresh()
		P.RefreshOutfitBox()
		SetStatus(true, "Click \"" .. name .. "\" again, or press Load, to put it on.")
	end, function(index)
		local name = ui.outfitNames[index]
		if name then
			P.ShowOutfit(name, " - click twice to put it on")
		end
	end, LIST_W, 15)
	ui.outfitList.leave = P.RefreshOutfitBox
	ui.outfitBox = P.NewBox(page, "Wardrobe", "dress", -66, 15, "Try on", P.StepOutfit)
	ui.outfitEmpty = Label(page, "No outfits yet. Build a look, type a name above and press Save.",
		"GameFontDisableSmall", 14, -74)
	ui.outfitEmpty:SetWidth(LIST_W - 12)

	local y = -346
	Button(page, "Load", 90, 8, y, LoadSelected)
	Button(page, "Delete", 90, 102, y, function()
		if not selectedOutfit then
			return SetStatus(false, "Pick an outfit in the list first.")
		end
		pendingDelete = selectedOutfit
		StaticPopup_Show("DMORPHOCTO_DELETE_OUTFIT", selectedOutfit)
	end)
end

StaticPopupDialogs["DMORPHOCTO_DELETE_OUTFIT"] = {
	text = "Delete the outfit \"%s\"?",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	OnAccept = function()
		if pendingDelete == selectedOutfit then
			selectedOutfit = nil
		end
		SetStatus(M.DeleteOutfit(pendingDelete))
		pendingDelete = nil
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
}

-- Setup reminder (user, 21 Oct: "if someone has an outdated version or hasn't
-- run the DmorphHelper installer, a pop-up when logging in or reloading"): once
-- per login or /reload, a few seconds in, when VanillaHelpers isn't running or
-- DmorphHelper is missing or older than this DMorph's. "Don't remind me" holds
-- until DMorph comes with a newer DmorphHelper.
local SETUP_NAG_DELAY = 5
function P.SetupProblem()
	if not M.HasMorphAPI() then
		return "DMorph can't morph anything: VanillaHelpers isn't running.\n\n" .. M.MissingAPI()
	end
	local running, wanted = M.GetHelperVersion()
	if not running then
		return "DmorphHelper isn't running, so weapon glows, size, your real skin, face and hair, weather and "
			.. "keeping your own faction during race morphs don't work.\n\nClose the game, double-click "
			.. "\"Install DmorphHelper.bat\" in Interface\\AddOns\\DmorphOcto, then start the game from OctoLauncher."
	end
	if running < wanted then
		return "Your DmorphHelper is out of date: v" .. running .. " is running, this DMorph needs v" .. wanted
			.. ".\n\nClose the game, double-click \"Install DmorphHelper.bat\" in Interface\\AddOns\\DmorphOcto, "
			.. "then start the game from OctoLauncher."
	end
end

StaticPopupDialogs["DMORPHOCTO_SETUP"] = {
	text = "DMorph: %s",
	button1 = "OK",
	button2 = "Don't remind me",
	-- (No hideOnEscape: Escape would count as "Don't remind me".)
	OnCancel = function()
		local _, wanted = M.GetHelperVersion()
		DmorphOctoAccount.setupNagOff = wanted
	end,
	timeout = 0,
	whileDead = 1,
}

local setupNag = CreateFrame("Frame")
setupNag:RegisterEvent("PLAYER_ENTERING_WORLD")
setupNag:SetScript("OnEvent", function()
	this:UnregisterEvent("PLAYER_ENTERING_WORLD") -- once per login or /reload
	this.wait = SETUP_NAG_DELAY
end)
setupNag:SetScript("OnUpdate", function()
	if not this.wait then
		return
	end
	this.wait = this.wait - arg1
	if this.wait > 0 then
		return
	end
	this.wait = nil
	local _, wanted = M.GetHelperVersion()
	if DmorphOctoAccount and DmorphOctoAccount.setupNagOff == wanted and M.HasMorphAPI() then
		return
	end
	local problem = P.SetupProblem()
	if problem then
		StaticPopup_Show("DMORPHOCTO_SETUP", problem)
	end
end)

-- Weather tab ---------------------------------------------------------------------

-- A button per weather (M.WEATHERS): Clear skies on its own row, then light,
-- normal and heavy rain, snow and sandstorm, with a slider for the strength
-- of the one picked. Below, the time of day (M.TIMES and a slider).
local WEATHER_ROW_NAMES = { "Rain", "Snow", "Sandstorm" }

local function Highlight(button, on)
	if on then
		button:LockHighlight()
	else
		button:UnlockHighlight()
	end
end

local function RefreshWeather()
	local kind, intensity, serverKind, serverIntensity = M.GetWeather()
	for i = 1, table.getn(M.WEATHERS) do
		local w = M.WEATHERS[i]
		Highlight(ui.weatherButtons[w.key], kind == w.kind and (w.kind == 0 or math.abs(intensity - w.intensity) < 0.001))
	end
	local minutes, realMinutes = M.GetTime()
	for i = 1, table.getn(M.TIMES) do
		local t = M.TIMES[i]
		Highlight(ui.timeButtons[t.key], minutes == t.minutes)
	end
	ui.weatherSync = true
	ui.weatherSlider:SetValue(kind and kind > 0 and intensity or 0.55)
	ui.timeSlider:SetValue(minutes or realMinutes or 720)
	ui.weatherSync = nil
	local weather = "Weather: the server's"
	if kind then
		weather = "Weather: |cff33ff99" .. M.DescribeWeather(kind, intensity) .. "|r (yours)"
	end
	if serverKind then
		weather = weather .. "; the server's is " .. M.DescribeWeather(serverKind, serverIntensity)
	end
	local time = "Time: the real time"
	if minutes then
		time = "Time: |cff33ff99" .. M.DescribeTime(minutes) .. "|r (yours)"
	end
	if realMinutes then
		time = time .. "; the real time is " .. M.DescribeTime(realMinutes)
	end
	ui.weatherState:SetText(weather .. ".\n" .. time .. ".")
	if M.HasWeather() and M.HasTime() then
		ui.weatherMissing:Hide()
	else
		ui.weatherMissing:Show()
	end
end

-- A slider like the size slider; onStill runs once it stands still.
local function WeatherSlider(page, name, y, min, max, step, onChange, onStill)
	local slider = CreateFrame("Slider", name, page)
	slider:SetOrientation("HORIZONTAL")
	slider:SetWidth(PAGE_W - 130)
	slider:SetHeight(8)
	slider:SetPoint("TOPLEFT", page, "TOPLEFT", 110, y - 4)
	Flat(slider, C.field, C.line)
	slider:SetThumbTexture(WHITE)
	local thumb = slider:GetThumbTexture()
	if thumb then
		thumb:SetWidth(10)
		thumb:SetHeight(14)
		thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	slider.timer = NewTimer()
	slider:SetScript("OnValueChanged", function()
		local value = math.floor(this:GetValue() / step + 0.5) * step
		onChange(value)
		if ui.weatherSync then
			return
		end
		Debounce(this.timer, 0.3, function()
			onStill(value)
		end)
	end)
	slider:SetScript("OnLeave", HideTooltip)
	return slider
end

local function BuildWeatherPage(page)
	Label(page, "Weather and time", "GameFontNormal", 10, -12)
	Label(page, "Only on your screen; it stays on in every zone.", "GameFontDisableSmall", 136, -15)
	ui.weatherButtons = {}
	local function Pick()
		Morph(M.SetWeather, this.weatherKind, this.intensity)
	end
	for i = 1, table.getn(M.WEATHERS) do
		local w = M.WEATHERS[i]
		local x, y = 110, -36
		if w.kind > 0 then
			-- Light, normal, heavy in columns; one row per kind.
			x = 110 + math.mod(i - 2, 3) * 118
			y = -64 - (w.kind - 1) * 28
		end
		local button = Button(page, w.text, 112, x, y, Pick, "DmorphOctoWeather" .. w.key)
		button.weatherKind, button.intensity = w.kind, w.intensity
		ui.weatherButtons[w.key] = button
	end
	Label(page, "Sky", "GameFontHighlight", 14, -40)
	for i = 1, 3 do
		Label(page, WEATHER_ROW_NAMES[i], "GameFontHighlight", 14, -68 - (i - 1) * 28)
	end

	ui.weatherStrength = Label(page, "Strength", "GameFontHighlight", 14, -155, "DmorphOctoWeatherStrengthLabel")
	ui.weatherSlider = WeatherSlider(page, "DmorphOctoWeatherStrength", -154, 0.05, 1, 0.05, function(value)
		ui.weatherStrength:SetText("Strength " .. math.floor(value * 100 + 0.5) .. "%")
	end, function(value)
		local kind = M.GetWeather()
		if kind and kind > 0 then
			SetStatus(M.SetWeather(kind, value))
		else
			SetStatus(false, "Pick rain, snow or a sandstorm first; the slider sets how strong it is.")
			RefreshWeather()
		end
	end)
	ui.weatherSlider:SetScript("OnEnter", function()
		Tooltip(this, "Strength", "How strong the rain, snow or sandstorm you picked is.",
			"Its sound changes with it: light below 40%, heavy from 70%.")
	end)

	-- Time of day: the world's light, sky, sun and moon.
	Label(page, "Time of day", "GameFontHighlight", 14, -196)
	ui.timeButtons = {}
	for i = 1, table.getn(M.TIMES) do
		local t = M.TIMES[i]
		local button = Button(page, t.text, 84, 110 + (i - 1) * 88, -192, function()
			Morph(M.SetTime, this.minutes)
		end, "DmorphOctoTime" .. t.key)
		button.minutes = t.minutes
		ui.timeButtons[t.key] = button
	end
	ui.timeLabel = Label(page, "Time", "GameFontHighlight", 14, -227, "DmorphOctoTimeLabel")
	ui.timeSlider = WeatherSlider(page, "DmorphOctoTimeSlider", -226, 0, 1425, 15, function(value)
		ui.timeLabel:SetText("Time " .. M.DescribeTime(value))
	end, function(value)
		SetStatus(M.SetTime(value))
	end)
	ui.timeSlider:SetScript("OnEnter", function()
		Tooltip(this, "Time of day", "Drag to light the world as at that time: day, dusk, night.",
			"Your clock and everyone else keep the real time.")
	end)

	ui.weatherState = Label(page, "", "GameFontHighlightSmall", 10, -258, "DmorphOctoWeatherState")
	ui.weatherState:SetWidth(PAGE_W - 20)
	ui.weatherMissing = Label(page, "Weather and time need DmorphHelper v9 or newer: close the game and "
		.. "double-click \"Install DmorphHelper.bat\" in the DmorphOcto folder.", "GameFontRedSmall", 10, -290,
		"DmorphOctoWeatherMissing")
	ui.weatherMissing:SetWidth(PAGE_W - 20)
	Label(page, "Weather shows outdoors only. Stormy skies come with rain or snow where the zone has them.",
		"GameFontDisableSmall", 10, -322)

	Button(page, "Server's weather", 140, 8, -352, function()
		Morph(M.SetWeather, nil)
	end, "DmorphOctoWeatherServer")
	Button(page, "Real time", 100, 152, -352, function()
		Morph(M.SetTime, nil)
	end, "DmorphOctoTimeReal")
	Label(page, ".weather rain heavy and .time 22:00 in chat.", "GameFontDisableSmall", 258, -357)
end

local REFRESH = {
	weather = RefreshWeather,
	models = RefreshModels,
	mounts = RefreshMounts,
	favourites = RefreshFavourites,
	races = RefreshRaces,
	glows = RefreshGlows,
	items = RefreshItems,
	slutmog = RefreshSlutmog,
	extra = function() P.RefreshExtra() end,
	sets = RefreshSets,
	wardrobe = RefreshWardrobe,
}

local function RefreshAll()
	if not (frame and frame:IsVisible()) then
		return
	end
	UpdateSlots()
	UpdatePlate()
	ShowArt()
	REFRESH[currentTab]()
	RequestPreview()
end

-- Once a second: slot icons (1.12 has no event for item info arriving) and
-- items the background lookup has found.
local function Poll()
	UpdateSlots()
	local version = M.GetItemsVersion()
	if version ~= ui.itemsVersion then
		ui.itemsVersion = version
		if ui.itemResult and currentTab == "items" then
			FilterItems(true)
		end
		if ui.setResult and currentTab == "sets" then
			FilterSets(true)
		end
		if ui.slutResult and currentTab == "slutmog" then
			FilterSlutmog(true)
		end
	end
	local left = M.GetLookupStatus()
	local text = ""
	if left > 0 then
		text = "Looking up " .. Count(left, "OctoWoW item") .. "..."
	end
	ui.itemLookup:SetText(text)
	ui.setLookup:SetText(text)
end

local function TabLook(tab, active)
	-- The open tab is filled purple, the others plain.
	if active then
		tab:SetBackdropColor(C.deep[1], C.deep[2], C.deep[3], 1)
		tab:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
		tab.label:SetTextColor(1, 1, 1)
	else
		tab:SetBackdropColor(C.btn[1], C.btn[2], C.btn[3], 1)
		tab:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
		tab.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
	end
end

ShowTab = function(key)
	if key ~= "glows" then
		P.EndGlowPreview()
	end
	currentTab = key
	ui.menu:Hide()
	for i = 1, table.getn(TABS) do
		local tab = TABS[i]
		if tab.key == key then
			ui.pages[tab.key]:Show()
		else
			ui.pages[tab.key]:Hide()
		end
		TabLook(ui.tabs[tab.key], tab.key == key)
	end
	if key == "models" and not ui.modelResult then
		FilterModels()
	elseif key == "items" then
		FilterItems()
	elseif key == "extra" then
		P.FilterExtra(ui.extraResult ~= nil)
	elseif key == "slutmog" then
		FilterSlutmog(ui.slutResult ~= nil)
	elseif key == "sets" and not ui.setResult then
		FilterSets()
	elseif key == "glows" then
		FilterGlows(ui.glowResult ~= nil)
	elseif key == "favourites" then
		FilterFavourites()
	elseif key == "mounts" and not ui.mountResult then
		FilterMounts()
	end
	UpdateSlots()
	REFRESH[key]()
end

-- Window ------------------------------------------------------------------------------

local function BuildStage()
	-- The dressing room: backdrop art, your character, the slots around it.
	local stage = CreateFrame("Frame", "DmorphOctoStage", frame)
	stage:SetWidth(ART_W)
	stage:SetHeight(ART_H)
	stage:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)
	local base = stage:GetFrameLevel()
	-- Levels: model loading (+1) < art (+2) < model shown (+3) < drag area (+4)
	-- < name plate (+5) < slots (+6) < border (+7).
	local art = Layer(stage, 2)
	art:SetAllPoints(stage)
	local black = art:CreateTexture(nil, "BACKGROUND")
	black:SetTexture(0, 0, 0, 1)
	black:SetAllPoints(art)
	ui.art = {}
	local sizes = { { 256, 255 }, { 62, 255 }, { 256, 128 }, { 62, 128 } }
	for i = 1, 4 do
		local texture = art:CreateTexture("DmorphOctoArt" .. i, "ARTWORK")
		texture:SetWidth(sizes[i][1])
		texture:SetHeight(sizes[i][2])
		ui.art[i] = texture
	end
	ui.art[1]:SetPoint("TOPLEFT", art, "TOPLEFT", 0, 0)
	ui.art[2]:SetPoint("TOPLEFT", ui.art[1], "TOPRIGHT", 0, 0)
	ui.art[3]:SetPoint("TOPLEFT", ui.art[1], "BOTTOMLEFT", 0, 0)
	ui.art[4]:SetPoint("TOPLEFT", ui.art[1], "BOTTOMRIGHT", 0, 0)

	local p = { models = {}, front = 1, rotation = 0.61, low = base + 1, high = base + 3, zoom = 0, panX = 0, panY = 0 }
	for i = 1, 2 do
		local model = CreateFrame("PlayerModel", "DmorphOctoModel" .. i, stage)
		model:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -4)
		model:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, PLATE_H)
		model:SetFrameLevel(p.low)
		model:Hide()
		p.models[i] = model
	end
	ui.preview = p
	-- Creature morphs show here instead (P.StageCreature).
	ui.stageView = NewView(stage, "DmorphOctoStageModel", base + 1, base + 3, ART_W / (ART_H - 4 - PLATE_H))
	ui.stageView.model:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -4)
	ui.stageView.model:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, PLATE_H)
	ui.stageView.model:Hide()

	-- Over the model: drag to turn it, right-drag to move it, mouse wheel to
	-- zoom in and out.
	local drag = CreateFrame("Frame", "DmorphOctoModelDrag", stage)
	drag:SetFrameLevel(base + 4)
	drag:SetAllPoints(p.models[1])
	drag:EnableMouse(true)
	drag:EnableMouseWheel(true)
	drag:SetScript("OnMouseDown", function()
		local x, y = GetCursorPosition()
		if arg1 == "RightButton" then
			this.panX, this.panY = x, y
		else
			this.dragX = x
		end
	end)
	drag:SetScript("OnMouseUp", function()
		this.dragX, this.panX, this.panY = nil, nil, nil
	end)
	drag:SetScript("OnUpdate", function()
		if this.dragX then
			local x = GetCursorPosition()
			p.rotation = p.rotation + (x - this.dragX) * 0.02
			this.dragX = x
			p.models[p.front]:SetRotation(p.rotation)
			ui.stageView.facing = p.rotation
		elseif this.panX then
			-- The farther in, the smaller a step: the model follows the cursor.
			local x, y = GetCursorPosition()
			local step = 0.006 / (frame:GetEffectiveScale() * (1 + math.max(p.zoom, 0) * 0.45))
			p.panX = p.panX + (x - this.panX) * step
			p.panY = p.panY + (y - this.panY) * step
			this.panX, this.panY = x, y
			ApplyView(p.models[p.front])
		end
	end)
	drag:SetScript("OnMouseWheel", function()
		Zoom(arg1)
	end)
	local function ZoomButton(text, width, x, name, onClick, line)
		local button = Button(stage, text, width, x, -10, onClick, name)
		button:SetFrameLevel(base + 6)
		button:SetScript("OnEnter", function()
			Tooltip(this, "Zoom", line, "Or: mouse wheel over your character to zoom, right-drag to move it, drag to turn it.")
		end)
		button:SetScript("OnLeave", HideTooltip)
	end
	local middle = ART_W / 2
	ZoomButton("-", 24, middle - 117, "DmorphOctoZoomOut", function()
		Zoom(-1)
	end, "Zoom out.")
	ZoomButton("+", 24, middle - 91, "DmorphOctoZoomIn", function()
		Zoom(1)
	end, "Zoom in, to see the details.")
	ZoomButton("Reset view", 80, middle - 65, "DmorphOctoZoomReset", ResetView, "Back to the whole character.")
	-- Birthday suit (user, 18 Oct): every armour slot shows nothing, to build up from.
	local birthday = Button(stage, "Birthday suit", 92, middle + 19, -10, function()
		Morph(M.BirthdaySuit)
	end, "DmorphOctoBirthdaySuit")
	birthday:SetFrameLevel(base + 6)
	birthday:SetScript("OnEnter", function()
		Tooltip(this, "Birthday suit", "Every armour slot shows nothing: build a look up from bare skin.",
			"Weapons stay. Use my own gear (Items tab) or Reset everything brings your gear back.")
	end)
	birthday:SetScript("OnLeave", HideTooltip)

	local plate = Layer(stage, 5)
	plate:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 0, 0)
	plate:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, 0)
	plate:SetHeight(PLATE_H + 20)
	Gradient(plate, "BACKGROUND", 0.03, 0.02, 0.05, 0.95, 0.03, 0.02, 0.05, 0):SetAllPoints(plate)
	ui.plateTitle = Font(plate:CreateFontString("DmorphOctoLookName", "OVERLAY", "GameFontNormalLarge"), 15, C.gold)
	ui.plateTitle:SetPoint("BOTTOM", plate, "BOTTOM", 0, 22)
	ui.plateTitle:SetWidth(ART_W - 16)
	ui.plateTitle:SetHeight(18)
	ui.plateInfo = Font(plate:CreateFontString("DmorphOctoLookInfo", "OVERLAY", "GameFontHighlightSmall"), 11, C.dim)
	ui.plateInfo:SetPoint("BOTTOM", plate, "BOTTOM", 0, 8)
	ui.plateInfo:SetWidth(ART_W - 16)
	ui.plateInfo:SetHeight(14) -- one line; a longer one ends in "..."

	-- Your size in the world, 25% to 300% (DmorphHelper v2). Applied once the
	-- slider stands still: each change rebuilds your model.
	ui.sizeTimer = NewTimer()
	local size = CreateFrame("Slider", "DmorphOctoSize", plate)
	size:SetFrameLevel(base + 6)
	size:SetOrientation("HORIZONTAL")
	size:SetWidth(132)
	size:SetHeight(8)
	size:SetPoint("BOTTOMLEFT", plate, "BOTTOMLEFT", 124, 50)
	-- A thin flat track and a purple thumb (OctoBG's slider).
	Flat(size, C.field, C.line)
	size:SetThumbTexture(WHITE)
	local thumb = size:GetThumbTexture()
	if thumb then
		thumb:SetWidth(10)
		thumb:SetHeight(14)
		thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	size:SetMinMaxValues(0.25, 3)
	-- 1% steps, and the mouse wheel for a single one (Khijazi: finer steps).
	size:SetValueStep(0.01)
	size:EnableMouseWheel(true)
	size:SetScript("OnMouseWheel", function()
		this:SetValue(math.max(0.25, math.min(3, this:GetValue() + (arg1 > 0 and 0.01 or -0.01))))
	end)
	ui.sizeLabel = Font(size:CreateFontString("DmorphOctoSizeLabel", "OVERLAY", "GameFontHighlightSmall"), 11)
	ui.sizeLabel:SetPoint("RIGHT", size, "LEFT", -8, 0)
	-- "in game": it changes your character in the world, not only here (user, 18 Oct).
	ui.sizeLabel:SetText("Size in game 100%")
	size:SetScript("OnValueChanged", function()
		local value = math.floor(this:GetValue() * 100 + 0.5) / 100
		ui.sizeLabel:SetText("Size in game " .. math.floor(value * 100 + 0.5) .. "%")
		if ui.sizeSync then
			return
		end
		Debounce(ui.sizeTimer, 0.3, function()
			if math.abs(value - 1) < 0.001 then
				SetStatus(M.SetScale(nil))
			else
				SetStatus(M.SetScale(value))
			end
			UpdatePlate() -- back to the size you have if it couldn't change
		end)
	end)
	size:SetScript("OnMouseUp", function()
		if arg1 == "RightButton" then
			this:SetValue(1)
		end
	end)
	size:SetScript("OnEnter", function()
		Tooltip(this, "Size in game", "Drag to make your character smaller or bigger in the world, not only here.",
			"Right-click or Reset: your own size. Needs DmorphHelper (Setup shows it).")
	end)
	size:SetScript("OnLeave", HideTooltip)
	ui.sizeSlider = size
	local sizeReset = Button(plate, "Reset", 46, 0, 0, function()
		size:SetValue(1)
	end, "DmorphOctoSizeReset")
	sizeReset:ClearAllPoints()
	sizeReset:SetPoint("LEFT", size, "RIGHT", 8, 0)
	sizeReset:SetHeight(18)
	sizeReset:SetFrameLevel(base + 6)
	sizeReset:SetScript("OnEnter", function()
		Tooltip(this, "Normal size", "Your character back to its own size, 100%.")
	end)
	sizeReset:SetScript("OnLeave", HideTooltip)

	local function AddSlots(slots, x)
		for i = 1, table.getn(slots) do
			local slot = slots[i]
			local button = CreateFrame("Button", "DmorphOctoSlot" .. slot, stage)
			button:SetFrameLevel(base + 6)
			button:SetWidth(36)
			button:SetHeight(36)
			button:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -10 - (i - 1) * 46)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			-- A flat square: the icon inside a 1 px line, a purple frame
			-- round it while the slot is morphed.
			Flat(button, C.field, C.line)
			button.icon = button:CreateTexture(nil, "BORDER")
			button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
			button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
			button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			button.glow = CreateFrame("Frame", nil, button)
			button.glow:SetFrameLevel(base + 7)
			button.glow:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
			button.glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
			button.glow:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
			button.glow:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
			Hover(button, 0.3)
			button.slot = slot
			button:SetScript("OnClick", function()
				if arg1 == "RightButton" then
					Morph(M.SetItem, this.slot, 0)
				else
					ShowItemSlot(this.slot)
				end
			end)
			button:SetScript("OnEnter", SlotTooltip)
			button:SetScript("OnLeave", HideTooltip)
			ui.slots[slot] = button
		end
	end
	AddSlots(LEFT_SLOTS, 8)
	AddSlots(RIGHT_SLOTS, ART_W - 44)

	local border = Layer(stage, 7)
	border:SetPoint("TOPLEFT", stage, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	border:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)

	Button(frame, "Reset model", 156, 18, -436, function()
		Morph(M.ResetModel)
	end)
	Button(frame, "Reset everything", 156, 180, -436, function()
		Morph(M.ResetAll)
	end)
end

-- Scales the window, keeping its top-left corner where it is.
local function ScaleWindow(scale)
	if scale < MIN_SCALE then
		scale = MIN_SCALE
	elseif scale > MAX_SCALE then
		scale = MAX_SCALE
	end
	local old, left, top = frame:GetScale(), frame:GetLeft(), frame:GetTop()
	frame:SetScale(scale)
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * old / scale, top * old / scale)
	end
	Prefs().scale = scale
end

-- The corner grip: drag it to make the whole window bigger or smaller.
local function BuildGrip()
	local grip = CreateFrame("Button", "DmorphOctoResize", frame)
	grip:SetWidth(18)
	grip:SetHeight(18)
	grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	grip:EnableMouse(true)
	grip.dots = {}
	local spots = { { 2, 2 }, { 7, 2 }, { 12, 2 }, { 2, 7 }, { 7, 7 }, { 2, 12 } }
	for i = 1, table.getn(spots) do
		local dot = grip:CreateTexture(nil, "OVERLAY")
		dot:SetTexture(WHITE)
		dot:SetWidth(3)
		dot:SetHeight(3)
		dot:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -spots[i][1], spots[i][2])
		dot:SetVertexColor(C.lineHi[1], C.lineHi[2], C.lineHi[3])
		grip.dots[i] = dot
	end
	local function Tint(r, g, b)
		for i = 1, table.getn(grip.dots) do
			grip.dots[i]:SetVertexColor(r, g, b)
		end
	end
	grip:SetScript("OnEnter", function()
		Tint(C.accent[1], C.accent[2], C.accent[3])
		Tooltip(this, "Window size", "Drag to make the window bigger or smaller.")
	end)
	grip:SetScript("OnLeave", function()
		Tint(C.lineHi[1], C.lineHi[2], C.lineHi[3])
		GameTooltip:Hide()
	end)
	grip:SetScript("OnMouseDown", function()
		this.startX = GetCursorPosition()
		this.startScale = frame:GetScale()
	end)
	grip:SetScript("OnMouseUp", function()
		this.startX = nil
	end)
	grip:SetScript("OnUpdate", function()
		if this.startX then
			local x = GetCursorPosition()
			ScaleWindow(this.startScale + (x - this.startX) / (W * UIParent:GetEffectiveScale()))
		end
	end)
end

local function BuildTabs()
	for i = 1, table.getn(TABS) do
		local info = TABS[i]
		local tab = CreateFrame("Button", "DmorphOctoTab" .. string.gsub(info.text, " ", ""), frame)
		tab:SetHeight(26)
		Flat(tab, C.btn, C.line)
		tab.label = Font(tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"), 12)
		tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)
		tab.label:SetText(info.text)
		Hover(tab, 0.18)
		tab.key = info.key
		tab:SetScript("OnClick", function()
			PlaySound("igCharacterInfoTab")
			ShowTab(this.key)
		end)
		ui.tabs[info.key] = tab
		local page = CreateFrame("Frame", "DmorphOctoPage" .. info.text, frame)
		page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X, PAGE_Y)
		page:SetWidth(PAGE_W)
		page:SetHeight(PAGE_H)
		Flat(page, C.panel, C.line)
		page:Hide()
		ui.pages[info.key] = page
	end
	-- Each tab as wide as its name, the room left shared out evenly.
	local count, used = table.getn(TABS), 0
	for i = 1, count do
		used = used + ui.tabs[TABS[i].key].label:GetStringWidth()
	end
	local pad = math.floor((PAGE_W - (count - 1) * TAB_GAP - used) / count)
	-- Eleven tabs (2.29.0) may not fit at 12 pt: then a size smaller.
	if pad < 6 then
		used = 0
		for i = 1, count do
			local label = ui.tabs[TABS[i].key].label
			Font(label, 10)
			used = used + label:GetStringWidth()
		end
		pad = math.floor((PAGE_W - (count - 1) * TAB_GAP - used) / count)
	end
	local x = PAGE_X
	for i = 1, count do
		local tab = ui.tabs[TABS[i].key]
		local width = math.floor(tab.label:GetStringWidth() + pad)
		tab:SetWidth(width)
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -42)
		x = x + width + TAB_GAP
	end
	BuildModelsPage(ui.pages.models)
	BuildMountsPage(ui.pages.mounts)
	BuildFavouritesPage(ui.pages.favourites)
	BuildRacesPage(ui.pages.races)
	BuildGlowsPage(ui.pages.glows)
	P.BuildExtraPage(ui.pages.extra)
	BuildItemsPage(ui.pages.items)
	BuildSlutmogPage(ui.pages.slutmog)
	BuildSetsPage(ui.pages.sets)
	BuildWardrobePage(ui.pages.wardrobe)
	BuildWeatherPage(ui.pages.weather)
end

-- Sharing (Share.lua): whether others see your morph and you see theirs.
local function ShareMenu()
	local sharing, seeing = M.GetShareStatus()
	local options = {
		{ text = "Others see my morph", key = "share", checked = sharing },
		{ text = "I see their morphs", key = "see", checked = seeing },
	}
	OpenMenu(this, options, function(option)
		if option.key == "share" then
			SetStatus(M.SetSharing(not sharing))
		else
			SetStatus(M.SetSeeing(not seeing))
		end
	end, true)
end

-- Setup check (M.GetSetupReport): a footer button that says whether morphing
-- works, and a panel with each part DMorph uses and how to fix what doesn't.
local CHECK_COLOURS = { ok = { 0.2, 1, 0.6 }, bad = { 1, 0.33, 0.33 }, off = { 0.6, 0.6, 0.6 } }
local CHECK_WORDS = { ok = "OK", bad = "Not working", off = "Not running" }

local function UpdateSetupButton()
	if not ui.setupButton then
		return
	end
	-- The helper's version shows on the button: an old one needs the installer.
	local helper, wanted = M.GetHelperVersion()
	if not M.HasMorphAPI() then
		ui.setupButton:SetText("|cffff5555Setup: fix me|r")
	elseif helper and helper < wanted then
		ui.setupButton:SetText("|cffffcc00Old helper v" .. helper .. ": fix|r")
	elseif helper then
		ui.setupButton:SetText("|cff33ff99Setup OK|r |cffccccccHelper v" .. helper .. "|r")
	else
		ui.setupButton:SetText("|cff33ff99Setup OK|r |cff999999No helper|r")
	end
end

local function FillSetupPanel()
	local report = M.GetSetupReport()
	if M.HasMorphAPI() then
		ui.setupSummary:SetText("|cff33ff99Morphing works.|r The optional parts below add extras.")
	else
		ui.setupSummary:SetText("|cffff5555Morphing doesn't work yet.|r Follow the VanillaHelpers line, then press Check again.")
	end
	for i = 1, table.getn(ui.setupRows) do
		local row, entry = ui.setupRows[i], report[i]
		if entry then
			local colour = CHECK_COLOURS[entry.state]
			row.name:SetText(entry.name)
			row.state:SetText(CHECK_WORDS[entry.state])
			row.state:SetTextColor(colour[1], colour[2], colour[3])
			row.text:SetText(entry.text)
		else
			row.name:SetText("")
			row.state:SetText("")
			row.text:SetText("")
		end
	end
	UpdateSetupButton()
end

local function ShowSetupPanel()
	FillSetupPanel()
	ui.setupPanel:Show()
end

local function BuildSetupPanel()
	local panel = CreateFrame("Frame", "DmorphOctoSetup", frame)
	panel:Hide()
	panel:SetWidth(580)
	panel:SetHeight(340)
	panel:SetPoint("CENTER", frame, "CENTER", 0, 10)
	panel:SetFrameLevel(frame:GetFrameLevel() + 30)
	panel:EnableMouse(true)
	Flat(panel, C.panel, C.accent)
	Label(panel, "DMorph setup check", "GameFontNormalLarge", 16, -14)
	ui.setupSummary = Label(panel, "", "GameFontHighlight", 16, -40, "DmorphOctoSetupSummary")
	ui.setupRows = {}
	for i = 1, 4 do
		local y = -68 - (i - 1) * 60
		local row = {}
		row.name = Label(panel, "", "GameFontNormal", 16, y, "DmorphOctoSetupName" .. i)
		row.state = Label(panel, "", "GameFontHighlight", 140, y, "DmorphOctoSetupState" .. i)
		row.text = Label(panel, "", "GameFontHighlightSmall", 16, y - 18, "DmorphOctoSetupText" .. i)
		row.text:SetWidth(548)
		row.text:SetHeight(38)
		row.text:SetJustifyV("TOP")
		ui.setupRows[i] = row
	end
	Button(panel, "Check again", 110, 16, -306, FillSetupPanel, "DmorphOctoSetupRecheck")
	Label(panel, "/dmorph check prints this in chat.", "GameFontDisableSmall", 140, -311)
	Button(panel, "Close", 80, 484, -306, function()
		ui.setupPanel:Hide()
	end, "DmorphOctoSetupClose")
	ui.setupPanel = panel
end

-- The window closes. (Outside Build: Lua 5.0 allows 32 upvalues a function.)
function P.OnWindowHide()
	PlaySound("igCharacterInfoClose")
	P.EndGlowPreview()
	-- The try-on boxes load your character afresh next time.
	for _, box in pairs(ui.boxes) do
		box.loaded, box.dressed = nil, nil
	end
	ui.menu:Hide()
	-- A click still waiting at the gate is applied now.
	local nextCall = ui.gateNext
	ui.gateBusy, ui.gateNext = nil, nil
	if nextCall then
		Morph(nextCall[1], nextCall[2], nextCall[3])
	end
end

local function Build()
	frame = CreateFrame("Frame", "DmorphOctoFrame", UIParent)
	frame:Hide()
	frame:SetWidth(W)
	frame:SetHeight(H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetScale(Prefs().scale)
	Flat(frame, C.bg, C.deep)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function()
		this:StartMoving()
	end)
	frame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
	end)
	frame:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen")
		UpdateSetupButton()
		if not M.HasMorphAPI() then
			-- Nothing can morph: show what's wrong and how to fix it straight away.
			SetStatus(false, M.MissingAPI())
			ShowSetupPanel()
		end
		ShowTab(currentTab)
		ShowArt()
		UpdatePlate()
		RequestPreview()
	end)
	frame:SetScript("OnHide", P.OnWindowHide)
	frame:SetScript("OnUpdate", function()
		this.sincePoll = (this.sincePoll or 0) + arg1
		if this.sincePoll > 1 then
			this.sincePoll = 0
			Poll()
		end
	end)
	-- Shapeshifts, zoning and the like rebuild your model.
	frame:RegisterEvent("UNIT_MODEL_CHANGED")
	frame:SetScript("OnEvent", function()
		if arg1 == "player" then
			RequestPreview()
		end
	end)
	-- Escape closes the window.
	table.insert(UISpecialFrames, "DmorphOctoFrame")

	-- The title bar: a purple strip, the name, a flat close button.
	local bar = frame:CreateTexture(nil, "BORDER")
	bar:SetTexture(WHITE)
	bar:SetGradientAlpha("HORIZONTAL", C.deep[1], C.deep[2], C.deep[3], 1, C.bg[1], C.bg[2], C.bg[3], 1)
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
	bar:SetHeight(32)
	local line = frame:CreateTexture(nil, "ARTWORK")
	line:SetTexture(WHITE)
	line:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.8)
	line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, 0)
	line:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, 0)
	line:SetHeight(1)
	local title = Font(frame:CreateFontString("DmorphOctoTitle", "OVERLAY", "GameFontNormal"), 16, C.text)
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -9)
	title:SetText("|cffb46bffD|rMorph  |cff9b98a8for OctoWoW|r")
	local close = CreateFrame("Button", "DmorphOctoFrameClose", frame)
	close:SetWidth(22)
	close:SetHeight(22)
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -5)
	FlatButton(close, "x", 13)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	ui.searchTimer = NewTimer()
	ui.previewTimer = NewTimer()
	ui.revealTimer = NewTimer()
	ui.gateTimer = NewTimer()
	ui.glowTimer = NewTimer()
	-- ClassicAPI's Model:SetDisplayInfo shows creatures by display ID.
	local probe = CreateFrame("Model", nil, frame)
	ui.canPreview = type(probe.SetDisplayInfo) == "function"
	probe:Hide()
	local player = CreateFrame("PlayerModel", nil, frame)
	ui.playerViews = ui.canPreview and type(player.SetDisplayInfo) == "function" or nil
	player:Hide()
	ui.menu = BuildMenu()

	BuildStage()
	BuildTabs()
	BuildGrip()

	ui.status = Label(frame, "", "GameFontHighlightSmall", 20, -466, "DmorphOctoFrameStatus")
	ui.status:SetWidth(W - 40)
	ui.status:SetHeight(26)
	-- The footer: a thin line, setup, a hint, sharing, the version.
	local foot = frame:CreateTexture(nil, "ARTWORK")
	foot:SetTexture(WHITE)
	foot:SetVertexColor(C.line[1], C.line[2], C.line[3], 1)
	foot:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -494)
	foot:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -494)
	foot:SetHeight(1)
	ui.setupButton = Button(frame, "", 160, 18, -502, ShowSetupPanel, "DmorphOctoSetupButton")
	ui.setupButton:SetScript("OnEnter", function()
		local helper, wanted = M.GetHelperVersion()
		local line = "DmorphHelper: not running (optional)."
		if helper then
			line = "DmorphHelper: v" .. helper .. " running, v" .. wanted .. " comes with this DMorph."
		end
		Tooltip(this, "Setup check", "Whether VanillaHelpers and the optional client mods are running,",
			"and how to fix what isn't.", line)
	end)
	ui.setupButton:SetScript("OnLeave", HideTooltip)
	UpdateSetupButton()
	Label(frame, "DMorph users see each other's morphs. /dmorph help: commands.",
		"GameFontDisableSmall", 190, -508)
	BuildSetupPanel()
	local share = Button(frame, "Sharing", 80, W - 200, -502, ShareMenu, "DmorphOctoShare")
	share:SetScript("OnEnter", function()
		local _, _, known, morphed = M.GetShareStatus()
		Tooltip(this, "Sharing with DMorph users", "Who sees whose morph. Only friendly players can be morphed.",
			"DMorph users seen: " .. known .. " (" .. morphed .. " morphed).")
	end)
	share:SetScript("OnLeave", HideTooltip)
	local version = Font(frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 10, C.dim)
	version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -508)
	version:SetText("v" .. M.VERSION)
end

function M.ToggleUI()
	if not frame then
		Build()
	end
	if frame:IsVisible() then
		frame:Hide()
	else
		frame:Show()
	end
end

M.RegisterListener(RefreshAll)

-- /dmorph frametest [displayID] (2.21.6, simplified in 2.21.7): one display
-- five ways, for an in-game check of how this client draws a framed model.
-- The first run (19 Oct) showed that with a camera set, position and facing
-- are ignored. Now: A the full-body camera (type 1), B the portrait camera,
-- C / D the full-body camera zoomed out / in (scale 0.7 / 1.4), E no camera.
-- Top row facing 0, bottom row facing a quarter turn.
function P.FrameTest(args)
	local display = M.ParseID(args[1] or "") or 63568
	if not ui.canPreview then
		DEFAULT_CHAT_FRAME:AddMessage("DMorph frame test: 3D previews need ClassicAPI.")
		return
	end
	local test = DmorphOctoFrameTest
	if not test then
		test = CreateFrame("Frame", "DmorphOctoFrameTest", UIParent)
		test:SetFrameStrata("FULLSCREEN_DIALOG")
		test:SetWidth(5 * 150 + 20)
		test:SetHeight(2 * 170 + 50)
		test:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		Flat(test, C.bg, C.accent)
		test:EnableMouse(true)
		test.title = Font(test:CreateFontString(nil, "OVERLAY"), 13, C.gold)
		test.title:SetPoint("TOPLEFT", test, "TOPLEFT", 10, -8)
		local close = Button(test, "Close", 60, 5 * 150 + 20 - 70, -6, function()
			DmorphOctoFrameTest:Hide()
		end)
		close:SetHeight(18)
		test.cells = {}
		for row = 1, 2 do
			for col = 1, 5 do
				local cell = CreateFrame("Frame", nil, test)
				cell:SetWidth(144)
				cell:SetHeight(160)
				cell:SetPoint("TOPLEFT", test, "TOPLEFT", 10 + (col - 1) * 150, -36 - (row - 1) * 170)
				Flat(cell, C.card, C.line)
				local model = CreateFrame("Model", nil, cell)
				model:SetPoint("TOPLEFT", cell, "TOPLEFT", 2, -2)
				model:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -2, 16)
				local label = Font(cell:CreateFontString(nil, "OVERLAY"), 12, C.accent)
				label:SetPoint("BOTTOM", cell, "BOTTOM", 0, 2)
				label:SetText(string.sub("ABCDE", col, col) .. row)
				table.insert(test.cells, { model = model, col = col, row = row })
			end
		end
		local SCALES = { 1, 1, 0.7, 1.4, 1 }
		local CAMERAS = { 1, 0, 1, 1 }
		test:SetScript("OnUpdate", function()
			for i = 1, table.getn(this.cells) do
				local c = this.cells[i]
				if CAMERAS[c.col] then
					pcall(c.model.SetCamera, c.model, CAMERAS[c.col])
				end
				c.model:SetModelScale(SCALES[c.col])
				c.model:SetFacing(c.row == 2 and 1.5708 or 0)
			end
		end)
	end
	test.title:SetText("DMorph frame test: display " .. display .. " (" .. (M.GetDisplayName(display) or "?") .. ")")
	for i = 1, table.getn(test.cells) do
		local m = test.cells[i].model
		pcall(m.ClearModel, m)
		m:SetDisplayInfo(display)
		pcall(m.SetLight, m, 1, 0, 0, -0.7, -0.7, 0.7, 1, 1, 1, 0.8, 1, 1, 1)
	end
	test:Show()
end
M.commands.frametest = P.FrameTest

-- Minimap button ------------------------------------------------------------------

local function PlaceMinimapButton(button)
	local pos = M.GetAccount().minimap
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", pos.x, pos.y)
end

-- Keeps the button on the minimap's edge, pointing at the cursor. Plain
-- vectors instead of angles: the 1.12 trig functions' units vary by build.
local function DragMinimapButton()
	local x, y = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	local cx, cy = Minimap:GetCenter()
	x, y = x / scale - cx, y / scale - cy
	local length = math.sqrt(x * x + y * y)
	if length > 0 then
		local pos = M.GetAccount().minimap
		pos.x, pos.y = x / length * 80, y / length * 80
		PlaceMinimapButton(this)
	end
end

local function CreateMinimapButton()
	local account = M.GetAccount()
	local pos = account.minimap
	if type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then
		account.minimap = { x = -75, y = -27 }
	end
	local button = CreateFrame("Button", "DmorphOctoMinimapButton", Minimap)
	button:SetWidth(31)
	button:SetHeight(31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetTexture("Interface\\Icons\\Spell_Nature_Polymorph")
	icon:SetWidth(20)
	icon:SetHeight(20)
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -5)
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetWidth(53)
	border:SetHeight(53)
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	highlight:SetBlendMode("ADD")
	highlight:SetAllPoints(button)
	button:SetScript("OnClick", M.ToggleUI)
	button:SetScript("OnDragStart", function()
		this:SetScript("OnUpdate", DragMinimapButton)
	end)
	button:SetScript("OnDragStop", function()
		this:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_LEFT")
		GameTooltip:SetText("DMorph |cff33ff99(OctoWoW)|r")
		GameTooltip:AddLine("Click to open the morph window.", 1, 1, 1)
		GameTooltip:AddLine("Drag to move this button.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	PlaceMinimapButton(button)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
	if not DmorphOctoMinimapButton then
		CreateMinimapButton()
	end
end)
