extends GdUnitTestSuite
## The Ruins screen builds against the live App, and the Missions tab it opens on
## is the one that was rebuilt around slots.
##
## Every list on this screen is built in _ready(), so a screen that crashes on
## open crashes on the first tap of the nav row. The chooser is the exception -
## it is built only when an empty slot is pressed - which is exactly the kind of
## path that ships broken, so it is opened here through the button rather than by
## calling the method.

const PANEL_SCENE := preload("res://view/ruins/sc_ruins.tscn")

var _panel: Control
var _saved_ruins: Dictionary

func before_test() -> void:
	_saved_ruins = App.ruins_data.to_save()
	App.ruins_data.load_from_save({})
	_panel = PANEL_SCENE.instantiate()
	add_child(_panel)
	await get_tree().process_frame

func after_test() -> void:
	remove_child(_panel)
	_panel.free()
	App.ruins_data.load_from_save(_saved_ruins)

## Takes over every creature the roster offers, so there is somebody to send.
func _recruit() -> void:
	App.biomes_data.unlock(MissionSystem.RUINS_KEY)
	for def in App.creature_defs.creatures:
		App.ruins_data.set_rank(def.id, 5)

func _first_sendable() -> StringName:
	for def in App.mission_defs.missions:
		if not def.is_farm and App.is_mission_unlocked(def.id):
			return def.id
	return &""

## The expedition some farm names as the thing that opens it.
func _farm_opener() -> StringName:
	for def in App.mission_defs.missions:
		if def.is_farm and not def.requires_mission_id.is_empty():
			return def.requires_mission_id
	return &""

## Presses go through the guard, which defers a rebuild by a frame.
func _press(button: Button) -> void:
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

# ─── The boards ──────────────────────────────────────────────────────────────

## One card per expedition actually out, and no reserved places: with nothing out
## the list is empty and the Send button under it is the whole of the section.
func test_the_expedition_list_is_empty_with_nothing_out() -> void:
	assert_int(_panel.vbox_expeditions.get_child_count()).is_zero()
	assert_bool(_panel.btn_send_expedition.visible).is_true()

## Nothing is recruited on a cleared board, so there is nobody to send and the
## button says which half is missing.
func test_the_send_button_is_dark_with_nobody_to_send() -> void:
	assert_bool(_panel.btn_send_expedition.disabled).is_true()
	assert_str(_panel.lbl_send_hint.text).is_equal("Every creature is busy.")

func test_the_farm_board_draws_one_card_per_plot() -> void:
	assert_int(_panel.vbox_farms.get_child_count()).is_equal(App.farm_slots())

## Before the first expedition that opens one is finished there is nothing to put
## in a plot, and a section headed FARMS is a promise the player cannot act on.
func test_the_farms_section_is_hidden_until_a_farm_is_open() -> void:
	assert_bool(_panel.section_farms.visible).is_equal(App.ruins_vm.farms_visible)

## The list is exactly as long as the number out, so it has to follow a send and
## a collect - not only the moment the screen was opened.
func test_the_expedition_list_follows_the_board() -> void:
	_recruit()
	var mission := _first_sendable()
	assert_int(App.send_mission(mission, App.best_creature_for_mission(mission))).is_greater(0)
	await get_tree().process_frame
	assert_int(_panel.vbox_expeditions.get_child_count()).override_failure_message(
		"Sending an expedition did not add a card.").is_equal(1)

	var entry := App.active_mission(mission)
	App.ruins_data.remove(int(entry["instance_id"]))
	await get_tree().process_frame
	assert_int(_panel.vbox_expeditions.get_child_count()).override_failure_message(
		"Clearing the board did not remove the card.").is_zero()

## Sending is what makes the board non-empty, so the header has to move with it.
func test_the_header_follows_the_board() -> void:
	_recruit()
	var mission := _first_sendable()
	App.send_mission(mission, App.best_creature_for_mission(mission))
	await get_tree().process_frame
	assert_str(_panel.lbl_board.text).contains("1 out")

## Finishing an expedition can open a farm, which brings a whole section on
## screen - the other half of what the board notifications have to reach.
func test_the_farms_section_arrives_when_an_expedition_opens_one() -> void:
	assert_bool(_panel.section_farms.visible).is_false()
	App.ruins_data.mark_expedition_done(_farm_opener())
	await get_tree().process_frame
	assert_bool(_panel.section_farms.visible).override_failure_message(
		"Opening a farm did not bring the FARMS section on screen.").is_true()

