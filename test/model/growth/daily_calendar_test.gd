extends GdUnitTestSuite
## Unit tests for DailyCalendar (model/growth/gd_daily_calendar.gd).
##
## The whole system's notion of "a day" is this one function, so the boundaries
## are worth pinning: an off-by-one here is a reward the player can claim twice,
## or one they cannot claim at all.

const DAY := 86400.0

func test_the_epoch_is_day_zero() -> void:
	assert_int(DailyCalendar.day_index(0.0, 0)).is_zero()

func test_a_day_lasts_until_its_last_second() -> void:
	assert_int(DailyCalendar.day_index(DAY - 1.0, 0)).is_zero()

func test_midnight_starts_the_next_day() -> void:
	assert_int(DailyCalendar.day_index(DAY, 0)).is_equal(1)

func test_days_keep_counting_up() -> void:
	assert_int(DailyCalendar.day_index(DAY * 19_000.0, 0)).is_equal(19_000)

# ---------------------------------------------------------------- offsets

## An hour east of UTC, the local day rolls over an hour before UTC midnight.
func test_a_positive_offset_rolls_the_day_over_early() -> void:
	assert_int(DailyCalendar.day_index(DAY - 3601.0, 60)).is_zero()
	assert_int(DailyCalendar.day_index(DAY - 3600.0, 60)).is_equal(1)

## Five hours west, it rolls over five hours after.
func test_a_negative_offset_rolls_the_day_over_late() -> void:
	assert_int(DailyCalendar.day_index(DAY, -300)).is_zero()
	assert_int(DailyCalendar.day_index(DAY + 18000.0, -300)).is_equal(1)

## Before the epoch the index goes negative rather than truncating toward zero,
## which is what floor() is there for - two timestamps on the same pre-epoch day
## have to share an index like any other pair.
func test_before_the_epoch_the_index_goes_negative() -> void:
	assert_int(DailyCalendar.day_index(-1.0, 0)).is_equal(-1)
	assert_int(DailyCalendar.day_index(-DAY, 0)).is_equal(-1)
	assert_int(DailyCalendar.day_index(-DAY - 1.0, 0)).is_equal(-2)
