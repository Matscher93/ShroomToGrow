extends GdUnitTestSuite
## Unit tests for BiomeSystem (model/biomes/gd_biome_system.gd), driven by the
## real authored biome data, so the rules and the .tres content are checked
## together. test_upgrade_ids_resolve_to_real_defs is the integrity check.

const EPS := 0.000001

var _biomes: BiomeList
var _data: BiomesData
var _player: PlayerData
var _ctx: ResolveContext
var _symbiosis: UpgradeSystem
var _biome_upgrades: UpgradeSystem
var _prestige: UpgradeSystem
var _system: BiomeSystem

func before_test() -> void:
	_biomes = load("res://data/biomes/all_biomes.tres") as BiomeList
	var nodes := load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes
	_data = BiomesData.new()
	_player = PlayerData.new()
	_ctx = ResolveContext.new()
	_symbiosis = UpgradeSystem.new()
	_biome_upgrades = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	var production := ProductionSystem.new(_symbiosis, _biome_upgrades, _prestige, _ctx)
	_system = BiomeSystem.new(_biomes, _data, _player, nodes.mycelium_nodes, production,
		_symbiosis, _biome_upgrades, _prestige, _ctx)
	_system.unlock_starting_biomes()

# ─── Lookup and data integrity ───────────────────────────────────────────────

func test_lookup_by_key() -> void:
	assert_object(_system.biome_def(&"forest")).is_not_null()
	assert_object(_system.biome_def(&"nope")).is_null()

func test_every_biome_authors_ten_upgrade_ids() -> void:
	for def in _biomes.biomes:
		assert_array(_system.upgrade_ids(def.key)).has_size(10)

func test_upgrade_ids_resolve_to_real_defs() -> void:
	# Guards the folder/id naming skew: Meadow's upgrades are named Forest*,
	# Forest's are named Symbiosis*. The ids are what bind, not the folders.
	#
	# Goes through the same loader and the same path constant App registers
	# from, so this validates the set the game actually has rather than a second
	# copy of the walk that could drift from it.
	var known := {}
	for def in UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH):
		known[def.id] = true
	assert_bool(known.is_empty()) \
		.override_failure_message("Loaded no biome upgrade defs at all, so this test proves nothing.") \
		.is_false()
	for biome in _biomes.biomes:
		for id: StringName in _system.upgrade_ids(biome.key):
			assert_bool(known.has(id)) \
				.override_failure_message("Biome '%s' references unknown upgrade '%s'" % [biome.key, id]) \
				.is_true()

func test_unknown_key_yields_no_upgrade_ids() -> void:
	assert_array(_system.upgrade_ids(&"nope")).is_empty()

# ─── Unlocking ───────────────────────────────────────────────────────────────

func test_starting_biomes_are_unlocked() -> void:
	assert_bool(_data.is_unlocked(&"meadow")).is_true()
	assert_bool(_data.is_unlocked(&"forest")).is_false()

func test_unlock_requires_and_deducts_the_cost() -> void:
	# The cost is read from the def rather than written in: retuning a biome's
	# price is a data change and must not fail a test about the deduction.
	var cost := _system.biome_def(&"forest").unlock_cost
	assert_bool(cost.gt(BigNumber.new(0.0, 0))) \
		.override_failure_message("forest is free, so this test cannot tell a deduction from a no-op.") \
		.is_true()

	_player.nutrients = cost.scale(0.5)
	assert_bool(_system.can_unlock(&"forest")).is_false()

	_player.nutrients = cost.scale(3.0)
	assert_bool(_system.can_unlock(&"forest")).is_true()
	assert_bool(_system.unlock(&"forest")).is_true()
	assert_float(_player.nutrients.to_float()).is_equal_approx(cost.scale(2.0).to_float(), EPS)
	assert_bool(_data.is_unlocked(&"forest")).is_true()

func test_exactly_the_cost_is_enough() -> void:
	# The affordability check is gte, so landing exactly on the price must buy.
	var cost := _system.biome_def(&"forest").unlock_cost
	_player.nutrients = cost.copy()

	assert_bool(_system.can_unlock(&"forest")).is_true()
	assert_bool(_system.unlock(&"forest")).is_true()
	assert_float(_player.nutrients.to_float()).is_zero()

func test_cannot_unlock_twice() -> void:
	var cost := _system.biome_def(&"forest").unlock_cost
	_player.nutrients = cost.scale(3.0)
	_system.unlock(&"forest")

	assert_bool(_system.can_unlock(&"forest")).is_false()
	assert_bool(_system.unlock(&"forest")).is_false()
	assert_float(_player.nutrients.to_float()).is_equal_approx(cost.scale(2.0).to_float(), EPS)

