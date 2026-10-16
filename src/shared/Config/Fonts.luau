--!strict
-- Fonts - the faces on trial for the combat feedback text: the floating damage
-- numbers, and the big popups (LEVEL UP!, banners, the stage name, powerup
-- toasts). Everything else in the UI keeps the face its layout was built with.
--
-- Only built-in Roblox families, so nothing is uploaded. `Default` stays the
-- shipped LuckiestGuy until a person has compared the others in Studio:
-- `font <name>` (DevService) sets both roles live, `font <name> numbers` or
-- `font <name> popups` one of them, `font` alone lists the faces.

local Fonts = {}

local function family(name: string): string
	return `rbxasset://fonts/families/{name}.json`
end

Fonts.Faces = {
	-- chunky round brush capitals: the face the game shipped with
	luckiest = { family = family("LuckiestGuy"), weight = Enum.FontWeight.Regular },
	-- soft and round, very open digits: the friendliest read at speed
	fredoka = { family = family("FredokaOne"), weight = Enum.FontWeight.Regular },
	-- condensed comic-book punch: the most "BONK", narrow so big numbers stay short
	bangers = { family = family("Bangers"), weight = Enum.FontWeight.Regular },
	-- Roblox's own clean sans at extra bold: the plainest, the most legible
	builder = { family = family("BuilderSans"), weight = Enum.FontWeight.ExtraBold },
	-- geometric heavy sans: arcade-scoreboard digits
	gotham = { family = family("GothamSSm"), weight = Enum.FontWeight.Heavy },
	-- rounded display face with a slight lean: between fredoka and luckiest
	denk = { family = family("DenkOne"), weight = Enum.FontWeight.Regular },
}
Fonts.Order = { "luckiest", "fredoka", "bangers", "builder", "gotham", "denk" }
Fonts.Default = "luckiest"

-- the Workspace attributes a Studio session sets to try a face (DevService)
Fonts.Attributes = { numbers = "BonkFontNumbers", popups = "BonkFontPopups" }

--- The face for a role ("numbers" or "popups") under a picked name; an unknown
--- or missing name is the default.
function Fonts.face(name: string?): Font
	local f = Fonts.Faces[name or ""] or Fonts.Faces[Fonts.Default]
	return Font.new(f.family, f.weight, Enum.FontStyle.Normal)
end

return Fonts
