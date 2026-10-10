-- DMorph for OctoWoW: other DMorph users see your morph, and you see theirs.
--
-- Each client tells the others what it looks like (body, item morphs, and
-- the mount skin while it rides) on DMorph's own chat channel, which the
-- addon joins itself so no chat window shows it, and with addon messages in a
-- group. Each client then morphs those players on its own screen through
-- VanillaHelpers whenever it has a unit token for them: target, mouseover,
-- target of target, party, raid, or with SuperWoW their GUID. VanillaHelpers
-- only morphs friendly players. Nobody without DMorph sees anything different.
--
-- VanillaHelpers keeps a morph on the player's GUID, but when a player leaves
-- your sight and comes back the game builds them afresh without it. So every
-- fifth of a second the addon looks at the players it knows and puts the look
-- straight back on anyone who has just come back into view.
--
-- Messages: "DMO1 L <display> <mount> <slot:item,...|-> [guid]" is a look
-- (0 = none) and "DMO1 Q <name>,<name>" asks those players for theirs.

local M = DmorphOcto

local CHANNEL = "DmorphOcto"
local TAG = "DMO1"
local TICK, SCAN_GAP = 0.1, 0.2
local SEND_DELAY = 0.5 -- wait this long after a change, so quick changes go in one message
local JOIN_DELAY, READY_DELAY = 3, 2 -- after login: join the channel, then talk
local REPLY_GAP = 3 -- answer questions about us at most this often
local QUERY_GAP = 3 -- ask about new faces at most this often
local ASK_AGAIN = 300 -- ask a player without DMorph again after this long
local REFRESH = 300 -- ask a DMorph user again if we haven't heard from them for this long
local MAX_ASK = 12
local MAX_PEERS = 500

local clock, scanID = 0, 0
local peers, peerCount = {}, 0 -- name -> { display, mount, items, guid, key, version, heard }
local applied = {} -- name -> what we put on them: { display, mount, items, version, scan, away }
local asked, queue, queued = {}, {}, {} -- name -> when we last asked; names to ask about
local timers = {} -- clock times: join, ready, send, group, reply, replied, query, scan
local lastKey, lastMount
local guidWorks -- whether VanillaHelpers took a GUID as a unit token (nil: not tried)

local function Sharing()
	return not M.GetAccount().shareOff
end

local function Seeing()
	return not M.GetAccount().othersOff
end

-- Our look as "display mount items", the parts other clients need.
local function OwnLook()
	local display, items, mount = M.GetSharedLook()
	local parts = {}
	for slot = 1, 19 do
		if items[slot] then
			table.insert(parts, slot .. ":" .. items[slot])
		end
	end
	local itemText = "-"
	if table.getn(parts) > 0 then
		itemText = table.concat(parts, ",")
	end
	return (display or 0) .. " " .. (mount or 0) .. " " .. itemText, mount
end

-- SuperWoW's UnitExists also returns the unit's GUID.
local function GUIDOf(unit)
	local ok, _, guid = pcall(UnitExists, unit)
	if ok and type(guid) == "string" and strfind(guid, "^0x%x+$") then
		return guid
	end
end

local function GroupChannel()
	for i = 1, (MAX_BATTLEFIELD_QUEUES or 3) do
		local ok, status = pcall(GetBattlefieldStatus, i)
		if ok and status == "active" then
			return "BATTLEGROUND"
		end
	end
	if GetNumRaidMembers() > 0 then
		return "RAID"
	elseif GetNumPartyMembers() > 0 then
		return "PARTY"
	end
end

local function ChannelID()
	local id = GetChannelName(CHANNEL)
	if id and id > 0 then
		return id
	end
end

-- Sends to the channel (everyone online with DMorph) and/or the group.
local function Send(text, toChannel, toGroup)
	local id = toChannel and ChannelID()
	if id then
		pcall(SendChatMessage, TAG .. " " .. text, "CHANNEL", nil, id)
	end
	local group = toGroup and GroupChannel()
	if group then
		pcall(SendAddonMessage, TAG, text, group)
	end
end

