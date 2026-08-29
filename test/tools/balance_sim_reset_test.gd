extends GdUnitTestSuite
## BalanceSim._reset() (tools/gd_balance_sim.gd).
##
## The simulator drives the real App autoload, so a run has to start from a real
## first-run state. _reset() is what produces it, and it is hand-maintained
## against App._ready() with nothing checking the two agree.
##
## They did not: the entire Ruins was absent from _reset() for as long as the
## Ruins existed, so `--load=<a real save>` carried that player's hero levels,
## mission board and completed tally straight into what tools/balance_report.json
## then reported as a baseline. test/data/balance_pacing_test.gd pins that report,
## so the drift could not show up there either.
##
## The check below is deliberately blunt and bucket-agnostic: dirty everything
## App saves, reset, and require the save to come back to where it started. A
## track added later is covered without touching this suite, which is exactly the
## property _reset() itself claimed to have and did not.

const SIM := preload("res://tools/gd_balance_sim.gd")

var _entry_save: Dictionary

func before() -> void:
	# The live autoload is shared with every other suite in the run.
	_entry_save = App.to_save()

func after() -> void:
	App.load_from_save(_entry_save)

# ─── Drift guard ─────────────────────────────────────────────────────────────

func test_reset_returns_every_saved_bucket_to_its_first_run_state() -> void:
	SIM._reset(App)
	var fresh := App.to_save()

	_dirty_everything()
	SIM._reset(App)

	for key: String in fresh:
		assert_dict({key: App.to_save()[key]}).override_failure_message(
			"_reset() left \"%s\" carrying state from the previous run, so a simulated baseline is not a first run. App._ready() builds it; _reset() has to clear it." % key
			).is_equal({key: fresh[key]})

func test_reset_clears_the_ruins() -> void:
	# The bucket that was actually missing, named on its own so a regression says
	# what it is rather than only which key differs.
	SIM._reset(App)
	App.ruins_data.missions_completed = 17
	App.mission_system.sync_missions_completed()

	SIM._reset(App)

	assert_int(App.ruins_data.missions_completed).is_zero()
	assert_int(App.player_data.missions_completed).is_zero()

## The expedition rewards write into the very stats the simulation measures, so a
## run that kept one from a loaded save would report a first run that is faster
## than any first run actually is.
func test_reset_clears_the_expedition_rewards() -> void:
	SIM._reset(App)
	var expedition := _first_rewarding_expedition()
	App.ruins_data.mark_expedition_done(expedition)
	App.ruins_data.workers_owned = 5
	App.mission_system.sync_expedition_rewards()
	assert_int(App.expedition_upgrade_system.level(expedition)).is_equal(1)

	SIM._reset(App)

	assert_int(App.ruins_data.completed_expeditions.size()).is_zero()
	assert_int(App.ruins_data.workers_owned).is_zero()
	assert_int(App.expedition_upgrade_system.level(expedition)).is_zero()

func _first_rewarding_expedition() -> StringName:
	for def in App.mission_defs.missions:
		if not def.is_farm and not def.rewards.is_empty():
			return def.id
	return &""

func test_reset_leaves_tier_zero_with_one_node() -> void:
	# Not a fresh-save value: with nothing producing, a run can never earn the
	# first purchase back, so _reset() seeds it the way PrestigeSystem does.
	SIM._reset(App)

	assert_int(App.mycelium_node_data[0].node.manual_nodes).is_equal(1)
	for i in range(1, App.mycelium_node_data.size()):
		assert_int(App.mycelium_node_data[i].node.manual_nodes).is_zero()

## Puts something in every bucket App.to_save() writes, so a bucket _reset()
## forgets shows up as a difference rather than as two matching empties.
##
## Every id is taken from the live registries rather than written out here: a
## hand-picked id that gets renamed turns this into a test that dirties nothing
## and passes for the wrong reason.
func _dirty_everything() -> void:
	App.player_data.nutrients = BigNumber.from_value(1e12)
	App.player_data.crystals = BigNumber.from_value(500.0)
	App.player_data.prestige_count = 3
	App.mycelium_node_data[0].node.manual_nodes = 99
	for track: UpgradeSystem in [App.upgrade_system, App.prestige_upgrade_system,
			App.biome_upgrade_system, App.boost_upgrade_system,
			App.project_upgrade_system, App.growth_upgrade_system,
			App.fertilizer_upgrade_system, App.mission_upgrade_system]:
		_dirty_track(track)
	for def in App.biomes.biomes:
		App.biomes_data.unlock(def.key)
	App.achievement_progress.load_from_save(
		{String(App.achievements.achievements[0].id): 2})
	App.automation_data.levels[App.automations.automations[0].id] = 4
	App.daily_reward_data.load_from_save({"streak": 6})
	App.events_data.add(App.random_events.events[0].id, 3)
	App.ruins_data.missions_completed = 12
	App.ruins_data.hero_levels[App.hero_defs.heroes[0].id] = 2

## Levels the first upgrade a track holds, whatever it happens to be. _defs is
## private by convention only, and reaching for it here is the same call
## save_round_trip_test.gd makes on MyceliumNode's backing fields.
func _dirty_track(track: UpgradeSystem) -> void:
	for id: StringName in track._defs.keys():
		track.set_level_for_analysis(id, 3)
		return
