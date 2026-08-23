extends GdUnitTestSuite
## A tap on the nav must survive a game tick landing between press and release.
##
## The tick is what makes this a real failure rather than a theoretical one: an
## automation buying Biome Size invalidates the prestige track once a tick, which
## reaches the nav as upgrades_changed. The nav used to respawn every chip on it,
## so the Button that captured the press was gone by the time the finger came up
## and the tap did nothing. Guarded by PressGuard now, with the rebuild itself
## skipped when the rows did not actually move.
##
## The bar is hosted in a SubViewport because the test runner's root viewport is
## 64x64 - a chip 220px along the row is outside it, and a press aimed there hits
## nothing at all.

const SUB_BAR_SCENE := preload("res://view/navigation/sc_nav_sub_bar.tscn")
const VIEWPORT_SIZE := Vector2i(700, 200)

var _viewport: SubViewport
var _bar: Control
var _screen_before: ScreenTypes.Types
var _tab_before: int
## Written by the chip's own signal. A suite member rather than a local, because
## a GDScript lambda captures locals by value - assigning one inside the handler
## never reaches the assertion.
var _asked_for: int

func before_test() -> void:
	_asked_for = -1
	_screen_before = App.screens_data.current_screen
	_tab_before = App.crystal_caves_vm.current_tab
	App.screens_data.select(ScreenTypes.Types.CRYSTAL_CAVES, 0)

	_viewport = SubViewport.new()
	_viewport.size = VIEWPORT_SIZE
	add_child(_viewport)
	_bar = SUB_BAR_SCENE.instantiate()
	_viewport.add_child(_bar)
	await get_tree().process_frame
	await get_tree().process_frame

func after_test() -> void:
	_release()
	remove_child(_viewport)
	_viewport.free()
	App.crystal_caves_vm.current_tab = _tab_before
	App.screens_data.current_screen = _screen_before

## The chips only, never the PressGuard the bar also parents.
func _chips() -> Array[Control]:
	var out: Array[Control] = []
	for child in _bar.get_children():
		var chip := child as PanelContainer
		if chip:
			out.append(chip)
	return out

## Fed to both: Input carries the held state PressGuard reads, the viewport
## carries the hit test.
func _press(at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	_viewport.push_input(event)
	await get_tree().process_frame

func _release(at: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	if is_instance_valid(_viewport):
		_viewport.push_input(event)

## The exact signal a tick fires: Biome Size bought -> prestige track invalidated
## -> upgrades_changed, with no level anywhere having moved.
func _tick_notification() -> void:
	App.prestige_upgrade_system.notify_changed()

func test_the_screen_has_chips_to_press() -> void:
	assert_array(_chips()).override_failure_message(
		"the Caves screen authors three sub-views, so the bar cannot be empty"
		).is_not_empty()

## The failure that started this: the chip was freed mid-press and the release
## landed on nothing.
func test_a_chip_is_not_freed_by_a_tick_landing_mid_press() -> void:
	var chips := _chips()
	if chips.is_empty():
		return
	var chip := chips[chips.size() - 1]
	await _press(chip.get_global_rect().get_center())
	_tick_notification()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(chip)).override_failure_message(
		"a tick during the press freed the chip out from under the finger").is_true()
	_release()

## A tick changes no nav row, so the rebuild is skipped outright and the chips on
## screen are the same nodes afterwards - press or no press.
func test_a_notification_that_changed_nothing_keeps_the_same_chips() -> void:
	var before: Array[int] = []
	for chip in _chips():
		before.append(chip.get_instance_id())
	if before.is_empty():
		return

	_tick_notification()
	await get_tree().process_frame
	await get_tree().process_frame

	var after: Array[int] = []
	for chip in _chips():
		after.append(chip.get_instance_id())
	assert_array(after).override_failure_message(
		"the chips were respawned for a change that did not touch them").is_equal(before)

## End to end: press, tick, release - and the tab still switches.
func test_a_tap_across_a_tick_still_navigates() -> void:
	var chips := _chips()
	if chips.size() < 2:
		return
	var chip := chips[chips.size() - 1]
	# Which tab this chip leads to is the chip's own business - read it off the
	# press rather than assuming the row order matches the tab order, which it
	# does not while the Boosts tab is hidden.
	chip.selected.connect(_on_chip_selected)

	var at := chip.get_global_rect().get_center()
	await _press(at)
	_tick_notification()
	await get_tree().process_frame
	_release(at)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_int(_asked_for).override_failure_message(
		"the tap was swallowed by the tick - the chip never fired").is_greater_equal(0)
	assert_int(App.crystal_caves_vm.current_tab).is_equal(_asked_for)

func _on_chip_selected(_screen_type: int, tab_index: int) -> void:
	_asked_for = tab_index