local function SendLook(toChannel, toGroup)
	local look = "0 0 -"
	if Sharing() then
		look = OwnLook()
	end
	Send("L " .. look .. " " .. (GUIDOf("player") or "-"), toChannel, toGroup)
end

-- Keeps the hidden channel out of every chat window.
local function JoinChannel()
	if not ChannelID() then
		pcall(JoinChannelByName, CHANNEL)
	end
	for i = 1, (NUM_CHAT_WINDOWS or 7) do
		local chatFrame = getglobal("ChatFrame" .. i)
		if chatFrame and chatFrame.channelList and ChatFrame_RemoveChannel then
			for _, name in pairs(chatFrame.channelList) do
				if strupper(name) == strupper(CHANNEL) then
					ChatFrame_RemoveChannel(chatFrame, CHANNEL)
					break
				end
			end
		end
	end
end

-- Putting looks on other players -------------------------------------------

local NONE = { items = {} }

-- Only display IDs the client has (a bad one could break its model).
local function Display(text)
	local id = tonumber(text)
	if id and id > 0 and M.GetDisplayName(id) then
		return id
	end
end

local function IsGUID(token)
	return strfind(token, "^0x") ~= nil
end

-- Party, raid and GUID tokens stay with their player; the others don't, so a
-- mount skin only goes on through the first kind (it has to come off the
-- moment that player dismounts).
local function Steady(token)
	return IsGUID(token) or strfind(token, "^party%d$") ~= nil or strfind(token, "^raid%d+$") ~= nil
end

-- VanillaHelpers errors on players it can't morph (out of sight, hostile).
local function Call(fn, token, a, b)
	if b then
		return pcall(fn, token, a, b)
	end
	return pcall(fn, token, a)
end

-- Puts a player's look on them. `force` sets every part again, for a player
-- the game has just built afresh (their morph is gone on our screen).
local function ApplyTo(name, token)
	local peer = peers[name]
	local want = NONE
	if peer and Seeing() then
		want = peer
	end
	local done = applied[name]
	if not done and want == NONE then
		return
	end
	local ok, shown = pcall(UnitDisplayInfo, token)
	local force = not done or done.away or (ok and want.display and shown ~= want.display)
	if not force and done.version == want.version then
		done.scan = scanID
		return
	end
	done = done or { items = {} }
	if force or want.display ~= done.display then
		local worked = Call(SetUnitDisplayID, token, want.display)
		if IsGUID(token) then
			guidWorks = worked
		end
		if not worked then
			return
		end
		done.display = want.display
	end
	for slot = 1, 19 do
		local item = want.items[slot]
		if item ~= done.items[slot] or (force and item) then
			if Call(SetUnitVisibleItemID, token, slot, item) then
				done.items[slot] = item
			end
		end
	end
	local mount = want.mount
	if mount and not Steady(token) then
		mount = done.mount
	end
	if (mount ~= done.mount or (force and mount)) and type(SetUnitMountDisplayID) == "function" then
		if Call(SetUnitMountDisplayID, token, mount) then
			done.mount = mount
		end
	end
	done.version, done.scan, done.away = want.version, scanID, nil
	if want == NONE and not done.display and not done.mount and not next(done.items) then
		applied[name] = nil
	else
		applied[name] = done
	end
end

local function Ask(name)
	if not queued[name] then
		queued[name] = true
		table.insert(queue, name)
	end
end

-- A unit token: put a known player's look on, or ask about a new face.
local function Visit(token)
	local ok, isPlayer = pcall(UnitIsPlayer, token)
	if not (ok and isPlayer) then
		return
	end
	-- A group member far away has a token but no model to morph.
	local seen, visible = pcall(UnitIsVisible, token)
	if seen and not visible then
		return
	end
	local name = UnitName(token)
	if not name or name == UnitName("player") then
		return
	end
	local peer = peers[name]
	if peer or applied[name] then
		ApplyTo(name, token)
		if peer and clock - peer.heard > REFRESH and clock - (asked[name] or -1000) > REFRESH then
			Ask(name) -- in case we missed a change
		end
	elseif Seeing() and UnitCanAssist("player", token)
		and (not asked[name] or clock - asked[name] > ASK_AGAIN) then
		Ask(name)
	end
