extends GdUnitTestSuite
## Unit tests for PlayerLevelCalculator (model/growth/gd_player_level_calculator.gd).
##
## The ladder is BASE * GROWTH^((n-1)^EXPONENT), so the interesting cases are all
## at a boundary - where the log-space shortcut and the requirement it is
## corrected against have to agree exactly. The exponent bends the ladder without
## moving that contract, so it gets the same boundary sweeps.

const EPS := 0.000001

func _level(value: float) -> int:
	return PlayerLevelCalculator.level_of(BigNumber.from_value(value))

# ---------------------------------------------------------------- levels

func test_a_fresh_save_is_level_zero() -> void:
	assert_int(PlayerLevelCalculator.level_of(BigNumber.new(0.0, 0))).is_equal(0)

func test_below_the_first_requirement_is_still_level_zero() -> void:
	assert_int(_level(999.0)).is_equal(0)

func test_the_first_requirement_lands_level_one() -> void:
	assert_int(_level(PlayerLevelCurve.DEFAULT_BASE)).is_equal(1)

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

# ---------------------------------------------------------------- the curve

func _curve(base: float, growth: float, exponent: float = 1.0) -> PlayerLevelCurve:
	var curve := PlayerLevelCurve.new()
	curve.base = base
	curve.growth = growth
	curve.growth_exponent = exponent
	return curve

## The authored ladder is what the balance editor edits, so it has to be the
## thing the arithmetic actually reads - not a default the curve shadows.
func test_an_authored_curve_moves_the_requirements() -> void:
	var curve := _curve(100.0, 2.0)
	assert_float(PlayerLevelCalculator.requirement(1, curve).to_float()).is_equal_approx(
		100.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(2, curve).to_float()).is_equal_approx(
		200.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(3, curve).to_float()).is_equal_approx(
		400.0, EPS)

func test_an_authored_curve_moves_the_levels() -> void:
	var curve := _curve(100.0, 2.0)
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(99.0), curve)).is_zero()
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(100.0), curve)).is_equal(1)
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(400.0), curve)).is_equal(3)

## Every boundary of an edited curve, the same sweep the default one gets: the
## log-space shortcut has to land on the level below as exactly here as there.
func test_an_authored_curve_lands_on_its_own_boundaries() -> void:
	var curve := _curve(250.0, 1.7)
	for level in range(1, 40):
		var requirement := PlayerLevelCalculator.requirement(level, curve)
		assert_int(PlayerLevelCalculator.level_of(requirement, curve)).override_failure_message(
			"Level %d's requirement should read back as level %d." % [level, level]
			).is_equal(level)
		var just_under := requirement.scale(0.999)
		assert_int(PlayerLevelCalculator.level_of(just_under, curve)).override_failure_message(
			"Just under level %d should read as level %d." % [level, level - 1]
			).is_equal(level - 1)

## No curve at all is the authored default, so a system built without one - every
## test suite that does not care about the ladder - behaves as it always did.
func test_no_curve_is_the_authored_default() -> void:
	assert_float(PlayerLevelCalculator.requirement(1).to_float()).is_equal_approx(
		PlayerLevelCurve.DEFAULT_BASE, EPS)
	assert_float(PlayerLevelCalculator.requirement(2).to_float()).is_equal_approx(
		PlayerLevelCurve.DEFAULT_BASE * PlayerLevelCurve.DEFAULT_GROWTH, EPS)

## A curve edited to nonsense in the editor must not hang the ladder-walking
## loops or hand back a level the requirements disagree with.
func test_a_degenerate_curve_reads_as_level_zero() -> void:
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(1.0e9),
		_curve(1000.0, 1.0))).is_zero()
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(1.0e9),
		_curve(0.0, 3.0))).is_zero()

# ------------------------------------------------------- the growth exponent

## The shipped exponent, and the one every curve built without one gets. The
## whole ladder has to come out bit-identical to the flat-ratio one it replaced,
## or the knob's default silently retunes a live save.
func test_an_exponent_of_one_is_the_ladder_it_replaced() -> void:
	var curve := _curve(1000.0, 3.0, 1.0)
	for level in range(1, 40):
		var with_exponent := PlayerLevelCalculator.requirement(level, curve)
		var default_curve := PlayerLevelCalculator.requirement(level)
		assert_float(with_exponent.log10()).override_failure_message(
			"Level %d moved at an exponent of 1.0." % level
			).is_equal_approx(default_curve.log10(), EPS)

