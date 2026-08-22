class_name ProductionSystem
extends RefCounted
## MODEL: resolves a stat through every upgrade track at once.
##
## The eight UpgradeSystems (symbiosis, biome upgrades, perks, crystal boosts,
## well projects, growth, fertilizer, mission boosts) write into the same stat
## buckets, so any upgrade targeting a stat contributes automatically. Adding one
## is a data edit, never a wiring change.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Order is fixed: symbiosis, then biome, then prestige, then boosts,
## then projects, then growth, then fertilizer, then missions.

var _symbiosis: UpgradeSystem
var _biome: UpgradeSystem
var _prestige: UpgradeSystem
var _boosts: UpgradeSystem
var _projects: UpgradeSystem
var _growth: UpgradeSystem
var _fertilizer: UpgradeSystem
var _missions: UpgradeSystem
var _ctx: ResolveContext

## Resolved results, dropped whole the moment any track changes. One stack() is
## eight UpgradeSystem.modify() calls and node_production_bonus() is three
## stacks, so a tick that reads the same node's bonus for production, for a
## purchase decision and again for an automation paid nine resolves for one
## answer. Nothing in a ResolveContext moves without an invalidate() (it says so
## itself), so "any track changed" is the only staleness there is.
##
## Shape: stat -> target -> [base_mantissa, base_exponent, value]. Two dictionary
## lookups and two float compares, rather than one composite key that would cost
## a String to build on every hot-path read.
var _memo: Dictionary = {}
var _memo_external: Dictionary = {}
var _memo_version := -1

## `boosts`, `projects`, `growth`, `fertilizer` and `missions` default to empty
## tracks so the callers that predate the boosts menu, the well, the growth sheet,
## the events queue and the ruins - and the tests that only care about one of the
## other three - keep building a ProductionSystem with four arguments. An empty
## UpgradeSystem resolves to the identity, so the stack below needs no null check
## on the hot path.
func _init(symbiosis: UpgradeSystem, biome: UpgradeSystem, prestige: UpgradeSystem,
		ctx: ResolveContext, boosts: UpgradeSystem = null,
		projects: UpgradeSystem = null, growth: UpgradeSystem = null,
		fertilizer: UpgradeSystem = null, missions: UpgradeSystem = null) -> void:
	_symbiosis = symbiosis
	_biome = biome
	_prestige = prestige
	_boosts = boosts if boosts != null else UpgradeSystem.new()
	_projects = projects if projects != null else UpgradeSystem.new()
	_growth = growth if growth != null else UpgradeSystem.new()
	_fertilizer = fertilizer if fertilizer != null else UpgradeSystem.new()
	_missions = missions if missions != null else UpgradeSystem.new()
	_ctx = ctx

## Runs base through every track. `target` scopes the lookup to one node id
## or biome key, leave it empty for a global stat.
func stack(stat: StringName, base: BigNumber, target: StringName = &"") -> BigNumber:
	var hit := _recall(_memo, stat, base, target)
	if hit != null:
		return hit
	var value := _symbiosis.modify(stat, base, _ctx, [], target)
	value = _biome.modify(stat, value, _ctx, [], target)
	value = _prestige.modify(stat, value, _ctx, [], target)
	value = _boosts.modify(stat, value, _ctx, [], target)
	value = _projects.modify(stat, value, _ctx, [], target)
	value = _growth.modify(stat, value, _ctx, [], target)
	value = _fertilizer.modify(stat, value, _ctx, [], target)
	value = _missions.modify(stat, value, _ctx, [], target)
	return _remember(_memo, stat, base, target, value)