end

local function Scan()
	if type(SetUnitDisplayID) ~= "function" then
		return
	end
	scanID = scanID + 1
	Visit("target")
	Visit("mouseover")
	Visit("targettarget")
	if GetNumRaidMembers() > 0 then
		for i = 1, 40 do
			Visit("raid" .. i)
		end
	else
		for i = 1, 4 do
			Visit("party" .. i)
			Visit("party" .. i .. "target")
		end
	end
	-- Without SuperWoW a GUID isn't a unit token, and UnitName finds nothing.
	for name, peer in pairs(peers) do
		if peer.guid then
			local found, unitName = pcall(UnitName, peer.guid)
			if found and unitName == name then
				Visit(peer.guid)
			end
		end
	end
	-- Anyone we didn't see this time may be rebuilt without their look when
	-- we next do, so it goes on again in full then.
	for _, done in pairs(applied) do
		if done.scan ~= scanID then
			done.away = true
		end
	end
end

local function AskQueued()
	local names = {}
	while table.getn(queue) > 0 and table.getn(names) < MAX_ASK do
		local name = table.remove(queue, 1)
		queued[name] = nil
		asked[name] = clock
		table.insert(names, name)
	end
	if table.getn(names) > 0 then
		Send("Q " .. table.concat(names, ","), true, false)
	end
end

-- Messages from other clients ---------------------------------------------------

local function ReadLook(sender, rest)
	local _, _, d, m, itemText, guid = strfind(rest, "^(%d+) (%d+) (%S+) ?(%S*)")
	if not d then
		return
	end
	local key = d .. " " .. m .. " " .. itemText
	local peer = peers[sender]
	asked[sender] = clock
	if peer and peer.key == key then
		peer.heard = clock
		return
	end
	if not peer then
		if peerCount >= MAX_PEERS then
			return
		end
		peerCount = peerCount + 1
	end
	local look = { display = Display(d), mount = Display(m), items = {}, key = key, heard = clock }
	if itemText ~= "-" then
		for slot, item in string.gfind(itemText, "(%d+):(%d+)") do
			slot, item = tonumber(slot), tonumber(item)
			if slot >= 1 and slot <= 19 and item > 0 and item < 1000000 then
				look.items[slot] = item
			end
		end
	end
	if strfind(guid, "^0x%x+$") then
		look.guid = guid
	end
	look.version = (peer and peer.version or 0) + 1
	peers[sender] = look
	Scan()
end

local function Receive(sender, text)
	if not sender or sender == "" or sender == UnitName("player") then
		return
	end
	local _, _, kind, rest = strfind(text or "", "^(%u) (.*)$")
	if kind == "L" then
		ReadLook(sender, rest)
	elseif kind == "Q" and Sharing() then
		local me = UnitName("player")
		for name in string.gfind(rest, "[^,]+") do
			if name == me then
				local at = math.max(clock + 0.2 + math.random() * 0.8, (timers.replied or -100) + REPLY_GAP)
				if not timers.reply or timers.reply > at then
					timers.reply = at
				end
				return
			end
		end
	end
end

-- Your own changes ------------------------------------------------------------

local function OnChange()
	local key, mount = OwnLook()
	if not Sharing() or key == lastKey then
		return
	end
	-- Mounting and dismounting go out at once; other changes wait a moment.
	local at = clock + SEND_DELAY
	if mount ~= lastMount then
		at = clock
	end
	if not timers.send or timers.send > at then
		timers.send = at
	end
end

