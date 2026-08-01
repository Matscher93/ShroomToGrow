extends GdUnitTestSuite
## Integrity checks over everything authored under data/.
##
## These resources are linked by plain StringName, never by reference, so a
## rename or a typo produces no error at load, no warning at runtime and no
## visible symptom: the effect simply resolves to zero forever. Only a sweep
## like this catches it. Everything here reads the same files and the same
## loader App registers from.

## Every stat some system actually reads. ProductionSystem consumes the first
## five, BiomeSystem the last. An effect naming anything else is inert, so
## adding a stat means adding it here too.
const KNOWN_STATS: Array[StringName] = [
	&"potency_production", &"synergy_production", &"node_production",
	&"biomass_gain", &"tick_rate", &"biome_points",
]

var _nodes: Array[MyceliumNode]
var _biomes: Array[BiomeDef]
var _perks: Array[PerkDef]
var _symbiosis_defs: Array[UpgradeDef]
var _biome_defs: Array[UpgradeDef]

func before_test() -> void:
	_nodes = (load("res://data/mycelium_nodes/res_all_mycelium_nodes.tres") as MyceliumNodes).mycelium_nodes
	_biomes = (load("res://data/biomes/all_biomes.tres") as BiomeList).biomes
	_perks = PerkTree.build(load("res://data/prestige/all_branches.tres") as PerkBranchList)
	_symbiosis_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.SYMBIOSIS_PATH)
	_biome_defs = UpgradeDefLoader.load_all(UpgradeDefLoader.BIOME_PATH)

## Node tiers and biomes both address by StringName, and NODE-scoped effects use
## one field for both, so a target is valid if it names either.
func _scope_targets() -> Dictionary:
	var targets := {}
	for node in _nodes:
		targets[StringName(str(node.node_id))] = true
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
	# A dangling key is invisible: ResolveContext.biome_size() returns 0.0 for an
	# unknown biome, the magnitude is scaled to zero and the upgrade does nothing
	# at any level. The player still pays for it.
	var keys := _biome_keys()
	for def in _all_upgrade_defs():
		for e in def.effects:
			if e.dependency == null or e.dependency.kind != ScalingSourceDef.Kind.BIOME_SIZE:
				continue
			assert_bool(keys.has(e.dependency.key)) \
				.override_failure_message("Upgrade '%s' scales off biome size '%s', which is not a biome. It is dead at every level." \
					% [def.id, e.dependency.key]).is_true()

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
	# cost() is base * growth^(level^exponent). A growth of 1 or less makes the
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
