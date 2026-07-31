class_name UpgradeSystem
extends RefCounted
signal upgrades_changed

var _defs: Dictionary = {}      # id -> UpgradeDef
var _levels: Dictionary = {}    # id -> int   ← this is your save data
var _cache: Dictionary = {}     # stat -> { scope_key -> {add, inc, more} }
var _dirty := true

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

## Marks the cache stale — call when something a ScalingSourceDef depends on changes
## (e.g. manual node count) so cacheable (non-live) sources get re-evaluated.
func invalidate() -> void:
	_dirty = true
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

## Marginal gain from this upgrade's own effect a single additional level would
## add at the current level, ScalingSourceDef dependency included. This used to
## skip the dependency and leave callers to label the result as a per-unit rate,
## which meant an effect scaled by a dependency the player couldn't see from the
## panel advertised a gain it would never deliver.
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

## Combines several upgrades' own effects into one overall % bonus, assuming
## each contributes multiplicatively (op MORE) — e.g. potency * synergy.
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
	_dirty = true
	upgrades_changed.emit()
	return true

## Level up an upgrade paid for with a point budget (e.g. biome level points)
## instead of a BigNumber currency — always costs exactly 1 point.
##
## The point itself is spent by the caller, which owns the budget; this only
## needs to know whether one was available. It used to take the caller's point
## count as an int and compare it against 1 without ever deducting anything,
## which read like it did the spending.
func buy_with_points(id: StringName, has_point_available: bool) -> bool:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return false
	if def.max_level > 0 and level(id) >= def.max_level:
		return false
	if not has_point_available:
		return false
	_levels[id] = level(id) + 1
	_dirty = true
	upgrades_changed.emit()
	return true

## Sum of every registered upgrade's level — used as a biome XP source.
func total_levels() -> int:
	var total := 0
	for id in _levels:
		total += _levels[id]
	return total

## Clears purchased levels (e.g. on prestige) without touching _defs.
func reset() -> void:
	_levels.clear()
	for id in _defs:
		_levels[id] = 0
	_dirty = true
	upgrades_changed.emit()

func to_save() -> Dictionary:
	var data := {}
	for id in _levels:
		var lvl: int = _levels[id]
		if lvl > 0:
			data[String(id)] = lvl
	return data

## Levels for ids this system doesn't know are dropped, not stored: a renamed or
## deleted UpgradeDef (or a data directory that failed to load) would otherwise
## leave an id in _levels that _rebuild() has no def for.
func from_save(data: Dictionary) -> void:
	for key in data:
		var id := StringName(key)
		if not _defs.has(id):
			push_warning("Save contains unknown upgrade '%s' — dropping its level." % key)
			continue
		_levels[id] = int(data[key])
	_dirty = true
	upgrades_changed.emit()

# Effect authoring side: which single bucket does this effect write into?
func _scope_key(scope: UpgradeEffectDef.Scope, target: StringName) -> String:
	match scope:
		UpgradeEffectDef.Scope.GLOBAL:
			return _K_GLOBAL
		UpgradeEffectDef.Scope.TAG:
			if target.is_empty():
				push_warning("TAG-scoped effect has no target; it will never apply.")
			return _K_TAG + String(target)
		UpgradeEffectDef.Scope.NODE:
			if target.is_empty():
				push_warning("NODE-scoped effect has no target; it will never apply.")
			return _K_NODE + String(target)
		_:
			push_error("Unknown scope %d" % scope)
			return _K_GLOBAL

# Query side: which buckets does *this* node read from?
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

func modify(stat: StringName, base: BigNumber, ctx: ResolveContext, tags: PackedStringArray = [],
			node_id: StringName = &"") -> BigNumber:
	if _dirty: _rebuild(ctx)
	var bucket: Dictionary = _cache.get(stat, {})
	var add := BigNumber.new(0.0, 0)
	var inc := BigNumber.new(0.0, 0)
	var more := BigNumber.from_value(1.0)
	for key in _applicable_keys(tags, node_id):   # ["g", "t:mycelium", "n:<id>"]
		var a: Dictionary = bucket.get(key, {})
		add = add.add(a.get("add", BigNumber.new(0.0, 0)))
		inc = inc.add(a.get("inc", BigNumber.new(0.0, 0)))
		more = more.mul(a.get("more", BigNumber.from_value(1.0)))
	return base.add(add).mul(BigNumber.from_value(1.0).add(inc)).mul(more)
