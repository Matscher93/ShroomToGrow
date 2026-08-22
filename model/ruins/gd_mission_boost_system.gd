class_name MissionBoostSystem
extends RefCounted
## MODEL: what the mission currencies buy - the spending half of the Ruins, split
## from MissionSystem the way WellSystem is split from WaterSystem.
##
## Thin by design: the ladder itself is an UpgradeSystem track like the crystal
## boosts and the well projects, so cost, level and effect resolution are already
## handled there. What lives here is the gate and the currency - which rung is
## open, and that a purchase spends relics, ichor or glyphs rather than nutrients.
##
## That track is never reset. The mission currencies are permanent, and so is what
## they were spent on.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _player_data: PlayerData
var _upgrades: UpgradeSystem
var _data: RuinsData
var _boosts: Array[MissionBoostDef] = []
var _by_id: Dictionary = {}   # StringName -> MissionBoostDef

func _init(player_data: PlayerData, upgrades: UpgradeSystem, data: RuinsData,
		list: MissionBoostList) -> void:
	_player_data = player_data
	_upgrades = upgrades
	_data = data
	if list != null:
		_boosts = list.boosts
	for boost in _boosts:
		if boost == null:
			continue
		_by_id[boost.id] = boost

# ---------------------------------------------------------------- lookup

func boosts() -> Array[MissionBoostDef]:
	return _boosts

func boost_def(boost_id: StringName) -> MissionBoostDef:
	return _by_id.get(boost_id)

func level(boost_id: StringName) -> int:
	return _upgrades.level(boost_id)

func max_level(boost_id: StringName) -> int:
	var def: MissionBoostDef = _by_id.get(boost_id)
	return def.max_level if def != null else 0

func is_maxed(boost_id: StringName) -> bool:
	var ceiling := max_level(boost_id)
	return ceiling > 0 and level(boost_id) >= ceiling

## False while the board has not been worked enough to reveal this rung. Only
## blocks buying: levels bought before a threshold moved keep paying out.
func is_unlocked(boost_id: StringName) -> bool:
	var def: MissionBoostDef = _by_id.get(boost_id)
	if def == null:
		return false
	return _data.missions_completed >= def.min_missions_completed

## Missions still owed before this rung opens. Zero once it has.
func missions_until_unlock(boost_id: StringName) -> int:
	var def: MissionBoostDef = _by_id.get(boost_id)
	if def == null:
		return 0
	return maxi(0, def.min_missions_completed - _data.missions_completed)

## The PlayerData field a purchase spends. UpgradeSystem.buy() takes a field name
## rather than a CurrencyTypes value, so this is the whole of the currency wiring.
func currency_field(boost_id: StringName) -> StringName:
	var def: MissionBoostDef = _by_id.get(boost_id)
	if def == null or def.currency == null:
		return &"relics"
	return CurrencyTypes.field_for(def.currency.currency_type)

# ---------------------------------------------------------------- buying

## What the next level costs. Zero once maxed, which is also what can_buy()
## reports on.
func cost(boost_id: StringName) -> BigNumber:
	if is_maxed(boost_id):
		return BigNumber.new(0.0, 0)
	return _upgrades.cost(boost_id)

func can_buy(boost_id: StringName) -> bool:
	if not _by_id.has(boost_id) or is_maxed(boost_id) or not is_unlocked(boost_id):
		return false
	var balance: BigNumber = _player_data.get(currency_field(boost_id))
	return _upgrades.can_buy(boost_id, balance)

func buy(boost_id: StringName) -> bool:
	if not can_buy(boost_id):
		return false
	return _upgrades.buy(boost_id, _player_data, currency_field(boost_id))

## What one rung currently contributes, resolved through the same effect
## machinery that pays it out, so the number shown is the number applied.
func amount(boost_id: StringName, ctx: ResolveContext) -> BigNumber:
	return _upgrades.effect_amount(boost_id, ctx)

## What one more level adds, at the current level. Not the same as the authored
## per_level for a COMPOUND effect, where each level is worth more than the last.
func next_level_delta(boost_id: StringName, ctx: ResolveContext) -> BigNumber:
	return _upgrades.next_level_delta(boost_id, ctx)

## Total levels across the whole ladder, for the screen's header line.
func total_levels() -> int:
	var total := 0
	for boost in _boosts:
		if boost == null:
			continue
		total += level(boost.id)
	return total
