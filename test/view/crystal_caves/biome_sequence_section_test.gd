extends GdUnitTestSuite
## The reworked sequence section (view/crystal_caves/gd_biome_sequence_section.gd),
## driven through its own controls.
##
## The screen smoke test boots this scene, but only ever for the starter biome:
## default state leaves every other biome shut, so the auto-buy row, the dead-grid
## case and the point-gated slots are all unreachable there. Those are the parts
## this section was rebuilt around, so they get driven directly.
##
## Bound to the live App autoload, because that is what the section's ViewModel
## reads. Everything it touches is real game state, so before_test() sets what it
## asserts on rather than assuming, and after_test() puts it all back.

const SECTION := "res://view/crystal_caves/sc_biome_sequence_section.tscn"

var _key: StringName
var _def: BiomeDef
var _vm: BiomeSequenceViewModel
var _section: Node
var _was_unlocked: bool
var _was_ever_unlocked: bool
var _had_auto_unlock: bool

func before_test() -> void:
	# The first biome that can actually relock - a starter biome offers no
	# auto-buy, which is half of what this suite is here for.
	for def in App.biomes.biomes:
		if not def.always_unlocked:
			_def = def
			break
	_key = _def.key
	_was_unlocked = App.biomes_data.is_unlocked(_key)
	_was_ever_unlocked = App.biomes_data.is_ever_unlocked(_key)
	_had_auto_unlock = App.has_biome_auto_unlock(_key)

	App.biomes_data.unlocked[_key] = true
	App.biomes_data.ever_unlocked[_key] = true
	App.biomes_data.auto_unlock.erase(_key)
	App.automation_data.clear_sequence(_key)

	_vm = App.biome_sequence_vms[_key]
	# The ViewModel outlives the screen by design, so its view state carries over
	# between cases as well. Wind it back.
	while _vm.step_amount != 1:
		_vm.cycle_step_amount()
	_vm.expanded = false

	_section = _spawn_section()

func after_test() -> void:
	App.automation_data.clear_sequence(_key)
	App.biomes_data.auto_unlock.erase(_key)
	if _had_auto_unlock:
		App.biomes_data.auto_unlock[_key] = true
	App.biomes_data.unlocked[_key] = _was_unlocked
	App.biomes_data.ever_unlocked[_key] = _was_ever_unlocked
	_vm.expanded = false
	await _free_section()

func _spawn_section() -> Node:
	var section := (load(SECTION) as PackedScene).instantiate()
	add_child(section)
	section.bind(_vm)
	return section

## Freed rather than auto_free()'d, and a frame is given away first: the section
## clears its rows and slots with queue_free(), which only lands at the end of a
## frame.
func _free_section() -> void:
	if _section == null:
		return
	remove_child(_section)
	_section.free()
	_section = null
	await get_tree().process_frame

## The slot holding this upgrade, in the same grid order the biome card uses.
func _slot_for(id: StringName) -> Button:
	return _section.grid_upgrade_slots.get_child(_def.upgrade_ids.find(id)) as Button

func _ungated_id() -> StringName:
	for id in _def.upgrade_ids:
		var def := App.biome_upgrade_system.def(id)
		if def != null and def.min_biome_points_spent <= 0:
			return id
	return &""

func _gated_id() -> StringName:
	for id in _def.upgrade_ids:
		var def := App.biome_upgrade_system.def(id)
		if def != null and def.min_biome_points_spent > 0:
			return id
	return &""

# ─── Auto-buy after sporation ────────────────────────────────────────────────

func test_a_biome_that_relocks_carries_an_auto_buy_row() -> void:
	assert_bool(_section.auto_unlock_row.visible).is_true()
	assert_bool(_section.btn_auto_unlock_buy.visible).is_true()
	assert_bool(_section.btn_auto_unlock_enabled.visible).is_false()
	assert_str(_section.lbl_auto_unlock.text).is_not_empty()

## The purchase is one-off, so its button gives way to the switch it unlocks
## rather than sitting there disabled forever.
func test_owning_the_auto_buy_swaps_the_button_for_the_switch() -> void:
	App.biomes_data.auto_unlock[_key] = true
	_section.refresh()
	assert_bool(_section.btn_auto_unlock_buy.visible).is_false()
	assert_bool(_section.btn_auto_unlock_enabled.visible).is_true()
	assert_bool(_section.btn_auto_unlock_enabled.button_pressed).is_true()

