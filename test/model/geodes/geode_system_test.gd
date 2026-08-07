extends GdUnitTestSuite
## Unit tests for GeodeSystem (model/geodes/gd_geode_system.gd).
##
## Built against a hand-authored two-boost list rather than the shipped data, so
## retuning a boost's curves can't turn the rules red. The two test boosts are
## deliberately shaped differently: both curves are authored per boost, and a
## suite where they matched would pass just as well if they were still shared.

const EPS := 0.000001

var _player: PlayerData
var _upgrades: UpgradeSystem
var _conversion_upgrades: UpgradeSystem
var _production: ProductionSystem
var _list: GeodeBoostList
var _prestige: UpgradeSystem
var _system: GeodeSystem

func before_test() -> void:
	_player = PlayerData.new()
	_upgrades = UpgradeSystem.new()
	# The track a future "geodes cost fewer crystals" upgrade would live in. Kept
	# separate from the boost track so a discount test can't accidentally lean on
	# the boost defs.
	_conversion_upgrades = UpgradeSystem.new()
	# The prestige track sits in both places it does in App: it gates the boosts
	# and it resolves stats, which is what lets a perk discount the conversion.
	_prestige = UpgradeSystem.new()
	_production = ProductionSystem.new(_conversion_upgrades, UpgradeSystem.new(),
		_prestige, ResolveContext.new(), _upgrades)
	_list = _boost_list()
	for def in GeodeBoostTree.build(_list):
		_upgrades.register(def)
	_system = GeodeSystem.new(_player, _upgrades, _production, _list, _prestige)

func _boost_list() -> GeodeBoostList:
	# Node-scoped to tier 0, mirroring the shipped Nutrient Flow: tier 0 is the
	# only node whose output becomes nutrients.
	var nutrients := GeodeBoostDef.new()
	nutrients.id = &"test_nutrients"
	nutrients.display_name = "Test Nutrients"
	nutrients.stat = &"node_production"
	nutrients.scope = UpgradeEffectDef.Scope.NODE
	nutrients.target = &"0"
	nutrients.base_per_level = 0.01
	nutrients.per_level_growth = 5.0
	nutrients.base_cost = 2.0
	nutrients.cost_growth = 1.1
	nutrients.tier_cost_growth = 10.0

	# Every curve deliberately different from the one above.
	var biomass := GeodeBoostDef.new()
	biomass.id = &"test_biomass"
	biomass.display_name = "Test Biomass"
	biomass.stat = &"biomass_gain"
	biomass.base_per_level = 0.02
	biomass.per_level_growth = 2.0
	biomass.base_cost = 2.0
	biomass.cost_growth = 1.1
	biomass.tier_cost_growth = 3.0

	var boosts: Array[GeodeBoostDef] = [nutrients, biomass]
	var list := GeodeBoostList.new()
	list.boosts = boosts
	return list

## The nutrient boost's per-level rate, which most of the effect tests measure
## against. Read back off the def so it follows the authored curve.
func _per_level(tier: int) -> float:
	return _system.boost_def(&"test_nutrients").per_level(tier)

## Levels a boost without paying, for the tests that care about where on the
## ladder the player stands rather than how they got there.
func _grant_levels(boost_id: StringName, levels: int) -> void:
	for i in range(levels):
		var tier := GeodeTiers.tier_for_level(_system.boost_level(boost_id))
		_upgrades.buy_with_points(GeodeTiers.upgrade_id(boost_id, tier), true)

## Registers a &"geode_conversion" upgrade at one level, standing in for the
## discounts this system is built to accept later.
func _register_discount(per_level: float) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"geode_conversion"
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = &"discount"
	def.effects = effects
	_conversion_upgrades.register(def)
	_conversion_upgrades.buy_with_points(&"discount", true)

func _big(value: float) -> BigNumber:
	return BigNumber.from_value(value)

## Perk levels are set straight on the prestige UpgradeSystem, as the node and
## automation gate tests do: what a perk costs is PerkSystem's rule, not this
## system's.
func _own_perk(id: StringName, level: int = 1) -> void:
	var def := PerkDef.new()
	def.id = id
	def.max_level = level
	_prestige.register(def)
	_prestige.from_save({String(id): level})

