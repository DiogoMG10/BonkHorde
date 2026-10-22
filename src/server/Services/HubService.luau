--!nonstrict
-- HubService - life on Skyhold, the island hub (T6/T7).
--
-- Builds the island once the Wardwood's terrain is down (Skyhold/Builder), and
-- gives every player in it a character: their hero, walking the island with
-- the game's own movement and camera. Choosing another hero at a plinth
-- re-dresses that same character in place. A fall off the rim puts the player
-- back on the meadow. When a party's run ends they step back out of the portal,
-- together. Players in a run are left alone: their character belongs to the
-- run (PlayerStateService) until it hands them back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Roster = require(ReplicatedStorage.Shared.Config.Roster)
local Skyhold = require(ReplicatedStorage.Shared.Config.Skyhold)
local SkyholdGen = require(ReplicatedStorage.Shared.Core.SkyholdGen)

local Builder = require(script.Parent.Parent.Skyhold.Builder)
local HeroDress = require(script.Parent.Parent.HeroDress)
local RunAudience = require(script.Parent.Parent.RunAudience)

local HubService = Knit.CreateService({ Name = "HubService" })

local FALL_CHECK = 0.5

function HubService:KnitInit()
	self._plan = SkyholdGen.build(Skyhold)
	self._ready = false
	self._waiting = {} -- players to spawn once the island is built: player -> where
	self._chars = {} -- player -> their island character
	self._spawning = {}
end

function HubService:KnitStart()
	self._party = Knit.GetService("PartyService")
	self._data = Knit.GetService("DataService")
	self._director = Knit.GetService("RunDirectorService")
	local map = Knit.GetService("MapService")

	Players.CharacterAutoLoads = false

	task.spawn(function()
		-- the Wardwood clears all terrain before writing its own: the island goes after
		while not map:IsTerrainReady() do
			task.wait(0.2)
		end
		-- the island's trees come from the Wardwood's kit: wait for them (a while at most)
		local deadline = os.clock() + 60
		while not map:IsArtReady() and os.clock() < deadline do
			task.wait(0.2)
		end
		local ok, err = pcall(function()
			Builder.writeTerrain(self._plan)
		end)
		if not ok then
			warn(`[HubService] island terrain failed: {err}`)
		end
		local failed = Builder.bakeKit()
		if #failed > 0 then
			warn(`[HubService] {#failed} Skyhold kit asset(s) would not bake: {table.concat(failed, ", ")}`)
		end
		local okBuild, errBuild = pcall(function()
			Builder.build(self._plan)
		end)
		if not okBuild then
			warn(`[HubService] island build failed: {errBuild}`)
		end
		self._ready = true
		print("[HubService] Skyhold is ready")
		for player, where in self._waiting do
			task.spawn(self.Spawn, self, player, where)
		end
		table.clear(self._waiting)
	end)
	-- a later rewrite of the Wardwood (the `grass` dev command) clears the island's ground too
	map.TerrainWritten:Connect(function()
		if self._ready then
			Builder.writeTerrain(self._plan)
		end
	end)

	-- a newcomer appears on the meadow once their profile says which hero they wear
	self._data.Loaded:Connect(function(player)
		self:Spawn(player, "spawn")
	end)
	for _, player in Players:GetPlayers() do
		if self._data:IsLoaded(player) then
			task.spawn(self.Spawn, self, player, "spawn")
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		self._waiting[player] = nil
		self._chars[player] = nil
		self._spawning[player] = nil
	end)
	self._party.HeroChanged:Connect(function(player, heroId)
		self:_redress(player, heroId)
	end)
	-- the party is back from the Wardwood: out of the portal, together
	self._director.RunEnded:Connect(function(players)
		for i, player in players do
			task.spawn(self.Spawn, self, player, "return", i)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < FALL_CHECK then
			return
		end
		acc = 0
		self:_catchFalls()
	end)
end

