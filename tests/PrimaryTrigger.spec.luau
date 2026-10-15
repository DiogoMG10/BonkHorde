--!strict
-- Specs for the hand-fired primary weapon: what the server accepts from the
-- attack button, how a click is remembered, the cadence, and what a swing can
-- reach across the real map.

local GameConfig = require("../src/shared/Config/GameConfig")
local MapGen = require("../src/shared/Core/MapGen")
local PrimaryTrigger = require("../src/shared/Core/PrimaryTrigger")
local Roster = require("../src/shared/Config/Roster")

local STEP = 1 / GameConfig.SimHz
local BUFFER = GameConfig.PrimaryClickBuffer
local COOLDOWN = Roster.Weapons.Sword.base.Cooldown

local map = MapGen.build(GameConfig.MapSizeStuds, GameConfig.HeightCellStuds, GameConfig.WallHeight)

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

-- Run the weapon for `seconds` of gameplay. `each(tick, simNow, input)` may
-- press or release before every tick. Returns how many attacks fired and the
-- gameplay time of each.
local function simulate(seconds: number, each: (number, number, PrimaryTrigger.Input) -> (), startCd: number?): (number, { number })
	local input = PrimaryTrigger.new()
	local cd = startCd or 0.4
	local fired: { number } = {}
	local now = 0
	for tick = 1, math.floor(seconds / STEP + 0.5) do
		now += STEP
		each(tick, now, input)
		local left, fires = PrimaryTrigger.step(input, cd, STEP, COOLDOWN, now, BUFFER)
		cd = left
		if fires then
			table.insert(fired, now)
		end
	end
	return #fired, fired
end

-- what an automatic weapon does with the same cooldown, as CombatService steps it
local function automatic(seconds: number, startCd: number?): number
	local cd = startCd or 0.4
	local count = 0
	for _ = 1, math.floor(seconds / STEP + 0.5) do
		cd -= STEP
		if cd <= 0 then
			cd += COOLDOWN
			count += 1
		end
	end
	return count
end

