extends GdUnitTestSuite
## Unit tests for ProductionSystem (model/gd_production_system.gd).
##
## Built with its dependencies injected and no App autoload, which is the point
## of the extraction.

const EPS := 0.000001

var _symbiosis: UpgradeSystem
var _biome: UpgradeSystem
var _prestige: UpgradeSystem
var _ctx: ResolveContext
var _production: ProductionSystem

func before_test() -> void:
	_symbiosis = UpgradeSystem.new()
	_biome = UpgradeSystem.new()
	_prestige = UpgradeSystem.new()
	_ctx = ResolveContext.new()
	_production = ProductionSystem.new(_symbiosis, _biome, _prestige, _ctx)

func _effect(stat: StringName, per_level: float, op: UpgradeEffectDef.Op,
		scope := UpgradeEffectDef.Scope.GLOBAL, target := &"") -> UpgradeEffectDef:
	var e := UpgradeEffectDef.new()
	e.stat = stat
	e.per_level = per_level
	e.op = op
	e.scope = scope
	e.target = target
	return e

func _node(node_id: int, tags: Array[StringName]) -> MyceliumNode:
	var node := MyceliumNode.new()
	node.node_id = node_id
	node.tags = tags
	return node

## Rebuilds the system over a node list, since the tag index is read once at
## construction. The tracks are kept, so a _register() either side of this call
## still lands in the same place.
func _with_nodes(nodes: Array[MyceliumNode]) -> void:
	_production = ProductionSystem.new(_symbiosis, _biome, _prestige, _ctx,
		null, null, null, null, null, nodes)

func _register(system: UpgradeSystem, id: StringName, effects: Array[UpgradeEffectDef]) -> void:
	var d := UpgradeDef.new()
	d.id = id
	d.effects = effects
	system.register(d)
	system.set_level_for_analysis(id, 1)

func test_each_track_is_resolved_separately() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_biome, &"BioPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	# 1.0 -> symbiosis +100% -> 2.0 -> biome +100% -> 4.0. Both levels landing in
	# one system would make them additive instead: 1 * (1 + 1 + 1) = 3.
	assert_float(_production.node_potency_bonus(&"3").to_float()).is_equal_approx(4.0, EPS)

func test_the_track_order_is_symbiosis_then_biome_then_prestige() -> void:
	# Two INCREASED effects commute across tracks, so they cannot pin the order.
	# ADD and MORE do not: symbiosis +5 -> 6, biome x2 -> 12, prestige +6 -> 18.
	# Any other permutation of the same three effects lands somewhere else.
	_register(_symbiosis, &"SymFlat", [_effect(&"potency_production", 5.0,
		UpgradeEffectDef.Op.ADD, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_biome, &"BioMore", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.MORE, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_prestige, &"PerkFlat", [_effect(&"potency_production", 6.0,
		UpgradeEffectDef.Op.ADD, UpgradeEffectDef.Scope.NODE, &"3")])

	assert_float(_production.node_potency_bonus(&"3").to_float()).is_equal_approx(18.0, EPS)

func test_stack_external_skips_symbiosis_and_keeps_the_remaining_order() -> void:
	# Same three effects as above with the symbiosis leg dropped: base 1, biome
	# x2 -> 2, prestige +6 -> 8. A stale symbiosis +5 would show up as 18.
	_register(_symbiosis, &"SymFlat", [_effect(&"potency_production", 5.0,
		UpgradeEffectDef.Op.ADD, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_biome, &"BioMore", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.MORE, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_prestige, &"PerkFlat", [_effect(&"potency_production", 6.0,
		UpgradeEffectDef.Op.ADD, UpgradeEffectDef.Scope.NODE, &"3")])

	assert_float(_production.node_potency_external_multiplier(&"3").to_float()) \
		.is_equal_approx(8.0, EPS)

func test_bonuses_are_scoped_to_their_node() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	assert_float(_production.node_potency_bonus(&"7").to_float()).is_equal_approx(1.0, EPS)

# ─── Groups ──────────────────────────────────────────────────────────────────

func test_a_tag_bonus_reaches_every_node_carrying_it() -> void:
	_with_nodes([_node(3, [&"canopy"]), _node(7, [&"canopy"]), _node(1, [])])
	_register(_biome, &"Canopy", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.TAG, &"canopy")])

	assert_float(_production.node_potency_bonus(&"3").to_float()).is_equal_approx(2.0, EPS)
	assert_float(_production.node_potency_bonus(&"7").to_float()).is_equal_approx(2.0, EPS)

func test_a_tag_bonus_does_not_reach_an_untagged_node() -> void:
	_with_nodes([_node(3, [&"canopy"]), _node(1, [])])
	_register(_biome, &"Canopy", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.TAG, &"canopy")])

	assert_float(_production.node_potency_bonus(&"1").to_float()).is_equal_approx(1.0, EPS)

