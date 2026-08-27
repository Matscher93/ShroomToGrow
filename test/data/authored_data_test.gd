extends GdUnitTestSuite
## Integrity checks over everything authored under data/.
##
## These resources are linked by plain StringName, never by reference, so a
## rename or a typo produces no error at load, no warning at runtime and no
## visible symptom: the effect simply resolves to zero forever. Only a sweep
## like this catches it. Everything here reads the same files and the same
## loader App registers from.

## Every stat some system actually reads. The list itself lives in StatNames,
## where the balance editor can read it too and offer it as a dropdown - an
## effect naming anything else is inert, and that is worth preventing at the
## point of authoring as well as catching here.
const KNOWN_STATS := StatNames.ALL

## The sentence every biome upgrade's description ends with, since all of them
## scale with their biome's Size.
const SIZE_SCALING_NOTE := "Scales with this biome's Size."

var _nodes: Array[MyceliumNode]
var _biomes: Array[BiomeDef]
var _perks: Array[PerkDef]
var _symbiosis_defs: Array[UpgradeDef]
var _biome_defs: Array[UpgradeDef]
var _achievements: Array[AchievementDef]
var _automations: Array[AutomationDef]
var _boosts: Array[BoostDef]
var _projects: Array[ProjectDef]
var _producers: Array[GrowthProducerDef]
var _missions: Array[MissionDef]
var _creatures: Array[CreatureDef]
var _mission_boosts: Array[MissionBoostDef]

func before_test() -> void:
	_nodes = (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes).mycelium_nodes
	_biomes = (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes
	_perks = PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList)
	_symbiosis_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH)
	_biome_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH)
	_achievements = (load("res://data/achievements/all_achievements.tres") as AchievementList).achievements
	_automations = (load("res://data/automation/all_automations.tres") as AutomationList).automations
	_boosts = (load("res://data/boosts/all_boosts.tres") as BoostList).boosts
	_projects = (load("res://data/well/all_projects.tres") as ProjectList).projects
	_producers = (load("res://data/growth/all_producers.tres") as GrowthProducerList).producers
	_missions = (load("res://data/ruins/all_missions.tres") as MissionList).missions
	_creatures = (load("res://data/ruins/all_creatures.tres") as CreatureList).creatures
	_mission_boosts = (load("res://data/ruins/all_mission_boosts.tres") as MissionBoostList).boosts

## Node tiers, biomes and crystal boosts all address by StringName, and
## NODE-scoped effects use one field for all three, so a target is valid if it
## names any of them.
func _scope_targets() -> Dictionary:
	var targets := {}
	for node in _nodes:
		targets[node.id_key] = true
	for biome in _biomes:
		targets[biome.key] = true
	for boost in _boosts:
		targets[boost.id] = true
	return targets

func _biome_keys() -> Dictionary:
	var keys := {}
	for biome in _biomes:
		keys[biome.key] = true
	return keys

## Keys App writes into ResolveContext.manual_counts (see App._track_manual_count).
func _manual_count_keys() -> Dictionary:
	var keys := {}
	for node in _nodes:
		keys[StringName("ManualNode%d" % node.node_id)] = true
	return keys

func _all_upgrade_defs() -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	defs.append_array(_symbiosis_defs)
	defs.append_array(_biome_defs)
	for perk in _perks:
		defs.append(perk)
	defs.append_array(_mission_boost_defs())
	return defs

## The Ruins ladder's defs are generated from the boost list rather than authored
## one by one, but the effects are authored verbatim, so a typo in one is exactly
## as silent as a typo in an upgrade .tres.
func _mission_boost_defs() -> Array[UpgradeDef]:
	var list := MissionBoostList.new()
	list.boosts = _mission_boosts
	return MissionBoostTree.build(list)

## The growth track's defs are generated from the producer list rather than
## authored, but they are built from authored stats and scopes, so a typo in one
## is exactly as silent as a typo in an upgrade .tres.
func _growth_defs() -> Array[UpgradeDef]:
	var list := GrowthProducerList.new()
	list.producers = _producers
	return GrowthTree.build(list)

func _sorted_nodes() -> Array[MyceliumNode]:
	var sorted := _nodes.duplicate()
	sorted.sort_custom(func(a: MyceliumNode, b: MyceliumNode) -> bool: return a.node_id < b.node_id)
	return sorted

# ─── The data is actually there ──────────────────────────────────────────────

func test_every_registry_loads_something() -> void:
	# Guards every other test in this file: a loader returning nothing would make
	# all the sweeps below pass without checking anything.
	assert_array(_nodes).is_not_empty()
	assert_array(_biomes).is_not_empty()
	assert_array(_perks).is_not_empty()
	assert_array(_symbiosis_defs).is_not_empty()
	assert_array(_biome_defs).is_not_empty()
	assert_array(_achievements).is_not_empty()
	assert_array(_automations).is_not_empty()

func test_node_tiers_are_contiguous_from_zero() -> void:
	# TickSystem indexes bonuses by array position and looks effects up by
	# node_id, and the prestige reset special-cases tier 0 by id.
	var sorted := _sorted_nodes()
	for i in range(sorted.size()):
		assert_int(sorted[i].node_id) \
			.override_failure_message("Node tier %d out of order or duplicated." % i).is_equal(i)

func test_upgrade_ids_are_unique_within_their_track() -> void:
	# Ids are the save keys inside one UpgradeSystem, so a duplicate silently
	# collapses two upgrades into one shared level.
	for track: Array[UpgradeDef] in [_symbiosis_defs, _biome_defs]:
		var seen := {}
		for def in track:
			assert_bool(seen.has(def.id)) \
				.override_failure_message("Duplicate upgrade id '%s'." % def.id).is_false()
			seen[def.id] = true

# ─── Links resolve ───────────────────────────────────────────────────────────

func test_every_effect_names_a_stat_something_reads() -> void:
	for def in _all_upgrade_defs():
		for e in def.effects:
			assert_bool(KNOWN_STATS.has(e.stat)) \
				.override_failure_message("Upgrade '%s' targets stat '%s', which no system reads." \
					% [def.id, e.stat]).is_true()

func test_every_scoped_effect_has_a_target() -> void:
	# UpgradeSystem._scope_key() warns and then buckets a targetless scoped
	# effect where nothing ever reads it.
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.scope == UpgradeEffectDef.Scope.GLOBAL:
				continue
			assert_str(String(e.target)) \
				.override_failure_message("Upgrade '%s' is %s-scoped with no target." \
					% [def.id, UpgradeEffectDef.Scope.keys()[e.scope]]).is_not_empty()

