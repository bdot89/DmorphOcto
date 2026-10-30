-- DMorph for OctoWoW: other DMorph users see your morph, and you see theirs.
--
-- Each client tells the others what it looks like (body, item morphs, and
-- the mount skin while it rides). Each client then morphs those players on
-- its own screen through VanillaHelpers whenever it has a unit token for
-- them: target, mouseover, target of target, party, raid, or with SuperWoW
-- their GUID. VanillaHelpers only morphs friendly players. Nobody without
-- DMorph sees anything different.
--
-- Talking as little as possible (the server slows down anyone who chats fast):
--  * Group, raid, battleground and guild mates get hidden addon messages.
--    Only players outside those hear us on DMorph's own chat channel, which
--    no chat window shows.
--  * Your changes go out once they stand still for a second (one message for
--    a whole outfit), and only while a DMorph user is in range of you (about
--    28 yards, seen in the last minute). Nothing goes out otherwise: anyone
--    else asks when they come near you.
--  * Only players near you (or in your group) that you target or mouse over
--    are asked whether they have DMorph, and a player without it isn't asked
--    again for a day (remembered between sessions).
--  * Mounting and dismounting is a tiny message of its own that goes first.
--  * Looks are short (base 36) and remembered between sessions. A question
--    carries a fingerprint of the look we remember, and the answer is a
--    fingerprint too when nothing changed.
--
-- VanillaHelpers keeps a morph on the player's GUID, but when a player leaves
-- your sight and comes back the game builds them afresh without it. So every
-- fifth of a second the addon looks at the players it knows and puts the look
-- straight back on anyone who has just come back into view.
--
-- Messages (prefix "DMO2"). A look is "<display> <mount> <items>": display and
-- mount IDs in base 36 (0 = none), items as a slot letter (a = 1 ... s = 19)
-- and an item ID in base 36 each, or "-".
--   L <look> <guid|-> [s<size>] [<ported>]   this is my look
-- A look may carry a fourth part for ported models (Data/Ported.lua, only on
-- PCs that installed the same pack): "P<pack>_<display>_<mount>_<items>".
-- It goes last in L messages, so older DMorph reads only the first three
-- parts and keeps showing the normal look; receivers use it only when their
-- pack is the same (M.GetPortedPack). Fingerprints cover all four parts.
-- Weapon glows (2.23.0) ride along like the size: a "g" token after the guid in
-- L and H messages, a slot letter (p, q, r = 16, 17, 18) and an enchant ID in
-- base 36 per glowing hand ("gp1CE", 0 = no glow), none without glows; older
-- DMorph skips the token. Receivers put a glow on only if their game has it.
-- How weapons are held and sheathed (2.28.0) ride along the same way: a "w"
-- token, per hand a slot letter (p, q) then o / t / - (held one-hand,
-- two-hand, as it is) and b / s / - (sheathed on the back, at the side, as
-- it is): "wp-bqos". Receivers wear a copy held and sheathed that way
-- (DmorphHelper v17).
--   G <glows|->           my weapon glows changed, the rest didn't
-- Picked missiles (2.36.0): a "b" token, the spell visual your ranged attacks
-- fire in base 36 ("b2GC"); "B <visual|0>" when only that changed. Receivers
-- put it on through DmorphHelper_SetUnitShotVisual (v19), if their client
-- flies that visual as a missile.
-- Extra wear (2.29.0): an "x" token, the spell IDs worn in base 36 with "-"
-- between ("xBXT-H"); receivers put the looks they know on through
-- DmorphHelper_SetAura (v17).
--   W <ways|->            how my weapons are held/sheathed changed, the rest didn't
--   X <spells|->          my extra wear changed, the rest didn't
--   M <mount>             my mount skin changed, the rest didn't
--   H <fingerprint> <guid|->  my look is still the one with this fingerprint
--   Q <name>[:<fingerprint>],...  what do these players look like now?
-- Questions are answered on the way they came (channel, group or guild).

local M = DmorphOcto

local CHANNEL, PASSWORD = "DmorphShare", "dmo2"
local OLD_CHANNEL = "DmorphOcto" -- 1.7's channel: left after login
local TAG = "DMO2"
local TICK, SCAN_GAP = 0.1, 0.2
local SETTLE, MAX_WAIT = 1, 3 -- send a changed look once it stands still this long, at most this late
local CHANNEL_GAP, ADDON_GAP = 0.6, 0.2 -- between our messages
local JOIN_DELAY, READY_DELAY = 3, 2 -- after login: join the channel, then talk
local REPLY_GAP = 3 -- answer questions about us at most this often (per way)
local QUERY_GAP = 10 -- ask about players at most this often
local ASK_AGAIN = 3600 -- ask a player again after this long (this session)
local NO_DMORPH_KEEP = 86400 -- a player who didn't answer isn't asked again for a day (any session)
local RECHECK = 120 -- ask a DMorph user who comes back into range whether they changed, at most this often
local CONFIRM_WAIT = 20 -- a player who doesn't answer in this long has no DMorph (now)
local AUDIENCE = 60 -- DMorph users in range this recently, or who asked about us, get our changes
local GUILD_GAP = 120 -- refresh the guild list this often
local KEEP = 14 * 86400 -- forget remembered looks after two weeks
local MAX_ASK = 12
local MAX_PEERS = 500

local clock, scanID = 0, 0
local peers, peerCount = {}, 0 -- name -> { display, mount, items, d, m, it, look, print, guid, version, heard, confirmed }
local applied = {} -- name -> what we put on them: { display, mount, items, version, scan, away }
local asked, queue, queued = {}, {}, {} -- name -> when we last asked; names to ask about; name -> fingerprint or true
local pending = {} -- name -> when a player we know nothing about was asked (no answer = no DMorph)
local noDmorph -- DmorphOctoAccount.noDmorph for this realm: name -> time() they didn't answer
local audience = {} -- name -> when they last showed they see us
local inGroup, inGuild = {}, {} -- names
local replies = {} -- way -> "L" (full look) or "H" (fingerprint)
local timers = {} -- clock times: join, ready, send, first, mount, reply, replied, query, scan, guild, next
local sent = { d = "0", m = "0", it = "-", s = "", p = "", g = "", w = "", x = "" } -- what the others were last told
local cache -- DmorphOctoAccount.peerCache for this realm
local guidWorks -- whether VanillaHelpers took a GUID as a unit token (nil: not tried)
local counts = { channel = 0, hidden = 0 }

