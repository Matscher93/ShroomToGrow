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

## The automation that replays recorded biome sequences. Named here so the
## Crystal Caves biome sections can say whether replay is actually running,
## rather than each of them hard-coding the id.
const SEQUENCE_AUTOMATION_ID := &"AutoSpendPoints"

## How long one automation may spend firing in a single tick. There is no ceiling
## on the *number* of actions: a fixed one silently ate the rate upgrades that
## pushed past it, while the card kept counting up and reporting a rate the tick
## never delivered.
##
## A budget instead of a count, because the cost that mattered was always frame
## time - each action walks every node tier or biome - and that is what this
## measures directly. Actions the budget cuts short are owed, not dropped, and
## handle_frame() below pays them off.
const RUN_BUDGET_USEC := 2000

## How long the whole system may spend paying off owed actions in one frame -
## shared by every automation, unlike RUN_BUDGET_USEC, which each one gets in
## full once a tick.
##
## Owed actions used to wait for the next tick, which is ten seconds at base and
## never under one, so a level whose rate overran the tick budget bought a count
## the game only delivered a tick later. Paying the debt off across frames keeps
## a tick's advertised count landing inside that tick, which is what the card
## promises when the player buys the level.
##
## 4ms of a 16ms frame, and only on the frames that actually owe something - a
## debt small enough to clear in one frame costs a fraction of it, and one large
## enough to want the whole budget is a debt worth spending the frame on.
const FRAME_BUDGET_USEC := 4000

var _automations: AutomationList
var _data: AutomationData
var _player_data: PlayerData
var _production: ProductionSystem
var _node_data: Array[MyceliumNodeData]
var _symbiosis: UpgradeSystem
var _biomes: BiomeList
var _biomes_data: BiomesData
var _biome_system: BiomeSystem
## Levels of the perks automations are gated behind. Read-only from here: perks
## are bought with biomass through PerkSystem, never through an automation.
var _prestige_upgrades: UpgradeSystem
## id -> banked fraction of an action, carried between ticks. Only ever the
## fraction: a rate below one action a tick is paced by the tick on purpose, so
## 0.25 has to stay one action every four ticks rather than every four frames.
## Transient: a reload starting from zero costs at most one tick of progress.
var _pending: Dictionary = {}
## id -> whole actions the rate has paid for and the budget has not run yet,
## drained by handle_frame(). Transient for the same reason as _pending.
var _owed: Dictionary = {}
## biome key -> how far the point-spending walk has already got:
## {"index", "seen", "spent", "src", "size"}. The walk used to restart at step 0
## for every single action, which on a hundred-step plan is a hundred-step tally
## to buy one thing, twenty times a tick.
##
## Only the steps the walk has confirmed *bought* are behind the cursor, never a
## step that is merely gated: a gate opens as points are spent, so the next
## action has to look at it again.
##
## Valid while nothing outside this system has moved the biome's upgrades, which
## `spent` watches - every purchase goes through BiomeSystem.buy_upgrade() and
## moves points_spent, and a prestige reset takes it back to zero. `src`/`size`
## catch the player editing the plan out from under it.
var _walk: Dictionary = {}
## biome key -> available_points(), which re-derives biome XP and resolves a stat
## through every upgrade track. Held for as long as this system is the only thing
## spending, and re-derived the moment it reads empty - an upgrade can itself
## grant points.
var _points: Dictionary = {}
## id -> AutomationDef. Built once: automation_def() is called several times per
## action, and the authored list never changes at runtime.
var _defs_by_id: Dictionary = {}

func _init(automations: AutomationList, data: AutomationData, player_data: PlayerData,
		production: ProductionSystem, node_data: Array[MyceliumNodeData],
		symbiosis: UpgradeSystem, biomes: BiomeList, biomes_data: BiomesData,
		biome_system: BiomeSystem, prestige_upgrades: UpgradeSystem) -> void:
	_automations = automations
	_data = data
	_player_data = player_data
	_production = production
	_node_data = node_data
	_symbiosis = symbiosis
	_biomes = biomes
	_biomes_data = biomes_data
	_biome_system = biome_system
	_prestige_upgrades = prestige_upgrades
	for def in _automations.automations:
		_defs_by_id[def.id] = def

