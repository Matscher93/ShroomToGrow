extends GdUnitTestSuite
## Unit tests for AchievementSystem (model/achievements/gd_achievement_system.gd).
##
## Curves and awarding are driven by hand-built fixtures rather than the authored
## .tres, so retuning an achievement can't turn a rule test red. The authored set
## is swept separately in test/data/authored_data_test.gd.

const EPS := 0.000001

var _progress: AchievementProgress
var _player: PlayerData
var _symbiosis: UpgradeSystem
var _biomes_data: BiomesData
var _production: ProductionSystem

func before_test() -> void:
	_progress = AchievementProgress.new()
	_player = PlayerData.new()
	_symbiosis = UpgradeSystem.new()
	_biomes_data = BiomesData.new()
	var ctx := ResolveContext.new()
	_production = ProductionSystem.new(_symbiosis, UpgradeSystem.new(), UpgradeSystem.new(), ctx)

## goal 10, 20, 40...  reward 1, 2, 4...
func _def(stat: AchievementDef.Stat, max_tier: int = 0) -> AchievementDef:
	var def := AchievementDef.new()
	def.id = &"test_achievement"
	def.display_name = "Test"
	def.stat = stat
	def.goal_base = BigNumber.from_value(10.0)
	def.goal_growth = 2.0
	def.goal_growth_exponent = 1.0
	def.reward_base = BigNumber.from_value(1.0)
	def.reward_growth = 2.0
	def.reward_growth_exponent = 1.0
	def.max_tier = max_tier
	return def

func _system(defs: Array[AchievementDef]) -> AchievementSystem:
	var list := AchievementList.new()
	list.achievements = defs
	return AchievementSystem.new(list, _progress, _player, _production, _symbiosis, _biomes_data)

# ─── Curves ──────────────────────────────────────────────────────────────────

func test_the_goal_rises_with_each_tier() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	assert_float(system.goal_for(def, 0).to_float()).is_equal_approx(10.0, EPS)
	assert_float(system.goal_for(def, 1).to_float()).is_equal_approx(20.0, EPS)
	assert_float(system.goal_for(def, 3).to_float()).is_equal_approx(80.0, EPS)

func test_a_counted_goal_is_always_a_whole_number() -> void:
	# You cannot unlock 5.1 biomes or prestige 5.8 times, so a bar landing
	# between two counts asks for something unreachable.
	var def := _def(AchievementDef.Stat.BIOMES_EVER_UNLOCKED)
	def.goal_base = BigNumber.from_value(2.0)
	def.goal_growth = 1.7
	var system := _system([def])
	for achievement_tier in range(10):
		# Nearest whole rather than an exact zero fraction: BigNumber normalises
		# to mantissa x 10^e, so a clean 201 reads back as 201.00000000000003.
		var goal := system.goal_for(def, achievement_tier).to_float()
		assert_float(absf(goal - round(goal))) \
			.override_failure_message("Tier %d asks for %f, which is not a whole count." \
				% [achievement_tier, goal]).is_less(EPS)

func test_a_counted_goal_rounds_up_never_down() -> void:
	# Rounding down would show a bar the player already cleared.
	var def := _def(AchievementDef.Stat.PRESTIGE_COUNT)
	def.goal_base = BigNumber.from_value(3.0)
	def.goal_growth = 1.1        # raw tier 1 is 3.3
	var system := _system([def])
	assert_float(system.goal_for(def, 1).to_float()).is_equal_approx(4.0, EPS)

func test_consecutive_counted_goals_are_never_equal() -> void:
	# A shallow curve rounds neighbouring tiers to the same number, and a tier
	# whose goal matches the one before it completes the instant that one does,
	# handing out a free tier for no progress.
	var def := _def(AchievementDef.Stat.PRESTIGE_COUNT)
	def.goal_base = BigNumber.from_value(1.0)
	def.goal_growth = 1.05
	var system := _system([def])
	var previous := system.goal_for(def, 0)
	for achievement_tier in range(1, 60):
		var goal := system.goal_for(def, achievement_tier)
		assert_bool(goal.gt(previous)) \
			.override_failure_message("Tier %d asks for %s, no more than tier %d's %s." \
				% [achievement_tier, goal, achievement_tier - 1, previous]).is_true()
		previous = goal

