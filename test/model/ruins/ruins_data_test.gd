extends GdUnitTestSuite
## Unit tests for RuinsData (model/ruins/gd_ruins_data.gd) - the in-flight board,
## the roster's ranks, and how both survive a save.

const EPS := 0.000001

var _data: RuinsData

func before_test() -> void:
	_data = RuinsData.new()

func _payouts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"currency": int(CurrencyTypes.Types.RELICS), "m": 2.5, "e": 3})
	return out

# ─── The board ───────────────────────────────────────────────────────────────

func test_adding_a_mission_hands_back_a_usable_instance_id() -> void:
	var instance_id := _data.add(&"dig", &"grub", 100.0, 60.0, _payouts())
	assert_int(instance_id).is_greater(0)
	assert_int(_data.count()).is_equal(1)
	var entry := _data.find(instance_id)
	assert_str(String(entry["mission_id"])).is_equal("dig")
	assert_str(String(entry["creature_id"])).is_equal("grub")
	assert_float(entry["started_at"]).is_equal_approx(100.0, EPS)
	assert_float(entry["duration"]).is_equal_approx(60.0, EPS)

func test_instance_ids_are_never_reused_within_a_session() -> void:
	var first := _data.add(&"dig", &"grub", 0.0, 1.0, [])
	assert_bool(_data.remove(first)).is_true()
	var second := _data.add(&"dig", &"grub", 0.0, 1.0, [])
	assert_int(second).is_not_equal(first)

func test_a_creature_is_found_by_the_mission_it_carries() -> void:
	_data.add(&"dig", &"grub", 0.0, 1.0, [])
	assert_bool(_data.find_by_creature(&"grub").is_empty()).is_false()
	assert_bool(_data.find_by_creature(&"stalker").is_empty()).is_true()

func test_finding_an_unknown_instance_answers_empty_rather_than_crashing() -> void:
	assert_bool(_data.find(999).is_empty()).is_true()
	assert_bool(_data.remove(999)).is_false()

# ─── The roster ──────────────────────────────────────────────────────────────

func test_an_unrecruited_creature_reads_as_rank_zero() -> void:
	assert_int(_data.rank(&"grub")).is_equal(0)

func test_setting_a_rank_emits_once_and_only_on_a_change() -> void:
	var emitted := [0]
	_data.creatures_changed.connect(func() -> void: emitted[0] += 1)
	_data.set_rank(&"grub", 1)
	assert_int(emitted[0]).is_equal(1)
	_data.set_rank(&"grub", 1)
	assert_int(emitted[0]).is_equal(1)

func test_the_tally_emits_only_on_a_change() -> void:
	var seen := [-1]
	_data.missions_completed_changed.connect(func(value: int) -> void: seen[0] = value)
	_data.missions_completed = 3
	assert_int(seen[0]).is_equal(3)
	seen[0] = -1
	_data.missions_completed = 3
	assert_int(seen[0]).is_equal(-1)

# ─── Save ────────────────────────────────────────────────────────────────────

func test_a_full_board_round_trips() -> void:
	var instance_id := _data.add(&"dig", &"grub", 1234.5, 60.0, _payouts())
	_data.set_rank(&"grub", 2)
	_data.missions_completed = 7

	var restored := RuinsData.from_save(_data.to_save())
	assert_int(restored.count()).is_equal(1)
	assert_int(restored.missions_completed).is_equal(7)
	assert_int(restored.rank(&"grub")).is_equal(2)
	var entry := restored.find(instance_id)
	assert_str(String(entry["mission_id"])).is_equal("dig")
	assert_float(entry["started_at"]).is_equal_approx(1234.5, EPS)
	assert_float(entry["duration"]).is_equal_approx(60.0, EPS)
	assert_int(entry["payouts"].size()).is_equal(1)
	assert_float(entry["payouts"][0]["m"]).is_equal_approx(2.5, EPS)
	assert_int(entry["payouts"][0]["e"]).is_equal(3)

## The snapshot is the point of storing payouts at all - a save that dropped them
## would pay whatever the rules say on load rather than what the card promised.
func test_the_payout_snapshot_survives_a_round_trip_through_json() -> void:
	_data.add(&"dig", &"grub", 0.0, 1.0, _payouts())
	var text := JSON.stringify(_data.to_save())
	var parsed: Variant = JSON.parse_string(text)
	var restored := RuinsData.from_save(parsed)
	var entry: Dictionary = restored.active[0]
	assert_float(entry["payouts"][0]["m"]).is_equal_approx(2.5, EPS)
	assert_int(entry["payouts"][0]["currency"]).is_equal(int(CurrencyTypes.Types.RELICS))

func test_instance_ids_are_not_reused_across_a_load() -> void:
	var first := _data.add(&"dig", &"grub", 0.0, 1.0, [])
	var restored := RuinsData.from_save(_data.to_save())
	restored.remove(first)
	assert_int(restored.add(&"dig", &"grub", 0.0, 1.0, [])).is_greater(first)

## Even a board emptied before the save must not hand out an id an in-flight card
## remembers, which is why next_instance_id is saved as well as derived.
func test_an_emptied_board_still_advances_its_id_counter() -> void:
	var first := _data.add(&"dig", &"grub", 0.0, 1.0, [])
	_data.remove(first)
	var restored := RuinsData.from_save(_data.to_save())
	assert_int(restored.add(&"dig", &"grub", 0.0, 1.0, [])).is_greater(first)

func test_an_empty_save_leaves_a_fresh_board() -> void:
	var restored := RuinsData.from_save({})
	assert_int(restored.count()).is_equal(0)
	assert_int(restored.missions_completed).is_equal(0)

func test_a_corrupt_entry_is_skipped_rather_than_taking_the_load_down() -> void:
	_data.add(&"dig", &"grub", 0.0, 1.0, _payouts())
	var save := _data.to_save()
	save["active"].append("not a dictionary")
	var restored := RuinsData.from_save(save)
	assert_int(restored.count()).is_equal(1)

func test_a_corrupt_payout_is_skipped_rather_than_taking_the_load_down() -> void:
	_data.add(&"dig", &"grub", 0.0, 1.0, _payouts())
	var save := _data.to_save()
	save["active"][0]["payouts"].append(42)
	var restored := RuinsData.from_save(save)
	assert_int(restored.active[0]["payouts"].size()).is_equal(1)

## Loaded in place, so the systems holding a reference stay bound. Same contract
## as PlayerData.load_from_save.
func test_loading_mutates_in_place_rather_than_replacing() -> void:
	var seen := [0]
	_data.active_changed.connect(func() -> void: seen[0] += 1)
	_data.load_from_save({"missions_completed": 4})
	assert_int(seen[0]).is_greater(0)
	assert_int(_data.missions_completed).is_equal(4)
