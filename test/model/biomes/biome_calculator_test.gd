extends GdUnitTestSuite
## Unit tests for BiomeCalculator (model/biomes/gd_biome_calculator.gd).
##
## Counters are injected rather than read off the App autoload, which does not
## exist outside a running game and made this class untestable.

func test_levels_start_at_one_with_no_progress() -> void:
	var info := BiomeCalculator.level_for(0)
	assert_int(info.level).is_equal(1)
	assert_int(info.into).is_zero()
	assert_int(info.need).is_greater(0)

func test_the_level_up_lands_exactly_on_the_requirement() -> void:
	# The requirement is read back rather than written in: retuning the curve is
	# a data change, the boundary sitting one XP off is a bug.
	var first_need: int = BiomeCalculator.level_for(0).need

	assert_int(BiomeCalculator.level_for(first_need - 1).level).is_equal(1)
	assert_int(BiomeCalculator.level_for(first_need).level).is_equal(2)
	assert_int(BiomeCalculator.level_for(first_need).into).is_zero()

func test_progress_into_current_level() -> void:
	var first_need: int = BiomeCalculator.level_for(0).need
	var info := BiomeCalculator.level_for(first_need - 1)
	assert_int(info.level).is_equal(1)
	assert_int(info.into).is_equal(first_need - 1)

func test_progress_never_reaches_the_requirement() -> void:
	# into == need would mean a level-up that didn't happen, and the progress bar
	# renders into/need directly.
	for xp in range(0, 400):
		var info := BiomeCalculator.level_for(xp)
		assert_int(info.into) \
			.override_failure_message("xp %d sits at %d/%d of level %d." \
				% [xp, info.into, info.need, info.level]).is_less(info.need)

func test_requirement_grows_each_level() -> void:
	# Explicit types: level_for() returns a Dictionary, so these are Variant and
	# := cannot infer them (CODING_STANDARDS.md, "Local variable typing").
	var first: int = BiomeCalculator.level_for(0).need
	var later: int = BiomeCalculator.level_for(1000).need
	assert_int(later).is_greater(first)

func test_high_xp_stays_bounded() -> void:
	# Exponential growth: the loop must stay short even at absurd xp.
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

func test_achievement_tiers_source_reads_the_player_total() -> void:
	# Crystal Caves levels off the achievement ladder, which is what makes its
	# tab worth opening in the first place.
	var player := PlayerData.new()
	player.achievement_tiers = 12
	var def := BiomeDef.new()
	def.xp_source = BiomeDef.XpSource.ACHIEVEMENT_TIERS

	assert_int(BiomeCalculator.xp_for(def, [] as Array[MyceliumNode],
		UpgradeSystem.new(), player)).is_equal(12)

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
