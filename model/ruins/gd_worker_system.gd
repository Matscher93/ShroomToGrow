class_name WorkerSystem
extends RefCounted
## MODEL: the worker pool - how many have been hired, how many are free, what the
## next one costs, and how many may be put on one farm.
##
## Workers are the other half of the Ruins roster, and the opposite kind of thing
## to a hero. A hero is a named unit with a level and a chain of its own; a worker
## is a number. Nothing distinguishes one worker from another, so there is no
## roster to draw, no card to bind and no id to store - a farm holds a count, and
## the pool holds a count, and the difference between them is how many are idle.
##
## Split from HeroSystem rather than folded into it for the same reason
## HeroSystem was split from MissionSystem: this owns the workers, that owns the
## heroes, and the board owns what either of them is doing.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## Workers that may be put on one farm before any &"workers_per_farm" upgrade
## raises it. One, so the first upgrade that widens a farm is felt.
const BASE_WORKERS_PER_FARM := 1

var _data: RuinsData
var _player_data: PlayerData
var _production: ProductionSystem
var _cost: WorkerCostDef

func _init(data: RuinsData, player_data: PlayerData, cost: WorkerCostDef,
		production: ProductionSystem = null) -> void:
	_data = data
	_player_data = player_data
	_cost = cost
	_production = production

# ---------------------------------------------------------------- the pool

func owned() -> int:
	return _data.workers_owned

## Workers currently on a farm, counted off the board rather than tracked
## alongside it: the board is the only record of where a worker is, so a second
## tally could disagree with it.
func assigned() -> int:
	var total := 0
	for entry in _data.active:
		if bool(entry["is_farm"]):
			total += int(entry["workers"])
	return total

func idle() -> int:
	return maxi(0, owned() - assigned())

# ---------------------------------------------------------------- hiring

## What the next worker costs, as {field: StringName, amount: BigNumber} rows -
## the same shape HeroSystem.recruit_prices() hands back, so the two are spent
## and displayed by the same code.
func prices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _cost == null:
		return out
	var growth := BigNumber.from_value(_cost.cost_growth).pow_int(owned())
	for price in _cost.prices:
		if price == null or price.currency == null:
			push_error("WorkerCostDef has a price with no currency, skipping it.")
			continue
		out.append({
			"field": CurrencyTypes.field_for(price.currency.currency_type),
			"amount": price.amount.mul(growth),
		})
	return out

func can_hire() -> bool:
	var rows := prices()
	if rows.is_empty():
		return false
	for price: Dictionary in rows:
		var balance: BigNumber = _player_data.get(price["field"])
		if not balance.gte(price["amount"]):
			return false
	return true

## Hires one worker, spending every currency in the price.
##
## Every balance is checked before any of them is taken, so a short third
## currency cannot leave the player charged for the first two. That is the whole
## reason can_hire() walks the rows rather than each spend checking as it goes.
func hire() -> bool:
	if not can_hire():
		return false
	for price: Dictionary in prices():
		var balance: BigNumber = _player_data.get(price["field"])
		_player_data.set(price["field"], balance.sub(price["amount"]))
	_data.workers_owned += 1
	return true

# ---------------------------------------------------------------- assignment

## Workers this farm may hold at once. Scoped by mission id, so an expedition
## reward can widen one farm without widening the rest - the same shape
## ProductionSystem.hero_level_bonus() reads &"hero_level_cap" in.
func max_per_farm(mission_id: StringName) -> int:
	var bonus := 0
	if _production != null:
		bonus = _production.workers_per_farm(mission_id)
	return maxi(1, BASE_WORKERS_PER_FARM + bonus)

## The most that could be put on this farm right now: its ceiling, capped by what
## is actually free plus whatever it already holds.
func most_available_for(mission_id: StringName, already_here: int) -> int:
	return mini(max_per_farm(mission_id), idle() + already_here)
