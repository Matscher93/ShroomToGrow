class_name GeodeSystem
extends RefCounted
## MODEL: the geode economy's rules - what a boost level costs and what that
## costs in crystals.
##
## A geode is a pricing unit, not a balance: there is nothing to hold and nothing
## to spend ahead of time. Boost levels are priced in geodes, and buying one
## melts exactly the crystals that many geodes are worth, at conversion_rate().
## That rate is a stat, so an upgrade lowering &"geode_conversion" makes every
## boost cheaper without any of this changing.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Boost levels live in a plain UpgradeSystem (one def per boost per
## tier, built by GeodeBoostTree), which is what makes the boosts stack through
## ProductionSystem without any per-stat wiring here.

## Above this exponent a BigNumber has no fractional part left to drop and
## to_float() would lose precision trying, so _floor() hands it back untouched.
## Matches AchievementSystem's rounding guard.
const _INTEGRAL_EXPONENT := 15

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _boosts: Array[GeodeBoostDef] = []
var _by_id: Dictionary = {}   # StringName -> GeodeBoostDef

func _init(player_data: PlayerData, upgrades: UpgradeSystem, production: ProductionSystem,
		list: GeodeBoostList) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_production = production
	if list != null:
		_boosts = list.boosts
	for boost in _boosts:
		_by_id[boost.id] = boost

# ---------------------------------------------------------------- conversion

## Crystals melted per geode right now, after every &"geode_conversion" upgrade.
## Floored at MIN_CRYSTALS_PER_GEODE so a stacked discount can never make geodes
## free.
func conversion_rate() -> BigNumber:
	return BigNumber.from_value(_production.geode_conversion_rate(
		GeodeTiers.CRYSTALS_PER_GEODE, GeodeTiers.MIN_CRYSTALS_PER_GEODE))

## Whole geodes the crystal balance is worth at the current rate. Nothing is
## stored, so this is the closest thing to a geode balance there is.
func available_geodes() -> BigNumber:
	return _floor(_player_data.crystals.div(conversion_rate()))

## Crystals a price in geodes comes to.
func crystal_cost(geodes: BigNumber) -> BigNumber:
	return geodes.mul(conversion_rate())

# ---------------------------------------------------------------- boosts

func boosts() -> Array[GeodeBoostDef]:
	return _boosts

func boost_def(boost_id: StringName) -> GeodeBoostDef:
	return _by_id.get(boost_id)

## Levels bought across every tier of this boost. The tiers are separate level
## counters only so the cost curve and the per-level rate can change at each
## boundary; to the player it is one ladder.
func boost_level(boost_id: StringName) -> int:
	var total := 0
	for tier in range(1, GeodeTiers.MAX_TIER + 1):
		total += _upgrades.level(GeodeTiers.upgrade_id(boost_id, tier))
	return total

## Tier the next level falls into, i.e. the rate it will be bought at.
func boost_tier(boost_id: StringName) -> int:
	return GeodeTiers.tier_for_level(boost_level(boost_id))

func is_maxed(boost_id: StringName) -> bool:
	return boost_level(boost_id) >= GeodeTiers.max_level()

## What the boost currently multiplies its stat by, e.g. 2.7 for a x2.7. Every
## tier compounds into the same product, so a level bought at T3 is worth its
## whole factor on top of the tiers below rather than a share of a common pool.
##
## Computed from the tier table rather than read back out of the UpgradeSystem
## cache, so the number shown is the authored ladder even before the cache is
## rebuilt.
func boost_multiplier(boost_id: StringName) -> BigNumber:
	var total := BigNumber.from_value(1.0)
	var def: GeodeBoostDef = _by_id.get(boost_id)
	if def == null:
		return total
	for tier in range(1, GeodeTiers.MAX_TIER + 1):
		var levels := _upgrades.level(GeodeTiers.upgrade_id(boost_id, tier))
		if levels <= 0:
			continue
		var per_level := BigNumber.from_value(1.0 + def.per_level(tier))
		total = total.mul(per_level.pow_float(float(levels)))
	return total

## What one more level multiplies by, as a fraction above 1.0 (0.05 for a
## x1.05). Zero once maxed.
func next_level_gain(boost_id: StringName) -> float:
	var def: GeodeBoostDef = _by_id.get(boost_id)
	if def == null or is_maxed(boost_id):
		return 0.0
	return def.per_level(boost_tier(boost_id))

## Geodes the next level costs. Zero once maxed, which is also what
## can_buy_boost() reports on.
func boost_cost(boost_id: StringName) -> BigNumber:
	if is_maxed(boost_id):
		return BigNumber.new(0.0, 0)
	return _upgrades.cost(GeodeTiers.upgrade_id(boost_id, boost_tier(boost_id)))

## The same price in crystals, which is what actually leaves the player's pocket.
func boost_crystal_cost(boost_id: StringName) -> BigNumber:
	return crystal_cost(boost_cost(boost_id))

func can_buy_boost(boost_id: StringName) -> bool:
	if not _by_id.has(boost_id) or is_maxed(boost_id):
		return false
	return _player_data.crystals.gte(boost_crystal_cost(boost_id))

func buy_boost(boost_id: StringName) -> bool:
	if not can_buy_boost(boost_id):
		return false
	var tier := boost_tier(boost_id)
	var cost := boost_crystal_cost(boost_id)
	# Level first, crystals second: the level is what boost_cost() is priced off,
	# and a buy_with_points() that refuses (tier already at its cap) must not
	# leave the player short the crystals it would have charged.
	if not _upgrades.buy_with_points(GeodeTiers.upgrade_id(boost_id, tier), true):
		return false
	_player_data.crystals = _player_data.crystals.sub(cost)
	return true

# ---------------------------------------------------------------- helpers

## Geodes are whole things: a balance of "3.7 geodes" is not one the player can
## ever spend exactly.
func _floor(value: BigNumber) -> BigNumber:
	if value.exponent > _INTEGRAL_EXPONENT:
		return value
	return BigNumber.from_value(floor(value.to_float()))
