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

func test_closing_the_chooser_clears_the_layer() -> void:
	await _press(_panel.btn_send_expedition)
	var chooser: Node = _panel.chooser_layer.get_child(0)
	await _press(chooser.btn_close)
	assert_bool(_panel.chooser_layer.has_popup()).is_false()