func test_every_scoped_effect_target_resolves() -> void:
	var targets := _scope_targets()
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.scope != UpgradeEffectDef.Scope.NODE:
				continue
			assert_bool(targets.has(e.target)) \
				.override_failure_message("Upgrade '%s' targets '%s', which is neither a node tier nor a biome." \
					% [def.id, e.target]).is_true()

func test_every_dependency_kind_is_still_supported() -> void:
	# STAT and RESOURCE were removed but kept their ordinals, so an old .tres
	# still deserialises and only push_error()s at resolve time.
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null:
				continue
			assert_bool([ScalingSourceDef.Kind.NONE, ScalingSourceDef.Kind.NODE_COUNT,
					ScalingSourceDef.Kind.BIOME_SIZE].has(e.dependency.kind)) \
				.override_failure_message("Upgrade '%s' scales off removed kind %d." \
					% [def.id, e.dependency.kind]).is_true()

func test_every_node_count_dependency_resolves() -> void:
	var keys := _manual_count_keys()
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null or e.dependency.kind != ScalingSourceDef.Kind.NODE_COUNT:
				continue
			assert_bool(keys.has(e.dependency.key)) \
				.override_failure_message("Upgrade '%s' scales off manual count '%s', which App never writes." \
					% [def.id, e.dependency.key]).is_true()

func test_every_biome_size_dependency_resolves() -> void:
	# A dangling key is invisible: ResolveContext.biome_size() returns the base
	# 1.0 for an unknown biome, so the upgrade silently stops scaling and stays
	# at its authored magnitude no matter how much Size the player buys.
	var keys := _biome_keys()
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null or e.dependency.kind != ScalingSourceDef.Kind.BIOME_SIZE:
				continue
			assert_bool(keys.has(e.dependency.key)) \
				.override_failure_message("Upgrade '%s' scales off biome size '%s', which is not a biome. It is dead at every level." \
					% [def.id, e.dependency.key]).is_true()

func test_every_biome_upgrade_scales_with_its_own_biome_size() -> void:
	# Biome Size is the payoff for every point spent in a biome: each of its
	# upgrades multiplies by that biome's size. A missing dependency makes one
	# upgrade quietly fall behind its neighbours, and a dependency naming the
	# wrong biome hands the payoff to a biome the player never invested in.
	# Note the folder names lag the biome renames (data/upgrades/biomes/forest/
	# holds Meadow's upgrades), so this checks against BiomeDef.upgrade_ids.
	var owner_of := {}
	for biome in _biomes:
		for id in biome.upgrade_ids:
			owner_of[id] = biome.key
	for def in _biome_defs:
		var key: StringName = owner_of.get(def.id, &"")
		assert_str(String(key)) \
			.override_failure_message("Biome upgrade '%s' is in no biome's upgrade_ids, so no screen offers it." \
				% def.id).is_not_empty()
		for e in def.effects:
			assert_object(e.dependency) \
				.override_failure_message("Biome upgrade '%s' has an effect that does not scale with Biome Size." \
					% def.id).is_not_null()
			assert_int(e.dependency.kind) \
				.override_failure_message("Biome upgrade '%s' scales off kind %d, not its biome's size." \
					% [def.id, e.dependency.kind]).is_equal(ScalingSourceDef.Kind.BIOME_SIZE)
			assert_str(String(e.dependency.key)) \
				.override_failure_message("Biome upgrade '%s' belongs to '%s' but scales off '%s' size." \
					% [def.id, key, e.dependency.key]).is_equal(String(key))
		# The card shows description and "now +x%" side by side, and the Size
		# multiplier is already baked into that number. Without the sentence the
		# player sees a figure that does not match the authored per-level rate
		# and has nothing telling them why.
		assert_str(def.description) \
			.override_failure_message("Biome upgrade '%s' scales with Size but its description never says so." \
				% def.id).contains(SIZE_SCALING_NOTE)

func test_every_perk_parent_resolves() -> void:
	var ids := {}
	for perk in _perks:
		ids[perk.id] = true
	for perk in _perks:
		if perk.parent_id.is_empty():
			continue   # the core
		assert_bool(ids.has(perk.parent_id)) \
			.override_failure_message("Perk '%s' hangs off '%s', which the tree has no node for." \
				% [perk.id, perk.parent_id]).is_true()

func test_exactly_one_perk_is_the_root() -> void:
	# PerkSystem treats an empty parent_id as "available from the start", so a
	# second one would open a whole branch for free.
	var roots := 0
	for perk in _perks:
		if perk.parent_id.is_empty():
			roots += 1
	assert_int(roots).is_equal(1)

# ─── Presentation links ──────────────────────────────────────────────────────

func test_every_biome_has_a_shader() -> void:
	for biome in _biomes:
		assert_object(biome.biome_shader) \
			.override_failure_message("Biome '%s' has no shader, its icon renders blank." % biome.key) \
			.is_not_null()

func test_biome_screen_types_are_unique() -> void:
	# biome_def_for_screen() returns the first match, so a shared screen_type
	# makes one of the two biomes unreachable through the tab.
	var seen := {}
	for biome in _biomes:
		assert_bool(seen.has(biome.screen_type)) \
			.override_failure_message("Biome '%s' shares screen type %d." % [biome.key, biome.screen_type]) \
			.is_false()
		seen[biome.screen_type] = true

func test_every_screen_has_a_scene_and_the_initial_one_exists() -> void:
	var screens := load("res://data/screens/all_screens.tres") as Screens
	for screen_type: ScreenTypes.Types in screens.screens:
		assert_object(screens.screens[screen_type].screen_scene) \
			.override_failure_message("Screen %d has no scene." % screen_type).is_not_null()
	assert_bool(screens.screens.has(screens.initial_screen)) \
		.override_failure_message("Initial screen %d is not in the registry." % screens.initial_screen) \
		.is_true()

# ─── Costs rise along a chain ────────────────────────────────────────────────

func test_node_tiers_get_strictly_more_expensive() -> void:
	var sorted := _sorted_nodes()
	for i in range(1, sorted.size()):
		assert_bool(sorted[i].initial_cost.gt(sorted[i - 1].initial_cost)) \
			.override_failure_message("Tier %d (%s) costs no more than tier %d (%s)." \
				% [sorted[i].node_id, sorted[i].initial_cost, sorted[i - 1].node_id,
					sorted[i - 1].initial_cost]).is_true()

