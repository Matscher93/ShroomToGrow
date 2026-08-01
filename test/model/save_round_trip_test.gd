extends GdUnitTestSuite
## Save/load round-trip for every model that persists state.
##
## The save format is the one thing a player cannot recover from if it breaks,
## and its failure modes only show up on the corrupt or missing-data path, which
## is when it matters most.

const EPS := 0.000001

# ─── PlayerData ──────────────────────────────────────────────────────────────

func test_player_data_round_trip() -> void:
	var original := PlayerData.new()
	original.nutrients = BigNumber.from_value(123456.0)
	original.biomass = BigNumber.from_value(42.0)
	original.water = BigNumber.from_value(7.0)
	original.tick_count = 9439
	original.prestige_count = 3

	var restored := PlayerData.from_save(original.to_save())

	assert_float(restored.nutrients.to_float()).is_equal_approx(123456.0, EPS)
	assert_float(restored.biomass.to_float()).is_equal_approx(42.0, EPS)
	assert_float(restored.water.to_float()).is_equal_approx(7.0, EPS)
	assert_int(restored.tick_count).is_equal(9439)
	assert_int(restored.prestige_count).is_equal(3)

func test_player_data_loads_in_place_so_viewmodels_stay_bound() -> void:
	# Replacing App.player_data would orphan every VM already holding it, so
	# load_from_save must mutate through the setters instead.
	var live := PlayerData.new()
	var emitted: Array[int] = [0]
	live.nutrients_changed.connect(func(_v: BigNumber) -> void: emitted[0] += 1)

	live.load_from_save({"nutrients": {"m": 5.0, "e": 3}})

	assert_float(live.nutrients.to_float()).is_equal_approx(5000.0, EPS)
	assert_int(emitted[0]).is_equal(1)

func test_player_data_tolerates_an_empty_save() -> void:
	var restored := PlayerData.from_save({})
	assert_float(restored.nutrients.to_float()).is_zero()
	assert_int(restored.tick_count).is_zero()

# ─── BiomesData ──────────────────────────────────────────────────────────────

func test_biomes_data_round_trip() -> void:
	var original := BiomesData.new()
	original.unlock(&"meadow")
	original.unlock(&"forest")
	original.spend_points(&"meadow", 2)
	original.increase_size(&"forest")

	var restored := BiomesData.from_save(original.to_save())

	assert_bool(restored.is_unlocked(&"meadow")).is_true()
	assert_bool(restored.is_unlocked(&"forest")).is_true()
	assert_int(restored.points_spent(&"meadow")).is_equal(2)
	assert_int(restored.biome_size(&"forest")).is_equal(1)

func test_biomes_data_keeps_ever_unlocked_across_a_reset() -> void:
	var original := BiomesData.new()
	original.unlock(&"forest")
	original.reset()

	var restored := BiomesData.from_save(original.to_save())

	assert_bool(restored.is_unlocked(&"forest")).is_false()
	assert_bool(restored.is_ever_unlocked(&"forest")).is_true()

func test_legacy_save_backfills_ever_unlocked() -> void:
	# Saves predating the ever_unlocked field must not lose already-reached tabs.
	var restored := BiomesData.from_save({"unlocked": {"forest": true}})
	assert_bool(restored.is_ever_unlocked(&"forest")).is_true()

func test_biomes_data_tolerates_an_empty_save() -> void:
	var restored := BiomesData.from_save({})
	assert_bool(restored.is_unlocked(&"meadow")).is_false()
	assert_int(restored.points_spent(&"meadow")).is_zero()

# ─── MyceliumNode ────────────────────────────────────────────────────────────

func test_node_auto_nodes_round_trip() -> void:
	var node := MyceliumNode.new()
	node.auto_nodes = BigNumber.from_value(1e12)
	var restored := BigNumber.from_save(node.auto_nodes.to_save())
	assert_bool(restored.same_value(node.auto_nodes)).is_true()

func test_node_backing_fields_track_the_cached_value() -> void:
	# The cached BigNumber and the exported floats a .tres persists must never
	# disagree, or a save would write a different value than the game shows.
	var node := MyceliumNode.new()
	node.auto_nodes = BigNumber.from_value(123456.0)
	assert_float(node._auto_nodes_mantissa).is_equal_approx(node.auto_nodes.mantissa, EPS)
	assert_int(node._auto_nodes_exponent).is_equal(node.auto_nodes.exponent)

func test_setting_an_equal_value_does_not_emit() -> void:
	# == on a RefCounted is an identity check, which would make this guard dead
	# and fan a signal out to every bound ViewModel on each assignment.
	var node := MyceliumNode.new()
	var emitted: Array[int] = [0]
	node.auto_nodes_changed.connect(func(_v: BigNumber) -> void: emitted[0] += 1)

	node.auto_nodes = BigNumber.from_value(100.0)
	node.auto_nodes = BigNumber.from_value(100.0)   # distinct instance, same value
	assert_int(emitted[0]).is_equal(1)

	node.auto_nodes = BigNumber.from_value(100.5)   # a real change still emits
	assert_int(emitted[0]).is_equal(2)

func test_node_reads_authored_backing_fields() -> void:
	# A .tres deserialises straight into the exported floats, so the lazily
	# built cache has to pick them up rather than stay at zero.
	var node := MyceliumNode.new()
	node._auto_nodes_mantissa = 2.5
	node._auto_nodes_exponent = 4
	assert_float(node.auto_nodes.to_float()).is_equal_approx(25000.0, EPS)

# ─── SaveManager migrations ──────────────────────────────────────────────────

func test_v1_perk_ids_are_remapped_and_the_save_is_stamped_v2() -> void:
	# Perk ids used to be "<branch key><roman numeral>". UpgradeSystem.from_save()
	# drops levels it has no def for, so a missed remap wipes the tree.
	var data := {"version": 1, "game": {"prestige_upgrades": {"nutI": 2, "bntIII·A": 1, "core": 1}}}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_int(int(data["version"])).is_equal(SaveManager.SAVE_VERSION)
	assert_dict(data["game"]["prestige_upgrades"]).is_equal({
		"substrate_1": 2, "bounty_3a": 1, "core": 1,
	})

func test_migrated_perk_ids_are_all_known_to_the_built_tree() -> void:
	var ids := {}
	for perk in PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList):
		ids[String(perk.id)] = true
	for old_id: String in SaveManager.PERK_IDS_V1_TO_V2:
		assert_bool(ids.has(SaveManager.PERK_IDS_V1_TO_V2[old_id])) \
			.override_failure_message("v1 perk '%s' migrates to an id no longer in the tree." % old_id) \
			.is_true()

func test_migration_leaves_unknown_and_already_current_perk_ids_alone() -> void:
	var data := {"version": 0, "game": {"prestige_upgrades": {"substrate_1": 3, "not_a_perk": 1}}}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_dict(data["game"]["prestige_upgrades"]).is_equal({"substrate_1": 3, "not_a_perk": 1})

func test_a_save_from_a_newer_build_is_refused() -> void:
	assert_bool(SaveManager._migrate({"version": SaveManager.SAVE_VERSION + 1})).is_false()

func test_migration_tolerates_a_save_with_no_game_section() -> void:
	assert_bool(SaveManager._migrate({"version": 1})).is_true()
