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
	original.crystals = BigNumber.from_value(88.0)
	original.fertilizer = BigNumber.from_value(11.0)
	original.relics = BigNumber.from_value(310.0)
	original.ichor = BigNumber.from_value(64.0)
	original.glyphs = BigNumber.from_value(9.0)
	original.tick_count = 9439
	original.prestige_count = 3
	original.lifetime_nutrients = BigNumber.from_value(1e9)
	original.lifetime_crystals = BigNumber.from_value(150.0)
	original.lifetime_fertilizer = BigNumber.from_value(37.0)
	original.lifetime_relics = BigNumber.from_value(980.0)
	original.lifetime_ichor = BigNumber.from_value(200.0)
	original.lifetime_glyphs = BigNumber.from_value(45.0)
	original.lifetime_ticks = 20000
	original.lifetime_manual_nodes = 512
	original.lifetime_biome_size = 64
	original.events_resolved = 26

	var restored := PlayerData.from_save(original.to_save())

	assert_float(restored.nutrients.to_float()).is_equal_approx(123456.0, EPS)
	assert_float(restored.biomass.to_float()).is_equal_approx(42.0, EPS)
	assert_float(restored.water.to_float()).is_equal_approx(7.0, EPS)
	assert_float(restored.crystals.to_float()).is_equal_approx(88.0, EPS)
	assert_float(restored.fertilizer.to_float()).is_equal_approx(11.0, EPS)
	assert_float(restored.relics.to_float()).is_equal_approx(310.0, EPS)
	assert_float(restored.ichor.to_float()).is_equal_approx(64.0, EPS)
	assert_float(restored.glyphs.to_float()).is_equal_approx(9.0, EPS)
	assert_int(restored.tick_count).is_equal(9439)
	assert_int(restored.prestige_count).is_equal(3)
	assert_float(restored.lifetime_nutrients.to_float()).is_equal_approx(1e9, EPS)
	assert_float(restored.lifetime_crystals.to_float()).is_equal_approx(150.0, EPS)
	assert_float(restored.lifetime_fertilizer.to_float()).is_equal_approx(37.0, EPS)
	assert_float(restored.lifetime_relics.to_float()).is_equal_approx(980.0, EPS)
	assert_float(restored.lifetime_ichor.to_float()).is_equal_approx(200.0, EPS)
	assert_float(restored.lifetime_glyphs.to_float()).is_equal_approx(45.0, EPS)
	assert_int(restored.lifetime_ticks).is_equal(20000)
	assert_int(restored.lifetime_manual_nodes).is_equal(512)
	assert_int(restored.lifetime_biome_size).is_equal(64)
	assert_int(restored.events_resolved).is_equal(26)

func test_achievement_tiers_is_not_saved_on_player_data() -> void:
	# It is a projection of AchievementProgress, rebuilt by
	# AchievementSystem.sync_tier_count() on load. Persisting it too would let the
	# two drift apart on any save written mid-award.
	var original := PlayerData.new()
	original.achievement_tiers = 17
	assert_bool(original.to_save().has("achievement_tiers")).is_false()

func test_well_project_levels_is_not_saved_on_player_data() -> void:
	# Same contract as achievement_tiers above: a projection of the project
	# UpgradeSystem, rebuilt by WellSystem.sync_project_levels() on load.
	var original := PlayerData.new()
	original.well_project_levels = 9
	assert_bool(original.to_save().has("well_project_levels")).is_false()

## The expedition reward track holds no save data of its own: it is a projection
## of RuinsData.completed_expeditions, rebuilt on load. Two records of the same
## thing is how they come to disagree.
func test_the_expedition_reward_track_is_not_saved() -> void:
	assert_bool(App.to_save().has("expedition_upgrades")) \
		.override_failure_message("The expedition reward track is being saved; it is a projection.") \
		.is_false()

func test_missions_completed_is_not_saved_on_player_data() -> void:
	# Same contract as achievement_tiers and well_project_levels above: a
	# projection of RuinsData, rebuilt by MissionSystem.sync_missions_completed()
	# on load.
	var original := PlayerData.new()
	original.missions_completed = 12
	assert_bool(original.to_save().has("missions_completed")).is_false()

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
	original.set_auto_unlock(&"forest")

	var restored := BiomesData.from_save(original.to_save())

	assert_bool(restored.is_unlocked(&"meadow")).is_true()
	assert_bool(restored.is_unlocked(&"forest")).is_true()
	assert_int(restored.points_spent(&"meadow")).is_equal(2)
	assert_int(restored.biome_size(&"forest")).is_equal(1)
	assert_bool(restored.is_auto_unlock(&"forest")).is_true()

