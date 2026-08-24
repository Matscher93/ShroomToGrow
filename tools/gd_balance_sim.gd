extends Node

## Headless run simulator: how long the authored numbers actually take to play.
##
##   godot --headless tools/sc_balance_sim.tscn -- \
##       [--ticks=20000] [--policy=roi|cheapest|nodes_only] [--prestiges=3] \
##       [--samples=200] [--stride=100000] [--progress=FILE] \
##       [--load=SAVE] [--from-tick=0] [--from-seconds=0] [--save=FILE] \
##       [--breakdowns=milestones|end|off] --out=FILE
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
## Preloaded for its save-file constants alone. The autoload itself is taken out
## of the tree before a run starts (see _prepare), but the file shape a run
## exports has to stay the one the game reads.
const SaveManagerScript := preload("res://autoload/gd_save_manager.gd")

const DEFAULT_TICKS := 20000
const DEFAULT_PRESTIGES := 3
const DEFAULT_SAMPLES := 200

## Ceiling on how many idle ticks one stride may skip. There is no correctness
## reason for a ceiling - the jump is exact at any length - but a bounded stride
## keeps the cost of a mistaken idle judgement bounded too, and the trace's own
## sampling interval caps most strides well below this anyway.
const DEFAULT_STRIDE := 100000

## Where a simulated run's own wall clock starts, as a unix time. Any day well
## past the epoch will do, and it has to be past it: DailyRewardData opens at
## last_claim_day 0, which is 1970-01-01, so a run starting there would find its
## first reward already spent instead of waiting.
const SIM_EPOCH := 20_000.0 * 86400.0

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

## How often the run asks whether it should prestige. Asking costs a
## can_prestige() and a preview_biomass_gain(), and asking every tick was a
## sizeable slice of a long run for an answer that cannot change quickly:
## nothing may prestige inside MIN_TICKS_BETWEEN_PRESTIGES anyway, and a real
## gap runs to hundreds of ticks. A prestige therefore lands up to this many
## ticks late, which is well inside the noise of a pacing measurement.
const PRESTIGE_CHECK_EVERY := 10

## How often the run tells --progress=FILE where it has got to. A run takes
## minutes and the page watching it has nothing else to go on, so this wants to
## be often enough to look alive and rare enough to stay free: at 250ms a
## 20,000-tick run writes it a couple of hundred times.
const PROGRESS_EVERY_MS := 250

## How often achievements are evaluated. The game drains them once a frame off a
## dirty flag that every tick sets, so a per-tick evaluation is the faithful
## thing - but it walks every achievement, and the only thing riding on it here
## is when crystals arrive. Completing a tier a few ticks late costs a run
## nothing it can measure.
const ACHIEVEMENTS_EVERY := 5

## When a bonus breakdown is taken - see _breakdown().
##
## Every milestone by default, which is what makes the mix visible as it shifts
## over a run. It is not free: one probe is a full re-resolve, and a long run puts
## a few hundred levelled upgrades through one at every milestone. "end" takes the
## single snapshot the run finished on, "off" restores the cost of a run that
## never asks.
const BREAKDOWN_OFF := "off"
const BREAKDOWN_END := "end"
const BREAKDOWN_MILESTONES := "milestones"
const BREAKDOWN_MODES := [BREAKDOWN_OFF, BREAKDOWN_END, BREAKDOWN_MILESTONES]


func _ready() -> void:
	# The root is still busy adding this scene, and _prepare() has to take two
	# autoloads out of it. One frame later it is free to.
	await get_tree().process_frame
	var app := _prepare()
	var args := OS.get_cmdline_user_args()
	# Parsed before anything is done with the App, because --load replaces the
	# fresh start _prepare() just set up.
	var out_path := ""
	var report := false
	var ticks := DEFAULT_TICKS
	var prestiges := DEFAULT_PRESTIGES
	var samples := DEFAULT_SAMPLES
	var stride := DEFAULT_STRIDE
	var progress_path := ""
	var load_path := ""
	var save_path := ""
	var from_tick := 0
	var from_seconds := 0.0
	var policy_name := "roi"
	var breakdowns := BREAKDOWN_MILESTONES

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
		elif arg.begins_with("--stride="):
			stride = maxi(1, int(arg.trim_prefix("--stride=")))
		elif arg.begins_with("--progress="):
			progress_path = arg.trim_prefix("--progress=")
		elif arg.begins_with("--load="):
			load_path = arg.trim_prefix("--load=")
		elif arg.begins_with("--save="):
			save_path = arg.trim_prefix("--save=")
		elif arg.begins_with("--from-tick="):
			from_tick = maxi(0, int(arg.trim_prefix("--from-tick=")))
		elif arg.begins_with("--from-seconds="):
			from_seconds = maxf(0.0, float(arg.trim_prefix("--from-seconds=")))
		elif arg.begins_with("--policy="):
			policy_name = arg.trim_prefix("--policy=")
		elif arg.begins_with("--breakdowns="):
			breakdowns = arg.trim_prefix("--breakdowns=")

	if not BREAKDOWN_MODES.has(breakdowns):
		printerr("--breakdowns must be one of %s" % ", ".join(BREAKDOWN_MODES))
		_finish(2)
		return
	if report:
		_finish(_write(out_path if not out_path.is_empty() else DEFAULT_REPORT_PATH,
			_build_report(app, ticks, prestiges)))
		return
	if out_path.is_empty():
		printerr("missing --out=FILE")
		_finish(2)
		return
	if not load_path.is_empty():
		var loaded := _read_save(load_path)
		if loaded.is_empty():
			printerr("could not read a save from %s" % load_path)
			_finish(2)
			return
		app.load_from_save(loaded)
	var result := run(app, BalancePolicyScript.kind_from_name(policy_name),
		ticks, prestiges, samples, stride, progress_path, from_tick, from_seconds, breakdowns)
	if not save_path.is_empty() and _write(save_path, result["save"]) != 0:
		_finish(2)
		return
	_finish(_write(out_path, result))


