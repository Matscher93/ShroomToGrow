extends GdUnitTestSuite
## Unit tests for PressGuard (view/base_views/gd_press_guard.gd).
##
## The guard is what stops a game tick from freeing or reflowing the button a
## finger is already down on, so what matters here is the timing: nothing runs
## while the pointer is held, everything queued runs once when it comes up.

var _guard: PressGuard
var _runs: int

func before_test() -> void:
	_guard = PressGuard.new()
	add_child(_guard)
	_runs = 0

func after_test() -> void:
	_release()
	remove_child(_guard)
	_guard.free()

func _count() -> void:
	_runs += 1

func _hold() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame

func _release() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	Input.parse_input_event(event)

## Nothing held is the ordinary case, and it costs nothing: the work runs where
## it always did, in the notification itself.
func test_work_runs_immediately_when_nothing_is_held() -> void:
	_guard.run_when_free(&"work", _count)
	assert_int(_runs).is_equal(1)

## The deferred flavour, for the callers whose work would free the node whose
## signal is still on the stack.
func test_deferred_work_runs_on_the_next_frame() -> void:
	_guard.run_when_free(&"work", _count, true)
	assert_int(_runs).is_zero()
	await get_tree().process_frame
	assert_int(_runs).is_equal(1)

func test_work_waits_while_the_pointer_is_held() -> void:
	await _hold()
	_guard.run_when_free(&"work", _count)
	for i in range(4):
		await get_tree().process_frame
	assert_int(_runs).override_failure_message(
		"work ran while the pointer was still down").is_zero()

func test_work_runs_once_the_pointer_comes_up() -> void:
	await _hold()
	_guard.run_when_free(&"work", _count)
	await get_tree().process_frame
	_release()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_runs).is_equal(1)

## A burst of notifications during one hold is one visible change, so it costs
## one run - which is the whole reason the queue is keyed.
func test_repeat_requests_under_one_key_collapse_to_a_single_run() -> void:
	await _hold()
	for i in range(5):
		_guard.run_when_free(&"work", _count)
	_release()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_runs).is_equal(1)

func test_different_keys_each_run() -> void:
	await _hold()
	_guard.run_when_free(&"one", _count)
	_guard.run_when_free(&"two", _count)
	_release()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_runs).is_equal(2)
