class_name ProductionSystem
extends RefCounted
## MODEL: resolves a stat through every upgrade track at once.
##
## The three UpgradeSystems (symbiosis, biome upgrades, perks) write into the
## same stat buckets, so any upgrade targeting a stat contributes automatically.
## Adding one is a data edit, never a wiring change.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. Order is fixed: symbiosis, then biome, then prestige.

var _symbiosis: UpgradeSystem
var _biome: UpgradeSystem
var _prestige: UpgradeSystem
var _ctx: ResolveContext

func _init(symbiosis: UpgradeSystem, biome: UpgradeSystem, prestige: UpgradeSystem,
		ctx: ResolveContext) -> void:
	_symbiosis = symbiosis
	_biome = biome
	_prestige = prestige
	_ctx = ctx

## Runs base through all three tracks. `target` scopes the lookup to one node id
## or biome key, leave it empty for a global stat.
func stack(stat: StringName, base: BigNumber, target: StringName = &"") -> BigNumber:
	var value := _symbiosis.modify(stat, base, _ctx, [], target)
	value = _biome.modify(stat, value, _ctx, [], target)
	return _prestige.modify(stat, value, _ctx, [], target)

## Everything boosting the stat *except* the player's own symbiosis levels.
## Scales a symbiosis upgrade's marginal per-level rate for display, so the
## shown rate includes the boosts applied on top of it.
func stack_external(stat: StringName, base: BigNumber, target: StringName = &"") -> BigNumber:
	var value := _biome.modify(stat, base, _ctx, [], target)
	return _prestige.modify(stat, value, _ctx, [], target)

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
