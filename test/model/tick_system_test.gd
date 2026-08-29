extends GdUnitTestSuite
## Unit tests for TickSystem (model/gd_tick_system.gd): the production cascade
## every other number in the game is derived from.
##
## Built with its dependencies injected and no App autoload, which is the point
## of the extraction.

const EPS := 0.000001

var _symbiosis: UpgradeSystem
var _biome: UpgradeSystem
var _prestige: UpgradeSystem
var _ctx: ResolveContext
var _production: ProductionSystem
var _player: PlayerData

func before_test() -> void:
	_symbiosis = UpgradeSystem.new()
	_biome = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(_symbiosis, _biome, _prestige, _ctx)
	_player = PlayerData.new()
	_player.nutrients = BigNumber.from_value(0.0)

func _node(node_id: int, manual: int = 0) -> MyceliumNode:
	var node := MyceliumNode.new()
	node.node_id = node_id
	node.manual_nodes = manual
	node.auto_nodes = BigNumber.from_value(0.0)
	return node

func _chain(manual_per_tier: Array[int]) -> Array[MyceliumNode]:
	var nodes: Array[MyceliumNode] = []
	for i in range(manual_per_tier.size()):
		nodes.append(_node(i, manual_per_tier[i]))
	return nodes

func _system(nodes: Array[MyceliumNode]) -> TickSystem:
	return TickSystem.new(nodes, _player, _production)

func _register(system: UpgradeSystem, id: StringName, stat: StringName,
		per_level: float, target: StringName) -> void:
	var e := UpgradeEffectDef.new()
	e.stat = stat
	e.per_level = per_level
	e.op = UpgradeEffectDef.Op.INCREASED
	e.scope = UpgradeEffectDef.Scope.NODE
	e.target = target
	var d := UpgradeDef.new()
	d.id = id
	d.effects = [e]
	system.register(d)
	system.set_level_for_analysis(id, 1)

# ─── Tick bookkeeping ────────────────────────────────────────────────────────

func test_every_tick_advances_the_counter() -> void:
	var system := _system(_chain([1] as Array[int]))
	system.handle_tick()
	system.handle_tick()
	assert_int(_player.tick_count).is_equal(2)

func test_a_single_tier_pays_straight_into_nutrients() -> void:
	var nodes := _chain([3] as Array[int])
	_system(nodes).handle_tick()
	assert_float(_player.nutrients.to_float()).is_equal_approx(3.0, EPS)

func test_a_tier_produces_from_auto_plus_manual_nodes() -> void:
	var nodes := _chain([2] as Array[int])
	nodes[0].auto_nodes = BigNumber.from_value(5.0)
	_system(nodes).handle_tick()
	assert_float(_player.nutrients.to_float()).is_equal_approx(7.0, EPS)

func test_an_idle_chain_pays_nothing() -> void:
	var nodes := _chain([0, 0, 0] as Array[int])
	_system(nodes).handle_tick()
	assert_float(_player.nutrients.to_float()).is_zero()
	assert_float(nodes[0].auto_nodes.to_float()).is_zero()

# ─── Cascade order ───────────────────────────────────────────────────────────

func test_a_top_tier_gain_reaches_nutrients_in_the_same_tick() -> void:
	# The invariant the descending loop exists for. Iterating upwards instead
	# would park each tier's output for the next tick, and this first tick would
	# pay 0 rather than 1.
	var nodes := _chain([0, 0, 1] as Array[int])

	_system(nodes).handle_tick()

	assert_float(nodes[2].auto_nodes.to_float()).is_zero()   # tier 2 only produces
	assert_float(nodes[1].auto_nodes.to_float()).is_equal_approx(1.0, EPS)
	assert_float(nodes[0].auto_nodes.to_float()).is_equal_approx(1.0, EPS)
	assert_float(_player.nutrients.to_float()).is_equal_approx(1.0, EPS)

func test_the_chain_compounds_across_ticks() -> void:
	# Tick 2 pays 3, not another 1: tier 1 now holds what tier 2 made last tick,
	# and tier 0 holds both. A flat payout here means the cascade went linear.
	var nodes := _chain([0, 0, 1] as Array[int])
	var system := _system(nodes)

	system.handle_tick()
	system.handle_tick()

	assert_float(nodes[1].auto_nodes.to_float()).is_equal_approx(2.0, EPS)
	assert_float(nodes[0].auto_nodes.to_float()).is_equal_approx(3.0, EPS)
	assert_float(_player.nutrients.to_float()).is_equal_approx(4.0, EPS)   # 1 + 3

