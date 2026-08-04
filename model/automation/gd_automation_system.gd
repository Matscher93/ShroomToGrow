class_name AutomationSystem
extends RefCounted
## MODEL: every rule about automations. What a level costs in crystals, how often
## an owned automation fires and what one firing actually buys.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## Buying a Biome Size level moves state every size display binds to. BiomeSystem
## documents that the caller announces the change; App forwards this to its own
## biome_size_changed, exactly as it does for a manual purchase.
signal biome_size_bought(key: StringName)

## Mirrors MyceliumNodeViewModel.synergy_track_unlocked: the synergy upgrades are
## hidden until Forest is unlocked, so the automation must not buy behind the
## player's back what the UI is still hiding.
const SYNERGY_GATE_BIOME := &"forest"

## Ceiling on actions one automation may take in a single tick. Stacked
## &"automation_rate" bonuses have no cap of their own, and each action walks
## every node tier or biome, so an uncapped rate would stall the frame.
const MAX_RUNS_PER_TICK := 50

var _automations: AutomationList
var _data: AutomationData
var _player_data: PlayerData
var _production: ProductionSystem
var _node_data: Array[MyceliumNodeData]
var _symbiosis: UpgradeSystem
var _biomes: BiomeList
var _biomes_data: BiomesData
var _biome_system: BiomeSystem
## id -> banked fraction of an action, carried between ticks. Transient: a
## reload starting from zero costs at most one tick of progress.
var _pending: Dictionary = {}

func _init(automations: AutomationList, data: AutomationData, player_data: PlayerData,
		production: ProductionSystem, node_data: Array[MyceliumNodeData],
		symbiosis: UpgradeSystem, biomes: BiomeList, biomes_data: BiomesData,
		biome_system: BiomeSystem) -> void:
	_automations = automations
	_data = data
	_player_data = player_data
	_production = production
	_node_data = node_data
	_symbiosis = symbiosis
	_biomes = biomes
	_biomes_data = biomes_data
	_biome_system = biome_system

# ---------------------------------------------------------------- lookup

func automation_def(id: StringName) -> AutomationDef:
	for def in _automations.automations:
		if def.id == id:
			return def
	return null

func level(id: StringName) -> int:
	return _data.level(id)

func is_owned(id: StringName) -> bool:
	return _data.level(id) > 0

## Owned, switched on, and therefore due to fire on its timer.
func is_active(id: StringName) -> bool:
	return is_owned(id) and _data.is_enabled(id)

# ---------------------------------------------------------------- buying

func cost(id: StringName) -> BigNumber:
	var def := automation_def(id)
	if def == null:
		return BigNumber.new(0.0, 0)
	var scaled_level := pow(float(level(id)), def.cost_growth_exponent)
	return def.base_cost.mul(BigNumber.from_value(def.cost_growth).pow_float(scaled_level))

func is_maxed(id: StringName) -> bool:
	var def := automation_def(id)
	return def != null and def.max_level > 0 and level(id) >= def.max_level

func can_buy(id: StringName) -> bool:
	if automation_def(id) == null or is_maxed(id):
		return false
	return _player_data.crystals.gte(cost(id))

func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	_player_data.crystals = _player_data.crystals.sub(cost(id))
	_data.add_level(id)
	return true

# ---------------------------------------------------------------- timing

## Actions this automation gets per game tick. Levels add to the authored rate,
## then every &"automation_rate" upgrade multiplies the total.
func runs_per_tick(id: StringName) -> float:
	var def := automation_def(id)
	if def == null:
		return 0.0
	var lvl := level(id)
	if lvl <= 0:
		return 0.0
	var rate := def.base_runs_per_tick + def.runs_per_level * float(lvl - 1)
	return maxf(0.0, rate * _production.automation_rate())

## Ticks until the next action, for display. 0 when it fires at least once a
## tick, so callers can show a per-tick count instead.
func ticks_per_run(id: StringName) -> int:
	var rate := runs_per_tick(id)
	if rate <= 0.0 or rate >= 1.0:
		return 0
	return int(ceil(1.0 / rate))

