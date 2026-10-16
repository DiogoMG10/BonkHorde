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
-- From the lobby too:
--   unlock Frostling   unlock a hero for this session only (no Silver, never saved)
--   site Falls         stand in front of a Wardwood landmark (site alone lists them)
--   marker             show or hide the Sword's aim marker on the ground
--   hop                show or hide real vs intended movement speed (M2.B playtest)
--   sky night          switch the sky live: golden (the default), clear, dusk,
--                      sunset, night, enchanted
--   leaves Grass       re-material every tree's foliage live (LeafyGrass, Grass,
--                      SmoothPlastic, Plastic...; `leaves` alone puts it back)
--   grass full         rewrite the terrain all-grass as before; `grass less` back
--                      to grass in drifts between moss and worn earth (default)
--   font bangers       try a face on the damage numbers and popups (Config/Fonts);
--                      `font bangers numbers` / `font fredoka popups` one of them
-- In a run:
--   maxbuild           fill every weapon and tome slot at the cap (LVL MAX);
--                      `maxbuild 1` leaves the last one a level short

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
	local data = Knit.GetService("DataService")

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
	-- these need no hero, so they also work in the lobby
	local lobbyCommands = { clock = true, unlock = true, marker = true, hop = true, sky = true, leaves = true, font = true, grass = true }

	function commands.unlock(_, id)
		local player = Players:GetPlayers()[1]
		if player and data:DevUnlock(player, id or "") then
			print(`[Dev] {id} unlocked for this session`)
		else
			print(`[Dev] cannot unlock {id}`)
		end
	end
	function commands.hop()
		local on = Workspace:GetAttribute("BonkHopDebug") ~= true
		Workspace:SetAttribute("BonkHopDebug", on)
		print(`[Dev] hop speed readout {if on then "on" else "off"}`)
	end
	function commands.sky(_, name)
		local Look = require(script.Parent.Parent.Wardwood.Look)
		if Look.sky(name or "") then
			print(`[Dev] sky {name}`)
		else
			local names = {}
			for key in Look.Skies do
				table.insert(names, key)
			end
			table.sort(names)
			print(`[Dev] sky is {Look.current()}; skies: {table.concat(names, ", ")}`)
		end
	end
	-- every tree's foliage, found once by its material and shape (moss bands are
	-- Grass cylinders and blocks, so they stay out), with the material it had
	local foliage: { [BasePart]: Enum.Material }? = nil
	function commands.leaves(_, name)
		if not foliage then
			local found = {}
			local map = Workspace:FindFirstChild("Map")
			for _, d in if map then map:GetDescendants() else {} do
				if d:IsA("BasePart") then
					local m = d.Material
					local rounded = d:IsA("Part") and (d.Shape == Enum.PartType.Ball or d:FindFirstChildOfClass("SpecialMesh") ~= nil)
					if m == Enum.Material.LeafyGrass or (m == Enum.Material.Grass and (rounded or d:IsA("WedgePart"))) then
						found[d] = m
					end
				end
			end
			foliage = found
		end
		local ok, material = pcall(function()
			return (Enum.Material :: any)[name or ""]
		end)
		local count = 0
		for part, original in foliage :: any do
			part.Material = if ok and material then material else original
			count += 1
		end
		print(`[Dev] leaves {if ok and material then name else "as built"} on {count} parts`)
	end
	function commands.font(_, name, role)
		local Fonts = require(ReplicatedStorage.Shared.Config.Fonts)
		if not Fonts.Faces[name or ""] then
			print(`[Dev] fonts: {table.concat(Fonts.Order, ", ")} (default {Fonts.Default})`)
			return
		end
		for key, attr in Fonts.Attributes do
			if role == nil or role == key then
				Workspace:SetAttribute(attr, name)
			end
		end
		print(`[Dev] font {name} on {role or "numbers and popups"}`)
	end
	function commands.grass(_, mode)
		if mode ~= "full" and mode ~= "less" then
			print("[Dev] grass full | grass less")
			return
		end
		task.spawn(function()
			mapService:SetGrass(mode)
			print(`[Dev] grass {mode}: terrain rewritten`)
		end)
	end
	function commands.marker()
		local on = Workspace:GetAttribute("BonkAimMarker") ~= true
		Workspace:SetAttribute("BonkAimMarker", on)
		print(`[Dev] aim marker {if on then "on" else "off"}`)
	end

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
		players:Hurt(rec, tonumber(n) or 10, nil, director:Now())
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
	-- a finished build, for the LVL MAX state: free slots filled in roster order,
	-- then every weapon and tome levelled to the cap (`maxbuild 1`: the last one
	-- stops a level short, so the next level-up finishes it)
	function commands.maxbuild(rec, short)
		local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
		local cap = GameConfig.UpgradeMaxLevel
		for _, id in Roster.WeaponOrder do
			if #rec.weapons < GameConfig.WeaponSlots then
				players:GrantWeapon(rec, id)
			end
		end
		for _, id in Roster.TomeOrder do
			if #rec.tomes < GameConfig.TomeSlots and not rec.tomeIndex[id] then
				local def = Roster.Tomes[id]
				players:GrantTome(rec, id, { { stat = def.stat, amount = def.perLevel } })
			end
		end
		local last = if tonumber(short) then rec.tomes[#rec.tomes] else nil
		for _, w in rec.weapons do
			local pool = Roster.Weapons[w.id].pool
			local key = next(pool)
			while w.level < cap do
				players:UpgradeWeapon(rec, w.id, if key then { { stat = key, amount = pool[key] } } else {})
			end
		end
		for _, t in rec.tomes do
			local def = Roster.Tomes[t.id]
			while t.level < (if t == last then cap - 1 else cap) do
				players:GrantTome(rec, t.id, { { stat = def.stat, amount = def.perLevel } })
			end
		end
		print(`[Dev] maxbuild: complete={rec.complete}`)
	end
	function commands.weapon(rec, id)
		if Roster.Weapons[id] then
			players:GrantWeapon(rec, id)
		end
	end
	function commands.tp(rec, x, z)
		teleport(rec, tonumber(x) or 0, tonumber(z) or 0)
	end
	-- the Wardwood's landmarks, for a quick look round in a playtest
	function commands.site(rec, name)
		local World = require(ReplicatedStorage.Shared.Core.World)
		local names = {}
		for _, s in World.Sites do
			table.insert(names, s.name)
			if string.lower(s.name) == string.lower(name or "") then
				-- stand on the spawn side of it, looking at it
				local d = math.sqrt(s.x * s.x + s.z * s.z)
				local back = if d > 1 then (s.clear + 6) / d else 0
				teleport(rec, s.x - s.x * back, s.z - s.z * back)
				print(`[Dev] site {s.name} at {s.x}, {s.z}`)
				return
			end
		end
		print(`[Dev] sites: {table.concat(names, ", ")}`)
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
				interactables:_interact(rec, it, director:Now())
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
		bosses:SpawnMini(name or "BoulderBro", director:Now())
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
				.. `manual={rec.manual} held={rec.input.held} swings={rec.primarySwings or 0} auto={rec.primaryAuto or 0} `
				.. `pos={math.floor(rec.x)},{math.floor(rec.y)},{math.floor(rec.z)} downed={rec.downed} `
				.. `tickMs={string.format("%.2f", (director._tickCost or 0) * 1000)} projs={#Knit.GetService("CombatService")._projs} `
				.. `gems={Knit.GetService("PickupService")._gems} coins={Knit.GetService("PickupService")._coins}`
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
		if not rec and not lobbyCommands[name] then
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