local function Sharing()
	return not M.GetAccount().shareOff
end

local function Seeing()
	return not M.GetAccount().othersOff
end

-- Short numbers --------------------------------------------------------------------

local DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function Encode(n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then
		return "0"
	end
	local text = ""
	while n > 0 do
		local digit = math.mod(n, 36)
		text = strsub(DIGITS, digit + 1, digit + 1) .. text
		n = math.floor(n / 36)
	end
	return text
end

local function Decode(text)
	if text and strfind(text, "^[0-9A-Z]+$") and strlen(text) <= 6 then
		return tonumber(text, 36)
	end
end

-- A four-character fingerprint of a look.
local function Fingerprint(look)
	local h = 5381
	for i = 1, strlen(look) do
		h = math.mod(h * 33 + string.byte(look, i), 1679609)
	end
	return Encode(h)
end

-- Our look's three parts, as the others should see it.
local function OwnParts()
	if not Sharing() then
		return "0", "0", "-"
	end
	local display, items, mount = M.GetSharedLook()
	local parts = {}
	for slot = 1, 19 do
		if items[slot] then
			table.insert(parts, string.char(96 + slot) .. Encode(items[slot]))
		end
	end
	local itemText = "-"
	if table.getn(parts) > 0 then
		itemText = table.concat(parts)
	end
	return Encode(display), Encode(mount), itemText
end

local function OwnLook()
	local d, m, it = OwnParts()
	return d .. " " .. m .. " " .. it
end

-- The ported part of our look ("P<pack>_<d>_<m>_<items>"), or "".
local function OwnPorted()
	local pack = M.GetPortedPack and M.GetPortedPack()
	if not (pack and Sharing() and M.GetSharedPorted) then
		return ""
	end
	local display, items, mount = M.GetSharedPorted()
	local parts = {}
	for slot = 1, 19 do
		if items[slot] then
			table.insert(parts, string.char(96 + slot) .. Encode(items[slot]))
		end
	end
	if not display and not mount and table.getn(parts) == 0 then
		return ""
	end
	return "P" .. pack .. "_" .. Encode(display) .. "_" .. Encode(mount) .. "_" .. (table.getn(parts) > 0 and table.concat(parts) or "-")
end

-- Everything a fingerprint covers: the look and its ported part.
local function OwnFull()
	local ported = OwnPorted()
	if ported ~= "" then
		return OwnLook() .. " " .. ported
	end
	return OwnLook()
end

-- SuperWoW's UnitExists also returns the unit's GUID.
local function GUIDOf(unit)
	local ok, _, guid = pcall(UnitExists, unit)
	if ok and type(guid) == "string" and strfind(guid, "^0x%x+$") then
		return guid
	end
end

-- Ways to reach players ------------------------------------------------------------

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

-- The quietest way to reach a player: their group or guild, or the channel.
local function Way(name)
	local group = GroupChannel()
	if group == "BATTLEGROUND" or (group and inGroup[name]) then
		return group
	elseif inGuild[name] then
		return "GUILD"
	end
	return "CHANNEL"
end

local function ChannelID(name)
	local id = GetChannelName(name or CHANNEL)
	if id and id > 0 then
		return id
	end
end

local function Send(text, way)
	if way == "CHANNEL" then
		local id = ChannelID()
		if id and pcall(SendChatMessage, TAG .. " " .. text, "CHANNEL", nil, id) then
			counts.channel = counts.channel + 1
		end
	elseif way then
		if pcall(SendAddonMessage, TAG, text, way) then
			counts.hidden = counts.hidden + 1
		end
	end
	-- The server is slower to forgive the channel.
	local gap = ADDON_GAP
	if way == "CHANNEL" then
		gap = CHANNEL_GAP
	end
	timers.next = math.max(timers.next or 0, clock + gap)
end

-- Where a change of ours has to go: the group always, and whoever else is
-- around with DMorph, through their guild if all of them are guild mates.
local function ChangeWays()
	local ways = {}
	local group = GroupChannel()
	if group then
		ways[group] = true
	end
	for name, at in pairs(audience) do
		if clock - at > AUDIENCE then
			audience[name] = nil
		else
			ways[Way(name)] = true
		end
	end
	if ways.CHANNEL then
		return { CHANNEL = true } -- everyone with DMorph is on it
	end
	return ways
end

local function OurChannel(name)
	if type(name) ~= "string" then
		return false
	end
	name = strupper((string.gsub(name, "^%d+%.%s*", "")))
	return name == strupper(CHANNEL) or name == strupper(OLD_CHANNEL)
end

-- No chat window shows DMorph's channel: its messages, joins and notices are
-- dropped before the chat frames see them, whatever channels they listen to.
local function HideChannel()
	if M.shareChatHooked or type(ChatFrame_OnEvent) ~= "function" then
		return
	end
	M.shareChatHooked = true
	local original = ChatFrame_OnEvent
	ChatFrame_OnEvent = function(event)
		if type(event) == "string" and strsub(event, 1, 16) == "CHAT_MSG_CHANNEL"
			and (OurChannel(arg9) or OurChannel(arg4)) then
			return
		end
		return original(event)
	end
end

local function JoinChannel()
	HideChannel()
	if ChannelID(OLD_CHANNEL) and LeaveChannelByName then
		pcall(LeaveChannelByName, OLD_CHANNEL)
	end
	if not ChannelID() then
		pcall(JoinChannelByName, CHANNEL, PASSWORD)
	end
	for i = 1, (NUM_CHAT_WINDOWS or 7) do
		local chatFrame = getglobal("ChatFrame" .. i)
		if chatFrame and chatFrame.channelList and ChatFrame_RemoveChannel then
			local found = true
			while found do
				found = nil
				for _, name in pairs(chatFrame.channelList) do
					if OurChannel(name) then
						ChatFrame_RemoveChannel(chatFrame, name)
						found = true
						break
					end
				end
			end
		end
	end
end

local function ReadGuild()
	inGuild = {}
	if not (IsInGuild and IsInGuild()) then
		return
	end
	local ok, count = pcall(GetNumGuildMembers)
	for i = 1, (ok and count or 0) do
		local name = GetGuildRosterInfo(i)
		if name then
			inGuild[name] = true
		end
	end
end

-- Rebuilds the group's names; a newcomer hears our look.
local function ReadGroup()
	local before = inGroup
	inGroup = {}
	local raid = GetNumRaidMembers()
	if raid > 0 then
		for i = 1, 40 do
			local name = UnitName("raid" .. i)
			if name then
				inGroup[name] = true
			end
		end
	else
		for i = 1, 4 do
			local name = UnitName("party" .. i)
			if name then
				inGroup[name] = true
			end
		end
	end
	if timers.introduced then
		for name in pairs(inGroup) do
			if not before[name] then
				timers.group = timers.group or clock + 1
				break
			end
		end
	end
end

-- Remembered looks -----------------------------------------------------------------

local function Cache()
	if not cache then
		local account = M.GetAccount()
		if type(account.peerCache) ~= "table" then
			account.peerCache = {}
		end
		local realm = (GetRealmName and GetRealmName()) or "?"
		if type(account.peerCache[realm]) ~= "table" then
			account.peerCache[realm] = {}
		end
		cache = account.peerCache[realm]
		local now = time()
		for name, entry in pairs(cache) do
			if type(entry) ~= "table" or type(entry.look) ~= "string" or now - (tonumber(entry.seen) or 0) > KEEP then
				cache[name] = nil
			end
		end
	end
	return cache
end

-- Players who didn't answer a question: they have no DMorph, for a day.
local function NoDmorph()
	if not noDmorph then
		local account = M.GetAccount()
		if type(account.noDmorph) ~= "table" then
			account.noDmorph = {}
		end
		local realm = (GetRealmName and GetRealmName()) or "?"
		if type(account.noDmorph[realm]) ~= "table" then
			account.noDmorph[realm] = {}
		end
		noDmorph = account.noDmorph[realm]
		local now = time()
		for name, at in pairs(noDmorph) do
			if type(at) ~= "number" or now - at > NO_DMORPH_KEEP then
				noDmorph[name] = nil
			end
		end
	end
	return noDmorph
end

local function KnownWithout(name)
	local at = NoDmorph()[name]
	return at and time() - at <= NO_DMORPH_KEEP
end

-- Someone answered: they have DMorph after all.
local function Answered(name)
	pending[name] = nil
	NoDmorph()[name] = nil
end

-- Putting looks on other players -------------------------------------------

local NONE = { items = {} }

-- Only display IDs the client has (a bad one could break its model).
local function Display(text)
	local id = Decode(text)
	if id and id > 0 and M.GetDisplayName(id) then
		return id
	end
end

-- A ported part puts ported models on a look, if this PC has the same pack
-- and can show them (a model it has, an item DmorphHelper can copy).
local function Overlay(look, ported)
	local _, _, pack, pd, pm, pit = strfind(ported or "", "^P(%w+)_([0-9A-Z]+)_([0-9A-Z]+)_([a-s0-9A-Z%-]+)$")
	if not pack then
		return false
	end
	if pack ~= (M.GetPortedPack and M.GetPortedPack()) then
		return true
	end
	local display, mount = Display(pd), Display(pm)
	if display then
		look.display = display
	end
	if mount then
		look.mount = mount
	end
	if pit ~= "-" then
		for letter, id in string.gfind(pit, "([a-s])([0-9A-Z]+)") do
			local item = Decode(id)
			if item and M.CanShowPortedItem and M.CanShowPortedItem(item) then
				look.items[string.byte(letter) - 96] = item
			end
		end
	end
	return true
end

-- A look from its three parts (and a ported part), or nil if they don't read as one.
local function MakeLook(d, m, it, ported)
	if not (Decode(d) and Decode(m) and it and (it == "-" or strfind(it, "^[a-s][0-9A-Z]+[a-s0-9A-Z]*$"))) then
		return nil
	end
	local look = { display = Display(d), mount = Display(m), items = {}, d = d, m = m, it = it }
	if it ~= "-" then
		for letter, id in string.gfind(it, "([a-s])([0-9A-Z]+)") do
			local item = Decode(id)
			-- 0: a slot their set hides (shows nothing); DMorph before 2.16 skips it.
			if item and item >= 0 and item < 1000000 then
				look.items[string.byte(letter) - 96] = item
			end
		end
	end
	look.look = d .. " " .. m .. " " .. it
	if ported and ported ~= "" and Overlay(look, ported) then
		look.ported = ported
		look.look = look.look .. " " .. ported
	end
	look.print = Fingerprint(look.look)
	return look
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

local function GroupToken(token)
	return strfind(token, "^party%d$") ~= nil or strfind(token, "^raid%d+$") ~= nil
end

-- In range: within follow distance (about 28 yards), or a group member
-- (who hears us through hidden group messages, wherever they are).
local function Near(token)
	if GroupToken(token) then
		return true
	end
	local ok, close = pcall(CheckInteractDistance, token, 4)
	return ok and close and true or false
end

-- VanillaHelpers errors on players it can't morph (out of sight, hostile).
local function Call(fn, token, a, b)
	if b then
		return pcall(fn, token, a, b)
	end
	return pcall(fn, token, a)
end

-- A player's weapon glows, through DmorphHelper (the enchant field of each
-- weapon slot, like your own glows). Checked on every scan, not only when their
-- look changes: the server resends the field when they change weapons, which
-- takes the glow off. Their real enchant is kept to put back when the glow goes.
local function KeepGlows(token, want, done)
	if type(DmorphHelper_SetItemEnchants) ~= "function" or type(DmorphHelper_GetItemEnchants) ~= "function" then
		return
	end
	local wantGlows = want.glows or {}
	done.glows, done.glowReal = done.glows or {}, done.glowReal or {}
	for slot = 16, 18 do
		local glow = wantGlows[slot]
		if glow or done.glows[slot] then
			local ok, p, t = pcall(DmorphHelper_GetItemEnchants, token, slot)
			if ok and type(p) == "number" then
				if glow then
					if p ~= glow or t ~= 0 then
						if p ~= glow then
							done.glowReal[slot] = { p, t or 0 } -- theirs (again, after a resend)
						end
						if pcall(DmorphHelper_SetItemEnchants, token, slot, glow, 0) then
							done.glows[slot] = glow
						end
					else
						done.glows[slot] = glow
					end
				else
					local real = done.glowReal[slot]
					if not real or pcall(DmorphHelper_SetItemEnchants, token, slot, real[1], real[2]) then
						done.glows[slot], done.glowReal[slot] = nil, nil
					end
				end
			end
		end
	end