## `target` carries biome keys and boost ids as well as node tiers, and only the
## node ones have tags. A biome read must not pick up a node's groups because the
## two share the field.
func test_a_biome_target_is_not_read_as_a_node_tag() -> void:
	_with_nodes([_node(3, [&"canopy"])])
	_register(_prestige, &"Canopy", [_effect(&"biome_points", 5.0,
		UpgradeEffectDef.Op.ADD, UpgradeEffectDef.Scope.TAG, &"canopy")])

	assert_float(_production.stack(&"biome_points", BigNumber.new(0.0, 0), &"forest").to_float()) \
		.is_equal_approx(0.0, EPS)

## The memo is keyed on the target, and a group spans several. Two tiers reading
## the same group must both get it rather than the second one reading the first
## one's cached answer - or missing it because the first read filled the memo.
func test_two_nodes_sharing_a_tag_both_get_it() -> void:
	_with_nodes([_node(3, [&"canopy"]), _node(7, [&"canopy"])])
	_register(_biome, &"Canopy", [_effect(&"node_production", 1.0,
		UpgradeEffectDef.Op.MORE, UpgradeEffectDef.Scope.TAG, &"canopy")])

	assert_float(_production.node_production_bonus(&"3").to_float()).is_equal_approx(2.0, EPS)
	assert_float(_production.node_production_bonus(&"7").to_float()).is_equal_approx(2.0, EPS)

func test_synergy_uses_its_own_stat() -> void:
	_register(_biome, &"Syn", [_effect(&"synergy_production", 2.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"1")])
	assert_float(_production.node_synergy_bonus(&"1").to_float()).is_equal_approx(3.0, EPS)
	assert_float(_production.node_synergy_external_multiplier(&"1").to_float()) \
		.is_equal_approx(3.0, EPS)

