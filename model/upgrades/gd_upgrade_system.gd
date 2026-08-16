class_name UpgradeSystem
extends RefCounted
## MODEL: one track of purchasable upgrade levels, and the resolved effect cache
## they add up to.
##
## Backs all four tracks (symbiosis, biome upgrades, perks, crystal boosts), which
## is what lets ProductionSystem stack them without any per-stat wiring: they all
## write into the same stat buckets. A defect here is a defect everywhere at once.
##
## Holds only its own state, no App reference, so it can be built and exercised
## in isolation.

signal upgrades_changed

var _defs: Dictionary = {}      # id -> UpgradeDef
var _levels: Dictionary = {}    # id -> int, this is the save data

## The resolved effects, in two layers, because a purchase invalidates far less
## than it used to redo.
##
## _contrib holds what one upgrade contributes at its current level, with its
## ScalingSourceDef already applied - the expensive half, since a magnitude is a
## pow() and a dependency is a context read. _cache holds the summed buckets one
## stat resolves through, which is the only thing modify() actually reads.
##
## Buying a level makes exactly one upgrade's contribution stale, and through it
## only the stats that upgrade writes. invalidate() makes the context-reading
## upgrades stale and nothing else. Both layers rebuild lazily, per stat, on the
## next read - so a stat nothing asks for is never summed at all.
var _cache: Dictionary = {}     # stat -> { scope_key -> {add, inc, more} }
var _contrib: Dictionary = {}   # id -> Array[Dictionary] {stat, key, op, mag}
var _stat_ids: Dictionary = {}  # stat -> { id -> true }, who writes into it
var _stale: Dictionary = {}     # id -> true, contributions to recompute
var _stat_dirty: Dictionary = {}  # stat -> true, buckets to re-sum

## Upgrades whose magnitude reads the ResolveContext, and so the only ones an
## invalidate() can have moved. Everything else is a pure function of its level.
var _context_readers: Dictionary = {}

## Bumped by every change that makes the resolved effects stale. A caller
## stacking several tracks can memoise a resolved value and drop it the moment
## any track moves, without knowing what moved - see ProductionSystem, which
## resolves the same handful of stats dozens of times per tick from unchanged
## levels.
var version: int = 0

## While non-zero, changes still mark the cache stale immediately but hold their
## signal until the outermost end_batch(). See begin_batch().
var _batch_depth := 0
var _batch_pending := false

## Levels ever bought through this system, including ones a later reset() wiped.
## Raised only by the two purchase paths, so it counts real purchases rather than
## whatever _levels happens to hold: a save load or a prestige must not move it.
##
## Lives here rather than at the call sites because buying is this class's rule,
## and symbiosis alone is bought from two places (the node panel and the
## automation that tends it).
var lifetime_levels: int = 0

## Save key for lifetime_levels. '#' never appears in an authored UpgradeDef.id,
## so it cannot collide with one.
const LIFETIME_KEY := "#lifetime"

const _K_GLOBAL := "g"
const _K_TAG    := "t:"
const _K_NODE   := "n:"

func register(def: UpgradeDef) -> void:
	_defs[def.id] = def
	if not _levels.has(def.id):
		_levels[def.id] = 0
	if _reads_context(def):
		_context_readers[def.id] = true
	else:
		_context_readers.erase(def.id)   # a re-register may have dropped the dependency
	_touch([def.id])

func has_def(id: StringName) -> bool:
	return _defs.has(id)

func def(id: StringName) -> UpgradeDef:
	return _defs.get(id)

func level(id: StringName) -> int:
	return _levels.get(id, 0)

## Marks the cache stale. Call when something a ScalingSourceDef depends on
## changes (e.g. manual node count) so those sources get re-evaluated.
##
## Only the upgrades that actually read a context are re-evaluated. The rest
## resolve from their level alone, and a manual node count moving cannot change
## what they contribute.
func invalidate() -> void:
	_touch(_context_readers.keys())
	_emit_changed()

## Stale, and say so. Every write path goes through here rather than touching
## the caches itself, so no change can move the levels without moving `version`
## - which is what a caller memoising across tracks watches. `ids` may be empty
## and the version still moves: an invalidate() with no context-reading upgrades
## in this track can still have moved another one.
func _touch(ids: Array) -> void:
	for id: StringName in ids:
		_stale[id] = true
	version += 1

## True when any of this upgrade's effects scales by something outside itself.
static func _reads_context(def: UpgradeDef) -> bool:
	for e: UpgradeEffectDef in def.effects:
		if e.dependency != null and e.dependency.kind != ScalingSourceDef.Kind.NONE:
			return true
	return false

## Collapses a burst of purchases into one upgrades_changed.
##
## Every listener on that signal refreshes synchronously - the tick duration, the
## biome panels' slot grids, each node card - and the automation tick can buy
## dozens of levels in a single frame, which otherwise means dozens of full
## refreshes for one visible change. Purchases inside a batch still mark the
## cache stale as they happen, so any read in between sees the new levels.
##
## Always pair with end_batch(). Nesting is counted, only the outermost emits.
func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth > 0 or not _batch_pending:
		return
	_batch_pending = false
	upgrades_changed.emit()

