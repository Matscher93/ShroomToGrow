class_name UpgradeSystem extends RefCounted
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

func level(id: StringName) -> int:
	return _levels.get(id, 0)

## Marks the cache stale — call when something a ScalingSource depends on changes
## (e.g. manual node count) so cacheable (non-live) sources get re-evaluated.
func invalidate() -> void:
	_dirty = true
	upgrades_changed.emit()

## Flat total of this upgrade's own effect at its current level (for display).
func effect_amount(id: StringName, ctx: ResolveContext) -> float:
	var def: UpgradeDef = _defs.get(id)
	if def == null or def.effects.is_empty():
		return 0.0
	var lvl := level(id)
	var e: UpgradeEffect = def.effects[0]
	var mag := e.magnitude(lvl)
	if e.dependency:
		mag *= e.dependency.evaluate(ctx)
	return mag

## Combines several upgrades' own effects into one overall % bonus, assuming
## each contributes multiplicatively (op MORE) — e.g. potency * synergy.
func combined_bonus(ids: Array, ctx: ResolveContext) -> float:
	var total := 1.0
	for id in ids:
		total *= (1.0 + effect_amount(id, ctx))
	return total - 1.0

func cost(id: StringName) -> float:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return 0.0
	return def.base_cost * pow(def.cost_growth, level(id))

func can_buy(id: StringName, nutrients: BigNumber) -> bool:
	var def: UpgradeDef = _defs.get(id)
	if def == null:
		return false
	if def.max_level > 0 and level(id) >= def.max_level:
		return false
	return nutrients.gte(BigNumber.from_value(cost(id)))

func buy(id: StringName, player_data: PlayerData) -> bool:
	if not can_buy(id, player_data.nutrients):
		return false
	player_data.nutrients = player_data.nutrients.sub(BigNumber.from_value(cost(id)))
	_levels[id] = level(id) + 1
	_dirty = true
	upgrades_changed.emit()
	return true

func to_save() -> Dictionary:
	var data := {}
	for id in _levels:
		var lvl: int = _levels[id]
		if lvl > 0:
			data[String(id)] = lvl
	return data

func from_save(data: Dictionary) -> void:
	for key in data:
		_levels[StringName(key)] = int(data[key])
	_dirty = true
	upgrades_changed.emit()

# Effect authoring side: which single bucket does this effect write into?
func _scope_key(scope: UpgradeEffect.Scope, target: StringName) -> String:
	match scope:
		UpgradeEffect.Scope.GLOBAL:
			return _K_GLOBAL
		UpgradeEffect.Scope.TAG:
			if target.is_empty():
				push_warning("TAG-scoped effect has no target; it will never apply.")
			return _K_TAG + String(target)
		UpgradeEffect.Scope.NODE:
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
		for e in (_defs[id] as UpgradeDef).effects:
			var mag: float = e.magnitude(lvl)
			if e.dependency:
				mag *= e.dependency.evaluate(ctx)
			var key := _scope_key(e.scope, e.target)
			var bucket: Dictionary = _cache.get(e.stat, {})
			var agg: Dictionary = bucket.get(key, {"add": 0.0, "inc": 0.0, "more": 1.0})
			match e.op:
				UpgradeEffect.Op.ADD:       agg.add  += mag
				UpgradeEffect.Op.INCREASED: agg.inc  += mag
				UpgradeEffect.Op.MORE:      agg.more *= (1.0 + mag)
			bucket[key] = agg
			_cache[e.stat] = bucket
	_dirty = false

func modify(stat: StringName, base: float, ctx: ResolveContext, tags: PackedStringArray = [],
			node_id: StringName = &"") -> float:
	if _dirty: _rebuild(ctx)
	var bucket: Dictionary = _cache.get(stat, {})
	var add := 0.0; var inc := 0.0; var more := 1.0
	for key in _applicable_keys(tags, node_id):   # ["g", "t:mycelium", "n:<id>"]
		var a: Dictionary = bucket.get(key, {})
		add += a.get("add", 0.0)
		inc += a.get("inc", 0.0)
		more *= a.get("more", 1.0)
	return (base + add) * (1.0 + inc) * more
