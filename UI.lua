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

local W, H = 846, 530
local ART_W, ART_H, PLATE_H = 318, 383, 44
local PAGE_X, PAGE_Y, PAGE_W, PAGE_H = 352, -70, 474, 382
local ROW_HEIGHT, LIST_ROWS, LIST_WIDTH = 18, 15, 436
local TILE_W, TILE_H, TILE_GAP, GRID_COLS = 110, 132, 6, 4
-- ClassicAPI dresses at most 8 NPC preview models at a time, so 8 tiles.
local PAGE_SIZE = 8
-- How long a model loads out of sight before it's shown.
local REVEAL = 0.45
-- After a morph the game rebuilds your character; a second change before it
-- has finished can mix the two looks' textures. Clicks closer than this wait.
local GATE = 0.35
local MIN_SCALE, MAX_SCALE = 0.6, 1.6
-- Zooming the character: how far it comes towards you (model units, about a
-- yard each), per mouse wheel notch and at most.
local ZOOM_STEP, ZOOM_MIN, ZOOM_MAX = 0.3, -1.5, 3
local MENU_ROWS, MENU_WIDTH = 20, 170
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
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
local KIND_COLORS = { [0] = { 1, 1, 1 }, [1] = { 0.62, 0.76, 0.92 }, [2] = { 0.45, 1, 0.6 }, [3] = { 0.45, 1, 0.6 } }
local KIND_NOTES = {
	[0] = "A creature from the world database.",
	[1] = "No creature has this look, so it's named after its model file.",
	[2] = "New in OctoWoW: a creature from Turtle WoW's database.",
	[3] = "New in OctoWoW, named after its model file.",
}

local TABS = {
	{ key = "models", text = "Models" },
	{ key = "mounts", text = "Mounts" },
	{ key = "favourites", text = "Favourites" },
	{ key = "races", text = "Races" },
	{ key = "glows", text = "Glows" },
	{ key = "items", text = "Items" },
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
	creator = {}, creatorRows = {}, mountRows = {}, glowSlots = {},
}
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

-- Widget helpers --------------------------------------------------------------

local function Label(parent, text, font, x, y, name)
	local label = parent:CreateFontString(name, "OVERLAY", font or "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function Button(parent, text, width, x, y, onClick, name)
	buttonCount = buttonCount + 1
	local button = CreateFrame("Button", name or ("DmorphOctoButton" .. buttonCount), parent, "UIPanelButtonTemplate")
	button:SetWidth(width)
	button:SetHeight(22)
	button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local function EditBox(parent, name, width, x, y, maxLetters)
	local box = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
	box:SetWidth(width)
	box:SetHeight(20)
	-- The template's left border sits 5px outside the box.
	box:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 5, y)
	box:SetAutoFocus(false)
	box:SetMaxLetters(maxLetters or 40)
	box:SetScript("OnEscapePressed", function()
		this:ClearFocus()
	end)
	return box
end

-- A flat panel: a solid colour inside a thin border.
local function Panel(f, r, g, b)
	f:SetBackdrop({
		bgFile = WHITE, edgeFile = EDGE, tile = false, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(r, g, b, 1)
	f:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
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
				row.label:SetTextColor(1, 0.82, 0)
				row:Disable()
			else
				row.label:SetTextColor(1, 1, 1)
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
	Panel(menu, 0.06, 0.06, 0.07)
	menu:SetBackdropBorderColor(0.8, 0.65, 0.3, 1)
	menu.rows = {}
	for i = 1, MENU_ROWS do
		local row = CreateFrame("Button", "DmorphOctoMenuRow" .. i, menu)
		row:SetFrameLevel(menu:GetFrameLevel() + 1)
		row:SetWidth(MENU_WIDTH - 12)
		row:SetHeight(18)
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * 18)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")
		highlight:SetAllPoints(row)
		row.check = row:CreateTexture(nil, "ARTWORK")
		row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row.check:SetWidth(16)
		row.check:SetHeight(16)
		row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
	-- A dark track behind the scroll bar, so it reads as one.
	local track = scroll:CreateTexture(nil, "BACKGROUND")
	track:SetTexture(0, 0, 0, 0.45)
	track:SetPoint("TOPLEFT", getglobal(name .. "ScrollBar"), "TOPLEFT", 2, 16)
	track:SetPoint("BOTTOMRIGHT", getglobal(name .. "ScrollBar"), "BOTTOMRIGHT", -2, -16)

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
				row.text:SetTextColor(1, 1, 1)
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
			stripe:SetTexture(1, 1, 1, 0.035)
			stripe:SetAllPoints(row)
		end
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")
		highlight:SetAllPoints(row)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
		row.text:SetWidth(width - infoWidth - 14)
		row.text:SetHeight(ROW_HEIGHT)
		row.text:SetJustifyH("LEFT")
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
			ui.card:Hide()
			if ui.itemCard then
				ui.itemCard:Hide()
			end
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
			row:SetScript("OnLeave", function()
				ui.card:Hide()
				if ui.itemCard then
					ui.itemCard:Hide()
				end
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
-- an opaque layer, and moves up to `high` once REVEAL has passed.
local function NewView(parent, name, low, high)
	local model = CreateFrame("Model", name, parent)
	model:SetFrameLevel(low)
	return { model = model, low = low, high = high, facing = 0 }
end

local function LoadView(view, displayID)
	local model = view.model
	view.displayID = displayID
	view.facing = 0
	view.wait = REVEAL
	model:SetFrameLevel(view.low)
	-- Drop the old model and its skins first, so none carry over to the new one.
	pcall(model.ClearModel, model)
	model:SetDisplayInfo(displayID)
	-- Camera 0 is the model's portrait camera; a Model has no light of its own.
	pcall(model.SetCamera, model, 0)
	pcall(model.SetLight, model, 1, 0, 0, -0.7, -0.7, 0.7, 1, 1, 1, 0.8, 1, 1, 1)
	model:SetFacing(0)
end

-- Per frame: reveal a loaded model, and turn it slowly while `spin` is set.
-- (Plain Model frames turn with SetFacing; SetRotation is PlayerModel's.)
local function TickView(view, elapsed, spin)
	if view.wait then
		view.wait = view.wait - elapsed
		if view.wait <= 0 then
			view.wait = nil
			view.model:SetFrameLevel(view.high)
		end
	end
	if spin and view.displayID then
		view.facing = view.facing + elapsed * 1.6
		view.model:SetFacing(view.facing)
	end
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
	if count == 1 then
		info = info .. " - 1 item morphed"
	elseif count > 1 then
		info = info .. " - " .. count .. " items morphed"
	end
	if state.mount then
		info = info .. " - mount morphed"
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
		if itemID then
			local ok, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, itemID)
			if not ok then
				texture = nil
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
	if ui.page > 1 then
		ui.prevPage:Enable()
	else
		ui.prevPage:Disable()
	end
	if ui.page < pages then
		ui.nextPage:Enable()
	else
		ui.nextPage:Disable()
	end
end

-- The display ID you're morphed into, if any.
local function TargetDisplay()
	return M.GetState().display
end

local function TileBorder(tile)
	if tile.hover then
		tile:SetBackdropBorderColor(1, 1, 1, 1)
	elseif tile.displayID and tile.displayID == TargetDisplay() then
		tile:SetBackdropBorderColor(1, 0.82, 0, 1)
	else
		tile:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
	end
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
		-- The list's preview card may have taken one of ClassicAPI's 8 NPC
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
	Panel(tile, 0.07, 0.07, 0.08)
	local base = tile:GetFrameLevel()
	-- Levels: model while loading (+1) < cover (+2) < model once loaded (+3) < text (+4).
	tile.view = NewView(tile, "DmorphOctoTile" .. i .. "Model", base + 1, base + 3)
	tile.view.model:SetPoint("TOPLEFT", tile, "TOPLEFT", 4, -4)
	tile.view.model:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -4, 30)
	local cover = Layer(tile, 2)
	cover:SetAllPoints(tile.view.model)
	Gradient(cover, "BACKGROUND", 0.05, 0.05, 0.06, 1, 0.12, 0.11, 0.09, 1):SetAllPoints(cover)
	local text = Layer(tile, 4)
	text:SetAllPoints(tile)
	tile.title = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	tile.title:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 5, 4)
	tile.title:SetWidth(TILE_W - 10)
	tile.title:SetHeight(26)
	tile.title:SetJustifyH("CENTER")
	tile.idText = text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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

