extends GdUnitTestSuite
## Unit tests for ProductionSystem (model/gd_production_system.gd).
##
## Built with its dependencies injected and no App autoload in sight — that is
## the whole point of the extraction.

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

func _register(system: UpgradeSystem, id: StringName, effects: Array[UpgradeEffectDef]) -> void:
	var d := UpgradeDef.new()
	d.id = id
	d.effects = effects
	system.register(d)
	system.from_save({String(id): 1})

func test_stack_runs_all_three_tracks_in_order() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_biome, &"BioPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	# 1.0 -> symbiosis +100% -> 2.0 -> biome +100% -> 4.0
	assert_float(_production.node_potency_bonus(&"3").to_float()).is_equal_approx(4.0, EPS)

func test_stack_external_skips_symbiosis() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	_register(_biome, &"BioPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	assert_float(_production.node_potency_external_multiplier(&"3").to_float()) \
		.is_equal_approx(2.0, EPS)

func test_bonuses_are_scoped_to_their_node() -> void:
	_register(_symbiosis, &"SymPot", [_effect(&"potency_production", 1.0,
		UpgradeEffectDef.Op.INCREASED, UpgradeEffectDef.Scope.NODE, &"3")])
	assert_float(_production.node_potency_bonus(&"7").to_float()).is_equal_approx(1.0, EPS)

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
