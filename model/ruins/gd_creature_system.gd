class_name CreatureSystem
extends RefCounted
## MODEL: the roster - who may be taken over, how far each may be pushed, and what
## a creature brings to a mission it is sent on.
##
## Split from MissionSystem the way WellSystem is split from WaterSystem: this
## owns the thralls, that owns the errands they run.
##
## Ranks are held on RuinsData rather than in an UpgradeSystem track. A rank is
## not a stat - nothing resolves through ProductionSystem from it - and putting it
## in a track would mean a second, parallel record of the roster that
## RuinsData.creature_ranks already keeps for the in-flight lookup.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _data: RuinsData
var _player_data: PlayerData
var _production: ProductionSystem
var _creatures: Array[CreatureDef] = []
var _by_id: Dictionary = {}   # StringName -> CreatureDef

func _init(data: RuinsData, player_data: PlayerData, list: CreatureList,
		production: ProductionSystem = null) -> void:
	_data = data
	_player_data = player_data
	_production = production
	if list != null:
		_creatures = list.creatures
	for creature in _creatures:
		if creature == null:
			push_error("CreatureList holds a null entry, skipping it.")
			continue
		_by_id[creature.id] = creature

# ---------------------------------------------------------------- lookup

func creatures() -> Array[CreatureDef]:
	return _creatures

func creature_def(creature_id: StringName) -> CreatureDef:
	return _by_id.get(creature_id)

func rank(creature_id: StringName) -> int:
	return _data.rank(creature_id)

func is_recruited(creature_id: StringName) -> bool:
	return rank(creature_id) > 0

## False while the board has not been worked enough to reveal this creature.
## Only blocks recruiting: a creature taken over before a threshold moved keeps
## running missions.
func is_unlocked(creature_id: StringName) -> bool:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return false
	return _data.missions_completed >= def.min_missions_completed

## Missions still owed before this creature can be taken over. Zero once it can.
func missions_until_unlock(creature_id: StringName) -> int:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return 0
	return maxi(0, def.min_missions_completed - _data.missions_completed)

## How far this creature may currently be ranked: its authored ceiling plus
## whatever &"creature_rank_cap" has added for it.
func rank_cap(creature_id: StringName) -> int:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return 0
	var bonus := 0
	if _production != null:
		bonus = _production.creature_rank_bonus(creature_id)
	return def.base_rank_cap + bonus

func is_maxed(creature_id: StringName) -> bool:
	return is_recruited(creature_id) and rank(creature_id) >= rank_cap(creature_id)

## True while this creature is out on a mission, which is what stops it being
## sent on a second one or ranked up mid-errand.
func is_busy(creature_id: StringName) -> bool:
	return not _data.find_by_creature(creature_id).is_empty()

# ---------------------------------------------------------------- bonuses

## What this creature multiplies a mission's speed by. Rank is LINEAR rather than
## compounding so a long roster stays legible, and the affinity bonus rides on top
## of it rather than being folded into the per-rank rate - a rank-1 specialist
## should already beat a rank-1 generalist on its own missions.
func speed_multiplier(creature_id: StringName, mission_id: StringName) -> float:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return 1.0
	var value := 1.0 + def.speed_per_rank * float(rank(creature_id))
	if has_affinity(creature_id, mission_id):
		value *= 1.0 + def.affinity_bonus
	return maxf(0.01, value)

## What this creature multiplies a mission's payouts by. Same shape as above.
func yield_multiplier(creature_id: StringName, mission_id: StringName) -> float:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return 1.0
	var value := 1.0 + def.yield_per_rank * float(rank(creature_id))
	if has_affinity(creature_id, mission_id):
		value *= 1.0 + def.affinity_bonus
	return maxf(0.0, value)

func has_affinity(creature_id: StringName, mission_id: StringName) -> bool:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return false
	return def.affinity.has(mission_id)

# ---------------------------------------------------------------- recruiting

func recruit_cost(creature_id: StringName) -> BigNumber:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null:
		return BigNumber.new(0.0, 0)
	return def.recruit_cost

func can_recruit(creature_id: StringName) -> bool:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null or def.recruit_currency == null:
		return false
	if is_recruited(creature_id) or not is_unlocked(creature_id):
		return false
	var field := CurrencyTypes.field_for(def.recruit_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	return balance.gte(def.recruit_cost)

## Takes a creature over at rank 1.
##
## The rank is set before the currency is spent for the same reason
## BoostSystem.buy_boost() takes the level first: a refused rank must never leave
## the player charged, and set_rank() is the step that can be refused.
func recruit(creature_id: StringName) -> bool:
	if not can_recruit(creature_id):
		return false
	var def: CreatureDef = _by_id[creature_id]
	_data.set_rank(creature_id, 1)
	var field := CurrencyTypes.field_for(def.recruit_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.sub(def.recruit_cost))
	return true

# ---------------------------------------------------------------- ranking up

## What the next rank costs: base * growth^(rank - 1), so the first rank-up is
## priced at base. Zero for a creature not yet taken over or already at its
## ceiling, which is also what can_rank_up() reports on.
func rank_cost(creature_id: StringName) -> BigNumber:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null or not is_recruited(creature_id) or is_maxed(creature_id):
		return BigNumber.new(0.0, 0)
	var steps := rank(creature_id) - 1
	return def.rank_base_cost.mul(BigNumber.from_value(def.rank_cost_growth).pow_int(steps))

func can_rank_up(creature_id: StringName) -> bool:
	var def: CreatureDef = _by_id.get(creature_id)
	if def == null or def.rank_currency == null:
		return false
	if not is_recruited(creature_id) or is_maxed(creature_id):
		return false
	# A creature out on a mission carries the rank it left with - see the snapshot
	# contract on RuinsData - so ranking it up mid-errand would charge for a bonus
	# that mission will never pay.
	if is_busy(creature_id):
		return false
	var field := CurrencyTypes.field_for(def.rank_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	return balance.gte(rank_cost(creature_id))

func rank_up(creature_id: StringName) -> bool:
	if not can_rank_up(creature_id):
		return false
	var def: CreatureDef = _by_id[creature_id]
	var cost := rank_cost(creature_id)
	_data.set_rank(creature_id, rank(creature_id) + 1)
	var field := CurrencyTypes.field_for(def.rank_currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.sub(cost))
	return true

# ---------------------------------------------------------------- selection

## Every creature that could be sent on this mission right now: taken over, idle,
## and ranked high enough. The board's creature picker is the one caller.
func available_for(mission: MissionDef) -> Array[CreatureDef]:
	var out: Array[CreatureDef] = []
	if mission == null:
		return out
	for creature in _creatures:
		if creature == null:
			continue
		if not is_recruited(creature.id) or is_busy(creature.id):
			continue
		if rank(creature.id) < mission.min_creature_rank:
			continue
		out.append(creature)
	return out
