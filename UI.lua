-- DMorph for OctoWoW: the morph window.
--
-- Left: a live preview of your character with the morphable slots around it.
-- Right: tabs to browse creature models, races and items, and a wardrobe of
-- saved outfits. Everything goes through the DmorphOcto.* functions in
-- DmorphOcto.lua, the same ones the chat commands use, so a change shows on
-- your character straight away and is remembered across /reload and logins.
--
-- 1.12 API: scripts read `this`/`arg1` instead of taking arguments, there is
-- no SetSize, and lists use FauxScrollFrameTemplate.

local M = DmorphOcto

local ROW_HEIGHT = 18
local LIST_ROWS = 14
local LIST_WIDTH = 350
local PAGE_X, PAGE_Y = 318, -72

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

local TABS = {
	{ key = "models", text = "Models" },
	{ key = "races", text = "Races" },
	{ key = "items", text = "Items" },
	{ key = "wardrobe", text = "Wardrobe" },
}

local frame -- the window, built the first time it opens
local ui = { tabs = {}, pages = {}, slots = {}, raceButtons = {} }
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

-- Widget helpers --------------------------------------------------------------

local function Label(parent, text, font, x, y, name)
	local label = parent:CreateFontString(name, "OVERLAY", font or "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function Button(parent, text, width, x, y, onClick)
	buttonCount = buttonCount + 1
	local button = CreateFrame("Button", "DmorphOctoButton" .. buttonCount, parent, "UIPanelButtonTemplate")
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
	return box
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

-- A scrolling list of LIST_ROWS rows over a FauxScrollFrame. fill(row, index)
-- draws entry `index` (row.text, row.info), click(index, mouseButton) handles
-- a click. infoWidth is the width of the right-hand column.
local function List(parent, name, y, infoWidth, fill, click)
	local list = { rows = {}, count = 0 }
	local scroll = CreateFrame("ScrollFrame", name, parent, "FauxScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
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
				fill(row, index)
				row:Show()
			else
				row:Hide()
			end
		end
		FauxScrollFrame_Update(scroll, list.count, LIST_ROWS, ROW_HEIGHT)
	end

	-- New contents: back to the top.
	function list.SetCount(count)
		list.count = count
		FauxScrollFrame_SetOffset(scroll, 0)
		getglobal(name .. "ScrollBar"):SetValue(0)
		list.Refresh()
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
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y - (i - 1) * ROW_HEIGHT)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
		highlight:SetBlendMode("ADD")
		highlight:SetAllPoints(row)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
		row.text:SetWidth(LIST_WIDTH - infoWidth - 12)
		row.text:SetHeight(ROW_HEIGHT)
		row.text:SetJustifyH("LEFT")
		row.info = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
		row.info:SetWidth(infoWidth)
		row.info:SetHeight(ROW_HEIGHT)
		row.info:SetJustifyH("RIGHT")
		row:EnableMouseWheel(true)
		row:SetScript("OnMouseWheel", function()
			local bar = getglobal(name .. "ScrollBar")
			bar:SetValue(bar:GetValue() - arg1 * ROW_HEIGHT * 3)
		end)
		row:SetScript("OnClick", function()
			click(this.index, arg1)
		end)
		list.rows[i] = row
	end
	return list
end

-- Preview -----------------------------------------------------------------------

local function RefreshModel()
	ui.model:SetUnit("player")
	ui.model:SetRotation(ui.model.rotation)
end

-- VanillaHelpers rebuilds the model over a frame or two, so look again shortly.
local function RefreshModelSoon()
	RefreshModel()
	Debounce(ui.modelTimer, 0.3, RefreshModel)
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
	ui.look:SetText("Current look: " .. M.DescribeOutfit(state))
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

-- Pages -------------------------------------------------------------------------

local ShowTab -- defined below; the slot buttons switch to the Items tab

local function RefreshModels()
	ui.modelList.Refresh()
end

local function FilterModels()
	local count
	ui.modelResult, count = M.FilterCatalog(M.GetCreatureCatalog(), ui.modelSearch:GetText())
	ui.modelCount:SetText(count .. " models")
	ui.modelList.SetCount(count)
end

local function BuildModelsPage(page)
	Label(page, "Creature models", "GameFontNormal", 0, 0)
	ui.modelCount = Label(page, "", "GameFontDisableSmall", 250, -2)
	Label(page, "Search:", nil, 0, -27)
	ui.modelSearch = EditBox(page, "DmorphOctoModelSearch", 220, 50, -22)
	ui.modelSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterModels)
	end)
	ui.modelSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterModels()
	end)
	ui.modelList = List(page, "DmorphOctoModelList", -50, 60, function(row, index)
		local catalog = M.GetCreatureCatalog()
		local i = ui.modelResult[index]
		row.text:SetText(catalog.names[i])
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == M.GetState().display then
			row:LockHighlight()
		end
	end, function(index)
		local catalog = M.GetCreatureCatalog()
		local displayID = catalog.ids[ui.modelResult[index]]
		ui.displayBox:SetText(displayID)
		SetStatus(M.SetDisplay(displayID))
	end)

	local y = -50 - LIST_ROWS * ROW_HEIGHT - 12
	Label(page, "Display ID:", nil, 0, y - 5)
	ui.displayBox = EditBox(page, "DmorphOctoDisplayID", 70, 70, y, 9)
	local function Apply(step)
		local displayID = M.ParseID(ui.displayBox:GetText()) or M.GetState().display
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
		ui.displayBox:SetText(displayID)
		ui.displayBox:ClearFocus()
		SetStatus(M.SetDisplay(displayID))
	end
	ui.displayBox:SetScript("OnEnterPressed", function()
		Apply(0)
	end)
	Button(page, "<", 26, 152, y, function()
		Apply(-1)
	end)
	Button(page, ">", 26, 180, y, function()
		Apply(1)
	end)
	Button(page, "Morph", 70, 210, y, function()
		Apply(0)
	end)
	Label(page, "Use < and > to step through every model ID, including ones not in the list.",
		"GameFontDisableSmall", 0, y - 28)
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
			button:LockHighlight()
		else
			button:UnlockHighlight()
		end
	end
