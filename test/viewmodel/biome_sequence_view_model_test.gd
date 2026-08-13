extends GdUnitTestSuite
## Recording rules and pagination for BiomeSequenceViewModel
## (viewmodel/gd_biome_sequence_view_model.gd).
##
## This VM carries the only non-trivial logic in the ViewModel layer: how many
## steps a slot press records, when a slot refuses one, and which page an edit
## leaves the player on. All three are arithmetic over authored gates and caps
## rather than a straight read-through, so all three can be wrong while every
## model test still passes.
##
## Driven through the live App autoload, because that is what the VM reads. The
## sequence it edits is real game state, so after_test() puts it back.

var _def: BiomeDef
var _vm: BiomeSequenceViewModel

func before_test() -> void:
	_def = App.biomes.biomes[0]
	_vm = BiomeSequenceViewModel.new(_def.key, _def)
	App.automation_data.clear_sequence(_def.key)

func after_test() -> void:
	App.automation_data.clear_sequence(_def.key)
	_vm.dispose()
	_vm = null

## The first upgrade in grid order that is gated at zero points, i.e. the one a
## fresh sequence can always start with.
func _ungated_id() -> StringName:
	for id in _def.upgrade_ids:
		var def := App.biome_upgrade_system.def(id)
		if def != null and def.min_biome_points_spent <= 0:
			return id
	return &""

# ─── Recording ───────────────────────────────────────────────────────────────

func test_a_fresh_sequence_is_empty() -> void:
	assert_int(_vm.step_count).is_equal(0)
	assert_array(_vm.sequence_rows()).is_empty()

func test_appending_records_the_chosen_amount() -> void:
	var id := _ungated_id()
	assert_str(String(id)).override_failure_message(
		"biome '%s' authors no upgrade gated at 0 points" % _def.key).is_not_empty()

	assert_int(_vm.append_step(id)).is_equal(1)   # step_amount starts at x1
	assert_int(_vm.step_count).is_equal(1)
	assert_int(_vm.recorded_count(id)).is_equal(1)

func test_cycling_the_amount_changes_how_many_a_press_records() -> void:
	var id := _ungated_id()
	_vm.cycle_step_amount()                       # x1 -> x5
	assert_int(_vm.step_amount).is_equal(5)
	assert_int(_vm.append_step(id)).is_equal(5)
	assert_int(_vm.step_count).is_equal(5)

func test_the_amount_cycle_wraps_back_round() -> void:
	var seen: Array[int] = []
	for i in range(BiomeSequenceViewModel.STEP_AMOUNTS.size()):
		seen.append(_vm.step_amount)
		_vm.cycle_step_amount()
	assert_array(seen).is_equal(BiomeSequenceViewModel.STEP_AMOUNTS)
	assert_int(_vm.step_amount).is_equal(BiomeSequenceViewModel.STEP_AMOUNTS[0])

## "Fill" takes the upgrade to its remaining cap rather than a fixed count.
func test_fill_takes_the_upgrade_to_its_cap() -> void:
	var id := _ungated_id()
	var def := App.biome_upgrade_system.def(id)
	if def == null or def.max_level <= 0:
		return   # uncapped upgrade, nothing to fill - covered by the next test

	while _vm.step_amount > 0:
		_vm.cycle_step_amount()
	assert_int(_vm.append_step(id)).is_equal(def.max_level)
	assert_int(_vm.recorded_count(id)).is_equal(def.max_level)

## An amount above what is left is clipped to the cap, not recorded past it.
func test_recording_stops_at_the_cap() -> void:
	var id := _ungated_id()
	var def := App.biome_upgrade_system.def(id)
	if def == null or def.max_level <= 0:
		return

	for i in range(def.max_level):
		_vm.append_step(id)
	assert_int(_vm.recorded_count(id)).is_equal(def.max_level)
	assert_int(_vm.steps_to_append(id)).is_equal(0)
	assert_bool(_vm.can_record(id)).is_false()
	assert_str(_vm.record_blocked_reason(id)).contains("cap")
	assert_int(_vm.append_step(id)).is_equal(0)
	assert_int(_vm.recorded_count(id)).is_equal(def.max_level)