-- The floating preview next to a hovered row in list view.
local function BuildCard()
	local card = CreateFrame("Frame", "DmorphOctoPreviewCard", UIParent)
	card:Hide()
	card:SetFrameStrata("TOOLTIP")
	card:SetWidth(160)
	card:SetHeight(196)
	card:SetClampedToScreen(true)
	Panel(card, 0.06, 0.06, 0.07)
	local base = card:GetFrameLevel()
	card.view = NewView(card, "DmorphOctoPreviewCardModel", base + 1, base + 3)
	card.view.model:SetPoint("TOPLEFT", card, "TOPLEFT", 5, -5)
	card.view.model:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -5, 46)
	local cover = Layer(card, 2)
	cover:SetAllPoints(card.view.model)
	Gradient(cover, "BACKGROUND", 0.05, 0.05, 0.06, 1, 0.12, 0.11, 0.09, 1):SetAllPoints(cover)
	local text = Layer(card, 4)
	text:SetAllPoints(card)
	card.title = text:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.title:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 6, 20)
	card.title:SetWidth(148)
	card.title:SetHeight(24)
	card.title:SetJustifyH("CENTER")
	card.idText = text:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.idText:SetPoint("BOTTOM", card, "BOTTOM", 0, 8)
	card:SetScript("OnUpdate", function()
		TickView(this.view, arg1, true)
	end)
	return card
end

-- The preview card next to a list row, for a display ID: on its right, or
-- with `left` set on its left.
local function ShowCardFor(row, displayID, name, color, left)
	if not (ui.canPreview and displayID) then
		return
	end
	local card = ui.card
	card:ClearAllPoints()
	if left then
		card:SetPoint("RIGHT", row, "LEFT", -12, 0)
	else
		card:SetPoint("LEFT", row, "RIGHT", 50, 0)
	end
	card.title:SetText(name)
	card.title:SetTextColor(color[1], color[2], color[3])
	card.idText:SetText("Display ID " .. displayID)
	card:Show()
	if card.view.displayID ~= displayID then
		LoadView(card.view, displayID)
	end
end

-- The try-on card next to an item or set row: your character wearing it, in
-- the Dressing Room's own model (TryOn). The game can only put on items it
-- knows: one it hasn't seen yet is asked for (ClassicAPI) and goes on when
-- it arrives.
local function TryOnAll(card)
	local missing = false
	for i = 1, table.getn(card.items) do
		local id = card.items[i]
		if not card.on[id] then
			if GetItemInfo(id) then
				pcall(card.model.TryOn, card.model, id)
				card.on[id] = true
			else
				missing = true
				if not card.asked[id] and type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
					card.asked[id] = true
					pcall(C_Item.RequestLoadItemDataByID, id)
				end
			end
		end
	end
	card.pending = missing or nil
	if missing then
		card.status:SetText("Loading from the server...")
	else
		card.status:SetText("")
	end
end

local function BuildItemCard()
	local card = CreateFrame("Frame", "DmorphOctoItemCard", UIParent)
	card:Hide()
	card:SetFrameStrata("TOOLTIP")
	card:SetWidth(190)
	card:SetHeight(260)
	card:SetClampedToScreen(true)
	Panel(card, 0.06, 0.06, 0.07)
	card.base = card:GetFrameLevel()
	-- It loads below the cover and is raised once loaded (no white flash).
	card.model = CreateFrame("DressUpModel", "DmorphOctoItemCardModel", card)
	card.model:SetFrameLevel(card.base + 1)
	card.model:SetPoint("TOPLEFT", card, "TOPLEFT", 5, -5)
	card.model:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -5, 46)
	local cover = Layer(card, 2)
	cover:SetAllPoints(card.model)
	Gradient(cover, "BACKGROUND", 0.05, 0.05, 0.06, 1, 0.12, 0.11, 0.09, 1):SetAllPoints(cover)
	local text = Layer(card, 4)
	text:SetAllPoints(card)
	card.title = text:CreateFontString("DmorphOctoItemCardTitle", "OVERLAY", "GameFontNormalSmall")
	card.title:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 6, 20)
	card.title:SetWidth(178)
	card.title:SetHeight(24)
	card.title:SetJustifyH("CENTER")
	card.idText = text:CreateFontString("DmorphOctoItemCardInfo", "OVERLAY", "GameFontDisableSmall")
	card.idText:SetPoint("BOTTOM", card, "BOTTOM", 0, 8)
	card.status = text:CreateFontString("DmorphOctoItemCardStatus", "OVERLAY", "GameFontHighlightSmall")
	card.status:SetPoint("CENTER", card.model, "CENTER", 0, 0)
	card.items, card.on, card.asked = {}, {}, {}
	card:SetScript("OnUpdate", function()
		if this.wait then
			this.wait = this.wait - arg1
			if this.wait <= 0 then
				this.wait = nil
				this.model:SetFrameLevel(this.base + 3)
			end
		end
		this.rotation = (this.rotation or 0) + arg1 * 0.8
		this.model:SetRotation(this.rotation)
		if this.pending then
			this.retry = (this.retry or 0) - arg1
			if this.retry <= 0 then
				this.retry = 0.25
				TryOnAll(this)
			end
		end
	end)
	return card
