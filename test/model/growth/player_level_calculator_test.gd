extends GdUnitTestSuite
## Unit tests for PlayerLevelCalculator (model/growth/gd_player_level_calculator.gd).
##
## The ladder is BASE * GROWTH^(n-1), so the interesting cases are all at a
## boundary - where the log-space shortcut and the requirement it is corrected
## against have to agree exactly.

const EPS := 0.000001

func _level(value: float) -> int:
	return PlayerLevelCalculator.level_of(BigNumber.from_value(value))

# ---------------------------------------------------------------- levels

func test_a_fresh_save_is_level_zero() -> void:
	assert_int(PlayerLevelCalculator.level_of(BigNumber.new(0.0, 0))).is_equal(0)

func test_below_the_first_requirement_is_still_level_zero() -> void:
	assert_int(_level(999.0)).is_equal(0)

func test_the_first_requirement_lands_level_one() -> void:
	assert_int(_level(PlayerLevelCalculator.BASE)).is_equal(1)

func test_a_level_holds_until_the_next_requirement() -> void:
	assert_int(_level(2999.0)).is_equal(1)

func test_each_requirement_multiplies_by_growth() -> void:
	assert_int(_level(3000.0)).is_equal(2)
	assert_int(_level(9000.0)).is_equal(3)
	assert_int(_level(27000.0)).is_equal(4)

## Every boundary the log-space shortcut has to land on exactly. A float ulp
## either way puts the player a whole level - and a whole Level Point - out.
func test_every_boundary_up_the_ladder_is_exact() -> void:
	for level in range(1, 60):
		var requirement := PlayerLevelCalculator.requirement(level)
		assert_int(PlayerLevelCalculator.level_of(requirement)).override_failure_message(
			"Level %d's own requirement did not resolve to level %d." % [level, level]
			).is_equal(level)

func test_a_hair_under_a_boundary_is_the_level_below() -> void:
	for level in range(2, 60):
		var just_under := PlayerLevelCalculator.requirement(level).scale(0.999)
		assert_int(PlayerLevelCalculator.level_of(just_under)).override_failure_message(
			"Just under level %d's requirement did not resolve to level %d." % [level, level - 1]
			).is_equal(level - 1)

# ---------------------------------------------------------------- requirement

func test_level_zero_requires_nothing() -> void:
	assert_float(PlayerLevelCalculator.requirement(0).to_float()).is_zero()

func test_requirements_follow_the_authored_curve() -> void:
	assert_float(PlayerLevelCalculator.requirement(1).to_float()).is_equal_approx(1000.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(2).to_float()).is_equal_approx(3000.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(3).to_float()).is_equal_approx(9000.0, EPS)

# ---------------------------------------------------------------- progress

func test_progress_reports_the_span_of_the_current_level() -> void:
	var progress := PlayerLevelCalculator.level_for(BigNumber.from_value(1000.0))
	assert_int(progress["level"]).is_equal(1)
	var into: BigNumber = progress["into"]
	var need: BigNumber = progress["need"]
	assert_float(into.to_float()).is_equal_approx(0.0, EPS)
	assert_float(need.to_float()).is_equal_approx(2000.0, EPS)

func test_progress_is_empty_at_the_start_of_a_level() -> void:
	var progress := PlayerLevelCalculator.level_for(BigNumber.from_value(3000.0))
	assert_float(progress["pct"]).is_equal_approx(0.0, EPS)

func test_progress_is_never_reported_past_full() -> void:
	var progress := PlayerLevelCalculator.level_for(BigNumber.from_value(2999.0))
	assert_float(progress["pct"]).is_less(1.0)
	assert_float(progress["pct"]).is_greater(0.0)

func test_an_untouched_save_reports_no_progress_rather_than_erroring() -> void:
	var progress := PlayerLevelCalculator.level_for(BigNumber.new(0.0, 0))
	assert_int(progress["level"]).is_equal(0)
	assert_float(progress["pct"]).is_zero()

## The whole reason pct is measured in log space: at this size into.div(need)
## has no float left to report a ratio with, and the bar would stick at one end
## for the rest of the game.
func test_progress_still_moves_far_past_float_range() -> void:
	var level := 200
	var low := PlayerLevelCalculator.requirement(level).scale(1.2)
	var high := PlayerLevelCalculator.requirement(level).scale(2.5)
	assert_int(PlayerLevelCalculator.level_of(low)).is_equal(level)
	assert_int(PlayerLevelCalculator.level_of(high)).is_equal(level)
	var low_pct: float = PlayerLevelCalculator.level_for(low)["pct"]
	var high_pct: float = PlayerLevelCalculator.level_for(high)["pct"]
	assert_float(low_pct).is_greater(0.0)
	assert_float(high_pct).is_less(1.0)
	assert_float(high_pct).is_greater(low_pct)