--- The world CFrame of one of the island's named places, the `slot`-th player
--- of a group a step apart so a party does not stand inside itself.
function HubService:PlaceCFrame(where: string, slot: number?): CFrame
	local spot = if where == "return" then Skyhold.Return else Skyhold.Spawn
	local k = (slot or 1) - 1
	local side = if k == 0 then 0 elseif k % 2 == 1 then -1 else 1
	local x = spot.x + side * math.ceil(k / 2) * 4
	local h = SkyholdGen.heightAt(self._plan, x, spot.z) or 0
	local wx, wy, wz = SkyholdGen.world(Skyhold, x, h + 4, spot.z)
	return CFrame.new(wx, wy, wz) * CFrame.Angles(0, math.rad(spot.yaw), 0)
end

--- Is this player's current character their island one?
function HubService:IsOnIsland(player: Player): boolean
	local character = self._chars[player]
	return character ~= nil and player.Character == character and character.Parent ~= nil
end

local function heroSpeed(heroId: string): number
	local def = Roster.Heroes[heroId]
	local delta = def and def.base and def.base.MoveSpeed or 0
	return GameConfig.PlayerWalkSpeed * (1 + delta)
end

local function applyMovement(character: Model, heroId: string)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = heroSpeed(heroId)
	character:SetAttribute("BaseSpeed", speed)
	character:SetAttribute("ExtraJumps", 0)
	character:SetAttribute("Downed", false)
	character:SetAttribute("OnIsland", true)
	humanoid.WalkSpeed = speed
	humanoid.JumpHeight = GameConfig.PlayerJumpHeight
end

--- Put `player` on the island as their hero: on the meadow ("spawn") or
--- stepping out of the portal ("return"). Does nothing for a player in a run.
function HubService:Spawn(player: Player, where: string, slot: number?)
	if player.Parent ~= Players or RunAudience.has(player) or self._spawning[player] then
		return
	end
	if not self._ready then
		self._waiting[player] = where
		return
	end
	self._spawning[player] = true
	local cf = self:PlaceCFrame(where, slot)
	local ok, err = pcall(function()
		player.ReplicationFocus = nil
		player:RequestStreamAroundAsync(cf.Position, 4)
		player:LoadCharacter()
	end)
	self._spawning[player] = nil
	if not ok then
		warn(`[HubService] LoadCharacter failed for {player.Name}: {err}`)
		return
	end
	local character = player.Character
	if not character or RunAudience.has(player) then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not root then
		return
	end
	HeroDress.prepare(character, humanoid)
	local hero = self._party:GetHero(player)
	local okDress, errDress = pcall(HeroDress.dress, character, hero)
	if not okDress then
		warn(`[HubService] hero dressing failed, walking as the avatar: {errDress}`)
	end
	character:PivotTo(cf)
	applyMovement(character, hero)
	self._chars[player] = character
	-- characters do not respawn on their own here (CharacterAutoLoads is off):
	-- should an island character ever die, it comes back on the meadow
	humanoid.Died:Connect(function()
		task.wait(2)
		if self._chars[player] == character and player.Character == character then
			self:Spawn(player, "spawn")
		end
	end)
end

-- a new hero chosen at a plinth: the same character, re-dressed where it stands
function HubService:_redress(player: Player, heroId: string)
	if not self:IsOnIsland(player) then
		return
	end
	local character = self._chars[player]
	local ok, err = pcall(HeroDress.dress, character, heroId)
	if not ok then
		warn(`[HubService] re-dressing failed: {err}`)
		return
	end
	applyMovement(character, heroId)
end

-- off the rim and into the clouds: back on the meadow, no harm done
function HubService:_catchFalls()
	local floor = Skyhold.Origin[2] - Skyhold.FallDepth
	for player, character in self._chars do
		if player.Character == character then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < floor then
				root.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(self:PlaceCFrame("spawn"))
			end
		end
	end
end

return HubService