func _emit_changed() -> void:
	if _batch_depth > 0:
		_batch_pending = true
		return
	upgrades_changed.emit()

## Flat total of this upgrade's own effect at its current level (for display).
func effect_amount(id: StringName, ctx: ResolveContext) -> BigNumber:
	var def: UpgradeDef = _defs.get(id)
	if def == null or def.effects.is_empty():
		return BigNumber.new(0.0, 0)
	return def.effects[0].contribution(level(id), ctx)

## Marginal gain one more level adds at the current level, ScalingSourceDef
## dependency and cap included. Both have to be applied here, otherwise the panel
## advertises a gain the upgrade will never deliver.
##
## Taken as the difference of two contributions rather than of two magnitudes: a
## capped effect has to report zero once it is sitting on its ceiling, and the
## difference of the uncapped magnitudes would keep promising a full level's
## worth forever.
func next_level_delta(id: StringName, ctx: ResolveContext) -> BigNumber:
	var def: UpgradeDef = _defs.get(id)
	if def == null or def.effects.is_empty():
		return BigNumber.new(0.0, 0)
	var lvl := level(id)
	var e: UpgradeEffectDef = def.effects[0]
	return e.contribution(lvl + 1, ctx).sub(e.contribution(lvl, ctx))

## Combines several upgrades' effects into one overall % bonus, assuming each
## contributes multiplicatively (op MORE), e.g. potency * synergy.
func combined_bonus(ids: Array, ctx: ResolveContext) -> BigNumber:
	var total := BigNumber.from_value(1.0)
	for id in ids:
		total = total.mul(BigNumber.from_value(1.0).add(effect_amount(id, ctx)))
	return total.sub(BigNumber.from_value(1.0))

func cost(id: StringName) -> BigNumber:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return BigNumber.new(0.0, 0)
	var scaled_level := float(level(id)) * pow(def.cost_growth_exponent, float(level(id)))
	return def.base_cost.mul(BigNumber.from_value(def.cost_growth).pow_float(scaled_level))

func can_buy(id: StringName, nutrients: BigNumber) -> bool:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return false
	if def.max_level > 0 and level(id) >= def.max_level:
		return false
	return nutrients.gte(cost(id))

func buy(id: StringName, player_data: PlayerData, currency: StringName = &"nutrients") -> bool:
	var current: BigNumber = player_data.get(currency)
	if not can_buy(id, current):
		return false
	player_data.set(currency, current.sub(cost(id)))
	_levels[id] = level(id) + 1
	lifetime_levels += 1
	_touch([id])
	_emit_changed()
	return true

## Level up an upgrade paid for with a point budget (e.g. biome level points)
## instead of a BigNumber currency. Always costs exactly 1 point.
##
## The caller owns the budget and spends the point itself. This only needs to
## know whether one was available.
func buy_with_points(id: StringName, has_point_available: bool) -> bool:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return false
	if def.max_level > 0 and level(id) >= def.max_level:
		return false
	if not has_point_available:
		return false
	_levels[id] = level(id) + 1
	lifetime_levels += 1
	_touch([id])
	_emit_changed()
	return true

## Sum of every registered upgrade's level, used as a biome XP source.
func total_levels() -> int:
	var total := 0
	for id in _levels:
		total += _levels[id]
	return total

## Clears purchased levels (e.g. on prestige) without touching _defs.
## lifetime_levels is deliberately left alone: it counts purchases, and a
## prestige does not un-buy them.
func reset() -> void:
	_levels.clear()
	for id in _defs:
		_levels[id] = 0
	_touch(_defs.keys())
	_emit_changed()

func to_save() -> Dictionary:
	var data := {}
	for id in _levels:
		var lvl: int = _levels[id]
		if lvl > 0:
			data[String(id)] = lvl
	if lifetime_levels > 0:
		data[LIFETIME_KEY] = lifetime_levels
	return data

## Levels for unknown ids are dropped, not stored. A renamed or deleted
## UpgradeDef, or a data directory that failed to load, would otherwise leave an
## id in _levels that no def backs.
func from_save(data: Dictionary) -> void:
	for key in data:
		if key == LIFETIME_KEY:
			lifetime_levels = int(data[key])
			continue
		var id := StringName(key)
		if not _defs.has(id):
			push_warning("Save contains unknown upgrade '%s', dropping its level." % key)
			continue
		_levels[id] = int(data[key])
	_touch(_defs.keys())
	_emit_changed()

