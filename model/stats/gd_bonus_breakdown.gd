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
##   "global_total": BigNumber,              # see below
##   "upgrade_count": int,
##   "sources": [{ "track": String, "upgrades": [{
##       "id": String, "name": String, "level": int,
##       "effects": [{"stat": String, "key": String, "op": int, "mag": BigNumber}],
##   }]}],
## }]
##
## `global_total` is the resource's first stat resolved through every track from
## a base of 1.0 - the real multiplier the game reads, memoised, not a sum of the
## rows. It is the GLOBAL bucket only: an effect scoped to one node or one tag
## writes a bucket of its own that no global read ever passes through, so those
## rows are listed but are not in the header number. A view showing the header
## has to say "global" for it to be true.
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
		out.append({
			"resource": resource,
			"stats": stats,
			"global_total": production.stack(StringName(stats[0]), BigNumber.from_value(1.0)),
			"upgrade_count": total,
			"sources": sources,
		})
	return out

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