end

-- A player's extra wear, through DmorphHelper's aura fields (like your own:
-- empty fields from the top down, skipping ones the server uses). Checked on
-- every scan: the server rewrites their fields when their buffs change.
local EXTRA_TOP = 31
local function KeepExtra(token, want, done)
	if type(DmorphHelper_SetAura) ~= "function" or type(DmorphHelper_GetAura) ~= "function" then
		return
	end
	local wanted = {}
	for i = 1, table.getn(want.extra or {}) do
		wanted[M.ExtraForBody and M.ExtraForBody(want.extra[i]) or want.extra[i]] = true
	end
	done.extraSlots = done.extraSlots or {}
	for index, spell in pairs(done.extraSlots) do
		local ok, now = pcall(DmorphHelper_GetAura, token, index)
		if ok and now == spell and not wanted[spell] then
			pcall(DmorphHelper_SetAura, token, index, 0)
			done.extraSlots[index] = nil
		elseif ok and now ~= spell then
			done.extraSlots[index] = nil
		elseif wanted[spell] then
			wanted[spell] = "on"
		end
	end
	local index = EXTRA_TOP
	for i = 1, table.getn(want.extra or {}) do
		local spell = M.ExtraForBody and M.ExtraForBody(want.extra[i]) or want.extra[i]
		if wanted[spell] == true then
			while index >= 0 do
				local ok, now = pcall(DmorphHelper_GetAura, token, index)
				if ok and now == 0 and not done.extraSlots[index] then
					break
				end
				index = index - 1
			end
			if index < 0 then
				return
			end
			if pcall(DmorphHelper_SetAura, token, index, spell) then
				done.extraSlots[index] = spell
			end
			index = index - 1
		end
	end
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
	if not force and done.version == want.version and not done.weaponWait then
		done.scan = scanID
		KeepGlows(token, want, done)
		KeepExtra(token, want, done)
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
	done.weaponWait = nil
	for slot = 1, 19 do
		local item = want.items[slot]
		-- A weapon held or sheathed their way: a copy (their weapon while it waits).
		local way = want.weapons and want.weapons[slot]
		if item and way and M.PeerWeaponID then
			local wait
			item, wait = M.PeerWeaponID(slot, item, way[1], way[2])
			if wait then
				done.weaponWait = true
			end
		end
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
	-- Their size, through DmorphHelper (which every DMorph user may not have):
	-- their own size is read first, to put back when they go back to it.
	local scale = want.scale
	if (scale ~= done.scale or (force and scale)) and type(DmorphHelper_SetScale) == "function" then
		if scale and not done.scale then
			local ok, real = pcall(DmorphHelper_GetScale, token)
			done.scaleReal = ok and type(real) == "number" and real or 1
		end
		if Call(DmorphHelper_SetScale, token, scale or done.scaleReal or 1) then
			done.scale = scale
		end
	end
	KeepGlows(token, want, done)
	KeepExtra(token, want, done)
	-- Their picked missile (DmorphHelper v19 keeps one per player GUID).
	if (want.shot ~= done.shot or (force and want.shot)) and type(DmorphHelper_SetUnitShotVisual) == "function" then
		if Call(DmorphHelper_SetUnitShotVisual, token, want.shot or 0) then
			done.shot = want.shot
		end
	end
	done.version, done.scan, done.away = want.version, scanID, nil
	if want == NONE and not done.display and not done.mount and not next(done.items) and not done.scale and not done.shot
		and not (done.glows and next(done.glows)) and not (done.extraSlots and next(done.extraSlots)) then
		applied[name] = nil
	else
		applied[name] = done
	end
