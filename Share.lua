-- DMorph for OctoWoW: other DMorph users see your morph, and you see theirs.
--
-- Each client tells the others what it looks like (body, item morphs, and
-- the mount skin while it rides) on DMorph's own chat channel, which the
-- addon joins itself so no chat window shows it, and with addon messages in a
-- group. Each client then morphs those players on its own screen through
-- VanillaHelpers whenever it has a unit token for them: target, mouseover,
-- party, raid, or with SuperWoW their GUID. VanillaHelpers only morphs
-- friendly players and keeps each morph on the player's GUID. Nobody without
-- DMorph sees anything different.
--
-- Messages: "DMO1 L <display> <mount> <slot:item,...|-> [guid]" is a look
-- (0 = none) and "DMO1 Q <name>,<name>" asks those players for theirs.

local M = DmorphOcto

local CHANNEL = "DmorphOcto"
local TAG = "DMO1"
local TICK = 0.25
local SEND_DELAY, MOUNT_DELAY = 2, 0.3
local REPLY_GAP = 5 -- answer questions about us at most this often
local QUERY_GAP = 10 -- ask about new faces at most this often
local ASK_AGAIN = 600 -- ask a player without DMorph again after this long
local STALE = 5 -- put a look on again after not seeing its player this long
local MAX_ASK = 10
local MAX_PEERS = 500

local clock = 0
local peers, peerCount = {}, 0 -- name -> { display, mount, items, guid, key, version }
local applied = {} -- name -> what we put on them: { display, mount, items, version, seen }
local asked, queue, queued = {}, {}, {} -- name -> when we last asked; names to ask about
local timers = {} -- clock times: join, ready, send, group, reply, query, scan
local lastKey, lastMount

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

-- Party, raid and GUID tokens stay with their player; target and mouseover
-- don't, so a mount skin is only put on through the first kind (it has to
-- come off again the moment they dismount).
local function Steady(token)
	return token ~= "target" and token ~= "mouseover"
end

-- VanillaHelpers errors on players it can't morph (out of sight, hostile).
local function Call(fn, token, a, b)
	if b then
		return pcall(fn, token, a, b)
	end
	return pcall(fn, token, a)
end

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
	local force = not done or clock - done.seen > STALE or (ok and want.display and shown ~= want.display)
	if done and not force and done.version == want.version then
		done.seen = clock
		return
	end
	done = done or { items = {} }
	if force or want.display ~= done.display then
		if not Call(SetUnitDisplayID, token, want.display) then
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
	if mount ~= done.mount and type(SetUnitMountDisplayID) == "function" then
		if Call(SetUnitMountDisplayID, token, mount) then
			done.mount = mount
		end
	end
	done.version, done.seen = want.version, clock
	if want == NONE and not done.display and not done.mount and not next(done.items) then
		applied[name] = nil
	else
		applied[name] = done
	end
end

-- A unit token: put a known player's look on, or ask about a new face.
local function Visit(token)
	local ok, isPlayer = pcall(UnitIsPlayer, token)
	if not (ok and isPlayer) then
		return
	end
	local name = UnitName(token)
	if not name or name == UnitName("player") then
		return
	end
	if peers[name] or applied[name] then
		ApplyTo(name, token)
	elseif Seeing() and UnitCanAssist("player", token) and not queued[name]
		and (not asked[name] or clock - asked[name] > ASK_AGAIN) then
		queued[name] = true
		table.insert(queue, name)
	end
end

local function Scan()
	if type(SetUnitDisplayID) ~= "function" then
		return
	end
	Visit("target")
	Visit("mouseover")
	if GetNumRaidMembers() > 0 then
		for i = 1, 40 do
			Visit("raid" .. i)
		end
	else
		for i = 1, 4 do
			Visit("party" .. i)
		end
	end
	-- Without SuperWoW a GUID isn't a unit token, and UnitName finds nothing.
	for name, peer in pairs(peers) do
		if peer.guid then
			local ok, found = pcall(UnitName, peer.guid)
			if ok and found == name then
				Visit(peer.guid)
			end
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
		return
	end
	if not peer then
		if peerCount >= MAX_PEERS then
			return
		end
		peerCount = peerCount + 1
	end
	local look = { display = Display(d), mount = Display(m), items = {}, key = key }
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
				timers.reply = math.max(clock + 0.5 + math.random() * 2, (timers.replied or -100) + REPLY_GAP)
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
	local delay = SEND_DELAY
	if mount ~= lastMount then
		delay = MOUNT_DELAY
	end
	if not timers.send or timers.send > clock + delay then
		timers.send = clock + delay
	end
end

local function Tick()
	if timers.join and clock >= timers.join then
		timers.join = nil
		JoinChannel()
		timers.ready = clock + 3 -- joining takes a moment
	end
	-- Nothing goes out before the channel is joined.
	if not (timers.ready and clock >= timers.ready) then
		return
	end
	if timers.send and clock >= timers.send then
		timers.send = nil
		lastKey, lastMount = OwnLook()
		SendLook(true, true)
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
	if clock >= (timers.scan or 0) then
		timers.scan = clock + 1
		Scan()
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
		-- After each loading screen: rejoin if needed. After login: say who we are.
		timers.join = clock + 6
		if not timers.introduced then
			timers.introduced = true
			timers.send = clock + 10 + math.random() * 10
		end
	elseif GroupChannel() then
		timers.group = clock + 3
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

-- How many players with DMorph you know of, and how many show their morph.
function M.GetShareStatus()
	local morphed = 0
	for _, peer in pairs(peers) do
		if peer.display or peer.mount or next(peer.items) then
			morphed = morphed + 1
		end
	end
	return Sharing(), Seeing(), peerCount, morphed
end

function M.SetSharing(on)
	M.GetAccount().shareOff = (not on) or nil
	lastKey = nil
	-- Tell the others at once, so they take your morph off when you stop.
	timers.send = clock + 0.5
	if on then
		return true, "Other DMorph users now see your morph."
	end
	return true, "Other DMorph users no longer see your morph."
end

function M.SetSeeing(on)
	M.GetAccount().othersOff = (not on) or nil
	-- Looks come off (or go on) as their players come by.
	for _, done in pairs(applied) do
		done.seen = -100
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
	local sharing, seeing, known, morphed = M.GetShareStatus()
	Report(true, "Others see your morph: " .. (sharing and "on" or "off") .. ". You see theirs: "
		.. (seeing and "on" or "off") .. ". DMorph users seen: " .. known .. " (" .. morphed .. " morphed).")
	Report(true, "Usage: .share on/off, .share others on/off. Only friendly players can be morphed.")
end