## Reads a save file, accepting either what SaveManager writes - a versioned
## envelope with the state under "game" - or a bare state on its own. Both turn
## up: the first is a save lifted straight out of a play session, the second is
## one savepoint out of a previous simulated run.
static func _read_save(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	var data: Dictionary = parsed
	var game: Variant = data.get("game")
	return game if game is Dictionary else data


## One save, in the shape the game's own save file has, so a run's end state can
## be dropped into user://save.json and played from.
static func _save_file(app: Node) -> Dictionary:
	return {
		"version": SaveManagerScript.SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"game": app.to_save(),
	}


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
## uses, and each save-backed holder through its own loader with nothing in it.
##
## Hand-maintained against App._ready(), and it has drifted before: the whole
## Ruins was missing here for as long as the Ruins existed, so a --load= from a
## real save carried that player's creature ranks and mission tally into the
## baseline, and balance_report.json measured pacing for a game with no missions
## in it. test/data/balance_pacing_test.gd pins that report, so the drift was
## invisible. Anything App builds and saves belongs here too.
static func _reset(app: Node) -> void:
	app.upgrade_system.reset()
	app.biome_upgrade_system.reset()
	app.prestige_upgrade_system.reset()
	app.boost_upgrade_system.reset()
	# Reset here even though a prestige never touches it: the well's projects are
	# permanent *within* a run, and this is starting a new one.
	app.project_upgrade_system.reset()
	# Same again for the growth track. Its two halves are account progress the
	# sporation has no claim on, but a simulated run starts from nothing - a
	# baseline carrying invested Level Points would not be a first run.
	app.growth_upgrade_system.reset()
	# And again for the fertilizer track, for exactly the same reason: what events
	# paid out in an earlier run is account progress, but a baseline starting with
	# Rich Soil already bought is not a first run.
	app.fertilizer_upgrade_system.reset()
	# The Ruins boost ladder, on the same footing as the well and growth tracks:
	# a mission boost bought in an earlier run is not part of a first one.
	app.mission_upgrade_system.reset()
	app.biome_system.reset()
	app.biome_system.unlock_free_biomes()

	app.player_data.load_from_save({})
	app.automation_data.load_from_save({})
	app.achievement_progress.load_from_save({})
	app.achievement_system.sync_tier_count()
	app.daily_reward_data.load_from_save({})
	# The queue goes too. Nothing in the simulation answers an event - it never
	# runs the spawn timer - so a carried-over offer would sit there unanswered
	# and only the fertilizer it never pays would differ.
	app.events_data.load_from_save({})
	# Creature ranks, the mission board and the completed tally. Without this a
	# --load= from a real save carried a player's whole Ruins into what the report
	# calls a first run.
	app.ruins_data.load_from_save({})
	# The doubling level is derived from the investments just cleared, so it has
	# to follow them down.
	app.player_level_system.sync_global_double()
	# PlayerData.well_project_levels is a projection of the levels just cleared,
	# and it is the Underground Lake's XP source, so it has to follow them down.
	app.well_system.sync_project_levels()
	# PlayerData.missions_completed is the same shape, and it is the Ruins biome's
	# XP source.
	app.mission_system.sync_missions_completed()

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
##
## `stride` caps how many idle ticks may be skipped in one step. 1 disables
## striding, which is the setting to reach for when a result looks wrong: the
## two paths must agree, and if they don't, this one is the suspect.
##
## `progress_path`, when given, gets how far the run has got written to it as it
## goes, for whoever is waiting on it. Empty means nobody is.
##
## `from_tick` and `from_seconds` are where the App handed in has already got to,
## for a run continuing from a savepoint rather than starting fresh. They shift
## what the trace and the milestones are labelled with, so a continued run's
## chart lines up with the run it came out of. They deliberately do not shift the
## tick budget: `ticks` is always how many ticks *this* run may play.
##
## `breakdowns` says when the bonus breakdown is taken - see BREAKDOWN_MODES.
static func run(app: Node, kind: BalancePolicyScript.Kind, ticks: int, prestiges: int,
		samples: int, stride: int = DEFAULT_STRIDE, progress_path: String = "",
		from_tick: int = 0, from_seconds: float = 0.0,
		breakdowns: String = BREAKDOWN_MILESTONES) -> Dictionary:
	var policy := BalancePolicyScript.new(app, kind)
	var milestones: Array = []
	# One save per milestone, so a run can be picked up again from any of the
	# points worth naming rather than only from where it stopped.
	var savepoints: Array = []
	# One bonus breakdown per milestone, or null when this run was not asked for
	# them - which is what _mark() below tests, so the mode is decided once here
	# rather than at all three call sites.
	var bonus_trail: Variant = [] if breakdowns == BREAKDOWN_MILESTONES else null
	var series: Array = []
	# Which biomes are already open, so only the ones this run actually opens are
	# reported. Seeded rather than started empty: the free biomes are open before
	# the first tick, and a run continuing from a savepoint starts with whatever
	# that savepoint had earned.
	var unlocked := _unlocked_now(app)
	# Which well projects have been funded at least once, so the ladder's steps get
	# a tick each. Not rebuilt on a prestige, unlike `unlocked`: the sporation
	# wipes the water but never what the water was spent on.
	var funded := _funded_now(app)
	var prestige_count := 0
	var last_prestige_tick := 0
	# Trace points are spaced geometrically, not evenly, because the chart's tick
	# axis goes logarithmic as soon as a run spans more than a few decades - and
	# every run of any length does. Even spacing on a log axis piles almost every
	# point into the last decade and leaves the first biome, the first automation
	# and the first prestige sharing a handful of pixels' worth of samples. A
	# constant ratio puts the same number of points in every decade instead.
	#
	# The ratio comes from the tick budget, so the trace fills to about `samples`
	# points whatever the run is asked for. It still thins if a run outlives the
	# estimate (see _thin), and squaring the ratio then keeps the spacing
	# geometric, exactly as doubling kept it even before.
	var keep := maxi(2, samples)
	var ratio := pow(maxf(2.0, float(ticks)), 1.0 / float(keep))
	# Which tick the last trace point was taken on, and where the next one is
	# due. Read from the tick counter rather than tested with a modulo, because a
	# stride moves the tick number by more than one and would step straight over
	# any exact multiple.
	var next_sample := 1
	# Wall clock the run would have taken. A tick is not a fixed span: every
	# &"tick_rate" upgrade shortens it, and the perks doing that survive a
	# prestige, so a later run advances the same tick count in less real time.
	# Accumulated per tick rather than derived from the trace, which is thinned.
	var seconds := from_seconds
	# The daily reward is gated on a wall clock, and a simulated run has its own.
	# A one-element array rather than the float itself: a lambda captures a local
	# by value, so a closure over `seconds` would read tick zero forever.
	var clock: Array[float] = [SIM_EPOCH + from_seconds]
	app.daily_reward_system.now_provider = func() -> float: return clock[0]
	# UTC, so a day boundary lands on an exact multiple of a day and the stride's
	# bound below needs no offset of its own.
	app.daily_reward_system.tz_bias_provider = func() -> int: return 0

	# Ticks where the last one bought nothing are candidates for a stride, which
	# is why the loop counts rather than iterating a range: a stride moves the
	# tick number by more than one.
	var tick := 0
	var idle := false
	var told_at := Time.get_ticks_msec()
	while tick < ticks:
		if not progress_path.is_empty() and Time.get_ticks_msec() - told_at >= PROGRESS_EVERY_MS:
			told_at = Time.get_ticks_msec()
			_report_progress(progress_path, tick, ticks, prestige_count, prestiges, seconds)
		if idle and stride > 1:
			var room := mini(stride, ticks - tick - 1)
			var jump := _stride(app, policy, room, tick - last_prestige_tick)
			if jump > 0:
				# Exact: nothing inside the span is bought, so nothing shortens
				# the tick either.
				seconds += float(jump) * app.tick_duration()
				clock[0] = SIM_EPOCH + seconds
				app.tick_system.advance(jump)
				tick += jump
		tick += 1
		seconds += app.tick_duration()
		clock[0] = SIM_EPOCH + seconds
		app.handle_tick()
		# App drains this once per frame in _process, and the loop here never
		# yields a frame. Without it no achievement ever completes and the run
		# earns no crystals, so no automation is ever affordable.
		if tick % ACHIEVEMENTS_EVERY == 0:
			app.achievement_system.evaluate()
		idle = policy.spend() == 0

		for def: BiomeDef in app.biomes.biomes:
			if unlocked.has(def.key) or not app.biomes_data.is_unlocked(def.key):
				continue
			unlocked[def.key] = tick
			_mark(milestones, savepoints, bonus_trail, app, from_tick + tick, seconds, "biome",
				String(def.key))

		for def: ProjectDef in app.projects.projects:
			if funded.has(def.id) or app.project_level(def.id) <= 0:
				continue
			funded[def.id] = tick
			_mark(milestones, savepoints, bonus_trail, app, from_tick + tick, seconds, "project",
				String(def.id))

		if tick % PRESTIGE_CHECK_EVERY == 0 and _should_prestige(app, tick - last_prestige_tick):
			var gain: BigNumber = app.preview_biomass_gain()
			app.prestige()
			prestige_count += 1
			last_prestige_tick = tick
			# A prestige relocks them, so the next run re-earns them - all but the
			# free ones, which reset() hands straight back.
			unlocked = _unlocked_now(app)
			_mark(milestones, savepoints, bonus_trail, app, from_tick + tick, seconds, "prestige",
				"#%d, +%s biomass" % [prestige_count, gain.to_scientific()])
			if prestige_count >= prestiges:
				series.append(_sample(app, from_tick + tick, seconds))
				break

		if tick >= next_sample:
			# Stepped off the tick actually reached, not off the tick that was
			# due: a stride can overshoot the ladder, and measuring from where
			# the run really is keeps the spacing geometric either way.
			next_sample = maxi(tick + 1, int(float(tick) * ratio))
			series.append(_sample(app, from_tick + tick, seconds))
			if series.size() > keep * 2:
				series = _thin(series)
				ratio *= ratio

	var result := {
		"policy": BalancePolicyScript.name_of(kind),
		"ticks": ticks,
		"seconds": seconds,
		"from_tick": from_tick,
		"from_seconds": from_seconds,
		"last_tick": from_tick + tick,
		# Where the run stopped, and every point on the way worth stopping at.
		# Both in the game's own save-file shape, so either can be dropped into
		# user://save.json and played, or handed back to --load to carry on.
		"save": _save_file(app),
		"savepoints": savepoints,
		"prestige_target": prestiges,
		"prestiges": prestige_count,
		"milestones": milestones,
		# What every levelled upgrade was contributing at the end, and - unless
		# this run was asked for less - at each milestone on the way. Null rather
		# than empty for a run that asked for none, so a page can tell "nothing was
		# measured" from "nothing was contributing".
		"breakdown": null if breakdowns == BREAKDOWN_OFF \
			else _breakdown(app, from_tick + tick, seconds),
		"breakdowns": bonus_trail if bonus_trail != null else [],
		"series": series,
		"errors": [],
	}
	return result


## The biome keys currently open, as a set.
static func _unlocked_now(app: Node) -> Dictionary:
	var open_now := {}
	for def: BiomeDef in app.biomes.biomes:
		if app.biomes_data.is_unlocked(def.key):
			open_now[def.key] = true
	return open_now


## The well project ids already funded at least once, as a set. Non-empty only
## for a run continuing from a savepoint, which is the point of reading it rather
## than starting empty.
static func _funded_now(app: Node) -> Dictionary:
	var done := {}
	for def: ProjectDef in app.projects.projects:
		if app.project_level(def.id) > 0:
			done[def.id] = true
	return done


## Records one tick worth naming: once lean for the table that lists them, once
## with the run's whole state attached so it can be started again from exactly
## here, and - when this run was asked for them - once as a bonus breakdown.
##
## The three arrays stay index-parallel, so the page showing one row can reach the
## save and the breakdown that go with it.
##
## The state is taken *after* the event has been applied - after the prestige,
## after the biome opened - because that is the state the run went on with, and
## therefore the one a continuation has to pick up.
static func _mark(milestones: Array, savepoints: Array, breakdowns: Variant, app: Node,
		tick: int, seconds: float, event: String, detail: String) -> void:
	var row := {"tick": tick, "seconds": seconds, "event": event, "detail": detail}
	milestones.append(row)
	var point := row.duplicate()
	point["save"] = _save_file(app)
	savepoints.append(point)
	if breakdowns != null:
		breakdowns.append(_breakdown(app, tick, seconds))


## Writes how far the run has got, for whoever is waiting on it.
##
## Through a temporary file and a rename, because the reader polls on its own
## schedule and would otherwise catch a half-written line and see a run that had
## gone backwards. A rename inside one directory is atomic; a write is not.
##
## Failures are ignored on purpose: nothing about the run depends on anyone
## reading this, and a run that has taken minutes must not die at the end of it
## because a temporary directory went away.
static func _report_progress(path: String, tick: int, ticks: int, prestiges: int,
		prestige_target: int, seconds: float) -> void:
	var staging := path + ".part"
	var file := FileAccess.open(staging, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"tick": tick,
		"ticks": ticks,
		"prestiges": prestiges,
		"prestige_target": prestige_target,
		"seconds": seconds,
		"played": format_duration(seconds),
	}))
	file.close()
	DirAccess.rename_absolute(staging, path)


