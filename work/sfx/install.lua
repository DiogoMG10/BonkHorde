-- roblox-sfx: build the verified sounds straight into this place.
-- Generated. Creates SoundService/SFX/<role>, ready to hear immediately.
local SoundService = game:GetService("SoundService")

local root = SoundService:FindFirstChild("SFX")
if not root then
	root = Instance.new("Folder")
	root.Name = "SFX"
	root.Parent = SoundService
end
root:ClearAllChildren()

local BANK = {
	{ role = "ambience_forest", id = 9112764558, volume = 0.25, looped = true },
	{ role = "axe_throw", id = 9119746592, volume = 0.45, looped = false },
	{ role = "banish", id = 136029417452204, volume = 0.5, looped = false },
	{ role = "bone_throw", id = 15674975792, volume = 0.4, looped = false },
	{ role = "boomerang_whoosh", id = 119868279005714, volume = 0.4, looped = false },
	{ role = "boss_death", id = 9126102254, volume = 0.8, looped = false },
	{ role = "boss_roar", id = 133651202885353, volume = 0.7, looped = false },
	{ role = "boss_roots", id = 9120825586, volume = 0.6, looped = false },
	{ role = "boss_slam", id = 74149238738530, volume = 0.7, looped = false },
	{ role = "boss_spawn", id = 9126102694, volume = 0.8, looped = false },
	{ role = "chest_open", id = 115509131608873, volume = 0.6, looped = false },
	{ role = "chest_reveal", id = 134383970285022, volume = 0.6, looped = false },
	{ role = "chest_reveal_legendary", id = 1840076509, volume = 0.7, looped = false },
	{ role = "coin_pickup", id = 93529351909119, volume = 0.35, looped = false },
	{ role = "crate_break", id = 117158373103667, volume = 0.5, looped = false },
	{ role = "death_sting", id = 1837950656, volume = 0.7, looped = false },
	{ role = "enemy_crit", id = 87911326370728, volume = 0.4, looped = false },
	{ role = "enemy_death", id = 98060153996881, volume = 0.3, looped = false },
	{ role = "enemy_hit", id = 109316755832781, volume = 0.3, looped = false },
	{ role = "final_swarm_alarm", id = 17737027571, volume = 0.8, looped = false },
	{ role = "fireball_cast", id = 83533788421264, volume = 0.45, looped = false },
	{ role = "fireball_explode", id = 140278004623742, volume = 0.5, looped = false },
	{ role = "footstep_grass", id = 135037154891351, volume = 0.25, looped = false },
	{ role = "freeze", id = 130739754816577, volume = 0.4, looped = false },
	{ role = "frenzy", id = 133977339172345, volume = 0.6, looped = false },
	{ role = "frost_pulse", id = 140692325552736, volume = 0.4, looped = false },
	{ role = "ghost_wail", id = 128403319571587, volume = 0.35, looped = false },
	{ role = "heal", id = 116368587548012, volume = 0.5, looped = false },
	{ role = "jump", id = 132163823091536, volume = 0.3, looped = false },
	{ role = "land", id = 123350827153183, volume = 0.3, looped = false },
	{ role = "level_up", id = 1301186018, volume = 0.7, looped = false },
	{ role = "lightning_strike", id = 92090867642655, volume = 0.5, looped = false },
	{ role = "magnet", id = 9120733724, volume = 0.6, looped = false },
	{ role = "music_boss", id = 109212175093615, volume = 0.4, looped = true },
	{ role = "music_forest", id = 139164113687966, volume = 0.35, looped = true },
	{ role = "music_menu", id = 112135643561867, volume = 0.35, looped = true },
	{ role = "music_overtime", id = 1842262051, volume = 0.4, looped = true },
	{ role = "music_results", id = 127032334305190, volume = 0.3, looped = true },
	{ role = "offer_pick", id = 80335269981031, volume = 0.6, looped = false },
	{ role = "player_down", id = 9113481220, volume = 0.7, looped = false },
	{ role = "player_hurt", id = 100970228713833, volume = 0.6, looped = false },
	{ role = "portal_enter", id = 76843646912123, volume = 0.6, looped = false },
	{ role = "portal_open", id = 93989620006639, volume = 0.6, looped = false },
	{ role = "pot_break", id = 9117859897, volume = 0.5, looped = false },
	{ role = "refresh", id = 9113578540, volume = 0.5, looped = false },
	{ role = "revive", id = 9116394876, volume = 0.6, looped = false },
	{ role = "rocket_explode", id = 134947109312227, volume = 0.5, looped = false },
	{ role = "rocket_launch", id = 128930562703728, volume = 0.45, looped = false },
	{ role = "shield_break", id = 84416257080892, volume = 0.6, looped = false },
	{ role = "shop_buy", id = 120891770644830, volume = 0.5, looped = false },
	{ role = "shop_denied", id = 97367190838793, volume = 0.5, looped = false },
	{ role = "shrine_charge_loop", id = 126797688359826, volume = 0.4, looped = true },
	{ role = "shrine_complete", id = 5371948450, volume = 0.6, looped = false },
	{ role = "shrine_greed", id = 71523868896758, volume = 0.6, looped = false },
	{ role = "slide", id = 114626769792529, volume = 0.35, looped = true },
	{ role = "sword_swing", id = 135315310485417, volume = 0.45, looped = false },
	{ role = "timer_tick", id = 134410911353980, volume = 0.4, looped = false },
	{ role = "ui_back", id = 87437544236708, volume = 0.5, looped = false },
	{ role = "ui_click", id = 113397864512278, volume = 0.5, looped = false },
	{ role = "ui_confirm", id = 85240253037283, volume = 0.5, looped = false },
	{ role = "ui_hover", id = 105474290615373, volume = 0.3, looped = false },
	{ role = "victory_sting", id = 1836860398, volume = 0.7, looped = false },
	{ role = "xp_pickup", id = 122625848431274, volume = 0.25, looped = false },
}

for _, e in ipairs(BANK) do
	local s = Instance.new("Sound")
	s.Name = e.role
	s.SoundId = "rbxassetid://" .. tostring(e.id)
	s.Volume = e.volume
	s.Looped = e.looped
	s.Parent = root
end

return string.format("installed %d sounds under SoundService.SFX", #BANK)
