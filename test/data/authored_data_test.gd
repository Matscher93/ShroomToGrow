extends GdUnitTestSuite
## Integrity checks over everything authored under data/.
##
## These resources are linked by plain StringName, never by reference, so a
## rename or a typo produces no error at load, no warning at runtime and no
## visible symptom: the effect simply resolves to zero forever. Only a sweep
## like this catches it. Everything here reads the same files and the same
## loader App registers from.

## Every stat some system actually reads. ProductionSystem consumes all but
## biome_points, which BiomeSystem reads. An effect naming anything else is
## inert, so adding a stat means adding it here too.
const KNOWN_STATS: Array[StringName] = [
	&"potency_production", &"synergy_production", &"node_production",
	&"biomass_gain", &"tick_rate", &"biome_points",
	&"crystal_gain", &"automation_rate", &"geode_conversion",
]

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
var _geode_boosts: Array[GeodeBoostDef]

func before_test() -> void:
	_nodes = (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes).mycelium_nodes
	_biomes = (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes
	_perks = PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList)
	_symbiosis_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH)
	_biome_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH)
	_achievements = (load("res://data/achievements/all_achievements.tres") as AchievementList).achievements
	_automations = (load("res://data/automation/all_automations.tres") as AutomationList).automations
	_geode_boosts = (load("res://data/geodes/all_geode_boosts.tres") as GeodeBoostList).boosts

## Node tiers and biomes both address by StringName, and NODE-scoped effects use
## one field for both, so a target is valid if it names either.
func _scope_targets() -> Dictionary:
	var targets := {}
	for node in _nodes:
		targets[node.id_key] = true
	for biome in _biomes:
		targets[biome.key] = true
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
	return defs

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

# ---------------------------------------------------------------- geode boosts

func test_every_conversion_perk_is_a_discount() -> void:
	# &"geode_conversion" is crystals *per geode*, so a positive per_level makes
	# geodes dearer - the opposite of what a perk priced in biomass is sold as.
	for perk in _perks:
		for e in perk.effects:
			if e.stat != &"geode_conversion":
				continue
			assert_float(e.per_level) \
				.override_failure_message("Perk '%s' raises the geode conversion rate (%f per level)." \
					% [perk.id, e.per_level]).is_less(0.0)

func test_every_geode_boost_perk_id_exists_in_the_perk_tree() -> void:
	# Same silent failure as the automations': a typo either locks the boost
	# forever or pins it at its authored ceiling, with nothing reported at load.
	var perk_ids := {}
	for perk in _perks:
		perk_ids[perk.id] = true
	for def in _geode_boosts:
		for id: StringName in [def.unlock_perk_id, def.max_level_perk_id]:
			if id.is_empty():
				continue
			assert_bool(perk_ids.has(id)) \
				.override_failure_message("Geode boost '%s' names perk '%s', which no branch authors." \
					% [def.id, id]).is_true()

func test_every_capped_geode_boost_can_be_opened_all_the_way() -> void:
	# A boost the perks cannot walk to the end of the ladder leaves authored
	# tiers no player can ever buy into.
	for def in _geode_boosts:
		if def.base_max_level <= 0:
			continue
		var cap_perk: PerkDef = null
		for perk in _perks:
			if perk.id == def.max_level_perk_id:
				cap_perk = perk
		assert_object(cap_perk) \
			.override_failure_message("Geode boost '%s' is capped at %d with no perk to raise it." \
				% [def.id, def.base_max_level]).is_not_null()
		var reachable := def.base_max_level + def.max_level_per_perk_level * cap_perk.max_level
		assert_int(reachable) \
			.override_failure_message("Geode boost '%s' tops out at %d, short of the ladder's %d." \
				% [def.id, reachable, GeodeTiers.max_level()]).is_greater_equal(GeodeTiers.max_level())

func test_geode_boost_ids_are_unique() -> void:
	var seen := {}
	for def in _geode_boosts:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Geode boost id '%s' is authored twice." % def.id).is_false()
		seen[def.id] = true

func test_every_geode_boost_stat_is_a_real_one() -> void:
	for def in _geode_boosts:
		assert_bool(KNOWN_STATS.has(def.stat)) \
			.override_failure_message("Geode boost '%s' targets stat '%s', which nothing reads." \
				% [def.id, def.stat]).is_true()

## A &"node_production" boost left GLOBAL is applied to every tier of the
## cascade, and each tier feeds the one below, so it compounds once per tier
## before it reaches nutrients - a x1.5 boost lands as roughly x1.5^10. Keeping
## it NODE-scoped to tier 0 is what makes it a nutrient boost rather than a
## whole-chain one, and nothing about that is visible at load time.
func test_a_node_production_geode_boost_is_scoped_to_one_tier() -> void:
	var targets := _scope_targets()
	for def in _geode_boosts:
		if def.stat != &"node_production":
			continue
		assert_int(def.scope) \
			.override_failure_message("Geode boost '%s' raises node production globally, so the node cascade compounds it once per tier." \
				% def.id).is_equal(UpgradeEffectDef.Scope.NODE)
		assert_bool(targets.has(def.target)) \
			.override_failure_message("Geode boost '%s' targets '%s', which is neither a node tier nor a biome." \
				% [def.id, def.target]).is_true()

func test_every_geode_boost_gets_more_expensive() -> void:
	for def in _geode_boosts:
		assert_float(def.cost_growth) \
			.override_failure_message("Geode boost '%s' has cost growth %f, so it never gets more expensive." \
				% [def.id, def.cost_growth]).is_greater(1.0)

## The within-tier curve restarts at every boundary. Without a tier growth above
## 1.0 it restarts at the *same* opening price, so a tier worth orders of
## magnitude more per level costs exactly what the first one did.
func test_every_geode_boost_opens_each_tier_dearer_than_the_last() -> void:
	for def in _geode_boosts:
		assert_float(def.tier_cost_growth) \
			.override_failure_message("Geode boost '%s' has tier cost growth %f, so its tiers all open at the same price." \
				% [def.id, def.tier_cost_growth]).is_greater(1.0)
		var previous := 0.0
		for tier in range(1, GeodeTiers.MAX_TIER + 1):
			var opening := def.tier_base_cost(tier)
			assert_float(opening) \
				.override_failure_message("Geode boost '%s' opens tier %d at %f, no dearer than the tier below." \
					% [def.id, tier, opening]).is_greater(previous)
			previous = opening

## A tier that pays less per level than the one under it makes crossing a
## boundary a downgrade the player just paid for.
func test_every_geode_boost_pays_more_per_level_each_tier() -> void:
	for def in _geode_boosts:
		assert_float(def.base_per_level) \
			.override_failure_message("Geode boost '%s' adds nothing at tier 1." % def.id) \
			.is_greater(0.0)
		assert_float(def.per_level_growth) \
			.override_failure_message("Geode boost '%s' has per-level growth %f, so a higher tier is worth no more than a lower one." \
				% [def.id, def.per_level_growth]).is_greater_equal(1.0)

## Every tier the ladder can reach has to produce a registerable def, or the
## levels above that boundary are unbuyable with no error to say why.
func test_the_generated_tier_defs_cover_the_whole_ladder() -> void:
	var defs := GeodeBoostTree.build(load("res://data/geodes/all_geode_boosts.tres") as GeodeBoostList)
	assert_int(defs.size()).is_equal(_geode_boosts.size() * GeodeTiers.MAX_TIER)
	for def in defs:
		assert_int(def.max_level).is_equal(GeodeTiers.LEVELS_PER_TIER)
		assert_int(def.effects.size()).is_equal(1)
