extends GdUnitTestSuite
## Unit tests for StatsSystem (model/stats/gd_stats_system.gd).
##
## The clock is injected, so a milestone recorded "an hour later" costs a float
## rather than an hour. Everything here is about the recording rules - a peak
## only rising, a milestone landing once - rather than about what the overlay
## makes of them.

var _stats: StatsData
var _player: PlayerData
var _biomes: BiomeList
var _biomes_data: BiomesData
var _nodes: Array[MyceliumNode]
var _tick_system: TickSystem
var _symbiosis: UpgradeSystem
var _perks: UpgradeSystem
var _system: StatsSystem
var _now := 1000.0

func before_test() -> void:
	_now = 1000.0
	_stats = StatsData.new()
	_player = PlayerData.new()
	_biomes_data = BiomesData.new()
	_biomes = BiomeList.new()
	_biomes.biomes = [_biome_def(&"loam", "Loam"), _biome_def(&"permafrost", "Permafrost")]
	_nodes = [_node(0, "Sprout"), _node(1, "Cap")]
	_symbiosis = UpgradeSystem.new()
	_perks = UpgradeSystem.new()
	var ctx := ResolveContext.new()
	var production := ProductionSystem.new(_symbiosis, UpgradeSystem.new(), _perks, ctx)
	_tick_system = TickSystem.new(_nodes, _player, production)
	var growth := UpgradeSystem.new()
	var levels := PlayerLevelSystem.new(_player, growth, GrowthProducerList.new(), production)
	_system = StatsSystem.new(_stats, _player, _biomes, _biomes_data, _nodes, _tick_system,
		_symbiosis, _perks, levels, DailyRewardData.new())
	_system.now_provider = func() -> float: return _now

func _biome_def(key: StringName, display_name: String) -> BiomeDef:
	var def := BiomeDef.new()
	def.key = key
	def.display_name = display_name
	return def

func _node(node_id: int, node_name: String) -> MyceliumNode:
	var node := MyceliumNode.new()
	node.node_id = node_id
	node.name = node_name
	return node

# ---------------------------------------------------------------- peaks

func test_currency_peak_only_ever_rises() -> void:
	_system.note_currency(BigNumber.from_value(500.0), &"nutrients")
	_system.note_currency(BigNumber.from_value(10.0), &"nutrients")
	assert_float(_stats.peak(&"nutrients").mantissa).is_equal_approx(5.0, 0.0001)
	assert_int(_stats.peak(&"nutrients").exponent).is_equal(2)

func test_handle_tick_records_the_tick_payout_as_production() -> void:
	_tick_system.last_tick_gain = BigNumber.from_value(42.0)
	_system.handle_tick()
	_tick_system.last_tick_gain = BigNumber.from_value(7.0)
	_system.handle_tick()
	assert_str(_stats.peak(&"production").to_display(0)).is_equal("42")

func test_handle_tick_seeds_both_timestamps_once() -> void:
	_system.handle_tick()
	assert_float(_stats.first_played_at).is_equal(1000.0)
	assert_float(_stats.run_started_at).is_equal(1000.0)
	_now = 5000.0
	_system.handle_tick()
	assert_float(_stats.first_played_at).is_equal(1000.0)
	assert_float(_stats.run_started_at).is_equal(1000.0)

func test_sample_counts_takes_the_structural_peaks() -> void:
	_nodes[0].manual_nodes = 3
	_nodes[1].manual_nodes = 2
	_biomes_data.unlock(&"loam")
	_system.sample_counts()
	assert_int(_stats.count(&"manual_nodes")).is_equal(5)
	assert_int(_stats.count(&"biomes_unlocked")).is_equal(1)
	# A prestige takes the nodes away; the record of having had them does not go
	# with them.
	_nodes[0].manual_nodes = 1
	_nodes[1].manual_nodes = 0
	_system.sample_counts()
	assert_int(_stats.count(&"manual_nodes")).is_equal(5)

# ---------------------------------------------------------------- milestones

func test_a_biome_unlocked_twice_is_one_milestone() -> void:
	_system.note_biome_unlocked(&"loam")
	_now = 9000.0
	_system.note_biome_unlocked(&"loam")
	assert_int(_stats.milestones.size()).is_equal(1)
	assert_float(_stats.milestones[0]["at"]).is_equal(1000.0)

func test_a_node_tier_bought_again_after_a_reset_is_one_milestone() -> void:
	_system.note_node_bought(_nodes[1])
	_system.note_node_bought(_nodes[1])
	_system.note_node_bought(_nodes[0])
	assert_int(_stats.milestones.size()).is_equal(2)
	assert_str(_stats.milestones[0]["key"]).is_equal("1")
	assert_str(_stats.milestones[1]["key"]).is_equal("0")

# ---------------------------------------------------------------- runs

