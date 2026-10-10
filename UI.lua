-- DMorph for OctoWoW: the morph window.
--
-- Left: your character in a dressing room (your race's dress-up backdrop),
-- with the morphable slots around it. Right: tabs to browse every creature
-- model (a grid of 3D previews, or a list), the races, a character creator,
-- items per slot, item sets and a wardrobe of saved outfits. Everything goes
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
local MENU_ROWS, MENU_WIDTH = 14, 170
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
	{ key = "favourites", text = "Favourites" },
	{ key = "races", text = "Races" },
	{ key = "creator", text = "Creator" },
	{ key = "items", text = "Items" },
	{ key = "sets", text = "Sets" },
	{ key = "wardrobe", text = "Wardrobe" },
}
local TAB_W, TAB_GAP = 64, 4
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
	creator = {}, creatorRaces = {}, creatorRows = {}, target = "you",
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

local function Tooltip(owner, title, line1, line2)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	GameTooltip:SetText(title)
	if line1 then
		GameTooltip:AddLine(line1, 1, 1, 1)
	end
	if line2 then
		GameTooltip:AddLine(line2, 0.8, 0.8, 0.8)
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
local function OpenMenu(anchor, options, pick)
	local menu = ui.menu
	if menu:IsShown() and menu.anchor == anchor then
		menu:Hide()
		return
	end
	menu.anchor, menu.pick = anchor, pick
	local count = table.getn(options)
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
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
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
local function List(parent, name, x, y, infoWidth, fill, click, enter)
	local list = { rows = {}, count = 0 }
	local scroll = CreateFrame("ScrollFrame", name, parent, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	scroll:SetWidth(LIST_WIDTH)
	scroll:SetHeight(LIST_ROWS * ROW_HEIGHT)

	function list.Refresh()
		local offset = FauxScrollFrame_GetOffset(scroll) or 0
		for i = 1, LIST_ROWS do
			local row = list.rows[i]
			local index = offset + i
			if index <= list.count then
				row.index = index
				row:UnlockHighlight()
				row.star:Hide()
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
		row:SetWidth(LIST_WIDTH)
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
		row.text:SetWidth(LIST_WIDTH - infoWidth - 14)
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
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function()
			ui.card:Hide()
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
	ui.plateTitle:SetText(title)
	ui.plateInfo:SetText(info)
end

local RequestPreview

-- The new look has loaded behind the backdrop: bring it to the front.
local function SwapPreview()
	local p = ui.preview
	p.front = 3 - p.front
	local front, back = p.models[p.front], p.models[3 - p.front]
	front:SetRotation(p.rotation)
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

-- The display ID the Models tab works on: your model's, or your mount's.
local function TargetDisplay()
	local state = M.GetState()
	if ui.target == "mount" then
		return state.mount
	end
	return state.display
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
			if M.IsFavourite(id, ui.target == "mount") then
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

-- Click a model: become it, or (with the Mount switch) make your mount it.
local function MorphInto(displayID)
	ui.displayBox:SetText(displayID)
	if ui.target == "mount" then
		Morph(M.SetMount, displayID)
	else
		Morph(M.SetDisplay, displayID)
	end
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
	if ui.target == "mount" then
		GameTooltip:AddLine("Click to make your mount look like it.", 0.6, 1, 0.6)
	else
		GameTooltip:AddLine("Click to morph into it.", 0.6, 1, 0.6)
	end
	local what = ui.target == "mount" and "favourite mounts" or "favourite models"
	if M.IsFavourite(catalog.ids[entry], ui.target == "mount") then
		GameTooltip:AddLine("Right-click to take it off your " .. what .. ".", 1, 0.82, 0)
	else
		GameTooltip:AddLine("Right-click to add it to your " .. what .. ".", 1, 0.82, 0)
	end
	GameTooltip:Show()
end

-- Right-click on a model: star it (as a model, or as a mount with the Mount
-- switch on), or take the star off.
local function ToggleFavourite(displayID)
	SetStatus(M.ToggleFavourite(displayID, ui.target == "mount"))
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

-- The preview card next to a list row, for a display ID.
local function ShowCardFor(row, displayID, name, color)
	if not (ui.canPreview and displayID) then
		return
	end
	local card = ui.card
	card:ClearAllPoints()
	card:SetPoint("LEFT", row, "RIGHT", 50, 0)
	card.title:SetText(name)
	card.title:SetTextColor(color[1], color[2], color[3])
	card.idText:SetText("Display ID " .. displayID)
	card:Show()
	if card.view.displayID ~= displayID then
		LoadView(card.view, displayID)
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

local function SetTarget(target)
	ui.target = target
	if target == "mount" then
		ui.targetButton:SetText("Morph: mount")
	else
		ui.targetButton:SetText("Morph: you")
	end
	RefreshModels()
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
	ui.targetButton = Button(page, "Morph: you", 112, 104, -33, function()
		if ui.target == "mount" then
			SetTarget("you")
		else
			SetTarget("mount")
		end
	end, "DmorphOctoModelTarget")
	ui.targetButton:SetScript("OnEnter", function()
		Tooltip(this, "What a click morphs", "You: become the model.",
			"Mount: your mount looks like it, every time you ride.")
	end)
	ui.targetButton:SetScript("OnLeave", HideTooltip)

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
		if M.IsFavourite(catalog.ids[i], ui.target == "mount") then
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
	Label(page, "In the Models tab, right-click a model to star it (with \"Morph: mount\", as a mount).",
		"GameFontDisableSmall", 10, -354)
end

-- Races tab ------------------------------------------------------------------------

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

local function RefreshRaces()
	local race, gender = M.GetBodyRace()
	local nativeRace, nativeGender = M.GetNative()
	if nativeRace then
		ui.nativeLabel:SetText("Your character: " .. M.DescribeBody(nativeRace, nativeGender))
	else
		ui.nativeLabel:SetText("")
	end
	local state = M.GetState()
	for _, button in pairs(ui.raceButtons) do
		if not state.display and button.race == race and button.gender == gender then
			button.ring:Show()
			button:LockHighlight()
		else
			button.ring:Hide()
			button:UnlockHighlight()
		end
	end
	for r, cell in pairs(ui.raceCells) do
		if r == nativeRace then
			cell.mine:SetText("your race")
		else
			cell.mine:SetText("")
		end
	end
end

local function BuildRacesPage(page)
	Label(page, "Races", "GameFontNormal", 10, -12)
	Label(page, "Pick a race and gender. Your own skin, face and hair carry over.", "GameFontDisableSmall", 62, -14)
	for race = 1, table.getn(M.RACES) do
		local cell = CreateFrame("Frame", nil, page)
		cell:SetWidth(225)
		cell:SetHeight(50)
		cell:SetPoint("TOPLEFT", page, "TOPLEFT", 8 + math.mod(race - 1, 2) * 233, -36 - math.floor((race - 1) / 2) * 56)
		Panel(cell, 0.08, 0.08, 0.09)
		for gender = 0, 1 do
			local button = CreateFrame("Button", "DmorphOctoRace" .. race .. GenderName(gender), cell)
			button:SetWidth(38)
			button:SetHeight(38)
			button:SetPoint("TOPLEFT", cell, "TOPLEFT", 6 + gender * 44, -6)
			RaceIcon(button, race, gender)
			button:SetScript("OnClick", function()
				Morph(M.SetRace, this.race, this.gender)
			end)
			button:SetScript("OnEnter", function()
				Tooltip(this, M.DescribeBody(this.race, this.gender), "Keeps your own skin, face and hair.",
					"Your item morphs show on it.")
			end)
			button:SetScript("OnLeave", HideTooltip)
			table.insert(ui.raceButtons, button)
		end
		Label(cell, M.RACES[race].name, "GameFontNormal", 100, -12)
		cell.mine = Label(cell, "", "GameFontDisableSmall", 100, -28)
		ui.raceCells[race] = cell
	end
	Button(page, "Swap gender", 140, 8, -346, function()
		Morph(M.ToggleGender)
	end)
	ui.nativeLabel = Label(page, "", "GameFontDisableSmall", 160, -352)
end

-- Creator tab ------------------------------------------------------------------------

-- The creator builds a look from the game's own NPCs of a race and gender
-- (Data/Looks.lua): pick a race, then step through the skin colours, faces,
-- hair styles and colours and facial hair that those NPCs have.
local function CreatorTarget()
	local c = ui.creator
	if not c.race then
		local race, gender = M.GetBodyRace()
		c.race, c.gender = race or 1, gender or 0
	end
	return c.race, c.gender
end

local function Position(list, value)
	for i = 1, table.getn(list) do
		if list[i] == value then
			return i
		end
	end
	return 1
end

local function RefreshCreator()
	local c = ui.creator
	local race, gender = CreatorTarget()
	local list = M.GetLooks(race, gender)
	local look = c.index and list[c.index]
	for _, button in pairs(ui.creatorRaces) do
		if button.race == race and button.gender == gender then
			button.ring:Show()
		else
			button.ring:Hide()
		end
	end
	ui.creatorTitle:SetText(M.DescribeBody(race, gender) .. ": " .. Count(table.getn(list), "look"))
	for f = 1, 6 do
		local row = ui.creatorRows[f]
		local values
		if f == 6 then
			values = look and M.GetLookOutfits(race, gender, c.index) or {}
		else
			values = M.GetLookValues(race, gender, f)
		end
		local text = "- / " .. table.getn(values)
		if look and f == 6 then
			text = Position(values, c.index) .. " / " .. table.getn(values) .. "  (" .. Count(look[7], "piece") .. ")"
		elseif look then
			text = Position(values, look[f + 1]) .. " / " .. table.getn(values)
		end
		row.value:SetText(text)
		if f == 5 then
			if gender == 1 then
				row.label:SetText("Features")
			else
				row.label:SetText("Facial hair")
			end
		end
	end
	if look then
		ui.creatorLook:SetText("Look " .. Commas(c.index) .. " of " .. Commas(table.getn(list)) .. " - display ID " .. look[1])
	else
		ui.creatorLook:SetText("Pick a race, then any feature, or roll the dice.")
	end
end

local function WearLook(index)
	local c = ui.creator
	local race, gender = CreatorTarget()
	local list = M.GetLooks(race, gender)
	if not (index and list[index]) then
		return SetStatus(false, "The game has no " .. M.DescribeBody(race, gender) .. " NPC looks.")
	end
	c.index = index
	RefreshCreator()
	Morph(M.SetDisplay, list[index][1])
end

-- Feature f (1-5) or the outfit (6) one value along.
local function StepFeature(f, step)
	local c = ui.creator
	local race, gender = CreatorTarget()
	local list = M.GetLooks(race, gender)
	if table.getn(list) == 0 then
		return WearLook(nil)
	end
	if not (c.index and list[c.index]) then
		return WearLook(1)
	end
	if f == 6 then
		local outfits = M.GetLookOutfits(race, gender, c.index)
		return WearLook(outfits[Wrap(Position(outfits, c.index), step, table.getn(outfits))])
	end
	local values = M.GetLookValues(race, gender, f)
	local value = values[Wrap(Position(values, list[c.index][f + 1]), step, table.getn(values))]
	WearLook(M.FindLook(race, gender, f, value, c.index))
end

local function BuildCreatorPage(page)
	Label(page, "Character creator", "GameFontNormal", 10, -10)
	Label(page, "Every face, skin and hairstyle the game's own NPCs have.", "GameFontDisableSmall", 130, -12)
	for race = 1, table.getn(M.RACES) do
		for gender = 0, 1 do
			local button = CreateFrame("Button", "DmorphOctoCreator" .. race .. GenderName(gender), page)
			button:SetWidth(36)
			button:SetHeight(36)
			button:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + (race - 1) * 45, -30 - gender * 40)
			RaceIcon(button, race, gender)
			button:SetScript("OnClick", function()
				local c = ui.creator
				c.race, c.gender, c.index = this.race, this.gender, nil
				WearLook(1)
			end)
			button:SetScript("OnEnter", function()
				Tooltip(this, M.DescribeBody(this.race, this.gender),
					Count(table.getn(M.GetLooks(this.race, this.gender)), "look") .. " from the game's NPCs.")
			end)
			button:SetScript("OnLeave", HideTooltip)
			table.insert(ui.creatorRaces, button)
		end
	end
	ui.creatorTitle = Label(page, "", "GameFontHighlight", 14, -116, "DmorphOctoCreatorTitle")
	local names = { M.LOOK_FEATURES[1], M.LOOK_FEATURES[2], M.LOOK_FEATURES[3], M.LOOK_FEATURES[4],
		M.LOOK_FEATURES[5], "Outfit" }
	for f = 1, 6 do
		local y = -140 - (f - 1) * 27
		local row = {}
		row.label = Label(page, names[f], "GameFontNormal", 20, y - 4)
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
	dice:SetWidth(30)
	dice:SetHeight(30)
	dice:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -304)
	dice:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
	dice:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Down")
	dice:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Highlight")
	dice:SetScript("OnClick", function()
		local race, gender = CreatorTarget()
		local count = table.getn(M.GetLooks(race, gender))
		if count == 0 then
			return WearLook(nil)
		end
		local index = math.random(count)
		if count > 1 and index == ui.creator.index then
			index = Wrap(index, 1, count)
		end
		WearLook(index)
	end)
	dice:SetScript("OnEnter", function()
		Tooltip(this, "Random look", "Any face, skin, hair and outfit of this race.")
	end)
	dice:SetScript("OnLeave", HideTooltip)
	ui.creatorLook = Label(page, "", "GameFontHighlightSmall", 52, -315, "DmorphOctoCreatorLook")
	local star = Button(page, "Favourite", 92, PAGE_W - 102, -309, function()
		local c = ui.creator
		local race, gender = CreatorTarget()
		local look = c.index and M.GetLooks(race, gender)[c.index]
		if not look then
			return SetStatus(false, "Pick a look first.")
		end
		SetStatus(M.ToggleFavourite(look[1]))
	end, "DmorphOctoCreatorFavourite")
	star:SetScript("OnEnter", function()
		Tooltip(this, "Favourite this look", "Adds it to the Favourites tab (or takes it off).")
	end)
	star:SetScript("OnLeave", HideTooltip)
	Label(page, "These are NPC looks, so your item morphs don't show on them.", "GameFontDisableSmall", 14, -346)
	Label(page, "For your own face with gear, use the Races tab.", "GameFontDisableSmall", 14, -360)