func test_a_tier_stores_its_output_raw_and_the_tier_below_scales_it() -> void:
	# Tier 1's 4 lands in tier 0 unmultiplied, then tier 0 applies its own x2.
	# Applying the producing tier's bonus on the way down instead would put 8 in
	# tier 0 and pay 16.
	var nodes := _chain([0, 4] as Array[int])
	var bonuses: Array[BigNumber] = [BigNumber.from_value(2.0), BigNumber.from_value(1.0)]

	_system(nodes).handle_tick(bonuses)

	assert_float(nodes[0].auto_nodes.to_float()).is_equal_approx(4.0, EPS)
	assert_float(_player.nutrients.to_float()).is_equal_approx(8.0, EPS)

# ─── Bonuses ─────────────────────────────────────────────────────────────────

func test_bonuses_are_indexed_by_array_position() -> void:
	var nodes := _chain([1, 1] as Array[int])
	var bonuses: Array[BigNumber] = [BigNumber.from_value(10.0), BigNumber.from_value(1.0)]

	_system(nodes).handle_tick(bonuses)

	# tier 1: 1 * 1 = 1 into tier 0, tier 0: (0 + 1 + 1) * 10 = 20
	assert_float(_player.nutrients.to_float()).is_equal_approx(20.0, EPS)

func test_node_production_bonuses_are_keyed_by_node_id_not_index() -> void:
	# node_id and array position are only incidentally equal. An upgrade targets
	# the id, so a system indexing by position would boost the wrong tier.
	var nodes: Array[MyceliumNode] = [_node(0), _node(5)]
	_register(_symbiosis, &"Tier5", &"node_production", 1.0, &"5")

	var bonuses := _system(nodes).node_production_bonuses()

	assert_int(bonuses.size()).is_equal(2)
	assert_float(bonuses[0].to_float()).is_equal_approx(1.0, EPS)
	assert_float(bonuses[1].to_float()).is_equal_approx(2.0, EPS)

## The trap a group bonus on &"node_production" sets, as a number rather than a
## comment: the cascade applies the bonus once per tagged link, so a x2 across
## three tiers is x2^3 at the nutrient output, not x2. Anyone changing the
## cascade or the bucket combination sees this move.
func test_a_tag_bonus_multiplies_every_tagged_tier_in_the_cascade() -> void:
	var nodes: Array[MyceliumNode] = [_node(0), _node(1), _node(2, 1)]
	for node in nodes:
		node.tags = [&"canopy"] as Array[StringName]
	_production = ProductionSystem.new(_symbiosis, _biome, _prestige, _ctx,
		null, null, null, null, null, nodes)
	var e := UpgradeEffectDef.new()
	e.stat = &"node_production"
	e.per_level = 1.0
	e.op = UpgradeEffectDef.Op.INCREASED
	e.scope = UpgradeEffectDef.Scope.TAG
	e.target = &"canopy"
	var d := UpgradeDef.new()
	d.id = &"Canopy"
	d.effects = [e]
	_symbiosis.register(d)
	_symbiosis.set_level_for_analysis(&"Canopy", 1)

	_system(nodes).handle_tick()

	# tier 2: 1 * 2 = 2 into tier 1, tier 1: 2 * 2 = 4 into tier 0,
	# tier 0: 4 * 2 = 8 into nutrients.
	assert_float(_player.nutrients.to_float()).is_equal_approx(8.0, EPS)

func test_an_empty_bonus_array_is_computed_fresh() -> void:
	var nodes := _chain([1] as Array[int])
	_register(_symbiosis, &"Tier0", &"node_production", 1.0, &"0")
	_system(nodes).handle_tick()
	assert_float(_player.nutrients.to_float()).is_equal_approx(2.0, EPS)

