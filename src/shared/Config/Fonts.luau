--!strict
-- Fonts - the faces on trial, in three roles: "numbers" (the floating damage
-- numbers), "popups" (LEVEL UP!, banners, the stage name, powerup toasts) and
-- "ui" (the rest of the game's own interface: menus, HUD, cards, panels, the
-- results and the world's labels; client/UiFonts).
--
-- Only built-in Roblox families, so nothing is uploaded. Numbers and popups
-- default to Fredoka, the face the playtest preferred. The ui role defaults to
-- the faces the screens were built with (Luckiest headings, Fredoka body) until
-- a person approves a whole-interface face in Studio:
--   `font fredoka all`      every role, the whole game in one face
--   `font fredoka ui`       the interface only; numbers and popups keep theirs
--   `font bangers numbers`  / `font denk popups`  one role
--   `font bangers`          numbers and popups, as before
--   `font`                  lists the faces and what each role wears now

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
-- the numbers' and popups' face when nobody has picked one
Fonts.Default = "fredoka"
-- the face the screens set their headings, values and prices in: a "ui" pick
-- replaces it, and leaves the body text's Fredoka alone
Fonts.Display = "luckiest"

-- the Workspace attributes a Studio session sets to try a face (DevService)
Fonts.Attributes = { numbers = "BonkFontNumbers", popups = "BonkFontPopups", ui = "BonkFontUi" }

--- The face for the numbers or popups role under a picked name; an unknown or
--- missing name is the default.
function Fonts.face(name: string?): Font
	local f = Fonts.Faces[name or ""] or Fonts.Faces[Fonts.Default]
	return Font.new(f.family, f.weight, Enum.FontStyle.Normal)
end

return Fonts
