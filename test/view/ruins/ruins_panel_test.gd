extends GdUnitTestSuite
## The Ruins screen builds against the live App, and the Missions tab it opens on
## is the one built out of heroes and farms.
##
## Every list on this screen is built in _ready(), so a screen that crashes on
## open crashes on the first tap of the nav row. What is asserted beyond that is
## the shape the rows take: one per hero taken over, one per farm opened, and no
## sheet in front of either.

const PANEL_SCENE := preload("res://view/ruins/sc_ruins.tscn")

var _panel: Control
var _saved_ruins: Dictionary

func before_test() -> void:
	_saved_ruins = App.ruins_data.to_save()
	App.ruins_data.load_from_save({})
	App.biomes_data.unlock(MissionSystem.RUINS_KEY)
	_panel = PANEL_SCENE.instantiate()
	add_child(_panel)
	await get_tree().process_frame

func after_test() -> void:
	remove_child(_panel)
	_panel.free()
	App.ruins_data.load_from_save(_saved_ruins)

## The expedition some farm names as the thing that opens it.
func _farm_opener() -> StringName:
	for def in App.mission_defs.missions:
		if def.is_farm and not def.requires_mission_id.is_empty():
			return def.requires_mission_id
	return &""

func _first_hero() -> StringName:
	return App.hero_defs.heroes[0].id

# ─── The boards ──────────────────────────────────────────────────────────────

## One row per hero taken over - not per place, and not per mission. Nothing is
## drawn for a hero the player has not got, and the hint says so in its place.
func test_the_expedition_board_draws_one_row_per_recruited_hero() -> void:
	assert_int(_panel.vbox_expeditions.get_child_count()).is_zero()
	assert_bool(_panel.lbl_expeditions_hint.visible).is_true()

	App.ruins_data.set_level(_first_hero(), 1)
	await get_tree().process_frame
	assert_int(_panel.vbox_expeditions.get_child_count()).is_equal(1)
	assert_bool(_panel.lbl_expeditions_hint.visible).is_false()

## One row per farm opened, running or not - so a farm arrives on screen the
## moment the expedition that opens it comes home, with nothing to assign it to.
func test_a_farm_arrives_when_its_expedition_opens_it() -> void:
	assert_int(_panel.vbox_farms.get_child_count()).is_zero()
	assert_bool(_panel.section_farms.visible).is_false()

	App.ruins_data.mark_expedition_done(_farm_opener())
	await get_tree().process_frame
	assert_int(_panel.vbox_farms.get_child_count()).is_greater(0)
	assert_bool(_panel.section_farms.visible).is_true()

## Sending repaints the row in place: how many rows there are is what a recruit
## changes, not what a press changes.
func test_sending_does_not_rebuild_the_expedition_rows() -> void:
	var hero := _first_hero()
	App.ruins_data.set_level(hero, 1)
	await get_tree().process_frame
	var row: Node = _panel.vbox_expeditions.get_child(0)

	App.send_mission(App.sendable_step(hero), hero)
	await get_tree().process_frame
	assert_int(_panel.vbox_expeditions.get_child_count()).is_equal(1)
	assert_object(_panel.vbox_expeditions.get_child(0)).is_same(row)
	assert_str(_panel.lbl_board.text).contains("1 of 1 heroes out")

## The chain positions of every hero taken over, over the board.
func test_the_header_names_where_each_chain_stands() -> void:
	App.ruins_data.set_level(_first_hero(), 1)
	await get_tree().process_frame
	assert_str(App.ruins_vm.chain_progress_text).contains("0/20")

# ─── Workers ─────────────────────────────────────────────────────────────────

## The workers arrive with the farms: there is nothing to put one on before the
## first farm opens, so hiring one would be money into a hole.
func test_the_workers_section_is_hidden_until_a_farm_is_open() -> void:
	assert_bool(_panel.section_workers.visible).is_false()
	App.ruins_data.mark_expedition_done(_farm_opener())
	await get_tree().process_frame
	assert_bool(_panel.section_workers.visible).is_true()

## A worker is priced in all three currencies at once, and the button says so
## rather than making the player find out by pressing it.
func test_the_hire_button_carries_the_whole_price() -> void:
	App.ruins_data.mark_expedition_done(_farm_opener())
	await get_tree().process_frame
	for field in ["relics", "ichor", "glyphs"]:
		assert_str(_panel.btn_hire_worker.text) \
			.override_failure_message("The hire button does not name %s." % field) \
			.contains(field)

func test_the_pool_line_follows_a_hire() -> void:
	App.ruins_data.mark_expedition_done(_farm_opener())
	await get_tree().process_frame
	assert_str(_panel.lbl_worker_pool.text).is_equal("0 idle / 0 hired")
	App.ruins_data.workers_owned = 3
	await get_tree().process_frame
	assert_str(_panel.lbl_worker_pool.text).is_equal("3 idle / 3 hired")

## Collecting from a hero's row rebuilds the board, and the rebuild frees the very
## card whose `pressed` handler is still running. Without a deferral that card is
## gone by the time the handler returns to repaint itself.
func test_collecting_from_a_row_does_not_free_the_card_under_the_press() -> void:
	var hero := _first_hero()
	App.ruins_data.set_level(hero, 1)
	await get_tree().process_frame

	var step := App.sendable_step(hero)
	App.send_mission(step, hero)
	# Land it: the clock is the live one here, so the entry is walked back rather
	# than waited out.
	App.ruins_data.find_by_hero(hero)["started_at"] -= 100000.0
	await get_tree().process_frame

	var row: Node = _panel.vbox_expeditions.get_child(0)
	row.btn_action.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_bool(App.is_mission_completed(step)).is_true()
	assert_int(_panel.vbox_expeditions.get_child_count()).is_equal(1)
	assert_str(_panel.vbox_expeditions.get_child(0).lbl_chain.text).is_equal("Chain 1 / 20")
