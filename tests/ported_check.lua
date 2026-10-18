-- Loads DMorph with this PC's real Data/Ported.lua and counts what each list shows.
dofile("tests/mock_wow.lua")
dofile("Data/Ported.lua")
Mock.portedData, Mock.portedItems = DmorphOcto_PortedData, DmorphOcto_PortedItems
Mock.ResetUI()
Mock.LoadAddon("DmorphOcto.toc")
Mock.Fire("VARIABLES_LOADED")
local c = DmorphOcto.GetCreatureCatalog()
local ported, mounts = 0, 0
for i = 1, c.count do
	if c.kind[i] == DmorphOcto.KIND_PORTED then
		ported = ported + 1
		if c.tags[i] and strfind(c.tags[i], "mount") then mounts = mounts + 1 end
	end
end
print("creature catalogue: " .. c.count .. " entries, ported " .. ported .. " (mounts " .. mounts .. ")")
for _, slot in ipairs({ 16, 17, 18 }) do
	local items, p = DmorphOcto.GetItemCatalog(slot), 0
	for i = 1, items.count do if items.kind[i] == DmorphOcto.KIND_PORTED then p = p + 1 end end
	print("slot " .. slot .. ": " .. items.count .. " items, ported " .. p)
end