## A &"geode_conversion" perk at `levels`, standing in for Softer Stone. Negative
## per_level is what makes it a discount - the stat is crystals *per geode*.
func _own_conversion_perk(per_level: float, levels: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = &"geode_conversion"
	effect.op = UpgradeEffectDef.Op.INCREASED
	effect.scope = UpgradeEffectDef.Scope.GLOBAL
	effect.per_level = per_level
	var effects: Array[UpgradeEffectDef] = [effect]
	var def := PerkDef.new()
	def.id = &"instinct_conversion"
	def.max_level = levels
	def.effects = effects
	_prestige.register(def)
	_prestige.from_save({"instinct_conversion": levels})

## Puts the gate fields on a test boost after the fact, so the shared list stays
## ungated for every other test in the suite.
func _gate(boost_id: StringName, unlock_perk_id: StringName, base_max_level: int,
		cap_perk_id: StringName = &"", per_perk_level: int = 0) -> void:
	var def := _system.boost_def(boost_id)
	def.unlock_perk_id = unlock_perk_id
	def.base_max_level = base_max_level
	def.max_level_perk_id = cap_perk_id
	def.max_level_per_perk_level = per_perk_level

# ---------------------------------------------------------------- conversion

func test_the_standard_rate_is_a_hundred_crystals_to_the_geode() -> void:
	assert_float(_system.conversion_rate().to_float()).is_equal_approx(100.0, EPS)

func test_the_geode_count_is_the_crystal_balance_restated() -> void:
	_player.crystals = _big(1000.0)

	assert_float(_system.available_geodes().to_float()).is_equal_approx(10.0, EPS)

func test_a_part_worn_geode_does_not_count() -> void:
	_player.crystals = _big(1099.0)

	assert_float(_system.available_geodes().to_float()).is_equal_approx(10.0, EPS)

func test_a_conversion_upgrade_makes_geodes_cheaper() -> void:
	_register_discount(-0.25)

	assert_float(_system.conversion_rate().to_float()).is_equal_approx(75.0, EPS)

func test_a_stacked_discount_can_never_make_geodes_free() -> void:
	_register_discount(-5.0)

	assert_float(_system.conversion_rate().to_float()).is_equal_approx(
		GeodeTiers.MIN_CRYSTALS_PER_GEODE, EPS)

func test_a_cheaper_rate_stretches_the_same_crystals_further() -> void:
	_player.crystals = _big(1000.0)
	_register_discount(-0.5)

	assert_float(_system.available_geodes().to_float()).is_equal_approx(20.0, EPS)

# ---------------------------------------------------------------- boost tiers

func test_the_first_hundred_levels_sit_in_tier_one() -> void:
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(1)
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER - 1)
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(1)

func test_crossing_a_hundred_levels_moves_the_ladder_up_a_tier() -> void:
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER)

	assert_int(_system.boost_level(&"test_nutrients")).is_equal(GeodeTiers.LEVELS_PER_TIER)
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(2)

## The within-tier curve restarts at each boundary, but from a higher opening
## price - otherwise tier 5, worth orders of magnitude more per level, would open
## at exactly what tier 1 did.
func test_crossing_a_tier_boundary_restarts_the_curve_at_a_higher_price() -> void:
	var def := _system.boost_def(&"test_nutrients")
	var first_level_cost := _system.boost_cost(&"test_nutrients").to_float()
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER)

	var tier_two_opening := _system.boost_cost(&"test_nutrients").to_float()
	assert_float(tier_two_opening).is_equal_approx(first_level_cost * def.tier_cost_growth, EPS)
	assert_float(tier_two_opening).is_greater(first_level_cost)

func test_every_tier_opens_dearer_than_the_one_below() -> void:
	var def := _system.boost_def(&"test_nutrients")
	var previous := 0.0
	for tier in range(1, GeodeTiers.MAX_TIER + 1):
		var opening := def.tier_base_cost(tier)
		assert_float(opening).is_greater(previous)
		previous = opening

func test_each_tier_is_worth_more_per_level_than_the_one_below() -> void:
	var previous := 0.0
	for tier in range(1, GeodeTiers.MAX_TIER + 1):
		var per_level := _per_level(tier)
		assert_float(per_level).is_greater(previous)
		previous = per_level

func test_the_first_two_tiers_are_the_authored_rates() -> void:
	assert_float(_per_level(1)).is_equal_approx(0.01, EPS)
	assert_float(_per_level(2)).is_equal_approx(0.05, EPS)

## Both curves belong to the boost, not to the ladder: two boosts on the same
## tier can be worth different amounts and open at different prices.
func test_each_boost_carries_its_own_curves() -> void:
	var nutrients := _system.boost_def(&"test_nutrients")
	var biomass := _system.boost_def(&"test_biomass")

	assert_float(nutrients.per_level(2)).is_equal_approx(0.05, EPS)   # 0.01 x 5
	assert_float(biomass.per_level(2)).is_equal_approx(0.04, EPS)     # 0.02 x 2
	assert_float(nutrients.tier_base_cost(2)).is_equal_approx(20.0, EPS)  # 2 x 10
	assert_float(biomass.tier_base_cost(2)).is_equal_approx(6.0, EPS)     # 2 x 3