end

-- Asks a player for their look; with the fingerprint we have, they only
-- send it all if it changed.
local function Ask(name, print)
	if not queued[name] then
		table.insert(queue, name)
	end
	queued[name] = print or true
end

local function Unask(name)
	if queued[name] then
		queued[name] = nil
		for i = 1, table.getn(queue) do
			if queue[i] == name then
				table.remove(queue, i)
				break
			end
		end
	end
end

-- Stores a player's look (new or remembered); returns the peer.
local function SetPeer(name, look, guid, confirmed)
	local peer = peers[name]
	if not peer then
		if peerCount >= MAX_PEERS then
			return
		end
		peerCount = peerCount + 1
	end
	look.guid = guid or (peer and peer.guid)
	look.scale = peer and peer.scale -- a full look message sets it again after
	look.glows = peer and peer.glows -- (the same for weapon glows)
	look.weapons = peer and peer.weapons
	look.extra = peer and peer.extra
	look.shot = peer and peer.shot
	look.version = (peer and peer.version or 0) + 1
	look.heard = confirmed and clock or -1000
	look.confirmed = confirmed
	peers[name] = look
	if confirmed then
		Cache()[name] = { look = look.look, guid = look.guid, seen = time() }
	end
	return look
end

local function DropPeer(name)
	if peers[name] then
		peers[name] = nil
		peerCount = peerCount - 1
	end
	Cache()[name] = nil
	audience[name] = nil
end

