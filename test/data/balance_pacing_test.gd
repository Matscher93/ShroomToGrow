extends GdUnitTestSuite
## Guards on tools/balance_report.json, the checked-in snapshot of what the
## authored numbers cost and how long they take to play.
##
## Two jobs, and the first is what makes the second trustworthy. The costs in the
## report are recomputed here from the .tres files: if they no longer match, the
## report predates the current data and the pacing numbers below it describe a
## game that no longer exists. Regenerate it with
##
##     godot --headless tools/sc_balance_sim.tscn -- --report
##
## The second job is the bounds themselves. They are deliberately wide - this
## catches an edit that moves pacing by an order of magnitude, not one that moves
## it by a few ticks - and they live as constants right here so retuning the game
## means retuning one line.

const REPORT_PATH := "res://tools/balance_report.json"

const BalanceDataScript := preload("res://tools/gd_balance_data.gd")

## A first prestige earlier than this means the run is over before the player has
## seen anything; later, and the prestige system may as well not exist.
const MIN_FIRST_PRESTIGE_TICK := 20
const MAX_FIRST_PRESTIGE_TICK := 1500

## Every biome the reference run has to reach at least once. Crystal Caves and
## Underground Lake are not on the list: the run stops at its prestige target,
## which comes first.
##
## Meadow is on it now. It used to be always_unlocked, seeded into the open set
## before the first tick and never worth a milestone; it is a bought biome like
## the rest since, and a run that cannot afford its one nutrient is a run that
## produces nothing at all.
const REQUIRED_BIOMES: Array[String] = ["meadow", "forest", "permafrost"]

## A cost curve that does not rise makes an upgrade free to max out.
const MIN_COST_GROWTH := 1.0

var _report: Dictionary

func before_test() -> void:
	var text := FileAccess.get_file_as_string(REPORT_PATH)
	assert_str(text).override_failure_message(
		"%s is missing. Generate it with: godot --headless tools/sc_balance_sim.tscn -- --report"
			% REPORT_PATH).is_not_empty()
	var parsed: Variant = JSON.parse_string(text)
	assert_that(parsed is Dictionary).override_failure_message(
		"%s is not valid JSON" % REPORT_PATH).is_true()
	_report = parsed


func test_report_generated_without_errors() -> void:
	assert_array(_report.get("errors", [])).is_empty()


# ─── Freshness ───────────────────────────────────────────────────────────────

func test_perk_costs_in_the_report_match_the_authored_data() -> void:
	var live: Dictionary = BalanceDataScript.perks()
	var by_id := {}
	for row: Dictionary in live["perks"]:
		by_id[row["id"]] = row

	var reported: Array = _report["perks"]
	assert_int(reported.size()).override_failure_message(
		"The report holds %d perks, the data builds %d - regenerate the report."
			% [reported.size(), by_id.size()]).is_equal(by_id.size())

	for row: Dictionary in reported:
		var id: String = row["id"]
		assert_bool(by_id.has(id)).override_failure_message(
			"Perk '%s' is in the report but no longer in the data - regenerate it." % id).is_true()
		var current: Dictionary = by_id[id]
		assert_str(row["cost_to_max"]).override_failure_message(
			"Perk '%s' costs %s to max, the report says %s - regenerate the report."
				% [id, _scientific(current["cost_to_max"]), row["cost_to_max"]]
		).is_equal(_scientific(current["cost_to_max"]))
		assert_str(row["path_cost"]).override_failure_message(
			"Perk '%s' costs %s to reach, the report says %s - regenerate the report."
				% [id, _scientific(current["path_cost"]), row["path_cost"]]
		).is_equal(_scientific(current["path_cost"]))


# ─── Pacing ──────────────────────────────────────────────────────────────────

func test_the_reference_run_reaches_its_prestige_target() -> void:
	var pacing: Dictionary = _report["pacing"]
	assert_int(int(pacing["prestiges"])).override_failure_message(
		("The reference run took %d prestiges in %d ticks. Either the run is now too "
			+ "slow to prestige, or the tick budget needs raising.")
			% [int(pacing["prestiges"]), int(pacing["tick_budget"])]).is_greater(0)


func test_the_first_prestige_lands_inside_its_window() -> void:
	var first := -1
	for milestone: Dictionary in _report["pacing"]["milestones"]:
		if milestone["event"] == "prestige":
			first = int(milestone["tick"])
			break
	assert_int(first).override_failure_message(
		"The reference run never prestiged.").is_greater(0)
	assert_int(first).override_failure_message(
		"First prestige at tick %d, outside the %d-%d window this game is tuned for."
			% [first, MIN_FIRST_PRESTIGE_TICK, MAX_FIRST_PRESTIGE_TICK]
	).is_between(MIN_FIRST_PRESTIGE_TICK, MAX_FIRST_PRESTIGE_TICK)


func test_every_gating_biome_is_reached() -> void:
	var reached := {}
	for milestone: Dictionary in _report["pacing"]["milestones"]:
		if milestone["event"] == "biome":
			reached[milestone["detail"]] = true
	for key: String in REQUIRED_BIOMES:
		assert_bool(reached.has(key)).override_failure_message(
			"The reference run never unlocked '%s'." % key).is_true()


# ─── Data sanity ─────────────────────────────────────────────────────────────

func test_every_priced_upgrade_gets_more_expensive_with_level() -> void:
	var curves: Dictionary = BalanceDataScript.curves("res://data")["curves"]
	for path: String in curves:
		var curve: Dictionary = curves[path]
		assert_float(curve["cost_growth"]).override_failure_message(
			("%s has cost_growth %f, so every level costs the same or less than the "
				+ "one before it.") % [path, curve["cost_growth"]]).is_greater(MIN_COST_GROWTH)


func test_no_perk_is_priced_out_of_its_own_branch() -> void:
	var live: Dictionary = BalanceDataScript.perks()
	var totals := {}
	for branch: Dictionary in live["branches"]:
		totals[branch["branch_key"]] = _big(branch["total_cost_to_max"])
	# The chain back to a perk starts at the core, which belongs to no branch, so
	# it is added to whatever branch the perk hangs on.
	var core: BigNumber = totals.get("", BigNumber.new(0.0, 0))

	for row: Dictionary in live["perks"]:
		var budget: BigNumber = totals.get(row["branch_key"], BigNumber.new(0.0, 0)).add(core)
		assert_bool(_big(row["path_cost"]).lte(budget)).override_failure_message(
			("Perk '%s' costs %s to reach, more than its whole branch plus the core "
				+ "costs to max (%s) - the branch rollup and the path walk disagree.")
				% [row["id"], _scientific(row["path_cost"]), budget.to_scientific()]).is_true()


# ─── Helpers ─────────────────────────────────────────────────────────────────

## The report stores costs the way BigNumber prints them, so comparing a live
## value means printing it the same way rather than comparing floats.
func _scientific(pair: Array) -> String:
	return BigNumber.new(pair[0], pair[1]).to_scientific()


## Costs travel as [mantissa, exponent] pairs and are compared as BigNumbers,
## since a deep path cost has no float to be compared as.
func _big(pair: Array) -> BigNumber:
	return BigNumber.new(pair[0], pair[1])