func test_a_shallow_counted_curve_still_takes_one_more_each_tier() -> void:
	var def := _def(AchievementDef.Stat.BIOMES_EVER_UNLOCKED)
	def.goal_base = BigNumber.from_value(1.0)
	def.goal_growth = 1.05
	var system := _system([def])
	assert_float(system.goal_for(def, 0).to_float()).is_equal_approx(1.0, EPS)
	assert_float(system.goal_for(def, 1).to_float()).is_equal_approx(2.0, EPS)
	assert_float(system.goal_for(def, 2).to_float()).is_equal_approx(3.0, EPS)

func test_a_continuous_goal_keeps_its_fraction() -> void:
	# Nutrients and crystals are not counts, and rounding a 1e24 goal is both
	# meaningless and lossy.
	var def := _def(AchievementDef.Stat.LIFETIME_NUTRIENTS)
	def.goal_base = BigNumber.from_value(3.0)
	def.goal_growth = 1.5
	var system := _system([def])
	assert_float(system.goal_for(def, 1).to_float()).is_equal_approx(4.5, EPS)

func test_a_counted_goal_past_float_precision_is_left_alone() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	def.goal_base = BigNumber.new(1.5, 30)
	var system := _system([def])
	var goal := system.goal_for(def, 0)
	assert_int(goal.exponent).is_equal(30)
	assert_float(goal.mantissa).is_equal_approx(1.5, EPS)

func test_the_reward_rises_with_each_tier() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	assert_float(system.reward_for(def, 0).to_float()).is_equal_approx(1.0, EPS)
	assert_float(system.reward_for(def, 2).to_float()).is_equal_approx(4.0, EPS)

func test_the_reward_is_scaled_by_crystal_gain_upgrades() -> void:
	# Authored as +100%, so the payout has to double. A regression here means an
	# entire upgrade track is silently dead.
	var upgrade := UpgradeDef.new()
	upgrade.id = &"CrystalTest"
	var effect := UpgradeEffectDef.new()
	effect.stat = &"crystal_gain"
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = 1.0
	upgrade.effects = [effect]

	var biome_upgrades := UpgradeSystem.new()
	biome_upgrades.register(upgrade)
	biome_upgrades.buy_with_points(&"CrystalTest", true)
	_production = ProductionSystem.new(_symbiosis, biome_upgrades, UpgradeSystem.new(),
		ResolveContext.new())

	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	assert_float(system.reward_for(def, 0).to_float()).is_equal_approx(2.0, EPS)

# ─── Measuring ───────────────────────────────────────────────────────────────

func test_every_stat_is_handled() -> void:
	# An unhandled Stat returns 0 forever, with no error anywhere: the
	# achievement just never moves.
	_player.lifetime_manual_nodes = 1
	_player.lifetime_ticks = 2
	_player.lifetime_nutrients = BigNumber.from_value(3.0)
	_player.lifetime_crystals = BigNumber.from_value(4.0)
	_player.prestige_count = 5
	_player.lifetime_biome_size = 6
	_biomes_data.unlock(&"meadow")
	var upgrade := UpgradeDef.new()
	upgrade.id = &"SymSeed"
	_symbiosis.register(upgrade)
	_symbiosis.buy_with_points(&"SymSeed", true)
	_biomes_data.unlock(&"forest")

	for stat: int in AchievementDef.Stat.values():
		var def := _def(stat)
		var system := _system([def])
		assert_float(system.current_value(def).to_float()) \
			.override_failure_message("Stat %s reads as zero, so nothing can ever complete it." \
				% [AchievementDef.Stat.keys()[stat]]) \
			.is_greater(0.0)

func test_biome_size_counts_every_level_ever_bought() -> void:
	# Reading the current run's sizes instead would reset the bar on every
	# prestige, which is exactly what the lifetime counter exists to avoid.
	var def := _def(AchievementDef.Stat.LIFETIME_BIOME_SIZE)
	var system := _system([def])
	_player.lifetime_biome_size = 7
	_biomes_data.size.clear()   # as a prestige leaves it

	assert_float(system.current_value(def).to_float()).is_equal_approx(7.0, EPS)

