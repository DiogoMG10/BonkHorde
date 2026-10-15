--!strict
-- Icons - every icon key the interface uses, mapped to its uploaded asset id.
--
-- The ids are empty until the icon set is uploaded; an empty id hides the image
-- instead of drawing a blank square. Keys for content are built from the roster
-- ids: weapons "Icon" .. id, tomes "IconTome" .. id, items "IconItem" .. id,
-- hero portraits "Portrait" .. id, map thumbnails "Thumb" .. id.

local Icons = {}

Icons.Map = {
	IconClock = "rbxassetid://108715038463926",
	IconSilver = "rbxassetid://120698284478658",
	IconGold = "rbxassetid://85947511924781",
	IconSkull = "rbxassetid://100036258340539",
	IconChest = "rbxassetid://98325407272190",
	IconPadlock = "rbxassetid://74301908224393",
	IconCheck = "rbxassetid://106107883413409",
	IconCrown = "rbxassetid://92704842005662",
	IconRun = "rbxassetid://72829149563290",
	IconArrowPlayer = "rbxassetid://132600941026578",
	IconMapChest = "rbxassetid://98600303333966",
	IconMapShrine = "rbxassetid://107982139961878",
	IconMapBoss = "rbxassetid://80196924824348",
	IconMapVendor = "rbxassetid://107717818608321",
	IconMapTeammate = "rbxassetid://117236328075408",
	IconShield = "rbxassetid://75158389310578",
	IconPassive = "rbxassetid://117003587450262",
	IconExclaim = "rbxassetid://128297169166851",
	IconSword = "rbxassetid://80866047531072",
	IconFireStaff = "rbxassetid://98975365319352",
	IconFrostRing = "rbxassetid://118796211156429",
	IconLightningStaff = "rbxassetid://70816421098869",
	IconBone = "rbxassetid://100637793941548",
	IconBoomernana = "rbxassetid://128514697792788",
	IconAxe = "rbxassetid://72623116608437",
	IconPartyRocket = "rbxassetid://134214492991319",
	IconTomeDamage = "rbxassetid://91289892362739",
	IconTomeAgility = "rbxassetid://131046204359082",
	IconTomeCooldown = "rbxassetid://119154606530759",
	IconTomePrecision = "rbxassetid://116238749409494",
	IconTomeSize = "rbxassetid://75962125575676",
	IconTomeShield = "rbxassetid://74072025503512",
	IconTomeHealth = "rbxassetid://140613343428111",
	IconTomeRegen = "rbxassetid://108181250222869",
	IconTomeXP = "rbxassetid://106714271225117",
	IconTomeLuck = "rbxassetid://86456125624767",
	IconTomeAttraction = "rbxassetid://113381583268610",
	IconTomeQuantity = "rbxassetid://126324019018570",
	IconItemTickingBracelet = "rbxassetid://80318624122922",
	IconItemLuckyClover = "rbxassetid://74706055471393",
	IconItemZoomSocks = "rbxassetid://108984003731669",
	IconItemProteinGoop = "rbxassetid://129257783217746",
	IconItemSusJuice = "rbxassetid://124912358963334",
	IconItemDodgyBattery = "rbxassetid://98745237593948",
	IconItemBandageBox = "rbxassetid://74286340094299",
	IconItemStinkyCheese = "rbxassetid://100529787456080",
	IconItemFrostShard = "rbxassetid://73132026930411",
	IconItemGiantSlayerPin = "rbxassetid://77855590110593",
	IconItemShrineWrench = "rbxassetid://129461812835216",
	IconItemGildedSneakers = "rbxassetid://87438965262902",
	IconItemEchoGem = "rbxassetid://82102896074908",
	IconItemPocketCampfire = "rbxassetid://92778101460219",
	IconItemFeatherweight = "rbxassetid://122943538963359",
	IconItemStaticMitts = "rbxassetid://87230909922029",
	IconItemSkeletonKey = "rbxassetid://98628757475883",
	IconItemAutoTrigger = "rbxassetid://119154606530759", -- placeholder: the Cooldown tome icon until its own is drawn
	IconItemVampireMitts = "rbxassetid://105704288960657",
	IconItemNightlight = "rbxassetid://86811854199526",
	IconItemCrackedGoggles = "rbxassetid://107953914413106",
	IconItemPanicMirror = "rbxassetid://102208364368172",
	IconItemVolatileMeatball = "rbxassetid://136473756322240",
	IconItemBigIceCube = "rbxassetid://119405681190292",
	IconItemColossalFork = "rbxassetid://121955789766598",
	IconItemSecondWindClock = "rbxassetid://136052125525274",
	PortraitKnight = "rbxassetid://95074487909614",
	PortraitFox = "rbxassetid://77082805777113",
	PortraitFrostling = "rbxassetid://92293233429599",
	ThumbMossyWoods = "rbxassetid://78605962719876",
	ThumbDesert = "rbxassetid://137133643576509",
	ThumbGraveyard = "rbxassetid://102792774709385",
} :: { [string]: string }

--- The asset id string for an icon key, or "" when the key is unknown or not uploaded yet.
function Icons.get(key: string?): string
	if not key then
		return ""
	end
	return Icons.Map[key] or ""
end

return Icons