end

local function BuildRacesPage(page)
	Label(page, "Races", "GameFontNormal", 0, 0)
	ui.nativeLabel = Label(page, "", "GameFontDisableSmall", 120, -2)
	Label(page, "Keeps your own skin, face and hair.", "GameFontDisableSmall", 0, -18)
	for race = 1, table.getn(M.RACES) do
		local y = -40 - (race - 1) * 26
		Label(page, M.RACES[race].name, "GameFontHighlight", 10, y - 4)
		for gender = 0, 1 do
			local text = "Male"
			if gender == 1 then
				text = "Female"
			end
			local button = Button(page, text, 90, 150 + gender * 96, y, function()
				SetStatus(M.SetRace(this.race, this.gender))
			end)
			button.race, button.gender = race, gender
			table.insert(ui.raceButtons, button)
		end
	end
	Button(page, "Swap gender", 186, 150, -40 - table.getn(M.RACES) * 26 - 4, function()
		SetStatus(M.ToggleGender())
	end)
end

local function RefreshItems()
	ui.itemList.Refresh()
end

local function FilterItems()
	local count
	ui.itemResult, count = M.FilterCatalog(M.GetItemCatalog(itemSlot), ui.itemSearch:GetText())
	ui.itemSlotLabel:SetText("Items: " .. M.SLOT_NAMES[itemSlot])
	ui.itemCount:SetText(count .. " items")
	ui.itemList.SetCount(count)
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
			ShowItemSlot(order[math.mod(i - 1 + step + count, count) + 1])
			return
		end
	end
end

