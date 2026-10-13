--!strict
-- Icons - every icon key the interface uses, mapped to its uploaded asset id.
--
-- The ids are empty until the icon set is uploaded; an empty id hides the image
-- instead of drawing a blank square. Keys for content are built from the roster
-- ids: weapons "Icon" .. id, tomes "IconTome" .. id, items "IconItem" .. id,
-- hero portraits "Portrait" .. id, map thumbnails "Thumb" .. id.

local Icons = {}

Icons.Map = {
	IconClock = "",
	IconSilver = "",
	IconGold = "",
	IconSkull = "",
	IconChest = "",
	IconPadlock = "",
	IconCheck = "",
	IconCrown = "",
	IconRun = "",
	IconArrowPlayer = "",
	IconMapChest = "",
	IconMapShrine = "",
	IconMapBoss = "",
	IconMapVendor = "",
	IconMapTeammate = "",
	IconShield = "",
	IconPassive = "",
	IconExclaim = "",
	IconSword = "",
	IconFireStaff = "",
	IconFrostRing = "",
	IconLightningStaff = "",
	IconBone = "",
	IconBoomernana = "",
	IconAxe = "",
	IconPartyRocket = "",
	IconTomeDamage = "",
	IconTomeAgility = "",
	IconTomeCooldown = "",
	IconTomePrecision = "",
	IconTomeSize = "",
	IconTomeShield = "",
	IconTomeHealth = "",
	IconTomeRegen = "",
	IconTomeXP = "",
	IconTomeLuck = "",
	IconTomeAttraction = "",
	IconTomeQuantity = "",
	IconItemTickingBracelet = "",
	IconItemLuckyClover = "",
	IconItemZoomSocks = "",
	IconItemProteinGoop = "",
	IconItemSusJuice = "",
	IconItemDodgyBattery = "",
	IconItemBandageBox = "",
	IconItemStinkyCheese = "",
	IconItemFrostShard = "",
	IconItemGiantSlayerPin = "",
	IconItemShrineWrench = "",
	IconItemGildedSneakers = "",
	IconItemEchoGem = "",
	IconItemPocketCampfire = "",
	IconItemFeatherweight = "",
	IconItemStaticMitts = "",
	IconItemSkeletonKey = "",
	IconItemVampireMitts = "",
	IconItemNightlight = "",
	IconItemCrackedGoggles = "",
	IconItemPanicMirror = "",
	IconItemVolatileMeatball = "",
	IconItemBigIceCube = "",
	IconItemColossalFork = "",
	IconItemSecondWindClock = "",
	PortraitKnight = "",
	PortraitFox = "",
	PortraitFrostling = "",
	ThumbMossyWoods = "",
	ThumbDesert = "",
	ThumbGraveyard = "",
} :: { [string]: string }

--- The asset id string for an icon key, or "" when the key is unknown or not uploaded yet.
function Icons.get(key: string?): string
	if not key then
		return ""
	end
	return Icons.Map[key] or ""
end

return Icons
