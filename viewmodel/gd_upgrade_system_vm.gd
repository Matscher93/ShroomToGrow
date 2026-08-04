class_name UpgradeSystem
extends RefCounted
signal upgrades_changed

var _defs: Dictionary = {}      # id -> UpgradeDef
var _levels: Dictionary = {}    # id -> int, this is the save data
var _cache: Dictionary = {}     # stat -> { scope_key -> {add, inc, more} }
var _dirty := true

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
	_dirty = true

func has_def(id: StringName) -> bool:
	return _defs.has(id)

func def(id: StringName) -> UpgradeDef:
	return _defs.get(id)

func level(id: StringName) -> int:
	return _levels.get(id, 0)

## Marks the cache stale. Call when something a ScalingSourceDef depends on
## changes (e.g. manual node count) so those sources get re-evaluated.
func invalidate() -> void:
	_dirty = true
	_emit_changed()

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
	var lvl := level(id)
	var e: UpgradeEffectDef = def.effects[0]
	var mag := e.magnitude(lvl)
	if e.dependency:
		mag = mag.scale(e.dependency.evaluate(ctx))
	return mag

## Marginal gain one more level adds at the current level, ScalingSourceDef
## dependency included. The dependency has to be applied here, otherwise the
## panel advertises a gain the upgrade will never deliver.
func next_level_delta(id: StringName, ctx: ResolveContext) -> BigNumber:
	var def: UpgradeDef = _defs.get(id)
	if def == null or def.effects.is_empty():
		return BigNumber.new(0.0, 0)
	var lvl := level(id)
	var e: UpgradeEffectDef = def.effects[0]
	var delta := e.magnitude(lvl + 1).sub(e.magnitude(lvl))
	if e.dependency:
		delta = delta.scale(e.dependency.evaluate(ctx))
	return delta

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
	var scaled_level := pow(float(level(id)), def.cost_growth_exponent)
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
	_dirty = true
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
	_dirty = true
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
	_dirty = true
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
## id in _levels that _rebuild() has no def for.
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
	_dirty = true
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

func _rebuild(ctx: ResolveContext) -> void:
	_cache.clear()
	for id in _levels:
		var lvl: int = _levels[id]
		if lvl <= 0: continue
		var upgrade_def: UpgradeDef = _defs.get(id)
		if upgrade_def == null:
			continue
		for e in upgrade_def.effects:
			var mag: BigNumber = e.magnitude(lvl)
			if e.dependency:
				mag = mag.scale(e.dependency.evaluate(ctx))
			var key := _scope_key(e.scope, e.target)
			var bucket: Dictionary = _cache.get(e.stat, {})
			var agg: Dictionary = bucket.get(key, {
				"add": BigNumber.new(0.0, 0),
				"inc": BigNumber.new(0.0, 0),
				"more": BigNumber.from_value(1.0),
			})
			match e.op:
				UpgradeEffectDef.Op.ADD:       agg.add  = agg.add.add(mag)
				UpgradeEffectDef.Op.INCREASED: agg.inc  = agg.inc.add(mag)
				UpgradeEffectDef.Op.MORE:      agg.more = agg.more.mul(BigNumber.from_value(1.0).add(mag))
			bucket[key] = agg
			_cache[e.stat] = bucket
	_dirty = false

## Hot path: every displayed stat resolves through this, three times over (one
## per track), and the automation tick drives it hundreds of times a tick. Hence
## the null accumulators and the bare Dictionary.get() - the identity BigNumbers
## the old default arguments built for every miss, then threw away, were most of
## the cost of a cache hit.
func modify(stat: StringName, base: BigNumber, ctx: ResolveContext, tags: PackedStringArray = [],
			node_id: StringName = &"") -> BigNumber:
	if _dirty: _rebuild(ctx)
	var bucket: Dictionary = _cache.get(stat, {})
	if bucket.is_empty():
		return base.copy()
	var add: BigNumber = null
	var inc: BigNumber = null
	var more: BigNumber = null
	for key in _applicable_keys(tags, node_id):   # ["g", "t:mycelium", "n:<id>"]
		var agg: Variant = bucket.get(key)
		if agg == null:
			continue
		# _rebuild() always writes all three, so no per-key defaults are needed.
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