func test_node_production_folds_potency_and_synergy() -> void:
	_register(_symbiosis, &"Pot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"2")])
	_register(_symbiosis, &"Syn", [_effect(&"synergy_production", 2.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"2")])
	# potency 2.0 * synergy 3.0, with no node_production effects on top
	assert_float(_production.node_production_bonus(&"2").to_float()).is_equal_approx(6.0, EPS)

func test_no_upgrades_is_a_neutral_multiplier() -> void:
	assert_float(_production.node_production_bonus(&"0").to_float()).is_equal_approx(1.0, EPS)

func test_tick_duration_applies_the_discount() -> void:
	_register(_prestige, &"Tick", [_effect(&"tick_rate", -0.5, UpgradeEffectDef.Op.MORE)])
	assert_float(_production.tick_duration(10.0, 1.0)).is_equal_approx(5.0, EPS)

func test_tick_duration_respects_the_floor() -> void:
	# The floor is what stops a stacked discount reaching or crossing zero.
	_register(_prestige, &"Tick", [_effect(&"tick_rate", -0.99, UpgradeEffectDef.Op.MORE)])
	assert_float(_production.tick_duration(10.0, 8.0)).is_equal_approx(8.0, EPS)

func test_tick_duration_unmodified_returns_base() -> void:
	assert_float(_production.tick_duration(10.0, 1.0)).is_equal_approx(10.0, EPS)

func test_biomass_gain_ignores_symbiosis() -> void:
	# Symbiosis levels are wiped by the prestige this gain is paying for, so
	# they must not inflate it.
	_register(_symbiosis, &"SymBio", [_effect(&"biomass_gain", 9.0, UpgradeEffectDef.Op.INCREASED)])
	_register(_biome, &"BioBio", [_effect(&"biomass_gain", 1.0, UpgradeEffectDef.Op.INCREASED)])
	assert_float(_production.modify_biomass_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(2.0, EPS)

# ─── Introspection, for the balance tools ────────────────────────────────────

func test_tracks_are_named_in_stacking_order() -> void:
	# The order is part of how a stat resolves, so the tools have to show it in
	# the order stack() applies it.
	var names: Array = []
	for pair: Array in _production.tracks():
		names.append(pair[0])
	assert_array(names).is_equal(["symbiosis", "biome", "prestige", "boosts",
		"projects", "growth", "fertilizer", "missions"])

func test_tracks_hand_out_the_systems_they_were_built_with() -> void:
	var by_name := {}
	for pair: Array in _production.tracks():
		by_name[pair[0]] = pair[1]
	assert_object(by_name["symbiosis"]).is_same(_symbiosis)
	assert_object(by_name["biome"]).is_same(_biome)
	assert_object(by_name["prestige"]).is_same(_prestige)

func test_breakdown_keys_every_track_by_name() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])

	var rows: Dictionary = _production.breakdown()

	# Every track, not just the ones with something in them.
	assert_int(rows.size()).is_equal(_production.tracks().size())
	assert_int((rows["symbiosis"] as Array).size()).is_equal(1)
	assert_str((rows["symbiosis"] as Array)[0]["id"]).is_equal("SymPot")
	# A track with nothing bought is present and empty, not absent - the table
	# reading this should say "nothing here yet", not skip the heading.
	assert_int((rows["growth"] as Array).size()).is_zero()

# ─── Fertilizer track ────────────────────────────────────────────────────────

## Built locally rather than in before_test(), so the tests above keep exercising
## the four-argument constructor the extraction is about.
func _with_fertilizer() -> Array:
	var fertilizer := UpgradeSystem.new()
	var production := ProductionSystem.new(_symbiosis, _biome, _prestige, _ctx,
		null, null, null, fertilizer)
	return [production, fertilizer]

func test_the_fertilizer_track_reaches_stack() -> void:
	var pair := _with_fertilizer()
	var production: ProductionSystem = pair[0]
	_register(pair[1], &"FertSoil", [_effect(&"node_production", 1.0,
		UpgradeEffectDef.Op.MORE, UpgradeEffectDef.Scope.NODE, &"0")])
	assert_float(production.node_production_bonus(&"0").to_float()) \
		.is_equal_approx(2.0, EPS)

## biomass_gain and crystal_gain resolve *only* through stack_external, so a
## track missing from it is half-disabled in a way stack() alone cannot show.
func test_the_fertilizer_track_reaches_stack_external() -> void:
	var pair := _with_fertilizer()
	var production: ProductionSystem = pair[0]
	_register(pair[1], &"FertBloom", [_effect(&"crystal_gain", 1.0,
		UpgradeEffectDef.Op.MORE)])
	assert_float(production.modify_crystal_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(2.0, EPS)

func test_the_fertilizer_track_moves_the_memo_version() -> void:
	# Without this the first resolved value would be handed back forever, and a
	# bought upgrade would appear to do nothing until another track moved.
	var pair := _with_fertilizer()
	var production: ProductionSystem = pair[0]
	var fertilizer: UpgradeSystem = pair[1]
	assert_float(production.modify_water_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(1.0, EPS)
	_register(fertilizer, &"FertBloom", [_effect(&"water_production", 1.0,
		UpgradeEffectDef.Op.MORE)])
	assert_float(production.modify_water_gain(BigNumber.from_value(1.0)).to_float()) \
		.is_equal_approx(2.0, EPS)
