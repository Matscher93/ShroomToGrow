class_name StatResources
extends RefCounted
## MODEL: which stat buckets feed which resource, in the order a reader wants
## them.
##
## A stat bucket is not what anyone asks about - "what is pushing nutrients" is,
## and three buckets answer it. This is where that question is answered rather
## than in whichever page draws the table, because both readers group by it: the
## balance simulator, whose per-resource probe has to know which upgrades belong
## together before it can take them all away at once, and the statistics
## overlay's bonus breakdown, which shows the same grouping without the probe.
##
## `metric` says which of a probe's numbers ranks that resource, and is read only
## by the simulator - three of them are measured against what the run itself does
## (nutrients per tick, the seconds a tick takes, the ticks between pumps), the
## rest get `stat`: the share of their own bucket, because production per tick
## does not read a &"biomass_gain" upgrade at all and ranking those by the
## production drop would rank them by zeroes.
##
## A stat missing here gets a resource of its own, named after the stat and
## ranked by its bucket - a new stat in data/ turning up unranked beats it
## vanishing.

const RESOURCES := [
	{"resource": "nutrients", "metric": "production",
		"stats": ["node_production", "potency_production", "synergy_production"]},
	{"resource": "tick speed", "metric": "tick", "stats": ["tick_rate"]},
	{"resource": "water", "metric": "stat", "stats": ["water_production"]},
	{"resource": "water pump", "metric": "water", "stats": ["water_rate"]},
	{"resource": "biomass", "metric": "stat", "stats": ["biomass_gain"]},
	{"resource": "crystals", "metric": "stat", "stats": ["crystal_gain"]},
	{"resource": "relics", "metric": "stat", "stats": ["relic_gain"]},
	{"resource": "ichor", "metric": "stat", "stats": ["ichor_gain"]},
	{"resource": "glyphs", "metric": "stat", "stats": ["glyph_gain"]},
	{"resource": "automation", "metric": "stat", "stats": ["automation_rate"]},
	{"resource": "missions", "metric": "stat",
		"stats": ["mission_speed", "mission_reward", "farm_slots"]},
	{"resource": "boosts", "metric": "stat",
		"stats": ["boost_power", "boost_max_level", "creature_rank_cap"]},
	{"resource": "biome points", "metric": "stat",
		"stats": ["biome_points", "level_points"]},
]


## The resource a stat feeds, or one invented for a stat RESOURCES does not name.
static func resource_of(stat: String) -> Dictionary:
	for group: Dictionary in RESOURCES:
		if group["stats"].has(stat):
			return group
	return {"resource": stat, "metric": "stat", "stats": [stat]}


## The resources present, in the order RESOURCES declares them, with the ones it
## does not name after all of them, alphabetically.
static func resource_order(present: Array) -> Array:
	var out: Array = []
	for group: Dictionary in RESOURCES:
		if present.has(group["resource"]):
			out.append(group["resource"])
	var extra: Array = []
	for res: String in present:
		if not out.has(res):
			extra.append(res)
	extra.sort()
	return out + extra


## An UpgradeEffectDef.Op as the word a breakdown row prints.
static func op_name(op: int) -> String:
	match op:
		UpgradeEffectDef.Op.ADD: return "ADD"
		UpgradeEffectDef.Op.INCREASED: return "INCREASED"
		UpgradeEffectDef.Op.MORE: return "MORE"
		_: return "?"