# ---------------------------------------------------------------- lookup

func automation_def(id: StringName) -> AutomationDef:
	return _defs_by_id.get(id)

func level(id: StringName) -> int:
	return _data.level(id)

func is_owned(id: StringName) -> bool:
	return _data.level(id) > 0

## False while this automation still waits on its prestige perk. Only blocks
## buying: an automation owned before the gate existed keeps its levels and keeps
## firing, the same way a locked node tier keeps the nodes it already has.
func is_unlocked(id: StringName) -> bool:
	var def := automation_def(id)
	if def == null:
		return false
	if def.unlock_perk_id.is_empty():
		return true
	return _prestige_upgrades.level(def.unlock_perk_id) > 0

## This automation's ceiling right now: the authored one plus whatever its
## max-level perk has added. 0 stays 0 - an automation authored without a ceiling
## has none to raise.
func max_level(id: StringName) -> int:
	var def := automation_def(id)
	if def == null:
		return 0
	if def.max_level <= 0:
		return 0
	if def.max_level_perk_id.is_empty():
		return def.max_level
	var perk_level := _prestige_upgrades.level(def.max_level_perk_id)
	return def.max_level + def.max_level_per_perk_level * perk_level

## Owned, switched on, and therefore due to fire on its timer.
func is_active(id: StringName) -> bool:
	return is_owned(id) and _data.is_enabled(id)

# ---------------------------------------------------------------- buying

func cost(id: StringName) -> BigNumber:
	var def := automation_def(id)
	if def == null:
		return BigNumber.new(0.0, 0)
	var scaled_level := float(level(id)) * pow(def.cost_growth_exponent, float(level(id)))
	return def.base_cost.mul(BigNumber.from_value(def.cost_growth).pow_float(scaled_level))

func is_maxed(id: StringName) -> bool:
	var ceiling := max_level(id)
	return ceiling > 0 and level(id) >= ceiling

func can_buy(id: StringName) -> bool:
	if automation_def(id) == null or is_maxed(id) or not is_unlocked(id):
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
	return runs_per_tick_at(id, level(id))

## The same rate at a level the automation is not necessarily on, so the card can
## price the next one: a level's worth of crystals is unanswerable without seeing
## what it buys.
func runs_per_tick_at(id: StringName, lvl: int) -> float:
	var def := automation_def(id)
	if def == null:
		return 0.0
	if lvl <= 0:
		return 0.0
	var rate := def.base_runs_per_tick + def.runs_per_level * float(lvl - 1)
	return maxf(0.0, rate * _production.automation_rate())

## Ticks until the next action, for display. 0 when it fires at least once a
## tick, so callers can show a per-tick count instead.
func ticks_per_run(id: StringName) -> int:
	return ticks_per_run_at(id, level(id))

func ticks_per_run_at(id: StringName, lvl: int) -> int:
	var rate := runs_per_tick_at(id, lvl)
	if rate <= 0.0 or rate >= 1.0:
		return 0
	return int(ceil(1.0 / rate))

## Advances every automation by one game tick. The only entry point that fires
## them: they have no timer of their own, so they cannot act while the game is
## not ticking, and SaveManager pauses this outright for the offline catch-up.
func handle_tick() -> void:
	# Ahead of the authored list, and that ordering is the point of it: a biome
	# still shut earns nothing all run, while the three nutrient-spending
	# automations below would happily drain the balance its unlock price needs.
	_run_biome_unlocks()
	for def in _automations.automations:
		_run_pending(def.id)

