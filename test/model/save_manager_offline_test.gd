extends GdUnitTestSuite
## Arming and re-arming of the offline gap in SaveManager (autoload/save_manager.gd).
##
## Android sends APPLICATION_RESUMED *and* FOCUS_IN per resume, plus FOCUS_IN at
## app start, so this state machine is driven several times per real resume and
## its failure mode is a duplicated or replayed catch-up. The instance under test
## is built directly rather than via the autoload, with an injected clock, so the
## thresholds can be crossed without waiting for them.

const HOUR := 3600.0
const START := 1_700_000_000.0   # any fixed epoch, the logic only reads deltas

var _manager: Node
var _clock: Array[float]

func before_test() -> void:
	_manager = auto_free(load("res://autoload/save_manager.gd").new())
	_clock = [START]
	var clock := _clock
	_manager.now_provider = func() -> float: return clock[0]

func _advance(seconds: float) -> void:
	_clock[0] += seconds

## Arms from a save written `ago` seconds before now.
func _arm(ago: float, notify: bool = false) -> void:
	_manager._arm_offline_progress(_clock[0] - ago, notify)

# ─── Arming ──────────────────────────────────────────────────────────────────

func test_a_long_gap_arms() -> void:
	_arm(5.0 * HOUR)
	assert_bool(_manager.has_pending_offline_progress()).is_true()

func test_a_gap_at_exactly_the_minimum_does_not_arm() -> void:
	_arm(OfflineProgress.MIN_SECONDS)
	assert_bool(_manager.has_pending_offline_progress()).is_false()

func test_a_gap_just_past_the_minimum_arms() -> void:
	_arm(OfflineProgress.MIN_SECONDS + 1.0)
	assert_bool(_manager.has_pending_offline_progress()).is_true()

func test_a_missing_timestamp_is_ignored() -> void:
	# load_game() has not run yet, so last_savegame has no saved_at and a resume
	# passes 0. Arming from that would measure the gap from the epoch.
	_manager._arm_offline_progress(0.0, false)
	assert_bool(_manager.has_pending_offline_progress()).is_false()

func test_a_missing_timestamp_does_not_clobber_an_armed_gap() -> void:
	# The startup order that produces this: load_game() arms a real gap, then
	# Android's FOCUS_IN arrives with an empty last_savegame.
	_arm(5.0 * HOUR)
	_manager._arm_offline_progress(0.0, false)
	assert_bool(_manager.has_pending_offline_progress()).is_true()

func test_arming_twice_for_one_resume_is_idempotent() -> void:
	# RESUMED and FOCUS_IN both fire, from the same saved_at.
	var saved_at := _clock[0] - 5.0 * HOUR
	_manager._arm_offline_progress(saved_at, true)
	_manager._arm_offline_progress(saved_at, true)
	assert_float(_manager._pending_offline_saved_at).is_equal_approx(saved_at, 0.001)

func test_arming_notifies_only_when_asked() -> void:
	# load_game() arms silently, a resume announces itself.
	var emitted: Array[int] = [0]
	_manager.offline_progress_pending.connect(func() -> void: emitted[0] += 1)

	_arm(5.0 * HOUR, false)
	assert_int(emitted[0]).is_zero()

	_arm(5.0 * HOUR, true)
	assert_int(emitted[0]).is_equal(1)

# ─── Short gaps ──────────────────────────────────────────────────────────────

func test_a_short_gap_clears_a_previously_armed_one() -> void:
	# Alt-tabbing away for a moment after a long absence ends the pending gap
	# rather than leaving it to fire later.
	_arm(5.0 * HOUR)
	_arm(2.0)
	assert_bool(_manager.has_pending_offline_progress()).is_false()

func test_a_cleared_short_gap_does_not_ripen_into_a_pending_one() -> void:
	# The bug the clear-to-zero exists for: keeping a sub-threshold timestamp
	# would let wall-clock alone push it past the minimum, and a mid-session
	# refresh would open a catch-up for time the player was watching.
	_arm(2.0)
	_advance(6.0 * HOUR)
	assert_bool(_manager.has_pending_offline_progress()).is_false()

# ─── Guards while a catch-up runs ────────────────────────────────────────────

func test_arming_is_refused_while_a_catch_up_is_running() -> void:
	# The running catch-up already zeroed the pending timestamp because it owns
	# that gap. Re-arming from the pre-resume saved_at replays the whole gap and
	# opens a second popup.
	_manager._offline_calc_running = true
	_arm(5.0 * HOUR, true)
	assert_bool(_manager.has_pending_offline_progress()).is_false()
	assert_bool(_manager.is_offline_calc_running()).is_true()

func test_a_short_gap_cannot_clear_an_armed_one_mid_catch_up() -> void:
	_arm(5.0 * HOUR)
	_manager._offline_calc_running = true
	_arm(2.0)
	_manager._offline_calc_running = false
	assert_bool(_manager.has_pending_offline_progress()).is_true()

# ─── Elapsed time ────────────────────────────────────────────────────────────

func test_the_gap_grows_with_the_clock_until_it_is_consumed() -> void:
	_arm(5.0 * HOUR)
	# Explicit type: _manager is a Node, so the member read comes back Variant.
	var armed_at: float = _manager._pending_offline_saved_at

	_advance(HOUR)

	# Still the same timestamp: the gap is measured at collection time, not
	# frozen when armed.
	assert_float(_manager._pending_offline_saved_at).is_equal_approx(armed_at, 0.001)
	assert_float(_clock[0] - armed_at).is_equal_approx(6.0 * HOUR, 0.001)
