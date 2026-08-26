extends GdUnitTestSuite
## Unit tests for BonusBreakdown (model/stats/gd_bonus_breakdown.gd).
##
## Hand-built tracks rather than the authored .tres, so a retuned upgrade cannot
## turn a grouping test red. What is asserted is the shape: which resource an
## upgrade lands under, that two tracks writing the same resource both show up as
## sources of it, and that they read in stacking order.

var _symbiosis: UpgradeSystem
var _biome: UpgradeSystem
var _perks: UpgradeSystem
var _production: ProductionSystem

func before_test() -> void:
	_symbiosis = UpgradeSystem.new()
	_biome = UpgradeSystem.new()
	_perks = UpgradeSystem.new()
	_production = ProductionSystem.new(_symbiosis, _biome, _perks, ResolveContext.new())

func _def(id: StringName, display_name: String, stat: StringName,
		op: UpgradeEffectDef.Op, per_level: float) -> UpgradeDef:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	var def := UpgradeDef.new()
	def.id = id
	def.display_name = display_name
	def.effects = [effect]
	return def

func _level(system: UpgradeSystem, def: UpgradeDef, lvl: int) -> void:
	system.register(def)
	system.set_level_for_analysis(def.id, lvl)

func test_an_unlevelled_track_contributes_nothing() -> void:
	_symbiosis.register(_def(&"a", "A", &"node_production", UpgradeEffectDef.Op.INCREASED, 0.1))
	assert_array(BonusBreakdown.build(_production)).is_empty()

func test_two_tracks_on_one_stat_become_two_sources_of_one_resource() -> void:
	_level(_symbiosis, _def(&"a", "A", &"node_production", UpgradeEffectDef.Op.INCREASED, 0.1), 3)
	_level(_perks, _def(&"b", "B", &"node_production", UpgradeEffectDef.Op.MORE, 0.5), 1)

	var groups := BonusBreakdown.build(_production)
	assert_int(groups.size()).is_equal(1)
	var group: Dictionary = groups[0]
	assert_str(str(group["resource"])).is_equal("nutrients")
	assert_int(int(group["upgrade_count"])).is_equal(2)
	# Stacking order, which is the order ProductionSystem.tracks() declares and
	# the order stack() actually applies them in - not dictionary order.
	assert_str(str(group["sources"][0]["track"])).is_equal("symbiosis")
	assert_str(str(group["sources"][1]["track"])).is_equal("prestige")

func test_different_stats_land_under_different_resources() -> void:
	_level(_symbiosis, _def(&"a", "A", &"node_production", UpgradeEffectDef.Op.INCREASED, 0.1), 1)
	_level(_symbiosis, _def(&"t", "T", &"tick_rate", UpgradeEffectDef.Op.INCREASED, 0.1), 1)

	var resources: Array = []
	for group: Dictionary in BonusBreakdown.build(_production):
		resources.append(str(group["resource"]))
	# StatResources.RESOURCES order, not alphabetical and not insertion order.
	assert_array(resources).is_equal(["nutrients", "tick speed"])

func test_a_stat_no_resource_names_gets_one_of_its_own() -> void:
	_level(_symbiosis, _def(&"x", "X", &"invented_stat", UpgradeEffectDef.Op.ADD, 2.0), 1)
	var groups := BonusBreakdown.build(_production)
	assert_int(groups.size()).is_equal(1)
	assert_str(str(groups[0]["resource"])).is_equal("invented_stat")

func test_the_group_total_is_the_resolved_multiplier() -> void:
	_level(_symbiosis, _def(&"a", "A", &"node_production", UpgradeEffectDef.Op.INCREASED, 0.25), 2)
	var groups := BonusBreakdown.build(_production)
	var total: BigNumber = groups[0]["total"]
	# Measured through stack() rather than summed from the rows, so it is exactly
	# what the game reads: 1.0 * (1 + 0.25*2).
	assert_str(total.to_display(2)).is_equal("1.50")
	assert_bool(groups[0]["additive"]).is_false()
	assert_str(str(groups[0]["total_scope"])).is_equal("")

## A node-scoped effect writes a bucket no global read passes through, so a total
## resolved globally left the crystal Nutrient Flow boost - authored against node
## 0 - out of a header printed above the very row listing it.
func test_the_group_total_reaches_a_node_scoped_effect() -> void:
	var scoped := _def(&"boost", "Boost", &"node_production", UpgradeEffectDef.Op.MORE, 3.0)
	scoped.effects[0].scope = UpgradeEffectDef.Scope.NODE
	scoped.effects[0].target = &"0"
	_level(_symbiosis, scoped, 1)

	var groups := BonusBreakdown.build(_production)
	assert_str(str(groups[0]["total_scope"])).is_equal("n:0")
	# 1.0 * (1 + 3.0), which a global resolve never sees at all.
	assert_str((groups[0]["total"] as BigNumber).to_display(2)).is_equal("4.00")

## Tick speed is seconds off an interval, authored as ADDs with a negative
## per_level. There is no multiplier in it and 1.0 is not its base.
func test_an_all_add_resource_totals_as_an_amount_from_zero() -> void:
	_level(_symbiosis, _def(&"t", "T", &"tick_rate", UpgradeEffectDef.Op.ADD, -0.1), 3)
	var groups := BonusBreakdown.build(_production)
	assert_bool(groups[0]["additive"]).is_true()
	assert_str((groups[0]["total"] as BigNumber).to_display(2)).is_equal("-0.30")

func test_the_heaviest_op_sorts_first_within_a_track() -> void:
	_level(_symbiosis, _def(&"add", "Add", &"node_production", UpgradeEffectDef.Op.ADD, 5.0), 1)
	_level(_symbiosis, _def(&"more", "More", &"node_production", UpgradeEffectDef.Op.MORE, 0.1), 1)
	_level(_symbiosis, _def(&"inc", "Inc", &"node_production", UpgradeEffectDef.Op.INCREASED, 0.2), 1)

	var names: Array = []
	for upgrade: Dictionary in BonusBreakdown.build(_production)[0]["sources"][0]["upgrades"]:
		names.append(str(upgrade["name"]))
	assert_array(names).is_equal(["More", "Inc", "Add"])