-- A player we heard from earlier, maybe in another session.
local function Remembered(name)
	local entry = Cache()[name]
	if entry then
		local _, _, d, m, it, ported = strfind(entry.look, "^(%S+) (%S+) (%S+) ?(%S*)$")
		local look = MakeLook(d, m, it, ported)
		if look then
			return SetPeer(name, look, entry.guid, false)
		end
		Cache()[name] = nil
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
	if not peer and Seeing() and UnitCanAssist("player", token) then
		peer = Remembered(name)
	end
	-- Looks go on whatever the distance; messages only go to players in range.
	local near = Near(token)
	if peer or applied[name] then
		local back = not applied[name] or applied[name].away
		ApplyTo(name, token)
		if peer and near then
			audience[name] = clock -- they can see us too
			if (back or not peer.confirmed) and clock - peer.heard > RECHECK
				and clock - (asked[name] or -1000) > RECHECK then
				Ask(name, peer.print) -- in case they changed while away
			end
		end
	elseif near and (token == "target" or token == "mouseover" or GroupToken(token))
		and Seeing() and UnitCanAssist("player", token) and not KnownWithout(name)
		and (not asked[name] or clock - asked[name] > ASK_AGAIN) then
		Ask(name)
	end
end

local function Scan()
	if type(SetUnitDisplayID) ~= "function" then
		return
	end
	scanID = scanID + 1
	ReadGroup()
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

-- Sends the waiting questions, one message per way.
local function AskQueued()
	local byWay, n = {}, 0
	while table.getn(queue) > 0 and n < MAX_ASK do
		local name = table.remove(queue, 1)
		local print = queued[name]
		queued[name] = nil
		asked[name] = clock
		if not peers[name] then
			pending[name] = clock
		end
		local way = Way(name)
		byWay[way] = byWay[way] or {}
		if print == true then
			table.insert(byWay[way], name)
		else
			table.insert(byWay[way], name .. ":" .. print)
		end
		n = n + 1
	end
	for way, names in pairs(byWay) do
		Send("Q " .. table.concat(names, ","), way)
	end
end

-- Messages from other clients ---------------------------------------------------

-- A player's size from a message's "s<percent>" token (none: normal size).
-- Clients before 2.6 send no token and ignore it.
local function SizeOf(token)
	local _, _, pct = strfind(token or "", "^s(%d+)$")
	pct = tonumber(pct)
	if pct and pct >= 10 and pct <= 1000 and pct ~= 100 then
		return pct / 100
	end
end

-- A player's weapon glows from a "g..." token: slot -> enchant ID, only the ones
-- this PC can show (M.IsKnownGlow), and a key to compare them by; nil for none.
local function GlowsOf(token)
	local _, _, list = strfind(token or "", "^g([p-r0-9A-Z]+)$")
	if not list then
		return nil
	end
	local glowsOut, keyParts = {}, {}
	for letter, id in string.gfind(list, "([p-r])([0-9A-Z]+)") do
		local enchant = Decode(id)
		if enchant and enchant < 1000000 and M.IsKnownGlow and M.IsKnownGlow(enchant) then
			local slot = string.byte(letter) - 96
			glowsOut[slot] = enchant
			table.insert(keyParts, slot .. ":" .. enchant)
		end
	end
	if table.getn(keyParts) == 0 then
		return nil
	end
	glowsOut.key = table.concat(keyParts, ",")
	return glowsOut
end

local function SetPeerGlows(name, glowsIn)
	local peer = peers[name]
	if peer and (peer.glows and peer.glows.key) ~= (glowsIn and glowsIn.key) then
		peer.glows = glowsIn
		peer.version = peer.version + 1
		Scan()
	end
end

-- How a player's weapons are held and sheathed, from a "w..." token: slot ->
-- { style, sheath }, and a key to compare by; nil for none.
local WAY_STYLE, WAY_SHEATH = { o = "one", t = "two" }, { b = "back", s = "side" }
local function WeaponsOf(token)
	local _, _, list = strfind(token or "", "^w([pqots%-b]+)$")
	if not list then
		return nil
	end
	local out, keyParts = {}, {}
	for letter, style, sheath in string.gfind(list, "([pq])([ot%-])([bs%-])") do
		if style ~= "-" or sheath ~= "-" then
			out[string.byte(letter) - 96] = { WAY_STYLE[style], WAY_SHEATH[sheath] }
			table.insert(keyParts, letter .. style .. sheath)
		end
	end
	if table.getn(keyParts) == 0 then
		return nil
	end
	out.key = table.concat(keyParts)
	return out
end

local function SetPeerWeapons(name, weaponsIn)
	local peer = peers[name]
	if peer and (peer.weapons and peer.weapons.key) ~= (weaponsIn and weaponsIn.key) then
		peer.weapons = weaponsIn
		peer.version = peer.version + 1
		Scan()
	end
end

-- A player's extra wear from an "x..." token: the spell IDs this PC knows
-- as looks (at most EXTRA_MAX), and a key to compare by; nil for none.
local function ExtraOf(token)
	local _, _, list = strfind(token or "", "^x([0-9A-Z%-]+)$")
	if not list then
		return nil
	end
	local out, catalog = { key = "" }, M.GetExtraWearCatalog and M.GetExtraWearCatalog()
	for id in string.gfind(list, "[0-9A-Z]+") do
		local spell = Decode(id)
		if spell and catalog and catalog.byID[spell] and table.getn(out) < (M.EXTRA_MAX or 6) then
			table.insert(out, spell)
			out.key = out.key .. id .. "-"
		end
	end
	if not out[1] then
		return nil
	end
	return out
end

local function SetPeerExtra(name, extraIn)
	local peer = peers[name]
	if peer and (peer.extra and peer.extra.key) ~= (extraIn and extraIn.key) then
		peer.extra = extraIn
		peer.version = peer.version + 1
		Scan()
	end
end

local function SetPeerSize(name, scale)
	local peer = peers[name]
	if peer and peer.scale ~= scale then
		peer.scale = scale
		peer.version = peer.version + 1
		Scan()
	end
end

-- A player's picked missile from a "b..." token (2.36.0): the spell visual in
-- base 36, only one this PC's client flies as a missile; nil for none.
local function ShotOf(token)
	local _, _, id = strfind(token or "", "^b([0-9A-Z]+)$")
	local visual = Decode(id)
	if not visual or visual == 0 or not M.GetShotCatalog then
		return nil
	end
	local catalog = M.GetShotCatalog()
	if not catalog.byID then
		catalog.byID = {}
		for i = 1, catalog.count do
			catalog.byID[catalog.ids[i]] = true
		end
	end
	return catalog.byID[visual] and visual or nil