func test_passed_in_bonuses_are_used_verbatim() -> void:
	# The offline catch-up contract: bonuses are hoisted out of the loop once and
	# must not be silently recomputed, or the hoist buys nothing.
	var nodes := _chain([1] as Array[int])
	var system := _system(nodes)
	var hoisted := system.node_production_bonuses()

	_register(_symbiosis, &"Tier0", &"node_production", 99.0, &"0")
	system.handle_tick(hoisted)

	assert_float(_player.nutrients.to_float()).is_equal_approx(1.0, EPS)

# ─── Striding ────────────────────────────────────────────────────────────────

## Runs the same chain twice, once tick by tick and once in one jump, and
## reports both end states so a test can compare them.
func _strided_against_looped(manual: Array[int], bonuses: Array[BigNumber],
		count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for strided in [false, true]:
		_player = PlayerData.new()
		_player.nutrients = BigNumber.from_value(0.0)
		_player.lifetime_nutrients = BigNumber.from_value(0.0)
		var nodes := _chain(manual)
		var system := _system(nodes)
		if strided:
			system.advance(count, bonuses)
		else:
			for _i in count:
				system.handle_tick(bonuses)
		var tiers: Array[float] = []
		for node in nodes:
			tiers.append(node.auto_nodes.to_float())
		out.append({
			"tiers": tiers,
			"nutrients": _player.nutrients.to_float(),
			"lifetime": _player.lifetime_nutrients.to_float(),
			"ticks": _player.tick_count,
		})
	return out

func _assert_stride_matches(manual: Array[int], bonuses: Array[BigNumber], count: int) -> void:
	var runs := _strided_against_looped(manual, bonuses, count)
	var looped: Dictionary = runs[0]
	var strided: Dictionary = runs[1]
	assert_int(strided["ticks"]).is_equal(looped["ticks"])
	assert_float(strided["nutrients"]).is_equal_approx(looped["nutrients"],
		maxf(EPS, absf(looped["nutrients"]) * 1e-9))
	assert_float(strided["lifetime"]).is_equal_approx(looped["lifetime"],
		maxf(EPS, absf(looped["lifetime"]) * 1e-9))
	for i in looped["tiers"].size():
		assert_float(strided["tiers"][i]).is_equal_approx(looped["tiers"][i],
			maxf(EPS, absf(looped["tiers"][i]) * 1e-9))

func test_one_strided_tick_is_one_tick() -> void:
	_assert_stride_matches([2, 3, 1] as Array[int], [] as Array[BigNumber], 1)

func test_a_stride_lands_where_the_loop_lands() -> void:
	# The whole premise: the closed form is exact, not an approximation, for a
	# span where nothing is bought.
	_assert_stride_matches([2, 3, 1] as Array[int], [] as Array[BigNumber], 250)

func test_a_stride_lands_where_the_loop_lands_with_bonuses() -> void:
	var bonuses: Array[BigNumber] = [BigNumber.from_value(2.5),
		BigNumber.from_value(1.5), BigNumber.from_value(3.0)]
	_assert_stride_matches([2, 0, 1] as Array[int], bonuses, 120)

func test_a_long_chain_strides_exactly() -> void:
	# Eight tiers is deep enough that the binomial series has to run its full
	# length before the differences vanish.
	_assert_stride_matches([1, 1, 1, 1, 1, 1, 1, 1] as Array[int],
		[] as Array[BigNumber], 60)

func test_an_idle_chain_strides_to_nothing() -> void:
	_assert_stride_matches([0, 0, 0] as Array[int], [] as Array[BigNumber], 1000)

func test_a_stride_of_zero_ticks_changes_nothing() -> void:
	var nodes := _chain([5] as Array[int])
	_system(nodes).advance(0)
	assert_int(_player.tick_count).is_zero()
	assert_float(_player.nutrients.to_float()).is_zero()

# ─── The well rides the same tick ────────────────────────────────────────────

## Water is driven from here rather than from App so that every caller advancing
## ticks moves it: the live timer, the offline catch-up (which walks
## handle_tick() one tick at a time) and the simulator (which strides through
## advance_by()). A well wired at the App level would have produced nothing
## offline and nothing in the simulator.
func _well_system(nodes: Array[MyceliumNode], biomes_data: BiomesData) -> TickSystem:
	return TickSystem.new(nodes, _player, _production,
		WaterSystem.new(_player, biomes_data, _production))

func test_walking_ticks_pumps_water() -> void:
	var biomes_data := BiomesData.new()
	biomes_data.unlock(WaterSystem.LAKE_KEY)
	var system := _well_system(_chain([1] as Array[int]), biomes_data)
	for _i in int(WaterSystem.BASE_INTERVAL) * 3:
		system.handle_tick()
	assert_float(_player.water.to_float()) \
		.is_equal_approx(WaterSystem.BASE_YIELD * 3.0, EPS)

func test_striding_ticks_pumps_the_same_water_as_walking_them() -> void:
	# The offline catch-up walks and the simulator strides. Both have to land on
	# the same number or a night away is worth a different amount depending on
	# which code path measured it.
	var span := 137
	var biomes_data := BiomesData.new()
	biomes_data.unlock(WaterSystem.LAKE_KEY)

	var walked := _well_system(_chain([1] as Array[int]), biomes_data)
	for _i in span:
		walked.handle_tick()
	var by_walking := _player.water.to_float()

	_player = PlayerData.new()
	_player.nutrients = BigNumber.from_value(0.0)
	_well_system(_chain([1] as Array[int]), biomes_data).advance(span)

	assert_float(_player.water.to_float()).is_equal_approx(by_walking, EPS)

# ─── Hoisted invariants ───────────────────────────────────────────────

func test_hoisted_manual_counts_match_the_fresh_ones() -> void:
	var nodes := _chain([2, 0, 7] as Array[int])
	var manual := _system(nodes).manual_node_counts()

	assert_int(manual.size()).is_equal(3)
	assert_float(manual[0].to_float()).is_equal_approx(2.0, EPS)
	assert_float(manual[1].to_float()).is_equal_approx(0.0, EPS)
	assert_float(manual[2].to_float()).is_equal_approx(7.0, EPS)

func test_passed_in_manual_counts_are_used_verbatim() -> void:
	# Same contract as the hoisted bonuses above: the catch-up takes these once
	# and the loop must not silently recompute them.
	var nodes := _chain([1] as Array[int])
	var system := _system(nodes)
	var hoisted := system.manual_node_counts()

	nodes[0].manual_nodes = 99
	system.handle_tick([] as Array[BigNumber], null, hoisted)

	assert_float(_player.nutrients.to_float()).is_equal_approx(1.0, EPS)

func test_a_run_of_ticks_with_every_invariant_hoisted_lands_where_a_plain_run_does() -> void:
	# The offline catch-up drives handle_tick() with all three hoists in hand.
	# It has to pay exactly what the live timer, which hoists nothing, would.
	var span := 137
	var biomes_data := BiomesData.new()
	biomes_data.unlock(WaterSystem.LAKE_KEY)

	var plain := _well_system(_chain([2, 3, 1] as Array[int]), biomes_data)
	for _i in span:
		plain.handle_tick()
	var by_plain := {
		"nutrients": _player.nutrients.to_float(),
		"water": _player.water.to_float(),
		"lifetime": _player.lifetime_nutrients.to_float(),
		"ticks": _player.tick_count,
	}

	_player = PlayerData.new()
	_player.nutrients = BigNumber.from_value(0.0)
	var nodes := _chain([2, 3, 1] as Array[int])
	var hoisted := _well_system(nodes, biomes_data)
	var bonuses := hoisted.node_production_bonuses()
	var manual := hoisted.manual_node_counts()
	var pump := WaterSystem.new(_player, biomes_data, _production).pump_plan()
	for _i in span:
		hoisted.handle_tick(bonuses, pump, manual)

	assert_float(_player.nutrients.to_float()).is_equal_approx(by_plain["nutrients"], EPS)
	assert_float(_player.water.to_float()).is_equal_approx(by_plain["water"], EPS)
	assert_float(_player.lifetime_nutrients.to_float()).is_equal_approx(by_plain["lifetime"], EPS)
	assert_int(_player.tick_count).is_equal(by_plain["ticks"])

func test_a_tick_system_without_a_well_still_runs() -> void:
	# Every existing caller builds this with three arguments.
	var system := _system(_chain([2] as Array[int]))
	system.handle_tick()
	assert_float(_player.water.to_float()).is_zero()
	assert_float(_player.nutrients.to_float()).is_greater(0.0)
