class_name PrestigeCalculator
extends RefCounted
## MODEL: pure calculation, no state. Every constant it works from is authored
## on the PrestigeCurveDef it is handed, so the whole prestige payout is tunable
## from the balance editor.
##
## A run fills two ladders of storage areas - one from the nutrients it produced,
## one from the ticks it survived - and each area up a ladder costs a fixed
## factor more than the one below it. The number of *filled* areas, both ladders
## summed, is what the payout is an exponential of. Whole areas only: a run is
## worth what it has finished filling, which is what makes "one more area" a
## thing a player can see coming.

## Exponent above which a gain is left fractional. Below it a gain is floored,
## because the perk tree prices in whole biomass and a fractional remainder is
## unspendable; above it floor() is meaningless anyway - the value has more
## digits than a double holds.
const WHOLE_NUMBER_LIMIT := 15

## How many areas `amount` fills on a ladder starting at `base` and multiplying
## by `growth` per area. Zero below the first area, clamped at `max_areas`.
##
## Done in log space rather than by walking the ladder: run nutrients pass what a
## double holds long before the ladder runs out of areas.
static func areas_filled(amount: BigNumber, base: BigNumber, growth: float,
		max_areas: int) -> int:
	if amount == null or base == null or amount.mantissa <= 0.0 or base.mantissa <= 0.0:
		return 0
	if amount.lt(base):
		return 0
	# A flat or shrinking ladder has no area width to divide by. Everything at or
	# past the base sits in the last area rather than in an infinite number of
	# them; PrestigeCurveDef.max_areas documents why this cannot be left to loop.
	if growth <= 1.0:
		return max_areas
	var steps := (amount.log10() - base.log10()) / (log(growth) / log(10.0))
	return clampi(int(floor(steps)) + 1, 0, max_areas)

## Progress into the next area, 0.0 to 1.0, for a storage bar. Below the first
## area this measures the approach to it over one area's width, so a run that has
## filled nothing still shows movement.
static func fill_fraction(amount: BigNumber, base: BigNumber, growth: float) -> float:
	if amount == null or base == null or amount.mantissa <= 0.0 or base.mantissa <= 0.0:
		return 0.0
	if growth <= 1.0:
		return 0.0
	var steps := (amount.log10() - base.log10()) / (log(growth) / log(10.0))
	if steps < 0.0:
		return clampf(1.0 + steps, 0.0, 1.0)
	return clampf(steps - floor(steps), 0.0, 1.0)

## Biomass a run of this shape converts into, before ProductionSystem's
## &"biomass_gain" stacks. Zero until the run has filled at least one area on
## either ladder, which is what keeps a fresh run from being worth prestiging.
static func calculate_biomass_gain(tick_count: int, nutrients_generated: BigNumber,
		def: PrestigeCurveDef) -> BigNumber:
	if def == null:
		push_error("PrestigeCalculator: no PrestigeCurveDef")
		return BigNumber.new(0.0, 0)
	var total := total_areas(tick_count, nutrients_generated, def)
	if total <= 0:
		return BigNumber.new(0.0, 0)
	var gain := def.payout_base().mul(
		BigNumber.from_value(def.payout_growth).pow_float(float(total - 1)))
	if gain.exponent < WHOLE_NUMBER_LIMIT:
		return BigNumber.from_value(floor(_snap(gain.to_float())))
	return gain

## A value that is a whole number bar float error, rounded to it. The payout is
## an exponential taken in log space, so a growth of 2.0 over one area lands on
## 1.9999999 rather than on 2 - and floor() turns that into a run paying half
## what it earned. Snapped only inside a relative epsilon: a genuinely fractional
## payout is still floored.
static func _snap(value: float) -> float:
	var whole := roundf(value)
	if absf(value - whole) <= 0.000001 * maxf(1.0, absf(whole)):
		return whole
	return value


## Areas the nutrient ladder has filled this run.
static func nutrient_areas(nutrients_generated: BigNumber, def: PrestigeCurveDef) -> int:
	return areas_filled(nutrients_generated, def.nutrient_base(), def.nutrient_growth,
		def.max_areas)

## Areas the tick ladder has filled this run.
static func tick_areas(tick_count: int, def: PrestigeCurveDef) -> int:
	return areas_filled(BigNumber.from_value(float(maxi(tick_count, 0))), def.tick_base(),
		def.tick_growth, def.max_areas)

## Both ladders summed - the number the payout is an exponential of.
static func total_areas(tick_count: int, nutrients_generated: BigNumber,
		def: PrestigeCurveDef) -> int:
	return nutrient_areas(nutrients_generated, def) + tick_areas(tick_count, def)