end

-- Shows the card on the left of row, with items (item IDs) tried on.
local function ShowItemCard(row, items, title, r, g, b, info)
	local card = ui.itemCard
	card:ClearAllPoints()
	card:SetPoint("RIGHT", row, "LEFT", -12, 0)
	card.title:SetText(title)
	card.title:SetTextColor(r, g, b)
	card.idText:SetText(info)
	if not card.loaded then
		-- Your character as it is now (once per opening of the window).
		card.loaded = true
		card.model:SetFrameLevel(card.base + 1)
		card.model:SetUnit("player")
		card.wait = REVEAL
	end
	card.model:Dress()
	card.items, card.on, card.rotation = items, {}, 0
	card:Show()
	TryOnAll(card)
end

local function HideCards()
	ui.card:Hide()
	if ui.itemCard then
		ui.itemCard:Hide()
	end
end

local function ShowCard(index, row)
	local entry = ui.modelResult[index]
	if entry then
		local catalog = M.GetCreatureCatalog()
		ShowCardFor(row, catalog.ids[entry], catalog.names[entry], KindColor(catalog.kind[entry]))
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

local function BuildModelsPage(page)
	local prefs = Prefs()
	Label(page, "Search:", nil, 10, -12)
	ui.modelSearch = EditBox(page, "DmorphOctoModelSearch", 146, 58, -8)
	ui.modelSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterModels)
	end)
	ui.modelSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterModels()
	end)
	ui.modelFilter = Button(page, M.MODEL_FILTERS[prefs.filter].text, 136, 216, -7, ModelFilterMenu, "DmorphOctoModelFilter")
	ui.modelFilter:SetScript("OnEnter", function()
		Tooltip(this, "Which models to list", "Creatures, bosses, rare creatures, mounts, models no creature uses,",
			"or only the ones OctoWoW added.")
	end)
	ui.modelFilter:SetScript("OnLeave", HideTooltip)
	ui.viewButton = Button(page, "List view", 106, 358, -7, function()
		SetListMode(not ui.listMode)
	end, "DmorphOctoModelView")

	SortButton(page, "DmorphOctoModelSort", 8, -33, "sortModels", FilterModels)

	-- Pager, next to the switches.
	local function PageButton(dir, x)
		local button = CreateFrame("Button", "DmorphOcto" .. dir .. "Page", page)
		button:SetWidth(24)
		button:SetHeight(24)
		button:SetPoint("TOPLEFT", page, "TOPLEFT", x, -32)
		button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Up")
		button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Down")
		button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. dir .. "Page-Disabled")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
		return button
	end
	ui.prevPage = PageButton("Prev", 222)
	ui.prevPage:SetScript("OnClick", function()
		TurnPage(-1)
	end)
	ui.nextPage = PageButton("Next", PAGE_W - 32)
	ui.nextPage:SetScript("OnClick", function()
		TurnPage(1)
	end)
	ui.pagerText = page:CreateFontString("DmorphOctoPagerText", "OVERLAY", "GameFontHighlightSmall")
	ui.pagerText:SetPoint("TOP", page, "TOPLEFT", 345, -39)

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

	-- Or a list.
	ui.listBox = CreateFrame("Frame", "DmorphOctoModelListBox", page)
	ui.listBox:SetAllPoints(page)
	ui.modelList = List(ui.listBox, "DmorphOctoModelList", 8, -60, 60, function(row, index)
		local catalog = M.GetCreatureCatalog()
		local i = ui.modelResult[index]
		local color = KindColor(catalog.kind[i])
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(color[1], color[2], color[3])
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == TargetDisplay() then
			row:LockHighlight()
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
	end, ShowCard)

	-- Any display ID, including ones no list has.
	local y = -346
	Label(page, "Display ID:", nil, 10, y - 5)
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
	Button(page, "<", 26, 158, y, function()
		Apply(-1)
	end)
	Button(page, ">", 26, 186, y, function()
		Apply(1)
	end)
	Button(page, "Morph", 70, 216, y, function()
		Apply(0)
	end)
	Label(page, "< and > step through every ID.", "GameFontDisableSmall", 294, y - 6)

	if not ui.canPreview then
		ui.viewButton:Hide()
		Label(page, "3D previews need ClassicAPI.", "GameFontDisableSmall", 362, -13)
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

