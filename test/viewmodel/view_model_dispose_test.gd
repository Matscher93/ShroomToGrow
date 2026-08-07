extends GdUnitTestSuite
## Connect/dispose symmetry for every ViewModel.
##
## A ViewModel subscribes to model signals in _init() and is expected to undo
## exactly that set in dispose(). The two lists are hand-maintained and sit ~200
## lines apart - BiomeViewModel connects 13 signals, BiomeSequenceViewModel 8 -
## so a signal added to one and forgotten in the other is the easiest mistake in
## the layer to make and the hardest to see.
##
## Both directions are failures, and neither shows up in play:
##   * a missed disconnect leaves a disposed VM notifying a view that is gone,
##   * a disconnect with no matching connect throws at runtime, but only on the
##     code path that disposes, which for the per-selection VMs is a reselect.
##
## Driven through the live App autoload, because that is what the VMs read.
## Nothing here mutates game state: each VM is built, counted and disposed.

## Every model object a ViewModel is allowed to subscribe to. A VM connecting to
## something outside this list would pass the census unnoticed, so it is
## deliberately the full set App owns rather than a per-test subset.
func _emitters() -> Array[Object]:
	var emitters: Array[Object] = [
		App,
		App.player_data,
		App.biomes_data,
		App.automation_data,
		App.achievement_progress,
		App.achievement_system,
		App.upgrade_system,
		App.biome_upgrade_system,
		App.prestige_upgrade_system,
		App.geode_upgrade_system,
		App.screens_data,
	]
	for node in App.nodes.mycelium_nodes:
		emitters.append(node)
	return emitters

## Total live signal connections across every emitter. An absolute number is
## meaningless - App's own long-lived VMs are in it - so only differences across
## a construct/dispose pair are ever asserted.
func _census() -> int:
	var total := 0
	for emitter in _emitters():
		for signal_info in emitter.get_signal_list():
			total += emitter.get_signal_connection_list(signal_info.name).size()
	return total

## Builds the VM, asserts it actually subscribed to something, disposes it and
## asserts the count is back where it started.
func _assert_symmetric(label: String, build: Callable) -> void:
	var before := _census()
	var vm: ViewModel = build.call()
	var connected := _census()
	assert_int(connected).override_failure_message(
		"%s connected to nothing in _init(), so this test proves nothing about it." % label
		).is_greater(before)
	vm.dispose()
	assert_int(_census()).override_failure_message(
		"%s left %d connection(s) behind after dispose()." % [label, _census() - before]
		).is_equal(before)

# ─── Per-item VMs (one per authored def, owned by App for the app's lifetime) ─

func test_biome_view_model_disposes_cleanly() -> void:
	for def in App.biomes.biomes:
		_assert_symmetric("BiomeViewModel(%s)" % def.key,
			func() -> ViewModel: return BiomeViewModel.new(def.key, def))

func test_biome_sequence_view_model_disposes_cleanly() -> void:
	for def in App.biomes.biomes:
		_assert_symmetric("BiomeSequenceViewModel(%s)" % def.key,
			func() -> ViewModel: return BiomeSequenceViewModel.new(def.key, def))

func test_perk_view_model_disposes_cleanly() -> void:
	for id: StringName in App.perk_defs:
		_assert_symmetric("PerkViewModel(%s)" % id,
			func() -> ViewModel: return PerkViewModel.new(id, App.perk_defs[id]))

func test_achievement_view_model_disposes_cleanly() -> void:
	for def in App.achievements.achievements:
		_assert_symmetric("AchievementViewModel(%s)" % def.id,
			func() -> ViewModel: return AchievementViewModel.new(def))

func test_automation_view_model_disposes_cleanly() -> void:
	for def in App.automations.automations:
		_assert_symmetric("AutomationViewModel(%s)" % def.id,
			func() -> ViewModel: return AutomationViewModel.new(def))

func test_geode_boost_view_model_disposes_cleanly() -> void:
	for def in App.geode_boosts.boosts:
		_assert_symmetric("GeodeBoostViewModel(%s)" % def.id,
			func() -> ViewModel: return GeodeBoostViewModel.new(def.id, def))

func test_mycelium_node_view_model_disposes_cleanly() -> void:
	for node_data in App.mycelium_node_data:
		_assert_symmetric("MyceliumNodeViewModel(%d)" % node_data.node.node_id,
			func() -> ViewModel: return MyceliumNodeViewModel.new(App.player_data, node_data))

# ─── Singleton VMs ───────────────────────────────────────────────────────────

func test_player_view_model_disposes_cleanly() -> void:
	_assert_symmetric("PlayerViewModel",
		func() -> ViewModel: return PlayerViewModel.new(App.player_data))

func test_screens_view_model_disposes_cleanly() -> void:
	_assert_symmetric("ScreensViewModel",
		func() -> ViewModel: return ScreensViewModel.new(App.screens_data))

func test_prestige_view_model_disposes_cleanly() -> void:
	_assert_symmetric("PrestigeViewModel",
		func() -> ViewModel: return PrestigeViewModel.new())

func test_achievements_view_model_disposes_cleanly() -> void:
	_assert_symmetric("AchievementsViewModel",
		func() -> ViewModel: return AchievementsViewModel.new())

func test_geodes_view_model_disposes_cleanly() -> void:
	_assert_symmetric("GeodesViewModel",
		func() -> ViewModel: return GeodesViewModel.new())

func test_crystal_caves_view_model_disposes_cleanly() -> void:
	_assert_symmetric("CrystalCavesViewModel",
		func() -> ViewModel: return CrystalCavesViewModel.new())

# ─── Per-selection VMs (built fresh on select, disposed on reselect) ─────────
#
# These are the ones a leak actually bites: the biome-upgrade card builds a new
# one on every grid slot press, so an unbalanced dispose() compounds per tap.

func test_biome_upgrade_view_model_disposes_cleanly() -> void:
	for def in App.biomes.biomes:
		for id in def.upgrade_ids:
			_assert_symmetric("BiomeUpgradeViewModel(%s)" % id,
				func() -> ViewModel: return BiomeUpgradeViewModel.new(id, def.key))

## Reselecting the same card repeatedly is the real usage pattern, and it is
## where an off-by-one in either list compounds instead of cancelling out.
func test_repeated_select_and_dispose_does_not_accumulate() -> void:
	var def: BiomeDef = App.biomes.biomes[0]
	var id: StringName = def.upgrade_ids[0]
	var before := _census()
	for i in range(20):
		var vm := BiomeUpgradeViewModel.new(id, def.key)
		vm.dispose()
	assert_int(_census()).is_equal(before)
