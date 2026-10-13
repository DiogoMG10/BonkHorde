-- roblox-sfx: play the whole bank out loud, spaced by each sound's real length.
-- Generated. Studio plays Sounds in edit mode, so this needs no playtest.
-- Returns immediately and schedules the rest with task.delay, because
-- execute_luau drops its output if the script yields.
local SoundService = game:GetService("SoundService")

local root = SoundService:FindFirstChild("SFX")
if not root then
	return "run install.lua first"
end

local TOUR = {
	{ role = "ambience_forest", length = 36.011 },
	{ role = "axe_throw", length = 1.193 },
	{ role = "banish", length = 1.355 },
	{ role = "bone_throw", length = 1.102 },
	{ role = "boomerang_whoosh", length = 1.187 },
	{ role = "boss_death", length = 5.722 },
	{ role = "boss_roar", length = 4.272 },
	{ role = "boss_roots", length = 2.453 },
	{ role = "boss_slam", length = 2.194 },
	{ role = "boss_spawn", length = 2.891 },
	{ role = "chest_open", length = 0.926 },
	{ role = "chest_reveal", length = 1.833 },
	{ role = "chest_reveal_legendary", length = 2.255 },
	{ role = "coin_pickup", length = 0.478 },
	{ role = "crate_break", length = 1.488 },
	{ role = "death_sting", length = 6.481 },
	{ role = "enemy_crit", length = 0.759 },
	{ role = "enemy_death", length = 0.866 },
	{ role = "enemy_hit", length = 0.642 },
	{ role = "final_swarm_alarm", length = 2.894 },
	{ role = "fireball_cast", length = 0.6 },
	{ role = "fireball_explode", length = 2.009 },
	{ role = "footstep_grass", length = 0.38 },
	{ role = "freeze", length = 0.682 },
	{ role = "frenzy", length = 1.723 },
	{ role = "frost_pulse", length = 1.437 },
	{ role = "ghost_wail", length = 2.961 },
	{ role = "heal", length = 2.0 },
	{ role = "jump", length = 0.279 },
	{ role = "land", length = 0.601 },
	{ role = "level_up", length = 1.853 },
	{ role = "lightning_strike", length = 2.136 },
	{ role = "magnet", length = 1.446 },
	{ role = "music_boss", length = 169.622 },
	{ role = "music_forest", length = 214.167 },
	{ role = "music_menu", length = 160.03 },
	{ role = "music_overtime", length = 68.089 },
	{ role = "music_results", length = 142.577 },
	{ role = "offer_pick", length = 1.219 },
	{ role = "player_down", length = 2.304 },
	{ role = "player_hurt", length = 0.342 },
	{ role = "portal_enter", length = 1.898 },
	{ role = "portal_open", length = 1.462 },
	{ role = "pot_break", length = 1.269 },
	{ role = "refresh", length = 0.699 },
	{ role = "revive", length = 2.006 },
	{ role = "rocket_explode", length = 0.753 },
	{ role = "rocket_launch", length = 1.792 },
	{ role = "shield_break", length = 1.431 },
	{ role = "shop_buy", length = 1.045 },
	{ role = "shop_denied", length = 0.637 },
	{ role = "shrine_charge_loop", length = 5.0 },
	{ role = "shrine_complete", length = 2.797 },
	{ role = "shrine_greed", length = 2.593 },
	{ role = "slide", length = 1.294 },
	{ role = "sword_swing", length = 0.653 },
	{ role = "timer_tick", length = 0.18 },
	{ role = "ui_back", length = 0.728 },
	{ role = "ui_click", length = 0.201 },
	{ role = "ui_confirm", length = 0.728 },
	{ role = "ui_hover", length = 0.108 },
	{ role = "victory_sting", length = 5.701 },
	{ role = "xp_pickup", length = 0.137 },
}

local GAP = 0.4
local at = 0
for _, e in ipairs(TOUR) do
	local offset = at
	task.delay(offset, function()
		local s = root:FindFirstChild(e.role)
		if s and s:IsA("Sound") then
			s.TimePosition = 0
			s:Play()
			print(string.format("%5.1fs  %s", offset, e.role))
		end
	end)
	at += e.length + GAP
end

return string.format("touring %d sounds over %.1f seconds - listen", #TOUR, at)