func test_symbiosis_upgrades_get_more_expensive_with_their_tier() -> void:
	# Grouped by the tier each upgrade targets rather than by id, so renaming an
	# upgrade doesn't quietly drop it out of this check.
	var by_stat := {}   # stat -> { tier -> base_cost }
	for def in _symbiosis_defs:
		for e in def.effects:
			if e.scope != UpgradeEffectDef.Scope.NODE:
				continue
			var tiers: Dictionary = by_stat.get(e.stat, {})
			tiers[int(String(e.target))] = def.base_cost
			by_stat[e.stat] = tiers

	assert_bool(by_stat.is_empty()).is_false()
	for stat: StringName in by_stat:
		var tiers: Dictionary = by_stat[stat]
		var ordered: Array = tiers.keys()
		ordered.sort()
		for i in range(1, ordered.size()):
			var here: BigNumber = tiers[ordered[i]]
			var before: BigNumber = tiers[ordered[i - 1]]
			assert_bool(here.gt(before)) \
				.override_failure_message("%s at tier %d (%s) costs no more than tier %d (%s)." \
					% [stat, ordered[i], here, ordered[i - 1], before]).is_true()

func test_a_perk_costs_more_than_its_parent() -> void:
	var by_id := {}
	for perk in _perks:
		by_id[perk.id] = perk
	for perk in _perks:
		if perk.parent_id.is_empty():
			continue
		var parent: PerkDef = by_id[perk.parent_id]
		assert_bool(perk.base_cost.gt(parent.base_cost)) \
			.override_failure_message("Perk '%s' (%s) costs no more than its parent '%s' (%s)." \
				% [perk.id, perk.base_cost, parent.id, parent.base_cost]).is_true()

func test_currency_bought_upgrades_have_a_rising_cost_curve() -> void:
	# cost() is base * growth^(level * exponent^level). A growth of 1 or less makes the
	# upgrade flat-priced or free at every level.
	var priced: Array[UpgradeDef] = []
	priced.append_array(_symbiosis_defs)
	for perk in _perks:
		priced.append(perk)
	for def in priced:
		assert_float(def.cost_growth) \
			.override_failure_message("Upgrade '%s' has cost growth %f, so it never gets more expensive." \
				% [def.id, def.cost_growth]).is_greater(1.0)

func test_biomes_get_more_expensive_to_unlock_and_to_grow() -> void:
	# List order is the order the player meets them.
	for i in range(1, _biomes.size()):
		assert_bool(_biomes[i].unlock_cost.gte(_biomes[i - 1].unlock_cost)) \
			.override_failure_message("Biome '%s' unlocks cheaper than '%s'." \
				% [_biomes[i].key, _biomes[i - 1].key]).is_true()
		assert_bool(_biomes[i].size_base_cost.gt(_biomes[i - 1].size_base_cost)) \
			.override_failure_message("Biome '%s' grows cheaper than '%s'." \
				% [_biomes[i].key, _biomes[i - 1].key]).is_true()

func test_auto_unlock_gets_more_expensive_along_the_biome_order() -> void:
	# A later biome reopening for fewer crystals than an earlier one would make
	# the earlier purchase strictly worse for the same job.
	for i in range(1, _biomes.size()):
		assert_bool(_biomes[i].auto_unlock_cost.gt(_biomes[i - 1].auto_unlock_cost)) \
			.override_failure_message("Biome '%s' reopens cheaper than '%s'." \
				% [_biomes[i].key, _biomes[i - 1].key]).is_true()

func test_every_relocking_biome_charges_something_to_reopen() -> void:
	for biome in _biomes:
		if biome.always_unlocked:
			continue   # never relocks, so it has nothing to sell
		assert_bool(biome.auto_unlock_cost.gt(BigNumber.new(0.0, 0))) \
			.override_failure_message("Biome '%s' reopens itself for free." % biome.key) \
			.is_true()

# ─── Biome upgrade gating ────────────────────────────────────────────────────

func test_the_point_requirement_rises_along_the_grid() -> void:
	# Grid order is the order the cards are shown in, so a requirement that dips
	# unlocks a later card before an earlier one.
	var by_id := {}
	for def in _biome_defs:
		by_id[def.id] = def
	for biome in _biomes:
		var previous := 0
		for id: StringName in biome.upgrade_ids:
			var def: UpgradeDef = by_id[id]
			assert_int(def.min_biome_points_spent) \
				.override_failure_message("Biome '%s': '%s' needs %d points, less than the card before it (%d)." \
					% [biome.key, id, def.min_biome_points_spent, previous]) \
				.is_greater_equal(previous)
			previous = def.min_biome_points_spent

func test_every_biome_has_something_buyable_at_zero_points() -> void:
	# Points are only earned by levelling, and the level only rises with XP, but
	# the chain still has to be enterable from a standing start.
	var by_id := {}
	for def in _biome_defs:
		by_id[def.id] = def
	for biome in _biomes:
		var free := false
		for id: StringName in biome.upgrade_ids:
			if by_id[id].min_biome_points_spent == 0:
				free = true
				break
		assert_bool(free) \
			.override_failure_message("Biome '%s' gates every upgrade behind points it can never spend." % biome.key) \
			.is_true()

# ─── Achievements ────────────────────────────────────────────────────────────

func test_achievement_ids_are_unique() -> void:
	# The id is the save key in AchievementProgress, so a duplicate silently
	# collapses two achievements onto one shared tier count.
	var seen := {}
	for def in _achievements:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Duplicate achievement id '%s'." % def.id).is_false()
		seen[def.id] = true

func test_every_achievement_goal_runs_away() -> void:
	# goal_for() is base * growth^(tier^exponent). At a growth of 1 or less the
	# bar never moves, so the tier loop hands out tiers until its safety cap and
	# then does it again on the next evaluate, forever.
	for def in _achievements:
		assert_float(def.goal_growth) \
			.override_failure_message("Achievement '%s' has goal growth %f, so its goal never rises." \
				% [def.id, def.goal_growth]).is_greater(1.0)

func test_every_achievement_pays_something() -> void:
	# A zero reward makes the whole ladder cosmetic: crystals are the only reason
	# to chase it.
	for def in _achievements:
		assert_bool(def.reward_base.gt(BigNumber.new(0.0, 0))) \
			.override_failure_message("Achievement '%s' pays no crystals at tier 1." % def.id) \
			.is_true()