end

local function SetPeerShot(name, shot)
	local peer = peers[name]
	if peer and peer.shot ~= shot then
		peer.shot = shot
		peer.version = peer.version + 1
		Scan()
	end
end

local function ReadLook(sender, rest)
	local _, _, d, m, it, guid, more = strfind(rest, "^(%S+) (%S+) (%S+) ?(%S*) ?(.*)$")
	local size, ported, glowToken, wayToken, extraToken, shotToken
	for token in string.gfind(more or "", "%S+") do
		if strfind(token, "^b") then
			shotToken = token
		elseif strfind(token, "^s%d+$") then
			size = token
		elseif strfind(token, "^P") then
			ported = token
		elseif strfind(token, "^g") then
			glowToken = token
		elseif strfind(token, "^w") then
			wayToken = token
		elseif strfind(token, "^x") then
			extraToken = token
		end
	end
	local glowsIn, weaponsIn, extraIn = GlowsOf(glowToken), WeaponsOf(wayToken), ExtraOf(extraToken)
	local look = MakeLook(d, m, it, ported)
	if not look then
		return
	end
	local scale = SizeOf(size)
	if not strfind(guid or "", "^0x%x+$") then
		guid = nil
	end
	Unask(sender)
	Answered(sender)
	asked[sender] = clock
	local peer = peers[sender]
	if peer and peer.look == look.look then
		peer.heard, peer.guid = clock, guid or peer.guid
		if not peer.confirmed then
			peer.confirmed = true
			Cache()[sender] = { look = peer.look, guid = peer.guid, seen = time() }
		end
		SetPeerSize(sender, scale)
		SetPeerGlows(sender, glowsIn)
		SetPeerWeapons(sender, weaponsIn)
		SetPeerExtra(sender, extraIn)
		SetPeerShot(sender, ShotOf(shotToken))
		return
	end
	if SetPeer(sender, look, guid, true) then
		look.scale = scale
		look.glows = glowsIn
		look.weapons = weaponsIn
		look.extra = extraIn
		look.shot = ShotOf(shotToken)
		Scan()
	end
end

-- Mounting or dismounting: only the mount part changed.
local function ReadMount(sender, m)
	local peer = peers[sender]
	if not (peer and peer.confirmed) then
		return
	end
	local look = MakeLook(peer.d, m, peer.it, peer.ported)
	if look and look.look ~= peer.look then
		SetPeer(sender, look, nil, true)
		Scan()
	end
end

-- "Nothing changed": confirms what we remember, else we ask for it all.
local function ReadPrint(sender, print, guid, size, glowToken, wayToken, extraToken, shotToken)
	Unask(sender)
	Answered(sender)
	asked[sender] = clock
	local peer = peers[sender]
	if peer and peer.print == print then
		peer.heard = clock
		SetPeerSize(sender, SizeOf(size))
		SetPeerGlows(sender, GlowsOf(glowToken))
		SetPeerWeapons(sender, WeaponsOf(wayToken))
		SetPeerExtra(sender, ExtraOf(extraToken))
		SetPeerShot(sender, ShotOf(shotToken))
		if strfind(guid or "", "^0x%x+$") then
			peer.guid = guid
		end
		if not peer.confirmed then
			peer.confirmed = true
			Cache()[sender] = { look = peer.look, guid = peer.guid, seen = time() }
		end
	else
		asked[sender] = nil
		Ask(sender)
	end
end

local function ReadQuestion(sender, rest, way)
	local me = UnitName("player")
	for entry in string.gfind(rest, "[^,]+") do
		local _, _, name, print = strfind(entry, "^([^:]+):?(.*)$")
		if name == me then
			if Sharing() then
				audience[sender] = clock
				if print ~= "" and print == Fingerprint(OwnFull()) then
					replies[way] = replies[way] or "H"
				else
					replies[way] = "L"
				end
				local at = math.max(clock + 0.2 + math.random() * 0.8, (timers.replied or -100) + REPLY_GAP)
				if not timers.reply or timers.reply > at then
					timers.reply = at
				end
			end
		elseif way == "CHANNEL" and queued[name] and Way(name) == "CHANNEL" then
			-- Someone else asked first: the answer comes on the channel anyway
			-- (and if none comes, they have no DMorph).
			Unask(name)
			asked[name] = clock
			if not peers[name] then
				pending[name] = clock
			end
		end
	end
end