## A refresh must not report a toggle back at the model it just read from.
func test_refreshing_does_not_flip_the_auto_buy_switch() -> void:
	App.biomes_data.auto_unlock[_key] = true
	App.toggle_biome_auto_unlock(_key)
	assert_bool(App.is_biome_auto_unlock_enabled(_key)).is_false()

	_section.refresh()
	_section.refresh()
	assert_bool(App.is_biome_auto_unlock_enabled(_key)).override_failure_message(
		"refresh() echoed the switch state back into the model").is_false()

# ─── Slots and the status line ───────────────────────────────────────────────

func test_pressing_an_open_slot_records_and_says_what_it_recorded() -> void:
	_slot_for(_ungated_id()).pressed.emit()
	assert_int(_vm.step_count).is_equal(1)
	assert_str(_section.lbl_slot_status.text).contains("Tap records")
	assert_str(_section.lbl_summary.text).contains("1 step")

## A blocked slot stays pressable on purpose. Godot swallows input on a disabled
## Button, and pressing one is how the status line is asked what blocks it - the
## reason used to be a tooltip, which does not exist on touch.
func test_pressing_a_blocked_slot_reports_why_instead_of_recording() -> void:
	var gated := _gated_id()
	if gated.is_empty():
		return   # this biome gates nothing
	var slot := _slot_for(gated)
	assert_bool(slot.disabled).override_failure_message(
		"a blocked slot was disabled, so it can never say what blocks it").is_false()

	slot.pressed.emit()
	assert_int(_vm.step_count).is_zero()
	assert_bool(_section.lbl_slot_status.visible).is_true()
	assert_str(_section.lbl_slot_status.text).contains("Unlocks after")

## Its section is still listed so the auto-buy above can be bought, but there is
## nothing to plan against until the biome is back.
func test_a_biome_shut_this_run_keeps_its_section_with_a_dead_grid() -> void:
	App.biomes_data.unlocked.erase(_key)
	_section.refresh()
	assert_bool(_section.auto_unlock_row.visible).is_true()
	for slot in _section.grid_upgrade_slots.get_children():
		assert_bool((slot as Button).disabled).is_true()

# ─── Editing ─────────────────────────────────────────────────────────────────

func test_remove_last_drops_one_step_from_the_end() -> void:
	var slot := _slot_for(_ungated_id())
	slot.pressed.emit()
	slot.pressed.emit()
	assert_int(_vm.step_count).is_equal(2)

	_section.btn_remove_last.pressed.emit()
	assert_int(_vm.step_count).is_equal(1)

## Clear is the one action here that cannot be undone and can throw away hundreds
## of steps, so the first press only arms it.
func test_clear_takes_two_presses() -> void:
	_section.btn_step_amount.pressed.emit()      # x5
	_slot_for(_ungated_id()).pressed.emit()
	assert_int(_vm.step_count).is_equal(5)

	_section.btn_clear.pressed.emit()
	assert_int(_vm.step_count).override_failure_message(
		"the first Clear press wiped the sequence without confirming").is_equal(5)
	assert_str(_section.btn_clear.text).is_equal("Sure?")

	_section.btn_clear.pressed.emit()
	assert_int(_vm.step_count).is_zero()
	assert_str(_section.btn_clear.text).is_equal("Clear")

## The instructions for using the grid must not sit inside the part that
## collapses - a player with no sequence has no reason to open an empty list.
func test_the_empty_state_reads_while_the_section_is_collapsed() -> void:
	assert_bool(_section.vbox_body.visible).is_false()
	assert_bool(_section.lbl_empty.visible).is_true()

	_slot_for(_ungated_id()).pressed.emit()
	assert_bool(_section.lbl_empty.visible).is_false()

# ─── View state ──────────────────────────────────────────────────────────────

## Screens are freed on every nav switch, so expansion lives on the ViewModel.
## Without it, re-finding a place in a long sequence costs the player a dozen
## taps every time they glance at another screen.
func test_expansion_survives_the_section_being_respawned() -> void:
	_section._toggle_expanded()
	assert_bool(_vm.expanded).is_true()

	await _free_section()
	_section = _spawn_section()
	assert_bool(_section.vbox_body.visible).override_failure_message(
		"a respawned section forgot that it was open").is_true()