## Gating is simulated off the sequence, not the current run: a step whose gate
## sits above the steps recorded before it could never be bought when its turn
## came, so it cannot be appended there.
func test_a_gated_upgrade_is_blocked_until_enough_steps_precede_it() -> void:
	var gated := &""
	var gate := 0
	for id in _def.upgrade_ids:
		var def := App.biome_upgrade_system.def(id)
		if def != null and def.min_biome_points_spent > 0:
			gated = id
			gate = def.min_biome_points_spent
			break
	if gated.is_empty():
		return   # this biome gates nothing

	assert_bool(_vm.can_record(gated)).is_false()
	assert_str(_vm.record_blocked_reason(gated)).contains("Unlocks after")

	var filler := _ungated_id()
	for i in range(gate):
		_vm.append_step(filler)

	assert_int(_vm.step_count).is_greater_equal(gate)
	assert_bool(_vm.can_record(gated)).is_true()
	assert_str(_vm.record_blocked_reason(gated)).is_empty()

# ─── Rows ────────────────────────────────────────────────────────────────────

func test_rows_carry_their_absolute_index() -> void:
	var id := _ungated_id()
	_vm.cycle_step_amount()          # x5
	_vm.append_step(id)
	var rows := _vm.sequence_rows()
	assert_array(rows).has_size(5)
	for i in range(rows.size()):
		assert_int(rows[i].index).is_equal(i)
		assert_str(String(rows[i].id)).is_equal(String(id))

func test_removing_the_last_step_shortens_the_sequence() -> void:
	var id := _ungated_id()
	_vm.cycle_step_amount()          # x5
	_vm.append_step(id)
	assert_bool(_vm.remove_last()).is_true()
	assert_int(_vm.step_count).is_equal(4)

func test_removing_from_an_empty_sequence_is_refused() -> void:
	assert_bool(_vm.remove_last()).is_false()
	assert_int(_vm.step_count).is_zero()

# ─── Pagination ──────────────────────────────────────────────────────────────

func test_a_short_sequence_carries_no_page_controls() -> void:
	_vm.append_step(_ungated_id())
	assert_int(_vm.page_count).is_equal(1)
	assert_bool(_vm.has_pages).is_false()
	assert_bool(_vm.can_page_back).is_false()
	assert_bool(_vm.can_page_forward).is_false()

func test_an_empty_sequence_still_reports_one_page() -> void:
	assert_int(_vm.page_count).is_equal(1)
	assert_str(_vm.page_text).is_equal("1 / 1")

func test_pages_split_at_page_size() -> void:
	var total := _fill_past_one_page()
	var expected_pages := ceili(float(total) / float(BiomeSequenceViewModel.PAGE_SIZE))
	assert_int(_vm.page_count).is_equal(expected_pages)
	assert_bool(_vm.has_pages).is_true()

## Appending follows the new step onto its page, so a tap is never invisible.
func test_appending_reveals_the_page_the_step_landed_on() -> void:
	_fill_past_one_page()
	assert_int(_vm.page).is_equal(_vm.page_count - 1)

func test_paging_clamps_at_both_ends() -> void:
	_fill_past_one_page()
	for i in range(10):
		_vm.page_back()
	assert_int(_vm.page).is_equal(0)
	assert_bool(_vm.can_page_back).is_false()

	for i in range(10):
		_vm.page_forward()
	assert_int(_vm.page).is_equal(_vm.page_count - 1)
	assert_bool(_vm.can_page_forward).is_false()

func test_a_page_holds_at_most_page_size_rows() -> void:
	_fill_past_one_page()
	for i in range(_vm.page_count):
		while _vm.page > i:
			_vm.page_back()
		while _vm.page < i:
			_vm.page_forward()
		assert_array(_vm.page_rows()).is_not_empty()
		assert_int(_vm.page_rows().size()).is_less_equal(BiomeSequenceViewModel.PAGE_SIZE)

## Clearing from a late page must not strand the player past the end.
func test_clearing_from_a_late_page_returns_to_the_first() -> void:
	_fill_past_one_page()
	assert_int(_vm.page).is_greater(0)
	_vm.clear()
	assert_int(_vm.step_count).is_equal(0)
	assert_int(_vm.page).is_equal(0)

## Records past PAGE_SIZE steps, spreading across upgrades so no single cap is
## hit. Returns the number of steps that landed.
func _fill_past_one_page() -> int:
	while _vm.step_amount > 0:                    # "Fill", to reach caps fast
		_vm.cycle_step_amount()
	for id in _def.upgrade_ids:
		if _vm.step_count > BiomeSequenceViewModel.PAGE_SIZE:
			break
		_vm.append_step(id)
	assert_int(_vm.step_count).override_failure_message(
		"biome '%s' cannot record more than one page of steps" % _def.key
		).is_greater(BiomeSequenceViewModel.PAGE_SIZE)
	return _vm.step_count
