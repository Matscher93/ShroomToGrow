extends GdUnitTestSuite
## The growth overlay's scene wiring.
##
## Every @export on this panel is a hand-written NodePath into a deep tree, and a
## wrong one is null at runtime with nothing to say so until a player opens the
## sheet. The screen smoke suite proves it boots; this proves it is actually
## bound to the nodes it renders into.
##
## Reads only. Investing a point or claiming a reward would move the live App
## autoload every later suite shares.

const PANEL := "res://view/growth/sc_growth_panel.tscn"

var _panel: Control

func before_test() -> void:
	_panel = (load(PANEL) as PackedScene).instantiate()
	add_child(_panel)
	await get_tree().process_frame

func after_test() -> void:
	# Freed rather than auto_free()'d: _exit_tree() disconnects the ViewModel and
	# only runs on an actual removal.
	remove_child(_panel)
	_panel.free()

func test_every_exported_node_resolves() -> void:
	for property in ["btn_close", "lbl_level", "lbl_lp_free", "bar_level", "lbl_level_progress",
			"lbl_double_now", "bar_double", "lbl_double_hint", "vbox_lp_rows",
			"lbl_fert_balance", "vbox_fert_rows",
			"lbl_daily_streak", "lbl_daily_hint", "grid_daily",
			"lp_row_scene", "fert_row_scene", "daily_chip_scene"]:
		assert_object(_panel.get(property)).override_failure_message(
			"growth_panel.%s did not resolve." % property).is_not_null()

func test_one_row_and_one_chip_per_authored_producer() -> void:
	var expected: int = App.growth_producers.producers.size()
	assert_int(_panel.vbox_lp_rows.get_child_count()).override_failure_message(
		"Expected one LP row per producer.").is_equal(expected)
	assert_int(_panel.grid_daily.get_child_count()).override_failure_message(
		"Expected one daily chip per producer.").is_equal(expected)

func test_rows_are_bound_rather_than_left_on_their_placeholders() -> void:
	var labels: Array[String] = []
	for row in _panel.vbox_lp_rows.get_children():
		labels.append(row.lbl_label.text)
	var expected: Array[String] = []
	for producer in App.growth_producers.producers:
		expected.append(producer.currency.currency_name)
	assert_array(labels).is_equal(expected)

func test_one_row_per_authored_fertilizer_upgrade() -> void:
	assert_int(_panel.vbox_fert_rows.get_child_count()).override_failure_message(
		"Expected one row per fertilizer upgrade.").is_equal(
		App.fertilizer_upgrades.upgrades.size())

func test_fertilizer_rows_are_bound_rather_than_left_on_their_placeholders() -> void:
	var labels: Array[String] = []
	for row in _panel.vbox_fert_rows.get_children():
		labels.append(row.lbl_label.text)
	var expected: Array[String] = []
	for upgrade in App.fertilizer_upgrades.upgrades:
		expected.append(upgrade.display_name)
	assert_array(labels).is_equal(expected)

## Every authored upgrade costs more than a fresh save holds, so the buttons are
## disabled but still on screen - the sheet must not change height the moment the
## stock crosses a price.
func test_fertilizer_buttons_are_disabled_rather_than_hidden_when_unaffordable() -> void:
	for row in _panel.vbox_fert_rows.get_children():
		assert_bool(row.visible).is_true()
		assert_bool(row.btn_buy.disabled).is_equal(not App.can_buy_fertilizer(row.get("_id")))

func test_the_fertilizer_header_reads_the_live_balance() -> void:
	assert_str(_panel.lbl_fert_balance.text).is_equal(
		"%s in stock" % App.player_data.fertilizer.to_display(0))

func test_the_header_reads_the_live_level() -> void:
	assert_str(_panel.lbl_level.text).is_equal("Lv %d" % App.player_level())
	assert_str(_panel.lbl_lp_free.text).is_equal("%d LP free" % App.lp_available())

## Rows are instantiated once and re-bound afterwards, so a notification must not
## grow the list. The level notification alone arrives once a tick.
func test_a_refresh_rebinds_rather_than_rebuilds() -> void:
	var before: int = _panel.vbox_lp_rows.get_child_count()
	var fert_before: int = _panel.vbox_fert_rows.get_child_count()
	App.growth_vm.property_changed.emit(GrowthViewModel.PROP_ROWS_CHANGED)
	App.growth_vm.property_changed.emit(GrowthViewModel.PROP_LEVEL_CHANGED)
	App.growth_vm.property_changed.emit(GrowthViewModel.PROP_FERT_CHANGED)
	assert_int(_panel.vbox_lp_rows.get_child_count()).is_equal(before)
	assert_int(_panel.vbox_fert_rows.get_child_count()).is_equal(fert_before)