func test_symbiosis_counts_every_level_ever_bought() -> void:
	# Reading the levels currently held instead would drop the bar back to zero
	# on every prestige, which is what the lifetime counter exists to avoid.
	var upgrade := UpgradeDef.new()
	upgrade.id = &"SymTest"
	_symbiosis.register(upgrade)
	_symbiosis.buy_with_points(&"SymTest", true)
	_symbiosis.buy_with_points(&"SymTest", true)

	var def := _def(AchievementDef.Stat.LIFETIME_SYMBIOSIS_LEVELS)
	var system := _system([def])
	assert_float(system.current_value(def).to_float()).is_equal_approx(2.0, EPS)

	_symbiosis.reset()   # as a prestige leaves it

	assert_int(_symbiosis.total_levels()).is_zero()
	assert_float(system.current_value(def).to_float()).is_equal_approx(2.0, EPS)

# ─── Completing ──────────────────────────────────────────────────────────────

func test_nothing_completes_below_the_first_goal() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 9
	system.evaluate()
	assert_int(system.tier(def.id)).is_zero()
	assert_int(system.unclaimed(def.id)).is_zero()
	assert_float(_player.crystals.to_float()).is_zero()

func test_crossing_the_goal_pays_nothing_until_it_is_claimed() -> void:
	# The whole point of claiming: completing banks the tier, the crystals wait.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()
	assert_int(system.unclaimed(def.id)).is_equal(1)
	assert_int(system.tier(def.id)).is_zero()
	assert_float(_player.crystals.to_float()).is_zero()
	assert_int(_player.achievement_tiers).is_zero()

func test_one_evaluate_banks_every_tier_crossed_at_once() -> void:
	# An offline catch-up or a big prestige can jump several bars in one go, and
	# none of that may be lost just because nobody was watching.
	# Goals 10 + 20 + 40 are all under 70, tier 4 needs 80.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 70
	system.evaluate()
	assert_int(system.unclaimed(def.id)).is_equal(3)
	assert_float(_player.crystals.to_float()).is_zero()

func test_the_next_goal_keeps_rising_while_claims_sit_waiting() -> void:
	# Not claiming must not stall progress, or leaving the screen alone costs
	# the player tiers.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()
	assert_float(system.current_goal(def).to_float()).is_equal_approx(20.0, EPS)
	_player.lifetime_ticks = 20
	system.evaluate()
	assert_int(system.unclaimed(def.id)).is_equal(2)

func test_the_ladder_stops_at_max_tier() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS, 2)
	var system := _system([def])
	_player.lifetime_ticks = 100000
	system.evaluate()
	assert_int(system.unclaimed(def.id)).is_equal(2)
	assert_bool(system.is_maxed(def)).is_true()

func test_a_second_evaluate_does_not_bank_twice() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()
	system.evaluate()
	assert_int(system.unclaimed(def.id)).is_equal(1)

func test_completing_emits_the_signal_without_a_reward() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	var seen: Array = []
	system.achievement_completed.connect(func(id: StringName, tier: int) -> void:
		seen.append([id, tier]))
	_player.lifetime_ticks = 30
	system.evaluate()
	assert_int(seen.size()).is_equal(2)
	assert_int(seen[0][1]).is_equal(1)
	assert_int(seen[1][1]).is_equal(2)

func test_progress_ratio_is_clamped_to_the_current_tier() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 5
	assert_float(system.progress_ratio(def)).is_equal_approx(0.5, EPS)
	_player.lifetime_ticks = 500
	assert_float(system.progress_ratio(def)).is_equal_approx(1.0, EPS)

# ─── Progress bar ────────────────────────────────────────────────────────────

func test_a_fresh_tier_starts_the_bar_at_empty() -> void:
	# Measuring from zero would leave it at goal(n-1)/goal(n) - 50% on this
	# curve - the instant the tier begins, so it could never read as empty.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)   # goals 10, 20, 40
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()

	assert_int(system.unclaimed(def.id)).is_equal(1)
	assert_float(system.progress_ratio(def)).is_zero()

func test_the_bar_fills_across_the_gap_between_two_goals() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()          # tier 1 banked, now working from 10 towards 20

	_player.lifetime_ticks = 15
	assert_float(system.progress_ratio(def)).is_equal_approx(0.5, EPS)
	_player.lifetime_ticks = 20
	assert_float(system.progress_ratio(def)).is_equal_approx(1.0, EPS)

