extends GdUnitTestSuite
## The v9 -> v10 migration: Substrate became one rung per mycelium tier.
##
## The branch used to fork at depth three into an a-side and a b-side, six perks
## all raising node_production globally. It is a ten-rung spine now, one rung per
## tier, so the four forked ids were renumbered into it. A missed remap is silent
## and total: UpgradeSystem.from_save() drops a level it has no def for, so the
## player's Substrate levels would simply be gone.
##
## Driven through SaveManager's own migrate step rather than through a file, so
## the test is about the shape of the data and not about disk.

const MIGRATE := "_migrate_substrate_perks_to_v10"

func _perks(save: Dictionary) -> Dictionary:
	SaveManager.call(MIGRATE, save)
	return save["game"]["prestige_upgrades"]

func _v9_save(perks: Dictionary) -> Dictionary:
	return {"version": 9, "game": {"prestige_upgrades": perks}}

func test_the_forked_perks_land_on_their_spine_rungs() -> void:
	var perks := _perks(_v9_save({
		"substrate_3a": 12, "substrate_3b": 7, "substrate_4a": 3, "substrate_4b": 1,
	}))
	assert_dict(perks).is_equal({
		"substrate_3": 12, "substrate_4": 7, "substrate_5": 3, "substrate_6": 1,
	})

func test_the_rungs_that_kept_their_ids_pass_straight_through() -> void:
	var perks := _perks(_v9_save({"substrate_1": 50, "substrate_2": 22}))
	assert_dict(perks).is_equal({"substrate_1": 50, "substrate_2": 22})

func test_perks_from_other_branches_are_left_alone() -> void:
	var perks := _perks(_v9_save({"fruiting_3a": 4, "reach_5": 1, "not_a_perk": 9}))
	assert_dict(perks).is_equal({"fruiting_3a": 4, "reach_5": 1, "not_a_perk": 9})

func test_a_save_with_no_game_block_is_left_alone() -> void:
	var save := {"version": 9}
	SaveManager.call(MIGRATE, save)
	assert_bool(save.has("game")).is_false()

## Every id the migration produces has to name a perk the tree actually builds,
## or the level it carried is dropped on the next load.
func test_every_migrated_id_is_still_in_the_tree() -> void:
	var ids := {}
	for perk in PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList):
		ids[String(perk.id)] = true
	for old_id: String in SaveManager.PERK_IDS_V9_TO_V10:
		assert_bool(ids.has(SaveManager.PERK_IDS_V9_TO_V10[old_id])) \
			.override_failure_message("v9 perk '%s' migrates to an id no longer in the tree." % old_id) \
			.is_true()

## The version this build writes. A save that came back at 9 would be migrated
## again on every load.
func test_the_build_writes_version_ten() -> void:
	assert_int(SaveManager.SAVE_VERSION).is_equal(10)
