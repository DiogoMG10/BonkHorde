--!strict
-- HubParty - the rules of the rune circles on Skyhold (T6/T7). Pure: players
-- are user ids, time is passed in, and every move answers whether it happened.
--
-- A circle holds at most one party. Whoever starts one leads it:
--   PLAY SOLO   a closed party of one that is ready at once and counts down
--   OPEN SQUAD  an open party others join (up to `size`), still forming
-- In a squad the leader starts the preparation (and is ready by doing so);
-- every member then confirms READY. All ready: a countdown. Anyone leaving, or
-- unreadying, cancels it safely: a leave ends the preparation, an unready only
-- the countdown. When the countdown ends the party departs (T8: a few seconds
-- held still, sinking into a portal on the ground), committed: nobody can
-- unready or call it off any more, a member leaving the server just drops out.
-- Then it enters the run. A run already on (one Wardwood run per server) makes
-- a finished countdown wait, still ready, and go first when the portal is free
-- again, after a short countdown. With no departure time (`descent` 0) a
-- countdown goes straight into the run. Joining and leaving are only ever these
-- calls; nothing here knows where a player stands.

local HubParty = {}

export type Phase = "forming" | "preparing" | "countdown" | "waiting" | "departing" | "run"

export type Party = {
	circle: number,
	leader: number,
	members: { number },
	mode: string, -- "solo" | "squad"
	phase: Phase,
	ready: { [number]: boolean },
	ends: number?, -- the countdown's end (or the departure's)
	waitSince: number?,
}

export type Hub = {
	circles: number,
	size: number,
	countdown: number,
	soloCountdown: number,
	resume: number, -- the countdown again after waiting for a busy portal
	descent: number, -- the departure, after the countdown
	parties: { [number]: Party },
	memberOf: { [number]: number },
}

function HubParty.new(circles: number, size: number, countdown: number, soloCountdown: number, descent: number?, resume: number?): Hub
	return {
		circles = circles,
		size = size,
		countdown = countdown,
		soloCountdown = soloCountdown,
		resume = resume or soloCountdown,
		descent = descent or 0,
		parties = {},
		memberOf = {},
	}
end

function HubParty.partyOf(hub: Hub, uid: number): Party?
	local circle = hub.memberOf[uid]
	return if circle then hub.parties[circle] else nil
end

local function allReady(party: Party): boolean
	for _, uid in party.members do
		if not party.ready[uid] then
			return false
		end
	end
	return #party.members > 0
end

