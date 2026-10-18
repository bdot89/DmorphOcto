-- Draws the window's layout from the mock's anchor points, one SVG per tab,
-- into tests/layout/ (gitignored): frames as boxes, text as text. Not the
-- game's rendering, only where things sit, to catch overlaps and things
-- running off a page. Run with the test host:
--   tools\LuaHost\bin\...\LuaHost.exe tests/layout.lua   (see tools/run_tests.ps1)
dofile("tests/mock_wow.lua")
Mock.ResetUI()
Mock.classicAPI = true
SetUnitDisplayID = function() end
SetUnitVisibleItemID = function() end
SetUnitMountDisplayID = function() end
UnitDisplayInfo = function() return 49, 49, 0 end
VANILLAHELPERS_VERSION = 10102
Mock.LoadAddon("DmorphOcto.toc")
Mock.Fire("VARIABLES_LOADED")
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(0.3)
DmorphOcto_ToggleUI()

local root = DmorphOctoFrame
local cache
local function Find(rel, widget)
	if type(rel) == "string" then
		return getglobal(rel)
	end
	return rel or widget.parent
end

local Rect
local function Spot(r, point)
	local x, y
	if strfind(point, "LEFT") then x = r.l elseif strfind(point, "RIGHT") then x = r.r else x = (r.l + r.r) / 2 end
	if strfind(point, "TOP") then y = r.t elseif strfind(point, "BOTTOM") then y = r.b else y = (r.t + r.b) / 2 end
	return x, y
end

-- l, t, r, b with y going up (the window's top-left corner is 0, 0).
Rect = function(w)
	if w == root then
		return { l = 0, t = 0, r = root.width, b = -root.height }
	end
	if cache[w] then
		return cache[w]
	end
	local pts = w.points
	local width, height = w.width, w.height
	if w.kind == "FontString" and not width then
		width = (w.GetStringWidth and w:GetStringWidth()) or 40
	end
	if w.kind == "FontString" and not height then
		height = 12
	end
	local rect
	if not pts then
		rect = nil
	elseif pts.ALL then
		local target = Rect(pts.ALL)
		rect = target and { l = target.l, t = target.t, r = target.r, b = target.b }
	else
		local xs, ys = {}, {}
		for point, a in pairs(pts) do
			local base = Rect(Find(a[1], w))
			if base then
				local x, y = Spot(base, a[2])
				x, y = x + a[3], y + a[4]
				if strfind(point, "LEFT") then xs.l = x elseif strfind(point, "RIGHT") then xs.r = x else xs.c = x end
				if strfind(point, "TOP") then ys.t = y elseif strfind(point, "BOTTOM") then ys.b = y else ys.c = y end
			end
		end
		width, height = width or 0, height or 0
		local l, r, t, b
		if xs.l and xs.r then l, r = xs.l, xs.r
		elseif xs.l then l, r = xs.l, xs.l + width
		elseif xs.r then l, r = xs.r - width, xs.r
		elseif xs.c then l, r = xs.c - width / 2, xs.c + width / 2 end
		if ys.t and ys.b then t, b = ys.t, ys.b
		elseif ys.t then t, b = ys.t, ys.t - height
		elseif ys.b then t, b = ys.b + height, ys.b
		elseif ys.c then t, b = ys.c + height / 2, ys.c - height / 2 end
		if l and t then
			rect = { l = l, t = t, r = r, b = b }
		end
	end
	cache[w] = rect or false
	return rect
end

local function Esc(s)
	s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
	s = string.gsub(s, "|r", "")
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	return s
end

local function Draw(name)
	cache = {}
	local out = {}
	table.insert(out, string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
		.. 'style="background:#0d0d10;font-family:Arial;font-size:10px">', root.width + 20, root.height + 20))
	local function Walk(w)
		if not w.shown then
			return
		end
		local r = Rect(w)
		if r and w ~= root then
			local x, y, wd, ht = r.l + 10, -r.t + 10, r.r - r.l, r.t - r.b
			if w.kind == "FontString" then
				if type(w.text) == "string" and w.text ~= "" then
					table.insert(out, string.format('<text x="%.0f" y="%.0f" fill="#ddd">%s</text>', x, y + 10, Esc(w.text)))
				end
			elseif w.kind == "Texture" then
				-- skipped: too many
			else
				local colour = "#4a3a66"
				if w.kind == "Button" then colour = "#b46bff" end
				if w.kind == "EditBox" then colour = "#3fa0ff" end
				if w.kind == "Model" or w.kind == "PlayerModel" or w.kind == "DressUpModel" then colour = "#ffd24d" end
				table.insert(out, string.format('<rect x="%.0f" y="%.0f" width="%.0f" height="%.0f" fill="none" stroke="%s" stroke-width="1"/>',
					x, y, math.max(wd, 1), math.max(ht, 1), colour))
				if w.kind == "Button" and type(w.text) == "string" and w.text ~= "" then
					table.insert(out, string.format('<text x="%.0f" y="%.0f" fill="#fff" text-anchor="middle">%s</text>',
						x + wd / 2, y + ht / 2 + 4, Esc(w.text)))
				end
			end
		end
		for _, child in ipairs(w.children) do
			Walk(child)
		end
	end
	Walk(root)
	table.insert(out, "</svg>")
	local f = io.open("tests/layout/" .. name .. ".svg", "w")
	f:write(table.concat(out, "\n"))
	f:close()
end

local tabs = { "Models", "Mounts", "Favourites", "Races", "Glows", "Items", "Slutmog", "Sets", "Wardrobe", "Weather" }
for _, t in ipairs(tabs) do
	Mock.Click(getglobal("DmorphOctoTab" .. t))
	Draw(t)
end
-- The models tab's list view too.
Mock.Click(DmorphOctoTabModels)
Mock.Click(DmorphOctoModelView)
Draw("ModelsList")
print("layout written to tests/layout/")
