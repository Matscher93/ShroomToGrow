class_name CurrencyHomes
extends RefCounted
## MODEL: which biome owns the screen a currency is shown and spent on, and
## therefore whether the player has a home for it yet.
##
## Derived rather than authored: a screen already lists its currencies and a
## biome already names its screen, so nothing has to repeat the mapping and a new
## currency cannot forget it. Currencies whose screen has no owning biome
## (nutrients) are absent from the map, which reads as "always reachable".
##
## Split out of EventSystem, which asked this question first and now asks it
## through here. The daily-track reward asks the same one for the same reason: a
## payout in a resource the player has never seen is not a weak reward, it is a
## reward in a currency they have no screen for.

## currency ordinal -> biome key.
var _biome_for_currency: Dictionary = {}

## Both registries are optional: without them the map stays empty and every
## currency reads as reachable, which is what a test building a system from two
## hand-made defs wants.
func _init(screens: Screens = null, biomes: BiomeList = null) -> void:
	if screens == null or biomes == null:
		return
	var biome_for_screen: Dictionary = {}
	for biome_def in biomes.biomes:
		if biome_def == null:
			continue
		biome_for_screen[biome_def.screen_type] = biome_def.key
	for screen_type: ScreenTypes.Types in screens.screens:
		if not biome_for_screen.has(screen_type):
			continue
		var screen_def: ScreenDefinition = screens.screens[screen_type]
		if screen_def == null:
			continue
		for currency in screen_def.currencies:
			if currency == null:
				continue
			_biome_for_currency[currency.currency_type] = biome_for_screen[screen_type]

## Whether the player has ever reached the screen this currency lives on.
##
## Permanent rather than per-run: it answers whether they have seen the resource
## at all, not whether this run has bought the biome back. A prestige does not
## un-teach what crystals are.
func is_reachable(currency: CurrencyTypes.Types, biomes_data: BiomesData) -> bool:
	if not _biome_for_currency.has(currency):
		return true
	if biomes_data == null:
		return true
	return biomes_data.is_ever_unlocked(_biome_for_currency[currency])

## The furthest-in currency the player has a home for, by the order
## CurrencyTypes declares - which is the order the game opens them in.
##
## Fertilizer is excluded: it is a currency everywhere it shows on screen, but
## nothing produces it and FertilizerSystem, not a balance field, is what grants
## it. A reward paid in it would take a different path entirely.
func deepest_reachable(biomes_data: BiomesData) -> CurrencyTypes.Types:
	var deepest := CurrencyTypes.Types.NUTRIENTS
	for currency: CurrencyTypes.Types in [CurrencyTypes.Types.NUTRIENTS,
			CurrencyTypes.Types.WATER, CurrencyTypes.Types.BIOMASS,
			CurrencyTypes.Types.CRYSTALS, CurrencyTypes.Types.RELICS,
			CurrencyTypes.Types.ICHOR, CurrencyTypes.Types.GLYPHS]:
		if is_reachable(currency, biomes_data):
			deepest = currency
	return deepest