## Everything boosting the stat *except* the player's own symbiosis levels. The
## project, growth and fertilizer tracks belong here as much as the boosts do: all
## four survive a sporation, and biomass and crystals are only ever resolved
## through here - so leaving growth out would make two of its four producers
## inert, and leaving fertilizer out would half-disable two of its three
## upgrades.
## Scales a symbiosis upgrade's marginal per-level rate for display, so the
## shown rate includes the boosts applied on top of it.
func stack_external(stat: StringName, base: BigNumber, target: StringName = &"") -> BigNumber:
	var hit := _recall(_memo_external, stat, base, target)
	if hit != null:
		return hit
	var value := _biome.modify(stat, base, _ctx, [], target)
	value = _prestige.modify(stat, value, _ctx, [], target)
	value = _boosts.modify(stat, value, _ctx, [], target)
	value = _projects.modify(stat, value, _ctx, [], target)
	value = _growth.modify(stat, value, _ctx, [], target)
	value = _fertilizer.modify(stat, value, _ctx, [], target)
	value = _missions.modify(stat, value, _ctx, [], target)
	return _remember(_memo_external, stat, base, target, value)

# ------------------------------------------------------------ introspection

## The eight tracks in stacking order, each with the name the balance tools show
## it under: [["symbiosis", UpgradeSystem], ["biome", ...], ...].
##
## Ordered because the order is part of how a stat resolves, and handed out as
## pairs rather than through eight accessors because the one caller - the balance
## simulator, which zeroes a level and re-measures - wants to treat them alike.
##
## Kept in step with stack() by hand. stack() does not read this: it runs on the
## hot path, hundreds of times a tick, and would be building this array every
## time. A ninth track has to be added in both places.
func tracks() -> Array:
	return [
		["symbiosis", _symbiosis],
		["biome", _biome],
		["prestige", _prestige],
		["boosts", _boosts],
		["projects", _projects],
		["growth", _growth],
		["fertilizer", _fertilizer],
		["missions", _missions],
	]

## Every track's breakdown, keyed by track name. See UpgradeSystem.breakdown().
func breakdown() -> Dictionary:
	var out := {}
	for pair: Array in tracks():
		var system: UpgradeSystem = pair[1]
		out[pair[0]] = system.breakdown(_ctx)
	return out

# ---------------------------------------------------------------- memo

## The memoised result for this exact call, or null when there is none. Clears
## both memos first if any track has moved since they were filled.
func _recall(memo: Dictionary, stat: StringName, base: BigNumber,
		target: StringName) -> BigNumber:
	var live := _version()
	if live != _memo_version:
		_memo.clear()
		_memo_external.clear()
		_memo_version = live
		return null
	var entry: Variant = memo.get(stat, {}).get(target)
	if entry == null:
		return null
	# One stat is read with more than one base (biomass and crystal gain both
	# stack their own running total), so the base is part of the identity.
	if entry[0] != base.mantissa or entry[1] != base.exponent:
		return null
	var value: BigNumber = entry[2]
	return value

## Files a result under its call, and hands it straight back so callers can
## `return _remember(...)`. BigNumber has no mutating operation, so sharing the
## instance with every later caller is safe.
func _remember(memo: Dictionary, stat: StringName, base: BigNumber, target: StringName,
		value: BigNumber) -> BigNumber:
	if not memo.has(stat):
		memo[stat] = {}
	memo[stat][target] = [base.mantissa, base.exponent, value]
	return value

## Where all eight tracks are, as one number. Any purchase, reset, save load or
## invalidate() moves it.
func _version() -> int:
	return _symbiosis.version + _biome.version + _prestige.version + _boosts.version \
		+ _projects.version + _growth.version + _fertilizer.version + _missions.version

# ---------------------------------------------------------------- node output

func node_potency_bonus(node_id: StringName) -> BigNumber:
	return stack(&"potency_production", BigNumber.from_value(1.0), node_id)

func node_synergy_bonus(node_id: StringName) -> BigNumber:
	return stack(&"synergy_production", BigNumber.from_value(1.0), node_id)

func node_potency_external_multiplier(node_id: StringName) -> BigNumber:
	return stack_external(&"potency_production", BigNumber.from_value(1.0), node_id)

func node_synergy_external_multiplier(node_id: StringName) -> BigNumber:
	return stack_external(&"synergy_production", BigNumber.from_value(1.0), node_id)

