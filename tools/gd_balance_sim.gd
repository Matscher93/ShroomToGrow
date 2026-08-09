extends Node

## Headless run simulator: how long the authored numbers actually take to play.
##
##   godot --headless tools/sc_balance_sim.tscn -- \
##       [--ticks=20000] [--policy=roi|cheapest|nodes_only] [--prestiges=3] \
##       [--samples=200] --out=FILE
##   godot --headless tools/sc_balance_sim.tscn -- --report --out=FILE
##
## Run as a scene rather than with --script, because the ViewModels App builds
## address the App autoload by name and that identifier only exists when Godot
## starts normally.
##
## It drives the real composition root, so adding an upgrade track to
## App._ready() is picked up without touching this file. Purchases go through
## BalancePolicy, which only ever calls public App methods.
##
## Results go to --out as JSON, because stdout carries the engine banner. Exit
## code is non-zero on error.

const AppScript := preload("res://autoload/gd_app.gd")
const BalanceDataScript := preload("res://tools/gd_balance_data.gd")
## Preloaded rather than named: a class_name only resolves once the editor has
## rescanned, and this script has to run straight from a checkout.
const BalancePolicyScript := preload("res://tools/gd_balance_policy.gd")

const DEFAULT_TICKS := 20000
const DEFAULT_PRESTIGES := 3
const DEFAULT_SAMPLES := 200

## Report path used when --report is given without --out. A plain path, relative
## to wherever godot was started, rather than a res:// one: the report is a file
## in the repository, not a resource the game loads.
const DEFAULT_REPORT_PATH := "tools/balance_report.json"

## A prestige is only worth taking once it multiplies the biomass already held
## by this much; below it the run is better off continuing. Also the reason a
## simulated run does not prestige on tick one for a single point of biomass.
const PRESTIGE_GAIN_FACTOR := 2.0

## Floor on how soon after a prestige the next one may be taken, so a run that
## can always afford one does not spend the whole simulation resetting.
const MIN_TICKS_BETWEEN_PRESTIGES := 50


func _ready() -> void:
	# The root is still busy adding this scene, and _prepare() has to take two
	# autoloads out of it. One frame later it is free to.
	await get_tree().process_frame
	var app := _prepare()
	var args := OS.get_cmdline_user_args()
	var out_path := ""
	var report := false
	var ticks := DEFAULT_TICKS
	var prestiges := DEFAULT_PRESTIGES
	var samples := DEFAULT_SAMPLES
	var policy_name := "roi"

	for arg: String in args:
		if arg == "--report":
			report = true
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--ticks="):
			ticks = int(arg.trim_prefix("--ticks="))
		elif arg.begins_with("--prestiges="):
			prestiges = int(arg.trim_prefix("--prestiges="))
		elif arg.begins_with("--samples="):
			samples = int(arg.trim_prefix("--samples="))
		elif arg.begins_with("--policy="):
			policy_name = arg.trim_prefix("--policy=")

	if report:
		_finish(_write(out_path if not out_path.is_empty() else DEFAULT_REPORT_PATH,
			_build_report(app, ticks, prestiges)))
		return
	if out_path.is_empty():
		printerr("missing --out=FILE")
		_finish(2)
		return
	_finish(_write(out_path, run(app, BalancePolicyScript.kind_from_name(policy_name),
		ticks, prestiges, samples)))


func _finish(code: int) -> void:
	get_tree().quit(code)