func test_every_achievement_starts_reachable() -> void:
	for def in _achievements:
		assert_bool(def.goal_base.gt(BigNumber.new(0.0, 0))) \
			.override_failure_message("Achievement '%s' has a first goal of 0, so it completes instantly." \
				% def.id).is_true()

func test_every_counted_achievement_asks_for_whole_numbers_that_keep_rising() -> void:
	# Runs the authored curves through the real system, so a retune that lands a
	# counting goal on a fraction, or flat against the tier before it, is caught
	# here rather than read as "5.1 biomes unlocked" in the archive.
	var system := AchievementSystem.new(
		load("res://data/achievements/all_achievements.tres") as AchievementList,
		AchievementProgress.new(), PlayerData.new(),
		ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(), UpgradeSystem.new(),
			ResolveContext.new()),
		UpgradeSystem.new(), BiomesData.new())

	for def in _achievements:
		if not AchievementDef.is_counted(def.stat):
			continue
		var previous: BigNumber = null
		for achievement_tier in range(50):
			var goal := system.goal_for(def, achievement_tier)
			# Only the sub-thousand range is checked for whole-ness, because that
			# is exactly the range the archive prints digit for digit. Above it
			# the goal renders as "913.0K" and a BigNumber cannot hold a large
			# integer exactly anyway: normalising to mantissa x 10^e means
			# to_float() comes back a hair off, invisibly.
			if goal.exponent < 3:
				# Compared against the nearest whole number rather than tested for
				# an exact zero fraction: BigNumber normalises to mantissa x 10^e,
				# so even a clean 201 comes back as 201.00000000000003.
				var as_float := goal.to_float()
				assert_float(absf(as_float - round(as_float))) \
					.override_failure_message("Achievement '%s' tier %d asks for %f of a counted stat, which the archive shows as a fraction." \
						% [def.id, achievement_tier, as_float]).is_less(0.000001)
			if previous != null:
				assert_bool(goal.gt(previous)) \
					.override_failure_message("Achievement '%s' tier %d (%s) asks no more than tier %d (%s), so it completes for free." \
						% [def.id, achievement_tier, goal, achievement_tier - 1, previous]).is_true()
			previous = goal

func test_every_achievement_stat_is_a_real_one() -> void:
	# An out-of-range ordinal deserialises fine and then falls through
	# AchievementSystem.current_value()'s match to a permanent zero.
	var known := AchievementDef.Stat.values()
	for def in _achievements:
		assert_bool(known.has(def.stat)) \
			.override_failure_message("Achievement '%s' measures unknown stat %d." \
				% [def.id, def.stat]).is_true()

# ─── Automations ─────────────────────────────────────────────────────────────

func test_automation_ids_are_unique() -> void:
	var seen := {}
	for def in _automations:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Duplicate automation id '%s'." % def.id).is_false()
		seen[def.id] = true

func test_every_automation_kind_is_authored_exactly_once() -> void:
	# Every Kind has to exist as a buyable automation, or that whole branch of
	# AutomationSystem.run() is unreachable. Two of the same kind would just be
	# two timers doing the same job.
	var seen := {}
	for def in _automations:
		assert_bool(seen.has(def.kind)) \
			.override_failure_message("Automation kind %s is authored twice." \
				% AutomationDef.Kind.keys()[def.kind]).is_false()
		seen[def.kind] = true
	for kind: int in AutomationDef.Kind.values():
		assert_bool(seen.has(kind)) \
			.override_failure_message("No automation authored for kind %s, so it can never run." \
				% AutomationDef.Kind.keys()[kind]).is_true()

func test_every_automation_gets_more_expensive() -> void:
	for def in _automations:
		assert_float(def.cost_growth) \
			.override_failure_message("Automation '%s' has cost growth %f, so it never gets more expensive." \
				% [def.id, def.cost_growth]).is_greater(1.0)

func test_levelling_an_automation_never_makes_it_slower() -> void:
	# runs_per_tick() adds runs_per_level once per level past the first. A
	# negative value is a downgrade the player pays crystals for.
	for def in _automations:
		assert_float(def.runs_per_level) \
			.override_failure_message("Automation '%s' slows down as it levels (%f per level)." \
				% [def.id, def.runs_per_level]).is_greater_equal(0.0)

func test_every_automation_acts_at_least_sometimes_once_bought() -> void:
	# A base rate of 0 means the first level buys an automation that never fires.
	for def in _automations:
		assert_float(def.base_runs_per_tick) \
			.override_failure_message("Automation '%s' does nothing at level 1 (%f per tick)." \
				% [def.id, def.base_runs_per_tick]).is_greater(0.0)

func test_every_automation_perk_id_exists_in_the_perk_tree() -> void:
	# Both ids are plain StringNames. A typo in the unlock one locks that
	# automation forever; a typo in the cap one silently pins it at its authored
	# ceiling. Neither shows up at load.
	var perk_ids := {}
	for perk in _perks:
		perk_ids[perk.id] = true
	for def in _automations:
		for id: StringName in [def.unlock_perk_id, def.max_level_perk_id]:
			if id.is_empty():
				continue
			assert_bool(perk_ids.has(id)) \
				.override_failure_message("Automation '%s' names perk '%s', which no branch authors." \
					% [def.id, id]).is_true()

func test_every_capped_automation_has_a_perk_that_raises_the_cap() -> void:
	# A cap perk that adds 0 levels, or an id with no step size behind it, is a
	# perk the player buys for nothing.
	for def in _automations:
		if def.max_level_perk_id.is_empty():
			continue
		assert_int(def.max_level) \
			.override_failure_message("Automation '%s' has a max-level perk but no ceiling to raise." \
				% def.id).is_greater(0)
		assert_int(def.max_level_per_perk_level) \
			.override_failure_message("Automation '%s' names a max-level perk that adds nothing." \
				% def.id).is_greater(0)

# ---------------------------------------------------------------- growth

func test_every_producer_names_a_currency() -> void:
	# GrowthTree keys its ids off currency_type and takes the label and colours
	# from the same resource, so a producer without one is skipped entirely.
	for def in _producers:
		assert_object(def.currency) \
			.override_failure_message("A growth producer has no CurrencyDef, so it is inert.").is_not_null()

func test_producer_currencies_are_unique() -> void:
	# Two producers on one currency would generate the same upgrade ids, and the
	# second registration would silently take the first one's levels with it.
	var seen := {}
	for def in _producers:
		var currency := def.currency.currency_type
		assert_bool(seen.has(currency)) \
			.override_failure_message("Currency '%s' has two growth producers." \
				% def.currency.currency_name).is_false()
		seen[currency] = true