# -------------------------------------------------------------------- striding

## How many of the next `limit` ticks can be skipped outright, which is the last
## one where the run still wants nothing.
##
## A run spends almost all of its ticks waiting: 97% of them, measured, buy
## nothing at all and only let nutrients pile up. TickSystem.advance() can land
## on the end of such a stretch in one step, and this is what decides how long
## the stretch is.
##
## Bisection is sound because every quantity that moves during an idle stretch
## only ever grows - nutrients, lifetime totals, tick count - while every price
## it is measured against is frozen, since a price only moves when something is
## bought. So "the run still wants nothing" is true up to some tick and false
## after it, and the search finds that tick in a dozen probes rather than
## walking the thousands of ticks in between.
##
## Each probe advances a throwaway copy of the state and puts it back, so a
## rejected probe leaves nothing behind.
##
## The search doubles before it bisects, so its cost tracks the stretch it
## actually finds rather than the ceiling it was handed: a hundred-tick lull
## costs about fourteen probes whether the ceiling was a thousand or a million.
##
## Everything a probe would otherwise re-derive is hoisted into `watch` first,
## because none of it can move while nothing is bought. A probe is then a
## weighted sum, three comparisons and a look at the handful of achievements
## whose measure grows on its own.
static func _stride(app: Node, policy: BalancePolicy, limit: int, gap: int) -> int:
	if limit < 1:
		return 0
	var watch := _watch(app, policy)
	if watch.is_empty():
		return 0     # something already wants attention, so nothing can be skipped
	# The day rolls over on its own, and the probe below cannot see it: the run's
	# clock only advances once a jump is committed. So it is bounded rather than
	# watched - the stride stops on the tick the next reward opens, and the walked
	# tick after it claims.
	limit = mini(limit, watch["daily_ticks"])
	if limit < 1:
		return 0
	var snapshot := _snapshot(app)
	var best := 0
	var high := 1
	while high <= limit and _probe(app, snapshot, watch, high, gap):
		best = high
		high *= 2
	if best == 0:
		return 0

	# Somewhere in (best, min(high, limit)] the run stops being idle. Nothing
	# below `best` needs re-testing: every quantity in play only grows, so a
	# tick that wanted nothing had every earlier tick want nothing too.
	var low := best + 1
	high = mini(high - 1, limit)
	while low <= high:
		@warning_ignore("integer_division")
		var mid := low + (high - low) / 2
		if _probe(app, snapshot, watch, mid, gap):
			best = mid
			low = mid + 1
		else:
			high = mid - 1
	return best