# Authoring side: which bucket does this effect write into?
func _scope_key(scope: UpgradeEffectDef.Scope, target: StringName) -> String:
	match scope:
		UpgradeEffectDef.Scope.GLOBAL:
			return _K_GLOBAL
		UpgradeEffectDef.Scope.TAG:
			if target.is_empty():
				push_warning("TAG-scoped effect has no target, it will never apply.")
			return _K_TAG + String(target)
		UpgradeEffectDef.Scope.NODE:
			if target.is_empty():
				push_warning("NODE-scoped effect has no target, it will never apply.")
			return _K_NODE + String(target)
		_:
			push_error("Unknown scope %d" % scope)
			return _K_GLOBAL

# Query side: which buckets does this node read from?
func _applicable_keys(tags: PackedStringArray, node_id: StringName) -> PackedStringArray:
	var keys := PackedStringArray([_K_GLOBAL])   # global always applies
	for tag in tags:
		keys.append(_K_TAG + tag)
	if not node_id.is_empty():
		keys.append(_K_NODE + String(node_id))
	return keys

## Re-resolves every upgrade marked stale, and marks the stats they write - the
## ones they used to write included, so an upgrade that stops contributing takes
## its old bucket down with it.
func _resolve_stale(ctx: ResolveContext) -> void:
	for id: StringName in _stale:
		_forget(id)
		_remember(id, ctx)
	_stale.clear()

func _forget(id: StringName) -> void:
	for c: Dictionary in _contrib.get(id, []):
		_stat_dirty[c["stat"]] = true
		var writers: Dictionary = _stat_ids.get(c["stat"], {})
		writers.erase(id)
	_contrib.erase(id)

## What this upgrade contributes at its current level. Nothing at level zero, and
## nothing for an id no def backs - a save can carry one past a rename.
func _remember(id: StringName, ctx: ResolveContext) -> void:
	var lvl: int = _levels.get(id, 0)
	if lvl <= 0: return
	var upgrade_def: UpgradeDef = _defs.get(id)
	if upgrade_def == null: return
	var out: Array[Dictionary] = []
	for e: UpgradeEffectDef in upgrade_def.effects:
		var mag: BigNumber = e.contribution(lvl, ctx)
		out.append({"stat": e.stat, "key": _scope_key(e.scope, e.target), "op": e.op, "mag": mag})
		_stat_dirty[e.stat] = true
		if not _stat_ids.has(e.stat):
			_stat_ids[e.stat] = {}
		_stat_ids[e.stat][id] = true
	_contrib[id] = out

## One stat's buckets, summed from the upgrades writing it. Re-summed only when
## one of those upgrades moved, and only when something asks for this stat.
func _bucket(stat: StringName) -> Dictionary:
	if not _stat_dirty.has(stat):
		return _cache.get(stat, {})
	_stat_dirty.erase(stat)
	var bucket := {}
	for id: StringName in _stat_ids.get(stat, {}):
		for c: Dictionary in _contrib.get(id, []):
			if c["stat"] != stat:
				continue     # a multi-effect upgrade writing more than one stat
			var agg: Dictionary = bucket.get(c["key"], {
				"add": BigNumber.new(0.0, 0),
				"inc": BigNumber.new(0.0, 0),
				"more": BigNumber.from_value(1.0),
			})
			var mag: BigNumber = c["mag"]
			match c["op"]:
				UpgradeEffectDef.Op.ADD:       agg.add  = agg.add.add(mag)
				UpgradeEffectDef.Op.INCREASED: agg.inc  = agg.inc.add(mag)
				UpgradeEffectDef.Op.MORE:      agg.more = agg.more.mul(BigNumber.from_value(1.0).add(mag))
			bucket[c["key"]] = agg
	_cache[stat] = bucket
	return bucket

## Hot path: every displayed stat resolves through this, three times over (one
## per track), and the automation tick drives it hundreds of times a tick. Hence
## the null accumulators and the bare Dictionary.get() - the identity BigNumbers
## the old default arguments built for every miss, then threw away, were most of
## the cost of a cache hit.
func modify(stat: StringName, base: BigNumber, ctx: ResolveContext, tags: PackedStringArray = [],
			node_id: StringName = &"") -> BigNumber:
	if not _stale.is_empty():
		_resolve_stale(ctx)
	var bucket := _bucket(stat)
	if bucket.is_empty():
		return base.copy()
	var add: BigNumber = null
	var inc: BigNumber = null
	var more: BigNumber = null
	for key in _applicable_keys(tags, node_id):   # ["g", "t:mycelium", "n:<id>"]
		var agg: Variant = bucket.get(key)
		if agg == null:
			continue
		# _bucket() always writes all three, so no per-key defaults are needed.
		add = agg["add"] if add == null else add.add(agg["add"])
		inc = agg["inc"] if inc == null else inc.add(agg["inc"])
		more = agg["more"] if more == null else more.mul(agg["more"])
	if add == null:
		return base.copy()   # stat exists, but nothing this caller reads from
	var value := base.add(add)
	if inc.mantissa != 0.0:
		value = value.mul(inc.add(BigNumber.new(1.0, 0)))
	if more.mantissa != 1.0 or more.exponent != 0:
		value = value.mul(more)
	return value
