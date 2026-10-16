--!strict
-- Damage - the rules for a hit, in both directions. Pure numbers in and out;
-- every random draw is passed in so a spec can pin the boundaries.

local Damage = {}

--- Roll one hit from a player on an enemy.
--- crit is 0 (normal), 1 (crit) or 2 (megacrit).
function Damage.roll(
	base: number,
	damageMult: number,
	critChance: number,
	critDamage: number,
	megaChance: number,
	megaMult: number,
	rCrit: number,
	rMega: number
): (number, number)
	local amount = base * damageMult
	if rCrit < critChance then
		if megaChance > 0 and rMega < megaChance then
			return amount * critDamage * megaMult, 2
		end
		return amount * critDamage, 1
	end
	return amount, 0
end

--- Damage an enemy deals after the player's armor and evasion.
--- Returns the amount that lands and whether it was dodged.
function Damage.mitigate(amount: number, armor: number, evasion: number, rEvade: number): (number, boolean)
	if amount <= 0 then
		return 0, false
	end
	if rEvade < evasion then
		return 0, true
	end
	local reduced = amount * (1 - math.clamp(armor, 0, 0.9)) -- the stat's own cap is in Roster.Stats
	return math.max(reduced, 1), false
end

--- Apply landed damage to shield first, then HP.
--- Returns newHP, newShield, and whether the shield broke on this hit.
function Damage.applyToPlayer(hp: number, shield: number, amount: number): (number, number, boolean)
	if amount <= 0 then
		return hp, shield, false
	end
	if shield > 0 then
		if amount < shield then
			return hp, shield - amount, false
		end
		local spill = amount - shield
		return math.max(hp - spill, 0), 0, true
	end
	return math.max(hp - amount, 0), 0, false
end

--- Knockback distance in studs for a hit, after the enemy's resistance.
function Damage.knockback(weaponKnockback: number, statKnockback: number, resist: number): number
	local kb = weaponKnockback * statKnockback * (1 - math.clamp(resist, 0, 1))
	return math.max(kb, 0)
end

return Damage