local function Tick()
	if timers.join and clock >= timers.join then
		timers.join = nil
		JoinChannel()
		timers.ready = clock + READY_DELAY -- joining takes a moment
	end
	if clock >= (timers.scan or 0) then
		timers.scan = clock + SCAN_GAP
		Scan()
	end
	-- Nothing goes out before the channel is joined.
	if not (timers.ready and clock >= timers.ready) then
		return
	end
	if timers.send and clock >= timers.send then
		timers.send = nil
		lastKey, lastMount = OwnLook()
		SendLook(true, true)
		timers.reply = nil -- that answered any question too
	end
	if timers.group and clock >= timers.group then
		timers.group = nil
		SendLook(false, true)
	end
	if timers.reply and clock >= timers.reply then
		timers.reply, timers.replied = nil, clock
		SendLook(true, false)
	end
	if table.getn(queue) > 0 and clock >= (timers.query or 0) then
		timers.query = clock + QUERY_GAP
		AskQueued()
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:SetScript("OnEvent", function()
	if event == "CHAT_MSG_CHANNEL" then
		-- arg9 is the channel's name, arg4 the same with its number.
		local channel = arg9 or string.gsub(arg4 or "", "^%d+%.%s*", "")
		if strupper(channel or "") == strupper(CHANNEL) then
			local _, _, text = strfind(arg1 or "", "^" .. TAG .. " (.*)$")
			if text then
				Receive(arg2, text)
			end
		end
	elseif event == "CHAT_MSG_ADDON" then
		if arg1 == TAG then
			Receive(arg4, arg2)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Visit("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Visit("mouseover")
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- After each loading screen everyone around is built afresh, and we
		-- rejoin if needed. After login we also say who we are.
		for _, done in pairs(applied) do
			done.away = true
		end
		timers.join = clock + JOIN_DELAY
		if not timers.introduced then
			timers.introduced = true
			timers.send = clock + JOIN_DELAY + READY_DELAY + 1 + math.random() * 3
		end
	elseif GroupChannel() then
		timers.group = clock + 1
	end
end)
frame:SetScript("OnUpdate", function()
	clock = clock + arg1
	this.wait = (this.wait or 0) - arg1
	if this.wait <= 0 then
		this.wait = TICK
		Tick()
	end
end)

M.RegisterListener(OnChange)

-- Settings and chat command -------------------------------------------------------

-- Whether you share and see, how many players with DMorph you know of, how
-- many of them are morphed, and whether GUIDs work as tokens (nil: untried).
function M.GetShareStatus()
	local morphed = 0
	for _, peer in pairs(peers) do
		if peer.display or peer.mount or next(peer.items) then
			morphed = morphed + 1
		end
	end
	return Sharing(), Seeing(), peerCount, morphed, guidWorks
end

function M.SetSharing(on)
	M.GetAccount().shareOff = (not on) or nil
	lastKey = nil
	-- Tell the others at once, so they take your morph off when you stop.
	timers.send = clock
	if on then
		return true, "Other DMorph users now see your morph."
	end
	return true, "Other DMorph users no longer see your morph."
end

function M.SetSeeing(on)
	M.GetAccount().othersOff = (not on) or nil
	-- Looks come off (or go on) as their players come by.
	for _, done in pairs(applied) do
		done.away = true
	end
	Scan()
	if on then
		return true, "You now see other DMorph users' morphs."
	end
	return true, "You no longer see other DMorph users' morphs (they come off as you see each player)."
end

local function Report(ok, message)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99DMorph|r: " .. message)
end

M.commands.share = function(args)
	local first, second = strlower(args[1] or ""), strlower(args[2] or "")
	if first == "on" or first == "off" then
		return Report(M.SetSharing(first == "on"))
	elseif first == "others" and (second == "on" or second == "off") then
		return Report(M.SetSeeing(second == "on"))
	end
	local sharing, seeing, known, morphed, guids = M.GetShareStatus()
	local guidText = "not tried yet"
	if guids == true then
		guidText = "yes, nearby players show without a target"
	elseif guids == false then
		guidText = "no, target or mouse over players to show them"
	end
	Report(true, "Others see your morph: " .. (sharing and "on" or "off") .. ". You see theirs: "
		.. (seeing and "on" or "off") .. ". DMorph users seen: " .. known .. " (" .. morphed .. " morphed).")
	Report(true, "SuperWoW GUIDs: " .. guidText .. ".")
	Report(true, "Usage: .share on/off, .share others on/off. Only friendly players can be morphed.")
end