## Clears the two ways a normal startup would contaminate a simulated run, and
## returns the App the simulation drives.
##
## SaveManager goes first and goes entirely: it writes user://save.json on a
## timer and again on quit, so a simulation left beside it would overwrite a real
## player's save with a robot's run.
##
## App itself is kept rather than rebuilt - every ViewModel binds to the autoload
## by name, and that name is fixed to the instance the engine registered - so its
## state is wiped back to a first run instead. SaveManager has by then loaded the
## player's save into it, which is exactly what a pacing measurement must not
## start from.
func _prepare() -> Node:
	var tree := get_tree()
	tree.set_auto_accept_quit(true)   # SaveManager turned this off to save on exit
	var saves := tree.root.get_node_or_null(^"SaveManager")
	if saves != null:
		tree.root.remove_child(saves)
		saves.free()

	var app: Node = tree.root.get_node(^"App")
	# Nothing may advance on its own: the run loop below is the only clock.
	app.tick_timer.stop()
	_reset(app)
	return app


## Back to a first run. Each track is cleared through the reset the game itself
## uses, and each save-backed holder through its own loader with nothing in it,
## so a field added later is covered without touching this.
static func _reset(app: Node) -> void:
	app.upgrade_system.reset()
	app.biome_upgrade_system.reset()
	app.prestige_upgrade_system.reset()
	app.geode_upgrade_system.reset()
	app.biome_system.reset()
	app.biome_system.unlock_free_biomes()

	app.player_data.load_from_save({})
	app.automation_data.load_from_save({})
	app.achievement_progress.load_from_save({})
	app.achievement_system.sync_tier_count()

	# Tier 0 keeps one node for the same reason PrestigeSystem leaves it one:
	# with nothing producing, a run can never earn the first purchase back.
	for i in app.mycelium_node_data.size():
		var node: MyceliumNode = app.mycelium_node_data[i].node
		node.manual_nodes = 1 if i == 0 else 0
		node.auto_nodes = BigNumber.from_value(0.0)


# ------------------------------------------------------------------ simulation

## Plays one run under `kind` and reports what happened.
##
## The returned dictionary holds `milestones` (the ticks worth naming) and
## `series` (a downsampled trace), plus the settings that produced them so a
## saved result is self-describing.
static func run(app: Node, kind: BalancePolicyScript.Kind, ticks: int, prestiges: int,
		samples: int) -> Dictionary:
	var policy := BalancePolicyScript.new(app, kind)
	var milestones: Array = []
	var series: Array = []
	var unlocked := {}
	var prestige_count := 0
	var last_prestige_tick := 0
	# Sampling starts dense and thins out as the trace fills (see _thin), rather
	# than spacing points over the tick budget: a run usually ends at its prestige
	# target long before the budget, and a fixed spacing leaves such a run with
	# two points on the chart.
	var every := 1
	var keep := maxi(2, samples)
	# Wall clock the run would have taken. A tick is not a fixed span: every
	# &"tick_rate" upgrade shortens it, and the perks doing that survive a
	# prestige, so a later run advances the same tick count in less real time.
	# Accumulated per tick rather than derived from the trace, which is thinned.
	var seconds := 0.0

	for tick in range(1, ticks + 1):
		seconds += app.tick_duration()
		app.handle_tick()
		# App drains this once per frame in _process, and the loop here never
		# yields a frame. Without it no achievement ever completes and the run
		# earns no crystals, so no automation is ever affordable.
		app.achievement_system.evaluate()
		policy.spend()

		for def: BiomeDef in app.biomes.biomes:
			if unlocked.has(def.key) or not app.biomes_data.is_unlocked(def.key):
				continue
			unlocked[def.key] = tick
			milestones.append({"tick": tick, "seconds": seconds, "event": "biome",
				"detail": String(def.key)})

		if _should_prestige(app, tick - last_prestige_tick):
			var gain: BigNumber = app.preview_biomass_gain()
			app.prestige()
			prestige_count += 1
			last_prestige_tick = tick
			unlocked.clear()   # a prestige relocks them, so the next run re-earns them
			milestones.append({"tick": tick, "seconds": seconds, "event": "prestige",
				"detail": "#%d, +%s biomass" % [prestige_count, gain.to_scientific()]})
			if prestige_count >= prestiges:
				series.append(_sample(app, tick, seconds))
				break

		if tick % every == 0:
			series.append(_sample(app, tick, seconds))
			if series.size() > keep * 2:
				series = _thin(series)
				every *= 2

	var result := {
		"policy": BalancePolicyScript.name_of(kind),
		"ticks": ticks,
		"seconds": seconds,
		"prestige_target": prestiges,
		"prestiges": prestige_count,
		"milestones": milestones,
		"series": series,
		"errors": [],
	}
	return result


