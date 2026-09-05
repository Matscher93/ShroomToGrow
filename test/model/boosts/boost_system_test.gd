extends GdUnitTestSuite
## Unit tests for BoostSystem (model/boosts/gd_boost_system.gd).
##
## Built against a hand-authored two-boost list rather than the shipped data, so
## retuning a boost's curves can't turn the rules red. The two test boosts are
## deliberately shaped differently: both curves are authored per boost, and a
## suite where they matched would pass just as well if they were still shared.

const EPS := 0.000001

## How far up the open-ended ladder the sweeps below walk. Not a limit the code
## has - there is no last tier - just far enough to cross several boundaries.
const SAMPLED_TIERS := 6
const SAMPLED_LEVELS := SAMPLED_TIERS * 100

var _player: PlayerData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _list: BoostList
var _prestige: UpgradeSystem
var _system: BoostSystem

func before_test() -> void:
	_player = PlayerData.new()
	_upgrades = UpgradeSystem.new()
	# The prestige track is what gates the boosts. It also resolves stats, which
	# is how the effect tests below see a perk and a boost land on one number.
	_prestige = UpgradeSystem.new()
	_production = ProductionSystem.new(UpgradeSystem.new(), UpgradeSystem.new(),
		_prestige, ResolveContext.new(), _upgrades)
	_list = _boost_list()
	# No pre-registration: BoostSystem opens tier one itself and grows the rest as
	# the ladder climbs, because there is no last tier to register up front.
	_system = BoostSystem.new(_player, _upgrades, _list, _prestige, _production)

## BoostTiers is seeded once at boot and holds its shape statically, so a suite
## that moves it would hand the next one someone else's ladder.
func after_test() -> void:
	BoostTiers.configure(BoostList.new())

## Registers one Well-style upgrade writing `per_level` into `stat`, scoped to a
## boost id the way a project boon reaches a boost. Levelled straight in: what a
## project costs is WellSystem's rule, not this system's.
func _well_upgrade(id: StringName, stat: StringName, boost_id: StringName,
		op: UpgradeEffectDef.Op, per_level: float, level: int) -> void:
	var effect := UpgradeEffectDef.new()
	effect.stat = stat
	effect.op = op
	effect.scope = UpgradeEffectDef.Scope.NODE
	effect.target = boost_id
	effect.per_level = per_level
	var effects: Array[UpgradeEffectDef] = [effect]
	var def := UpgradeDef.new()
	def.id = id
	def.effects = effects
	# The projects track is not one of the five this suite's ProductionSystem
	# folds, so these ride in on the prestige track - the stat is what matters,
	# and every track writes into the same buckets.
	_prestige.register(def)
	_prestige.set_level_for_analysis(id, level)
	_system.refresh_power()

func _boost_list() -> BoostList:
	# Node-scoped to tier 0, mirroring the shipped Nutrient Flow: tier 0 is the
	# only node whose output becomes nutrients.
	var nutrients := BoostDef.new()
	nutrients.id = &"test_nutrients"
	nutrients.display_name = "Test Nutrients"
	nutrients.stat = &"node_production"
	nutrients.scope = UpgradeEffectDef.Scope.NODE
	nutrients.target = &"0"
	nutrients.base_per_level = 0.01
	nutrients.per_level_growth = 5.0
	nutrients.base_cost = 2.0
	nutrients.cost_growth = 1.1
	# The smooth ladder: a tier opens exactly one cost_growth step above where the
	# tier below closed, with no extra step of its own.
	nutrients.tier_cost_growth = 1.0

	# Every curve deliberately different from the one above.
	var biomass := BoostDef.new()
	biomass.id = &"test_biomass"
	biomass.display_name = "Test Biomass"
	biomass.stat = &"biomass_gain"
	biomass.base_per_level = 0.02
	biomass.per_level_growth = 2.0
	biomass.base_cost = 2.0
	biomass.cost_growth = 1.1
	# Same base and same within-tier growth as the one above, so every difference
	# in their openings is this extra step at the boundary and nothing else.
	biomass.tier_cost_growth = 1.5

	var boosts: Array[BoostDef] = [nutrients, biomass]
	var list := BoostList.new()
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
		var at := _system.boost_level(boost_id)
		# buy_boost() grows the ladder on the way past a boundary; granting has to
		# do it too, or the tier being bought into has no def and the grant is a
		# silent no-op.
		_system.ensure_tiers_for_level(boost_id, at)
		_upgrades.buy_with_points(BoostTiers.upgrade_id(boost_id, BoostTiers.tier_for_level(at)), true)

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
	_prestige.set_level_for_analysis(id, level)

