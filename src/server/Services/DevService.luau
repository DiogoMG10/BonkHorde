--!nonstrict
-- DevService - Studio-only test hooks. Does nothing at all in a live server.
--
-- A running game cannot be asked a question from outside its own scripts, so the
-- playtest needs a way in. Setting the Workspace attribute `BonkDev` to a command
-- string runs it here, and `status` prints one line of state to the Output.
--
--   gold 500 | level 3 | clock 590 | god | hurt 50 | killall | item Nightlight
--   weapon Axe | tp 120 -40 | goto Chest | goto ChargeShrine | goto BossPortal
--   spawn Skeleton 40 | boss | mini Hamlet | bosshp 0.05 | status

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)

local DevService = Knit.CreateService({ Name = "DevService" })

function DevService:KnitStart()
	if not RunService:IsStudio() then
		return
	end
	local players = Knit.GetService("PlayerStateService")
	local director = Knit.GetService("RunDirectorService")
	local enemies = Knit.GetService("EnemyService")
	local xp = Knit.GetService("XPService")
	local upgrades = Knit.GetService("UpgradeService")
	local interactables = Knit.GetService("InteractableService")
	local bosses = Knit.GetService("BossService")
	local mapService = Knit.GetService("MapService")

	local function firstRec()
		return players:All()[1]
	end

	local function teleport(rec, x: number, z: number)
		local character = rec.player.Character
		if character then
			character:PivotTo(CFrame.new(x, mapService:HeightAt(x, z) + 4, z))
		end
	end

	local commands = {}

	function commands.gold(rec, n)
		rec.gold += tonumber(n) or 100
		rec.dirty = true
	end
	function commands.level(_, n)
		for _ = 1, tonumber(n) or 1 do
			xp:Add(xp:Need(), nil)
		end
	end
	function commands.clock(_, n)
		director._clock = tonumber(n) or 0
	end
	function commands.god(rec)
		rec.god = not rec.god
		rec.invulnUntil = if rec.god then math.huge else 0
	end
	function commands.hurt(rec, n)
		rec.invulnUntil = 0
		players:Hurt(rec, tonumber(n) or 10, nil, os.clock())
	end
	function commands.killall(rec)
		local out = {}
		local n = enemies:Query(rec.x, rec.z, 1000, out)
		for i = 1, n do
			enemies:Damage(out[i], 1e7, rec, 0)
		end
	end
	function commands.item(rec, id)
		if Roster.Items[id] then
			players:GrantItem(rec, id)
		end
	end
	function commands.weapon(rec, id)
		if Roster.Weapons[id] then
			players:GrantWeapon(rec, id)
		end
	end
	function commands.tp(rec, x, z)
		teleport(rec, tonumber(x) or 0, tonumber(z) or 0)
	end
	commands["goto"] = function(rec, kind)
		local best, bestD = nil, math.huge
		for _, it in interactables._list do
			if it.kind == kind and it.state ~= "used" and not it.used[rec.player.UserId] then
				local d = (it.x - rec.x) ^ 2 + (it.z - rec.z) ^ 2
				if d < bestD then
					best, bestD = it, d
				end
			end
		end
		if best then
			teleport(rec, best.x + 4, best.z + 4)
			print(`[Dev] goto {kind} id {best.id} at {math.floor(best.x)}, {math.floor(best.z)}`)
		else
			print(`[Dev] no {kind} available`)
		end
	end
	function commands.use(rec, kind)
		-- interact with the nearest interactable of a kind, as if E were pressed
		for _, it in interactables._list do
			if it.kind == kind and (it.x - rec.x) ^ 2 + (it.z - rec.z) ^ 2 < 15 * 15 then
				interactables:_interact(rec, it, os.clock())
				print(`[Dev] used {kind} id {it.id}`)
				return
			end
		end
		print(`[Dev] no {kind} in reach`)
	end
	function commands.spawn(rec, name, n, hpMult)
		for _ = 1, tonumber(n) or 1 do
			enemies:SpawnNear(rec, name, { hpMult = tonumber(hpMult) or 1 }, 30, 60)
		end
	end
	function commands.boss(rec)
		local portal = interactables:GetPortal()
		if portal then
			teleport(rec, portal.x + 6, portal.z + 6)
			director:PortalUsed(portal)
		end
	end
	function commands.mini(_, name)
		bosses:SpawnMini(name or "BoulderBro", os.clock())
	end
	function commands.bosshp(_, fraction)
		for slot in bosses._bosses do
			local hp, maxHp = enemies:Health(slot)
			enemies:Damage(slot, math.max(0, hp - maxHp * (tonumber(fraction) or 0.05)), nil, 0)
		end
	end
	function commands.pick(rec, index)
		local open = upgrades._open[rec]
		if open then
			upgrades:_choose(rec, open, "pick", tonumber(index) or 1)
		end
	end
	function commands.panel(rec, action, index)
		local panel = interactables._panels[rec]
		if panel then
			interactables:_panelChoice(rec, panel, action or "take", tonumber(index) or 0)
			print(`[Dev] panel {panel.kind} {action} {index}`)
		else
			print("[Dev] no panel open")
		end
	end
	-- auto: answer every level-up and panel with its first option, so a scripted
	-- test is never left waiting on a pause
	local auto = false
	function commands.auto()
		auto = not auto
		print(`[Dev] auto {auto}`)
	end
	task.spawn(function()
		while true do
			task.wait(0.25)
			if auto then
				for _, rec in players:All() do
					local open = upgrades._open[rec]
					if open then
						upgrades:_choose(rec, open, "pick", 1)
					end
					local panel = interactables._panels[rec]
					if panel then
						local action = if panel.kind == "chest" then "take" elseif panel.kind == "shop" then "leave" else "pick"
						interactables:_panelChoice(rec, panel, action, 1)
					end
				end
			end
		end
	end)
	function commands.status(rec)
		local w = {}
		for _, weapon in rec.weapons do
			table.insert(w, `{weapon.id}{weapon.level}`)
		end
		local bossCount = 0
		for _ in bosses._bosses do
			bossCount += 1
		end
		print(
			`[Dev] phase={director:GetPhase()} clock={math.floor(director:GetClock())} paused={director:IsPaused()} lvl={xp:GetLevel()} `
				.. `hp={math.floor(rec.hp)}/{math.floor(rec.stats.MaxHP)} sh={math.floor(rec.shield)} gold={rec.gold} kills={director._kills} `
				.. `enemies={enemies:Count()} bosses={bossCount} weapons={table.concat(w, ",")} items={#rec.items} tomes={#rec.tomes} `
				.. `pos={math.floor(rec.x)},{math.floor(rec.y)},{math.floor(rec.z)} downed={rec.downed} `
				.. `tickMs={string.format("%.2f", (director._tickCost or 0) * 1000)}`
		)
	end

	local function run(text: string)
		local parts = string.split(text, " ")
		local name = parts[1]
		local command = commands[name]
		local rec = firstRec()
		if not command then
			print(`[Dev] unknown command {name}`)
			return
		end
		if not rec and name ~= "clock" then
			print(`[Dev] no hero in the run yet (phase {director:GetPhase()})`)
			return
		end
		local ok, err = pcall(command, rec, parts[2], parts[3], parts[4])
		if not ok then
			warn(`[Dev] {text} failed: {err}`)
		end
	end

	Workspace:GetAttributeChangedSignal("BonkDev"):Connect(function()
		local value = Workspace:GetAttribute("BonkDev")
		if typeof(value) == "string" and value ~= "" then
			-- several commands may be chained with ";"
			for _, text in string.split(value, ";") do
				run(string.gsub(text, "^%s+", ""))
			end
			Workspace:SetAttribute("BonkDev", "")
		end
	end)
	Players.PlayerAdded:Connect(function() end)
	print("[Dev] test hooks active (Studio only): set Workspace attribute BonkDev")
end

return DevService