local function BuildItemsPage(page)
	ui.itemSlotLabel = Label(page, "", "GameFontNormal", 0, 0, "DmorphOctoItemSlotLabel")
	ui.itemCount = Label(page, "", "GameFontDisableSmall", 160, -2)
	Button(page, "<", 26, 296, 3, function()
		CycleSlot(-1)
	end)
	Button(page, ">", 26, 324, 3, function()
		CycleSlot(1)
	end)
	Label(page, "Search:", nil, 0, -27)
	ui.itemSearch = EditBox(page, "DmorphOctoItemSearch", 220, 50, -22)
	ui.itemSearch:SetScript("OnTextChanged", function()
		Debounce(ui.searchTimer, 0.25, FilterItems)
	end)
	ui.itemSearch:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		FilterItems()
	end)
	ui.itemList = List(page, "DmorphOctoItemList", -50, 60, function(row, index)
		local catalog = M.GetItemCatalog(itemSlot)
		local i = ui.itemResult[index]
		local color = ITEM_QUALITY_COLORS[catalog.quality[i]] or ITEM_QUALITY_COLORS[1]
		row.text:SetText(catalog.names[i])
		row.text:SetTextColor(color.r, color.g, color.b)
		row.info:SetText(catalog.ids[i])
		if catalog.ids[i] == M.GetState().items[itemSlot] then
			row:LockHighlight()
		end
	end, function(index)
		local catalog = M.GetItemCatalog(itemSlot)
		local itemID = catalog.ids[ui.itemResult[index]]
		ui.itemBox:SetText(itemID)
		SetStatus(M.SetItem(itemSlot, itemID))
	end)

	local y = -50 - LIST_ROWS * ROW_HEIGHT - 12
	Label(page, "Item ID:", nil, 0, y - 5)
	ui.itemBox = EditBox(page, "DmorphOctoItemID", 70, 55, y, 9)
	local function Apply()
		ui.itemBox:ClearFocus()
		SetStatus(M.SetItem(itemSlot, M.ParseID(ui.itemBox:GetText()) or -1))
	end
	ui.itemBox:SetScript("OnEnterPressed", Apply)
	Button(page, "Apply", 70, 138, y, Apply)
	Button(page, "Use my own gear", 130, 214, y, function()
		ui.itemBox:SetText("")
		SetStatus(M.SetItem(itemSlot, 0))
	end)
	Label(page, "Weapons list everything that fits the hand, including NPC weapons.",
		"GameFontDisableSmall", 0, y - 28)
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
end

local function LoadSelected()
	if not selectedOutfit then
		return SetStatus(false, "Pick an outfit in the list first.")
	end
	SetStatus(M.LoadOutfit(selectedOutfit))
end

local function BuildWardrobePage(page)
	Label(page, "Wardrobe", "GameFontNormal", 0, 0)
	Label(page, "Outfits are shared by all your characters.", "GameFontDisableSmall", 90, -2)
	Label(page, "Name:", nil, 0, -27)
	ui.outfitName = EditBox(page, "DmorphOctoOutfitName", 180, 42, -22, 32)
	local function Save()
		ui.outfitName:ClearFocus()
		local ok, message = M.SaveOutfit(ui.outfitName:GetText())
		if ok then
			selectedOutfit = M.FindOutfit(ui.outfitName:GetText())
		end
		SetStatus(ok, message)
	end
	ui.outfitName:SetScript("OnEnterPressed", Save)
	Button(page, "Save current look", 130, 232, -22, Save)

	ui.outfitList = List(page, "DmorphOctoOutfitList", -50, 190, function(row, index)
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
		"GameFontDisableSmall", 4, -56)

	local y = -50 - LIST_ROWS * ROW_HEIGHT - 12
	Button(page, "Load", 90, 0, y, LoadSelected)
	Button(page, "Delete", 90, 96, y, function()
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
	races = RefreshRaces,
	items = RefreshItems,
	wardrobe = RefreshWardrobe,
}

local function RefreshAll()
	if not (frame and frame:IsVisible()) then
		return
	end
	UpdateSlots()
	REFRESH[currentTab]()
	RefreshModelSoon()
end

ShowTab = function(key)
	currentTab = key
	for i = 1, table.getn(TABS) do
		local tab = TABS[i]
		if tab.key == key then
			ui.pages[tab.key]:Show()
			ui.tabs[tab.key]:LockHighlight()
		else
			ui.pages[tab.key]:Hide()
			ui.tabs[tab.key]:UnlockHighlight()
		end
	end
	if key == "models" and not ui.modelResult then
		FilterModels()
	elseif key == "items" then
		FilterItems()
	end
	UpdateSlots()
	REFRESH[key]()
end

-- Window ------------------------------------------------------------------------