func test_every_producer_names_a_stat_something_reads() -> void:
	for def in _producers:
		assert_bool(KNOWN_STATS.has(def.stat)) \
			.override_failure_message("Growth producer '%s' targets stat '%s', which no system reads." \
				% [def.currency.currency_name, def.stat]).is_true()

func test_every_producer_pays_something_for_both_stacks() -> void:
	for def in _producers:
		assert_float(def.lp_per_level) \
			.override_failure_message("Growth producer '%s' pays nothing per Level Point." \
				% def.currency.currency_name).is_greater(0.0)
		assert_float(def.daily_per_level) \
			.override_failure_message("Growth producer '%s' pays nothing per daily claim." \
				% def.currency.currency_name).is_greater(0.0)

## A global &"node_production" effect is applied once per node tier, so a x1.05
## nutrient bonus would land as x1.05^10. BoostDef documents this at length and
## res_nutrient_boost.tres is scoped the same way for the same reason.
func test_a_node_production_producer_is_scoped_to_one_node() -> void:
	for def in _producers:
		if def.stat != &"node_production":
			continue
		assert_int(def.scope) \
			.override_failure_message("Growth producer '%s' boosts node_production globally, which the node cascade compounds per tier." \
				% def.currency.currency_name).is_equal(UpgradeEffectDef.Scope.NODE)
		assert_str(String(def.target)) \
			.override_failure_message("Growth producer '%s' is NODE-scoped with no target." \
				% def.currency.currency_name).is_not_empty()

func test_generated_growth_ids_are_unique() -> void:
	var seen := {}
	for def in _growth_defs():
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Generated growth id '%s' collides with another." % def.id).is_false()
		seen[def.id] = true

func test_growth_stacks_multiply_rather_than_join_the_additive_pool() -> void:
	# Op.INCREASED would pool these into the same bucket every symbiosis and
	# biome upgrade writing the stat shares, where each level is worth less than
	# the one before - which is not what "+5% per point" means.
	for def in _growth_defs():
		for e in def.effects:
			assert_int(e.op) \
				.override_failure_message("Growth def '%s' is not a MORE effect." % def.id) \
				.is_equal(UpgradeEffectDef.Op.MORE)

func test_the_global_doubling_covers_every_producer() -> void:
	# One def with one effect per producer, so a single level keeps all four in
	# step. A producer missing from it is one the doubling silently skips.
	var double_def: UpgradeDef = null
	for def in _growth_defs():
		if def.id == GrowthTree.GLOBAL_DOUBLE_ID:
			double_def = def
	assert_object(double_def).is_not_null()
	assert_int(double_def.effects.size()).is_equal(_producers.size())

# ---------------------------------------------------------------- well projects

func test_project_ids_are_unique() -> void:
	var seen := {}
	for def in _projects:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Project id '%s' is authored twice." % def.id).is_false()
		seen[def.id] = true

func test_every_project_has_boons() -> void:
	for def in _projects:
		assert_bool(def.boons.is_empty()) \
			.override_failure_message("Project '%s' has no boons, so funding it buys nothing." \
				% def.id).is_false()

func test_every_projects_first_boon_opens_at_level_one() -> void:
	# Boon 0 carries the project's own level and water price (see ProjectTree), so
	# a project whose first rung opens later can never be funded at all.
	for def in _projects:
		assert_int(def.boons[0].unlock_at_level) \
			.override_failure_message("Project '%s' opens its first boon at level %d, not 1." \
				% [def.id, def.boons[0].unlock_at_level]).is_equal(1)

func test_project_boon_thresholds_climb() -> void:
	# The card lists them in ladder order and the player reads that order as the
	# order they arrive in. A threshold that dips means a later rung opens first.
	for def in _projects:
		for i in range(1, def.boons.size()):
			assert_int(def.boons[i].unlock_at_level) \
				.override_failure_message("Project '%s' boon %d opens at %d, no later than the rung before it." \
					% [def.id, i, def.boons[i].unlock_at_level]) \
				.is_greater(def.boons[i - 1].unlock_at_level)

func test_every_project_boon_opens_within_its_project() -> void:
	# A threshold past the project's own ceiling is a rung no funding can reach.
	for def in _projects:
		if def.max_level <= 0:
			continue
		for boon in def.boons:
			assert_int(boon.unlock_at_level) \
				.override_failure_message("Project '%s' boon '%s' opens at %d, past its cap of %d." \
					% [def.id, boon.display_name, boon.unlock_at_level, def.max_level]) \
				.is_less_equal(def.max_level)

func test_every_project_boon_has_an_effect_naming_a_real_stat() -> void:
	for def in _projects:
		for boon in def.boons:
			assert_object(boon.effect) \
				.override_failure_message("Project '%s' boon '%s' has no effect." \
					% [def.id, boon.display_name]).is_not_null()
			assert_bool(KNOWN_STATS.has(boon.effect.stat)) \
				.override_failure_message("Project '%s' boon '%s' targets stat '%s', which nothing reads." \
					% [def.id, boon.display_name, boon.effect.stat]).is_true()

func test_every_project_boon_target_resolves() -> void:
	var targets := _scope_targets()
	for def in _projects:
		for boon in def.boons:
			if boon.effect == null or boon.effect.scope != UpgradeEffectDef.Scope.NODE:
				continue
			assert_bool(targets.has(boon.effect.target)) \
				.override_failure_message("Project '%s' boon '%s' targets '%s', which is no node tier." \
					% [def.id, boon.display_name, boon.effect.target]).is_true()

func test_the_project_depth_perk_exists_in_the_perk_tree() -> void:
	# Same silent failure as the boosts': a typo leaves every project pinned at
	# its authored ceiling forever, with nothing reported at load.
	var list := load("res://data/well/all_projects.tres") as ProjectList
	if list.max_level_perk_id.is_empty():
		return
	var perk_ids := {}
	for perk in _perks:
		perk_ids[perk.id] = true
	assert_bool(perk_ids.has(list.max_level_perk_id)) \
		.override_failure_message("The Well names perk '%s', which no branch authors." \
			% list.max_level_perk_id).is_true()

func test_the_project_depth_perk_actually_raises_something() -> void:
	var list := load("res://data/well/all_projects.tres") as ProjectList
	if list.max_level_perk_id.is_empty():
		return
	assert_int(list.max_level_per_perk_level) \
		.override_failure_message("The Well's depth perk raises the ceiling by 0 per level.") \
		.is_greater(0)

