extends GdUnitTestSuite
## The v10 -> v11 migration: Bounty became one rung per biome.
##
## The branch used to fork at depth three into an a-side and a b-side, and every
## perk past the second poured its biome point into Permafrost. It is a six-rung
## spine now, one rung per biome, so all six ids were renamed onto the biome each
## one feeds. A missed remap is silent and total: UpgradeSystem.from_save() drops
## a level it has no def for, so the player's Bounty levels would simply be gone.
##
## Driven through SaveManager's own migrate step rather than through a file, so
## the test is about the shape of the data and not about disk.

const MIGRATE := "_migrate_bounty_perks_to_v11"

func _perks(save: Dictionary) -> Dictionary:
	SaveManager.call(MIGRATE, save)
	return save["game"]["prestige_upgrades"]

func _v10_save(perks: Dictionary) -> Dictionary:
	return {"version": 10, "game": {"prestige_upgrades": perks}}

func test_every_old_rung_lands_on_a_biome() -> void:
	var perks := _perks(_v10_save({
		"bounty_1": 5, "bounty_2": 4, "bounty_3a": 3,
		"bounty_3b": 2, "bounty_4a": 1, "bounty_4b": 5,
	}))
	assert_dict(perks).is_equal({
		"bounty_meadow": 5, "bounty_forest": 4, "bounty_permafrost": 3,
		"bounty_crystal_caves": 2, "bounty_underground_lake": 1, "bounty_ruins": 5,
	})

func test_perks_from_other_branches_are_left_alone() -> void:
	var perks := _perks(_v10_save({"fruiting_3a": 4, "substrate_6": 1, "not_a_perk": 9}))
	assert_dict(perks).is_equal({"fruiting_3a": 4, "substrate_6": 1, "not_a_perk": 9})

func test_a_save_with_no_game_block_is_left_alone() -> void:
	var save := {"version": 10}
	SaveManager.call(MIGRATE, save)
	assert_bool(save.has("game")).is_false()

## Every id the migration produces has to name a perk the tree actually builds,
## or the level it carried is dropped on the next load.
func test_every_migrated_id_is_still_in_the_tree() -> void:
	var ids := {}
	for perk in PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList):
		ids[String(perk.id)] = true
	for old_id: String in SaveManager.PERK_IDS_V10_TO_V11:
		assert_bool(ids.has(SaveManager.PERK_IDS_V10_TO_V11[old_id])) \
			.override_failure_message("v10 perk '%s' migrates to an id no longer in the tree." % old_id) \
			.is_true()

## Every biome gets exactly one Bounty rung, which is the whole point of the
## rework: a biome added without one would leave its points unreachable.
func test_every_biome_has_a_bounty_rung() -> void:
	var targets := {}
	for perk in PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList):
		if perk.branch_key != &"bnt":
			continue
		for effect: UpgradeEffectDef in perk.effects:
			targets[String(effect.target)] = int(targets.get(String(effect.target), 0)) + 1
	for biome in (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes:
		assert_int(int(targets.get(String(biome.key), 0))) \
			.override_failure_message("Biome '%s' is fed by %d Bounty perks, expected exactly one." \
				% [biome.key, int(targets.get(String(biome.key), 0))]).is_equal(1)

## The version this build writes. A save that came back at 10 would be migrated
## again on every load.
func test_the_build_writes_version_eleven() -> void:
	assert_int(SaveManager.SAVE_VERSION).is_equal(11)
