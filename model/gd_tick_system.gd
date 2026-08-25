class_name TickSystem
extends RefCounted
## MODEL: the per-tick production cascade.
##
## Each node tier's output feeds the tier below it, and tier 0 feeds nutrients.
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

var _nodes: Array[MyceliumNode]
var _player_data: PlayerData
var _production: ProductionSystem
## The well's pump, driven from here so every caller that advances ticks - the
## live timer, the offline catch-up and the simulator's strides - moves water
## too. Optional so a test that only cares about the node cascade can build this
## with three arguments.
var _water: WaterSystem

## Nutrients paid out by the most recent handle_tick(), for a caller that wants
## the run's production per tick without recomputing the cascade - the statistics
## overlay's peak-production record reads it once per tick.
##
## Only handle_tick() writes it. advance_ticks() deliberately leaves it alone: a
## strided catch-up lands on the same state as N single ticks but never computes
## any one tick's payout, so there is no honest value to put here and a made-up
## one would set a peak the player never reached.
var last_tick_gain: BigNumber = BigNumber.new(0.0, 0)

func _init(nodes: Array[MyceliumNode], player_data: PlayerData,
		production: ProductionSystem, water: WaterSystem = null) -> void:
	_nodes = nodes
	_player_data = player_data
	_production = production
	_water = water

## Per-node production multiplier, indexed like the node array. Callers driving
## many ticks back-to-back (offline catch-up) compute this once and pass it into
## handle_tick(): node_production_bonus() is a chain of ~9 UpgradeSystem.modify()
## calls, and redoing it per node per tick dominates a long catch-up loop. Safe
## to hoist because its only live inputs are upgrade levels and manual node
## counts, and every ScalingSourceDef kind is player-action driven (see
## ResolveContext), so nothing goes stale mid-loop.
func node_production_bonuses() -> Array[BigNumber]:
	var bonuses: Array[BigNumber] = []
	for node in _nodes:
		bonuses.append(_production.node_production_bonus(node.id_key))
	return bonuses

## Advances the game one tick. Pass `bonuses` to reuse a hoisted set, leave it
## empty to compute them fresh.
func handle_tick(bonuses: Array[BigNumber] = []) -> void:
	# Read before the counter moves: the pump is due on multiples of its interval,
	# so it needs the tick the span starts from, not the one it ends on.
	var before := _player_data.tick_count
	_player_data.tick_count += 1
	_player_data.lifetime_ticks += 1
	if _water != null:
		_water.handle_ticks(before, 1)
	if bonuses.is_empty():
		bonuses = node_production_bonuses()
	# Highest tier first, and that order is load-bearing: each tier writes into
	# the tier below *before* that tier produces, so a top-tier gain reaches
	# nutrients within the same tick. Iterating upwards instead would park each
	# tier's output for the next tick, stretching the payout of an N-tier chain
	# over N ticks and flattening the whole idle curve.
	for i in range(_nodes.size() - 1, -1, -1):
		var node := _nodes[i]
		var node_change := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		node_change = node_change.mul(bonuses[i])
		if i != 0:
			var receiving_node := _nodes[i - 1]
			receiving_node.auto_nodes = receiving_node.auto_nodes.add(node_change)
		else:
			_player_data.nutrients = _player_data.nutrients.add(node_change)
			_player_data.lifetime_nutrients = _player_data.lifetime_nutrients.add(node_change)
			last_tick_gain = node_change

## Advances `count` ticks in one step, landing on exactly the state `count`
## calls to handle_tick() would have reached.
##
## Only sound while nothing is bought in between: manual counts and bonuses are
## read once and treated as fixed for the whole span, which is what makes the
## jump possible at all. The caller owns that guarantee - see the simulator,
## which only strides across stretches it has established are idle.
##
## The trick is that one tick is a *linear* map on (auto nodes, nutrients) once
## the manual counts are held still: each tier adds a fixed multiple of itself to
## the tier below. Its linear part differs from the identity only by a nilpotent
## one - a tier can only ever feed downwards - so the map's powers terminate:
##
##     T^K(v) = v + sum_j C(K, j) * d_j,  where d_1 = T(v) - v and d_(j+1) is the
##                                        same difference taken again
##
## and d_j is zero once j passes the number of tiers. A dozen differences
## therefore describe a jump of any length, which is what lets a week of game
## time cost about what a single tick costs. Nothing here approximates: for
## count = 1 the sum is exactly T(v).
func advance(count: int, bonuses: Array[BigNumber] = []) -> void:
	advance_by(count, jump_kernel(bonuses))