func test_at_least_one_project_is_open_from_the_start() -> void:
	# The only levels that count towards a gate are levels bought at the Well, so
	# a ladder whose every rung is gated can never have its first rung funded.
	# Nothing at runtime reports that - the screen just sits there dead.
	var open_from_zero := false
	for def in _projects:
		if def.min_project_levels <= 0:
			open_from_zero = true
	assert_bool(open_from_zero) \
		.override_failure_message("Every project is gated, so the Well can never be started.") \
		.is_true()

func test_project_gates_are_reachable() -> void:
	# A threshold past what the whole ladder can ever be funded to is a project no
	# save can open. Uncapped projects make the total unbounded, so they are only
	# checked against each other.
	var total := 0
	for def in _projects:
		if def.max_level <= 0:
			return
		total += def.max_level
	for def in _projects:
		assert_int(def.min_project_levels) \
			.override_failure_message("Project '%s' opens at %d well levels, past the %d the ladder holds." \
				% [def.id, def.min_project_levels, total]).is_less_equal(total)

func test_project_gates_climb_with_display_order() -> void:
	# The list is the order the cards are shown in, and a player reads that top to
	# bottom as the order they arrive in. A gate that dips means a card lower down
	# opens first.
	for i in range(1, _projects.size()):
		assert_int(_projects[i].min_project_levels) \
			.override_failure_message("Project '%s' opens at %d, before '%s' above it at %d." \
				% [_projects[i].id, _projects[i].min_project_levels,
					_projects[i - 1].id, _projects[i - 1].min_project_levels]) \
			.is_greater_equal(_projects[i - 1].min_project_levels)

func test_project_cost_curves_rise() -> void:
	# A flat curve makes a project free to max out, and the ladder's late rungs
	# are priced against the assumption that it does not.
	for def in _projects:
		assert_float(def.cost_growth) \
			.override_failure_message("Project '%s' has a cost curve that never rises." \
				% def.id).is_greater(1.0)

func test_project_upgrade_ids_are_unique_across_the_built_tree() -> void:
	# ProjectTree ids are derived from the project id, so two projects sharing one
	# would silently share their levels too.
	var seen := {}
	for def in ProjectTree.build(load("res://data/well/all_projects.tres") as ProjectList):
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Project upgrade id '%s' is built twice." % def.id).is_false()
		seen[def.id] = true

# ---------------------------------------------------------------- boosts

func test_every_boost_perk_id_exists_in_the_perk_tree() -> void:
	# Same silent failure as the automations': a typo either locks the boost
	# forever or pins it at its authored ceiling, with nothing reported at load.
	var perk_ids := {}
	for perk in _perks:
		perk_ids[perk.id] = true
	for def in _boosts:
		for id: StringName in [def.unlock_perk_id, def.max_level_perk_id]:
			if id.is_empty():
				continue
			assert_bool(perk_ids.has(id)) \
				.override_failure_message("Boost '%s' names perk '%s', which no branch authors." \
					% [def.id, id]).is_true()

func test_every_capped_boost_can_be_opened_all_the_way() -> void:
	# A boost the perks cannot walk to the end of the ladder leaves authored
	# tiers no player can ever buy into.
	for def in _boosts:
		if def.base_max_level <= 0:
			continue
		var cap_perk: PerkDef = null
		for perk in _perks:
			if perk.id == def.max_level_perk_id:
				cap_perk = perk
		assert_object(cap_perk) \
			.override_failure_message("Boost '%s' is capped at %d with no perk to raise it." \
				% [def.id, def.base_max_level]).is_not_null()
		var reachable := def.base_max_level + def.max_level_per_perk_level * cap_perk.max_level
		assert_int(reachable) \
			.override_failure_message("Boost '%s' tops out at %d, short of the ladder's %d." \
				% [def.id, reachable, BoostTiers.max_level()]).is_greater_equal(BoostTiers.max_level())

func test_boost_ids_are_unique() -> void:
	var seen := {}
	for def in _boosts:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Boost id '%s' is authored twice." % def.id).is_false()
		seen[def.id] = true

func test_every_boost_stat_is_a_real_one() -> void:
	for def in _boosts:
		assert_bool(KNOWN_STATS.has(def.stat)) \
			.override_failure_message("Boost '%s' targets stat '%s', which nothing reads." \
				% [def.id, def.stat]).is_true()

## A &"node_production" boost left GLOBAL is applied to every tier of the
## cascade, and each tier feeds the one below, so it compounds once per tier
## before it reaches nutrients - a x1.5 boost lands as roughly x1.5^10. Keeping
## it NODE-scoped to tier 0 is what makes it a nutrient boost rather than a
## whole-chain one, and nothing about that is visible at load time.
func test_a_node_production_boost_is_scoped_to_one_tier() -> void:
	var targets := _scope_targets()
	for def in _boosts:
		if def.stat != &"node_production":
			continue
		assert_int(def.scope) \
			.override_failure_message("Boost '%s' raises node production globally, so the node cascade compounds it once per tier." \
				% def.id).is_equal(UpgradeEffectDef.Scope.NODE)
		assert_bool(targets.has(def.target)) \
			.override_failure_message("Boost '%s' targets '%s', which is neither a node tier nor a biome." \
				% [def.id, def.target]).is_true()

func test_every_boost_gets_more_expensive() -> void:
	for def in _boosts:
		assert_float(def.cost_growth) \
			.override_failure_message("Boost '%s' has cost growth %f, so it never gets more expensive." \
				% [def.id, def.cost_growth]).is_greater(1.0)

## The within-tier curve restarts at every boundary. Without a tier growth above
## 1.0 it restarts at the *same* opening price, so a tier worth orders of
## magnitude more per level costs exactly what the first one did.
func test_every_boost_opens_each_tier_dearer_than_the_last() -> void:
	for def in _boosts:
		assert_float(def.tier_cost_growth) \
			.override_failure_message("Boost '%s' has tier cost growth %f, so its tiers all open at the same price." \
				% [def.id, def.tier_cost_growth]).is_greater(1.0)
		var previous := 0.0
		for tier in range(1, BoostTiers.MAX_TIER + 1):
			var opening := def.tier_base_cost(tier)
			assert_float(opening) \
				.override_failure_message("Boost '%s' opens tier %d at %f, no dearer than the tier below." \
					% [def.id, tier, opening]).is_greater(previous)
			previous = opening

