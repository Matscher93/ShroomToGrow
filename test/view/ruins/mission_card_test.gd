extends GdUnitTestSuite
## The mission card's countdown, and specifically that its bar is continuous.
##
## A mission finishes on the wall clock, so nothing in the model fires as one
## counts down. The card animates its own bar from _process for exactly that
## reason: every polling scheme that was tried instead - a game tick, a one-second
## timer - showed up on screen as the bar stepping at that interval.
##
## Driven by moving an injected clock rather than by waiting, and restored in
## after_test: MissionSystem.now_provider is on the live App autoload that every
## later suite shares.

const CARD := "res://view/ruins/sc_mission_card.tscn"
const MISSION := &"sift_rubble"
const EPS := 0.0001

var _card: PanelContainer
var _now: float = 0.0
var _saved_provider: Callable
var _saved_ruins: Dictionary

func before_test() -> void:
	_saved_provider = App.mission_system.now_provider
	_saved_ruins = App.ruins_data.to_save()
	_now = float(Time.get_unix_time_from_system())
	App.mission_system.now_provider = func() -> float: return _now

	_card = (load(CARD) as PackedScene).instantiate()
	add_child(_card)
	_card.bind(App.mission_vms[MISSION])
	await get_tree().process_frame

func after_test() -> void:
	# Freed rather than auto_free()'d: _exit_tree() disconnects the ViewModel and
	# only runs on an actual removal.
	remove_child(_card)
	_card.free()
	App.mission_system.now_provider = _saved_provider
	App.ruins_data.load_from_save(_saved_ruins)

## Puts a mission on the board directly, so the test does not depend on a
## creature being recruited or affordable in whatever save is loaded.
func _send(duration: float) -> int:
	return App.ruins_data.add(MISSION, &"test_creature", _now, duration, [])

# ─── The bar ─────────────────────────────────────────────────────────────────

func test_the_bar_reads_zero_to_one_rather_than_a_percentage() -> void:
	# A 0..100 range with the default step of 1 quantises to whole percent, which
	# is the other half of why the bar used to move in visible jumps.
	assert_float(_card.bar_progress.max_value).is_equal_approx(1.0, EPS)
	assert_float(_card.bar_progress.step).is_equal_approx(0.0, EPS)

func test_an_idle_card_stays_out_of_the_frame_loop() -> void:
	assert_bool(_card.is_processing()).override_failure_message(
		"An idle mission card is still processing every frame.").is_false()
	assert_bool(_card.bar_progress.visible).is_false()

func test_a_sent_mission_puts_the_card_into_the_frame_loop() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	assert_bool(_card.is_processing()).is_true()
	assert_bool(_card.bar_progress.visible).is_true()

## The point of the whole change: a fraction of a second of wall clock moves the
## bar, with no notification sent and no whole second elapsed.
func test_the_bar_moves_on_a_part_second_with_no_notification() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	var before: float = _card.bar_progress.value

	_now += 0.25
	await get_tree().process_frame

	assert_float(_card.bar_progress.value).override_failure_message(
		"The bar did not move across a quarter second of wall clock.").is_greater(before)
	assert_float(_card.bar_progress.value).is_equal_approx(0.0025, EPS)

func test_the_bar_tracks_the_clock_across_the_whole_errand() -> void:
	# Measured off the moment of the send rather than off a fresh read of the real
	# clock: the two drift by however long the test itself has been running, which
	# is exactly the kind of slack that makes a suite flake at 3am.
	var sent_at := _now
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	for elapsed: float in [10.0, 33.3, 50.0, 99.9]:
		_now = sent_at + elapsed
		await get_tree().process_frame
		assert_float(_card.bar_progress.value).override_failure_message(
			"At %.1fs of 100s the bar read %f." % [elapsed, _card.bar_progress.value]) \
			.is_equal_approx(elapsed / 100.0, EPS)

func test_the_bar_stops_at_one_rather_than_running_past_it() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	_now += 500.0
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).is_equal_approx(1.0, EPS)

# ─── The label and the button ────────────────────────────────────────────────

## The label only ever renders whole seconds, so it is deliberately *not* rewritten
## every frame - only the bar is.
func test_the_countdown_label_is_left_alone_within_one_second() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	var before: String = _card.lbl_countdown.text
	_now += 0.25
	await get_tree().process_frame
	assert_str(_card.lbl_countdown.text).is_equal(before)

func test_the_countdown_label_follows_the_clock_across_a_second() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	var before: String = _card.lbl_countdown.text
	_now += 5.0
	await get_tree().process_frame
	assert_str(_card.lbl_countdown.text).is_not_equal(before)

## The frame the errand lands is the frame Collect has to come alive - not the
## next poll, up to a second later.
func test_the_collect_button_arms_on_the_frame_the_mission_lands() -> void:
	_send(100.0)
	App.ruins_vm.poll_clock()
	await get_tree().process_frame
	assert_bool(_card.btn_action.disabled).is_true()

	_now += 100.0
	await get_tree().process_frame

	assert_bool(_card.btn_action.disabled).override_failure_message(
		"Collect was still disabled on the frame the mission finished.").is_false()
	assert_str(_card.btn_action.text).is_equal("Collect")
	assert_str(_card.lbl_countdown.text).is_equal("Ready")
