extends GdUnitTestSuite
## Unit tests for PrestigeCalculator (model/prestige/gd_prestige_calculator.gd).
##
## The payout is a step function over filled storage areas - one step per area,
## all of them summed - and every constant it uses is authored on a
## PrestigeCurveDef, so these build their own def rather than reading
## data/prestige/res_prestige_curve.tres, which is tuning and moves. What is
## pinned is the shape: never negative, zero on a fresh run, monotonic in both
## inputs, whole biomass, and a step added at each area boundary.

const EPS := 0.000001

var _def: PrestigeCurveDef

func before_test() -> void:
	# Nutrient areas at 1e3, 1e4, 1e5 …; tick areas at 100, 200, 400 …; a filled
	# area is worth 2x the one before, starting at 1 biomass.
	_def = PrestigeCurveDef.new()
	_def._nutrient_base_mantissa = 1.0
	_def._nutrient_base_exponent = 3
	_def.nutrient_growth = 10.0
	_def._tick_base_mantissa = 1.0
	_def._tick_base_exponent = 2
	_def.tick_growth = 2.0
	_def._payout_base_mantissa = 1.0
	_def._payout_base_exponent = 0
	_def.payout_growth = 2.0
	_def.max_areas = 200

func _gain(tick_count: int, nutrients: float) -> float:
	return PrestigeCalculator.calculate_biomass_gain(
		tick_count, BigNumber.from_value(nutrients), _def).to_float()

# ─── Storage ladders ─────────────────────────────────────────────────────────

func test_nothing_below_the_first_area_counts() -> void:
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(999.0), _def)).is_zero()
	assert_int(PrestigeCalculator.tick_areas(99, _def)).is_zero()

func test_an_area_fills_exactly_at_its_threshold() -> void:
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(1e3), _def)).is_equal(1)
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(1e4), _def)).is_equal(2)
	assert_int(PrestigeCalculator.tick_areas(100, _def)).is_equal(1)
	assert_int(PrestigeCalculator.tick_areas(200, _def)).is_equal(2)

func test_a_part_filled_area_does_not_count_yet() -> void:
	# Whole areas only: 9.99e3 is 99% of the way to the second area and worth
	# exactly what the first one was.
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(9.99e3), _def)).is_equal(1)
	assert_float(_gain(0, 9.99e3)).is_equal_approx(_gain(0, 1e3), EPS)

func test_the_fill_fraction_matches_the_amounts_the_bar_is_labelled_with() -> void:
	# The first area spans 0 to 1e3, the second 1e3 to 1e4: the bar is the plain
	# ratio across whichever one is being filled, so it agrees with the "X / Y"
	# the label carries.
	assert_float(PrestigeCalculator.fill_fraction(
		BigNumber.from_value(500.0), _def.nutrient_base(), _def.nutrient_growth, 1.0, 0)) \
		.is_equal_approx(0.5, 0.001)
	assert_float(PrestigeCalculator.fill_fraction(
		BigNumber.from_value(5.5e3), _def.nutrient_base(), _def.nutrient_growth, 1.0, 1)) \
		.is_equal_approx(0.5, 0.001)

func test_the_fill_fraction_never_leaves_its_bar() -> void:
	assert_float(PrestigeCalculator.fill_fraction(
		BigNumber.from_value(0.0), _def.nutrient_base(), _def.nutrient_growth, 1.0, 0)).is_zero()
	assert_float(PrestigeCalculator.fill_fraction(
		BigNumber.from_value(1e30), _def.nutrient_base(), _def.nutrient_growth, 1.0, 1)) \
		.is_equal_approx(1.0, EPS)

func test_an_area_threshold_is_what_that_area_costs() -> void:
	assert_float(PrestigeCalculator.area_threshold(
		_def.nutrient_base(), _def.nutrient_growth, 1.0, 1).to_float()).is_equal_approx(1e3, 1.0)
	assert_float(PrestigeCalculator.area_threshold(
		_def.nutrient_base(), _def.nutrient_growth, 1.0, 3).to_float()).is_equal_approx(1e5, 1.0)
	# Area 0 is the empty ladder, not a price.
	assert_float(PrestigeCalculator.area_threshold(
		_def.nutrient_base(), _def.nutrient_growth, 1.0, 0).to_float()).is_zero()

func test_max_areas_clamps_a_ladder() -> void:
	_def.max_areas = 3
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(1e300), _def)).is_equal(3)

func test_a_flat_ladder_cannot_run_away() -> void:
	# growth 1.0 gives every area the same threshold, so there is no area width
	# to divide by. Clamped rather than looped - see PrestigeCurveDef.max_areas.
	_def.nutrient_growth = 1.0
	_def.max_areas = 5
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(1e30), _def)).is_equal(5)
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.from_value(1.0), _def)).is_zero()

# ─── Bent ladders ────────────────────────────────────────────────────────────

func test_an_exponent_of_one_leaves_the_index_alone() -> void:
	# The whole point of the default: an unbent ladder is the plain index, so
	# every number above this section still describes the shipped curve.
	for area: int in [0, 1, 5, 40]:
		assert_float(PrestigeCalculator.scaled_area(area, 1.0)) \
			.is_equal_approx(float(area), EPS)

func test_an_exponent_below_one_is_clamped_away() -> void:
	# Under 1.0 the index peaks and falls again, which would price a later area
	# below an earlier one. Clamped rather than trusted - see PrestigeCurveDef.
	assert_float(PrestigeCalculator.scaled_area(3, 0.5)).is_equal_approx(3.0, EPS)
	assert_float(PrestigeCalculator.scaled_area(3, 0.0)).is_equal_approx(3.0, EPS)

