class_name PlayerLevelSystem
extends RefCounted
## MODEL: the account-wide level, the Level Points it grants, and where they
## have been spent.
##
## Split from DailyRewardSystem the way WellSystem is split from WaterSystem:
## the two write into the same UpgradeSystem track and boost the same producers,
## but one is earned by producing and the other by showing up, and neither rule
## belongs inside the other.
##
## Holds no App reference, so it can be built and exercised in isolation.

## Level Points invested, in total across every producer, that buy one more
## doubling of all of them.
const LP_PER_DOUBLE := 10

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _production: ProductionSystem
var _producers: Array[GrowthProducerDef] = []

## `production` is optional so a test caring only about the ladder can build this
## with three arguments. Without it the &"level_points" stat resolves to nothing
## and the budget is the level alone, which is the pre-perk behaviour.
func _init(player_data: PlayerData, upgrades: UpgradeSystem, list: GrowthProducerList,
		production: ProductionSystem = null) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_production = production
	if list != null:
		_producers = list.producers

# ---------------------------------------------------------------- level

func level() -> int:
	return PlayerLevelCalculator.level_of(_player_data.lifetime_nutrients)

## {level, into, need, pct} for the progress bar and its caption.
func level_progress() -> Dictionary:
	return PlayerLevelCalculator.level_for(_player_data.lifetime_nutrients)

# ---------------------------------------------------------------- points

func invested(currency: CurrencyTypes.Types) -> int:
	return _upgrades.level(GrowthTree.invest_id(currency))

## Level Points spent, summed over the authored producers only.
##
## Deliberately not UpgradeSystem.total_levels(): this track also carries the
## daily stacks and the doubling level, and counting those as investments would
## hand the player free doublings for turning up.
func invested_total() -> int:
	var total := 0
	for producer in _producers:
		if producer == null or producer.currency == null:
			continue
		total += invested(producer.currency.currency_type)
	return total

## Level-derived points plus any flat bonus from upgrades in any track that
## target the &"level_points" stat - the prestige web's Attunement perk is the
## one that does.
##
## Exactly the shape BiomeSystem.available_points() has for &"biome_points", and
## for the same reason: a perk that hands out points is a data edit rather than a
## second budget to keep in step.
func available_points() -> int:
	var bonus := 0
	if _production != null:
		bonus = int(_production.stack(&"level_points", BigNumber.new(0.0, 0)).to_float())
	return maxi(0, level() + bonus - invested_total())

# ---------------------------------------------------------------- doubling

## Doublings earned so far, read off the level the effect actually resolves
## through rather than recomputed, so the displayed multiplier and the applied
## one cannot disagree.
func doublings() -> int:
	return _upgrades.level(GrowthTree.GLOBAL_DOUBLE_ID)

func global_double() -> BigNumber:
	return BigNumber.from_value(2.0).pow_int(doublings())

## Points still to invest before the next doubling lands.
func points_to_next_double() -> int:
	return LP_PER_DOUBLE - invested_total() % LP_PER_DOUBLE

# ---------------------------------------------------------------- investing

func can_invest(currency: CurrencyTypes.Types) -> bool:
	return available_points() >= 1 and _upgrades.has_def(GrowthTree.invest_id(currency))

func invest(currency: CurrencyTypes.Types) -> bool:
	if not can_invest(currency):
		return false
	# Batched: the investment and the doubling it may have just earned are one
	# decision to the player, so they get one upgrades_changed rather than two
	# full refreshes of every bound view.
	_upgrades.begin_batch()
	var bought := _upgrades.buy_with_points(GrowthTree.invest_id(currency), true)
	if bought:
		sync_global_double()
	_upgrades.end_batch()
	return bought

## Brings the global-doubling level up to what the invested total warrants: one
## per LP_PER_DOUBLE points, wherever they were spent.
##
## Called after every investment and again after a save load. The level does
## round-trip in the track's save dict - UpgradeSystem.to_save() writes every
## level it holds - so the load-time call is a drift guard against a future
## migration rather than the primary path, in the same spirit as
## WellSystem.sync_project_levels().
##
## buy_with_points() only ever increments, so a level found *above* its target is
## left alone and reported. Reaching that takes a hand-edited save, and this is
## the same posture UpgradeSystem.from_save() takes on an unknown id: say so, and
## keep the rest of the load intact.
func sync_global_double() -> void:
	var target := invested_total() / LP_PER_DOUBLE
	var current := doublings()
	if current > target:
		push_warning("Global doubling is at level %d but only %d Level Points are invested, leaving it alone."
			% [current, invested_total()])
		return
	if current == target:
		return
	_upgrades.begin_batch()
	for _i in range(target - current):
		_upgrades.buy_with_points(GrowthTree.GLOBAL_DOUBLE_ID, true)
	_upgrades.end_batch()
