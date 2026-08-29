extends GdUnitTestSuite
## The v8 -> v9 migration: one Ruins roster split into heroes and workers.
##
## Before v9 the same units ran both boards. A save from then holds
## `creature_ranks` and farms carried by a `creature_id`; after it, heroes run
## expeditions and farms are worked by a pool nobody had bought yet.
##
## Driven through SaveManager's own migrate step rather than through a file, so
## the test is about the shape of the data and not about disk.

const MIGRATE := "_migrate_ruins_to_v9"

func _v8_save(active: Array, ranks: Dictionary = {}) -> Dictionary:
	return {
		"version": 8,
		"game": {"ruins": {
			"active": active,
			"creature_ranks": ranks,
			"missions_completed": 12,
		}},
	}

func _entry(mission_id: String, creature_id: String, is_farm: bool) -> Dictionary:
	return {
		"mission_id": mission_id,
		"creature_id": creature_id,
		"started_at": 1000.0,
		"duration": 60.0,
		"instance_id": 1 if not is_farm else 2,
		"is_farm": is_farm,
		"payouts": [],
	}

func _ruins(save: Dictionary) -> Dictionary:
	return save["game"]["ruins"]

func _migrate(save: Dictionary) -> Dictionary:
	SaveManager.call(MIGRATE, save)
	return _ruins(save)

# ─── The roster ──────────────────────────────────────────────────────────────

func test_creature_ranks_become_hero_levels() -> void:
	var save := _v8_save([], {"rot_grub": 3, "pale_stalker": 1})
	var ruins := _migrate(save)
	assert_bool(ruins.has("creature_ranks")).is_false()
	assert_int(int(ruins["hero_levels"]["rot_grub"])).is_equal(3)
	assert_int(int(ruins["hero_levels"]["pale_stalker"])).is_equal(1)

func test_an_expedition_keeps_its_hero() -> void:
	var save := _v8_save([_entry("sift_rubble", "rot_grub", false)])
	var entry: Dictionary = _migrate(save)["active"][0]
	assert_str(String(entry["hero_id"])).is_equal("rot_grub")
	assert_bool(entry.has("creature_id")).is_false()

# ─── The farms ───────────────────────────────────────────────────────────────

## A farm is nobody's errand now. It keeps running on one worker, the player is
## given that worker so the pool accounts for it, and the hero is handed back.
func test_a_running_farm_becomes_one_worker_and_frees_its_hero() -> void:
	var save := _v8_save([_entry("farm_pick_the_middens", "rot_grub", true)])
	var ruins := _migrate(save)
	var entry: Dictionary = ruins["active"][0]
	assert_int(int(entry["workers"])).is_equal(1)
	assert_str(String(entry["hero_id"])).is_empty()
	assert_int(int(ruins["workers_owned"])).is_equal(1)

func test_every_running_farm_is_paid_for() -> void:
	var save := _v8_save([
		_entry("farm_pick_the_middens", "rot_grub", true),
		_entry("farm_tap_the_seeps", "pale_stalker", true),
		_entry("sift_rubble", "chitin_scribe", false),
	])
	var ruins := _migrate(save)
	# Two farms, two workers - and the expedition contributes none.
	assert_int(int(ruins["workers_owned"])).is_equal(2)

func test_a_board_with_no_farms_hires_nobody() -> void:
	var save := _v8_save([_entry("sift_rubble", "rot_grub", false)])
	assert_int(int(_migrate(save)["workers_owned"])).is_zero()

# ─── Robustness ──────────────────────────────────────────────────────────────

## A half-written migration is worse than none, so a save whose ruins block is
## missing or the wrong shape is left exactly as it was.
func test_a_save_with_no_ruins_block_is_left_alone() -> void:
	var save := {"version": 8, "game": {}}
	SaveManager.call(MIGRATE, save)
	assert_bool((save["game"] as Dictionary).has("ruins")).is_false()

func test_a_malformed_ruins_block_is_left_alone() -> void:
	var save := {"version": 8, "game": {"ruins": "not a dictionary"}}
	SaveManager.call(MIGRATE, save)
	assert_str(String(save["game"]["ruins"])).is_equal("not a dictionary")

func test_a_corrupt_entry_is_skipped_rather_than_taking_the_migration_down() -> void:
	var save := _v8_save([42, _entry("farm_pick_the_middens", "rot_grub", true)])
	var ruins := _migrate(save)
	assert_int(int(ruins["workers_owned"])).is_equal(1)

## The version this build writes. A save that came back at 8 would be migrated
## again on every load.
func test_the_build_writes_version_nine() -> void:
	assert_int(SaveManager.SAVE_VERSION).is_equal(9)
