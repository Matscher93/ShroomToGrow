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
var _nodes: Array[MyceliumNode]
var _production: ProductionSystem
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _biome_system: BiomeSystem

func _init(player_data: PlayerData, biomes_data: BiomesData, nodes: Array[MyceliumNode],
		production: ProductionSystem, symbiosis: UpgradeSystem,
		biome_upgrades: UpgradeSystem, biome_system: BiomeSystem) -> void:
	_player_data = player_data
	_biomes_data = biomes_data
	_nodes = nodes
	_production = production
	_symbiosis = symbiosis
	_biome_upgrades = biome_upgrades
	_biome_system = biome_system

## Biomass the current run would convert into, boosted by every track except
## symbiosis (see ProductionSystem.modify_biomass_gain).
func preview_biomass_gain() -> BigNumber:
	var base := PrestigeCalculator.calculate_biomass_gain(
		_player_data.tick_count, _player_data.nutrients)
	return _production.modify_biomass_gain(base)

func can_prestige() -> bool:
	if not _biomes_data.is_unlocked(GATE_BIOME):
		return false
	return preview_biomass_gain().gt(BigNumber.new(0.0, 0))

## Resets the current run (nutrients, water, tick_count, node purchases,
## symbiosis upgrades, biome unlocks) and converts it into biomass. Perks are
## untouched, they persist across prestiges.
func prestige() -> void:
	var gain := preview_biomass_gain()
	prestiging.emit(gain)
	_player_data.biomass = _player_data.biomass.add(gain)
	_player_data.nutrients = BigNumber.from_value(1.0)
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