## A tier that pays less per level than the one under it makes crossing a
## boundary a downgrade the player just paid for.
func test_every_boost_pays_more_per_level_each_tier() -> void:
	for def in _boosts:
		assert_float(def.base_per_level) \
			.override_failure_message("Boost '%s' adds nothing at tier 1." % def.id) \
			.is_greater(0.0)
		assert_float(def.per_level_growth) \
			.override_failure_message("Boost '%s' has per-level growth %f, so a higher tier is worth no more than a lower one." \
				% [def.id, def.per_level_growth]).is_greater_equal(1.0)

## Every tier the ladder can reach has to produce a registerable def, or the
## levels above that boundary are unbuyable with no error to say why.
func test_the_generated_tier_defs_cover_the_whole_ladder() -> void:
	var defs := BoostTree.build(load("res://data/boosts/all_boosts.tres") as BoostList)
	assert_int(defs.size()).is_equal(_boosts.size() * BoostTiers.MAX_TIER)
	for def in defs:
		# Uncapped on purpose: BoostSystem owns the ceiling now, because a
		# &"boost_max_level" upgrade can move it past the last authored tier and a
		# number baked in here could not follow.
		assert_int(def.max_level).is_zero()
		assert_int(def.effects.size()).is_equal(1)

# ─── The Ruins ───────────────────────────────────────────────────────────────

func test_every_mission_id_is_unique() -> void:
	var seen := {}
	for def in _missions:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Mission id '%s' is used twice." % def.id).is_false()
		seen[def.id] = true

func test_every_creature_id_is_unique() -> void:
	var seen := {}
	for def in _creatures:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Creature id '%s' is used twice." % def.id).is_false()
		seen[def.id] = true

func test_every_ruins_boost_id_is_unique() -> void:
	var seen := {}
	for def in _mission_boosts:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Ruins boost id '%s' is used twice." % def.id).is_false()
		seen[def.id] = true

## A payout with no currency pays nothing, and MissionSystem can only push an
## error about it once the player has already run the mission.
func test_every_mission_pays_something() -> void:
	for def in _missions:
		assert_bool(def.payouts.is_empty()) \
			.override_failure_message("Mission '%s' pays nothing." % def.id).is_false()
		for payout in def.payouts:
			assert_object(payout.currency) \
				.override_failure_message("Mission '%s' has a payout with no currency." % def.id) \
				.is_not_null()
			assert_bool(payout.amount.gt(BigNumber.new(0.0, 0))) \
				.override_failure_message("Mission '%s' has a payout of zero." % def.id).is_true()

## The per-currency gain stat has to match the currency it rides on, or a
## &"glyph_gain" boost silently raises a relic payout.
func test_every_payout_gain_stat_matches_its_currency() -> void:
	var expected := {
		CurrencyTypes.Types.RELICS: &"relic_gain",
		CurrencyTypes.Types.ICHOR: &"ichor_gain",
		CurrencyTypes.Types.GLYPHS: &"glyph_gain",
	}
	for def in _missions:
		for payout in def.payouts:
			if payout.gain_stat.is_empty() or payout.currency == null:
				continue
			assert_str(String(payout.gain_stat)) \
				.override_failure_message("Mission '%s' pays %s but scales on '%s'." \
					% [def.id, payout.currency.currency_name, payout.gain_stat]) \
				.is_equal(String(expected.get(payout.currency.currency_type, &"")))

func test_every_mission_takes_time() -> void:
	for def in _missions:
		assert_float(def.base_duration_seconds) \
			.override_failure_message("Mission '%s' takes no time." % def.id).is_greater(0.0)

## List order is the order the player meets them, so a later mission that opens
## sooner would be a rung the ladder skips over.
func test_missions_open_in_list_order() -> void:
	for i in range(1, _missions.size()):
		assert_int(_missions[i].min_missions_completed) \
			.override_failure_message("Mission '%s' opens at %d, before '%s' at %d." \
				% [_missions[i].id, _missions[i].min_missions_completed,
					_missions[i - 1].id, _missions[i - 1].min_missions_completed]) \
			.is_greater_equal(_missions[i - 1].min_missions_completed)

## A longer errand that pays no better is one no player would ever choose.
##
## Compared within one currency at a time, never across them: the three are
## deliberately not on the same scale - a ritual pays a handful of glyphs where a
## dig pays dozens of relics - so a raw total is not a number two missions paying
## different currencies can be ranked by.
func test_a_longer_mission_pays_more_of_the_same_currency() -> void:
	for type: CurrencyTypes.Types in _mission_currencies():
		var ordered := _missions_paying(type)
		ordered.sort_custom(func(a: MissionDef, b: MissionDef) -> bool:
			return a.base_duration_seconds < b.base_duration_seconds)
		for i in range(1, ordered.size()):
			if is_equal_approx(ordered[i].base_duration_seconds,
					ordered[i - 1].base_duration_seconds):
				continue
			assert_float(_payout_of(ordered[i], type)) \
				.override_failure_message("Mission '%s' runs longer than '%s' but pays no more %s." \
					% [ordered[i].id, ordered[i - 1].id, CurrencyTypes.field_for(type)]) \
				.is_greater(_payout_of(ordered[i - 1], type))

func _mission_currencies() -> Array:
	var types := {}
	for def in _missions:
		for payout in def.payouts:
			if payout.currency != null:
				types[payout.currency.currency_type] = true
	return types.keys()

func _missions_paying(type: CurrencyTypes.Types) -> Array[MissionDef]:
	var out: Array[MissionDef] = []
	for def in _missions:
		if _payout_of(def, type) > 0.0:
			out.append(def)
	return out

func _payout_of(def: MissionDef, type: CurrencyTypes.Types) -> float:
	var total := 0.0
	for payout in def.payouts:
		if payout.currency != null and payout.currency.currency_type == type:
			total += payout.amount.to_float()
	return total

## Every affinity names a mission that exists. A typo here is silent: the
## creature simply never gets its bonus.
func test_every_creature_affinity_names_a_real_mission() -> void:
	var ids := {}
	for def in _missions:
		ids[def.id] = true
	for creature in _creatures:
		for mission_id in creature.affinity:
			assert_bool(ids.has(mission_id)) \
				.override_failure_message("Creature '%s' has affinity for '%s', which is not a mission." \
					% [creature.id, mission_id]).is_true()

