extends GdUnitTestSuite
## The hero row on the expedition board: its countdown, and specifically that its
## bar is continuous.
##
## An expedition finishes on the wall clock, so nothing in the model fires as one
## counts down. The card animates its own bar from _process for exactly that
## reason: every polling scheme tried instead - a game tick, a one-second timer -
## showed up on screen as the bar stepping at that interval.
##
## Driven by moving an injected clock rather than by waiting, and restored in
## after_test: MissionSystem.now_provider is on the live App autoload that every
## later suite shares.

const CARD := "res://view/ruins/sc_hero_expedition_card.tscn"
const HERO := &"rot_grub"
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
	App.biomes_data.unlock(MissionSystem.RUINS_KEY)
	App.ruins_data.set_level(HERO, 1)

	_card = (load(CARD) as PackedScene).instantiate()
	add_child(_card)
	_card.bind(App.hero_expedition_vms[HERO])
	await get_tree().process_frame

func after_test() -> void:
	# Freed rather than auto_free()'d: _exit_tree() disconnects the ViewModel and
	# only runs on an actual removal.
	remove_child(_card)
	_card.free()
	App.mission_system.now_provider = _saved_provider
	App.ruins_data.load_from_save(_saved_ruins)

## The step this hero would run next.
func _step() -> StringName:
	return App.sendable_step(HERO)

# ─── The row ─────────────────────────────────────────────────────────────────

## A hero at home shows the step in front of it and offers to send it - there is
## nothing to pick, so the button is the whole interface.
func test_a_hero_at_home_offers_its_next_step() -> void:
	assert_str(_card.btn_action.text).is_equal("Send")
	assert_bool(_card.btn_action.disabled).is_false()
	assert_str(_card.lbl_step.text).is_equal(App.mission_def(_step()).display_name)
	assert_str(_card.lbl_chain.text).is_equal("Chain 0 / 20")

func test_an_idle_hero_stays_out_of_the_frame_loop() -> void:
	assert_bool(_card.is_processing()).override_failure_message(
		"An idle hero card is still processing every frame.").is_false()
	assert_bool(_card.bar_progress.visible).is_false()

func test_sending_puts_the_card_into_the_frame_loop() -> void:
	_card.btn_action.pressed.emit()
	await get_tree().process_frame
	assert_bool(_card.is_processing()).is_true()
	assert_bool(_card.bar_progress.visible).is_true()
	assert_str(_card.btn_action.text).is_equal("Collect")

# ─── The bar ─────────────────────────────────────────────────────────────────

func test_the_bar_reads_zero_to_one_rather_than_a_percentage() -> void:
	# A 0..100 range with the default step of 1 quantises to whole percent, which
	# is the other half of why a bar moves in visible jumps.
	assert_float(_card.bar_progress.max_value).is_equal_approx(1.0, EPS)
	assert_float(_card.bar_progress.step).is_equal_approx(0.0, EPS)

## The point of the whole arrangement: a fraction of a second of wall clock moves
## the bar, with no notification sent and no whole second elapsed.
func test_the_bar_moves_on_a_part_second_with_no_notification() -> void:
	var duration := App.mission_duration(_step(), HERO)
	_card.btn_action.pressed.emit()
	await get_tree().process_frame
	var before: float = _card.bar_progress.value

	_now += duration * 0.25
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).override_failure_message(
		"The bar did not move across a quarter of the errand.").is_greater(before)
	assert_float(_card.bar_progress.value).is_equal_approx(0.25, EPS)

func test_the_bar_stops_at_one_rather_than_running_past_it() -> void:
	_card.btn_action.pressed.emit()
	await get_tree().process_frame
	_now += 100000.0
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).is_equal_approx(1.0, EPS)

# ─── The button ──────────────────────────────────────────────────────────────

## The frame the expedition lands is the frame Collect has to come alive - not
## the next poll, up to a second later.
func test_collect_arms_on_the_frame_the_expedition_lands() -> void:
	var duration := App.mission_duration(_step(), HERO)
	_card.btn_action.pressed.emit()
	await get_tree().process_frame
	assert_bool(_card.btn_action.disabled).is_true()

	_now += duration
	await get_tree().process_frame
	assert_bool(_card.btn_action.disabled).override_failure_message(
		"Collect was still disabled on the frame the expedition finished.").is_false()
	assert_str(_card.lbl_countdown.text).is_equal("Ready")

## Collecting walks the chain on, and the row moves to the next step with no
## rebuild and nothing for the player to pick.
func test_collecting_advances_the_row_to_the_next_step() -> void:
	var first := _step()
	var duration := App.mission_duration(first, HERO)
	_card.btn_action.pressed.emit()
	await get_tree().process_frame
	_now += duration
	await get_tree().process_frame
	_card.btn_action.pressed.emit()
	await get_tree().process_frame

	assert_str(_card.lbl_chain.text).is_equal("Chain 1 / 20")
	assert_str(_card.btn_action.text).is_equal("Send")
	assert_str(_card.lbl_step.text).is_not_equal(App.mission_def(first).display_name)

## A step behind a level gate says which level it wants rather than only going
## dark - the two want opposite things from the player.
func test_a_gated_step_says_what_it_is_waiting_for() -> void:
	# Walk to the gate at step 6, which asks for level 2.
	for i in range(5):
		var step := App.sendable_step(HERO)
		assert_str(String(step)).is_not_empty()
		App.send_mission(step, HERO)
		_now += App.mission_duration(step, HERO) + 1.0
		App.collect_mission(int(App.ruins_data.find_by_hero(HERO)["instance_id"]))
	await get_tree().process_frame

	assert_bool(_card.btn_action.disabled).is_true()
	assert_str(_card.lbl_status.text).contains("level 2")
	App.ruins_data.set_level(HERO, 2)
	await get_tree().process_frame
	assert_bool(_card.btn_action.disabled).is_false()