local function Build()
	frame = CreateFrame("Frame", "DmorphOctoFrame", UIParent)
	frame:Hide()
	frame:SetWidth(720)
	frame:SetHeight(500)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetFrameStrata("DIALOG")
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
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
		RefreshModelSoon()
	end)
	frame:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose")
	end)
	-- 1.12 has no event for item info arriving, so redraw the slot icons now
	-- and then: a morphed item's "?" turns into its icon once the client knows it.
	frame:SetScript("OnUpdate", function()
		this.sinceSlots = (this.sinceSlots or 0) + arg1
		if this.sinceSlots > 1 then
			this.sinceSlots = 0
			UpdateSlots()
		end
	end)
	-- Escape closes the window.
	table.insert(UISpecialFrames, "DmorphOctoFrame")

	local header = frame:CreateTexture(nil, "ARTWORK")
	header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	header:SetWidth(320)
	header:SetHeight(64)
	header:SetPoint("TOP", frame, "TOP", 0, 12)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", header, "TOP", 0, -14)
	title:SetText("DMorph |cff33ff99(OctoWoW)|r")
	local close = CreateFrame("Button", "DmorphOctoFrameClose", frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

	ui.searchTimer = NewTimer()
	ui.modelTimer = NewTimer()

	-- Preview: your character, turned by dragging, with the slots around it.
	local model = CreateFrame("PlayerModel", "DmorphOctoModel", frame)
	model:SetWidth(196)
	model:SetHeight(300)
	model:SetPoint("TOPLEFT", frame, "TOPLEFT", 64, -46)
	model.rotation = 0.61
	model:EnableMouse(true)
	model:SetScript("OnMouseDown", function()
		this.dragX = GetCursorPosition()
	end)
	model:SetScript("OnMouseUp", function()
		this.dragX = nil
	end)
	model:SetScript("OnUpdate", function()
		if this.dragX then
			local x = GetCursorPosition()
			this.rotation = this.rotation + (x - this.dragX) * 0.02
			this.dragX = x
			this:SetRotation(this.rotation)
		end
	end)
	model:RegisterEvent("UNIT_MODEL_CHANGED")
	model:SetScript("OnEvent", function()
		if arg1 == "player" then
			RefreshModel()
		end
	end)
	ui.model = model

	local function AddSlots(slots, x)
		for i = 1, table.getn(slots) do
			local slot = slots[i]
			local button = CreateFrame("Button", "DmorphOctoSlot" .. slot, frame)
			button:SetWidth(36)
			button:SetHeight(36)
			button:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -50 - (i - 1) * 44)
			button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			button.icon = button:CreateTexture(nil, "BORDER")
			button.icon:SetAllPoints(button)
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
					SetStatus(M.SetItem(this.slot, 0))
				else
					ShowItemSlot(this.slot)
				end
			end)
			button:SetScript("OnEnter", SlotTooltip)
			button:SetScript("OnLeave", function()
				GameTooltip:Hide()
			end)
			ui.slots[slot] = button
		end
	end
	AddSlots(LEFT_SLOTS, 22)
	AddSlots(RIGHT_SLOTS, 266)

	ui.look = Label(frame, "", "GameFontHighlightSmall", 22, -358)
	ui.look:SetWidth(282)
	ui.look:SetHeight(14)
	Label(frame, "Drag the model to turn it.", "GameFontDisableSmall", 22, -376)
	Button(frame, "Reset model", 136, 22, -398, function()
		SetStatus(M.ResetModel())
	end)
	Button(frame, "Reset everything", 140, 164, -398, function()
		SetStatus(M.ResetAll())
	end)

	-- Tabs and pages.
	for i = 1, table.getn(TABS) do
		local tab = TABS[i]
		ui.tabs[tab.key] = Button(frame, tab.text, 90, PAGE_X + (i - 1) * 94, -38, function()
			ShowTab(this.key)
		end)
		ui.tabs[tab.key].key = tab.key
		local page = CreateFrame("Frame", nil, frame)
		page:SetPoint("TOPLEFT", frame, "TOPLEFT", PAGE_X, PAGE_Y)
		page:SetWidth(380)
		page:SetHeight(360)
		page:Hide()
		ui.pages[tab.key] = page
	end
	BuildModelsPage(ui.pages.models)
	BuildRacesPage(ui.pages.races)
	BuildItemsPage(ui.pages.items)
	BuildWardrobePage(ui.pages.wardrobe)

	ui.status = Label(frame, "", "GameFontHighlightSmall", 22, -440, "DmorphOctoFrameStatus")
	ui.status:SetWidth(676)
	ui.status:SetHeight(36)
	Label(frame, "Morphs only change what you see. Type /dmorph help for chat commands.",
		"GameFontDisableSmall", 22, -472)
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