## Puts the gate fields on a test boost after the fact, so the shared list stays
## ungated for every other test in the suite.
func _gate(boost_id: StringName, unlock_perk_id: StringName, base_max_level: int,
		cap_perk_id: StringName = &"", per_perk_level: int = 0) -> void:
	var def := _system.boost_def(boost_id)
	def.unlock_perk_id = unlock_perk_id
	def.base_max_level = base_max_level
	def.max_level_perk_id = cap_perk_id
	def.max_level_per_perk_level = per_perk_level

# ---------------------------------------------------------------- boost tiers

func test_the_first_hundred_levels_sit_in_tier_one() -> void:
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(1)
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER - 1)
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(1)

func test_crossing_a_hundred_levels_moves_the_ladder_up_a_tier() -> void:
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER)

	assert_int(_system.boost_level(&"test_nutrients")).is_equal(BoostTiers.LEVELS_PER_TIER)
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(2)

## The ladder is one curve, not a staircase: a tier opens one cost_growth step
## above where the tier below closed, times whatever extra step tier_cost_growth
## asks for.
##
## Pricing off a tier's own counter alone is what made every boundary a discount
## of cost_growth^LEVELS_PER_TIER - and a boundary is also where the payout jumps,
## so the player was paid to cross into the tier worth more.
func test_a_tier_opens_above_where_the_tier_below_closed() -> void:
	var def := _system.boost_def(&"test_nutrients")
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER - 1)
	var tier_one_closing := _system.boost_cost(&"test_nutrients").to_float()

	_grant_levels(&"test_nutrients", 1)

	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(2)
	var tier_two_opening := _system.boost_cost(&"test_nutrients").to_float()
	assert_float(tier_two_opening).is_greater(tier_one_closing)
	# Prices are floored to whole crystals, so the ratio of two of them carries up
	# to a crystal of rounding on each side rather than matching the curve exactly.
	assert_float(tier_two_opening / tier_one_closing).is_equal_approx(
		def.cost_growth * def.tier_cost_growth, 0.001)

## The invariant the restart broke, checked the only way that catches it: against
## the price the tier below *closed* at, not against the one it opened at. Every
## opening was already dearer than the last while the dip was live.
func test_every_tier_opens_above_where_the_one_below_closed() -> void:
	var def := _system.boost_def(&"test_nutrients")
	for tier in range(2, SAMPLED_TIERS + 1):
		var opens_at := (tier - 1) * BoostTiers.LEVELS_PER_TIER
		var opening := def.cost_at(opens_at)
		var closing := def.cost_at(opens_at - 1)
		assert_bool(opening.gt(closing)).override_failure_message(
			"tier %d opens at %s, under the %s tier %d closed at"
				% [tier, opening.to_display(), closing.to_display(), tier - 1]
		).is_true()

## The same property walked one level at a time through the real pricing path,
## which is what a player feels. The per-tier assertions above cannot see a
## boundary the ladder never actually reaches.
func test_the_price_never_falls_as_the_ladder_is_climbed() -> void:
	var previous := 0.0
	for level in range(SAMPLED_LEVELS):
		var price := _system.boost_cost(&"test_nutrients").to_float()
		assert_float(price).override_failure_message(
			"level %d priced %f, under the %f before it" % [level, price, previous]
		).is_greater_equal(previous)
		previous = price
		_grant_levels(&"test_nutrients", 1)

# ------------------------------------------------------- exponential cost curve

## 1.0 leaves the plain geometric ladder every boost shipped with, so the field
## can be added to a def without moving a single price.
func test_an_exponent_of_one_is_the_plain_geometric_ladder() -> void:
	var def := _system.boost_def(&"test_nutrients")
	def.cost_growth_exponent = 1.0

	for level in [0, 1, 50, BoostTiers.LEVELS_PER_TIER, 250]:
		var plain := 2.0 * pow(1.1, float(level))
		# To within the crystal the floor drops: a whole-number price cannot sit on
		# a curve that runs between the integers.
		assert_float(def.cost_at(level).to_float()).is_equal_approx(
			plain, maxf(1.0, plain * 1e-6))

