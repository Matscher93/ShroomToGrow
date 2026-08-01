extends GdUnitTestSuite
## Unit tests for OfflineProgress (model/gd_offline_progress.gd).
##
## Pure arithmetic, so the boundaries can be checked without a wall clock. The
## payout the catch-up loop hands a returning player comes straight out of
## simulated_ticks(), and there is no way to notice it drifting in play.

const EPS := 0.000001

## The subtraction loop SaveManager used to run inline. simulated_ticks() has to
## agree with it exactly or a refactor silently retunes offline income.
func _reference_ticks(elapsed: float, tick_duration: float) -> int:
	var remaining := elapsed - tick_duration
	var ticks := 0
	while remaining > 0.0:
		remaining -= tick_duration
		ticks += 1
	return ticks

# ─── Threshold ───────────────────────────────────────────────────────────────

func test_a_gap_at_exactly_the_minimum_is_not_worth_showing() -> void:
	# Arming and polling used to compare this boundary with different operators,
	# so a gap of exactly MIN_SECONDS armed and then never resolved.
	assert_bool(OfflineProgress.is_gap_worth_showing(OfflineProgress.MIN_SECONDS)).is_false()

func test_a_gap_below_the_minimum_is_not_worth_showing() -> void:
	assert_bool(OfflineProgress.is_gap_worth_showing(0.0)).is_false()
	assert_bool(OfflineProgress.is_gap_worth_showing(OfflineProgress.MIN_SECONDS - 0.1)).is_false()

func test_a_gap_past_the_minimum_is_worth_showing() -> void:
	assert_bool(OfflineProgress.is_gap_worth_showing(OfflineProgress.MIN_SECONDS + 0.1)).is_true()

func test_a_negative_gap_is_not_worth_showing() -> void:
	# A clock that went backwards (timezone change, NTP correction) must not
	# produce a popup.
	assert_bool(OfflineProgress.is_gap_worth_showing(-5000.0)).is_false()

# ─── Cap ─────────────────────────────────────────────────────────────────────

func test_a_gap_under_the_cap_passes_through() -> void:
	assert_float(OfflineProgress.capped(3600.0)).is_equal_approx(3600.0, EPS)

func test_a_gap_over_the_cap_is_clamped() -> void:
	assert_float(OfflineProgress.capped(OfflineProgress.MAX_SECONDS * 10.0)) \
		.is_equal_approx(OfflineProgress.MAX_SECONDS, EPS)

func test_a_month_away_pays_the_same_as_the_cap() -> void:
	var month := 30.0 * 86400.0
	assert_int(OfflineProgress.simulated_ticks(OfflineProgress.capped(month), 10.0)) \
		.is_equal(OfflineProgress.simulated_ticks(OfflineProgress.MAX_SECONDS, 10.0))

# ─── Tick count ──────────────────────────────────────────────────────────────

func test_the_first_interval_buys_nothing() -> void:
	# One full interval has to elapse before a tick lands, matching the live
	# timer: closing the app and reopening it a tick later is worth zero.
	assert_int(OfflineProgress.simulated_ticks(0.0, 10.0)).is_zero()
	assert_int(OfflineProgress.simulated_ticks(9.9, 10.0)).is_zero()
	assert_int(OfflineProgress.simulated_ticks(10.0, 10.0)).is_zero()

func test_each_further_interval_buys_one_tick() -> void:
	assert_int(OfflineProgress.simulated_ticks(10.1, 10.0)).is_equal(1)
	assert_int(OfflineProgress.simulated_ticks(20.0, 10.0)).is_equal(1)
	assert_int(OfflineProgress.simulated_ticks(100.0, 10.0)).is_equal(9)

func test_a_shorter_tick_duration_pays_more() -> void:
	assert_int(OfflineProgress.simulated_ticks(100.0, 1.0)).is_equal(99)
	assert_int(OfflineProgress.simulated_ticks(100.0, 10.0)).is_equal(9)

func test_the_capped_day_is_a_bounded_loop() -> void:
	# The catch-up loop runs this many iterations on the main thread, timesliced.
	# At the minimum tick duration it is the worst case the budget has to cover.
	assert_int(OfflineProgress.simulated_ticks(OfflineProgress.MAX_SECONDS, 1.0)) \
		.is_equal(86399)

func test_a_zero_tick_duration_pays_nothing_instead_of_hanging() -> void:
	# The old subtraction loop never terminated on this.
	assert_int(OfflineProgress.simulated_ticks(5000.0, 0.0)).is_zero()
	assert_int(OfflineProgress.simulated_ticks(5000.0, -1.0)).is_zero()

func test_a_negative_gap_pays_nothing() -> void:
	assert_int(OfflineProgress.simulated_ticks(-5000.0, 10.0)).is_zero()

func test_the_count_matches_the_loop_it_replaced() -> void:
	for tick_duration: float in [1.0, 2.5, 10.0]:
		for elapsed: float in [0.0, 30.0, 61.0, 100.0, 3600.0, 86400.0]:
			assert_int(OfflineProgress.simulated_ticks(elapsed, tick_duration)) \
				.override_failure_message("elapsed %f at %fs/tick" % [elapsed, tick_duration]) \
				.is_equal(_reference_ticks(elapsed, tick_duration))

func test_any_showable_gap_is_worth_at_least_one_tick() -> void:
	# The progress bar divides by this total, and a popup that opened for a gap
	# worth zero ticks would show an empty diff.
	var just_showable := OfflineProgress.MIN_SECONDS + 0.1
	for tick_duration: float in [1.0, 5.0, 10.0]:
		assert_int(OfflineProgress.simulated_ticks(just_showable, tick_duration)) \
			.override_failure_message("%fs/tick pays nothing for a showable gap" % tick_duration) \
			.is_greater(0)