## What has to be watched across an idle stretch, and what it is measured
## against. Empty when the stretch cannot start at all: something already wants
## buying, an achievement is already standing on its goal, or a prestige is
## already due, and there is nothing to skip.
##
## The three prices are read once because a price only moves when a level does,
## and nothing buys a level inside a stride. The achievements are filtered to the
## ones whose measure can move on its own - a tick count and a nutrient total -
## since every other one is counting something only a purchase changes.
##
## The water price is watched for the same reason nutrients are: the Underground
## Lake pumps whether or not anything is bought, so a stride has to stop on the
## tick a well project becomes fundable exactly as it stops on the tick a node
## becomes affordable. Crystals need no such watch - only an achievement claim
## moves them, and a pending claim ends the stretch two lines below.
static func _watch(app: Node, policy: BalancePolicy) -> Dictionary:
	if app.has_achievement_claims():
		return {}
	# Both halves of the growth sheet come due on their own, so a stretch cannot
	# start with either already waiting.
	if app.lp_available() >= 1 or app.can_claim_daily():
		return {}
	var growing: Array[AchievementDef] = []
	for def: AchievementDef in app.achievements.achievements:
		if app.achievement_system.is_maxed(def):
			continue
		if app.achievement_system.current_value(def).gte(app.achievement_system.current_goal(def)):
			return {}
		# PLAYER_LEVEL belongs here for the same reason LIFETIME_NUTRIENTS does,
		# and literally because of it: the level is derived from that counter, so
		# it climbs on its own across an idle stretch.
		if def.stat == AchievementDef.Stat.LIFETIME_TICKS \
				or def.stat == AchievementDef.Stat.LIFETIME_NUTRIENTS \
				or def.stat == AchievementDef.Stat.PLAYER_LEVEL:
			growing.append(def)
	# Ticks to the next local midnight at the current tick length. Nothing inside
	# a stride buys a level, so nothing shortens the tick either, which is what
	# makes one division enough. Ceil: the reward opens on the tick that reaches
	# midnight, not the one before it.
	var daily_ticks := int(ceil(app.daily_reward_system.seconds_until_next_day()
		/ app.tick_duration()))
	return {
		"price": policy.cheapest_price(),
		"water": policy.cheapest_water_price(),
		"perk": _cheapest_locked_perk_cost(app),
		"growing": growing,
		"daily_ticks": maxi(1, daily_ticks),
		"kernel": app.tick_system.jump_kernel(),
	}