local function BuildFavouritesPage(page)
	local prefs = Prefs()
	Label(page, "Search:", nil, 10, -12)
	ui.favSearch = EditBox(page, "DmorphOctoFavSearch", 140, 58, -8)
	ui.favSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterFavourites)
	end)
	ui.favSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterFavourites()
	end)
	ui.favFilter = Button(page, FAV_FILTERS[prefs.favFilter].text, 150, 212, -7, FavouriteMenu, "DmorphOctoFavFilter")
	SortButton(page, "DmorphOctoFavSort", 368, -7, "sortFavs", FilterFavourites)

	ui.favList = List(page, "DmorphOctoFavList", 8, -36, 90, function(row, index)
		local fav = ui.favResult[index]
		local state = M.GetState()
		row.text:SetText(fav.name)
		if fav.mount then
			row.text:SetTextColor(MOUNT_COLOR[1], MOUNT_COLOR[2], MOUNT_COLOR[3])
			row.info:SetText("Mount " .. fav.id)
			if state.mount == fav.id then
				row:LockHighlight()
			end
		else
			row.info:SetText("Model " .. fav.id)
			if state.display == fav.id then
				row:LockHighlight()
			end
		end
	end, function(index, button)
		local fav = ui.favResult[index]
		if button == "RightButton" then
			SetStatus(M.ToggleFavourite(fav.id, fav.mount))
			ui.card:Hide()
			FilterFavourites(true)
		elseif fav.mount then
			Morph(M.SetMount, fav.id)
		else
			Morph(M.SetDisplay, fav.id)
		end
	end, function(index, row)
		local fav = ui.favResult[index]
		if fav then
			ShowCardFor(row, fav.id, fav.name, fav.mount and MOUNT_COLOR or KIND_COLORS[0])
		end
	end)
	ui.favCount = Label(page, "", "GameFontDisableSmall", 10, -314, "DmorphOctoFavCount")
	ui.favEmpty = Label(page, "No favourites yet. Right-click a model in the Models tab to star it.",
		"GameFontDisableSmall", 14, -44)
	Label(page, "Click to wear it. Right-click to take it off the list.", "GameFontDisableSmall", 10, -340)
	Label(page, "Right-click a model (Models tab) or a mount skin (Mounts tab) to star it.",
		"GameFontDisableSmall", 10, -354)
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
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
	highlight:SetBlendMode("ADD")
	highlight:SetAllPoints(button)
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
			button:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + (race - 1) * 45, -30 - gender * 40)
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
		Button(page, "<", 26, 170, y, function()
			StepFeature(this.feature, -1)
		end, "DmorphOctoCreatorPrev" .. f).feature = f
		row.value = page:CreateFontString("DmorphOctoCreatorValue" .. f, "OVERLAY", "GameFontHighlight")
		row.value:SetPoint("TOP", page, "TOPLEFT", 270, y - 4)
		Button(page, ">", 26, 344, y, function()
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

-- The list leaves room on its right for the "Your skin" box.
local MOUNT_LIST_W = 290

local MOUNT_FILTERS = {
	{ text = "Mount models", tag = "mount" },
	{ text = "All models" },
	{ text = "New in OctoWoW", kinds = { [2] = true, [3] = true } },
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
	if not pos then
		ui.mountList.Refresh()
		return
	end
	local top = ui.mountList.GetOffset() + 1
	if pos < top or pos > top + LIST_ROWS - 1 then
		ui.mountList.ScrollTo(pos - math.floor(LIST_ROWS / 2))
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
	local panel, chosen = ui.mountPanel, MountPick()
	panel.target:SetText("For: " .. target)
	if chosen then
		panel.title:SetText(MountName(chosen))
		panel.idText:SetText("Display ID " .. chosen)
	else
		panel.title:SetText("No skin")
		panel.idText:SetText("Your mount looks as usual.")
	end
	if not chosen then
		panel.view.displayID = nil
		panel.view.wait = nil
		panel.view.model:SetFrameLevel(panel.view.low)
	elseif ui.canPreview and panel.view.displayID ~= chosen then
		LoadView(panel.view, chosen)
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

-- An up or down arrow like a scroll bar's.
local function ArrowButton(parent, name, direction, onClick, title, line)
	local button = CreateFrame("Button", name, parent)
	button:SetWidth(30)
	button:SetHeight(30)
	local file = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. direction .. "Button-"
	button:SetNormalTexture(file .. "Up")
	button:SetPushedTexture(file .. "Down")
	button:SetHighlightTexture(file .. "Highlight")
	button:SetScript("OnClick", onClick)
	button:SetScript("OnEnter", function()
		Tooltip(this, title, line)
	end)
	button:SetScript("OnLeave", HideTooltip)
	return button
end

-- The box beside the list: the skin you have on, turning, with arrows to put
-- on the previous or next model in the list.
local function BuildMountPanel(page)
	local width = PAGE_W - MOUNT_LIST_W - 40
	local panel = CreateFrame("Frame", "DmorphOctoMountPanel", page)
	panel:SetPoint("TOPLEFT", page, "TOPLEFT", MOUNT_LIST_W + 32, -82)
	panel:SetWidth(width)
	panel:SetHeight(LIST_ROWS * ROW_HEIGHT)
	Panel(panel, 0.06, 0.06, 0.07)
	local base = panel:GetFrameLevel()
	panel.view = NewView(panel, "DmorphOctoMountPanelModel", base + 1, base + 3)
	panel.view.model:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -24)
	panel.view.model:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -5, 96)
	local cover = Layer(panel, 2)
	cover:SetAllPoints(panel.view.model)
	Gradient(cover, "BACKGROUND", 0.05, 0.05, 0.06, 1, 0.12, 0.11, 0.09, 1):SetAllPoints(cover)
	local text = Layer(panel, 4)
	text:SetAllPoints(panel)
	local heading = text:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOP", panel, "TOP", 0, -7)
	heading:SetText("Your skin")
	panel.title = text:CreateFontString("DmorphOctoMountSkinName", "OVERLAY", "GameFontHighlight")
	panel.title:SetPoint("BOTTOM", panel, "BOTTOM", 0, 68)
	panel.title:SetWidth(width - 10)
	panel.title:SetHeight(26)
	panel.title:SetTextColor(1, 0.82, 0)
	panel.idText = text:CreateFontString("DmorphOctoMountSkinID", "OVERLAY", "GameFontDisableSmall")
	panel.idText:SetPoint("BOTTOM", panel, "BOTTOM", 0, 56)
	panel.idText:SetWidth(width - 10)
	panel.target = text:CreateFontString("DmorphOctoMountSkinFor", "OVERLAY", "GameFontHighlightSmall")
	panel.target:SetPoint("BOTTOM", panel, "BOTTOM", 0, 42)
	panel.target:SetWidth(width - 10)
	panel:SetScript("OnUpdate", function()
		TickView(this.view, arg1, true)
	end)
	ui.mountPanel = panel

	local up = ArrowButton(text, "DmorphOctoMountPrev", "Up", function()
		StepMount(-1)
	end, "Previous model", "Puts on the model above yours in the list.")
	up:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 6)
	local down = ArrowButton(text, "DmorphOctoMountNext", "Down", function()
		StepMount(1)
	end, "Next model", "Puts on the model below yours in the list.")
	down:SetPoint("BOTTOMLEFT", panel, "BOTTOM", 4, 6)
end

local function BuildMountsPage(page)
	local prefs = Prefs()
	if not MOUNT_FILTERS[prefs.mountFilter] then
		prefs.mountFilter = 1
	end
	Label(page, "Skin for:", "GameFontNormal", 10, -12)
	ui.mountForButton = Button(page, "All my mounts", 200, 76, -7, MountForMenu, "DmorphOctoMountFor")
	ui.mountForButton:SetScript("OnEnter", function()
		Tooltip(this, "Which mount gets the skin", "All your mounts, or one you've ridden on this character.",
			"Ride a mount once and it appears in this menu.")
	end)
	ui.mountForButton:SetScript("OnLeave", HideTooltip)
	Button(page, "Remove skin", 110, 282, -7, function()
		ui.mountPick = { target = ui.mountFor }
		Morph(M.SetMountSkin, 0, ui.mountFor)
	end, "DmorphOctoMountReset")
	ui.mountState = Label(page, "", "GameFontHighlightSmall", 10, -34, "DmorphOctoMountState")
	ui.mountState:SetWidth(PAGE_W - 20)

	Label(page, "Search:", nil, 10, -60)
	ui.mountSearch = EditBox(page, "DmorphOctoMountSearch", 140, 58, -56)
	ui.mountSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterMounts)
	end)
	ui.mountSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterMounts()
	end)
	ui.mountFilter = Button(page, MOUNT_FILTERS[prefs.mountFilter].text, 150, 212, -55, MountFilterMenu, "DmorphOctoMountFilter")
	SortButton(page, "DmorphOctoMountSort", 368, -55, "sortMounts", FilterMounts)

	ui.mountList = List(page, "DmorphOctoMountList", 8, -82, 44, function(row, index)
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
			row.text:SetTextColor(1, 0.82, 0)
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
	end, function(index, row)
		local catalog = M.GetCreatureCatalog()
		local i = ui.mountResult[index]
		if i then
			ShowCardFor(row, catalog.ids[i], catalog.names[i], KindColor(catalog.kind[i]), true)
		end
	end, MOUNT_LIST_W)
	BuildMountPanel(page)
	ui.mountCount = Label(page, "", "GameFontDisableSmall", 10, -362, "DmorphOctoMountCount")
	Label(page, "Click: use as the skin. Right-click: star it. Arrows: previous / next.",
		"GameFontDisableSmall", 110, -362)
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
end

