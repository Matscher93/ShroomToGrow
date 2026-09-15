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
			"lbl_daily_streak", "lbl_daily_hint", "grid_daily",
			"lbl_track_progress", "lbl_track_hint", "grid_track",
			"lp_row_scene", "daily_chip_scene", "track_slot_scene"]:
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

## The step button's label is the count that press would actually spend, so it
## has to be bound rather than left on the scene's authored "+10".
func test_every_lp_row_labels_its_step_button() -> void:
	var producers := App.growth_producers.producers
	for i in range(producers.size()):
		var row: Node = _panel.vbox_lp_rows.get_child(i)
		var currency: CurrencyTypes.Types = producers[i].currency.currency_type
		var step := App.lp_step_size(currency)
		var expected := "+%d" % (step if step > 0 else App.lp_points_to_next_double())
		assert_str(row.btn_invest_step.text).override_failure_message(
			"LP row %d's step button is not bound to the live step size." % i
			).is_equal(expected)

## One slot per authored day, in one grid the sheet lays out as two rows of seven.
func test_one_slot_per_authored_track_day() -> void:
	assert_int(_panel.grid_track.get_child_count()).override_failure_message(
		"Expected one slot per authored track day.").is_equal(App.daily_track_count())

func test_the_track_slots_are_bound_rather_than_left_on_their_placeholders() -> void:
	var days: Array[String] = []
	for slot in _panel.grid_track.get_children():
		days.append(slot.lbl_day.text)
	var expected: Array[String] = []
	for day in range(1, App.daily_track_count() + 1):
		expected.append("D%d" % day)
	assert_array(days).is_equal(expected)

## Only the day the track is sitting on is pressable - the rest are a record, and
## a live button on a day the player cannot claim would do nothing when tapped.
func test_only_todays_slot_is_pressable() -> void:
	var pending: int = App.daily_track_pending_day()
	for slot in _panel.grid_track.get_children():
		var day := int(slot.lbl_day.text.substr(1))
		assert_bool(slot.btn_claim.disabled).override_failure_message(
			"Track day %d should be %s (pending day is %d)." % [day,
			"pressable" if day == pending else "disabled", pending]
			).is_equal(day != pending)

func test_the_header_reads_the_live_level() -> void:
	assert_str(_panel.lbl_level.text).is_equal("Lv %d" % App.player_level())
	assert_str(_panel.lbl_lp_free.text).is_equal("%d LP free" % App.lp_available())

## Rows are instantiated once and re-bound afterwards, so a notification must not
## grow the list. The level notification alone arrives once a tick.
func test_a_refresh_rebinds_rather_than_rebuilds() -> void:
	var before: int = _panel.vbox_lp_rows.get_child_count()
	App.growth_vm.property_changed.emit(GrowthViewModel.PROP_ROWS_CHANGED)
	App.growth_vm.property_changed.emit(GrowthViewModel.PROP_LEVEL_CHANGED)
	assert_int(_panel.vbox_lp_rows.get_child_count()).is_equal(before)