## The exponent raises the level through itself before it becomes cost_growth's
## exponent, so the curve bows upwards instead of running straight in log space.
func test_an_exponent_above_one_steepens_the_ladder() -> void:
	var def := _system.boost_def(&"test_nutrients")
	var plain := def.cost_at(100)

	def.cost_growth_exponent = 1.01

	# Level 0 is untouched - 0 levels raised through anything is still 0 steps.
	assert_float(def.cost_at(0).to_float()).is_equal_approx(def.base_cost, EPS)
	assert_bool(def.cost_at(100).gt(plain)).is_true()

## Bent or straight, the ladder still only ever climbs. The exponent multiplies
## the step count rather than replacing it, so it cannot walk the price back.
func test_an_exponent_never_makes_a_level_cheaper_than_the_one_before() -> void:
	var def := _system.boost_def(&"test_nutrients")
	def.cost_growth_exponent = 1.01

	var previous := def.cost_at(0)
	for level in range(1, SAMPLED_LEVELS):
		var price := def.cost_at(level)
		assert_bool(price.gte(previous)).override_failure_message(
			"level %d priced %s, under the %s before it"
				% [level, price.to_display(), previous.to_display()]
		).is_true()
		previous = price

## An exponent puts the top of this ladder past any float. BigNumber saturates at
## MAX_EXPONENT rather than handing back an inf, which would spread into the
## crystal balance the moment a price was subtracted from it.
func test_a_steep_exponent_saturates_rather_than_overflowing() -> void:
	var def := _system.boost_def(&"test_nutrients")
	def.cost_growth_exponent = 1.5

	var price := def.cost_at(SAMPLED_LEVELS)

	assert_bool(is_finite(price.mantissa)).is_true()
	assert_int(price.exponent).is_less_equal(BigNumber.MAX_EXPONENT)
	assert_bool(price.gt(BigNumber.from_value(1.0))).is_true()

## The ladder's shape is authored on the list rather than fixed in the script, so
## the balance editor can move it. after_test() puts it back.
func test_the_ladder_takes_its_shape_from_the_authored_list() -> void:
	var list := BoostList.new()
	list.levels_per_tier = 10

	BoostTiers.configure(list)

	assert_int(BoostTiers.LEVELS_PER_TIER).is_equal(10)
	assert_int(BoostTiers.tier_for_level(0)).is_equal(1)
	assert_int(BoostTiers.tier_for_level(10)).is_equal(2)

## The tier keeps climbing every LEVELS_PER_TIER levels for good. It used to clamp
## at a last tier, which meant every level a perk opened past the ladder's end was
## bought at the top tier's rate however far past it really was.
func test_the_tier_keeps_climbing_with_no_last_tier() -> void:
	assert_int(BoostTiers.tier_for_level(BoostTiers.LEVELS_PER_TIER * 5)).is_equal(6)
	assert_int(BoostTiers.tier_for_level(BoostTiers.LEVELS_PER_TIER * 99)).is_equal(100)
	# The boundary belongs to the tier above it, and level 0 opens tier 1.
	assert_int(BoostTiers.tier_for_level(0)).is_equal(1)
	assert_int(BoostTiers.tier_for_level(BoostTiers.LEVELS_PER_TIER - 1)).is_equal(1)
	assert_int(BoostTiers.tier_for_level(BoostTiers.LEVELS_PER_TIER)).is_equal(2)

## A tier with no def is a tier whose levels cannot be bought, so the defs have to
## follow the ladder up rather than stopping at a table's end.
func test_the_defs_grow_to_meet_the_tier_being_bought() -> void:
	# Well past where the old five-tier table stopped.
	_gate(&"test_nutrients", &"", 9 * BoostTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e300)

	_grant_levels(&"test_nutrients", 8 * BoostTiers.LEVELS_PER_TIER)

	# Eight tiers were built to hold them, three past where the table used to stop.
	assert_bool(_upgrades.has_def(BoostTiers.upgrade_id(&"test_nutrients", 8))).is_true()
	# Every level is still accounted for, summed across those eight counters.
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(
		8 * BoostTiers.LEVELS_PER_TIER)
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(9)

	# Tier nine is grown by the purchase that needs it, not before.
	assert_bool(_upgrades.has_def(BoostTiers.upgrade_id(&"test_nutrients", 9))).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

	assert_bool(_upgrades.has_def(BoostTiers.upgrade_id(&"test_nutrients", 9))).is_true()
	assert_int(_upgrades.level(BoostTiers.upgrade_id(&"test_nutrients", 9))).is_equal(1)
	# And the rate kept climbing into the tiers the old table had no room for.
	assert_float(_per_level(9)).is_greater(_per_level(5))