# ─── The ledger ──────────────────────────────────────────────────────────────

## Folded shut on arrival: it is what to work towards, not what to do now.
func test_the_ledger_starts_folded_shut() -> void:
	assert_bool(_panel.vbox_ledger.visible).is_false()
	assert_str(_panel.btn_ledger.text).contains("expedition")

func test_pressing_the_ledger_folds_it_open_and_shut() -> void:
	await _press(_panel.btn_ledger)
	assert_bool(_panel.vbox_ledger.visible).is_true()
	assert_int(_panel.vbox_ledger.get_child_count()).is_greater(0)
	await _press(_panel.btn_ledger)
	assert_bool(_panel.vbox_ledger.visible).is_false()

## Every expedition is ahead of a board that has run none, so the ledger lists
## them all and the count says so.
func test_the_ledger_lists_every_expedition_still_ahead() -> void:
	await _press(_panel.btn_ledger)
	assert_int(_panel.vbox_ledger.get_child_count()) \
		.is_equal(App.ruins_vm.remaining_expedition_vms.size())

# ─── The chooser ─────────────────────────────────────────────────────────────

func test_the_send_button_opens_the_chooser() -> void:
	assert_bool(_panel.chooser_layer.has_popup()).is_false()
	await _press(_panel.btn_send_expedition)
	assert_bool(_panel.chooser_layer.has_popup()).is_true()

## A free farm plot is still a place, so it opens the chooser by being tapped.
func test_a_free_farm_plot_opens_the_chooser() -> void:
	await _press(_panel.vbox_farms.get_child(0).btn_action)
	assert_bool(_panel.chooser_layer.has_popup()).is_true()
	var chooser: Node = _panel.chooser_layer.get_child(0)
	assert_str(chooser.lbl_title.text).is_equal("Assign a farm")

func test_the_chooser_offers_the_expeditions_that_can_be_sent() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	assert_str(chooser.lbl_title.text).is_equal("Send an expedition")
	assert_int(chooser.vbox_missions.get_child_count()) \
		.is_equal(App.ruins_vm.sendable_missions(false).size())

## A press on the backdrop that travels is a scroll, not a tap. Overscrolling the
## list used to carry onto the backdrop and shut the sheet under the player.
func test_dragging_across_the_backdrop_does_not_close_the_chooser() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	chooser._gui_input(_click(true, Vector2(10, 700)))
	chooser._gui_input(_motion(Vector2(10, 640)))
	chooser._gui_input(_click(false, Vector2(10, 640)))
	await get_tree().process_frame
	assert_bool(_panel.chooser_layer.has_popup()).override_failure_message(
		"A drag across the backdrop closed the chooser.").is_true()

## The touch scroller cancels a press it has turned into a scroll by pushing the
## pointer far outside every control. The backdrop still holds the grab, so that
## is the motion it sees - and it has to read as a cancelled tap.
func test_the_scrollers_press_cancel_does_not_close_the_chooser() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	chooser._gui_input(_click(true, Vector2(10, 700)))
	chooser._gui_input(_motion(Vector2(-100000, -100000)))
	chooser._gui_input(_click(false, Vector2(10, 700)))
	await get_tree().process_frame
	assert_bool(_panel.chooser_layer.has_popup()).is_true()

## A tap that stays put still closes it, which is the whole point of the backdrop.
func test_tapping_the_backdrop_closes_the_chooser() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	chooser.dismissed.connect(_panel.chooser_layer.clear, CONNECT_ONE_SHOT)
	chooser._gui_input(_click(true, Vector2(10, 700)))
	chooser._gui_input(_click(false, Vector2(12, 702)))
	await get_tree().process_frame
	assert_bool(_panel.chooser_layer.has_popup()).is_false()

## Closing on the press meant the sheet was gone before the player had finished
## the gesture, so nothing else could reinterpret it.
func test_the_backdrop_does_not_close_on_the_press_alone() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	chooser._gui_input(_click(true, Vector2(10, 700)))
	await get_tree().process_frame
	assert_bool(_panel.chooser_layer.has_popup()).is_true()

func _click(pressed: bool, at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	return event

func _motion(to: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = to
	return event

func test_closing_the_chooser_clears_the_layer() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	await _press(chooser.btn_close)
	assert_bool(_panel.chooser_layer.has_popup()).is_false()
