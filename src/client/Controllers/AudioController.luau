--!nonstrict
-- AudioController - owns every sound the client makes: music by phase, forest
-- ambience, and the sound for each gameplay event the server replays.
--
-- It only listens. Nothing else in the game waits on a sound, and every play
-- goes through Sfx, which fails inert. Volumes follow the settings sliders
-- (PlayerGui attributes MasterVolume, MusicVolume and SfxVolume): each group is
-- master x its own slider, never above 1, so 100% is the level the SoundBank
-- was mixed at and nothing is ever amplified past it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Knit = require(ReplicatedStorage.Packages.Knit)
local Net = require(ReplicatedStorage.Shared.Net)
local Sfx = require(ReplicatedStorage.Shared.Sfx)
local SoundBank = require(ReplicatedStorage.Shared.Config.SoundBank)

local AudioController = Knit.CreateController({ Name = "AudioController" })

local player = Players.LocalPlayer

-- the shortest gap between two plays of the same busy sound, in seconds
local GAPS = {
	enemy_hit = 0.06,
	enemy_crit = 0.1,
	enemy_death = 0.07,
	xp_pickup = 0.045,
	coin_pickup = 0.06,
	sword_swing = 0.12,
	lightning_strike = 0.15,
	fireball_explode = 0.12,
	rocket_explode = 0.12,
	frost_pulse = 0.3,
	ui_hover = 0.05,
	footstep_grass = 0.2,
}

local MUSIC_FOR = {
	Lobby = "music_menu",
	Intro = "music_forest",
	Playing = "music_forest",
	Overtime = "music_overtime",
	Victory = "music_results",
	Wipe = "music_results",
	Results = "music_results",
}

local PROJ_SOUND = { "fireball_cast", "bone_throw", "boomerang_whoosh", "rocket_launch", nil }

function AudioController:KnitInit()
	self._last = {}
	self._music = nil
	self._musicRole = nil
	self._ambience = nil
	self._bossUp = false

	local function group(name: string): SoundGroup
		local g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
		return g
	end
	self._sfxGroup = group("BonkSfx")
	self._musicGroup = group("BonkMusic")
end

--- Play a one-shot by role. Busy sounds are rate-limited so 300 enemies dying
--- at once is a crunch, not a wall of noise.
function AudioController:Play(role: string, pitchVary: number?, pitch: number?): Sound?
	local gap = GAPS[role]
	local now = os.clock()
	if gap then
		if now - (self._last[role] or 0) < gap then
			return nil
		end
		self._last[role] = now
	end
	local sound = Sfx.play(role, nil, pitchVary)
	if sound then
		sound.SoundGroup = self._sfxGroup
		if pitch then
			sound.PlaybackSpeed = pitch
		end
	end
	return sound
end

--- Play a one-shot from a place in the world (a part or attachment), heard
--- nearer or further as the listener is.
function AudioController:PlayAt(role: string, parent: Instance, pitchVary: number?): Sound?
	local sound = Sfx.play(role, parent, pitchVary)
	if sound then
		sound.SoundGroup = self._sfxGroup
	end
	return sound
end

function AudioController:_setMusic(role: string?)
	if role == self._musicRole then
		return
	end
	self._musicRole = role
	local old = self._music
	if old then
		local out = TweenService:Create(old, TweenInfo.new(0.8), { Volume = 0 })
		out:Play()
		out.Completed:Once(function()
			Sfx.stop(old)
		end)
	end
	self._music = nil
	if role then
		local sound = Sfx.play(role)
		if sound then
			sound.SoundGroup = self._musicGroup
			local target = (SoundBank[role] and SoundBank[role].volume) or 0.35
			sound.Volume = 0
			TweenService:Create(sound, TweenInfo.new(1.2), { Volume = target }):Play()
			self._music = sound
		end
	end
end

function AudioController:_refreshMusic()
	local phase = self._state.phase
	local role = MUSIC_FOR[phase]
	if self._bossUp and (phase == "Playing" or phase == "Overtime") then
		role = "music_boss"
	end
	self:_setMusic(role)

	local inRun = phase ~= "Lobby" and phase ~= "Results"
	if inRun and not self._ambience then
		local a = Sfx.play("ambience_forest")
		if a then
			a.SoundGroup = self._sfxGroup
		end
		self._ambience = a
	elseif not inRun and self._ambience then
		Sfx.stop(self._ambience)
		self._ambience = nil
	end
end

