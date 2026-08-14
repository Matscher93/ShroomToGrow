class_name BoostSystem
extends RefCounted
## MODEL: the boost economy's rules - what a boost level costs and what buying it
## takes out of the player's pocket.
##
## Boost levels are priced in crystals directly. There is no exchange step and no
## second currency: the cost curve authored on a BoostDef is already the crystal
## price.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Boost levels live in a plain UpgradeSystem (one def per boost per
## tier, built by BoostTree), which is what makes the boosts stack through
## ProductionSystem without any per-stat wiring here.

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _boosts: Array[BoostDef] = []
var _by_id: Dictionary = {}   # StringName -> BoostDef
## Levels of the perks the boosts are gated behind. Read-only from here: perks
## are bought with biomass through PerkSystem, never with crystals.
var _prestige_upgrades: UpgradeSystem

func _init(player_data: PlayerData, upgrades: UpgradeSystem, list: BoostList,
		prestige_upgrades: UpgradeSystem) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_prestige_upgrades = prestige_upgrades
	if list != null:
		_boosts = list.boosts
	for boost in _boosts:
		_by_id[boost.id] = boost

# ---------------------------------------------------------------- boosts

func boosts() -> Array[BoostDef]:
	return _boosts

func boost_def(boost_id: StringName) -> BoostDef:
	return _by_id.get(boost_id)

## Levels bought across every tier of this boost. The tiers are separate level
## counters only so the cost curve and the per-level rate can change at each
## boundary; to the player it is one ladder.
func boost_level(boost_id: StringName) -> int:
	var total := 0
	for tier in range(1, BoostTiers.MAX_TIER + 1):
		total += _upgrades.level(BoostTiers.upgrade_id(boost_id, tier))
	return total

## Tier the next level falls into, i.e. the rate it will be bought at.
func boost_tier(boost_id: StringName) -> int:
	return BoostTiers.tier_for_level(boost_level(boost_id))

## False while this boost still waits on its prestige perk. Only blocks buying:
## levels bought before the gate existed keep multiplying, the same way a locked
## automation keeps firing.
func is_unlocked(boost_id: StringName) -> bool:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return false
	if def.unlock_perk_id.is_empty():
		return true
	return _prestige_upgrades.level(def.unlock_perk_id) > 0

## How far up the ladder this boost may currently be bought: its authored
## ceiling plus whatever its perk has added, never past the ladder's own end.
func max_level(boost_id: StringName) -> int:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null or def.base_max_level <= 0:
		return BoostTiers.max_level()
	var ceiling := def.base_max_level
	if not def.max_level_perk_id.is_empty():
		ceiling += def.max_level_per_perk_level * _prestige_upgrades.level(def.max_level_perk_id)
	return clampi(ceiling, 0, BoostTiers.max_level())

func is_maxed(boost_id: StringName) -> bool:
	return boost_level(boost_id) >= max_level(boost_id)

## What the boost currently multiplies its stat by, e.g. 2.7 for a x2.7. Every
## tier compounds into the same product, so a level bought at T3 is worth its
## whole factor on top of the tiers below rather than a share of a common pool.
##
## Computed from the tier table rather than read back out of the UpgradeSystem
## cache, so the number shown is the authored ladder even before the cache is
## rebuilt.
func boost_multiplier(boost_id: StringName) -> BigNumber:
	var total := BigNumber.from_value(1.0)
	var def: BoostDef = _by_id.get(boost_id)
	if def == null:
		return total
	for tier in range(1, BoostTiers.MAX_TIER + 1):
		var levels := _upgrades.level(BoostTiers.upgrade_id(boost_id, tier))
		if levels <= 0:
			continue
		var per_level := BigNumber.from_value(1.0 + def.per_level(tier))
		total = total.mul(per_level.pow_float(float(levels)))
	return total

## What one more level multiplies by, as a fraction above 1.0 (0.05 for a
## x1.05). Zero once maxed.
func next_level_gain(boost_id: StringName) -> float:
	var def: BoostDef = _by_id.get(boost_id)
	if def == null or is_maxed(boost_id):
		return 0.0
	return def.per_level(boost_tier(boost_id))

## Crystals the next level costs. Zero once maxed, which is also what
## can_buy_boost() reports on.
func boost_cost(boost_id: StringName) -> BigNumber:
	if is_maxed(boost_id):
		return BigNumber.new(0.0, 0)
	return _upgrades.cost(BoostTiers.upgrade_id(boost_id, boost_tier(boost_id)))

func can_buy_boost(boost_id: StringName) -> bool:
	if not _by_id.has(boost_id) or is_maxed(boost_id) or not is_unlocked(boost_id):
		return false
	return _player_data.crystals.gte(boost_cost(boost_id))

func buy_boost(boost_id: StringName) -> bool:
	if not can_buy_boost(boost_id):
		return false
	var tier := boost_tier(boost_id)
	var cost := boost_cost(boost_id)
	# Level first, crystals second: the level is what boost_cost() is priced off,
	# and a buy_with_points() that refuses (tier already at its cap) must not
	# leave the player short the crystals it would have charged.
	if not _upgrades.buy_with_points(BoostTiers.upgrade_id(boost_id, tier), true):
		return false
	_player_data.crystals = _player_data.crystals.sub(cost)
	return true
