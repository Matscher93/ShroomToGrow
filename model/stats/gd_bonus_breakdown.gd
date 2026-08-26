class_name BonusBreakdown
extends RefCounted
## MODEL: what every levelled upgrade is contributing right now, grouped the way
## a player asks about it - by the resource it moves, then by the track it comes
## from, then upgrade by upgrade.
##
## The same grouping the balance simulator's bonus breakdown uses, and off the
## same table (StatResources), but with the magnitudes only. The simulator's
## second number - the measured impact, taken by zeroing a level and letting the
## run re-resolve - costs one probe per levelled upgrade and is not something to
## do to a live, ticking game. What is left is exact rather than comparable: a
## +0.15 INCREASED and a +0.15 MORE are both honest and are not the same size.
##
## The rows come out of UpgradeSystem's own _contrib cache, so a breakdown cannot
## disagree with what modify() actually applies - the magnitudes already have
## their ScalingSourceDef and their cap in them.

## Every resource with something levelled feeding it. Shape:
##
## [{
##   "resource": String, "stats": Array,     # the buckets this resource is made of
##   "additive": bool,                       # see below
##   "total": BigNumber, "total_scope": String,
##   "upgrade_count": int,
##   "sources": [{ "track": String, "upgrades": [{
##       "id": String, "name": String, "level": int,
##       "effects": [{"stat": String, "key": String, "op": int, "mag": BigNumber}],
##   }]}],
## }]
##
## `total` is measured through stack() rather than summed from the rows, so it is
## exactly what the game reads, memoised. Two things decide what it means:
##
## `additive` is true when every effect on the resource is an ADD, which makes it
## an amount rather than a multiplier - tick speed and the water pump are both
## authored as seconds subtracted from an interval, so they resolve from a base
## of zero and 1.0 is not the base of anything. Everything else resolves from 1.0
## and multiplies, and where a resource is several buckets the buckets chain: a
## node's nutrient output is its potency multiplier times its synergy multiplier
## with the node_production multipliers stacked over both, which is what
## ProductionSystem.node_production_bonus() spells out.
##
## `total_scope` is the bucket key `total` was resolved at, "" for global. Scoped
## effects are the reason it exists: the crystal Nutrient Flow boost is authored
## against node 0, so no global read passes through it at all, and a header
## resolved globally sat orders of magnitude below rows listed underneath it. The
## scope reported is whichever one resolves largest - the best a single target
## actually gets - so the header is never smaller than the rows explaining it.
static func build(production: ProductionSystem) -> Array:
	var rows_by_track: Dictionary = production.breakdown()

	# resource -> track -> id -> upgrade row. Three levels because one upgrade
	# writing two resources belongs under both, carrying only that resource's
	# effect lines in each.
	var grouped := {}
	var stats_by_resource := {}
	for pair: Array in production.tracks():
		var track: String = pair[0]
		for row: Dictionary in rows_by_track.get(track, []):
			var group := StatResources.resource_of(row["stat"])
			var resource: String = group["resource"]
			if not stats_by_resource.has(resource):
				stats_by_resource[resource] = group["stats"]
			var tracks: Dictionary = grouped.get(resource, {})
			grouped[resource] = tracks
			var upgrades: Dictionary = tracks.get(track, {})
			tracks[track] = upgrades
			var upgrade: Dictionary = upgrades.get(row["id"], {
				"id": row["id"], "name": row["name"], "level": row["level"], "effects": [],
			})
			upgrades[row["id"]] = upgrade
			upgrade["effects"].append({
				"stat": row["stat"], "key": row["key"], "op": row["op"], "mag": row["mag"],
			})

	var out: Array = []
	for resource: String in StatResources.resource_order(grouped.keys()):
		var stats: Array = stats_by_resource[resource]
		var tracks: Dictionary = grouped[resource]
		var sources: Array = []
		var total := 0
		# Walked through tracks() rather than through the dictionary, so the
		# sources read in stacking order - the order the game actually applies
		# them in, which is the order that explains the number in the header.
		for pair: Array in production.tracks():
			var track: String = pair[0]
			if not tracks.has(track):
				continue
			var upgrades: Array = (tracks[track] as Dictionary).values()
			upgrades.sort_custom(_heavier_first)
			total += upgrades.size()
			sources.append({"track": track, "upgrades": upgrades})
		var additive := _is_additive(sources)
		var scope := _best_scope(production, stats, sources, additive)
		out.append({
			"resource": resource,
			"stats": stats,
			"additive": additive,
			"total": _total(production, stats, additive, scope),
			"total_scope": scope,
			"upgrade_count": total,
			"sources": sources,
		})
	return out