## Drops every second point, halving a full trace so sampling can carry on at
## twice the interval. Spacing stays even, which is what a chart needs; the run
## keeps whatever length it turns out to have, which is what a fixed interval
## cannot do.
static func _thin(series: Array) -> Array:
	var kept: Array = []
	for i in range(0, series.size(), 2):
		kept.append(series[i])
	return kept


## A prestige is taken when it is allowed, buys something, and is not too soon
## after the last one - the same three questions a player asks.
##
## "Buys something" is meant literally: the gain has to put at least one perk
## that is currently out of reach into reach, otherwise the run is thrown away
## for nothing. On top of that it has to be worth more than what is already
## banked, so a run does not reset for a rounding error late on.
static func _should_prestige(app: Node, ticks_since_last: int) -> bool:
	if ticks_since_last < MIN_TICKS_BETWEEN_PRESTIGES or not app.can_prestige():
		return false
	var gain: BigNumber = app.preview_biomass_gain()
	var held: BigNumber = app.player_data.biomass
	var next_perk := _cheapest_locked_perk_cost(app)
	if next_perk != null and not held.add(gain).gte(next_perk):
		return false
	if held.mantissa == 0.0:
		return true
	return gain.gte(held.scale(PRESTIGE_GAIN_FACTOR))


## What the cheapest perk the run cannot currently afford costs, or null when
## every reachable perk is already bought.
static func _cheapest_locked_perk_cost(app: Node) -> BigNumber:
	var cheapest: BigNumber = null
	for id: StringName in app.perk_defs:
		# Locked ones are behind a perk that is not bought yet, so their price is
		# not what this run is saving up for; maxed ones cannot be bought at all.
		if app.can_buy_perk(id) or app.perk_status(id) == PerkSystem.STATUS_LOCKED:
			continue
		var def: PerkDef = app.perk_defs[id]
		if def.max_level > 0 and app.prestige_upgrade_system.level(id) >= def.max_level:
			continue
		var cost: BigNumber = app.prestige_upgrade_system.cost(id)
		if cheapest == null or cost.lt(cheapest):
			cheapest = cost
	return cheapest


## One point on the trace. Everything unbounded is stored as log10, which is what
## a chart plots anyway and what keeps a late run inside a JSON number.
static func _sample(app: Node, tick: int, seconds: float) -> Dictionary:
	var production := BigNumber.new(0.0, 0)
	var bonuses: Array[BigNumber] = app.node_production_bonuses()
	for i in app.nodes.mycelium_nodes.size():
		var node: MyceliumNode = app.nodes.mycelium_nodes[i]
		var count := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		production = production.add(count.mul(bonuses[i]))

	var manual := 0
	for node: MyceliumNode in app.nodes.mycelium_nodes:
		manual += node.manual_nodes

	return {
		"tick": tick,
		"seconds": seconds,
		"nutrients": _log10(app.player_data.nutrients),
		"production": _log10(production),
		"biomass": _log10(app.player_data.biomass),
		"nodes": manual,
		"symbiosis": app.upgrade_system.total_levels(),
		"biome_upgrades": app.biome_upgrade_system.total_levels(),
		"perks": app.prestige_upgrade_system.total_levels(),
		"tick_duration": app.tick_duration(),
	}


## Seconds as a span someone can judge: "2h 14m" rather than 8040. Two units is
## enough - the minutes matter next to the hours, the seconds do not.
static func format_duration(seconds: float) -> String:
	var total := int(round(seconds))
	if total < 60:
		return "%ds" % total
	if total < 3600:
		return "%dm %ds" % [total / 60, total % 60]
	if total < 86400:
		return "%dh %dm" % [total / 3600, (total % 3600) / 60]
	return "%dd %dh" % [total / 86400, (total % 86400) / 3600]