## The differences a jump from *this* state is built from. They depend on the
## state and the bonuses but not on how far the jump goes, so a caller trying
## several lengths from the same state - the simulator, searching for how long a
## lull lasts - builds this once and pays only the weighted sum per attempt.
##
## Valid exactly as long as advance_by() is: until something is bought, or the
## state moves by any route other than advance_by() itself.
func jump_kernel(bonuses: Array[BigNumber] = []) -> Array:
	if bonuses.is_empty():
		bonuses = node_production_bonuses()
	# One entry per tier plus the nutrients they pour into. The first difference
	# is taken with the manual counts, since those are the map's constant term;
	# every later one is a difference of differences, where the constant has
	# already cancelled.
	var kernel: Array = []
	var difference := _difference(_state(), bonuses, true)
	for _j in range(1, _nodes.size() + 2):
		if _is_zero(difference):
			break
		kernel.append(difference)
		difference = _difference(difference, bonuses, false)
	return kernel

## Advances `count` ticks using a kernel from jump_kernel(), taken at the state
## this is being applied to.
func advance_by(count: int, kernel: Array) -> void:
	if count <= 0:
		return
	# Same contract as handle_tick(): the pump counts the multiples that fall
	# inside the span, which is what makes a stride pay exactly what walking the
	# span one tick at a time would.
	var before := _player_data.tick_count
	_player_data.tick_count += count
	_player_data.lifetime_ticks += count
	if _water != null:
		_water.handle_ticks(before, count)

	var totals := _state()
	var binomial := BigNumber.from_value(1.0)
	for j in kernel.size():
		# C(count, j+1) from C(count, j), which keeps the whole series to one
		# multiply each - and a factorial of a dozen never gets built.
		binomial = binomial.scale(float(count - j) / float(j + 1))
		if binomial.mantissa == 0.0:
			break     # count ticks cannot reach this far down the chain yet
		totals = _add_scaled(totals, kernel[j], binomial)

	for i in _nodes.size():
		_nodes[i].auto_nodes = totals[i]
	var gained: BigNumber = totals[_nodes.size()].sub(_player_data.nutrients)
	_player_data.nutrients = totals[_nodes.size()]
	_player_data.lifetime_nutrients = _player_data.lifetime_nutrients.add(gained)

## The live state as the flat vector the jump works on: one auto-node count per
## tier, then nutrients.
func _state() -> Array:
	var out: Array = []
	for node in _nodes:
		out.append(node.auto_nodes)
	out.append(_player_data.nutrients)
	return out

## One tick's worth of change to `vector`, which is the tick itself minus what
## went in. `with_manual` is true only for the first difference: hand-bought
## nodes are the map's constant term, and a difference of differences has
## already cancelled it.
func _difference(vector: Array, bonuses: Array[BigNumber], with_manual: bool) -> Array:
	var moved := vector.duplicate()
	for i in range(_nodes.size() - 1, -1, -1):
		var producing: BigNumber = moved[i]
		if with_manual:
			producing = producing.add(BigNumber.from_value(_nodes[i].manual_nodes))
		var change := producing.mul(bonuses[i])
		if i != 0:
			moved[i - 1] = moved[i - 1].add(change)
		else:
			moved[_nodes.size()] = moved[_nodes.size()].add(change)
	var out: Array = []
	for i in moved.size():
		out.append(moved[i].sub(vector[i]))
	return out

func _is_zero(vector: Array) -> bool:
	for value: BigNumber in vector:
		if value.mantissa != 0.0:
			return false
	return true

func _add_scaled(vector: Array, addend: Array, factor: BigNumber) -> Array:
	var out: Array = []
	for i in vector.size():
		out.append(vector[i].add(addend[i].mul(factor)))
	return out