func test_prestige_records_the_run_from_pre_reset_state() -> void:
	_player.tick_count = 240
	_player.nutrients = BigNumber.from_value(1.0e9)
	_nodes[0].manual_nodes = 6
	_biomes_data.unlock(&"loam")
	_biomes_data.unlock(&"permafrost")
	_tick_system.last_tick_gain = BigNumber.from_value(80.0)
	_system.handle_tick()
	_now = 4600.0

	_system.note_prestige(BigNumber.from_value(12.0))

	assert_int(_stats.runs.size()).is_equal(1)
	var run: Dictionary = _stats.runs[0]
	assert_int(int(run["index"])).is_equal(1)
	assert_int(int(run["ticks"])).is_equal(240)
	assert_int(int(run["manual_nodes"])).is_equal(6)
	assert_int(int(run["biomes"])).is_equal(2)
	assert_str(str(run["deepest_biome"])).is_equal("Permafrost")
	assert_float(float(run["started_at"])).is_equal(1000.0)
	assert_float(float(run["ended_at"])).is_equal(4600.0)
	assert_str(BigNumber.from_save(run["biomass_gained"]).to_display(0)).is_equal("12")
	assert_str(BigNumber.from_save(run["peak_production"]).to_display(0)).is_equal("80")

## The runs tab lists water, crystals and the three Ruins currencies beside the
## nutrients, and a record with no key for one of them prints "-" rather than a
## zero - so every field in the list has to actually be written, not just the two
## the tab started with.
func test_prestige_records_every_currency_balance() -> void:
	_player.nutrients = BigNumber.from_value(500.0)
	_player.water = BigNumber.from_value(40.0)
	_player.crystals = BigNumber.from_value(7.0)
	_player.relics = BigNumber.from_value(3.0)

	_system.note_prestige(BigNumber.from_value(1.0))

	var run: Dictionary = _stats.runs[0]
	for field: String in StatsSystem.CURRENCY_FIELDS:
		assert_bool(run.has(field)).override_failure_message(
			"run record is missing %s" % field).is_true()
	assert_str(BigNumber.from_save(run["water"]).to_display(0)).is_equal("40")
	assert_str(BigNumber.from_save(run["crystals"]).to_display(0)).is_equal("7")
	assert_str(BigNumber.from_save(run["relics"]).to_display(0)).is_equal("3")

func test_prestige_restarts_the_run_clock_and_the_run_peak() -> void:
	_tick_system.last_tick_gain = BigNumber.from_value(80.0)
	_system.handle_tick()
	_now = 4600.0
	_system.note_prestige(BigNumber.from_value(1.0))
	assert_float(_stats.run_started_at).is_equal(4600.0)

	# The all-time peak stays where it was; the next run's record starts from
	# nothing rather than inheriting it.
	_tick_system.last_tick_gain = BigNumber.from_value(5.0)
	_system.handle_tick()
	_now = 9000.0
	_system.note_prestige(BigNumber.from_value(1.0))
	assert_str(_stats.peak(&"production").to_display(0)).is_equal("80")
	assert_str(BigNumber.from_save(_stats.runs[1]["peak_production"]).to_display(0)).is_equal("5")

func test_the_run_cap_drops_the_oldest_and_leaves_the_peaks_alone() -> void:
	_stats.raise_peak(&"production", BigNumber.from_value(999.0))
	for i in StatsData.MAX_RUNS + 3:
		_player.prestige_count = i
		_system.note_prestige(BigNumber.from_value(1.0))
	assert_int(_stats.runs.size()).is_equal(StatsData.MAX_RUNS)
	assert_int(int(_stats.runs[0]["index"])).is_equal(4)
	assert_str(_stats.peak(&"production").to_display(0)).is_equal("999")

# ---------------------------------------------------------------- save

func test_stats_round_trip_through_a_save() -> void:
	_system.note_currency(BigNumber.from_value(1.0e12), &"crystals")
	_system.note_biome_unlocked(&"loam")
	_system.note_prestige(BigNumber.from_value(3.0))
	_stats.raise_count(&"player_level", 17)

	var restored := StatsData.from_save(_stats.to_save())
	assert_str(restored.peak(&"crystals").to_display(0)).is_equal("1T")
	assert_int(restored.count(&"player_level")).is_equal(17)
	assert_int(restored.milestones.size()).is_equal(2)
	assert_int(restored.runs.size()).is_equal(1)
	assert_float(restored.run_started_at).is_equal(_stats.run_started_at)

## A save written before stats existed has no bucket at all, and must load as an
## empty one rather than fail the whole load.
func test_a_missing_bucket_loads_as_empty() -> void:
	_stats.raise_peak(&"nutrients", BigNumber.from_value(5.0))
	_stats.load_from_save({})
	assert_int(_stats.peaks.size()).is_equal(0)
	assert_int(_stats.milestones.size()).is_equal(0)
	assert_float(_stats.run_started_at).is_equal(0.0)
