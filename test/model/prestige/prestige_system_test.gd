extends GdUnitTestSuite
## Unit tests for PrestigeSystem (model/prestige/gd_prestige_system.gd).
##
## A prestige is the one irreversible action in the game: it trades the whole
## run for biomass and there is no undo, so what it wipes and what it spares are
## both asserted explicitly.

const EPS := 0.000001

var _player: PlayerData
var _biomes_data: BiomesData
var _nodes: Array[MyceliumNode]
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _perks: UpgradeSystem
var _ctx: ResolveContext
var _production: ProductionSystem
var _biome_system: BiomeSystem
var _system: PrestigeSystem

func before_test() -> void:
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_nodes = _chain(3)
	_symbiosis = UpgradeSystem.new()
	_biome_upgrades = UpgradeSystem.new()
	_perks = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(_symbiosis, _biome_upgrades, _perks, _ctx)

	var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
	_biome_system = BiomeSystem.new(biomes, _biomes_data, _player, _nodes, _production,
		_symbiosis, _biome_upgrades, _perks, _ctx)
	_biome_system.unlock_free_biomes()

	_system = PrestigeSystem.new(_player, _biomes_data, _nodes, _production,
		_symbiosis, _biome_upgrades, _biome_system)

func _chain(tiers: int) -> Array[MyceliumNode]:
	var nodes: Array[MyceliumNode] = []
	for i in range(tiers):
		var node := MyceliumNode.new()
		node.node_id = i
		node.manual_nodes = 4
		node.auto_nodes = BigNumber.from_value(1000.0)
		nodes.append(node)
	return nodes

func _register(system: UpgradeSystem, id: StringName, level: int,
		effects: Array[UpgradeEffectDef] = []) -> void:
	var d := UpgradeDef.new()
	d.id = id
	d.effects = effects
	system.register(d)
	system.set_level_for_analysis(id, level)

func _biomass_effect(per_level: float) -> Array[UpgradeEffectDef]:
	var e := UpgradeEffectDef.new()
	e.stat = &"biomass_gain"
	e.per_level = per_level
	e.op = UpgradeEffectDef.Op.INCREASED
	e.scope = UpgradeEffectDef.Scope.GLOBAL
	return [e]

## Puts the run in a state a prestige is actually offered for.
func _make_prestige_available() -> void:
	_biomes_data.unlock(PrestigeSystem.GATE_BIOME)
	_player.nutrients = BigNumber.from_value(1e6)

# ─── Gating ──────────────────────────────────────────────────────────────────

func test_prestige_is_gated_on_the_biome_however_rich_the_run_is() -> void:
	_player.nutrients = BigNumber.from_value(1e30)
	assert_bool(_biomes_data.is_unlocked(PrestigeSystem.GATE_BIOME)).is_false()
	assert_bool(_system.can_prestige()).is_false()

func test_prestige_is_refused_when_the_run_is_worth_nothing() -> void:
	_biomes_data.unlock(PrestigeSystem.GATE_BIOME)
	_player.nutrients = BigNumber.from_value(1.0)
	assert_float(_system.preview_biomass_gain().to_float()).is_zero()
	assert_bool(_system.can_prestige()).is_false()

func test_prestige_is_offered_once_gated_and_worth_something() -> void:
	_make_prestige_available()
	assert_bool(_system.can_prestige()).is_true()

func test_the_gate_biome_is_one_the_authored_data_defines() -> void:
	# The key is a plain StringName, so a biome rename would silently make the
	# prestige tab unreachable rather than fail at load.
	assert_object(_biome_system.biome_def(PrestigeSystem.GATE_BIOME)).is_not_null()

# ─── Payout ──────────────────────────────────────────────────────────────────

func test_the_previewed_gain_is_what_biomass_actually_receives() -> void:
	_make_prestige_available()
	var previewed := _system.preview_biomass_gain()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(previewed.to_float(), EPS)

func test_the_gain_is_added_to_existing_biomass_not_replacing_it() -> void:
	_make_prestige_available()
	_player.biomass = BigNumber.from_value(100.0)
	var previewed := _system.preview_biomass_gain()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(100.0 + previewed.to_float(), EPS)