end

-- Items tab -------------------------------------------------------------------------

local function ItemFilterText(filters, source, quality)
	if quality > 1 and source > 1 then
		return M.QUALITY_FILTERS[quality].text .. ", " .. (source == 2 and "1.12" or "new")
	elseif quality > 1 then
		return M.QUALITY_FILTERS[quality].text
	end
	return filters[source].text
end

-- A menu with the source filters (all, 1.12, new) and the quality filters.
local function SourceQualityMenu(anchor, filters, sourceKey, qualityKey, done)
	local prefs, options = Prefs(), { { text = "Show", header = true } }
	for i = 1, table.getn(filters) do
		table.insert(options, { text = filters[i].text, source = i, checked = prefs[sourceKey] == i })
	end
	table.insert(options, { text = "Quality", header = true })
	for i = 1, table.getn(M.QUALITY_FILTERS) do
		table.insert(options, { text = M.QUALITY_FILTERS[i].text, quality = i, checked = prefs[qualityKey] == i })
	end
	OpenMenu(anchor, options, function(option)
		local p = Prefs()
		if option.source then
			p[sourceKey] = option.source
		else
			p[qualityKey] = option.quality
		end
		anchor:SetText(ItemFilterText(filters, p[sourceKey], p[qualityKey]))
		done()
	end)