## Levels past the old ladder end are bought at the tier they actually land in.
## They used to pile into the top tier, paying its rate however far past it.
func test_a_level_past_the_old_ladder_end_is_bought_at_its_own_tier() -> void:
	_gate(&"test_nutrients", &"", 9 * BoostTiers.LEVELS_PER_TIER)
	_grant_levels(&"test_nutrients", 7 * BoostTiers.LEVELS_PER_TIER)

	assert_float(_system.next_level_gain(&"test_nutrients")).is_equal_approx(
		_per_level(8), EPS)
	assert_int(_upgrades.level(BoostTiers.upgrade_id(&"test_nutrients", 7))) \
		.is_equal(BoostTiers.LEVELS_PER_TIER)

## Null is a no-op rather than a reset: a suite that builds systems without a list
## must keep the authored ladder, not silently inherit whatever ran last.
func test_configuring_from_nothing_leaves_the_ladder_alone() -> void:
	BoostTiers.configure(null)

	assert_int(BoostTiers.LEVELS_PER_TIER).is_equal(100)

## Two copies of the same number: BoostList's default is what a list that never
## authored it hands BoostTiers, so it has to be BoostTiers' own.
func test_the_list_default_is_the_ladders_default() -> void:
	var list := BoostList.new()

	assert_int(list.levels_per_tier).is_equal(BoostTiers.LEVELS_PER_TIER)

func test_each_tier_is_worth_more_per_level_than_the_one_below() -> void:
	var previous := 0.0
	for tier in range(1, SAMPLED_TIERS + 1):
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

	# Both share a base and a per-level growth, so the smooth opening is the same
	# for each and the whole difference is the step they take at the boundary.
	# Compared as a ratio: tier 2 is already five figures here, and an absolute
	# epsilon means nothing at that scale.
	var continuous := 2.0 * pow(1.1, float(BoostTiers.LEVELS_PER_TIER))
	var opens := BoostTiers.LEVELS_PER_TIER
	# Slack of a whole crystal over the continuous price, since floored prices land
	# on the integers rather than on the curve.
	var crystal := 1.0 / continuous
	assert_float(nutrients.cost_at(opens).to_float() / continuous).is_equal_approx(1.0, crystal)
	assert_float(biomass.cost_at(opens).to_float() / continuous).is_equal_approx(1.5, 1.5 * crystal)

func test_the_next_level_gain_follows_the_tier_the_level_lands_in() -> void:
	assert_float(_system.next_level_gain(&"test_nutrients")).is_equal_approx(
		_per_level(1), EPS)
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER)
	assert_float(_system.next_level_gain(&"test_nutrients")).is_equal_approx(
		_per_level(2), EPS)

# ---------------------------------------------------------------- buying

func test_buying_a_level_takes_its_price_out_in_crystals() -> void:
	_player.crystals = _big(100000.0)
	var cost := _system.boost_cost(&"test_nutrients").to_float()

	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

	assert_int(_system.boost_level(&"test_nutrients")).is_equal(1)
	assert_float(_player.crystals.to_float()).is_equal_approx(100000.0 - cost, EPS)

## The authored cost curve is the crystal price, with no exchange step in
## between: the first level of tier 1 costs exactly what the def says.
func test_the_price_is_the_authored_curve_in_crystals() -> void:
	assert_float(_system.boost_cost(&"test_nutrients").to_float()).is_equal_approx(
		_system.boost_def(&"test_nutrients").cost_at(0).to_float(), EPS)

func test_buying_without_the_crystals_to_cover_it_is_refused() -> void:
	_player.crystals = _big(1.0)

	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(0)

func test_a_maxed_ladder_stops_selling_levels() -> void:
	_gate(&"test_nutrients", &"", SAMPLED_LEVELS)
	_grant_levels(&"test_nutrients", SAMPLED_LEVELS)
	_player.crystals = _big(1.0e30)

	assert_bool(_system.is_maxed(&"test_nutrients")).is_true()
	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(SAMPLED_LEVELS)

## A boost that authors no ceiling of its own has none at all now that the ladder
## has no end to fall back on. The price is what stops it, not a table.
func test_a_boost_with_no_authored_ceiling_is_never_maxed() -> void:
	assert_int(_system.max_level(&"test_nutrients")).is_equal(BoostSystem.UNLIMITED)
	assert_bool(_system.is_maxed(&"test_nutrients")).is_false()

	_grant_levels(&"test_nutrients", SAMPLED_LEVELS)

	assert_bool(_system.is_maxed(&"test_nutrients")).is_false()