## Buys back every biome whose crystal auto-unlock is owned and switched on, as
## soon as the run can afford the unlock price.
##
## Not one of the authored automations: the per-biome crystal purchase is already
## the gate, so making the player buy a second thing to arm it would charge twice
## for one behaviour. It carries no rate either - each biome can succeed at most
## once per run, and there are a handful of them.
##
## Authored order rather than cheapest-first, unlike the automations below.
## Biomes may be priced in different currencies (BiomeDef.unlock_currency), so
## their costs are not comparable; the list is already in progression order.
func _run_biome_unlocks() -> void:
	for def in _biomes.biomes:
		if _biomes_data.is_unlocked(def.key):
			continue
		if not _biome_system.is_auto_unlock_armed(def.key):
			continue
		_biome_system.unlock(def.key)

## Rates below 1.0 would round to zero actions every tick and never fire at all,
## so the fraction is banked and spent once it reaches a whole action.
func _run_pending(id: StringName) -> void:
	if not is_active(id):
		# Banked progress is dropped rather than paid out later: switching an
		# automation off should stop it, not defer it.
		_pending.erase(id)
		_owed.erase(id)
		return
	var banked: float = _pending.get(id, 0.0) + runs_per_tick(id)
	_pending[id] = banked - floor(banked)
	_owed[id] = owed(id) + int(floor(banked))
	# The tick still runs everything it can right here. What it cannot reach in
	# its budget stays owed for the frames after it.
	_drain(id, Time.get_ticks_usec() + RUN_BUDGET_USEC)

## Pays off as much of one automation's debt as `deadline` allows. Returns
## whether anything was actually bought, so a caller can skip the work that only
## a purchase makes necessary.
func _drain(id: StringName, deadline: int) -> bool:
	var bought := false
	while owed(id) > 0:
		if not run(id):
			# Nothing left it can afford or anything left to buy. The rest of the
			# debt is dropped rather than carried: an automation that idles
			# through a tick should not fire a burst the moment it can pay again.
			_owed[id] = 0
			break
		bought = true
		_owed[id] = owed(id) - 1
		if Time.get_ticks_usec() >= deadline:
			break
	return bought

# ---------------------------------------------------------------- frames

## Actions the rate has already paid for and no tick has managed to run yet.
func owed(id: StringName) -> int:
	return _owed.get(id, 0)

func has_owed() -> bool:
	for id: StringName in _owed:
		if _owed[id] > 0:
			return true
	return false

## Pays off what the tick budget cut short, on the frame after it rather than on
## the next tick - ten seconds is far too late for a count the card advertises
## per tick. Returns whether anything was bought, so App only pays for a batched
## refresh on the frames that moved something.
##
## One budget for the whole call, in authored order, matching how handle_tick()
## walks the same list. Biome auto-unlocks are not repeated here: they are a tick
## rule, unrated and at most one per biome per run.
func handle_frame() -> bool:
	var deadline := Time.get_ticks_usec() + FRAME_BUDGET_USEC
	var bought := false
	for def in _automations.automations:
		if not is_active(def.id):
			_owed.erase(def.id)
			continue
		if _drain(def.id, deadline):
			bought = true
		if Time.get_ticks_usec() >= deadline:
			break
	return bought

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
		# The price once, for both questions. can_buy_size() would work it out
		# again for the comparison below, and this loop runs over every biome on
		# every action.
		var size_cost := _biome_system.size_cost(def.key)
		if not _player_data.nutrients.gte(size_cost):
			continue
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
			if not _symbiosis.has_room(id):
				continue
			# Same as _buy_biome_size(): the price once, for both the
			# affordability test and the comparison. There are two candidates per
			# node tier and this runs on every action.
			var upgrade_cost := _symbiosis.cost(id)
			if not _player_data.nutrients.gte(upgrade_cost):
				continue
			if best_cost == null or upgrade_cost.lt(best_cost):
				best_cost = upgrade_cost
				best_id = id
	if best_id.is_empty():
		return false
	return _symbiosis.buy(best_id, _player_data)