## Advances every automation by one game tick. The only entry point that fires
## them: they have no timer of their own, so they cannot act while the game is
## not ticking, and SaveManager pauses this outright for the offline catch-up.
func handle_tick() -> void:
	for def in _automations.automations:
		_run_pending(def.id)

## Rates below 1.0 would round to zero actions every tick and never fire at all,
## so the fraction is banked and spent once it reaches a whole action.
func _run_pending(id: StringName) -> void:
	if not is_active(id):
		# Banked progress is dropped rather than paid out later: switching an
		# automation off should stop it, not defer it.
		_pending.erase(id)
		return
	var banked: float = _pending.get(id, 0.0) + runs_per_tick(id)
	var runs: int = mini(int(floor(banked)), MAX_RUNS_PER_TICK)
	_pending[id] = banked - floor(banked)
	for i in range(runs):
		if not run(id):
			break  # nothing left it can afford, don't spin through the rest

# ---------------------------------------------------------------- firing

## Performs one action for this automation. Returns false when there was nothing
## it could afford or nothing left to buy, which is the normal idle case.
func run(id: StringName) -> bool:
	var def := automation_def(id)
	if def == null or not is_active(id):
		return false
	match def.kind:
		AutomationDef.Kind.BUY_NODES:
			return _buy_node()
		AutomationDef.Kind.BUY_BIOME_SIZE:
			return _buy_biome_size()
		AutomationDef.Kind.BUY_SYMBIOSIS:
			return _buy_symbiosis()
		AutomationDef.Kind.SPEND_BIOME_POINTS:
			return _spend_biome_points()
		_:
			return false

## Highest tier first: the top tiers feed everything below them, so spending a
## given pile of nutrients up there is worth strictly more than the same pile
## spent on tier 0.
func _buy_node() -> bool:
	for i in range(_node_data.size() - 1, -1, -1):
		if _node_data[i].can_buy_upgrade():
			return _node_data[i].buy_upgrade()
	return false

## Cheapest first, so one automation firing can't sink a run's nutrients into the
## single most expensive biome while the others sit at size 0.
func _buy_biome_size() -> bool:
	var best_key := &""
	var best_cost: BigNumber = null
	for def in _biomes.biomes:
		if not _biomes_data.is_unlocked(def.key):
			continue
		if not _biome_system.can_buy_size(def.key):
			continue
		var size_cost := _biome_system.size_cost(def.key)
		if best_cost == null or size_cost.lt(best_cost):
			best_cost = size_cost
			best_key = def.key
	if best_key.is_empty():
		return false
	if not _biome_system.buy_size(best_key):
		return false
	biome_size_bought.emit(best_key)
	return true

func _buy_symbiosis() -> bool:
	var best_id := &""
	var best_cost: BigNumber = null
	var synergy_unlocked := _biomes_data.is_unlocked(SYNERGY_GATE_BIOME)
	for node_data in _node_data:
		if not node_data.is_unlocked():
			continue
		var ids: Array[StringName] = [StringName("NodePotency%d" % node_data.node.node_id)]
		if synergy_unlocked:
			ids.append(StringName("NodeSynergy%d" % node_data.node.node_id))
		for id in ids:
			if not _symbiosis.can_buy(id, _player_data.nutrients):
				continue
			var upgrade_cost := _symbiosis.cost(id)
			if best_cost == null or upgrade_cost.lt(best_cost):
				best_cost = upgrade_cost
				best_id = id
	if best_id.is_empty():
		return false
	return _symbiosis.buy(best_id, _player_data)

## Walks each unlocked biome's point plan top-down and buys the first entry that
## is still below its target level. The plan order is the player's, set in the
## Crystal Caves screen, so this must not reorder or skip ahead.
func _spend_biome_points() -> bool:
	for def in _biomes.biomes:
		if not _biomes_data.is_unlocked(def.key):
			continue
		for entry: Dictionary in _data.plan_for(def.key, def.upgrade_ids):
			var id := StringName(entry.get("id", &""))
			var target := int(entry.get("target", 0))
			if target > 0 and _biome_system.upgrade_level(id) >= target:
				continue
			if not _biome_system.can_buy_upgrade(id, def.key):
				continue
			if _biome_system.buy_upgrade(id, def.key):
				return true
	return false