func test_an_exponent_bends_the_ladder_upward() -> void:
	# base 1e3, growth 10, exponent 1.2: area k above the base costs
	# 1e3 * 10^(k * 1.2^k), so the ladder's exponents run 3, 4.2, 5.88, 8.184 …
	_def.nutrient_growth_exponent = 1.2
	for expected: Array in [[1, 3.0], [2, 4.2], [3, 5.88], [4, 8.184]]:
		var threshold := PrestigeCalculator.area_threshold(
			_def.nutrient_base(), _def.nutrient_growth, 1.2, int(expected[0]))
		assert_float(threshold.log10()).is_equal_approx(float(expected[1]), 0.0001)

func test_a_bent_ladder_is_inverted_exactly() -> void:
	# The bent ladder has no closed-form inverse, so areas_filled bisects it. What
	# it must still agree with is area_threshold: an amount sitting exactly on
	# area N's threshold has filled N areas, and a hair under it has filled N-1.
	_def.nutrient_growth_exponent = 1.2
	for area: int in range(1, 7):
		var threshold := PrestigeCalculator.area_threshold(
			_def.nutrient_base(), _def.nutrient_growth, 1.2, area)
		assert_int(PrestigeCalculator.nutrient_areas(threshold, _def)).is_equal(area)
		assert_int(PrestigeCalculator.nutrient_areas(
			threshold.mul(BigNumber.from_value(0.99)), _def)).is_equal(area - 1)

func test_a_bent_ladder_fills_slower_than_a_straight_one() -> void:
	# What the exponent is for: the same run stands on fewer areas, so the payout
	# stops compounding at the rate the run's own output does.
	var straight := PrestigeCalculator.nutrient_areas(BigNumber.new(1.0, 40), _def)
	_def.nutrient_growth_exponent = 1.2
	var bent := PrestigeCalculator.nutrient_areas(BigNumber.new(1.0, 40), _def)
	assert_int(bent).is_less(straight)
	assert_int(bent).is_greater(0)

func test_a_bent_ladder_stays_monotonic() -> void:
	_def.nutrient_growth_exponent = 1.25
	_def.tick_growth_exponent = 1.25
	var previous := 0.0
	for nutrients: float in [1e3, 1e6, 1e12, 1e30, 1e60]:
		var current := _gain(5000, nutrients)
		assert_float(current).is_greater_equal(previous)
		previous = current

func test_a_bent_ladder_still_clamps_and_still_pays_past_float_range() -> void:
	_def.nutrient_growth_exponent = 1.2
	_def.max_areas = 4
	assert_int(PrestigeCalculator.nutrient_areas(BigNumber.new(1.0, 300), _def)).is_equal(4)
	_def.max_areas = 200
	assert_int(PrestigeCalculator.calculate_biomass_gain(
		0, BigNumber.new(1.0, 400), _def).exponent).is_greater_equal(0)

# ─── Payout ──────────────────────────────────────────────────────────────────

func test_a_fresh_run_is_worth_nothing() -> void:
	# App gates the prestige button on beating the best gain, and a fresh save's
	# best is zero: a non-zero value here would offer a prestige for nothing.
	assert_float(_gain(0, 1.0)).is_zero()

func test_sub_unit_nutrients_never_go_negative() -> void:
	assert_float(_gain(0, 0.001)).is_zero()
	assert_float(_gain(0, 1e-30)).is_zero()

func test_one_filled_area_pays_the_payout_base() -> void:
	assert_float(_gain(0, 1e3)).is_equal_approx(1.0, EPS)

func test_each_further_area_adds_its_own_step() -> void:
	# Every filled area pays a step of its own and the run is paid all of them:
	# two areas (1e4 nutrients) is 1 + 2, three (1e5) is 1 + 2 + 4.
	assert_float(_gain(0, 1e4)).is_equal_approx(3.0, EPS)
	assert_float(_gain(0, 1e5)).is_equal_approx(7.0, EPS)

func test_both_ladders_feed_the_same_payout() -> void:
	# 1e4 nutrients is two areas, 200 ticks is two more: four in total, so
	# 1 + 2 + 4 + 8.
	assert_float(_gain(200, 1e4)).is_equal_approx(15.0, EPS)

func test_a_flat_payout_pays_one_base_per_area() -> void:
	# A growth of 1.0 makes every step the base, so the sum is the base counted
	# out - and it is the case the closed-form sum would divide by zero on.
	_def.payout_growth = 1.0
	assert_float(_gain(200, 1e4)).is_equal_approx(4.0, EPS)

func test_gain_is_monotonic_in_tick_count() -> void:
	var previous := _gain(0, 1e6)
	for ticks: int in [100, 10_000, 1_000_000, 100_000_000]:
		var current := _gain(ticks, 1e6)
		assert_float(current).is_greater_equal(previous)
		previous = current

func test_gain_is_monotonic_in_nutrients() -> void:
	var previous := _gain(1000, 1.0)
	for nutrients: float in [1e3, 1e6, 1e12, 1e30]:
		var current := _gain(1000, nutrients)
		assert_float(current).is_greater_equal(previous)
		previous = current

func test_gain_is_a_whole_number() -> void:
	# The perk tree prices in whole biomass, so a fractional gain would leave a
	# permanently unspendable remainder.
	_def.payout_growth = 1.6
	for nutrients: float in [1e6, 5.5e6, 1e13]:
		var gain := _gain(7777, nutrients)
		assert_float(gain).is_equal_approx(round(gain), EPS)

func test_a_run_past_float_range_still_pays() -> void:
	# Run nutrients outgrow a double long before the ladder runs out of areas, so
	# the whole thing is computed in log space.
	var gain := PrestigeCalculator.calculate_biomass_gain(
		0, BigNumber.new(1.0, 400), _def)
	assert_int(gain.exponent).is_greater(0)