## log10 of a value that may legitimately be zero, which has none. Null rather
## than a made-up floor, so a chart can leave the point out.
static func _log10(value: BigNumber) -> Variant:
	return null if value.mantissa <= 0.0 else value.log10()


# ---------------------------------------------------------------------- report

## The checked-in balance report: what everything costs, plus how a reference run
## paces. Regenerated on demand, so a data edit shows its real effect in a diff.
static func _build_report(app: Node, ticks: int, prestiges: int) -> Dictionary:
	var perks := BalanceDataScript.perks()
	var pacing := run(app, BalancePolicyScript.Kind.ROI, ticks, prestiges, 0)
	return {
		"note": "Generated by tools/gd_balance_sim.gd --report. Costs come from the "
			+ "authored .tres files, pacing from a simulated run under the roi policy.",
		"perks": _report_perks(perks.get("perks", [])),
		"branches": _report_branches(perks.get("branches", [])),
		"upgrades": _report_upgrades(),
		"pacing": {
			"policy": pacing["policy"],
			"tick_budget": ticks,
			"prestiges": pacing["prestiges"],
			"seconds": pacing["seconds"],
			"played": format_duration(pacing["seconds"]),
			"milestones": pacing["milestones"],
		},
		"errors": perks.get("errors", []),
	}


static func _report_perks(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		out.append({
			"id": row["id"],
			"branch": row["branch_key"],
			"depth": row["depth"],
			"max_level": row["max_level"],
			"cost_to_max": _scientific(row["cost_to_max"]),
			"path_cost": _scientific(row["path_cost"]),
			"effect_at_max": _scientific(row["effect_at_max"]) if row.has("effect_at_max") else "",
		})
	return out


static func _report_branches(rows: Array) -> Array:
	var out: Array = []
	for row: Dictionary in rows:
		var stats := {}
		for key: String in row["stats"]:
			stats[key] = _scientific(row["stats"][key])
		out.append({
			"branch": row["branch_key"],
			"perks": row["perk_count"],
			"max_depth": row["max_depth"],
			"total_cost_to_max": _scientific(row["total_cost_to_max"]),
			"deepest_path_cost": _scientific(row["deepest_path_cost"]),
			"stats": stats,
		})
	return out


## Every priced upgrade outside the web, with what buying it out costs. Sorted by
## path so the report diffs line by line.
static func _report_upgrades() -> Array:
	var curves: Dictionary = BalanceDataScript.curves("res://data").get("curves", {})
	var paths: Array = curves.keys()
	paths.sort()
	var out: Array = []
	for path: String in paths:
		if path.begins_with("res://data/prestige/"):
			continue     # already covered, in web shape, by "perks"
		var curve: Dictionary = curves[path]
		var total := BigNumber.new(0.0, 0)
		for level in range(curve["max_level"]):
			total = total.add(BigNumber.new(curve["cost"][level][0], curve["cost"][level][1]))
		out.append({
			"path": path,
			"max_level": curve["max_level"],
			"stat": curve.get("stat", ""),
			"per_level": curve.get("per_level", 0.0),
			"cost_to_max": _scientific([total.mantissa, total.exponent]),
		})
	return out


static func _scientific(pair: Array) -> String:
	return BigNumber.new(pair[0], pair[1]).to_scientific()


static func _write(out_path: String, report: Dictionary) -> int:
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		printerr("could not write %s (%s)" % [out_path, error_string(FileAccess.get_open_error())])
		return 2
	file.store_string(JSON.stringify(report, "\t", false))
	file.close()
	for error: Variant in report.get("errors", []):
		printerr("error: %s" % error)
	return 1 if not report.get("errors", []).is_empty() else 0