func test_the_first_tier_still_measures_from_zero() -> void:
	# There is no previous bar to subtract, so tier 0 fills from nothing.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 5
	assert_float(system.progress_ratio(def)).is_equal_approx(0.5, EPS)

func test_a_bar_below_the_previous_goal_reads_as_empty() -> void:
	# Only reachable if a measure can fall, but the bar must not go negative.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()

	_player.lifetime_ticks = 2
	assert_float(system.progress_ratio(def)).is_zero()

func test_a_tier_spanning_orders_of_magnitude_uses_a_log_scale() -> void:
	# Goals 1e3 then 1e9. Linear, the halfway point of the bar would sit at
	# 5e8 - the player would see an empty bar for almost the entire tier.
	var def := _def(AchievementDef.Stat.LIFETIME_NUTRIENTS)
	def.goal_base = BigNumber.from_value(1e3)
	def.goal_growth = 1e6
	var system := _system([def])
	_player.lifetime_nutrients = BigNumber.from_value(1e3)
	system.evaluate()

	# 1e6 is the geometric midpoint of 1e3 and 1e9.
	_player.lifetime_nutrients = BigNumber.from_value(1e6)
	assert_float(system.progress_ratio(def)).is_equal_approx(0.5, EPS)
	_player.lifetime_nutrients = BigNumber.from_value(1e9)
	assert_float(system.progress_ratio(def)).is_equal_approx(1.0, EPS)

func test_a_tier_inside_three_decades_stays_linear() -> void:
	# A factor of 1000 is the cutoff, and just under it must not switch: a log
	# bar on a narrow tier would jump ahead early instead.
	var def := _def(AchievementDef.Stat.LIFETIME_NUTRIENTS)
	def.goal_base = BigNumber.from_value(1.0)
	def.goal_growth = 100.0        # tier 1 is 100, tier 2 is 10000
	var system := _system([def])
	_player.lifetime_nutrients = BigNumber.from_value(100.0)
	system.evaluate()              # working from 100 towards 10000, 2 decades

	_player.lifetime_nutrients = BigNumber.from_value(5050.0)   # linear midpoint
	assert_float(system.progress_ratio(def)).is_equal_approx(0.5, EPS)

func test_a_log_scaled_bar_survives_a_zero_measure() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_NUTRIENTS)
	def.goal_base = BigNumber.from_value(1e3)
	def.goal_growth = 1e6
	var system := _system([def])
	_player.lifetime_nutrients = BigNumber.from_value(1e3)
	system.evaluate()

	_player.lifetime_nutrients = BigNumber.new(0.0, 0)
	assert_float(system.progress_ratio(def)).is_zero()

# ─── Claiming ────────────────────────────────────────────────────────────────

func test_claiming_pays_the_crystals_and_records_the_tier() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 10
	system.evaluate()

	assert_bool(system.claim(def.id)).is_true()
	assert_int(system.tier(def.id)).is_equal(1)
	assert_int(system.unclaimed(def.id)).is_zero()
	assert_float(_player.crystals.to_float()).is_equal_approx(1.0, EPS)
	assert_float(_player.lifetime_crystals.to_float()).is_equal_approx(1.0, EPS)
	assert_int(_player.achievement_tiers).is_equal(1)

func test_claiming_with_nothing_waiting_is_refused() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	assert_bool(system.claim(def.id)).is_false()
	assert_float(_player.crystals.to_float()).is_zero()

func test_claiming_an_unknown_achievement_is_refused() -> void:
	var system := _system([_def(AchievementDef.Stat.LIFETIME_TICKS)])
	assert_bool(system.claim(&"nope")).is_false()

func test_each_banked_tier_pays_its_own_price() -> void:
	# Claiming three at once must pay 1 + 2 + 4, not 1 three times.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 70
	system.evaluate()

	system.claim(def.id)
	system.claim(def.id)
	system.claim(def.id)
	assert_float(_player.crystals.to_float()).is_equal_approx(1.0 + 2.0 + 4.0, EPS)
	assert_int(system.tier(def.id)).is_equal(3)