local function startCountdown(hub: Hub, party: Party, now: number, seconds: number?)
	party.phase = "countdown"
	party.ends = now + (seconds or (if #party.members == 1 then hub.soloCountdown else hub.countdown))
	party.waitSince = nil
end

-- back to forming: the preparation is over, nobody is ready
local function stand(party: Party)
	party.phase = "forming"
	party.ready = {}
	party.ends = nil
	party.waitSince = nil
end

--- Start a party on an empty circle: "solo" (ready and counting down at once)
--- or "squad" (open, forming).
function HubParty.start(hub: Hub, uid: number, circle: number, mode: string, now: number): boolean
	if circle < 1 or circle > hub.circles or hub.parties[circle] or hub.memberOf[uid] then
		return false
	end
	if mode ~= "solo" and mode ~= "squad" then
		return false
	end
	local party: Party = {
		circle = circle,
		leader = uid,
		members = { uid },
		mode = mode,
		phase = "forming",
		ready = {},
	}
	hub.parties[circle] = party
	hub.memberOf[uid] = circle
	if mode == "solo" then
		party.phase = "preparing"
		party.ready[uid] = true
		startCountdown(hub, party, now)
	end
	return true
end

--- Join an open squad that is forming or preparing and has room.
function HubParty.join(hub: Hub, uid: number, circle: number): boolean
	local party = hub.parties[circle]
	if not party or hub.memberOf[uid] or party.mode ~= "squad" or #party.members >= hub.size then
		return false
	end
	if party.phase ~= "forming" and party.phase ~= "preparing" then
		return false -- mid-countdown, waiting or in a run: the party is closed
	end
	table.insert(party.members, uid)
	hub.memberOf[uid] = circle
	return true
end

--- Leave whatever party `uid` is in. A leave during preparation ends it; a
--- leader's leave hands the lead to the next member; the last one out ends the
--- party. Returns the circle left, or nil.
function HubParty.leave(hub: Hub, uid: number): number?
	local circle = hub.memberOf[uid]
	local party = circle and hub.parties[circle]
	if not circle or not party then
		return nil
	end
	hub.memberOf[uid] = nil
	local i = table.find(party.members, uid)
	if i then
		table.remove(party.members, i)
	end
	party.ready[uid] = nil
	if #party.members == 0 then
		hub.parties[circle] = nil
		return circle
	end
	if party.leader == uid then
		party.leader = party.members[1]
	end
	if party.phase ~= "run" and party.phase ~= "departing" then
		stand(party) -- a departing party is committed: the rest go on
	end
	return circle
end

--- The leader starts the preparation (and is ready by doing so).
function HubParty.prepare(hub: Hub, uid: number, now: number): boolean
	local party = HubParty.partyOf(hub, uid)
	if not party or party.leader ~= uid or party.phase ~= "forming" then
		return false
	end
	party.phase = "preparing"
	party.ready = { [uid] = true }
	if allReady(party) then
		startCountdown(hub, party, now)
	end
	return true
end

--- The leader calls the preparation off: back to forming.
function HubParty.cancel(hub: Hub, uid: number): boolean
	local party = HubParty.partyOf(hub, uid)
	if not party or party.leader ~= uid then
		return false
	end
	if party.phase ~= "preparing" and party.phase ~= "countdown" and party.phase ~= "waiting" then
		return false
	end
	if party.mode == "solo" then
		-- a solo party is its own preparation: calling it off ends it
		HubParty.leave(hub, uid)
		return true
	end
	stand(party)
	return true
end

--- A member confirms READY, or takes it back. Everyone ready starts the
--- countdown; taking it back during the countdown (or the wait) stops it.
function HubParty.setReady(hub: Hub, uid: number, ready: boolean, now: number): boolean
	local party = HubParty.partyOf(hub, uid)
	if not party then
		return false
	end
	local phase = party.phase
	if phase ~= "preparing" and phase ~= "countdown" and phase ~= "waiting" then
		return false
	end
	if (party.ready[uid] == true) == ready then
		return false
	end
	if not ready and party.mode == "solo" then
		return HubParty.cancel(hub, uid)
	end
	party.ready[uid] = if ready then true else nil
	if ready then
		if phase == "preparing" and allReady(party) then
			startCountdown(hub, party, now)
		end
	else
		party.phase = "preparing"
		party.ends = nil
		party.waitSince = nil
	end
	return true
end

function HubParty.isReady(hub: Hub, uid: number): boolean
	local party = HubParty.partyOf(hub, uid)
	return party ~= nil and party.ready[uid] == true
end

--- Advance the countdowns. `runActive` is whether the server's one Wardwood
--- run is busy. Returns the party that enters the run now, if any (at most
--- one: the run it starts makes the portal busy for everyone else), and the
--- party that has just begun its departure, if any.
function HubParty.step(hub: Hub, now: number, runActive: boolean): (Party?, Party?)
	local launched: Party? = nil
	local departed: Party? = nil
	local busy = runActive
	-- a departing party has the portal, and enters the run when its time is up
	for circle = 1, hub.circles do
		local party = hub.parties[circle]
		if party and party.phase == "departing" then
			if party.ends and now >= party.ends and not runActive and not launched then
				party.phase = "run"
				party.ends = nil
				launched = party
			end
			busy = true
		end
	end
	-- a countdown ending on a free portal departs; on a busy one it waits
	for circle = 1, hub.circles do
		local party = hub.parties[circle]
		if party and party.phase == "countdown" and party.ends and now >= party.ends then
			if busy then
				party.phase = "waiting"
				party.ends = nil
				party.waitSince = party.waitSince or now
			elseif hub.descent > 0 then
				party.phase = "departing"
				party.ends = now + hub.descent
				departed = party
				busy = true
			else
				party.phase = "run"
				party.ends = nil
				launched = party
				busy = true
			end
		end
	end
	if not busy then
		-- the portal is free: the party that has waited longest goes next, after
		-- a short countdown, unless another is already counting down for it
		local counting = false
		local first: Party? = nil
		for circle = 1, hub.circles do
			local party = hub.parties[circle]
			if party then
				if party.phase == "countdown" then
					counting = true
				elseif party.phase == "waiting" and (not first or (party.waitSince or 0) < (first.waitSince or 0)) then
					first = party
				end
			end
		end
		if first and not counting then
			startCountdown(hub, first, now, hub.resume)
		end
	end
	return launched, departed
end

--- The party's run could not start after all: back to standing on its circle
--- (from its departure or the run).
function HubParty.launchFailed(hub: Hub, circle: number)
	local party = hub.parties[circle]
	if party and (party.phase == "run" or party.phase == "departing") then
		stand(party)
	end
end

--- The party's run is over: it stands on its circle again, nobody ready.
function HubParty.runEnded(hub: Hub, circle: number)
	local party = hub.parties[circle]
	if party and party.phase == "run" then
		stand(party)
	end
end

--- What the clients draw, one entry per occupied circle.
function HubParty.snapshot(hub: Hub, now: number)
	local list = {}
	for circle = 1, hub.circles do
		local party = hub.parties[circle]
		if party then
			local ready = {}
			for uid in party.ready do
				table.insert(ready, uid)
			end
			table.insert(list, {
				circle = circle,
				leader = party.leader,
				members = table.clone(party.members),
				mode = party.mode,
				phase = party.phase,
				ready = ready,
				seconds = if party.ends then math.max(0, party.ends - now) else nil,
			})
		end
	end
	return list
end

return HubParty
