class_name PrestigeCalculator
extends RefCounted
## MODEL: pure calculation, no state. Every constant it works from is authored
## on the PrestigeCurveDef it is handed, so the whole prestige payout is tunable
## from the balance editor.
##
## A run fills two ladders of storage areas - one from the nutrients it produced,
## one from the ticks it survived - and each area up a ladder costs a factor more
## than the one below it, a factor its ladder's growth exponent may itself widen
## with the area index. The number of *filled* areas, both ladders
## summed, is what the payout is an exponential of. Whole areas only: a run is
## worth what it has finished filling, which is what makes "one more area" a
## thing a player can see coming.

## Exponent above which a gain is left fractional. Below it a gain is floored,
## because the perk tree prices in whole biomass and a fractional remainder is
## unspendable; above it floor() is meaningless anyway - the value has more
## digits than a double holds.
const WHOLE_NUMBER_LIMIT := 15

## Relative slack on the area index a run has bought, absorbing the float error
## of taking the ladder in log space. Far below the one whole area that would
## change a payout, and far above the error a difference of logarithms carries.
const AREA_EPSILON := 0.000000001

## The index a ladder is actually raised to at `area` steps above its base:
## `area * growth_exponent^area`, the same scaled level UpgradeSystem prices a
## purchase with. At an exponent of 1.0 this is the plain index and the ladder is
## a plain exponential; above it each further area is worth more index than the
## one below, which is what bends the ladder upward.
##
## Clamped at 1.0 because a smaller exponent turns the index back downward past
## its peak - see PrestigeCurveDef.nutrient_growth_exponent.
static func scaled_area(area: int, growth_exponent: float) -> float:
	var steps := float(maxi(area, 0))
	return steps * pow(maxf(growth_exponent, 1.0), steps)

## How many areas `amount` fills on a ladder starting at `base` and multiplying
## by `growth^(k * growth_exponent^k)` at area k above it. Zero below the first
## area, clamped at `max_areas`.
##
## Done in log space rather than by walking the ladder: run nutrients pass what a
## double holds long before the ladder runs out of areas. A bent ladder
## (growth_exponent above 1.0) has no closed-form inverse - `k * e^k` is Lambert
## W shaped - so it is bisected instead, which is bounded by max_areas at some
## seventeen steps of float arithmetic rather than by the areas actually filled.
static func areas_filled(amount: BigNumber, base: BigNumber, growth: float,
		growth_exponent: float, max_areas: int) -> int:
	if amount == null or base == null or amount.mantissa <= 0.0 or base.mantissa <= 0.0:
		return 0
	if amount.lt(base):
		return 0
	# A flat or shrinking ladder has no area width to divide by. Everything at or
	# past the base sits in the last area rather than in an infinite number of
	# them; PrestigeCurveDef.max_areas documents why this cannot be left to loop.
	if growth <= 1.0:
		return max_areas
	# How much index the run has bought, in areas of an unbent ladder. Carrying a
	# relative slack for the same reason calculate_biomass_gain snaps: the span is
	# a difference of logarithms, so an amount sitting exactly on an area's
	# threshold lands on 2.8799999 rather than on 2.88 - and without the slack
	# that is an area the run filled and does not get paid for.
	var span := (amount.log10() - base.log10()) / (log(growth) / log(10.0))
	span += AREA_EPSILON * maxf(1.0, absf(span))
	if maxf(growth_exponent, 1.0) == 1.0:
		return clampi(int(floor(span)) + 1, 0, max_areas)
	# Largest k with scaled_area(k) <= span. The climb is monotonic (the exponent
	# is clamped at 1.0), so bisection cannot land past the first area that
	# outruns the span - and an index that overflows to INF simply fails the test.
	var low := 0
	var high := maxi(max_areas - 1, 0)
	while low < high:
		var middle := low + (high - low + 1) / 2
		if scaled_area(middle, growth_exponent) <= span:
			low = middle
		else:
			high = middle - 1
	return clampi(low + 1, 0, max_areas)

## What `area` costs on this ladder: `base * growth^scaled_area(area - 1)`. Zero
## for area 0, which is the empty ladder rather than a threshold.
static func area_threshold(base: BigNumber, growth: float, growth_exponent: float,
		area: int) -> BigNumber:
	if area <= 0 or base == null:
		return BigNumber.new(0.0, 0)
	# BigNumber.pow_float clamps at MAX_EXPONENT, so a scaled index that has run
	# off the end of a double lands on the largest BigNumber rather than a NaN.
	return base.mul(BigNumber.from_value(growth).pow_float(
		scaled_area(area - 1, growth_exponent)))

## Progress across the area currently being filled, 0.0 to 1.0, for a storage
## bar. Measured against the same two numbers the bar is labelled with - what
## the area started at and what it needs - so a bar at half is a label at half.
static func fill_fraction(amount: BigNumber, base: BigNumber, growth: float,
		growth_exponent: float, areas: int) -> float:
	if amount == null or base == null or amount.mantissa <= 0.0 or base.mantissa <= 0.0:
		return 0.0
	if growth <= 1.0:
		return 0.0
	var filled := area_threshold(base, growth, growth_exponent, areas)
	var needed := area_threshold(base, growth, growth_exponent, areas + 1)
	var span := needed.sub(filled)
	if span.mantissa <= 0.0:
		return 0.0
	return clampf(amount.sub(filled).div(span).to_float(), 0.0, 1.0)

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
		def.nutrient_growth_exponent, def.max_areas)

## Areas the tick ladder has filled this run.
static func tick_areas(tick_count: int, def: PrestigeCurveDef) -> int:
	return areas_filled(BigNumber.from_value(float(maxi(tick_count, 0))), def.tick_base(),
		def.tick_growth, def.tick_growth_exponent, def.max_areas)

## Both ladders summed - the number the payout is an exponential of.
static func total_areas(tick_count: int, nutrients_generated: BigNumber,
		def: PrestigeCurveDef) -> int:
	return nutrient_areas(nutrients_generated, def) + tick_areas(tick_count, def)
