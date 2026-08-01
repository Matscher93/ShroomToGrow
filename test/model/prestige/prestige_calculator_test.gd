extends GdUnitTestSuite
## Unit tests for PrestigeCalculator (model/prestige/gd_prestige_calculator.gd).
##
## The formula itself is a tuning placeholder, so these pin the *boundaries* a
## retune must not cross rather than the exact curve: never negative, monotonic
## in both inputs, and zero on a fresh run so can_prestige() stays false.

const EPS := 0.000001

func _gain(tick_count: int, nutrients: float) -> float:
	return PrestigeCalculator.calculate_biomass_gain(
		tick_count, BigNumber.from_value(nutrients)).to_float()

func test_a_fresh_run_is_worth_nothing() -> void:
	# App gates the prestige button on gain > 0, so a non-zero value here would
	# offer a prestige to a player who has done nothing.
	assert_float(_gain(0, 1.0)).is_zero()

func test_sub_unit_nutrients_never_go_negative() -> void:
	# nutrients below 1.0 have a negative exponent, so the raw formula goes
	# negative and only the max() clamp keeps it out of player_data.biomass.
	assert_float(_gain(0, 0.001)).is_zero()
	assert_float(_gain(0, 1e-30)).is_zero()

func test_gain_grows_with_nutrient_magnitude() -> void:
	assert_float(_gain(0, 1e6)).is_equal_approx(6.0, EPS)
	assert_float(_gain(0, 1e12)).is_equal_approx(12.0, EPS)

func test_magnitude_not_mantissa_drives_the_gain() -> void:
	# Everything inside one order of magnitude is worth the same, which is what
	# makes the curve a magnitude ladder rather than a linear payout.
	assert_float(_gain(0, 1e6)).is_equal_approx(_gain(0, 9.99e6), EPS)
	assert_float(_gain(0, 1e7)).is_greater(_gain(0, 9.99e6))

func test_ticks_survived_add_to_the_gain() -> void:
	# sqrt(10000) * 0.1 = 10 on top of the magnitude.
	assert_float(_gain(10000, 1e6)).is_equal_approx(16.0, EPS)

func test_gain_is_monotonic_in_tick_count() -> void:
	var previous := _gain(0, 1e6)
	for ticks: int in [100, 10_000, 1_000_000, 100_000_000]:
		var current := _gain(ticks, 1e6)
		assert_float(current).is_greater_equal(previous)
		previous = current

func test_gain_is_a_whole_number() -> void:
	# The perk tree prices in whole biomass, so a fractional gain would leave a
	# permanently unspendable remainder.
	for nutrients: float in [1e6, 5.5e6, 1e13]:
		var gain := _gain(7777, nutrients)
		assert_float(gain).is_equal_approx(round(gain), EPS)