local function GlowTooltip(index, row)
	local all = M.GetGlows()
	local i = ui.glowResult[index]
	if not i then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
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
	GameTooltip:AddLine("Glow " .. all.visual[i] .. ", shown with enchant " .. all.enchant[i] .. ".", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Click: on your " .. strlower(M.SLOT_NAMES[glowSlot]) .. ".", 0.6, 1, 0.6)
	GameTooltip:Show()
end

local function BuildGlowsPage(page)
	Label(page, "Weapon glows", "GameFontNormal", 10, -12)
	for i = 1, table.getn(M.GLOW_SLOTS) do
		local slot = M.GLOW_SLOTS[i]
		local button = Button(page, M.SLOT_NAMES[slot], 92, 180 + (i - 1) * 96, -7, function()
			glowSlot = this.slot
			RefreshGlows()
		end, "DmorphOctoGlowSlot" .. slot)
		button.slot = slot
		ui.glowSlots[slot] = button
	end
	Label(page, "Search:", nil, 10, -40)
	ui.glowSearch = EditBox(page, "DmorphOctoGlowSearch", 140, 58, -36)
	ui.glowSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterGlows)
	end)
	ui.glowSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterGlows()
	end)
	ui.glowCount = Label(page, "", "GameFontDisableSmall", 214, -40, "DmorphOctoGlowCount")

	ui.glowList = List(page, "DmorphOctoGlowList", 8, -62, 80, function(row, index)
		local all = M.GetGlows()
		local i = ui.glowResult[index]
		row.text:SetText(all.name[i])
		row.info:SetText("glow " .. all.visual[i])
		if M.GetGlow(glowSlot) == all.enchant[i] then
			row.tick:Show()
		end
	end, function(index)
		local all = M.GetGlows()
		Morph(M.SetGlow, glowSlot, all.enchant[ui.glowResult[index]])
	end, GlowTooltip)
	ui.glowEmpty = Label(page, "No glow list yet. Close the game, run tools\\update_from_game.ps1 from the "
		.. "DmorphOcto folder (it reads every glow from the game files), and start the game again.",
		"GameFontDisableSmall", 14, -72, "DmorphOctoGlowEmpty")
	ui.glowEmpty:SetWidth(PAGE_W - 28)

	ui.glowState = Label(page, "", "GameFontHighlightSmall", 10, -336, "DmorphOctoGlowState")
	Button(page, "No glow", 90, 8, -352, function()
		Morph(M.SetGlow, glowSlot, 0)
	end, "DmorphOctoGlowNone")
	Button(page, "My own glow", 110, 102, -352, function()
		Morph(M.SetGlow, glowSlot, nil)
	end, "DmorphOctoGlowOwn")
	Label(page, "Only you see it, like every morph.", "GameFontDisableSmall", 222, -357)
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

