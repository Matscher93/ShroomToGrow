class_name HeroSystem
extends RefCounted
## MODEL: the hero roster - who may be taken over, how far each may be pushed,
## what each brings to an expedition, and how far along its own chain it is.
##
## A hero runs expeditions and nothing else; the farms are WorkerSystem's half.
## Because a chain belongs to exactly one hero, there is never a choice of who
## goes - which is why there is no "available for this mission" list here any
## more, only "is this hero free".
##
## Split from MissionSystem the way WellSystem is split from WaterSystem: this
## owns the thralls, that owns the errands they run.
##
## Levels are held on RuinsData rather than in an UpgradeSystem track. A level is
## not a stat - nothing resolves through ProductionSystem from it - and putting it
## in a track would mean a second, parallel record of the roster that
## RuinsData.hero_levels already keeps for the in-flight lookup.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _data: RuinsData
var _player_data: PlayerData
var _production: ProductionSystem
var _heroes: Array[HeroDef] = []
var _by_id: Dictionary = {}   # StringName -> HeroDef

func _init(data: RuinsData, player_data: PlayerData, list: HeroList,
		production: ProductionSystem = null) -> void:
	_data = data
	_player_data = player_data
	_production = production
	if list != null:
		_heroes = list.heroes
	for hero in _heroes:
		if hero == null:
			push_error("HeroList holds a null entry, skipping it.")
			continue
		_by_id[hero.id] = hero

# ---------------------------------------------------------------- lookup

func heroes() -> Array[HeroDef]:
	return _heroes

func hero_def(hero_id: StringName) -> HeroDef:
	return _by_id.get(hero_id)

func level(hero_id: StringName) -> int:
	return _data.level(hero_id)

func is_recruited(hero_id: StringName) -> bool:
	return level(hero_id) > 0

## False while the board has not been worked enough to reveal this hero.
## Only blocks recruiting: a hero taken over before a threshold moved keeps
## running missions.
func is_unlocked(hero_id: StringName) -> bool:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return false
	return _data.missions_completed >= def.min_missions_completed

## Missions still owed before this hero can be taken over. Zero once it can.
func missions_until_unlock(hero_id: StringName) -> int:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return 0
	return maxi(0, def.min_missions_completed - _data.missions_completed)

## How far this hero may currently be leveled: its authored ceiling plus
## whatever &"hero_level_cap" has added for it.
func level_cap(hero_id: StringName) -> int:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return 0
	var bonus := 0
	if _production != null:
		bonus = _production.hero_level_bonus(hero_id)
	return def.base_level_cap + bonus

func is_maxed(hero_id: StringName) -> bool:
	return is_recruited(hero_id) and level(hero_id) >= level_cap(hero_id)

## True while this hero is out on a mission, which is what stops it being
## sent on a second one or levelled up mid-errand.
func is_busy(hero_id: StringName) -> bool:
	return not _data.find_by_hero(hero_id).is_empty()

# ---------------------------------------------------------------- bonuses

## What this hero multiplies its expeditions' speed by. Level is LINEAR rather
## than compounding, so a long roster stays legible.
##
## No mission argument: a hero only ever runs its own chain, so there is nothing
## for a per-mission bonus to distinguish. That is what affinity used to be for,
## and it is why affinity is gone.
func speed_multiplier(hero_id: StringName) -> float:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return 1.0
	return maxf(0.01, 1.0 + def.speed_per_level * float(level(hero_id)))

## What this hero multiplies its expeditions' payouts by. Same shape as above.
func yield_multiplier(hero_id: StringName) -> float:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return 1.0
	return maxf(0.0, 1.0 + def.yield_per_level * float(level(hero_id)))

# ---------------------------------------------------------------- recruiting

func recruit_cost(hero_id: StringName) -> BigNumber:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null:
		return BigNumber.new(0.0, 0)
	return def.recruit_cost

## Every currency this hero costs, as {field: StringName, amount: BigNumber}
## rows - the main price and any extras beside it.
##
## One list rather than a price and a special case, so a hero costing three
## currencies is charged by the same loop that charges one costing a single one.
func recruit_prices(hero_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: HeroDef = _by_id.get(hero_id)
	if def == null or def.recruit_currency == null:
		return out
	out.append({
		"field": CurrencyTypes.field_for(def.recruit_currency.currency_type),
		"amount": def.recruit_cost,
	})
	for extra in def.extra_recruit_costs:
		if extra == null or extra.currency == null:
			push_error("HeroDef '%s' has an extra recruit cost with no currency, skipping it." % def.id)
			continue
		out.append({
			"field": CurrencyTypes.field_for(extra.currency.currency_type),
			"amount": extra.amount,
		})
	return out

func can_recruit(hero_id: StringName) -> bool:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null or def.recruit_currency == null:
		return false
	if is_recruited(hero_id) or not is_unlocked(hero_id):
		return false
	return _can_afford(recruit_prices(hero_id))

## Whether every row of a price is covered. Checked in full before anything is
## spent, so a short last currency cannot leave the player charged for the first
## two - the same reason recruit() below sets the level before it takes the money.
func _can_afford(prices: Array[Dictionary]) -> bool:
	for price: Dictionary in prices:
		var balance: BigNumber = _player_data.get(price["field"])
		if not balance.gte(price["amount"]):
			return false
	return true

func _spend(prices: Array[Dictionary]) -> void:
	for price: Dictionary in prices:
		var balance: BigNumber = _player_data.get(price["field"])
		_player_data.set(price["field"], balance.sub(price["amount"]))

## Takes a hero over at level 1.
##
## The level is set before the currency is spent for the same reason
## BoostSystem.buy_boost() takes the level first: a refused level must never leave
## the player charged, and set_level() is the step that can be refused.
func recruit(hero_id: StringName) -> bool:
	if not can_recruit(hero_id):
		return false
	_data.set_level(hero_id, 1)
	_spend(recruit_prices(hero_id))
	return true

# ---------------------------------------------------------------- levelling up

## What the next level costs: base * growth^(level - 1), so the first level-up is
## priced at base. Zero for a hero not yet taken over or already at its
## ceiling, which is also what can_level_up() reports on.
func level_cost(hero_id: StringName) -> BigNumber:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null or not is_recruited(hero_id) or is_maxed(hero_id):
		return BigNumber.new(0.0, 0)
	var steps := level(hero_id) - 1
	return def.level_base_cost.mul(BigNumber.from_value(def.level_cost_growth).pow_int(steps))

func can_level_up(hero_id: StringName) -> bool:
	var def: HeroDef = _by_id.get(hero_id)
	if def == null or def.level_currency == null:
		return false
	if not is_recruited(hero_id) or is_maxed(hero_id):
		return false
	# A hero out on a mission carries the level it left with - see the snapshot
	# contract on RuinsData - so leveling it up mid-errand would charge for a bonus
	# that mission will never pay.
	if is_busy(hero_id):
		return false
	var field := CurrencyTypes.field_for(def.level_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	return balance.gte(level_cost(hero_id))

func level_up(hero_id: StringName) -> bool:
	if not can_level_up(hero_id):
		return false
	var def: HeroDef = _by_id[hero_id]
	var cost := level_cost(hero_id)
	_data.set_level(hero_id, level(hero_id) + 1)
	var field := CurrencyTypes.field_for(def.level_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.sub(cost))
	return true

# ---------------------------------------------------------------- selection

## Whether this hero could be sent on something right now: taken over and not
## already out. What it would be sent on is settled by its chain, not by a pick.
func is_available(hero_id: StringName) -> bool:
	return is_recruited(hero_id) and not is_busy(hero_id)