## True when nothing here multiplies anything - every effect is an ADD.
##
## Read off the rows rather than off a field somebody has to remember to author:
## a stat is additive because of how its effects are written, and asking them is
## the only answer that cannot drift from them.
static func _is_additive(sources: Array) -> bool:
	for source: Dictionary in sources:
		for upgrade: Dictionary in source["upgrades"]:
			for effect: Dictionary in upgrade["effects"]:
				if int(effect["op"]) != UpgradeEffectDef.Op.ADD:
					return false
	return true

## The resource's stats resolved together at one scope - the product of them for
## a multiplicative resource, the sum for an additive one.
static func _total(production: ProductionSystem, stats: Array, additive: bool,
		scope: String) -> BigNumber:
	var target := _target_of(scope)
	if additive:
		var sum := BigNumber.new(0.0, 0)
		for stat: String in stats:
			sum = sum.add(production.stack(StringName(stat), BigNumber.new(0.0, 0), target))
		return sum
	var product := BigNumber.from_value(1.0)
	for stat: String in stats:
		product = product.mul(production.stack(StringName(stat),
			BigNumber.from_value(1.0), target))
	return product

## Whichever scope the rows write into resolves largest, "" when that is global.
##
## Node buckets only. A tag bucket cannot be reached through stack() at all - it
## forwards its target as modify()'s node_id and always passes an empty tag list
## - and nothing in data/ authors a tag-scoped effect today, so the gap costs
## nothing until one does.
static func _best_scope(production: ProductionSystem, stats: Array, sources: Array,
		additive: bool) -> String:
	var best := ""
	var best_size := _magnitude(_total(production, stats, additive, ""))
	for key: String in _scope_keys(sources):
		if not key.begins_with("n:"):
			continue
		var size := _magnitude(_total(production, stats, additive, key))
		if size.gt(best_size):
			best = key
			best_size = size
	return best

## Every bucket key the resource's rows write into.
static func _scope_keys(sources: Array) -> Array:
	var keys: Array = []
	for source: Dictionary in sources:
		for upgrade: Dictionary in source["upgrades"]:
			for effect: Dictionary in upgrade["effects"]:
				var key := String(effect["key"])
				if not keys.has(key):
					keys.append(key)
	return keys

## A bucket key as the target stack() takes: "n:7" is how the bucket is filed,
## &"7" is the node it belongs to.
static func _target_of(scope: String) -> StringName:
	if scope.begins_with("n:"):
		return StringName(scope.substr(2))
	return &""

## Size without sign, so a tick-speed total of -12.7s ranks as bigger than -3.0s
## rather than smaller.
static func _magnitude(value: BigNumber) -> BigNumber:
	return BigNumber.new(absf(value.mantissa), value.exponent)

## Biggest first, within one track and one resource. MORE above INCREASED above
## ADD, because that is the order they compound in and the order the ops rank in
## when the magnitudes are all a view has; ties broken by the magnitude itself.
static func _heavier_first(a: Dictionary, b: Dictionary) -> bool:
	var a_op := _top_op(a)
	var b_op := _top_op(b)
	if a_op != b_op:
		return a_op > b_op
	var a_mag := _top_magnitude(a)
	var b_mag := _top_magnitude(b)
	if a_mag.same_value(b_mag):
		return a["name"] < b["name"]
	return a_mag.gt(b_mag)

static func _top_op(upgrade: Dictionary) -> int:
	var top := -1
	for effect: Dictionary in upgrade["effects"]:
		top = maxi(top, int(effect["op"]))
	return top

static func _top_magnitude(upgrade: Dictionary) -> BigNumber:
	var top := BigNumber.new(0.0, 0)
	for effect: Dictionary in upgrade["effects"]:
		var mag: BigNumber = effect["mag"]
		if mag.gt(top):
			top = mag
	return top
