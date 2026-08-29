extends GdUnitTestSuite
## The farm row and its stepper - the whole of the farm interface now that there
## are no plots to fill and no sheet to fill them from.
##
## What the stepper means at its ends is the point: from zero it starts the farm,
## and stepping the last worker off stops it. Driven by moving an injected clock
## rather than by waiting, and restored in after_test.

const CARD := "res://view/ruins/sc_farm_card.tscn"
const FARM := &"farm_pick_the_middens"
const OPENER := &"sift_rubble"
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
	# The expedition that opens this farm, and somebody to work it.
	App.ruins_data.mark_expedition_done(OPENER)
	App.ruins_data.workers_owned = 4

	_card = (load(CARD) as PackedScene).instantiate()
	add_child(_card)
	_card.bind(App.farm_vms[FARM])
	await get_tree().process_frame

func after_test() -> void:
	remove_child(_card)
	_card.free()
	App.mission_system.now_provider = _saved_provider
	App.ruins_data.load_from_save(_saved_ruins)

# ─── The stepper ─────────────────────────────────────────────────────────────

## A farm nobody is on is a row at zero workers, not a plot standing empty.
func test_an_unworked_farm_reads_as_zero_workers() -> void:
	assert_str(_card.lbl_workers.text).is_equal("0 / 1 workers")
	assert_bool(_card.btn_fewer.disabled).is_true()
	assert_bool(_card.btn_more.disabled).is_false()
	assert_bool(_card.bar_progress.visible).is_false()
	assert_bool(_card.is_processing()).is_false()

## Stepping up from zero is the only way a farm is ever started.
func test_stepping_up_from_zero_starts_the_farm() -> void:
	_card.btn_more.pressed.emit()
	await get_tree().process_frame
	assert_int(App.farm_slots_used()).is_equal(1)
	assert_str(_card.lbl_workers.text).is_equal("1 / 1 workers")
	assert_bool(_card.bar_progress.visible).is_true()
	assert_bool(_card.is_processing()).is_true()

## And stepping the last worker off stops it again, rather than leaving an empty
## farm holding a plot.
func test_stepping_the_last_worker_off_stops_the_farm() -> void:
	_card.btn_more.pressed.emit()
	await get_tree().process_frame
	_card.btn_fewer.pressed.emit()
	await get_tree().process_frame
	assert_int(App.farm_slots_used()).is_zero()
	assert_str(_card.lbl_workers.text).is_equal("0 / 1 workers")
	assert_int(App.workers_idle()).is_equal(4)

## One worker per farm until an upgrade says otherwise, and the + goes dark at
## the ceiling rather than refusing itself when pressed.
func test_the_stepper_stops_at_the_farms_ceiling() -> void:
	_card.btn_more.pressed.emit()
	await get_tree().process_frame
	assert_bool(_card.btn_more.disabled).is_true()

func test_the_stepper_stops_when_no_worker_is_free() -> void:
	App.ruins_data.workers_owned = 0
	await get_tree().process_frame
	assert_bool(_card.btn_more.disabled).is_true()
	assert_str(_card.lbl_status.text).is_equal("No worker is free.")

# ─── The bar ─────────────────────────────────────────────────────────────────

func test_the_bar_reads_zero_to_one_rather_than_a_percentage() -> void:
	assert_float(_card.bar_progress.max_value).is_equal_approx(1.0, EPS)
	assert_float(_card.bar_progress.step).is_equal_approx(0.0, EPS)

## A farm has no finish to wait for, so its bar wraps rather than filling and
## stopping - which is what makes it read as something that keeps going.
func test_the_bar_wraps_through_each_cycle() -> void:
	_card.btn_more.pressed.emit()
	await get_tree().process_frame
	var cycle := float(App.ruins_data.find_by_mission(FARM)["duration"])
	var started_at := _now

	_now = started_at + cycle * 0.5
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).is_equal_approx(0.5, EPS)

	_now = started_at + cycle * 1.5
	await get_tree().process_frame
	assert_float(_card.bar_progress.value).override_failure_message(
		"A farm bar filled and stayed full instead of starting its next cycle.") \
		.is_equal_approx(0.5, EPS)