return {
	-- ------------------------------------------------------------ what a client may send

	["only a boolean and a real number are accepted"] = function()
		assert(PrimaryTrigger.parse(true, 0.5))
		assert(not PrimaryTrigger.parse("true", 0.5))
		assert(not PrimaryTrigger.parse(true, "0.5"))
		assert(not PrimaryTrigger.parse(nil, nil))
		assert(not PrimaryTrigger.parse(true, { 1 }))
		assert(not PrimaryTrigger.parse(1, 1))
	end,

	["a yaw that is not a number, or is absurd, is refused"] = function()
		assert(not PrimaryTrigger.parse(true, 0 / 0), "NaN")
		assert(not PrimaryTrigger.parse(true, math.huge), "infinity")
		assert(not PrimaryTrigger.parse(true, -math.huge))
		assert(not PrimaryTrigger.parse(true, 1e9))
	end,

	["a yaw is wrapped into one turn"] = function()
		local ok, held, yaw = PrimaryTrigger.parse(true, math.pi * 2 + 0.25)
		assert(ok and held and near(yaw, 0.25))
		local _, _, back = PrimaryTrigger.parse(false, -math.pi * 3)
		assert(back >= -math.pi and back <= math.pi)
	end,

	["yaw zero looks down -z, the way the camera does"] = function()
		local dx, dz = PrimaryTrigger.direction(0)
		assert(near(dx, 0) and near(dz, -1))
		local lx, lz = PrimaryTrigger.direction(math.pi / 2)
		assert(near(lx, -1) and near(lz, 0), "a quarter turn left looks down -x")
	end,

	["a pitch is optional, must be a real number, and is held inside the camera's range"] = function()
		local low, high = math.rad(GameConfig.CameraPitchMin), math.rad(GameConfig.CameraPitchMax)
		local ok, _, _, level = PrimaryTrigger.parse(true, 0.5)
		assert(ok and level == 0, "an old two-value message aims level")
		assert(not PrimaryTrigger.parse(true, 0.5, "up", low, high))
		assert(not PrimaryTrigger.parse(true, 0.5, 0 / 0, low, high), "NaN")
		assert(not PrimaryTrigger.parse(true, 0.5, math.huge, low, high), "infinity")
		local _, _, _, up = PrimaryTrigger.parse(true, 0.5, 1.5, low, high)
		assert(near(up, high), "a client cannot aim above what the camera can look at")
		local _, _, _, down = PrimaryTrigger.parse(true, 0.5, -1.5, low, high)
		assert(near(down, low))
		local _, _, _, mid = PrimaryTrigger.parse(true, 0.5, 0.2, low, high)
		assert(near(mid, 0.2))
	end,

	["a press keeps the pitch for the next shot"] = function()
		local input = PrimaryTrigger.new()
		PrimaryTrigger.press(input, 0.3, 1, 1, 0.4)
		assert(near(input.yaw, 0.3) and near(input.pitch, 0.4))
		PrimaryTrigger.press(input, 0.3, 1.1, 1.1)
		assert(input.pitch == 0, "a press without a pitch is level")
	end,

	-- ------------------------------------------------------------ rate limit

	["a flood of presses is cut to the permitted rate"] = function()
		local input = PrimaryTrigger.new()
		local rate, burst = GameConfig.PrimaryInputRate, GameConfig.PrimaryInputBurst
		local accepted = 0
		-- 1000 messages a second for five seconds
		for i = 1, 5000 do
			if PrimaryTrigger.allow(input, 100 + i / 1000, rate, burst, false) then
				accepted += 1
			end
		end
		assert(accepted <= burst + rate * 5 + 1, "accepted " .. accepted)
		assert(accepted >= rate * 5 - 1, "an honest rate must still get through: " .. accepted)
	end,

	["a release always gets through, even with the bucket empty"] = function()
		local input = PrimaryTrigger.new()
		for _ = 1, 500 do
			PrimaryTrigger.allow(input, 50, GameConfig.PrimaryInputRate, GameConfig.PrimaryInputBurst, false)
		end
		assert(not PrimaryTrigger.allow(input, 50, GameConfig.PrimaryInputRate, GameConfig.PrimaryInputBurst, false))
		assert(PrimaryTrigger.allow(input, 50, GameConfig.PrimaryInputRate, GameConfig.PrimaryInputBurst, true))
	end,

	-- ------------------------------------------------------------ clicks

	["one click on a ready weapon is exactly one attack"] = function()
		local count = simulate(5, function(tick, now, input)
			if tick == 40 then
				PrimaryTrigger.press(input, 0, now, now)
			elseif tick == 42 then
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 1, "attacks: " .. count)
	end,

	["a click shorter than one tick still attacks once"] = function()
		-- press and release both arrive between two ticks
		local count = simulate(5, function(tick, now, input)
			if tick == 40 then
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 1, "attacks: " .. count)
	end,

	["a click just before the weapon is ready is remembered"] = function()
		-- the weapon comes ready at 0.4 s; the click lands 0.2 s earlier
		local count, fired = simulate(3, function(tick, now, input)
			if tick == 4 then
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 1 and near(fired[1], 0.4, STEP + 1e-6), `{count} at {fired[1]}`)
	end,

	["a click too early in the cooldown is dropped, not queued"] = function()
		local count = simulate(6, function(tick, now, input)
			if tick == 20 then
				PrimaryTrigger.press(input, 0, now, now) -- first attack, at 1.0 s
				PrimaryTrigger.release(input, now)
			elseif tick == 24 then
				-- 0.2 s into a 1.1 s cooldown: far outside the buffer
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 1, "the early click must not come back later: " .. count)
	end,

	["clicks during a cooldown never pile up into several attacks"] = function()
		-- one attack, then a click every tick for the whole cooldown and beyond
		local count = simulate(1.0 + COOLDOWN + 0.02, function(tick, now, input)
			if tick >= 20 then
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 2, "one at 1.0 s and one when the cooldown ends, got " .. count)
		-- and after the clicking stops there is nothing left over
		local after = simulate(8, function(tick, now, input)
			if tick >= 20 and tick <= 60 then
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		local expected = simulate(8, function(tick, now, input)
			if tick == 20 then
				PrimaryTrigger.press(input, 0, now, now)
			elseif tick == 61 then
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(after <= expected + 1, `spam {after} against a held button {expected}`)
	end,

	["a second click replaces the remembered one instead of adding to it"] = function()
		local input = PrimaryTrigger.new()
		PrimaryTrigger.press(input, 0.1, 1.00, 1.00)
		PrimaryTrigger.release(input, 1.01)
		PrimaryTrigger.press(input, 0.7, 1.05, 1.05)
		PrimaryTrigger.release(input, 1.06)
		local _, first = PrimaryTrigger.step(input, 0, STEP, COOLDOWN, 1.1, BUFFER)
		assert(first and near(input.yaw, 0.7), "the later click, and its direction, win")
		local _, second = PrimaryTrigger.step(input, 0, STEP, COOLDOWN, 1.15, BUFFER)
		assert(not second, "there was only ever one click to spend")
	end,

	-- ------------------------------------------------------------ holding

	["holding attacks at exactly the automatic cadence"] = function()
		for _, seconds in { 10, 60, 600 } do
			local held = simulate(seconds, function(tick, now, input)
				if tick == 1 then
					PrimaryTrigger.press(input, 0, now, now)
				end
			end)
			local auto = automatic(seconds)
			assert(math.abs(held - auto) <= 1, `{seconds}s: held {held}, automatic {auto}`)
		end
	end,

	["clicking a hundred times a second is no faster than holding"] = function()
		local held = simulate(60, function(tick, now, input)
			if tick == 1 then
				PrimaryTrigger.press(input, 0, now, now)
			end
		end)
		local spam = simulate(60, function(_tick, now, input)
			for _ = 1, 5 do -- five clicks inside every 50 ms tick
				PrimaryTrigger.press(input, 0, now, now)
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(spam <= held, `spam {spam}, held {held}`)
	end,

	["waiting with the weapon ready does not bank a second attack"] = function()
		-- thirty idle seconds, then one press held for a quarter of a second
		local count = simulate(31, function(tick, now, input)
			if tick == 600 then
				PrimaryTrigger.press(input, 0, now, now)
			elseif tick == 605 then
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == 1, "attacks after a long wait: " .. count)
	end,

	["releasing stops the attacks"] = function()
		local count = simulate(20, function(tick, now, input)
			if tick == 1 then
				PrimaryTrigger.press(input, 0, now, now)
			elseif tick == 100 then
				PrimaryTrigger.release(input, now)
			end
		end)
		assert(count == automatic(5), `held for 5 s of 20: {count}`)
	end,

	-- ------------------------------------------------------------ states that must not linger

	["a held button nobody confirms is dropped"] = function()
		local input = PrimaryTrigger.new()
		PrimaryTrigger.press(input, 0, 10, 500)
		PrimaryTrigger.expire(input, 500.9, GameConfig.PrimaryHeldTimeout)
		assert(input.held, "still inside the timeout")
		PrimaryTrigger.expire(input, 501.1, GameConfig.PrimaryHeldTimeout)
		assert(not input.held, "a silent client must stop attacking")
	end,

	["a confirmed hold is kept"] = function()
		local input = PrimaryTrigger.new()
		for i = 0, 20 do
			PrimaryTrigger.press(input, 0, 10 + i * 0.4, 500 + i * 0.4)
			PrimaryTrigger.expire(input, 500 + i * 0.4 + 0.39, GameConfig.PrimaryHeldTimeout)
			assert(input.held)
		end
	end,

	["a pause, a fall or a death wipes both the hold and the click"] = function()
		local input = PrimaryTrigger.new()
		PrimaryTrigger.press(input, 0, 5, 5)
		PrimaryTrigger.clear(input)
		local _, fires = PrimaryTrigger.step(input, 0, STEP, COOLDOWN, 5.05, BUFFER)
		assert(not fires and not input.held and input.clickAt == nil)
	end,

	["a repeated held message is not a new click"] = function()
		-- the client re-sends its state while the button stays down
		local input = PrimaryTrigger.new()
		PrimaryTrigger.press(input, 0, 1, 1)
		local _, first = PrimaryTrigger.step(input, 0, STEP, COOLDOWN, 1.05, BUFFER)
		assert(first)
		PrimaryTrigger.press(input, 0.2, 1.4, 1.4)
		assert(input.clickAt == nil, "only a press after a release is a click")
		PrimaryTrigger.release(input, 1.5)
		local _, after = PrimaryTrigger.step(input, 0, STEP, COOLDOWN, 2.2, BUFFER)
		assert(not after, "nothing may fire once the button is up")
	end,

	-- ------------------------------------------------------------ vertical reach

	["a swing touches an enemy standing on the same ground"] = function()
		-- hero root 3 studs above ground 10; a 4-stud enemy on that ground
		assert(PrimaryTrigger.touchHeight(13, GameConfig.PrimaryReachY, 10, 4) == 13)
	end,

	["a jumping hero still reaches what is under them"] = function()
		local at = PrimaryTrigger.touchHeight(13 + GameConfig.PlayerJumpHeight, GameConfig.PrimaryReachY, 10, 4)
		assert(at == 14, "the top of its head, got " .. tostring(at))
	end,

	["an enemy far above or far below is out of reach"] = function()
		assert(PrimaryTrigger.touchHeight(13, GameConfig.PrimaryReachY, 44, 4) == nil, "up on the plateau")
		assert(PrimaryTrigger.touchHeight(47, GameConfig.PrimaryReachY, 10, 4) == nil, "down at its foot")
	end,

	["a tall boss is touched at the hero's own height"] = function()
		assert(PrimaryTrigger.touchHeight(13, GameConfig.PrimaryReachY, 10, 22) == 13)
	end,

	-- ------------------------------------------------------------ the ground in the way

	["nothing is in the way across the spawn clearing"] = function()
		local y0 = MapGen.heightAt(map, 0, 0) + 3
		local y1 = MapGen.heightAt(map, 12, 0) + 2
		assert(MapGen.sightClear(map, 0, y0, 0, 12, y1, 0))
	end,

	["a walkable ramp does not hide what is standing on it"] = function()
		-- up ramp A onto the plateau: steep enough to notice, and enemies walk it
		local x = -95
		for z = 80, 140, 10 do
			local y0 = MapGen.heightAt(map, x, z) + 3
			local y1 = MapGen.heightAt(map, x, z + 12) + 2
			assert(MapGen.sightClear(map, x, y0, z, x, y1, z + 12), "blocked on the ramp at z " .. z)
			assert(MapGen.sightClear(map, x, y1, z + 12, x, y0, z), "blocked looking back down at z " .. z)
		end
	end,

	["the lip of the plateau hides an enemy standing back from its edge"] = function()
		-- from the foot of the south face to a point well back on the top
		local y0 = MapGen.heightAt(map, 0, 148) + 3
		local y1 = MapGen.heightAt(map, 0, 176) + 2
		assert(y1 - y0 > 25, "this spot should be a tall face")
		assert(not MapGen.sightClear(map, 0, y0, 148, 0, y1, 176))
	end,

	["the east ridge hides what is on its far side"] = function()
		local y0 = MapGen.heightAt(map, 195, -20) + 3
		local y1 = MapGen.heightAt(map, 275, -20) + 2
		assert(not MapGen.sightClear(map, 195, y0, -20, 275, y1, -20))
	end,

	["sight is not the same question as where an enemy may walk"] = function()
		-- straight up the plateau's south face no enemy can step...
		assert(not MapGen.canStep(map, 0, 152, 0, 160, GameConfig.CliffSlope))
		-- ...yet from the foot you can plainly see something standing on that face
		local y0 = MapGen.heightAt(map, 0, 150) + 3
		local y1 = MapGen.heightAt(map, 0, 156) + 2
		assert(MapGen.sightClear(map, 0, y0, 150, 0, y1, 156), "a face you look up at is not a wall you look through")
	end,

	["two points at the same place are always clear"] = function()
		local y = MapGen.heightAt(map, 40, 40) + 3
		assert(MapGen.sightClear(map, 40, y, 40, 40, y, 40))
	end,
}