## Replays each unlocked biome's recorded sequence by one step. A biome with no
## sequence is skipped: nothing was asked for, so nothing is bought.
func _spend_biome_points() -> bool:
	for def in _biomes.biomes:
		if not _biomes_data.is_unlocked(def.key):
			continue
		var id := next_sequence_step(def)
		if id.is_empty():
			continue
		var budget := _available_points(def.key)
		if _biome_system.buy_upgrade(id, def.key):
			# Both caches were right a moment ago and this call is what moved
			# them, so they are corrected rather than thrown away.
			_points[def.key] = maxi(0, budget - 1)
			var state: Variant = _walk.get(def.key)
			if state != null:
				state["spent"] = _biomes_data.points_spent(def.key)
			return true
		# The budget said there was a point and the purchase disagreed, so the
		# cached budget is stale - something outside this system spent it.
		_points.erase(def.key)
	return false

## The next step of a biome's sequence that is still outstanding and affordable,
## or empty when the sequence is finished, unrecorded, or entirely blocked.
##
## Outstanding is decided by counting: walking the sequence and tallying how many
## times each id has appeared so far, a step is already done once that tally is
## within the upgrade's current level. That is what makes replaying a sequence
## the same operation as running it the first time - after a prestige every level
## is back to zero, so the same walk rebuilds the same build order from the
## start, with no cursor to store or reset.
##
## A step that is outstanding but not currently buyable (its point gate is not
## met yet, or there are no points) is stepped over rather than waited on.
## Waiting would deadlock the common case where a later, cheaper step is what
## unlocks the gate the earlier one is behind.
func next_sequence_step(def: BiomeDef) -> StringName:
	# The sequence first, and only then the budget: most biomes have no plan at
	# all, and available_points() re-derives biome XP and resolves a stat through
	# every upgrade track, which is far too much to pay to find out that nothing
	# was asked for.
	var sequence := _data.sequence_for(def.key, def.upgrade_ids)
	if sequence.is_empty():
		return &""
	# Read once for the whole walk rather than once per step, via
	# BiomeSystem.has_upgrade_room(). Nothing inside the walk can raise it, so
	# one point is enough to know the walk is worth doing at all.
	if _available_points(def.key) < 1:
		return &""
	var state := _walk_state(def.key, sequence)
	var seen: Dictionary = state["seen"]
	# Behind the cursor is settled, so its tally is the shared one and moving it
	# is permanent. From the first outstanding step on, the walk is provisional -
	# a gated step is stepped over now and may be buyable in a moment - so the
	# tally forks there and the cursor stays put.
	var tally := seen
	var settled := true
	var i: int = state["index"]
	while i < sequence.size():
		var id: StringName = sequence[i]
		var count: int = tally.get(id, 0) + 1
		if count <= _biome_system.upgrade_level(id):
			tally[id] = count  # this step is already bought
			if settled:
				state["index"] = i + 1
			i += 1
			continue
		if settled:
			settled = false
			tally = seen.duplicate()
		tally[id] = count
		if _biome_system.has_upgrade_room(id, def.key):
			return id
		i += 1
	return &""

## Where the walk left off for this biome, or a fresh start when anything it was
## resting on has moved. See _walk.
func _walk_state(key: StringName, sequence: Array[StringName]) -> Dictionary:
	var state: Variant = _walk.get(key)
	if state != null and state["spent"] == _biomes_data.points_spent(key) \
			and state["size"] == sequence.size() and is_same(state["src"], sequence):
		return state
	var fresh := {
		"index": 0, "seen": {}, "spent": _biomes_data.points_spent(key),
		"src": sequence, "size": sequence.size(),
	}
	_walk[key] = fresh
	return fresh

## This biome's point budget, held between actions. See _points.
func _available_points(key: StringName) -> int:
	var cached: Variant = _points.get(key)
	if cached != null and int(cached) > 0:
		return int(cached)
	var live := _biome_system.available_points(key)
	_points[key] = live
	return live
