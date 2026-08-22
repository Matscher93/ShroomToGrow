extends GdUnitTestSuite
## Unit tests for FertilizerTree (model/fertilizer/gd_fertilizer_tree.gd).
##
## Built against hand-made defs rather than the shipped data, so retuning an
## authored fertilizer upgrade cannot turn the rules red.

const EPS := 0.000001

var _producers: GrowthProducerList

func before_test() -> void:
	_producers = GrowthProducerList.new()
	_producers.producers = [
		_producer(CurrencyTypes.Types.NUTRIENTS, &"node_production",
			UpgradeEffectDef.Scope.NODE, &"0"),
		_producer(CurrencyTypes.Types.WATER, &"water_production",
			UpgradeEffectDef.Scope.GLOBAL, &""),
		_producer(CurrencyTypes.Types.BIOMASS, &"biomass_gain",
			UpgradeEffectDef.Scope.GLOBAL, &""),
		_producer(CurrencyTypes.Types.CRYSTALS, &"crystal_gain",
			UpgradeEffectDef.Scope.GLOBAL, &""),
	]

func _currency(type: CurrencyTypes.Types) -> CurrencyDef:
	var def := CurrencyDef.new()
	def.currency_type = type
	def.currency_name = "Test"
	return def

func _producer(type: CurrencyTypes.Types, stat: StringName,
		scope: UpgradeEffectDef.Scope, target: StringName) -> GrowthProducerDef:
	var def := GrowthProducerDef.new()
	def.currency = _currency(type)
	def.stat = stat
	def.scope = scope
	def.target = target
	return def

func _upgrade(id: StringName, types: Array, per_level: float,
		base_cost: float) -> FertilizerUpgradeDef:
	var def := FertilizerUpgradeDef.new()
	def.id = id
	def.display_name = "Test"
	def.per_level = per_level
	def.base_cost = base_cost
	def.cost_growth = 2.0
	var currencies: Array[CurrencyDef] = []
	for type: CurrencyTypes.Types in types:
		currencies.append(_currency(type))
	def.currencies = currencies
	return def

func _list(upgrades: Array[FertilizerUpgradeDef]) -> FertilizerUpgradeList:
	var list := FertilizerUpgradeList.new()
	list.upgrades = upgrades
	return list

# ---------------------------------------------------------------- effects

func test_one_effect_per_listed_currency() -> void:
	var defs := FertilizerTree.build(_list([_upgrade(&"f1",
		[CurrencyTypes.Types.NUTRIENTS, CurrencyTypes.Types.BIOMASS], 0.2, 4.0)]), _producers)
	assert_int(defs.size()).is_equal(1)
	assert_int(defs[0].effects.size()).is_equal(2)

func test_effect_copies_the_producers_stat_scope_and_target() -> void:
	var defs := FertilizerTree.build(_list([_upgrade(&"f1",
		[CurrencyTypes.Types.NUTRIENTS], 0.1, 3.0)]), _producers)
	var effect := defs[0].effects[0]
	assert_str(String(effect.stat)).is_equal("node_production")
	assert_int(effect.scope).is_equal(UpgradeEffectDef.Scope.NODE)
	assert_str(String(effect.target)).is_equal("0")

## MORE + LINEAR, so n levels resolve as exactly 1 + per_level*n rather than
## pooling into the shared additive bucket.
func test_effect_is_more_and_linear() -> void:
	var defs := FertilizerTree.build(_list([_upgrade(&"f1",
		[CurrencyTypes.Types.WATER], 0.25, 5.0)]), _producers)
	var effect := defs[0].effects[0]
	assert_int(effect.op).is_equal(UpgradeEffectDef.Op.MORE)
	assert_int(effect.level_scaling).is_equal(UpgradeEffectDef.LevelScaling.LINEAR)
	assert_float(effect.per_level).is_equal_approx(0.25, EPS)

func test_a_currency_no_producer_covers_is_skipped_not_fatal() -> void:
	_producers.producers = [_producer(CurrencyTypes.Types.NUTRIENTS, &"node_production",
		UpgradeEffectDef.Scope.NODE, &"0")]
	var defs := FertilizerTree.build(_list([_upgrade(&"f1",
		[CurrencyTypes.Types.NUTRIENTS, CurrencyTypes.Types.CRYSTALS], 0.1, 3.0)]), _producers)
	assert_int(defs.size()).is_equal(1)
	assert_int(defs[0].effects.size()).is_equal(1)

func test_a_null_list_builds_nothing() -> void:
	assert_int(FertilizerTree.build(null, _producers).size()).is_equal(0)

# ---------------------------------------------------------------- cost ladder

func test_cost_doubles_with_every_level() -> void:
	var track := UpgradeSystem.new()
	for def in FertilizerTree.build(_list([_upgrade(&"f1",
			[CurrencyTypes.Types.NUTRIENTS], 0.1, 3.0)]), _producers):
		track.register(def)
	var player := PlayerData.new()
	player.fertilizer = BigNumber.from_value(1000.0)
	for level in 6:
		assert_float(track.cost(&"f1").to_float()).is_equal_approx(3.0 * pow(2.0, level), EPS)
		assert_bool(track.buy(&"f1", player, &"fertilizer")).is_true()