func test_biome_upgrades_and_perks_boost_the_gain() -> void:
	_make_prestige_available()
	var base := _system.preview_biomass_gain().to_float()

	_register(_biome_upgrades, &"BioBonus", 1, _biomass_effect(1.0))
	_register(_perks, &"PerkBonus", 1, _biomass_effect(1.0))

	# 1 * (1 + 1) biome, then 1 * (1 + 1) perks: the two tracks compound.
	assert_float(_system.preview_biomass_gain().to_float()).is_equal_approx(base * 4.0, EPS)

func test_symbiosis_never_boosts_the_gain_it_is_paying_for() -> void:
	_make_prestige_available()
	var base := _system.preview_biomass_gain().to_float()

	_register(_symbiosis, &"SymBonus", 1, _biomass_effect(9.0))

	assert_float(_system.preview_biomass_gain().to_float()).is_equal_approx(base, EPS)

# ─── What the reset wipes ────────────────────────────────────────────────────

func test_currencies_and_counters_are_reset() -> void:
	_make_prestige_available()
	_player.water = BigNumber.from_value(500.0)
	_player.tick_count = 9439

	_system.prestige()

	assert_float(_player.nutrients.to_float()).is_equal_approx(1.0, EPS)
	assert_float(_player.water.to_float()).is_zero()
	assert_int(_player.tick_count).is_zero()
	assert_int(_player.prestige_count).is_equal(1)

func test_tier_zero_keeps_one_node_so_the_run_can_restart() -> void:
	# With every tier at zero nothing produces, and nutrients reset to 1 is not
	# enough to buy a node back: the save would be permanently stuck.
	_make_prestige_available()

	_system.prestige()

	assert_int(_nodes[0].manual_nodes).is_equal(1)
	for node in _nodes:
		assert_float(node.auto_nodes.to_float()) \
			.override_failure_message("Tier %d kept auto nodes." % node.node_id).is_zero()

func test_every_tier_above_zero_is_wiped() -> void:
	_make_prestige_available()

	_system.prestige()

	for node in _nodes:
		if node.node_id == 0:
			continue
		assert_int(node.manual_nodes) \
			.override_failure_message("Tier %d kept manual nodes." % node.node_id).is_zero()

func test_symbiosis_and_biome_upgrade_levels_are_wiped() -> void:
	_make_prestige_available()
	_register(_symbiosis, &"Sym", 5)
	_register(_biome_upgrades, &"Bio", 3)

	_system.prestige()

	assert_int(_symbiosis.level(&"Sym")).is_zero()
	assert_int(_biome_upgrades.level(&"Bio")).is_zero()

func test_perk_levels_survive_the_reset() -> void:
	# Perks are what the run is being traded for. Wiping them makes the whole
	# prestige loop a net loss.
	_make_prestige_available()
	_register(_perks, &"Perk", 4)

	_system.prestige()

	assert_int(_perks.level(&"Perk")).is_equal(4)

func test_well_project_levels_survive_the_reset() -> void:
	# Water is a run currency the reset wipes, but what it was spent on is
	# permanent - the same split crystals and boosts have. PrestigeSystem is not
	# even handed the project track, and this is what says that is deliberate.
	_make_prestige_available()
	var projects := UpgradeSystem.new()
	_register(projects, &"project_sluice_b0", 6)
	_player.well_project_levels = 6

	_system.prestige()

	assert_float(_player.water.to_float()).is_zero()
	assert_int(projects.level(&"project_sluice_b0")).is_equal(6)
	assert_int(_player.well_project_levels).is_equal(6)

func test_biomes_are_relocked_but_stay_reachable() -> void:
	_make_prestige_available()

	_system.prestige()

	assert_bool(_biomes_data.is_unlocked(PrestigeSystem.GATE_BIOME)).is_false()
	assert_bool(_biomes_data.is_ever_unlocked(PrestigeSystem.GATE_BIOME)).is_true()
	assert_bool(_biomes_data.is_unlocked(&"meadow")).is_true()   # always_unlocked

func test_a_second_prestige_starts_from_the_reset_run() -> void:
	# tick_count and nutrients both feed the gain, so a reset that missed either
	# would pay the same run out twice.
	_make_prestige_available()
	_system.prestige()
	var after_first := _player.biomass.to_float()

	assert_float(_system.preview_biomass_gain().to_float()).is_zero()
	assert_bool(_system.can_prestige()).is_false()

	_system.prestige()

	assert_float(_player.biomass.to_float()).is_equal_approx(after_first, EPS)
	assert_int(_player.prestige_count).is_equal(2)
