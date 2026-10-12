--!strict
-- Spec files are required BY the runner, so this path is relative to tests/.
local Health = require("../src/shared/Core/Health")

return {
	["damage never drops below zero"] = function()
		assert(Health.applyDamage(10, 999, 100) == 0, "expected a floor at 0")
	end,

	["negative damage cannot heal"] = function()
		assert(Health.applyDamage(50, -25, 100) == 50, "negative damage must be inert")
	end,

	["fraction guards a zero maximum"] = function()
		-- The interesting case: 0/0 is nan and nan silently poisons every UI it
		-- reaches, so this must be 0 and not merely "not an error".
		assert(Health.fraction(0, 0) == 0, "expected 0, not nan")
	end,
}