func test_claim_all_collects_every_achievement_and_returns_the_total() -> void:
	var first := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var second := _def(AchievementDef.Stat.PRESTIGE_COUNT)
	second.id = &"second_achievement"
	second.goal_base = BigNumber.from_value(1.0)
	var system := _system([first, second])
	_player.lifetime_ticks = 30   # two tiers: 1 + 2
	_player.prestige_count = 1    # one tier: 1
	system.evaluate()

	var total := system.claim_all()

	assert_float(total.to_float()).is_equal_approx(4.0, EPS)
	assert_float(_player.crystals.to_float()).is_equal_approx(4.0, EPS)
	assert_bool(system.has_claims()).is_false()
	assert_int(system.total_tiers()).is_equal(3)
	assert_int(_player.achievement_tiers).is_equal(3)

func test_claim_all_with_nothing_waiting_pays_nothing() -> void:
	var system := _system([_def(AchievementDef.Stat.LIFETIME_TICKS)])
	assert_float(system.claim_all().to_float()).is_zero()
	assert_float(_player.crystals.to_float()).is_zero()

func test_claim_reward_is_zero_while_nothing_is_waiting() -> void:
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	assert_float(system.claim_reward(def).to_float()).is_zero()
	_player.lifetime_ticks = 10
	system.evaluate()
	assert_float(system.claim_reward(def).to_float()).is_equal_approx(1.0, EPS)

func test_a_crystal_gain_upgrade_bought_before_claiming_counts() -> void:
	# Rewards are priced when collected, not when completed, so banking tiers and
	# then investing in crystal_gain is a real decision rather than a trap.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var upgrade := UpgradeDef.new()
	upgrade.id = &"CrystalTest"
	var effect := UpgradeEffectDef.new()
	effect.stat = &"crystal_gain"
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = 1.0
	upgrade.effects = [effect]
	var biome_upgrades := UpgradeSystem.new()
	biome_upgrades.register(upgrade)
	_production = ProductionSystem.new(_symbiosis, biome_upgrades, UpgradeSystem.new(),
		ResolveContext.new())
	var system := _system([def])

	_player.lifetime_ticks = 10
	system.evaluate()
	biome_upgrades.buy_with_points(&"CrystalTest", true)   # bought after completing
	system.claim(def.id)

	assert_float(_player.crystals.to_float()).is_equal_approx(2.0, EPS)

func test_total_tiers_counts_claims_only() -> void:
	var first := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var second := _def(AchievementDef.Stat.PRESTIGE_COUNT)
	second.id = &"second_achievement"
	second.goal_base = BigNumber.from_value(1.0)
	var system := _system([first, second])
	_player.lifetime_ticks = 10
	_player.prestige_count = 1
	system.evaluate()

	assert_int(system.total_tiers()).is_zero()
	assert_int(system.total_unclaimed()).is_equal(2)
	system.claim(first.id)
	assert_int(system.total_tiers()).is_equal(1)
	assert_int(system.total_unclaimed()).is_equal(1)

# ─── Prestige ────────────────────────────────────────────────────────────────

func test_tiers_and_crystals_survive_a_prestige() -> void:
	# The whole premise of crystals as a meta-currency: PrestigeSystem must not
	# list them among the fields it zeroes.
	var def := _def(AchievementDef.Stat.LIFETIME_TICKS)
	var system := _system([def])
	_player.lifetime_ticks = 30
	_player.nutrients = BigNumber.from_value(1e9)
	system.evaluate()
	system.claim_all()
	var earned := _player.crystals.to_float()

	var nodes := (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes).mycelium_nodes
	var biomes := load("res://data/biomes/all_biomes.tres") as BiomeList
	var ctx := ResolveContext.new()
	var biome_upgrades := UpgradeSystem.new()
	var prestige_upgrades := UpgradeSystem.new()
	var production := ProductionSystem.new(_symbiosis, biome_upgrades, prestige_upgrades, ctx)
	var biome_system := BiomeSystem.new(biomes, _biomes_data, _player, nodes, production,
		_symbiosis, biome_upgrades, prestige_upgrades, ctx)
	PrestigeSystem.new(_player, _biomes_data, nodes, production, _symbiosis, biome_upgrades,
		biome_system).prestige()

	assert_float(_player.crystals.to_float()).is_equal_approx(earned, EPS)
	assert_int(system.tier(def.id)).is_equal(2)
	assert_int(_player.achievement_tiers).is_equal(2)