func test_auto_unlock_survives_a_reset_and_a_save() -> void:
	# Bought with crystals, so like every crystal purchase it outlives the run
	# that bought it. Losing it would charge the player twice.
	var original := BiomesData.new()
	original.unlock(&"forest")
	original.set_auto_unlock(&"forest")
	original.reset()

	var restored := BiomesData.from_save(original.to_save())

	assert_bool(restored.is_auto_unlock(&"forest")).is_true()

func test_a_switched_off_auto_unlock_stays_off_across_a_save() -> void:
	# The `false` is the whole point of the entry: dropping it the way the other
	# dictionaries drop their falses would silently re-arm the unlock on load.
	var original := BiomesData.new()
	original.set_auto_unlock(&"forest")
	original.set_auto_unlock_enabled(&"forest", false)

	var restored := BiomesData.from_save(original.to_save())

	assert_bool(restored.is_auto_unlock(&"forest")).is_true()
	assert_bool(restored.is_auto_unlock_enabled(&"forest")).is_false()

func test_loading_in_place_restores_every_biome_field() -> void:
	# The bug this guards: SaveManager used to copy a hand-picked four fields off
	# the loaded object onto the live one, so auto_unlock never arrived and the
	# player was charged crystals for it again on every boot. Loading in place
	# leaves no field list for a caller to get wrong.
	var original := BiomesData.new()
	original.unlock(&"forest")
	original.spend_points(&"forest", 3)
	original.increase_size(&"forest")
	original.set_auto_unlock(&"forest")
	original.set_auto_unlock_enabled(&"forest", false)

	# A live instance the way App holds it: starters already open before the load.
	var live := BiomesData.new()
	live.unlock(&"meadow")
	live.load_from_save(original.to_save())

	assert_bool(live.is_unlocked(&"meadow")).is_true()
	assert_bool(live.is_unlocked(&"forest")).is_true()
	assert_int(live.points_spent(&"forest")).is_equal(3)
	assert_int(live.biome_size(&"forest")).is_equal(1)
	assert_bool(live.is_auto_unlock(&"forest")).is_true()
	assert_bool(live.is_auto_unlock_enabled(&"forest")).is_false()

func test_loading_in_place_announces_the_biomes_it_opens() -> void:
	# The bottom bar and the biome screens bind to this and have nothing else to
	# tell them a save arrived.
	var live := BiomesData.new()
	var original := BiomesData.new()
	original.unlock(&"forest")
	var announced: Array[StringName] = []
	live.biome_unlocked.connect(func(key: StringName) -> void: announced.append(key))

	live.load_from_save(original.to_save())

	assert_array(announced).is_equal([&"forest"])

