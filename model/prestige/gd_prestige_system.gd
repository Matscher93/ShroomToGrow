class_name PrestigeSystem
extends RefCounted
## MODEL: what a prestige is worth and what it wipes.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Perks live in their own UpgradeSystem, which this never touches:
## they are what the run is being traded for.

## Raised at the top of prestige(), before anything is reset, carrying the
## biomass the run is about to convert into.
##
## Before rather than after, because the only interesting thing about a finished
## run is what it looked like at the end - its ticks, its nutrients, its nodes -
## and prestige() is about to wipe every one of them. A listener handed the
## aftermath has nothing left to record.
signal prestiging(gain: BigNumber)

## Prestige stays hidden until this biome has been reached at least once.
const GATE_BIOME := &"permafrost"

var _player_data: PlayerData
var _biomes_data: BiomesData
var _curve: PrestigeCurveDef
var _nodes: Array[MyceliumNode]
var _production: ProductionSystem
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _biome_system: BiomeSystem

func _init(player_data: PlayerData, biomes_data: BiomesData, nodes: Array[MyceliumNode],
		production: ProductionSystem, symbiosis: UpgradeSystem,
		biome_upgrades: UpgradeSystem, biome_system: BiomeSystem,
		curve: PrestigeCurveDef) -> void:
	_player_data = player_data
	_biomes_data = biomes_data
	_curve = curve
	_nodes = nodes
	_production = production
	_symbiosis = symbiosis
	_biome_upgrades = biome_upgrades
	_biome_system = biome_system

## Biomass the current run would convert into, boosted by every track except
## symbiosis (see ProductionSystem.modify_biomass_gain).
func preview_biomass_gain() -> BigNumber:
	var base := PrestigeCalculator.calculate_biomass_gain(
		_player_data.tick_count, _player_data.run_nutrients, _curve)
	return _production.modify_biomass_gain(base)

## Prestige is offered only for a run worth more than the best one ever taken.
##
## A strict improvement rather than any gain at all: the payout is a step
## function over filled storage areas, so without this a player could sporate
## every time one area refilled and trade a whole run for less biomass than the
## last one paid. best_biomass_gain starts at zero, so the first prestige is
## still gated on nothing more than a gain above nothing.
func can_prestige() -> bool:
	if not _biomes_data.is_unlocked(GATE_BIOME):
		return false
	return preview_biomass_gain().gt(_player_data.best_biomass_gain)

## What the two storage ladders currently look like, for the prestige screen's
## bars. One call rather than a property per number, so the View never re-derives
## a ladder the model already knows how to read.
func storage_report() -> Dictionary:
	var nutrients := _player_data.run_nutrients
	var ticks := BigNumber.from_value(float(maxi(_player_data.tick_count, 0)))
	var nutrient_areas := PrestigeCalculator.nutrient_areas(nutrients, _curve)
	var tick_areas := PrestigeCalculator.tick_areas(_player_data.tick_count, _curve)
	return {
		"nutrient_areas": nutrient_areas,
		"nutrient_fill": PrestigeCalculator.fill_fraction(
			nutrients, _curve.nutrient_base(), _curve.nutrient_growth,
			_curve.nutrient_growth_exponent, nutrient_areas),
		"nutrient_amount": nutrients,
		"nutrient_next": PrestigeCalculator.area_threshold(
			_curve.nutrient_base(), _curve.nutrient_growth,
			_curve.nutrient_growth_exponent, nutrient_areas + 1),
		"tick_areas": tick_areas,
		"tick_fill": PrestigeCalculator.fill_fraction(
			ticks, _curve.tick_base(), _curve.tick_growth,
			_curve.tick_growth_exponent, tick_areas),
		"tick_amount": ticks,
		"tick_next": PrestigeCalculator.area_threshold(
			_curve.tick_base(), _curve.tick_growth,
			_curve.tick_growth_exponent, tick_areas + 1),
		"total_areas": nutrient_areas + tick_areas,
		"gain": preview_biomass_gain(),
		"best": _player_data.best_biomass_gain,
	}

## Resets the current run (nutrients, water, tick_count, node purchases,
## symbiosis upgrades, biome unlocks) and converts it into biomass. Perks are
## untouched, they persist across prestiges.
func prestige() -> void:
	var gain := preview_biomass_gain()
	prestiging.emit(gain)
	_player_data.biomass = _player_data.biomass.add(gain)
	# The bar to clear next time. Raised rather than assigned: a run taken while
	# a temporary boost was up must not lower the mark once it expires.
	if gain.gt(_player_data.best_biomass_gain):
		_player_data.best_biomass_gain = gain
	_player_data.nutrients = BigNumber.from_value(1.0)
	_player_data.run_nutrients = BigNumber.new(0.0, 0)
	_player_data.water = BigNumber.from_value(0.0)
	_player_data.tick_count = 0
	_player_data.prestige_count += 1

	for node in _nodes:
		# Tier 0 keeps one node, or the run restarts with nothing producing and
		# no way to ever earn the nutrients to buy the first one back.
		node.manual_nodes = 0 if node.node_id != 0 else 1
		node.auto_nodes = BigNumber.new(0.0, 0)

	_symbiosis.reset()
	_biome_upgrades.reset()
	_biome_system.reset()