func test_unknown_biome_cannot_be_unlocked() -> void:
	_player.nutrients = BigNumber.from_value(1e9)
	assert_bool(_system.can_unlock(&"nope")).is_false()

# ─── Points ──────────────────────────────────────────────────────────────────

func test_biome_points_bonus_flows_through_the_production_stack() -> void:
	# permafrost scores off PRESTIGE_COUNT, which is 0 on a fresh PlayerData.
	assert_int(_system.available_points(&"permafrost")).is_zero()
	# meadow scores off TOTAL_NODES, so it already has points from the authored
	# node data, so capture that rather than assuming a value.
	var meadow_before := _system.available_points(&"meadow")

	var e := UpgradeEffectDef.new()
	e.stat = &"biome_points"
	e.per_level = 3.0
	e.op = UpgradeEffectDef.Op.ADD
	e.scope = UpgradeEffectDef.Scope.NODE
	e.target = &"permafrost"
	var d := UpgradeDef.new()
	d.id = &"PermaPoints"
	d.effects = [e]
	_prestige.register(d)
	_prestige.from_save({"PermaPoints": 1})

	assert_int(_system.available_points(&"permafrost")).is_equal(3)
	# The bonus targets permafrost only, so meadow must be untouched by it.
	assert_int(_system.available_points(&"meadow")).is_equal(meadow_before)

func test_spent_points_reduce_the_available_budget() -> void:
	_data.spend_points(&"permafrost", 2)
	assert_int(_system.available_points(&"permafrost")).is_zero()   # never negative

# ─── Biome size ──────────────────────────────────────────────────────────────

func test_buying_size_deducts_and_feeds_the_resolve_context() -> void:
	_player.nutrients = BigNumber.from_value(1e9)
	var before := _system.size(&"meadow")

	assert_bool(_system.buy_size(&"meadow")).is_true()
	assert_int(_system.size(&"meadow")).is_equal(before + 1)
	# biome_size() is the scaling multiplier, one higher than the purchased size.
	assert_float(_ctx.biome_size(&"meadow")).is_equal_approx(float(before + 2), EPS)
	assert_bool(_player.nutrients.lt(BigNumber.from_value(1e9))).is_true()

func test_cannot_buy_size_without_funds() -> void:
	_player.nutrients = BigNumber.from_value(0.0)
	assert_bool(_system.can_buy_size(&"meadow")).is_false()
	assert_bool(_system.buy_size(&"meadow")).is_false()

func test_unknown_biome_has_no_size_cost() -> void:
	assert_float(_system.size_cost(&"nope").to_float()).is_zero()
	assert_bool(_system.can_buy_size(&"nope")).is_false()

# ─── Prestige reset ──────────────────────────────────────────────────────────

func test_reset_relocks_the_run_but_keeps_ever_unlocked() -> void:
	_player.nutrients = BigNumber.from_value(1e9)   # enough for anything on offer
	_system.unlock(&"forest")
	_system.buy_size(&"meadow")

	_system.reset()

	assert_bool(_data.is_unlocked(&"forest")).is_false()
	assert_bool(_data.is_ever_unlocked(&"forest")).is_true()   # tab stays reachable
	assert_bool(_data.is_unlocked(&"meadow")).is_true()        # always_unlocked
	assert_bool(_ctx.biome_sizes.is_empty()).is_true()

func test_biomes_hub_screen_is_always_reachable() -> void:
	assert_bool(_system.is_screen_unlocked(ScreenTypes.Types.BIOMES)).is_true()

func test_screen_gating_follows_ever_unlocked() -> void:
	# permafrost gates the PRESTIGE tab. (Not forest: its .tres omits
	# screen_type, so it defaults to 0 = BIOMES, which is always reachable.)
	var permafrost := _system.biome_def(&"permafrost")
	assert_bool(_system.is_screen_unlocked(permafrost.screen_type)).is_false()

	_player.nutrients = permafrost.unlock_cost.scale(2.0)
	assert_bool(_system.unlock(&"permafrost")).is_true()
	assert_bool(_system.is_screen_unlocked(permafrost.screen_type)).is_true()

	_system.reset()   # a prestige must not take the tab away again
	assert_bool(_data.is_unlocked(&"permafrost")).is_false()
	assert_bool(_system.is_screen_unlocked(permafrost.screen_type)).is_true()