func test_a_save_written_before_the_switch_existed_loads_switched_on() -> void:
	var restored := BiomesData.from_save({"auto_unlock": {"forest": true}})

	assert_bool(restored.is_auto_unlock_enabled(&"forest")).is_true()

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
	# The lifetime seed rides along: a v1 save runs every later step too.
	assert_dict(data["game"]["prestige_upgrades"]).is_equal({
		"substrate_1": 2, "bounty_3a": 1, "core": 1, UpgradeSystem.LIFETIME_KEY: 4,
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

	assert_dict(data["game"]["prestige_upgrades"]).is_equal({
		"substrate_1": 3, "not_a_perk": 1, UpgradeSystem.LIFETIME_KEY: 4,
	})

func test_a_save_from_a_newer_build_is_refused() -> void:
	assert_bool(SaveManager._migrate({"version": SaveManager.SAVE_VERSION + 1})).is_false()

func test_migration_tolerates_a_save_with_no_game_section() -> void:
	assert_bool(SaveManager._migrate({"version": 1})).is_true()

func test_v3_migration_seeds_the_lifetime_counters() -> void:
	# A pre-v3 save has no record of them, and starting a veteran player's whole
	# achievement archive from zero is the bug this exists to prevent.
	var data := {
		"version": 2,
		"game": {
			"player_data": {"tick_count": 4200},
			"mycelium_nodes": [{"manual_nodes": 30}, {"manual_nodes": 12}],
		},
	}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_int(int(data["game"]["player_data"]["lifetime_ticks"])).is_equal(4200)
	assert_int(int(data["game"]["player_data"]["lifetime_manual_nodes"])).is_equal(42)

func test_v3_migration_tolerates_a_save_with_no_nodes_or_player_data() -> void:
	var data := {"version": 2, "game": {}}
	assert_bool(SaveManager._migrate(data)).is_true()
	assert_int(int(data["game"]["player_data"]["lifetime_ticks"])).is_zero()
	assert_int(int(data["game"]["player_data"]["lifetime_manual_nodes"])).is_zero()

func test_v4_migration_seeds_the_lifetime_biome_size_from_the_current_run() -> void:
	# Those sizes are the only surviving record: levels bought in runs already
	# sporated away were never counted anywhere.
	var data := {
		"version": 3,
		"game": {
			"player_data": {},
			"biomes": {"size": {"meadow": 4, "forest": 3}},
		},
	}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_int(int(data["game"]["player_data"]["lifetime_biome_size"])).is_equal(7)

func test_v4_migration_tolerates_a_save_with_no_biome_sizes() -> void:
	var data := {"version": 3, "game": {}}
	assert_bool(SaveManager._migrate(data)).is_true()
	assert_int(int(data["game"]["player_data"]["lifetime_biome_size"])).is_zero()

func test_v5_migration_seeds_every_tracks_lifetime_purchase_count() -> void:
	var data := {
		"version": 4,
		"game": {
			"upgrades": {"NodePotency0": 5, "NodeSynergy0": 3},
			"biome_upgrades": {"DenseMycelium": 2},
			"prestige_upgrades": {"core": 1},
		},
	}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_int(int(data["game"]["upgrades"][UpgradeSystem.LIFETIME_KEY])).is_equal(8)
	assert_int(int(data["game"]["biome_upgrades"][UpgradeSystem.LIFETIME_KEY])).is_equal(2)
	assert_int(int(data["game"]["prestige_upgrades"][UpgradeSystem.LIFETIME_KEY])).is_equal(1)

func test_v5_migration_tolerates_a_save_with_no_upgrades() -> void:
	var data := {"version": 4, "game": {}}
	assert_bool(SaveManager._migrate(data)).is_true()
	assert_bool(data["game"].has("upgrades")).is_false()

func test_v6_migration_expands_a_point_plan_into_a_sequence() -> void:
	# A target of n becomes n steps, which is how a sequence expresses levels.
	var data := {
		"version": 5,
		"game": {"automation": {"point_plan": {"meadow": [
			{"id": "DenseMycelium", "target": 2},
			{"id": "RootNetwork", "target": 1},
		]}}},
	}

	assert_bool(SaveManager._migrate(data)).is_true()

	var automation: Dictionary = data["game"]["automation"]
	assert_array(automation["upgrade_sequences"]["meadow"]) \
		.is_equal(["DenseMycelium", "DenseMycelium", "RootNetwork"])
	assert_bool(automation.has("point_plan")).is_false()

func test_v6_migration_reads_buy_until_maxed_as_a_single_step() -> void:
	# A sequence has no way to say "until maxed", and under-recording the intent
	# beats spending points the player never allocated.
	var data := {
		"version": 5,
		"game": {"automation": {"point_plan": {"meadow": [{"id": "DenseMycelium", "target": 0}]}}},
	}

	assert_bool(SaveManager._migrate(data)).is_true()

	assert_array(data["game"]["automation"]["upgrade_sequences"]["meadow"]) \
		.is_equal(["DenseMycelium"])

func test_v6_migration_tolerates_a_save_with_no_automation() -> void:
	var data := {"version": 5, "game": {}}
	assert_bool(SaveManager._migrate(data)).is_true()
	assert_bool(data["game"].has("automation")).is_false()

# ─── AchievementProgress ─────────────────────────────────────────────────────

func test_achievement_progress_round_trip() -> void:
	var original := AchievementProgress.new()
	original.mark_completed(&"DeepRoots")
	original.mark_completed(&"DeepRoots")
	original.claim(&"DeepRoots")
	original.mark_completed(&"Cartographer")

	var restored := AchievementProgress.from_save(original.to_save())

	assert_int(restored.tier(&"DeepRoots")).is_equal(1)
	assert_int(restored.unclaimed_count(&"DeepRoots")).is_equal(1)
	assert_int(restored.unclaimed_count(&"Cartographer")).is_equal(1)
	assert_int(restored.total_tiers()).is_equal(1)
	assert_int(restored.total_unclaimed()).is_equal(2)

func test_unclaimed_tiers_survive_a_save() -> void:
	# Losing these on quit would silently rob the player of everything they
	# completed since the last time they opened the screen.
	var original := AchievementProgress.new()
	for i in range(5):
		original.mark_completed(&"DeepRoots")

	var restored := AchievementProgress.from_save(original.to_save())

	assert_int(restored.unclaimed_count(&"DeepRoots")).is_equal(5)

func test_achievement_progress_loads_in_place() -> void:
	# AchievementSystem holds the reference, so a load must mutate rather than
	# replace, the same reason PlayerData.load_from_save exists.
	var live := AchievementProgress.new()
	live.mark_completed(&"Stale")
	live.load_from_save({"tiers": {"DeepRoots": 4}, "unclaimed": {}})

	assert_int(live.unclaimed_count(&"Stale")).is_zero()
	assert_int(live.tier(&"DeepRoots")).is_equal(4)

func test_a_pre_claiming_save_reads_as_already_paid_out() -> void:
	# Those tiers were auto-awarded when they completed, so re-reading them as
	# unclaimed would hand out a second payout for the same progress.
	var restored := AchievementProgress.from_save({"DeepRoots": 3, "RichSoil": 2})

	assert_int(restored.tier(&"DeepRoots")).is_equal(3)
	assert_int(restored.total_unclaimed()).is_zero()

func test_achievement_progress_tolerates_an_empty_save() -> void:
	var restored := AchievementProgress.from_save({})
	assert_int(restored.tier(&"DeepRoots")).is_zero()
	assert_int(restored.total_tiers()).is_zero()
	assert_int(restored.total_unclaimed()).is_zero()

# ─── DailyRewardData ─────────────────────────────────────────────────────────

func test_daily_reward_data_round_trip() -> void:
	var original := DailyRewardData.new()
	original.last_claim_day = 20_113
	original.streak = 12

	var restored := DailyRewardData.from_save(original.to_save())

	assert_int(restored.last_claim_day).is_equal(20_113)
	assert_int(restored.streak).is_equal(12)

func test_daily_reward_data_loads_in_place() -> void:
	# GrowthViewModel binds to these signals, so a load must mutate rather than
	# replace, the same reason PlayerData.load_from_save exists.
	var live := DailyRewardData.new()
	var announced: Array[int] = []
	live.streak_changed.connect(func(value: int) -> void: announced.append(value))

	live.load_from_save({"last_claim_day": 20_113, "streak": 4})

	assert_int(live.last_claim_day).is_equal(20_113)
	assert_array(announced).is_equal([4])

func test_an_empty_daily_reward_save_reads_as_never_claimed() -> void:
	# Day 0 is 1970, so every save written before this system existed arrives
	# with a reward waiting rather than one already spent.
	var restored := DailyRewardData.from_save({})
	assert_int(restored.last_claim_day).is_zero()
	assert_int(restored.streak).is_zero()

# ─── AutomationData ──────────────────────────────────────────────────────────

func test_automation_data_round_trip() -> void:
	var original := AutomationData.new()
	original.add_level(&"AutoBuyNodes")
	original.add_level(&"AutoBuyNodes")
	original.set_enabled(&"AutoBuyNodes", false)
	original.append_to_sequence(&"meadow", &"ForestUpgrade2")
	original.append_to_sequence(&"meadow", &"ForestUpgrade2")
	original.append_to_sequence(&"meadow", &"DenseMycelium")

	var restored := AutomationData.from_save(original.to_save())

	assert_int(restored.level(&"AutoBuyNodes")).is_equal(2)
	assert_bool(restored.is_enabled(&"AutoBuyNodes")).is_false()
	var sequence: Array = restored.upgrade_sequences[&"meadow"]
	assert_int(sequence.size()).is_equal(3)
	assert_str(String(sequence[0])).is_equal("ForestUpgrade2")
	assert_str(String(sequence[2])).is_equal("DenseMycelium")

func test_automation_data_keeps_the_sequence_order_through_a_save() -> void:
	# The order is the whole point of a sequence, and a Dictionary round trip is
	# exactly where it could quietly become alphabetical.
	var original := AutomationData.new()
	for id in [&"zzz", &"aaa", &"mmm"]:
		original.append_to_sequence(&"meadow", id)

	var restored := AutomationData.from_save(original.to_save())

	var ids: Array[String] = []
	for id: StringName in restored.upgrade_sequences[&"meadow"]:
		ids.append(String(id))
	assert_array(ids).is_equal(["zzz", "aaa", "mmm"])

func test_automation_data_tolerates_an_empty_save() -> void:
	var restored := AutomationData.from_save({})
	assert_int(restored.level(&"AutoBuyNodes")).is_zero()
	assert_bool(restored.is_enabled(&"AutoBuyNodes")).is_true()

# ─── EventsData ──────────────────────────────────────────────────────────────

func test_events_data_round_trip() -> void:
	var original := EventsData.new()
	var first := original.add(&"spore_flush", 0)
	original.add(&"steady_cultivation", 3)
	original.advance_progress(func(def_id: StringName) -> int:
		return 4 if def_id == &"steady_cultivation" else 0)

	var restored := EventsData.from_save(original.to_save())

	assert_int(restored.count()).is_equal(2)
	assert_int(restored.events[0]["instance_id"]).is_equal(first)
	assert_str(String(restored.events[1]["def_id"])).is_equal("steady_cultivation")
	assert_int(restored.events[1]["progress"]).is_equal(1)
	assert_int(restored.events[1]["roll"]).is_equal(3)

## An id handed out twice could match a card already on its way off screen to the
## event that took its slot, paying the wrong one out.
func test_events_data_does_not_reissue_instance_ids_after_a_load() -> void:
	var original := EventsData.new()
	var only := original.add(&"windfall", 2)
	original.remove(only)
	var restored := EventsData.from_save(original.to_save())
	assert_int(restored.add(&"windfall", 2)).is_greater(only)

func test_events_data_loads_in_place() -> void:
	# EventSystem holds the reference, so load_from_save must mutate rather than
	# be replaced. Same contract as PlayerData.
	var live := EventsData.new()
	var emitted: Array[int] = [0]
	live.events_changed.connect(func() -> void: emitted[0] += 1)
	live.load_from_save({"events": [
		{"def_id": "windfall", "progress": 0, "instance_id": 4, "roll": 1},
	]})
	assert_int(live.count()).is_equal(1)
	assert_int(emitted[0]).is_greater(0)

func test_events_data_tolerates_an_empty_save() -> void:
	var restored := EventsData.from_save({})
	assert_int(restored.count()).is_equal(0)
	assert_bool(restored.is_empty()).is_true()

func test_a_corrupt_event_entry_is_dropped_rather_than_fatal() -> void:
	var restored := EventsData.from_save({"events": [
		"not a dictionary",
		{"def_id": "windfall", "progress": 0, "instance_id": 2, "roll": 1},
		{"def_id": "windfall", "progress": 0, "instance_id": 0, "roll": 1},
	]})
	assert_int(restored.count()).is_equal(1)
	assert_int(restored.events[0]["instance_id"]).is_equal(2)

# ─── Fertilizer track ────────────────────────────────────────────────────────

func test_fertilizer_upgrade_levels_round_trip() -> void:
	var track := UpgradeSystem.new()
	for def in FertilizerTree.build(App.fertilizer_upgrades, App.growth_producers):
		track.register(def)
	var id: StringName = App.fertilizer_upgrades.upgrades[0].id
	var player := PlayerData.new()
	player.fertilizer = BigNumber.from_value(1000.0)
	track.buy(id, player, &"fertilizer")
	track.buy(id, player, &"fertilizer")

	var restored := UpgradeSystem.new()
	for def in FertilizerTree.build(App.fertilizer_upgrades, App.growth_producers):
		restored.register(def)
	restored.from_save(track.to_save())

	assert_int(restored.level(id)).is_equal(2)

## Both new buckets are absent from every save written before this build. They
## have to read as a fresh start rather than failing the load, which is the
## contract App.load_from_save documents.
func test_a_save_without_the_new_buckets_loads_as_a_fresh_start() -> void:
	var game: Dictionary = {}
	assert_bool(game.get("fertilizer_upgrades", {}).is_empty()).is_true()
	assert_int(EventsData.from_save(game.get("events", {})).count()).is_equal(0)
	assert_float(PlayerData.from_save(game.get("player_data", {})).fertilizer.to_float()) \
		.is_equal_approx(0.0, EPS)