## Every mission has to be reachable by somebody: a rank bar above every
## creature's ceiling is a card that can never be played.
func test_every_mission_is_within_some_creatures_reach() -> void:
	var best := 0
	for creature in _creatures:
		best = maxi(best, creature.base_rank_cap)
	for def in _missions:
		assert_int(def.min_creature_rank) \
			.override_failure_message("Mission '%s' needs rank %d, above every creature's ceiling of %d." \
				% [def.id, def.min_creature_rank, best]).is_less_equal(best)

## The bootstrap. Every mission needs a creature to carry it, and the three Ruins
## currencies have exactly one source - a collected mission. So if every creature
## at the front of the roster is priced in one of them, the Ruins can never be
## entered at all: the board sits there with an empty picker and a dead Send
## button, and nothing the player can do anywhere in the game opens it.
##
## Shipped exactly that way once. The end-to-end check missed it by granting
## itself relics before recruiting, which is precisely the step a real save has
## no way to perform.
func test_the_first_creature_is_affordable_before_any_mission_is_run() -> void:
	var mission_only := {}
	for def in _missions:
		for payout in def.payouts:
			if payout.currency != null:
				mission_only[payout.currency.currency_type] = true

	var reachable := false
	for creature in _creatures:
		if creature.min_missions_completed > 0 or creature.recruit_currency == null:
			continue
		if not mission_only.has(creature.recruit_currency.currency_type):
			reachable = true
	assert_bool(reachable).override_failure_message(
		"No creature is both open at zero missions and priced outside the currencies "
		+ "only missions pay - the Ruins cannot be entered.").is_true()

func test_every_creature_is_priced_in_something() -> void:
	for def in _creatures:
		assert_object(def.recruit_currency) \
			.override_failure_message("Creature '%s' has no recruit currency." % def.id).is_not_null()
		assert_object(def.rank_currency) \
			.override_failure_message("Creature '%s' has no rank currency." % def.id).is_not_null()
		assert_float(def.rank_cost_growth) \
			.override_failure_message("Creature '%s' has rank cost growth %f, so ranking it never gets dearer." \
				% [def.id, def.rank_cost_growth]).is_greater(1.0)
		assert_int(def.base_rank_cap) \
			.override_failure_message("Creature '%s' can never be ranked." % def.id).is_greater(0)

func test_creatures_open_in_list_order() -> void:
	for i in range(1, _creatures.size()):
		assert_int(_creatures[i].min_missions_completed) \
			.override_failure_message("Creature '%s' opens at %d, before '%s' at %d." \
				% [_creatures[i].id, _creatures[i].min_missions_completed,
					_creatures[i - 1].id, _creatures[i - 1].min_missions_completed]) \
			.is_greater_equal(_creatures[i - 1].min_missions_completed)

func test_every_ruins_boost_is_priced_and_gets_dearer() -> void:
	for def in _mission_boosts:
		assert_object(def.currency) \
			.override_failure_message("Ruins boost '%s' has no currency." % def.id).is_not_null()
		assert_bool(def.base_cost.gt(BigNumber.new(0.0, 0))) \
			.override_failure_message("Ruins boost '%s' is free." % def.id).is_true()
		assert_float(def.cost_growth) \
			.override_failure_message("Ruins boost '%s' has cost growth %f, so it never gets more expensive." \
				% [def.id, def.cost_growth]).is_greater(1.0)

## Every rung is priced in one of the three currencies missions actually pay.
## A rung priced in nutrients would be buyable without ever visiting the Ruins.
func test_every_ruins_boost_is_priced_in_a_mission_currency() -> void:
	var paid := {}
	for def in _missions:
		for payout in def.payouts:
			if payout.currency != null:
				paid[payout.currency.currency_type] = true
	for def in _mission_boosts:
		if def.currency == null:
			continue
		assert_bool(paid.has(def.currency.currency_type)) \
			.override_failure_message("Ruins boost '%s' is priced in %s, which no mission pays." \
				% [def.id, def.currency.currency_name]).is_true()

## The ladder has to have both halves. A Ruins with no general rungs is a system
## that never touches the rest of the game.
func test_the_ruins_ladder_has_both_a_control_and_a_colony_half() -> void:
	var control := 0
	var general := 0
	for def in _mission_boosts:
		var is_general := false
		for effect in def.effects:
			if not RuinsViewModel.CONTROL_STATS.has(effect.stat):
				is_general = true
		if is_general:
			general += 1
		else:
			control += 1
	assert_int(control).override_failure_message("No Ruins boost works the board itself.").is_greater(0)
	assert_int(general).override_failure_message("No Ruins boost reaches outside the Ruins.").is_greater(0)

# ---------------------------------------------------------------- currencies

## The registry is what makes a CurrencyDef reachable at all. Before it existed a
## def was only findable through whichever ScreenDefinition listed it, which is
## why fertilizer - never in the resource bar, so on no screen - had no def and
## every screen painting it hardcoded the same green instead.
##
## A currency added to the enum without an entry here goes silently colourless,
## and CurrencyTypes.field_for() hands back nutrients, so the whole enum is
## walked rather than a list that could drift from it.
func test_every_currency_type_has_a_def_filed_under_itself() -> void:
	for type: CurrencyTypes.Types in CurrencyTypes.Types.values():
		var def: CurrencyDef = App.currencies.currencies.get(type)
		assert_object(def).override_failure_message(
			"No CurrencyDef registered for CurrencyTypes.Types ordinal %d." % type).is_not_null()
		if def == null:
			continue
		assert_int(int(def.currency_type)).override_failure_message(
			"'%s' is filed in all_currencies.tres under ordinal %d but declares %d." \
				% [def.currency_name, type, def.currency_type]).is_equal(int(type))
		assert_str(def.currency_name).override_failure_message(
			"CurrencyDef ordinal %d has no name." % type).is_not_empty()

## field_for() falls through to nutrients, so a currency added without a case
## reads and writes the wrong PlayerData balance rather than failing.
func test_every_currency_type_maps_to_its_own_player_data_field() -> void:
	var seen := {}
	var player := PlayerData.new()
	for type: CurrencyTypes.Types in CurrencyTypes.Types.values():
		var field := CurrencyTypes.field_for(type)
		assert_bool(seen.has(field)).override_failure_message(
			"CurrencyTypes ordinal %d shares the field '%s' with an earlier one - " \
				% [type, field] + "field_for() is missing a case for it.").is_false()
		seen[field] = true
		assert_bool(player.get(field) is BigNumber).override_failure_message(
			"PlayerData has no BigNumber field '%s'." % field).is_true()