## Whether the run would still want nothing `jump` ticks from now. Leaves the
## state exactly as it found it.
static func _probe(app: Node, snapshot: Dictionary, watch: Dictionary, jump: int,
		gap: int) -> bool:
	app.tick_system.advance_by(jump, watch["kernel"])
	var quiet := _settled(app, watch, gap + jump)
	_restore(app, snapshot)
	return quiet


## Whether the run would do nothing at all from this state: buy nothing, complete
## no achievement, take no prestige. The three things a tick can produce.
static func _settled(app: Node, watch: Dictionary, gap: int) -> bool:
	var price: BigNumber = watch["price"]
	if price != null and app.player_data.nutrients.gte(price):
		return false
	var water: BigNumber = watch["water"]
	if water != null and app.player_data.water.gte(water):
		return false
	for def: AchievementDef in watch["growing"]:
		if app.achievement_system.current_value(def).gte(app.achievement_system.current_goal(def)):
			return false
	# Lifetime nutrients grow every tick, so a Level Point falls due inside an
	# idle stretch the way a well project does. _snapshot covers the counter this
	# reads, so the probe leaves it where it found it.
	if app.lp_available() >= 1:
		return false
	return not _should_prestige(app, gap, watch["perk"])


## Everything TickSystem.advance() moves, and nothing else - which is the whole
## list, since a stride is only ever taken across ticks that buy nothing.
## BigNumber has no mutating operation, so holding the references is a copy.
static func _snapshot(app: Node) -> Dictionary:
	var autos: Array[BigNumber] = []
	for node: MyceliumNode in app.nodes.mycelium_nodes:
		autos.append(node.auto_nodes)
	return {
		"auto_nodes": autos,
		"nutrients": app.player_data.nutrients,
		"lifetime_nutrients": app.player_data.lifetime_nutrients,
		"tick_count": app.player_data.tick_count,
		"lifetime_ticks": app.player_data.lifetime_ticks,
		"water": app.player_data.water,
	}


static func _restore(app: Node, snapshot: Dictionary) -> void:
	var autos: Array = snapshot["auto_nodes"]
	for i in app.nodes.mycelium_nodes.size():
		app.nodes.mycelium_nodes[i].auto_nodes = autos[i]
	app.player_data.nutrients = snapshot["nutrients"]
	app.player_data.lifetime_nutrients = snapshot["lifetime_nutrients"]
	app.player_data.tick_count = snapshot["tick_count"]
	app.player_data.lifetime_ticks = snapshot["lifetime_ticks"]
	app.player_data.water = snapshot["water"]


## Drops every second point, halving a full trace so sampling can carry on at
## the squared ratio. Spacing stays geometric, which is what a log axis needs;
## the run keeps whatever length it turns out to have, which is what a fixed
## interval cannot do.
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
##
## `next_perk` is the answer _cheapest_locked_perk_cost() would give, passed in
## by a caller that has it already: it walks every perk, and a stride asks this
## question a dozen times over a stretch where the answer cannot have changed.
static func _should_prestige(app: Node, ticks_since_last: int,
		next_perk: Variant = null) -> bool:
	if ticks_since_last < MIN_TICKS_BETWEEN_PRESTIGES or not app.can_prestige():
		return false
	var gain: BigNumber = app.preview_biomass_gain()
	var held: BigNumber = app.player_data.biomass
	var perk: BigNumber = next_perk if next_perk != null else _cheapest_locked_perk_cost(app)
	if perk != null and not held.add(gain).gte(perk):
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
	var production := _total_production(app)

	var manual := 0
	for node: MyceliumNode in app.nodes.mycelium_nodes:
		manual += node.manual_nodes

	return {
		"tick": tick,
		"seconds": seconds,
		"nutrients": _log10(app.player_data.nutrients),
		"production": _log10(production),
		"biomass": _log10(app.player_data.biomass),
		"crystals": _log10(app.player_data.crystals),
		"water": _log10(app.player_data.water),
		"nodes": manual,
		"symbiosis": app.upgrade_system.total_levels(),
		"biome_upgrades": app.biome_upgrade_system.total_levels(),
		"perks": app.prestige_upgrade_system.total_levels(),
		# Levels up the crystal ladders, summed across the boosts and their tiers -
		# the Caves' half of what crystals are spent on.
		"boosts": app.boost_upgrade_system.total_levels(),
		# Fundings across every well project. Counted through WellSystem rather
		# than off the project track's total_levels(), which counts the boons
		# riding along with each funding as well.
		"well_projects": app.well_total_levels(),
		# The account level lifetime nutrients have reached, and the points it has
		# handed out that are already spent. They part company only when a run
		# earns points faster than the policy spreads them.
		"player_level": app.player_level(),
		"level_points": app.lp_invested_total(),
		"tick_duration": app.tick_duration(),
		"water_interval": app.water_pump_interval(),
	}


