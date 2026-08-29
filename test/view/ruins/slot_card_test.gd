extends GdUnitTestSuite
## The slot card's countdown, and specifically that its bar is continuous.
##
## A mission finishes on the wall clock, so nothing in the model fires as one
## counts down. The card animates its own bar from _process for exactly that
## reason: every polling scheme that was tried instead - a game tick, a one-second
## timer - showed up on screen as the bar stepping at that interval.
##
## Driven by moving an injected clock rather than by waiting, and restored in
## after_test: MissionSystem.now_provider is on the live App autoload that every
## later suite shares.

const CARD := "res://view/ruins/sc_slot_card.tscn"
const MISSION := &"sift_rubble"
const FARM := &"farm_pick_the_middens"
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
	App.ruins_data.load_from_save({})

	_card = (load(CARD) as PackedScene).instantiate()
	add_child(_card)
	_card.bind(App.mission_slot_vm(0, false))
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

func _start_farm(duration: float) -> int:
	return App.ruins_data.add(FARM, &"test_creature", _now, duration, [], true)

## Rebinds the card to a farm plot instead of an expedition slot.
func _rebind_to_farm() -> void:
	remove_child(_card)
	_card.free()
	_card = (load(CARD) as PackedScene).instantiate()
	add_child(_card)
	_card.bind(App.mission_slot_vm(0, true))

# ─── The bar ─────────────────────────────────────────────────────────────────

func test_the_bar_reads_zero_to_one_rather_than_a_percentage() -> void:
	# A 0..100 range with the default step of 1 quantises to whole percent, which
	# is the other half of why the bar used to move in visible jumps.
	assert_float(_card.bar_progress.max_value).is_equal_approx(1.0, EPS)
	assert_float(_card.bar_progress.step).is_equal_approx(0.0, EPS)

func test_an_unfilled_card_stays_out_of_the_frame_loop() -> void:
	assert_bool(_card.is_processing()).override_failure_message(
		"An unfilled slot card is still processing every frame.").is_false()
	assert_bool(_card.bar_progress.visible).is_false()

func test_a_filled_slot_puts_the_card_into_the_frame_loop() -> void:
	_send(100.0)
	await get_tree().process_frame
	assert_bool(_card.is_processing()).is_true()
	assert_bool(_card.bar_progress.visible).is_true()

## The point of the whole arrangement: a fraction of a second of wall clock moves
## the bar, with no notification sent and no whole second elapsed.
func test_the_bar_moves_on_a_part_second_with_no_notification() -> void:
	_send(100.0)
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
	await get_tree().process_frame
	for elapsed: float in [10.0, 33.3, 50.0, 99.9]:
		_now = sent_at + elapsed
		await get_tree().process_frame
		assert_float(_card.bar_progress.value).override_failure_message(
			"At %.1fs of 100s the bar read %f." % [elapsed, _card.bar_progress.value]) \
			.is_equal_approx(elapsed / 100.0, EPS)

func test_the_bar_stops_at_one_rather_than_running_past_it() -> void:
	_send(100.0)
	await get_tree().process_frame
	_now += 500.0
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).is_equal_approx(1.0, EPS)

# ─── The label and the button ────────────────────────────────────────────────

## The label only ever renders whole seconds, so it is deliberately *not* rewritten
## every frame - only the bar is.
func test_the_countdown_label_is_left_alone_within_one_second() -> void:
	_send(100.0)
	await get_tree().process_frame
	var before: String = _card.lbl_countdown.text
	_now += 0.25
	await get_tree().process_frame
	assert_str(_card.lbl_countdown.text).is_equal(before)

func test_the_countdown_label_follows_the_clock_across_a_second() -> void:
	_send(100.0)
	await get_tree().process_frame
	var before: String = _card.lbl_countdown.text
	_now += 5.0
	await get_tree().process_frame
	assert_str(_card.lbl_countdown.text).is_not_equal(before)

## The frame the errand lands is the frame Collect has to come alive - not the
## next poll, up to a second later.
func test_the_collect_button_arms_on_the_frame_the_mission_lands() -> void:
	_send(100.0)
	await get_tree().process_frame
	assert_bool(_card.btn_action.disabled).is_true()

	_now += 100.0
	await get_tree().process_frame

	assert_bool(_card.btn_action.disabled).override_failure_message(
		"Collect was still disabled on the frame the mission finished.").is_false()
	assert_str(_card.btn_action.text).is_equal("Collect")
	assert_str(_card.lbl_countdown.text).is_equal("Ready")

# ─── A free plot ─────────────────────────────────────────────────────────────

## The way into the chooser, so it is live with nothing in the plot - the one
## button on this card that is enabled while it holds nothing.
##
## A free plot is a farm thing: the expeditions are uncapped, so they have no
## reserved places to leave empty and their way in is the panel's own button.
func test_a_free_plot_offers_a_live_way_in() -> void:
	_rebind_to_farm()
	await get_tree().process_frame
	assert_str(_card.btn_action.text).is_equal("Assign +")
	assert_bool(_card.btn_action.disabled).is_false()
	assert_str(_card.lbl_name.text).is_equal("Free plot")

func test_a_free_plot_asks_the_panel_to_open_the_chooser() -> void:
	_rebind_to_farm()
	await get_tree().process_frame
	var asked: Array[bool] = []
	_card.fill_requested.connect(func(is_farm: bool) -> void: asked.append(is_farm))
	_card.btn_action.pressed.emit()
	assert_int(asked.size()).is_equal(1)
	assert_bool(asked[0]).is_true()

# ─── A farm ──────────────────────────────────────────────────────────────────

func test_a_farm_slot_can_always_be_stopped() -> void:
	_rebind_to_farm()
	_start_farm(100.0)
	await get_tree().process_frame
	assert_str(_card.btn_action.text).is_equal("Stop")
	assert_bool(_card.btn_action.disabled).is_false()

## A farm has no finish to wait for, so its bar wraps rather than filling and
## stopping - which is what makes it read as something that keeps going.
func test_a_farm_bar_wraps_through_each_cycle() -> void:
	_rebind_to_farm()
	var started_at := _now
	_start_farm(100.0)
	await get_tree().process_frame

	_now = started_at + 50.0
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).is_equal_approx(0.5, EPS)

	_now = started_at + 150.0
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).override_failure_message(
		"A farm bar filled and stayed full instead of starting its next cycle.") \
		.is_equal_approx(0.5, EPS)