# ---------------------------------------------------------------- perk gates

func test_a_boost_without_an_unlock_perk_is_open() -> void:
	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_int(_system.max_level(&"test_nutrients")).is_equal(BoostSystem.UNLIMITED)

func test_a_gated_boost_cannot_be_bought_before_its_perk_is_owned() -> void:
	_gate(&"test_nutrients", &"instinct_flow", BoostTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_false()
	assert_bool(_system.can_buy_boost(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(0)

func test_a_gated_boost_opens_once_its_perk_is_owned() -> void:
	_gate(&"test_nutrients", &"instinct_flow", BoostTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)
	_own_perk(&"instinct_flow")

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()

## Each dimension carries its own gate: unlocking one must not open the other.
func test_the_two_boosts_are_gated_separately() -> void:
	_gate(&"test_nutrients", &"instinct_flow", BoostTiers.LEVELS_PER_TIER)
	_gate(&"test_biomass", &"instinct_density", BoostTiers.LEVELS_PER_TIER)
	_own_perk(&"instinct_flow")

	assert_bool(_system.is_unlocked(&"test_nutrients")).is_true()
	assert_bool(_system.is_unlocked(&"test_biomass")).is_false()

func test_the_ladder_stops_at_the_authored_ceiling() -> void:
	_gate(&"test_nutrients", &"", BoostTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		BoostTiers.LEVELS_PER_TIER)
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(BoostTiers.LEVELS_PER_TIER)
	assert_bool(_system.is_maxed(&"test_nutrients")).is_true()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_false()

func test_a_cap_perk_opens_the_next_stretch_of_the_ladder() -> void:
	_gate(&"test_nutrients", &"", BoostTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		BoostTiers.LEVELS_PER_TIER)
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER)
	_player.crystals = _big(1.0e30)
	_own_perk(&"instinct_flow_cap", 2)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(3 * BoostTiers.LEVELS_PER_TIER)
	assert_bool(_system.is_maxed(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	# The level lands in the tier it was bought at, so the rate steps up with it.
	assert_int(_system.boost_tier(&"test_nutrients")).is_equal(2)

## The tiers are what the rates and prices are authored against, so no stack of
## cap perks may buy a level past the end of the table.
func test_perks_alone_stop_at_the_end_of_the_ladder() -> void:
	# The authored cap perks are sized to reach exactly the ladder's end and no
	# further - only a &"boost_max_level" upgrade goes past it, and this suite
	# builds no ProductionSystem, so nothing here can.
	_gate(&"test_nutrients", &"", BoostTiers.LEVELS_PER_TIER, &"instinct_flow_cap",
		BoostTiers.LEVELS_PER_TIER)
	_own_perk(&"instinct_flow_cap", 4)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(
		BoostTiers.LEVELS_PER_TIER * 5)

# ------------------------------------------------- what the Well reaches

func test_boost_max_level_widens_only_the_boost_it_names() -> void:
	_gate(&"test_nutrients", &"", 100)
	_gate(&"test_biomass", &"", 100)
	_well_upgrade(&"WellCeiling", &"boost_max_level", &"test_nutrients",
		UpgradeEffectDef.Op.ADD, 3.0, 10)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(130)
	assert_int(_system.max_level(&"test_biomass")).is_equal(100)

func test_boost_max_level_can_push_past_where_the_perks_stop() -> void:
	# Every level the Well opens lands in the tier it actually falls in, and the
	# ladder grows a tier to hold it rather than clamping to a last one.
	var perk_end := BoostTiers.LEVELS_PER_TIER * 5
	_gate(&"test_nutrients", &"", perk_end)
	_well_upgrade(&"WellCeiling", &"boost_max_level", &"test_nutrients",
		UpgradeEffectDef.Op.ADD, 5.0, 20)

	assert_int(_system.max_level(&"test_nutrients")).is_equal(perk_end + 100)

func test_a_boost_at_the_old_ceiling_becomes_buyable_again() -> void:
	_gate(&"test_nutrients", &"", 2)
	_player.crystals = _big(1.0e12)
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	assert_bool(_system.is_maxed(&"test_nutrients")).is_true()

	_well_upgrade(&"WellCeiling", &"boost_max_level", &"test_nutrients",
		UpgradeEffectDef.Op.ADD, 1.0, 3)

	assert_bool(_system.is_maxed(&"test_nutrients")).is_false()
	assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	assert_int(_system.boost_level(&"test_nutrients")).is_equal(3)

func test_boost_power_raises_the_rate_each_level_is_bought_at() -> void:
	# base_per_level is 0.01 at tier 1 for the nutrient test boost.
	assert_float(_system.per_level(&"test_nutrients", 1)).is_equal_approx(0.01, EPS)

	_well_upgrade(&"WellPower", &"boost_power", &"test_nutrients",
		UpgradeEffectDef.Op.INCREASED, 0.5, 2)   # x2 into the additive pool

	assert_float(_system.power(&"test_nutrients")).is_equal_approx(2.0, EPS)
	assert_float(_system.per_level(&"test_nutrients", 1)).is_equal_approx(0.02, EPS)

func test_boost_power_reaches_the_resolved_stat_not_only_the_display() -> void:
	# The rate is baked into each tier's UpgradeDef, so a power change that only
	# moved boost_multiplier() would show a number the game never applied.
	_player.crystals = _big(1.0e12)
	for _i in 10:
		assert_bool(_system.buy_boost(&"test_nutrients")).is_true()
	var before := _production.stack(&"node_production", _big(1.0), &"0").to_float()

	_well_upgrade(&"WellPower", &"boost_power", &"test_nutrients",
		UpgradeEffectDef.Op.INCREASED, 1.0, 1)   # x2

	var after := _production.stack(&"node_production", _big(1.0), &"0").to_float()
	assert_float(after).is_greater(before)
	# Ten levels at x1.02 rather than at x1.01.
	assert_float(after).is_equal_approx(pow(1.02, 10.0), EPS)
	assert_float(_system.boost_multiplier(&"test_nutrients").to_float()) \
		.is_equal_approx(after, EPS)

func test_boost_power_leaves_the_other_boost_alone() -> void:
	_player.crystals = _big(1.0e12)
	for _i in 5:
		assert_bool(_system.buy_boost(&"test_biomass")).is_true()
	var before := _system.boost_multiplier(&"test_biomass").to_float()

	_well_upgrade(&"WellPower", &"boost_power", &"test_nutrients",
		UpgradeEffectDef.Op.INCREASED, 1.0, 1)

	assert_float(_system.boost_multiplier(&"test_biomass").to_float()) \
		.is_equal_approx(before, EPS)

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
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER + 10)

	var expected := pow(1.0 + _per_level(1), float(BoostTiers.LEVELS_PER_TIER)) \
		* pow(1.0 + _per_level(2), 10.0)
	assert_float(_system.boost_multiplier(&"test_nutrients").to_float()).is_equal_approx(
		expected, EPS)

func test_boost_levels_reach_production_through_the_boost_track() -> void:
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

## The whole reason for op MORE: a boost must not dilute into the additive
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
	_grant_levels(&"test_nutrients", BoostTiers.LEVELS_PER_TIER + 5)

	var saved := _upgrades.to_save()
	var restored := UpgradeSystem.new()
	var restored_system := BoostSystem.new(PlayerData.new(), restored, _list, _prestige)
	# A fresh system opens at tier one. The save reaches tier two, and from_save()
	# drops any id it has no def for, so the tiers are grown from the save's own
	# keys before the levels are read - which is what App does on load.
	restored_system.ensure_tiers_for_save(saved)
	restored.from_save(saved)

	assert_int(restored_system.boost_level(&"test_nutrients")).is_equal(
		BoostTiers.LEVELS_PER_TIER + 5)
	assert_int(restored_system.boost_tier(&"test_nutrients")).is_equal(2)

# ---------------------------------------------------------------- notification

func test_refresh_power_announces_itself_on_the_boost_track() -> void:
	# It rewrites every tier's per_level in place. register() is silent by design,
	# so without the explicit notify the boost cards - which listen to this track,
	# not to the project track that triggers the refresh - kept painting the old
	# multiplier until an unrelated purchase happened along.
	var fired := [0]
	var counter := fired
	_upgrades.upgrades_changed.connect(func() -> void: counter[0] += 1)

	_system.refresh_power()

	assert_int(fired[0]).override_failure_message(
		"refresh_power() emitted nothing, so no boost card repaints."
		).is_greater(0)

func test_refresh_power_collapses_to_a_single_notification() -> void:
	# One per rewritten tier would be dozens of full refreshes for one change,
	# which is what the batch around it is for.
	var fired := [0]
	var counter := fired
	_upgrades.upgrades_changed.connect(func() -> void: counter[0] += 1)

	_system.refresh_power()

	assert_int(fired[0]).is_equal(1)