## What every node produces in one tick, summed. The same figure the chart's
## `production` track plots, so a counterfactual below measures exactly what the
## chart shows rather than something adjacent to it.
static func _total_production(app: Node) -> BigNumber:
	var production := BigNumber.new(0.0, 0)
	var bonuses: Array[BigNumber] = app.node_production_bonuses()
	for i in app.nodes.mycelium_nodes.size():
		var node: MyceliumNode = app.nodes.mycelium_nodes[i]
		var count := node.auto_nodes.add(BigNumber.from_value(node.manual_nodes))
		production = production.add(count.mul(bonuses[i]))
	return production


# ----------------------------------------------------------------- breakdown

## Which stat buckets feed which resource, in the order a reader wants them.
##
## A stat bucket is not what anyone asks about - "what is pushing nutrients" is,
## and three buckets answer it. This is where that question is answered, rather
## than in the page that draws the table, because the totals below are measured
## per resource: the probe has to know which upgrades belong together before it
## can take them all away at once.
##
## `metric` says which of a probe's numbers ranks that resource. Three of them are
## measured against what the run itself does - nutrients per tick, the seconds a
## tick takes, the ticks between pumps. The rest get `stat`: the share of their own
## bucket, because production per tick does not read a &"biomass_gain" upgrade at
## all and ranking those by the production drop would rank them by zeroes.
##
## A stat missing here gets a resource of its own, named after the stat and ranked
## by its bucket - a new stat in data/ turning up unranked beats it vanishing.
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
		"stats": ["mission_speed", "mission_reward", "mission_slots"]},
	{"resource": "boosts", "metric": "stat",
		"stats": ["boost_power", "boost_max_level", "creature_rank_cap"]},
	{"resource": "biome points", "metric": "stat",
		"stats": ["biome_points", "level_points"]},
]


## The resource a stat feeds, or one invented for a stat RESOURCES does not name.
static func _resource_of(stat: String) -> Dictionary:
	for group: Dictionary in RESOURCES:
		if group["stats"].has(stat):
			return group
	return {"resource": stat, "metric": "stat", "stats": [stat]}

## What the six upgrade tracks are contributing right now, upgrade by upgrade.
##
## Two numbers per upgrade, because neither answers on its own. The magnitude is
## what it writes into its stat bucket - exact, and free, since UpgradeSystem has
## it cached - but a +0.15 INCREASED and a +0.15 MORE are not comparable, and
## across two different stats nothing is. So the impact is measured instead: the
## level is taken away, everything re-resolves, and what the run falls to without
## it is a number that compares across ops, scopes and tracks alike.
##
## Tick duration and pump interval are measured in the same probe as production,
## because a &"tick_rate" or &"water_rate" upgrade moves no production at all and
## would otherwise read as contributing nothing.
##
## Those three are all a run-level probe can see, and they leave most of the game
## unmeasured: production is nutrients per tick, so a &"biomass_gain" or
## &"crystal_gain" upgrade moves none of the three and reads as worth nothing at
## all. So the same probe also measures the stat buckets the upgrade itself writes
## - see _measure_buckets() - and reports what each one loses without it. That is
## the number that ranks the upgrades a run-level probe is blind to.
##
## Every probe puts back the level it took away before the next one starts, so a
## breakdown leaves the run exactly where it found it.
static func _breakdown(app: Node, tick: int, seconds: float) -> Dictionary:
	var rows_by_track: Dictionary = app.production_system.breakdown()
	var base := _measure(app)
	var groups: Array = []
	for pair: Array in app.production_system.tracks():
		var track: String = pair[0]
		var system: UpgradeSystem = pair[1]
		var upgrades := _breakdown_upgrades(app, base, system, rows_by_track.get(track, []))
		if upgrades.is_empty():
			continue
		var ids: Array = []
		for row: Dictionary in upgrades:
			ids.append(StringName(row["id"]))
		groups.append({
			"track": track,
			# What the track as a whole is worth. Measured rather than summed from
			# the rows: MORE effects compound, so taking two upgrades away costs
			# more than taking each of them away did.
			"impact": _impact_without(app, base, system, ids),
			"upgrades": upgrades,
		})
	return {
		"tick": tick,
		"seconds": seconds,
		"production": _log10(base["production"]),
		"tick_duration": base["tick_duration"],
		"water_interval": base["water_interval"],
		"tracks": groups,
		"resources": _breakdown_resources(app, base, groups),
	}


