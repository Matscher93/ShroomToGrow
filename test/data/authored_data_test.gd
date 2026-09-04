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
## The two kinds, split out. Almost every invariant below holds for one kind and
## is meaningless for the other: an expedition is a rung on a ladder ordered by
## min_missions_completed, and a farm is opened by finishing a named expedition
## instead, so comparing the two against each other says nothing.
var _expeditions: Array[MissionDef]
var _farms: Array[MissionDef]
var _heroes: Array[HeroDef]
## StringName hero id -> its expeditions, in authored order.
var _chains: Dictionary = {}
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
	_expeditions = []
	_farms = []
	for mission in _missions:
		if mission.is_farm:
			_farms.append(mission)
		else:
			_expeditions.append(mission)
	_heroes = (load("res://data/ruins/all_heroes.tres") as HeroList).heroes
	_chains = {}
	for mission in _expeditions:
		if not _chains.has(mission.hero_id):
			_chains[mission.hero_id] = []
		_chains[mission.hero_id].append(mission)
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

## Every group a node declares. There is no authored list of tags anywhere else:
## a tag means exactly "the nodes carrying it", so the node resources are the
## vocabulary, and a second list would only be somewhere to forget.
func _declared_tags() -> Dictionary:
	var tags := {}
	for node in _nodes:
		for tag in node.tags:
			tags[tag] = true
	return tags

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
	var tags := _declared_tags()
	for def in _all_upgrade_defs():
		for e in def.effects:
			match e.scope:
				UpgradeEffectDef.Scope.NODE:
					assert_bool(targets.has(e.target)) \
						.override_failure_message("Upgrade '%s' targets '%s', which is neither a node tier nor a biome." \
							% [def.id, e.target]).is_true()
				UpgradeEffectDef.Scope.TAG:
					assert_bool(tags.has(e.target)) \
						.override_failure_message("Upgrade '%s' targets group '%s', which no node carries. It is dead at every level." \
							% [def.id, e.target]).is_true()

func test_no_node_declares_the_same_tag_twice() -> void:
	# UpgradeSystem.scope_keys() dedupes, so a duplicate is silent rather than
	# double-counted - which is exactly why it needs catching here.
	for node in _nodes:
		var seen := {}
		for tag in node.tags:
			assert_bool(seen.has(tag)) \
				.override_failure_message("Node tier %d lists group '%s' twice." \
					% [node.node_id, tag]).is_false()
			seen[tag] = true

func test_no_tag_is_also_a_node_id() -> void:
	# The two share the `target` field and are told apart by scope alone, so a
	# group named "3" reads as a scope confusion everywhere a key is printed.
	var targets := _scope_targets()
	for node in _nodes:
		for tag in node.tags:
			assert_bool(targets.has(tag)) \
				.override_failure_message("Group '%s' on tier %d is also a node, biome or boost id." \
					% [tag, node.node_id]).is_false()

func test_every_declared_tag_is_carried_by_more_than_one_node() -> void:
	# A group of one is Scope.NODE written the long way, and hides a typo in a
	# tag that was meant to join an existing group.
	var counts := {}
	for node in _nodes:
		for tag in node.tags:
			counts[tag] = int(counts.get(tag, 0)) + 1
	for tag: StringName in counts:
		assert_int(int(counts[tag])) \
			.override_failure_message("Group '%s' is carried by one node. Use Scope.NODE, or fix the spelling." \
				% tag).is_greater(1)

func test_every_dependency_kind_is_still_supported() -> void:
	# STAT and RESOURCE were removed but kept their ordinals, so an old .tres
	# still deserialises and only push_error()s at resolve time.
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null:
				continue
			assert_bool([ScalingSourceDef.Kind.NONE, ScalingSourceDef.Kind.NODE_COUNT,
					ScalingSourceDef.Kind.BIOME_SIZE, ScalingSourceDef.Kind.BIOME_LEVEL].has(e.dependency.kind)) \
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