end

local function FilterItems(keep)
	local prefs = Prefs()
	local count
	ui.itemResult, count = M.FilterCatalog(M.GetItemCatalog(itemSlot), ui.itemSearch:GetText(),
		M.ITEM_FILTERS[prefs.itemFilter], M.QUALITY_FILTERS[prefs.itemQuality].quality, prefs.sortItems)
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
	ui.itemSearch = EditBox(page, "DmorphOctoItemSearch", 140, 58, -38)
	ui.itemSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterItems)
	end)
	ui.itemSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterItems()
	end)
	local filter = Button(page, ItemFilterText(M.ITEM_FILTERS, prefs.itemFilter, prefs.itemQuality), 150, 212, -37, function()
		SourceQualityMenu(this, M.ITEM_FILTERS, "itemFilter", "itemQuality", FilterItems)
	end, "DmorphOctoItemFilter")
	filter:SetScript("OnEnter", function()
		Tooltip(this, "Which items to list", "All, 1.12's own or the ones Turtle WoW and OctoWoW added,",
			"and one quality: Rare, Epic, Legendary, ...")
	end)
	filter:SetScript("OnLeave", HideTooltip)
	SortButton(page, "DmorphOctoItemSort", 368, -37, "sortItems", FilterItems)

	ui.itemList = List(page, "DmorphOctoItemList", 8, -64, 60, function(row, index)
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
	end)

	local y = -346
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
		M.SET_FILTERS[prefs.setFilter], M.QUALITY_FILTERS[prefs.setQuality].quality, prefs.sortSets)
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
end