## The same upgrades again, gathered by the resource they feed rather than by the
## track they live in, with a measured total for each gathering.
##
## Measured, not summed from the rows: MORE effects compound, so a column of
## per-upgrade drops adds up past 100% long before it says anything - fifteen
## upgrades each worth "the run falls 99% without it" sum to 1485%, which ranks
## the tracks by how many upgrades they happen to hold. Taking the whole set away
## at once is one probe and one honest number, and it is what the page ranks by.
##
## Costs one probe per resource plus one per resource and track that meet: 42 on
## top of the 211 a full run already takes, so a sixth again of the same measured
## quantity. Nothing here is summed anywhere.
static func _breakdown_resources(app: Node, base: Dictionary, groups: Array) -> Array:
	var systems := {}
	for pair: Array in app.production_system.tracks():
		systems[pair[0]] = pair[1]

	# resource -> {"metric", "tracks": {track -> {"ids", "buckets"}}}
	var wanted := {}
	for group: Dictionary in groups:
		for upgrade: Dictionary in group["upgrades"]:
			for effect: Dictionary in upgrade["effects"]:
				var res: String = effect["resource"]
				if not wanted.has(res):
					var def := _resource_of(effect["stat"])
					wanted[res] = {"metric": def["metric"], "tracks": {}}
				var tracks: Dictionary = wanted[res]["tracks"]
				if not tracks.has(group["track"]):
					tracks[group["track"]] = {"ids": [], "buckets": []}
				var subset: Dictionary = tracks[group["track"]]
				var id := StringName(upgrade["id"])
				if not subset["ids"].has(id):
					subset["ids"].append(id)
				# Only a stat-ranked resource needs its buckets measured. Nutrients
				# writes some thirty of them and is ranked on the run-level probe
				# regardless, so measuring them would be paid for nothing.
				if wanted[res]["metric"] != "stat":
					continue
				var bucket: Array = [effect["stat"], effect["key"]]
				if not subset["buckets"].has(bucket):
					subset["buckets"].append(bucket)

	var out: Array = []
	for res: String in _resource_order(wanted.keys()):
		var metric: String = wanted[res]["metric"]
		var tracks: Dictionary = wanted[res]["tracks"]
		var sources: Array = []
		var every: Array = []
		var every_bucket: Array = []
		for track: String in tracks:
			var subset: Dictionary = tracks[track]
			sources.append({
				"track": track,
				"impact": _impact_without(app, base, systems[track],
					subset["ids"], subset["buckets"]),
			})
			every.append([systems[track], subset["ids"]])
			for bucket: Array in subset["buckets"]:
				if not every_bucket.has(bucket):
					every_bucket.append(bucket)
		sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _influence(metric, a["impact"]) > _influence(metric, b["impact"]))
		out.append({
			"resource": res,
			"metric": metric,
			"impact": _impact_without_many(app, base, every, every_bucket),
			"sources": sources,
		})
	return out


## The resources present, in the order RESOURCES declares them, with the ones it
## does not name after all of them, alphabetically.
static func _resource_order(present: Array) -> Array:
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


## What one probe is worth under `metric`: the run-level number the resource is
## measured against, or - for a resource the run-level probe cannot see - what its
## own stat buckets lose. Positive is the upgrade helping, in all four.
static func _influence(metric: String, impact: Dictionary) -> float:
	match metric:
		"tick": return impact["tick_delta"]
		"water": return impact["water_delta"]
		"stat":
			# The biggest bucket, not the sum of them: a share of mission speed and
			# a share of mission payout are shares of two different things, and
			# adding them would rank a resource by how many buckets feed it.
			var top := 0.0
			for key: String in impact["stat_orders"]:
				top = maxf(top, impact["stat_orders"][key])
			return top
		_: return impact["production_orders"]


## One track's upgrades, each with its effects and what removing it would cost.
##
## The rows arrive one per effect, so they are grouped by upgrade first: a
## multi-effect upgrade has several magnitudes but only one counterfactual, and
## probing it once per effect would report the same drop several times over.
##
## Sorted by impact, descending, because the question this whole thing exists to
## answer is which upgrade is carrying the run.
static func _breakdown_upgrades(app: Node, base: Dictionary, system: UpgradeSystem,
		rows: Array) -> Array:
	var by_id := {}
	var order: Array = []
	for row: Dictionary in rows:
		var id: String = row["id"]
		if not by_id.has(id):
			# `buckets` is scaffolding for the probe below, not output: the stats
			# this upgrade writes, deduplicated, so a two-effect upgrade in one
			# bucket is measured once. Erased before the row is returned.
			by_id[id] = {"id": id, "name": row["name"], "level": row["level"],
				"effects": [], "buckets": []}
			order.append(id)
		var bucket: Array = [row["stat"], row["key"]]
		if not by_id[id]["buckets"].has(bucket):
			by_id[id]["buckets"].append(bucket)
		var mag: BigNumber = row["mag"]
		by_id[id]["effects"].append({
			"stat": row["stat"],
			# Which resource this bucket feeds, so the page groups the rows the
			# same way the probes above measured them.
			"resource": _resource_of(row["stat"])["resource"],
			"op": _op_name(row["op"]),
			"key": row["key"],
			# Scientific rather than a float: a COMPOUND effect at a few hundred
			# levels is well past what a JSON number carries.
			"mag": mag.to_scientific(),
			"mag_log": _log10(mag),
		})

	var out: Array = []
	for id: String in order:
		var upgrade: Dictionary = by_id[id]
		var buckets: Array = upgrade["buckets"]
		upgrade.erase("buckets")
		upgrade["impact"] = _impact_without(app, base, system, [StringName(id)], buckets)
		out.append(upgrade)
	# By distance rather than by fraction, for the reason production_orders exists:
	# at 1e1400 every upgrade worth having drops the fraction to exactly 1.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["impact"]["production_orders"] > b["impact"]["production_orders"])
	return out


## Where the run stands: the three things a probe below can move.
static func _measure(app: Node) -> Dictionary:
	return {
		"production": _total_production(app),
		"tick_duration": app.tick_duration(),
		"water_interval": app.water_pump_interval(),
	}


