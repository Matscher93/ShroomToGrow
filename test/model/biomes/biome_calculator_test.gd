extends GdUnitTestSuite
## Unit tests for BiomeCalculator (model/biomes/gd_biome_calculator.gd).
##
## Its counters used to be read off the App autoload, which made this class
## impossible to test at all: autoloads do not exist outside a running game.

func test_levels_start_at_one() -> void:
	var info := BiomeCalculator.level_for(0)
	assert_int(info.level).is_equal(1)
	assert_int(info.into).is_zero()
	assert_int(info.need).is_equal(6)

func test_level_two_at_six_xp() -> void:
	assert_int(BiomeCalculator.level_for(6).level).is_equal(2)
	assert_int(BiomeCalculator.level_for(5).level).is_equal(1)

func test_progress_into_current_level() -> void:
	var info := BiomeCalculator.level_for(3)
	assert_int(info.level).is_equal(1)
	assert_int(info.into).is_equal(3)

func test_requirement_grows_each_level() -> void:
	# Explicit types: level_for() returns a Dictionary, so these are Variant and
	# := cannot infer them (CODING_STANDARDS.md, "Local variable typing").
	var first: int = BiomeCalculator.level_for(0).need
	var later: int = BiomeCalculator.level_for(1000).need
	assert_int(later).is_greater(first)

func test_high_xp_stays_bounded() -> void:
	# Log growth: the loop must stay short even at absurd xp.
	assert_int(BiomeCalculator.level_for(1_000_000_000).level).is_greater(1)

func test_total_nodes_source_sums_manual_nodes() -> void:
	var a := MyceliumNode.new()
	a.manual_nodes = 7
	var b := MyceliumNode.new()
	b.manual_nodes = 3
	var def := BiomeDef.new()
	def.xp_source = BiomeDef.XpSource.TOTAL_NODES

	assert_int(BiomeCalculator.xp_for(def, [a, b] as Array[MyceliumNode],
		UpgradeSystem.new(), PlayerData.new())).is_equal(10)

func test_prestige_count_source_is_worth_ten_each() -> void:
	var player := PlayerData.new()
	player.prestige_count = 4
	var def := BiomeDef.new()
	def.xp_source = BiomeDef.XpSource.PRESTIGE_COUNT

	assert_int(BiomeCalculator.xp_for(def, [] as Array[MyceliumNode],
		UpgradeSystem.new(), player)).is_equal(40)

func test_symbiosis_source_uses_total_upgrade_levels() -> void:
	var system := UpgradeSystem.new()
	var d := UpgradeDef.new()
	d.id = &"Thing"
	system.register(d)
	system.from_save({"Thing": 5})
	var def := BiomeDef.new()
	def.xp_source = BiomeDef.XpSource.SYMBIOSIS_LEVELS

	assert_int(BiomeCalculator.xp_for(def, [] as Array[MyceliumNode],
		system, PlayerData.new())).is_equal(5)