## The point of the knob: above 1.0 the gap between levels widens as the ladder
## climbs, rather than holding at a flat `growth` ratio.
func test_an_exponent_above_one_stretches_the_late_levels() -> void:
	var curve := _curve(1000.0, 3.0, 2.0)
	# base * growth^((n-1)^2): level 2 is one growth up, level 3 is four.
	assert_float(PlayerLevelCalculator.requirement(1, curve).to_float()).is_equal_approx(
		1000.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(2, curve).to_float()).is_equal_approx(
		3000.0, EPS)
	assert_float(PlayerLevelCalculator.requirement(3, curve).to_float()).is_equal_approx(
		81000.0, EPS)

func test_an_exponent_below_one_flattens_the_ladder() -> void:
	var curve := _curve(1000.0, 3.0, 0.5)
	var flat := _curve(1000.0, 3.0, 1.0)
	assert_float(PlayerLevelCalculator.requirement(10, curve).log10()).is_less(
		PlayerLevelCalculator.requirement(10, flat).log10())

## level_of() inverts requirement() by taking a root in log space. Every boundary
## of a bent ladder has to land as exactly as a straight one's, at exponents on
## both sides of 1.0 - a float ulp either way is a whole Level Point.
func test_a_bent_ladder_lands_on_its_own_boundaries() -> void:
	for exponent in [0.6, 1.4, 2.0]:
		var curve := _curve(1000.0, 3.0, exponent)
		for level in range(1, 30):
			var requirement := PlayerLevelCalculator.requirement(level, curve)
			assert_int(PlayerLevelCalculator.level_of(requirement, curve)).override_failure_message(
				"At exponent %f, level %d's requirement read back wrong." % [exponent, level]
				).is_equal(level)
			var just_under := requirement.scale(0.999)
			assert_int(PlayerLevelCalculator.level_of(just_under, curve)).override_failure_message(
				"At exponent %f, just under level %d read wrong." % [exponent, level]
				).is_equal(level - 1)

func test_a_bent_ladder_is_still_level_zero_below_its_first_requirement() -> void:
	var curve := _curve(1000.0, 3.0, 1.8)
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(999.0), curve)).is_zero()
	assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(1.0), curve)).is_zero()

## A bent ladder leaves float range within a handful of levels, which is exactly
## where it is meant to be tuned - the progress bar has to keep moving there.
func test_a_bent_ladder_still_reports_progress_past_float_range() -> void:
	var curve := _curve(1000.0, 3.0, 1.6)
	var low := PlayerLevelCalculator.requirement(40, curve).scale(1.2)
	assert_int(PlayerLevelCalculator.level_of(low, curve)).is_equal(40)
	var pct: float = PlayerLevelCalculator.level_for(low, curve)["pct"]
	assert_float(pct).is_greater(0.0)
	assert_float(pct).is_less(1.0)

## An exponent edited to zero or below has no monotone ladder behind it, so it is
## read as the default rather than walked. Both functions must agree on that, or
## level_of() would correct against requirements it never derived the level from.
func test_a_non_positive_exponent_reads_as_the_default() -> void:
	for exponent in [0.0, -2.0]:
		var curve := _curve(1000.0, 3.0, exponent)
		assert_float(PlayerLevelCalculator.requirement(4, curve).to_float()
			).override_failure_message("Exponent %f did not fall back." % exponent
			).is_equal_approx(27000.0, EPS)
		assert_int(PlayerLevelCalculator.level_of(BigNumber.from_value(27000.0), curve)
			).is_equal(4)

## The shipped file, not a hand-made one: the editor writes this, and a value
## that reads as degenerate would flatten every level to zero in a live game.
func test_the_authored_curve_file_is_sane() -> void:
	var curve := load("res://data/growth/res_player_level_curve.tres") as PlayerLevelCurve
	assert_object(curve).is_not_null()
	assert_float(curve.base).is_greater(0.0)
	assert_float(curve.growth).is_greater(1.0)
	assert_float(curve.growth_exponent).is_greater(0.0)