## The potency and synergy tracks on their own, without the &"node_production"
## multipliers stacked on top. Displayed next to the total so the player can see
## what their own symbiosis levels contribute.
func node_symbiosis_bonus(node_id: StringName) -> BigNumber:
	return node_potency_bonus(node_id).mul(node_synergy_bonus(node_id))

## Shared by the tick loop and the display ViewModels so they can't drift.
func node_production_bonus(node_id: StringName) -> BigNumber:
	return stack(&"node_production", node_symbiosis_bonus(node_id), node_id)

# ---------------------------------------------------------------- global stats

## Biomass is only ever boosted by biome upgrades and perks, never by the
## symbiosis levels the prestige is about to reset.
func modify_biomass_gain(base: BigNumber) -> BigNumber:
	return stack_external(&"biomass_gain", base)

## Crystals are permanent, so the symbiosis track (wiped on the very next
## prestige) must not inflate an achievement payout the player keeps forever.
func modify_crystal_gain(base: BigNumber) -> BigNumber:
	return stack_external(&"crystal_gain", base)

## What one pump of the well draws up. Water is a run currency the sporation
## wipes, exactly like nutrients, so the symbiosis track counts here - unlike
## biomass and crystals, which are permanent and use stack_external.
func modify_water_gain(base: BigNumber) -> BigNumber:
	return stack(&"water_production", base)

## Ticks between one pump and the next. Any upgrade targeting &"water_rate"
## shortens the gap, authored as an ADD effect with a negative per_level - the
## same shape as tick_rate. Clamped so a stacked discount can never reach or
## cross zero.
func water_interval(base_interval: float, minimum: float) -> float:
	var interval := stack(&"water_rate", BigNumber.from_value(base_interval))
	return maxf(minimum, interval.to_float())

## Divides an automation's authored interval, so an upgrade raising
## &"automation_rate" makes automations fire more often. Clamped away from zero
## and below, which a stacked bonus could otherwise reach.
func automation_rate() -> float:
	var rate := stack(&"automation_rate", BigNumber.from_value(1.0))
	return maxf(0.01, rate.to_float())

## Any upgrade targeting &"tick_rate" shortens the interval. Clamped so a
## stacked discount can never reach or cross zero.
func tick_duration(base_duration: float, minimum: float) -> float:
	var duration := stack(&"tick_rate", BigNumber.from_value(base_duration))
	return maxf(minimum, duration.to_float())

# ---------------------------------------------------------------- missions

## Divides a mission's authored duration, so an upgrade raising &"mission_speed"
## brings a creature home sooner. Clamped away from zero and below, which a
## stacked bonus could otherwise reach - same shape as automation_rate().
func mission_speed() -> float:
	var speed := stack(&"mission_speed", BigNumber.from_value(1.0))
	return maxf(0.01, speed.to_float())

## Missions the player may have in flight at once, on top of the base allowance.
## Read as a count rather than a multiplier, the way biome and level points are:
## an ADD effect on &"mission_slots" is what a perk buys to widen the board.
func mission_slots() -> int:
	return int(stack(&"mission_slots", BigNumber.new(0.0, 0)).to_float())

## Levels one creature may be ranked up beyond its authored ceiling. Scoped by
## creature id, so a perk can lift one thrall without lifting the whole roster -
## the same shape BoostSystem.extra_max_levels() reads &"boost_max_level" in.
func creature_rank_bonus(creature_id: StringName) -> int:
	return int(stack(&"creature_rank_cap", BigNumber.new(0.0, 0), creature_id).to_float())

## What one mission payout is worth: the shared &"mission_reward" multiplier and
## then the payout's own per-currency stat, so a boost can lift every mission or
## only the ones paying in glyphs.
##
## stack_external, not stack: the three Ruins currencies are permanent, so the
## symbiosis track the next sporation wipes must not inflate a payout the player
## keeps - the same reasoning modify_crystal_gain() is built on.
func modify_mission_reward(base: BigNumber, gain_stat: StringName) -> BigNumber:
	var value := stack_external(&"mission_reward", base)
	if gain_stat.is_empty():
		return value
	return stack_external(gain_stat, value)