func test_every_biome_level_dependency_resolves() -> void:
	# Dangling exactly the way a biome size key dangles: ResolveContext
	# .biome_level() answers 1.0 for a biome it has never been written, so the
	# effect keeps its authored magnitude for ever and nothing says why.
	var keys := _biome_keys()
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null or e.dependency.kind != ScalingSourceDef.Kind.BIOME_LEVEL:
				continue
			assert_bool(keys.has(e.dependency.key)) \
				.override_failure_message("Upgrade '%s' scales off biome level '%s', which is not a biome. It is dead at every level." \
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

## The three stats Substrate moves, each once per tier along the spine and once
## globally at the Bedrock capstone.
const SUBSTRATE_STATS: Array[StringName] = [
	&"node_production", &"potency_production", &"synergy_production",
]

## Substrate is the branch that steers a single tier: one rung per mycelium tier
## boosting its production, with a potency and a synergy perk hanging off it.
## Those are NODE-scoped, and a target that drifts by one leaves a tier with no
## perk while another carries two - which no other check here would notice,
## because both spellings resolve to a real tier.
func test_every_mycelium_tier_has_its_own_substrate_perks() -> void:
	var by_stat := {}   # stat -> { tier -> count }
	for perk in _perks:
		if perk.branch_key != &"nut":
			continue
		for e in perk.effects:
			if e.scope == UpgradeEffectDef.Scope.GLOBAL:
				continue   # the Bedrock capstones, checked below
			assert_int(e.scope) \
				.override_failure_message("Substrate perk '%s' is neither global nor NODE-scoped, so it moves tiers it was never meant to." \
					% perk.id).is_equal(UpgradeEffectDef.Scope.NODE)
			var tiers: Dictionary = by_stat.get(e.stat, {})
			tiers[String(e.target)] = int(tiers.get(String(e.target), 0)) + 1
			by_stat[e.stat] = tiers

	for stat: StringName in SUBSTRATE_STATS:
		var tiers: Dictionary = by_stat.get(stat, {})
		for node in _nodes:
			assert_int(int(tiers.get(String(node.id_key), 0))) \
				.override_failure_message("Tier %d (%s) is targeted by %d Substrate '%s' perks, not exactly one." \
					% [node.node_id, node.name, int(tiers.get(String(node.id_key), 0)), stat]).is_equal(1)
		assert_int(tiers.size()) \
			.override_failure_message("Substrate has '%s' perks on %d targets but the game has %d tiers." \
				% [stat, tiers.size(), _nodes.size()]).is_equal(_nodes.size())

## The capstones are what the spine builds up to: past the last rung, one perk
## per stat that moves every tier at once. Global rather than ten node-scoped
## copies, so a tier added later is covered without touching them - and one per
## stat, because two would be the same multiplier under two names.
func test_substrate_ends_in_one_global_perk_per_stat() -> void:
	var globals := {}   # stat -> [perk ids]
	for perk in _perks:
		if perk.branch_key != &"nut":
			continue
		for e in perk.effects:
			if e.scope != UpgradeEffectDef.Scope.GLOBAL:
				continue
			var ids: Array = globals.get(e.stat, [])
			ids.append(String(perk.id))
			globals[e.stat] = ids

	for stat: StringName in SUBSTRATE_STATS:
		var ids: Array = globals.get(stat, [])
		assert_int(ids.size()) \
			.override_failure_message("Substrate has %d global '%s' perks (%s), not exactly one." \
				% [ids.size(), stat, ", ".join(PackedStringArray(ids))]).is_equal(1)
	assert_int(globals.size()) \
		.override_failure_message("Substrate carries global perks for stats outside %s." \
			% [SUBSTRATE_STATS]).is_equal(SUBSTRATE_STATS.size())

## The spine is the path outward, so walking it has to keep costing more. Held
## for the perks that carry the tree onward - the ones something hangs off - and
## not for its leaves.
##
## A leaf is a terminal purchase behind a gate that has already been paid for,
## and what it is worth is a balance call rather than a structural one. Reach is
## the branch that makes the difference: its rungs are tier unlocks priced in the
## thousands of digits, and its Attunement leaves are small bonuses hanging off
## them. Charging more for the bonus than for the gate it sits behind would be
## the wrong shape, and every other branch's leaves are dearer than their parent
## anyway - so what a leaf still owes is only that it costs something, which
## test_every_perk_costs_something asserts.
func test_the_perk_spine_costs_more_at_every_step() -> void:
	var by_id := {}
	var carries_the_tree := {}
	for perk in _perks:
		by_id[perk.id] = perk
		if not perk.parent_id.is_empty():
			carries_the_tree[perk.parent_id] = true
	for perk in _perks:
		if perk.parent_id.is_empty() or not carries_the_tree.has(perk.id):
			continue
		var parent: PerkDef = by_id[perk.parent_id]
		assert_bool(perk.base_cost.gt(parent.base_cost)) \
			.override_failure_message("Perk '%s' (%s) carries the tree onward but costs no more than its parent '%s' (%s)." \
				% [perk.id, perk.base_cost, parent.id, parent.base_cost]).is_true()

## What a leaf still owes, now that the ordering check above steps over it: a
## perk priced at nothing is one the tree hands out for free the moment its gate
## opens, and nothing else would say so.
func test_every_perk_costs_something() -> void:
	for perk in _perks:
		if perk.parent_id.is_empty():
			continue   # the core is the free one, by design
		assert_bool(perk.base_cost.gt(BigNumber.new(0.0, 0))) \
			.override_failure_message("Perk '%s' is free." % perk.id).is_true()

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
		# The ladder has no end to reach any more, so what matters is that the perk
		# is worth owning: it must open at least one whole tier past where the
		# boost starts, or maxing it moves the rate not at all.
		var reachable := def.base_max_level + def.max_level_per_perk_level * cap_perk.max_level
		var wanted := def.base_max_level + BoostTiers.LEVELS_PER_TIER
		assert_int(reachable) \
			.override_failure_message("Boost '%s' tops out at %d, not even one tier past the %d it opens at." \
				% [def.id, reachable, def.base_max_level]).is_greater_equal(wanted)

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

## Measured against where the tier below *closed*, not where it opened.
##
## Every opening was already dearer than the last while the boundary was still a
## 12x discount - the openings climbed by tier_cost_growth while the prices a
## player actually pays climbed by cost_growth over a hundred levels in between.
## Comparing openings to each other cannot see that, and did not.
##
## A boundary is also where the payout jumps by per_level_growth, so a boundary
## that is cheaper than the level before it is a discount on the upgrade.
func test_every_boost_opens_each_tier_above_where_the_last_one_closed() -> void:
	for def in _boosts:
		assert_float(def.tier_cost_growth) \
			.override_failure_message("Boost '%s' has tier cost growth %f, which makes crossing a boundary a discount." \
				% [def.id, def.tier_cost_growth]).is_greater_equal(1.0)
		assert_float(def.cost_growth_exponent) \
			.override_failure_message("Boost '%s' has cost growth exponent %f, which bends its price curve downwards." \
				% [def.id, def.cost_growth_exponent]).is_greater_equal(1.0)
		# Five tiers is a sample of an open-ended ladder, not the whole of it: the
		# invariant has to hold at every boundary, and the first few are where the
		# authored numbers are actually aimed.
		for tier in range(2, 6):
			var opens_at := (tier - 1) * BoostTiers.LEVELS_PER_TIER
			var opening := def.cost_at(opens_at)
			var closing := def.cost_at(opens_at - 1)
			assert_bool(opening.gt(closing)) \
				.override_failure_message("Boost '%s' opens tier %d at %s, under the %s the tier below closed at." \
					% [def.id, tier, opening.to_display(), closing.to_display()]).is_true()

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

## Every tier the ladder reaches has to produce a registerable def, or the levels
## above that boundary are unbuyable with no error to say why. The ladder has no
## last tier, so this asks for an arbitrary depth and expects it to be built.
func test_the_generated_tier_defs_cover_however_many_tiers_are_asked_for() -> void:
	var tiers := 9
	var defs := BoostTree.build(load("res://data/boosts/all_boosts.tres") as BoostList, tiers)
	assert_int(defs.size()).is_equal(_boosts.size() * tiers)
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

func test_every_hero_id_is_unique() -> void:
	var seen := {}
	for def in _heroes:
		assert_bool(seen.has(def.id)) \
			.override_failure_message("Hero id '%s' is used twice." % def.id).is_false()
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

## A chain is walked in order, so a later step that is shorter or pays less than
## the one before it is a rung the player would rather not have climbed.
##
## Held per chain rather than across all seven: the chains are independent
## progressions in different currencies, and comparing one against another says
## nothing.
func test_every_chain_climbs() -> void:
	for hero_id: StringName in _chains:
		var steps: Array = _chains[hero_id]
		for i in range(1, steps.size()):
			var here: MissionDef = steps[i]
			var before: MissionDef = steps[i - 1]
			assert_float(here.base_duration_seconds) \
				.override_failure_message("'%s' is shorter than '%s' before it in %s's chain." \
					% [here.id, before.id, hero_id]) \
				.is_greater(before.base_duration_seconds)
			assert_float(_payout_total(here)) \
				.override_failure_message("'%s' pays no more than '%s' before it in %s's chain." \
					% [here.id, before.id, hero_id]) \
				.is_greater(_payout_total(before))

func _payout_total(def: MissionDef) -> float:
	var total := 0.0
	for payout in def.payouts:
		total += payout.amount.to_float()
	return total

## Seven chains of twenty. The number is the shape of the whole feature, so it is
## worth failing loudly rather than quietly shipping a chain of nineteen.
func test_every_hero_has_a_full_chain() -> void:
	assert_int(_chains.size()).is_equal(_heroes.size())
	for hero: HeroDef in _heroes:
		assert_int((_chains.get(hero.id, []) as Array).size()) \
			.override_failure_message("Hero '%s' has no chain of twenty." % hero.id) \
			.is_equal(20)

## Every fifth step asks for one more hero level than the block before it, and no
## other step asks for anything. A gate anywhere else is a wall the player cannot
## see coming.
func test_the_level_gates_sit_every_fifth_step() -> void:
	var expected := {5: 2, 10: 3, 15: 4}
	for hero_id: StringName in _chains:
		var steps: Array = _chains[hero_id]
		for i in steps.size():
			var def: MissionDef = steps[i]
			assert_int(def.min_hero_level) \
				.override_failure_message("Step %d of %s's chain ('%s') asks for level %d." \
					% [i + 1, hero_id, def.id, def.min_hero_level]) \
				.is_equal(int(expected.get(i, 1)))

## The chain is the only ladder an expedition has. A stray tally gate would be a
## second one, invisible beside it.
func test_no_expedition_carries_a_tally_gate() -> void:
	for def in _expeditions:
		assert_int(def.min_missions_completed) \
			.override_failure_message("Expedition '%s' also gates on the tally." % def.id) \
			.is_zero()

## An expedition's predecessor is derived from its chain's authored order, so a
## hand-written link would be a second answer to the same question.
func test_no_expedition_names_a_required_mission() -> void:
	for def in _expeditions:
		assert_str(String(def.requires_mission_id)) \
			.override_failure_message("Expedition '%s' names a required mission; its chain says which." % def.id) \
			.is_empty()

func test_every_expedition_names_a_real_hero() -> void:
	var ids := {}
	for hero in _heroes:
		ids[hero.id] = true
	for def in _expeditions:
		assert_bool(ids.has(def.hero_id)) \
			.override_failure_message("Expedition '%s' names hero '%s', which does not exist." \
				% [def.id, def.hero_id]) \
			.is_true()

## The payout rule the whole roster is built on: the first three heroes pay one
## currency each, the next three pay two, the last pays all three. A chain that
## quietly started paying a fourth, or the wrong one, is exactly the drift this
## sweep exists to catch.
func test_every_mission_pays_in_its_heros_currencies() -> void:
	for hero: HeroDef in _heroes:
		var allowed := {}
		for currency in hero.payout_currencies:
			allowed[currency.currency_type] = true
		assert_bool(allowed.is_empty()) \
			.override_failure_message("Hero '%s' names no payout currencies." % hero.id) \
			.is_false()
		for def: MissionDef in _chains.get(hero.id, []):
			for payout in def.payouts:
				assert_bool(allowed.has(payout.currency.currency_type)) \
					.override_failure_message("'%s' pays %s, which is not %s's currency." \
						% [def.id, payout.currency.currency_name, hero.id]) \
					.is_true()

## A farm belongs to whichever chain opened it, and pays in that hero's
## currencies for the same reason its expeditions do.
func test_every_farm_pays_in_the_currencies_of_the_chain_that_opened_it() -> void:
	var hero_of := {}
	for def in _expeditions:
		hero_of[def.id] = def.hero_id
	var by_id := {}
	for hero in _heroes:
		by_id[hero.id] = hero
	for farm in _farms:
		var hero: HeroDef = by_id.get(hero_of.get(farm.requires_mission_id, &""))
		if hero == null:
			continue
		var allowed := {}
		for currency in hero.payout_currencies:
			allowed[currency.currency_type] = true
		for payout in farm.payouts:
			assert_bool(allowed.has(payout.currency.currency_type)) \
				.override_failure_message("Farm '%s' pays %s, which is not %s's currency." \
					% [farm.id, payout.currency.currency_name, hero.id]) \
				.is_true()

## Every mission has to be reachable by somebody: a level bar above every
## hero's ceiling is a card that can never be played.
func test_every_mission_is_within_some_heroes_reach() -> void:
	var best := 0
	for hero in _heroes:
		best = maxi(best, hero.base_level_cap)
	for def in _missions:
		assert_int(def.min_hero_level) \
			.override_failure_message("Mission '%s' needs level %d, above every hero's ceiling of %d." \
				% [def.id, def.min_hero_level, best]).is_less_equal(best)

## The bootstrap. Every mission needs a hero to carry it, and the three Ruins
## currencies have exactly one source - a collected mission. So if every hero
## at the front of the roster is priced in one of them, the Ruins can never be
## entered at all: the board sits there with an empty picker and a dead Send
## button, and nothing the player can do anywhere in the game opens it.
##
## Shipped exactly that way once. The end-to-end check missed it by granting
## itself relics before recruiting, which is precisely the step a real save has
## no way to perform.
func test_the_first_hero_is_affordable_before_any_mission_is_run() -> void:
	var mission_only := {}
	for def in _missions:
		for payout in def.payouts:
			if payout.currency != null:
				mission_only[payout.currency.currency_type] = true

	var reachable := false
	for hero in _heroes:
		if hero.min_missions_completed > 0 or hero.recruit_currency == null:
			continue
		if not mission_only.has(hero.recruit_currency.currency_type):
			reachable = true
	assert_bool(reachable).override_failure_message(
		"No hero is both open at zero missions and priced outside the currencies "
		+ "only missions pay - the Ruins cannot be entered.").is_true()

func test_every_hero_is_priced_in_something() -> void:
	for def in _heroes:
		assert_object(def.recruit_currency) \
			.override_failure_message("Hero '%s' has no recruit currency." % def.id).is_not_null()
		assert_object(def.level_currency) \
			.override_failure_message("Hero '%s' has no level currency." % def.id).is_not_null()
		assert_float(def.level_cost_growth) \
			.override_failure_message("Hero '%s' has level cost growth %f, so leveling it never gets dearer." \
				% [def.id, def.level_cost_growth]).is_greater(1.0)
		assert_int(def.base_level_cap) \
			.override_failure_message("Hero '%s' can never be leveled." % def.id).is_greater(0)

func test_heroes_open_in_list_order() -> void:
	for i in range(1, _heroes.size()):
		assert_int(_heroes[i].min_missions_completed) \
			.override_failure_message("Hero '%s' opens at %d, before '%s' at %d." \
				% [_heroes[i].id, _heroes[i].min_missions_completed,
					_heroes[i - 1].id, _heroes[i - 1].min_missions_completed]) \
			.is_greater_equal(_heroes[i - 1].min_missions_completed)

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