local function Receive(sender, text, way)
	if not sender or sender == "" or sender == UnitName("player") then
		return
	end
	local _, _, kind, rest = strfind(text or "", "^(%u) (.*)$")
	if kind == "L" then
		ReadLook(sender, rest)
	elseif kind == "M" then
		ReadMount(sender, rest)
	elseif kind == "H" then
		local _, _, print, guid, more = strfind(rest, "^(%S+) ?(%S*) ?(.*)$")
		if print then
			local size, glowToken, wayToken, extraToken, shotToken
			for token in string.gfind(more or "", "%S+") do
				if strfind(token, "^s%d+$") then
					size = token
				elseif strfind(token, "^g") then
					glowToken = token
				elseif strfind(token, "^w") then
					wayToken = token
				elseif strfind(token, "^x") then
					extraToken = token
				elseif strfind(token, "^b") then
					shotToken = token
				end
			end
			ReadPrint(sender, print, guid, size, glowToken, wayToken, extraToken, shotToken)
		end
	elseif kind == "B" then
		-- Only the picked missile changed ("0": their weapon's own again).
		local peer = peers[sender]
		if peer and peer.confirmed then
			SetPeerShot(sender, ShotOf("b" .. rest))
		end
	elseif kind == "G" then
		-- Only the weapon glows changed ("-": none any more).
		local peer = peers[sender]
		if peer and peer.confirmed then
			SetPeerGlows(sender, GlowsOf(rest))
		end
	elseif kind == "X" then
		-- Only the extra wear changed ("-": none any more).
		local peer = peers[sender]
		if peer and peer.confirmed then
			SetPeerExtra(sender, ExtraOf("x" .. rest))
		end
	elseif kind == "W" then
		-- Only how the weapons are held/sheathed changed ("-": as they are).
		local peer = peers[sender]
		if peer and peer.confirmed then
			SetPeerWeapons(sender, WeaponsOf(rest))
		end
	elseif kind == "S" then
		-- Only the size changed.
		local peer = peers[sender]
		if peer and peer.confirmed then
			SetPeerSize(sender, SizeOf("s" .. rest))
		end
	elseif kind == "Q" then
		ReadQuestion(sender, rest, way)
	end
end

-- Your own changes ------------------------------------------------------------

-- Your size as a message token: "s150", or "" at normal size.
local function OwnSize()
	local scale = Sharing() and M.GetScale and M.GetScale()
	local pct = scale and math.floor(scale * 100 + 0.5) or 100
	if pct == 100 then
		return ""
	end
	return "s" .. pct
end

-- Your weapon glows as a message token: "gp1CE...", or "" with none picked.
local function OwnGlows()
	if not (Sharing() and M.GetSharedGlows) then
		return ""
	end
	local picked, parts = M.GetSharedGlows(), {}
	for slot = 16, 18 do
		if picked[slot] then
			table.insert(parts, string.char(96 + slot) .. Encode(picked[slot]))
		end
	end
	if table.getn(parts) == 0 then
		return ""
	end
	return "g" .. table.concat(parts)
end

-- How your weapons are held and sheathed as a message token: "wp-bqos",
-- or "" when they're as they are.
local WAY_CHAR = { one = "o", two = "t", back = "b", side = "s" }
local function OwnWeapons()
	if not (Sharing() and M.GetSharedWeapons) then
		return ""
	end
	local ways, parts = M.GetSharedWeapons(), {}
	for slot = 16, 17 do
		local way = ways[slot]
		if way then
			table.insert(parts, string.char(96 + slot) .. (WAY_CHAR[way[1] or ""] or "-") .. (WAY_CHAR[way[2] or ""] or "-"))
		end
	end
	if table.getn(parts) == 0 then
		return ""
	end
	return "w" .. table.concat(parts)
end

-- Your extra wear as a message token: "xBXT-H", or "" with none.
local function OwnExtra()
	if not (Sharing() and M.GetExtraWear) then
		return ""
	end
	local worn, parts = M.GetExtraWear(), {}
	for i = 1, table.getn(worn) do
		table.insert(parts, Encode(worn[i]))
	end
	if not parts[1] then
		return ""
	end
	return "x" .. table.concat(parts, "-")
end

-- Your picked missile as a message token: "b5Z" (spell visual in base 36), or "".
local function OwnShot()
	local shot = Sharing() and M.GetShot and M.GetShot()
	if not shot or shot == 0 then
		return ""
	end
	return "b" .. Encode(shot)
end

local function OnChange()
	local d, m, it = OwnParts()
	if OwnExtra() ~= sent.x then
		timers.extra = timers.extra or clock + SETTLE
	end
	if OwnShot() ~= (sent.b or "") then
		timers.shot = timers.shot or clock + SETTLE
	end
	if OwnWeapons() ~= sent.w then
		timers.ways = timers.ways or clock + SETTLE
	end
	if OwnGlows() ~= sent.g then
		timers.glow = timers.glow or clock + SETTLE
	end
	-- Mounting and dismounting go out at once; other changes wait until
	-- they stand still a moment.
	if m ~= sent.m then
		timers.mount = timers.mount or clock
	end
	if OwnSize() ~= sent.s then
		timers.size = timers.size or clock + SETTLE
	end
	if OwnPorted() ~= sent.p then
		-- A ported mount or model: the whole look goes (old DMorph ignores that part).
		timers.first = timers.first or clock
		timers.send = math.min(timers.send or clock, clock)
		return
	end
	if d ~= sent.d or it ~= sent.it then
		timers.first = timers.first or clock
		timers.send = math.min(clock + SETTLE, timers.first + MAX_WAIT)
	elseif timers.send then
		timers.send, timers.first = nil, nil -- changed back before it went out
	end
end

-- The size and glow tokens after the guid (size first: DMorph before 2.23 reads
-- the token after an H message's guid as the size, and skips one it can't read).
local function WithSize(text)
	local size = OwnSize()
	if size ~= "" then
		text = text .. " " .. size
	end
	local glow = OwnGlows()
	if glow ~= "" then
		text = text .. " " .. glow
	end
	local ways = OwnWeapons()
	if ways ~= "" then
		text = text .. " " .. ways
	end
	local extra = OwnExtra()
	if extra ~= "" then
		text = text .. " " .. extra
	end
	local shot = OwnShot()
	if shot ~= "" then
		text = text .. " " .. shot
	end
	return text
end

local function LookText()
	local text = WithSize("L " .. OwnLook() .. " " .. (GUIDOf("player") or "-"))
	local ported = OwnPorted()
	if ported ~= "" then
		text = text .. " " .. ported
	end
	return text
end

-- Tells everyone who needs it; that answers any waiting question too.
local function SendLook(ways)
	sent.d, sent.m, sent.it = OwnParts()
	sent.s = OwnSize()
	sent.p = OwnPorted()
	sent.g = OwnGlows()
	sent.w = OwnWeapons()
	sent.x = OwnExtra()
	sent.b = OwnShot()
	timers.send, timers.first, timers.mount, timers.size, timers.glow, timers.ways = nil, nil, nil, nil, nil, nil
	timers.extra, timers.shot = nil, nil
	local text = LookText()
	for way in pairs(ways) do
		Send(text, way)
		replies[way] = nil
	end
	if ways.CHANNEL then
		replies = {} -- everyone with DMorph is on it
	end
end

-- At most one message (to each way it needs) per pass, the most urgent first.
local function SendNext()
	if timers.next and clock < timers.next then
		return
	end
	if timers.mount and clock >= timers.mount then
		timers.mount = nil
		local _, m = OwnParts()
		if m ~= sent.m then
			sent.m = m
			for way in pairs(ChangeWays()) do
				Send("M " .. m, way)
			end
		end
	elseif timers.send and clock >= timers.send then
		SendLook(ChangeWays())
	elseif timers.size and clock >= timers.size then
		timers.size = nil
		local size = OwnSize()
		if size ~= sent.s then
			sent.s = size
			for way in pairs(ChangeWays()) do
				Send("S " .. (size == "" and "100" or strsub(size, 2)), way)
			end
		end
	elseif timers.glow and clock >= timers.glow then
		timers.glow = nil
		local glow = OwnGlows()
		if glow ~= sent.g then
			sent.g = glow
			for way in pairs(ChangeWays()) do
				Send("G " .. (glow == "" and "-" or glow), way)
			end
		end
	elseif timers.extra and clock >= timers.extra then
		timers.extra = nil
		local extra = OwnExtra()
		if extra ~= sent.x then
			sent.x = extra
			for way in pairs(ChangeWays()) do
				Send("X " .. (extra == "" and "-" or strsub(extra, 2)), way)
			end
		end
	elseif timers.shot and clock >= timers.shot then
		timers.shot = nil
		local shot = OwnShot()
		if shot ~= (sent.b or "") then
			sent.b = shot
			for way in pairs(ChangeWays()) do
				Send("B " .. (shot == "" and "0" or strsub(shot, 2)), way)
			end
		end
	elseif timers.ways and clock >= timers.ways then
		timers.ways = nil
		local ways = OwnWeapons()
		if ways ~= sent.w then
			sent.w = ways
			for way in pairs(ChangeWays()) do
				Send("W " .. (ways == "" and "-" or ways), way)
			end
		end
	elseif timers.reply and clock >= timers.reply then
		timers.reply, timers.replied = nil, clock
		local look = OwnFull()
		for way, kind in pairs(replies) do
			replies[way] = nil
			if kind == "L" then
				Send(LookText(), way)
			else
				Send(WithSize("H " .. Fingerprint(look) .. " " .. (GUIDOf("player") or "-")), way)
			end
		end
	elseif table.getn(queue) > 0 and clock >= (timers.query or 0) then
		timers.query = clock + QUERY_GAP
		AskQueued()
	end
end

-- Remembered players who don't answer have stopped using DMorph, and new
-- faces who don't answer have none: neither is asked again for a day.
local function ForgetSilent()
	for name, peer in pairs(peers) do
		if not peer.confirmed and asked[name] and not queued[name] and clock - asked[name] > CONFIRM_WAIT then
			DropPeer(name)
			NoDmorph()[name] = time()
		end
	end
	for name, at in pairs(pending) do
		if clock - at > CONFIRM_WAIT then
			pending[name] = nil
			if not peers[name] then
				NoDmorph()[name] = time()
			end
		end
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
	if clock >= (timers.guild or 0) then
		timers.guild = clock + GUILD_GAP
		if IsInGuild and IsInGuild() and GuildRoster then
			pcall(GuildRoster)
		end
	end
	-- Nothing goes out before the channel is joined.
	if not (timers.ready and clock >= timers.ready) then
		return
	end
	if not timers.introduced then
		-- What we look like now is what everyone will learn by asking.
		timers.introduced = true
		sent.d, sent.m, sent.it = OwnParts()
		sent.s = OwnSize()
		timers.send, timers.first, timers.mount, timers.size = nil, nil, nil, nil
		timers.group = clock
	end
	if timers.group and clock >= timers.group and not (timers.next and clock < timers.next) then
		-- Only the group hears it: anyone else asks when they see us.
		timers.group = nil
		local group = GroupChannel()
		if group then
			Send(LookText(), group)
		end
	end
	SendNext()
	ForgetSilent()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")
frame:SetScript("OnEvent", function()
	if event == "CHAT_MSG_CHANNEL" then
		-- arg9 is the channel's name, arg4 the same with its number.
		if OurChannel(arg9) or OurChannel(arg4) then
			local _, _, text = strfind(arg1 or "", "^" .. TAG .. " (.*)$")
			if text then
				Receive(arg2, text, "CHANNEL")
			end
		end
	elseif event == "CHAT_MSG_ADDON" then
		if arg1 == TAG then
			Receive(arg4, arg2, arg3)
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		Visit("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		Visit("mouseover")
	elseif event == "GUILD_ROSTER_UPDATE" then
		ReadGuild()
	elseif event == "PLAYER_ENTERING_WORLD" then
		-- After each loading screen everyone around is built afresh, and we
		-- rejoin if needed.
		for _, done in pairs(applied) do
			done.away = true
		end
		timers.join = clock + JOIN_DELAY
		timers.guild = clock + 1
		Cache() -- forgets old looks
	else
		ReadGroup()
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
-- many of them are morphed, whether GUIDs work as tokens (nil: untried), and
-- how many messages went out on the channel and hidden.
function M.GetShareStatus()
	local morphed = 0
	for _, peer in pairs(peers) do
		if peer.display or peer.mount or next(peer.items) then
			morphed = morphed + 1
		end
	end
	return Sharing(), Seeing(), peerCount, morphed, guidWorks, counts.channel, counts.hidden
end

function M.SetSharing(on)
	M.GetAccount().shareOff = (not on) or nil
	-- The others hear at once, so they take your morph off when you stop.
	OnChange()
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
	local sharing, seeing, known, morphed, guids, onChannel, hidden = M.GetShareStatus()
	local guidText = "not tried yet"
	if guids == true then
		guidText = "yes, nearby players show without a target"
	elseif guids == false then
		guidText = "no, target or mouse over players to show them"
	end
	Report(true, "Others see your morph: " .. (sharing and "on" or "off") .. ". You see theirs: "
		.. (seeing and "on" or "off") .. ". DMorph users seen: " .. known .. " (" .. morphed .. " morphed).")
	Report(true, "SuperWoW GUIDs: " .. guidText .. ".")
	Report(true, "Messages sent this session: " .. onChannel .. " on the channel, " .. hidden
		.. " hidden to your group or guild.")
	Report(true, "Usage: .share on/off, .share others on/off. Only friendly players can be morphed.")
end