## What the run looks like with `ids` taken away, as a delta from `base`. Puts
## every level back before returning, on every path.
##
## `buckets` are the [stat, key] pairs to measure alongside the run-level three -
## the ones the upgrade being probed writes. Left empty for the whole-track probe,
## where a share of a bucket would mean nothing: the track writes a dozen of them.
static func _impact_without(app: Node, base: Dictionary, system: UpgradeSystem,
		ids: Array, buckets: Array = []) -> Dictionary:
	return _impact_without_many(app, base, [[system, ids]], buckets)


## The same, for ids spread across several tracks: `sets` is [[system, ids], ...].
## A resource is fed from six tracks at once, and what it is worth is what taking
## every one of them away does - one probe, not six added together.
static func _impact_without_many(app: Node, base: Dictionary, sets: Array,
		buckets: Array = []) -> Dictionary:
	var held_buckets := _measure_buckets(app, buckets)
	var was: Array = []
	for pair: Array in sets:
		var system: UpgradeSystem = pair[0]
		for id: StringName in pair[1]:
			was.append([system, id, system.level(id)])
			system.set_level_for_analysis(id, 0)
	var without := _measure(app)
	var lost_buckets := _measure_buckets(app, buckets)
	for entry: Array in was:
		var system: UpgradeSystem = entry[0]
		system.set_level_for_analysis(entry[1], entry[2])

	var held: BigNumber = base["production"]
	var lost: BigNumber = without["production"]
	# A run that produces nothing yet has no fraction to lose, and dividing by it
	# would be a division by zero. Zero is the honest answer: nothing is riding on
	# this upgrade because nothing is riding on anything.
	var drop := 0.0 if held.mantissa <= 0.0 else 1.0 - lost.div(held).to_float()
	var stat_drop := {}
	var stat_orders := {}
	for key: String in held_buckets:
		var held_bucket: BigNumber = held_buckets[key]
		var lost_bucket: BigNumber = lost_buckets[key]
		stat_drop[key] = 0.0 if held_bucket.mantissa <= 0.0 \
			else 1.0 - lost_bucket.div(held_bucket).to_float()
		stat_orders[key] = _orders_between(held_bucket, lost_bucket)

	return {
		"production_drop": drop,
		# The same drop as a distance rather than a fraction, because a fraction
		# stops saying anything up here: production runs to 1e1400 and a whole
		# track taken away lands the ratio under what a float can hold, so every
		# one of them reads as exactly -100%. Orders of magnitude keep separating
		# them long after that, and are what the page ranks by. See
		# _orders_between().
		"production_orders": _orders_between(held, lost),
		# Positive means the upgrade shortens it - taking it away puts the seconds
		# (or the ticks) back. Both stats are authored as negative ADDs, so this is
		# the direction that reads as "what the upgrade is doing for you".
		"tick_delta": without["tick_duration"] - base["tick_duration"],
		"water_delta": without["water_interval"] - base["water_interval"],
		# Per bucket, keyed "stat@scope_key" - the same two fields the effect rows
		# carry, so the page can match a row to its share. Both ways round again:
		# a bucket saturates exactly as hard as production does.
		"stat_drop": stat_drop,
		"stat_orders": stat_orders,
	}


## How many orders of magnitude `held` falls by when it drops to `lost`.
##
## Zero when nothing was there to lose. A `lost` of nothing is the whole distance
## rather than an infinity: it means the bucket resolved to zero without the
## upgrade, and log10(held) is how far that is from where it stood.
static func _orders_between(held: BigNumber, lost: BigNumber) -> float:
	if held.mantissa <= 0.0:
		return 0.0
	if lost.mantissa <= 0.0:
		return held.log10()
	return held.log10() - lost.log10()


## What one unit resolves to through each of `buckets`, so the probe around this
## can report what a bucket loses without the upgrade writing into it.
##
## A base of 1.0 for every stat, rather than the base the game happens to resolve
## that stat against: this is a ratio in the end, and the buckets run from a
## multiplier on a BigNumber to an ADD onto a slot count - there is no one honest
## base. What it costs is that an ADD-only bucket reads as a share of 1 + add
## rather than of the add alone. What it buys is one number per bucket, comparable
## against the other upgrades writing that same bucket, which is what it is for.
##
## TAG-scoped effects are skipped: ProductionSystem.stack() takes a node target
## but no tags, and no authored effect is TAG-scoped - data/ holds 180 GLOBAL and
## 53 NODE. One turning up would go unranked, not misranked.
static func _measure_buckets(app: Node, buckets: Array) -> Dictionary:
	var out := {}
	for bucket: Array in buckets:
		var stat: String = bucket[0]
		var key: String = bucket[1]
		var target := &""
		if key.begins_with("t:"):
			continue
		if key.begins_with("n:"):
			target = StringName(key.substr(2))
		out["%s@%s" % [stat, key]] = app.production_system.stack(
			StringName(stat), BigNumber.from_value(1.0), target)
	return out


static func _op_name(op: int) -> String:
	match op:
		UpgradeEffectDef.Op.ADD: return "ADD"
		UpgradeEffectDef.Op.INCREASED: return "INCREASED"
		UpgradeEffectDef.Op.MORE: return "MORE"
		_: return "?"


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
	# BREAKDOWN_OFF spelled out: the report is a checked-in file that diffs line by
	# line, and a breakdown is hundreds of measured rows that move on every edit.
	var pacing := run(app, BalancePolicyScript.Kind.ROI, ticks, prestiges, 0,
		DEFAULT_STRIDE, "", 0, 0.0, BREAKDOWN_OFF)
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