local function BuildItemsPage(page)
	local prefs = Prefs()
	-- The slot: click it for a menu of every slot.
	local slotButton = CreateFrame("Button", "DmorphOctoItemSlotButton", page)
	slotButton:SetWidth(210)
	slotButton:SetHeight(30)
	slotButton:SetPoint("TOPLEFT", page, "TOPLEFT", 6, -4)
	local highlight = slotButton:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:SetBlendMode("ADD")
	highlight:SetAllPoints(slotButton)
	slotButton:SetScript("OnClick", SlotMenu)
	slotButton:SetScript("OnEnter", function()
		Tooltip(this, "Slot", "Click to pick another slot.")
	end)
	slotButton:SetScript("OnLeave", HideTooltip)
	ui.itemSlotIcon = slotButton:CreateTexture(nil, "ARTWORK")
	ui.itemSlotIcon:SetWidth(26)
	ui.itemSlotIcon:SetHeight(26)
	ui.itemSlotIcon:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 2, -2)
	ui.itemSlotLabel = Label(slotButton, "", "GameFontNormal", 34, -4, "DmorphOctoItemSlotLabel")
	ui.itemCount = Label(slotButton, "", "GameFontDisableSmall", 34, -18, "DmorphOctoItemCount")
	ui.itemLookup = Label(page, "", "GameFontDisableSmall", 222, -14, "DmorphOctoItemLookup")
	Button(page, "<", 26, PAGE_W - 64, -8, function()
		CycleSlot(-1)
	end)
	Button(page, ">", 26, PAGE_W - 36, -8, function()
		CycleSlot(1)
	end)

	Label(page, "Search:", nil, 10, -42)
	ui.itemSearch = EditBox(page, "DmorphOctoItemSearch", 200, 58, -38)
	ui.itemSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterItems)
	end)
	ui.itemSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterItems()
	end)
	SortButton(page, "DmorphOctoItemSort", 368, -37, "sortItems", FilterItems)

	-- Type, quality, source: e.g. Cloth + Epic for every epic cloth helmet.
	ui.itemTypeButton = Button(page, "Any type", 150, 8, -62, function()
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
	ui.itemQualityButton = Button(page, "Any quality", 150, 162, -62, function()
		QualityMenu(this, "itemQuality", FilterItems)
	end, "DmorphOctoItemQuality")
	ui.itemSourceButton = Button(page, "All items", 150, 316, -62, function()
		SourceMenu(this, M.ITEM_FILTERS, "itemFilter", FilterItems)
	end, "DmorphOctoItemSource")
	ui.itemSourceButton:SetScript("OnEnter", function()
		Tooltip(this, "Which items", "All, 1.12's own, or the ones Turtle WoW and OctoWoW added.")
	end)
	ui.itemSourceButton:SetScript("OnLeave", HideTooltip)

	ui.itemList = List(page, "DmorphOctoItemList", 8, -90, 60, function(row, index)
		local catalog = M.GetItemCatalog(itemSlot)
		local i = ui.itemResult[index]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(QualityColor(catalog.quality[i]))
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == M.GetState().items[itemSlot] then
			row:LockHighlight()
		end
	end, function(index)
		local itemID = M.GetItemCatalog(itemSlot).ids[ui.itemResult[index]]
		ui.itemBox:SetText(itemID)
		Morph(M.SetItem, itemSlot, itemID)
	end, function(index, row)
		-- Hover: your character wearing it, without putting it on.
		local catalog = M.GetItemCatalog(itemSlot)
		local i = ui.itemResult[index]
		if i then
			local r, g, b = QualityColor(catalog.quality[i])
			ShowItemCard(row, { catalog.ids[i] }, catalog.names[i], r, g, b, "Item " .. catalog.ids[i] .. " - click to wear it")
		end
	end, nil, 14)

	local y = -352
	Label(page, "Item ID:", nil, 10, y - 5)
	ui.itemBox = EditBox(page, "DmorphOctoItemID", 70, 60, y, 9)
	local function Apply()
		ui.itemBox:ClearFocus()
		Morph(M.SetItem, itemSlot, M.ParseID(ui.itemBox:GetText()) or -1)
	end
	ui.itemBox:SetScript("OnEnterPressed", Apply)
	Button(page, "Apply", 70, 142, y, Apply)
	Button(page, "Use my own gear", 130, 218, y, function()
		ui.itemBox:SetText("")
		Morph(M.SetItem, itemSlot, 0)
	end)
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

local function RefreshSets()
	ui.setList.Refresh()
end

local function SetTooltip(index, row)
	local catalog = M.GetSetCatalog()
	local i = ui.setResult[index]
	if not i then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
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
	local r, g, b = QualityColor(catalog.quality[i])
	ShowItemCard(row, pieces, catalog.names[i], r, g, b, table.getn(pieces) .. " pieces - click to wear them")
end

local function BuildSetsPage(page)
	Label(page, "Search:", nil, 10, -12)
	ui.setSearch = EditBox(page, "DmorphOctoSetSearch", 200, 58, -8)
	ui.setSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterSets)
	end)
	ui.setSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterSets()
	end)
	SortButton(page, "DmorphOctoSetSort", 368, -7, "sortSets", FilterSets)
	ui.setTypeButton = Button(page, "Any type", 150, 8, -32, function()
		TypeMenu(this, M.GetSetCatalog(), Prefs().setType, function(kind)
			Prefs().setType = kind
			FilterSets()
		end)
	end, "DmorphOctoSetType")
	ui.setTypeButton:SetScript("OnEnter", function()
		Tooltip(this, "Type", "Cloth, leather, mail or plate: what most of the set's armour is made of.")
	end)
	ui.setTypeButton:SetScript("OnLeave", HideTooltip)
	ui.setQualityButton = Button(page, "Any quality", 150, 162, -32, function()
		QualityMenu(this, "setQuality", FilterSets)
	end, "DmorphOctoSetQuality")
	ui.setSourceButton = Button(page, "All sets", 150, 316, -32, function()
		SourceMenu(this, M.SET_FILTERS, "setFilter", FilterSets)
	end, "DmorphOctoSetSource")

	ui.setList = List(page, "DmorphOctoSetList", 8, -60, 80, function(row, index)
		local catalog = M.GetSetCatalog()
		local i = ui.setResult[index]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(QualityColor(catalog.quality[i]))
		row.info:SetText(Count(table.getn(catalog.pieces[i]), "piece"))
		if i == ui.selectedSet then
			row:LockHighlight()
		end
	end, function(index)
		ui.selectedSet = ui.setResult[index]
		ui.setList.Refresh()
		Morph(M.WearSet, ui.selectedSet)
	end, SetTooltip, nil, 14)
	ui.setCount = Label(page, "", "GameFontDisableSmall", 10, -318, "DmorphOctoSetCount")
	ui.setLookup = Label(page, "", "GameFontDisableSmall", 160, -318, "DmorphOctoSetLookup")
	Label(page, "Click a set to wear every piece it has. Hover to see the pieces.", "GameFontDisableSmall", 10, -352)
end

-- Wardrobe tab ------------------------------------------------------------------------

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
end

local function LoadSelected()
	if not selectedOutfit then
		return SetStatus(false, "Pick an outfit in the list first.")
	end
	Morph(M.LoadOutfit, selectedOutfit)
end

local function BuildWardrobePage(page)
	Label(page, "Wardrobe", "GameFontNormal", 10, -12)
	Label(page, "Outfits are shared by all your characters.", "GameFontDisableSmall", 86, -14)
	Label(page, "Name:", nil, 10, -42)
	ui.outfitName = EditBox(page, "DmorphOctoOutfitName", 200, 50, -38, 32)
	local function Save()
		ui.outfitName:ClearFocus()
		local ok, message = M.SaveOutfit(ui.outfitName:GetText())
		if ok then
			selectedOutfit = M.FindOutfit(ui.outfitName:GetText())
		end
		SetStatus(ok, message)
	end
	ui.outfitName:SetScript("OnEnterPressed", Save)
	Button(page, "Save current look", 140, 266, -37, Save)

	ui.outfitList = List(page, "DmorphOctoOutfitList", 8, -64, 230, function(row, index)
		local name = ui.outfitNames[index]
		row.text:SetText(name)
		row.info:SetText(M.DescribeOutfit(M.GetOutfit(name)))
		if name == selectedOutfit then
			row:LockHighlight()
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
		SetStatus(true, "Click \"" .. name .. "\" again, or press Load, to put it on.")
	end)
	ui.outfitEmpty = Label(page, "No outfits yet. Build a look, type a name above and press Save.",
		"GameFontDisableSmall", 14, -72)

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

-- Weather tab ---------------------------------------------------------------------

-- A button per weather (M.WEATHERS): Clear skies on its own row, then light,
-- normal and heavy rain, snow and sandstorm. The slider sets the strength
-- of the rain, snow or sandstorm you picked.
local WEATHER_ROW_NAMES = { "Rain", "Snow", "Sandstorm" }

local function RefreshWeather()
	local kind, intensity, serverKind, serverIntensity = M.GetWeather()
	for i = 1, table.getn(M.WEATHERS) do
		local w = M.WEATHERS[i]
		local button = ui.weatherButtons[w.key]
		local picked = kind == w.kind and (w.kind == 0 or math.abs(intensity - w.intensity) < 0.001)
		if picked then
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
	ui.weatherSync = true
	ui.weatherSlider:SetValue(kind and kind > 0 and intensity or 0.55)
	ui.weatherSync = nil
	local now
	if kind then
		now = "Now: |cff33ff99" .. M.DescribeWeather(kind, intensity) .. "|r, picked by you."
	else
		now = "Now: the server's weather."
	end
	if serverKind then
		now = now .. " The server's: " .. M.DescribeWeather(serverKind, serverIntensity) .. "."
	end
	ui.weatherState:SetText(now)
	if M.HasWeather() then
		ui.weatherMissing:Hide()
	else
		ui.weatherMissing:Show()
	end
end