func test_the_next_level_gain_follows_the_tier_the_level_lands_in() -> void:
	assert_float(_system.next_level_gain(&"test_nutrients")).is_equal_approx(
		_per_level(1), EPS)
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER)
	assert_float(_system.next_level_gain(&"test_nutrients")).is_equal_approx(
		_per_level(2), EPS)

# ---------------------------------------------------------------- buying

func test_buying_a_level_melts_the_crystals_the_price_is_worth() -> void:
	_player.crystals = _big(100000.0)
	var crystal_cost := _system.boost_crystal_cost(&"test_nutrients").to_float()

	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

	assert_int(_system.boost_level(&"test_nutrients")).is_equal(1)
	assert_float(_player.crystals.to_float()).is_equal_approx(100000.0 - crystal_cost, EPS)

func test_the_crystal_price_is_the_geode_price_at_the_current_rate() -> void:
	var geodes := _system.boost_cost(&"test_nutrients").to_float()

	assert_float(_system.boost_crystal_cost(&"test_nutrients").to_float()).is_equal_approx(
		geodes * 100.0, EPS)

func test_a_discount_makes_the_same_level_cost_fewer_crystals() -> void:
	var full_price := _system.boost_crystal_cost(&"test_nutrients").to_float()
	_register_discount(-0.5)

	assert_float(_system.boost_crystal_cost(&"test_nutrients").to_float()).is_equal_approx(
		full_price * 0.5, EPS)

func test_buying_without_the_crystals_to_cover_it_is_refused() -> void:
	_player.crystals = _big(1.0)

	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(0)

func test_a_maxed_ladder_stops_selling_levels() -> void:
	_grant_levels(&"test_nutrients", GeodeTiers.max_level())
	_player.crystals = _big(1.0e30)

	assert_bool(_system.is_maxed(&"test_nutrients")).is_true()
	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(GeodeTiers.max_level())

## The shipped discount is a perk, not a biome upgrade, so it has to reach the
## rate through the prestige track specifically.
func test_a_conversion_perk_makes_every_boost_cheaper() -> void:
	var full_price := _system.boost_crystal_cost(&"test_nutrients").to_float()
	_own_conversion_perk(-0.1, 5)

	assert_float(_system.conversion_rate().to_float()).is_equal_approx(50.0, EPS)
	assert_float(_system.boost_crystal_cost(&"test_nutrients").to_float()).is_equal_approx(
		full_price * 0.5, EPS)

## The floor is what stops a stacked discount handing out boost levels for
## nothing, so a perk deep enough to cross it must land on the floor instead.
func test_a_conversion_perk_cannot_drive_the_rate_below_the_floor() -> void:
	_own_conversion_perk(-0.5, 5)

	assert_float(_system.conversion_rate().to_float()).is_equal_approx(
		GeodeTiers.MIN_CRYSTALS_PER_GEODE, EPS)

# ---------------------------------------------------------------- perk gates

func test_a_boost_without_an_unlock_perk_is_open() -> void:
	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_int(_system.max_level(&"test_nutrients")).is_equal(GeodeTiers.max_level())