function AudioController:_hookButtons(gui: Instance)
	local function hook(inst: Instance)
		if inst:IsA("GuiButton") then
			inst.Activated:Connect(function()
				self:Play("ui_click", 0.05)
			end)
			inst.MouseEnter:Connect(function()
				-- a grid of tiles (the pause menu's build) would tick on every one passed over
				if not inst:GetAttribute("QuietHover") then
					self:Play("ui_hover", 0.05)
				end
			end)
		end
	end
	for _, d in gui:GetDescendants() do
		hook(d)
	end
	gui.DescendantAdded:Connect(hook)
end

function AudioController:KnitStart()
	self._state = Knit.GetController("StateController")
	local state = self._state
	local playerGui = player:WaitForChild("PlayerGui")

	local function level(name: string, default: number): number
		local value = playerGui:GetAttribute(name)
		return math.clamp(if typeof(value) == "number" then value else default, 0, 1)
	end
	local function volumes()
		local master = level("MasterVolume", 0.7)
		self._musicGroup.Volume = master * level("MusicVolume", 0.45)
		self._sfxGroup.Volume = master * level("SfxVolume", 0.55)
	end
	volumes()
	for _, name in { "MasterVolume", "MusicVolume", "SfxVolume" } do
		playerGui:GetAttributeChangedSignal(name):Connect(volumes)
	end

	task.spawn(Sfx.preload)
	self:_hookButtons(playerGui)

	local lastPhase = state.phase
	state.Changed:Connect(function(key)
		if key ~= "phase" then
			return
		end
		local phase = state.phase
		if phase ~= lastPhase then
			if phase == "Intro" then
				self:Play("portal_enter")
			elseif phase == "Overtime" then
				self:Play("final_swarm_alarm")
			elseif phase == "Victory" then
				self:Play("victory_sting")
			elseif phase == "Wipe" then
				self:Play("death_sting")
			elseif phase == "Lobby" then
				self._bossUp = false
			end
			lastPhase = phase
		end
		self:_refreshMusic()
	end)
	self:_refreshMusic()

	local function on(name: string, handler: (...any) -> ())
		local remote = Net.client(name)
		if remote then
			remote.OnClientEvent:Connect(function(...)
				local ok, err = pcall(handler, ...)
				if not ok then
					warn(`[Audio] {name} failed inert: {err}`)
				end
			end)
		end
	end

	on("Fx", function(name, a1, _a2, _a3, _a4, a5)
		if name == "Slash" then
			self:Play("sword_swing", 0.12)
		elseif name == "Frost" then
			self:Play("frost_pulse", 0.08)
		elseif name == "Bolt" then
			self:Play("lightning_strike", 0.1)
		elseif name == "Burst" then
			self:Play(if a5 == "mirror" then "shield_break" else "fireball_explode", 0.1)
		elseif name == "Axe" then
			self:Play("axe_throw", 0.08)
		elseif name == "LevelUp" then
			self:Play("level_up")
		elseif name == "Pickup" then
			local what = _a2
			self:Play(if what == "Magnet" then "magnet" elseif what == "Snack" then "heal" else "frenzy")
		end
		local _ = a1
	end)

	-- M4.B: a pack arriving sounds its horn, a ghost tide wails
	on("Banner", function(text, style)
		if style == "surge" then
			if string.find(tostring(text), "Ghost") then
				self:Play("ghost_wail", 0.05)
			else
				self:Play("boss_roar", 0.05, 1.45)
			end
		end
	end)

	-- spawn: id, kind, ...; end: id, x, z, boom, ...
	on("Proj", function(op, _id, kind, _z, boom)
		if op == "spawn" then
			local role = PROJ_SOUND[kind]
			if role then
				self:Play(role, 0.1)
			end
		elseif op == "end" and typeof(boom) == "number" and boom > 0 then
			self:Play("fireball_explode", 0.12)
		end
	end)

	on("Hits", function(b: buffer)
		local crit = false
		for i = 0, buffer.len(b) / 5 - 1 do
			if bit32.band(buffer.readu8(b, i * 5 + 4), 3) > 0 then
				crit = true
				break
			end
		end
		self:Play(if crit then "enemy_crit" else "enemy_hit", 0.15)
	end)

	on("EnemyGone", function(b: buffer)
		for i = 0, buffer.len(b) / 3 - 1 do
			if buffer.readu8(b, i * 3 + 2) == 1 then
				self:Play("enemy_death", 0.2)
				break
			end
		end
	end)

	-- gem and coin chimes play as each one reaches its hero (PickupRenderController)

	on("Hurt", function(_amount, dodged, shieldBroke)
		if shieldBroke then
			self:Play("shield_break")
		elseif not dodged then
			self:Play("player_hurt", 0.1)
		end
	end)

	on("Telegraph", function(_x, _z, _radius, delay)
		task.delay(delay or 0, function()
			self:Play("boss_slam", 0.08)
		end)
	end)

	on("Boss", function(list)
		local up = typeof(list) == "table" and #list > 0
		if up and not self._bossUp then
			self:Play("boss_spawn")
			task.delay(0.9, function()
				self:Play("boss_roar")
			end)
		elseif not up and self._bossUp then
			self:Play("boss_death")
		end
		self._bossUp = up
		self:_refreshMusic()
	end)

	on("Offers", function()
		self:Play("offer_pick")
	end)

	on("Panel", function(panel)
		local kind = typeof(panel) == "table" and panel.kind
		if kind == "chest" then
			self:Play("chest_open")
			task.delay(0.5, function()
				self:Play(if panel.rarity == "Legendary" then "chest_reveal_legendary" else "chest_reveal")
			end)
		elseif kind == "shrine" then
			self:Play("shrine_complete")
		elseif kind == "shop" or kind == "statue" then
			self:Play("ui_confirm")
		end
	end)

	on("InteractableState", function(_id, what, data)
		if what == "gone" then
			return
		elseif what == "broken" then
			self:Play(if typeof(data) == "table" and data.kind == "Crate" then "crate_break" else "pot_break", 0.1)
		elseif what == "summoned" or what == "exit" then
			self:Play("portal_open")
		end
	end)

	-- jump and land from the hero itself
	local function character(model: Model)
		local humanoid = model:WaitForChild("Humanoid", 5)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.StateChanged:Connect(function(_old, new)
				if new == Enum.HumanoidStateType.Jumping then
					self:Play("jump", 0.1)
				elseif new == Enum.HumanoidStateType.Landed then
					self:Play("land", 0.1)
				end
			end)
		end
	end
	player.CharacterAdded:Connect(character)
	if player.Character then
		task.spawn(character, player.Character)
	end
end

return AudioController