local function BuildWeatherPage(page)
	Label(page, "Weather", "GameFontNormal", 10, -12)
	Label(page, "Only on your screen; it stays on in every zone.",
		"GameFontDisableSmall", 76, -15)
	ui.weatherButtons = {}
	local function Pick()
		Morph(M.SetWeather, this.kind, this.intensity)
	end
	for i = 1, table.getn(M.WEATHERS) do
		local w = M.WEATHERS[i]
		local x, y = 110, -44
		if w.kind > 0 then
			-- Light, normal, heavy in columns; one row per kind.
			x = 110 + math.mod(i - 2, 3) * 118
			y = -84 - (w.kind - 1) * 36
		end
		local button = Button(page, w.text, 112, x, y, Pick, "DmorphOctoWeather" .. w.key)
		button.kind, button.intensity = w.kind, w.intensity
		ui.weatherButtons[w.key] = button
	end
	for i = 1, 3 do
		Label(page, WEATHER_ROW_NAMES[i], "GameFontHighlight", 14, -88 - (i - 1) * 36)
	end
	Label(page, "Sky", "GameFontHighlight", 14, -48)

	-- Strength of the picked rain, snow or sandstorm, applied once the slider
	-- stands still.
	ui.weatherTimer = NewTimer()
	local slider = CreateFrame("Slider", "DmorphOctoWeatherStrength", page)
	slider:SetOrientation("HORIZONTAL")
	slider:SetWidth(348)
	slider:SetHeight(16)
	slider:SetPoint("TOPLEFT", page, "TOPLEFT", 110, -206)
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	slider:SetMinMaxValues(0.05, 1)
	slider:SetValueStep(0.05)
	ui.weatherStrength = Label(page, "Strength", "GameFontHighlight", 14, -207, "DmorphOctoWeatherStrengthLabel")
	slider:SetScript("OnValueChanged", function()
		local value = math.floor(this:GetValue() * 20 + 0.5) / 20
		ui.weatherStrength:SetText("Strength " .. math.floor(value * 100 + 0.5) .. "%")
		if ui.weatherSync then
			return
		end
		Debounce(ui.weatherTimer, 0.3, function()
			local kind = M.GetWeather()
			if kind and kind > 0 then
				SetStatus(M.SetWeather(kind, value))
			else
				SetStatus(false, "Pick rain, snow or a sandstorm first; the slider sets how strong it is.")
				RefreshWeather()
			end
		end)
	end)
	slider:SetScript("OnEnter", function()
		Tooltip(this, "Strength", "How strong the rain, snow or sandstorm you picked is.",
			"Its sound changes with it: light below 40%, heavy from 70%.")
	end)
	slider:SetScript("OnLeave", HideTooltip)
	ui.weatherSlider = slider

	ui.weatherState = Label(page, "", "GameFontHighlightSmall", 10, -246, "DmorphOctoWeatherState")
	ui.weatherState:SetWidth(PAGE_W - 20)
	ui.weatherMissing = Label(page, "Changing the weather needs DmorphHelper v8 or newer: close the game and "
		.. "double-click \"Install DmorphHelper.bat\" in the DmorphOcto folder.", "GameFontRedSmall", 10, -272,
		"DmorphOctoWeatherMissing")
	ui.weatherMissing:SetWidth(PAGE_W - 20)
	Label(page, "Weather shows outdoors. Indoors and in some dungeons the game draws none.",
		"GameFontDisableSmall", 10, -310)

	Button(page, "Server's weather", 140, 8, -352, function()
		Morph(M.SetWeather, nil)
	end, "DmorphOctoWeatherServer")
	Label(page, ".weather rain heavy also works in chat.", "GameFontDisableSmall", 158, -357)
end