local function BuildSetsPage(page)
	local prefs = Prefs()
	Label(page, "Search:", nil, 10, -12)
	ui.setSearch = EditBox(page, "DmorphOctoSetSearch", 140, 58, -8)
	ui.setSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterSets)
	end)
	ui.setSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterSets()
	end)
	local filter = Button(page, ItemFilterText(M.SET_FILTERS, prefs.setFilter, prefs.setQuality), 150, 212, -7, function()
		SourceQualityMenu(this, M.SET_FILTERS, "setFilter", "setQuality", FilterSets)
	end, "DmorphOctoSetFilter")
	filter:SetScript("OnEnter", function()
		Tooltip(this, "Which sets to list", "All, 1.12's own or the ones Turtle WoW and OctoWoW added,",
			"and one quality: Rare, Epic, Legendary, ...")
	end)
	filter:SetScript("OnLeave", HideTooltip)
	SortButton(page, "DmorphOctoSetSort", 368, -7, "sortSets", FilterSets)

	ui.setList = List(page, "DmorphOctoSetList", 8, -36, 80, function(row, index)
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
	end, SetTooltip)
	ui.setCount = Label(page, "", "GameFontDisableSmall", 10, -314, "DmorphOctoSetCount")
	ui.setLookup = Label(page, "", "GameFontDisableSmall", 160, -314, "DmorphOctoSetLookup")
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