func test_a_gated_boost_cannot_be_bought_before_its_perk_is_owned() -> void:
	_gate(&"test_nutrients", &"instinct_flow", GeodeTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_false()
	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(0)

func test_a_gated_boost_opens_once_its_perk_is_owned() -> void:
	_gate(&"test_nutrients", &"instinct_flow", GeodeTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)
	_own_perk(&"instinct_flow")

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

## Each dimension carries its own gate: unlocking one must not open the other.
func test_the_two_boosts_are_gated_separately() -> void:
	_gate(&"test_nutrients", &"instinct_flow", GeodeTiers.LEVELS_PER_TIER)
	_gate(&"test_biomass", &"instinct_density", GeodeTiers.LEVELS_PER_TIER)
	_own_perk(&"instinct_flow")

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_bool(_system.is_unlocked(&"test_biomass")).is_false()

func test_the_ladder_stops_at_the_authored_ceiling() -> void:
	_gate(&"test_nutrients", &"", GeodeTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		GeodeTiers.LEVELS_PER_TIER)
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(GeodeTiers.LEVELS_PER_TIER)
	assert_bool(_system.is_maxed(&"test_nutrients")).is_true()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()

func test_a_cap_perk_opens_the_next_stretch_of_the_ladder() -> void:
	_gate(&"test_nutrients", &"", GeodeTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		GeodeTiers.LEVELS_PER_TIER)
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)
	_own_perk(&"instinct_flow_cap", 2)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(3 * GeodeTiers.LEVELS_PER_TIER)
	assert_bool(_system.is_maxed(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	# The level lands in the tier it was bought at, so the rate steps up with it.
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(2)

## The tiers are what the rates and prices are authored against, so no stack of
## cap perks may buy a level past the end of the table.
func test_the_ceiling_never_passes_the_end_of_the_ladder() -> void:
	_gate(&"test_nutrients", &"", GeodeTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		GeodeTiers.LEVELS_PER_TIER)
	_own_perk(&"instinct_flow_cap", 50)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(GeodeTiers.max_level())

func test_the_two_boosts_keep_separate_ladders() -> void:
	_player.crystals = _big(100000.0)

	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

	assert_int(_system.boost_level(&"test_nutrients")).is_equal(1)
	assert_int(_system.boost_level(&"test_biomass")).is_equal(0)

# ---------------------------------------------------------------- effect

func test_levels_compound_instead_of_adding_up() -> void:
	_grant_levels(&"test_nutrients", 10)

	# 1.01^10, not 1 + 0.01*10. The gap is small at ten levels and is the whole
	# point of the ladder at five hundred.
	var expected := pow(1.0 + _per_level(1), 10.0)
	assert_float(_system.boost_multiplier(&"test_nutrients").to_float()).is_equal_approx(
		expected, EPS)
	assert_float(_system.boost_multiplier(&"test_nutrients").to_float()).is_greater(
		1.0 + _per_level(1) * 10.0)

func test_every_tier_compounds_into_the_same_product() -> void:
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER + 10)

	var expected := pow(1.0 + _per_level(1), float(GeodeTiers.LEVELS_PER_TIER)) \
		* pow(1.0 + _per_level(2), 10.0)
	assert_float(_system.boost_multiplier(&"test_nutrients").to_float()).is_equal_approx(
		expected, EPS)

func test_boost_levels_reach_production_through_the_geode_track() -> void:
	_grant_levels(&"test_nutrients", 10)
	_grant_levels(&"test_biomass", 10)

	var node_bonus := _production.node_production_bonus(&"0").to_float()
	var biomass_bonus := _production.modify_biomass_gain(BigNumber.from_value(1.0)).to_float()

	# Each boost's own curve, not a shared one - the two test boosts differ.
	var biomass_per_level := _system.boost_def(&"test_biomass").per_level(1)
	assert_float(node_bonus).is_equal_approx(pow(1.0 + _per_level(1), 10.0), EPS)
	assert_float(biomass_bonus).is_equal_approx(pow(1.0 + biomass_per_level, 10.0), EPS)

## The nutrient boost has to land once, on the step that produces nutrients. A
## global &"node_production" boost would multiply every tier's feed as well, and
## the cascade would compound it once per tier before it ever reached nutrients.
func test_the_nutrient_boost_leaves_the_feeder_tiers_alone() -> void:
	_grant_levels(&"test_nutrients", 10)

	assert_float(_production.node_production_bonus(&"0").to_float()).is_equal_approx(
		pow(1.0 + _per_level(1), 10.0), EPS)
	for tier_id in [&"1", &"2", &"9"]:
		assert_float(_production.node_production_bonus(tier_id).to_float()).is_equal_approx(
			1.0, EPS)

## The whole reason for op MORE: a geode boost must not dilute into the additive
## pool an INCREASED upgrade on the same stat shares.
func test_the_boost_multiplies_on_top_of_an_additive_upgrade_rather_than_joining_it() -> void:
	var symbiosis := UpgradeSystem.new()
	var additive_effect := UpgradeEffectDef.new()
	additive_effect.stat = &"node_production"
	additive_effect.op = UpgradeEffectDef.Op.INCREASED
	additive_effect.scope = UpgradeEffectDef.Scope.GLOBAL
	additive_effect.per_level = 1.0
	var effects: Array[UpgradeEffectDef] = [additive_effect]
	var additive := UpgradeDef.new()
	additive.id = &"additive"
	additive.effects = effects
	symbiosis.register(additive)
	symbiosis.buy_with_points(&"additive", true)

	var production := ProductionSystem.new(symbiosis, UpgradeSystem.new(),
		UpgradeSystem.new(), ResolveContext.new(), _upgrades)
	_grant_levels(&"test_nutrients", 10)

	var expected := 2.0 * pow(1.0 + _per_level(1), 10.0)
	assert_float(production.node_production_bonus(&"0").to_float()).is_equal_approx(expected, EPS)

# ---------------------------------------------------------------- save

func test_boost_levels_round_trip_through_the_upgrade_track() -> void:
	_grant_levels(&"test_nutrients", GeodeTiers.LEVELS_PER_TIER + 5)

	var restored := UpgradeSystem.new()
	for def in GeodeBoostTree.build(_list):
		restored.register(def)
	restored.from_save(_upgrades.to_save())
	var restored_system := GeodeSystem.new(PlayerData.new(), restored, _production, _list,
		_prestige)

	assert_int(restored_system.boost_level(&"test_nutrients")).is_equal(
		GeodeTiers.LEVELS_PER_TIER + 5)
	assert_int(restored_system.boost_tier(&"test_nutrients")).is_equal(2)