local REFRESH = {
	weather = RefreshWeather,
	models = RefreshModels,
	mounts = RefreshMounts,
	favourites = RefreshFavourites,
	races = RefreshRaces,
	glows = RefreshGlows,
	items = RefreshItems,
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
	if active then
		tab:SetBackdropColor(0.18, 0.14, 0.05, 1)
		tab:SetBackdropBorderColor(1, 0.82, 0, 1)
		tab.label:SetTextColor(1, 0.82, 0)
	else
		tab:SetBackdropColor(0.08, 0.08, 0.09, 1)
		tab:SetBackdropBorderColor(0.35, 0.35, 0.38, 1)
		tab.label:SetTextColor(0.8, 0.8, 0.8)
	end
end

ShowTab = function(key)
	currentTab = key
	ui.card:Hide()
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
	stage:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -40)
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
	ZoomButton("-", 24, middle - 66, "DmorphOctoZoomOut", function()
		Zoom(-1)
	end, "Zoom out.")
	ZoomButton("+", 24, middle - 40, "DmorphOctoZoomIn", function()
		Zoom(1)
	end, "Zoom in, to see the details.")
	ZoomButton("Reset view", 80, middle - 14, "DmorphOctoZoomReset", ResetView, "Back to the whole character.")

	local plate = Layer(stage, 5)
	plate:SetPoint("BOTTOMLEFT", stage, "BOTTOMLEFT", 0, 0)
	plate:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, 0)
	plate:SetHeight(PLATE_H + 20)
	Gradient(plate, "BACKGROUND", 0, 0, 0, 0.92, 0, 0, 0, 0):SetAllPoints(plate)
	ui.plateTitle = plate:CreateFontString("DmorphOctoLookName", "OVERLAY", "GameFontNormalLarge")
	ui.plateTitle:SetPoint("BOTTOM", plate, "BOTTOM", 0, 22)
	ui.plateTitle:SetWidth(ART_W - 16)
	ui.plateTitle:SetHeight(18)
	ui.plateInfo = plate:CreateFontString("DmorphOctoLookInfo", "OVERLAY", "GameFontHighlightSmall")
	ui.plateInfo:SetPoint("BOTTOM", plate, "BOTTOM", 0, 8)
	ui.plateInfo:SetWidth(ART_W - 16)
	ui.plateInfo:SetTextColor(0.75, 0.75, 0.75)

	-- Your size in the world, 25% to 300% (DmorphHelper v2). Applied once the
	-- slider stands still: each change rebuilds your model.
	ui.sizeTimer = NewTimer()
	local size = CreateFrame("Slider", "DmorphOctoSize", plate)
	size:SetFrameLevel(base + 6)
	size:SetOrientation("HORIZONTAL")
	size:SetWidth(ART_W - 170)
	size:SetHeight(16)
	size:SetPoint("BOTTOM", plate, "BOTTOM", 26, 44)
	size:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	size:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background", edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8, insets = { left = 3, right = 3, top = 6, bottom = 6 },
	})
	size:SetMinMaxValues(0.25, 3)
	size:SetValueStep(0.05)
	ui.sizeLabel = size:CreateFontString("DmorphOctoSizeLabel", "OVERLAY", "GameFontHighlightSmall")
	ui.sizeLabel:SetPoint("RIGHT", size, "LEFT", -8, 0)
	ui.sizeLabel:SetText("Size 100%")
	size:SetScript("OnValueChanged", function()
		local value = math.floor(this:GetValue() * 20 + 0.5) / 20
		ui.sizeLabel:SetText("Size " .. math.floor(value * 100 + 0.5) .. "%")
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
		Tooltip(this, "Size", "Drag to make your character smaller or bigger, in the world.",
			"Right-click: your own size. Needs DmorphHelper (Setup shows it).")
	end)
	size:SetScript("OnLeave", HideTooltip)
	ui.sizeSlider = size

	local function AddSlots(slots, x)
		for i = 1, table.getn(slots) do
			local slot = slots[i]
			local button = CreateFrame("Button", "DmorphOctoSlot" .. slot, stage)
			button:SetFrameLevel(base + 6)
			button:SetWidth(36)
			button:SetHeight(36)
			button:SetPoint("TOPLEFT", stage, "TOPLEFT", x, -10 - (i - 1) * 46)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button.icon = button:CreateTexture(nil, "BORDER")
			button.icon:SetAllPoints(button)
			local rim = button:CreateTexture(nil, "ARTWORK")
			rim:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			rim:SetWidth(62)
			rim:SetHeight(62)
			rim:SetPoint("CENTER", button, "CENTER", 0, 0)
			button.glow = button:CreateTexture(nil, "OVERLAY")
			button.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
			button.glow:SetBlendMode("ADD")
			button.glow:SetVertexColor(0.3, 1, 0.5)
			button.glow:SetWidth(66)
			button.glow:SetHeight(66)
			button.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
			local highlight = button:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
			highlight:SetBlendMode("ADD")
			highlight:SetAllPoints(button)
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
	border:SetPoint("TOPLEFT", stage, "TOPLEFT", -4, 4)
	border:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 4, -4)
	border:SetBackdrop({ edgeFile = EDGE, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
	border:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)

	Button(frame, "Reset model", 155, 20, -432, function()
		Morph(M.ResetModel)
	end)
	Button(frame, "Reset everything", 155, 183, -432, function()
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
		dot:SetVertexColor(0.7, 0.6, 0.4)
		grip.dots[i] = dot
	end
	local function Tint(r, g, b)
		for i = 1, table.getn(grip.dots) do
			grip.dots[i]:SetVertexColor(r, g, b)
		end
	end
	grip:SetScript("OnEnter", function()
		Tint(1, 0.82, 0)
		Tooltip(this, "Window size", "Drag to make the window bigger or smaller.")
	end)
	grip:SetScript("OnLeave", function()
		Tint(0.7, 0.6, 0.4)
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
		local tab = CreateFrame("Button", "DmorphOctoTab" .. info.text, frame)
		tab:SetHeight(26)
		Panel(tab, 0.08, 0.08, 0.09)
		tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		tab.label:SetPoint("CENTER", tab, "CENTER", 0, 0)
		tab.label:SetText(info.text)
		local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")
		highlight:SetPoint("TOPLEFT", tab, "TOPLEFT", 3, -3)
		highlight:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -3, 3)
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
		Panel(page, 0.035, 0.035, 0.04)
		page:Hide()
		ui.pages[info.key] = page
	end
	-- Each tab as wide as its name, the room left shared out evenly.
	local count, used = table.getn(TABS), 0
	for i = 1, count do
		used = used + ui.tabs[TABS[i].key].label:GetStringWidth()
	end
	local pad = math.floor((PAGE_W - (count - 1) * TAB_GAP - used) / count)
	local x = PAGE_X
	for i = 1, count do
		local tab = ui.tabs[TABS[i].key]
		local width = math.floor(tab.label:GetStringWidth() + pad)
		tab:SetWidth(width)
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -38)
		x = x + width + TAB_GAP
	end
	BuildModelsPage(ui.pages.models)
	BuildMountsPage(ui.pages.mounts)
	BuildFavouritesPage(ui.pages.favourites)
	BuildRacesPage(ui.pages.races)
	BuildGlowsPage(ui.pages.glows)
	BuildItemsPage(ui.pages.items)
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
	Panel(panel, 0.06, 0.06, 0.07)
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

local function Build()
	frame = CreateFrame("Frame", "DmorphOctoFrame", UIParent)
	frame:Hide()
	frame:SetWidth(W)
	frame:SetHeight(H)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetScale(Prefs().scale)
	frame:SetBackdrop({
		bgFile = WHITE, edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = false, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	frame:SetBackdropColor(0.055, 0.055, 0.065, 1)
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
	frame:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		ui.card:Hide()
		if ui.itemCard then
			ui.itemCard:Hide()
			ui.itemCard.loaded = nil
		end
		ui.menu:Hide()
		-- A click still waiting at the gate is applied now.
		local nextCall = ui.gateNext
		ui.gateBusy, ui.gateNext = nil, nil
		if nextCall then
			Morph(nextCall[1], nextCall[2], nextCall[3])
		end
	end)
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

	local glow = Gradient(frame, "BORDER", 0.3, 0.24, 0.1, 0, 0.3, 0.24, 0.1, 0.22)
	glow:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
	glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
	glow:SetHeight(70)
	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetWidth(340)
	header:SetHeight(64)
	header:SetPoint("TOP", frame, "TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("DMorph |cff33ff99(OctoWoW)|r")
	local close = CreateFrame("Button", "DmorphOctoFrameClose", frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

	ui.searchTimer = NewTimer()
	ui.previewTimer = NewTimer()
	ui.revealTimer = NewTimer()
	ui.gateTimer = NewTimer()
	ui.card = BuildCard()
	ui.itemCard = BuildItemCard()
	ui.canPreview = type(ui.card.view.model.SetDisplayInfo) == "function"
	ui.menu = BuildMenu()

	BuildStage()
	BuildTabs()
	BuildGrip()

	ui.status = Label(frame, "", "GameFontHighlightSmall", 22, -462, "DmorphOctoFrameStatus")
	ui.status:SetWidth(W - 44)
	ui.status:SetHeight(30)
	ui.setupButton = Button(frame, "", 160, 22, -495, ShowSetupPanel, "DmorphOctoSetupButton")
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
		"GameFontDisableSmall", 192, -500)
	BuildSetupPanel()
	local share = Button(frame, "Sharing", 80, W - 230, -495, ShareMenu, "DmorphOctoShare")
	share:SetScript("OnEnter", function()
		local _, _, known, morphed = M.GetShareStatus()
		Tooltip(this, "Sharing with DMorph users", "Who sees whose morph. Only friendly players can be morphed.",
			"DMorph users seen: " .. known .. " (" .. morphed .. " morphed).")
	end)
	share:SetScript("OnLeave", HideTooltip)
	local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -500)
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