local REFRESH = {
	models = RefreshModels,
	favourites = RefreshFavourites,
	races = RefreshRaces,
	creator = RefreshCreator,
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
	elseif key == "favourites" then
		FilterFavourites()
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

	local p = { models = {}, front = 1, rotation = 0.61, low = base + 1, high = base + 3 }
	for i = 1, 2 do
		local model = CreateFrame("PlayerModel", "DmorphOctoModel" .. i, stage)
		model:SetPoint("TOPLEFT", stage, "TOPLEFT", 0, -4)
		model:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, PLATE_H)
		model:SetFrameLevel(p.low)
		model:Hide()
		p.models[i] = model
	end
	ui.preview = p

	-- Dragging anywhere over the model turns it.
	local drag = Layer(stage, 4)
	drag:SetAllPoints(p.models[1])
	drag:EnableMouse(true)
	drag:SetScript("OnMouseDown", function()
		this.dragX = GetCursorPosition()
	end)
	drag:SetScript("OnMouseUp", function()
		this.dragX = nil
	end)
	drag:SetScript("OnUpdate", function()
		if this.dragX then
			local x = GetCursorPosition()
			p.rotation = p.rotation + (x - this.dragX) * 0.02
			this.dragX = x
			p.models[p.front]:SetRotation(p.rotation)
		end
	end)

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
		tab:SetWidth(TAB_W)
		tab:SetHeight(26)
		tab:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X + (i - 1) * (TAB_W + TAB_GAP), -38)
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
	BuildModelsPage(ui.pages.models)
	BuildFavouritesPage(ui.pages.favourites)
	BuildRacesPage(ui.pages.races)
	BuildCreatorPage(ui.pages.creator)
	BuildItemsPage(ui.pages.items)
	BuildSetsPage(ui.pages.sets)
	BuildWardrobePage(ui.pages.wardrobe)
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
		if not M.HasMorphAPI() then
			SetStatus(false, M.MISSING_API)
		end
		ShowTab(currentTab)
		ShowArt()
		UpdatePlate()
		RequestPreview()
	end)
	frame:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
		ui.card:Hide()
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
	ui.canPreview = type(ui.card.view.model.SetDisplayInfo) == "function"
	ui.menu = BuildMenu()

	BuildStage()
	BuildTabs()
	BuildGrip()

	ui.status = Label(frame, "", "GameFontHighlightSmall", 22, -462, "DmorphOctoFrameStatus")
	ui.status:SetWidth(W - 44)
	ui.status:SetHeight(30)
	Label(frame, "Morphs only change what you see. Type /dmorph help for chat commands.",
		"GameFontDisableSmall", 22, -500)
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
