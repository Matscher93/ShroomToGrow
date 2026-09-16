class_name PlayerLevelCalculator
extends RefCounted
## MODEL: pure calculation of the account-wide player level and its progress bar.
## Performs no writes.
##
## The counter is passed in rather than read off the App autoload: autoloads
## don't exist outside a running game, so anything referencing App can't be
## compiled by a test harness. Same contract as BiomeCalculator.
##
## Levels off lifetime nutrients, which PlayerData never resets, so the ladder
## keeps climbing across sporations. That is the whole point of it: perks,
## boosts and projects all measure a run, and this measures the account.
##
## The curve itself is authored - see PlayerLevelCurve - and passed in on every
## call rather than held here. Static functions with a static configuration would
## be one global to set at load and leak between tests; a parameter that defaults
## to the authored defaults is the same arithmetic with nothing to reset.
##
## Every caller that has a curve must pass it to *all* of these: a level read off
## one curve and a requirement read off another disagree silently.

## The shape used when no curve is passed. Reads off PlayerLevelCurve so the
## fallback and the authored defaults cannot drift apart.
static func _base_of(curve: PlayerLevelCurve) -> float:
	return curve.base if curve != null else PlayerLevelCurve.DEFAULT_BASE

static func _growth_of(curve: PlayerLevelCurve) -> float:
	return curve.growth if curve != null else PlayerLevelCurve.DEFAULT_GROWTH

## A non-positive exponent reads as the default rather than as authored. At zero
## every level past the first costs the same, and below it the ladder runs
## backwards - level_of() would walk it forever. Falling back here rather than
## guarding in level_of() alone keeps requirement() reading the same ladder the
## level is derived from, which is the one invariant this file has.
static func _exponent_of(curve: PlayerLevelCurve) -> float:
	if curve == null or curve.growth_exponent <= 0.0:
		return PlayerLevelCurve.DEFAULT_GROWTH_EXPONENT
	return curve.growth_exponent

## The level a lifetime nutrient total has reached. Doubles as the Level Point
## budget - one point per level - so the ladder's shape lives here alone.
static func level_of(lifetime: BigNumber, curve: PlayerLevelCurve = null) -> int:
	if lifetime.mantissa <= 0.0:
		return 0
	var base := _base_of(curve)
	var growth := _growth_of(curve)
	if base <= 0.0 or growth <= 1.0:
		return 0
	# Straight to the answer in log space rather than walking the ladder, then
	# corrected against the real requirement. The division lands on an exact
	# integer at every boundary, where a float ulp either way would put the
	# player a whole level out, and neither loop below runs more than once.
	#
	# Inverting requirement(): the ladder is base * growth^((n-1)^exponent), so
	# `steps` is (n-1)^exponent and the level is one past its exponent-th root.
	# At an exponent of 1.0 the root is the identity and this is the plain
	# division it has always been.
	var steps := (lifetime.log10() - log(base) / log(10.0)) / (log(growth) / log(10.0))
	# Below the first requirement there is no root to take - pow() of a negative
	# base with a fractional exponent is NaN, which floors to a garbage level.
	if steps < 0.0:
		return 0
	var level := maxi(0, int(floor(pow(steps, 1.0 / _exponent_of(curve)))) + 1)
	while level > 0 and lifetime.lt(requirement(level, curve)):
		level -= 1
	while lifetime.gte(requirement(level + 1, curve)):
		level += 1
	return level

## Lifetime nutrients needed to reach the given level: base * growth^((n-1)^e).
## Zero at level 0, which is where every save starts.
static func requirement(level: int, curve: PlayerLevelCurve = null) -> BigNumber:
	if level <= 0:
		return BigNumber.new(0.0, 0)
	var scaled := pow(float(level - 1), _exponent_of(curve))
	return BigNumber.from_value(_base_of(curve)).mul(
		BigNumber.from_value(_growth_of(curve)).pow_float(scaled))

## {level, into, need, pct} for a lifetime nutrient total: the level itself, how
## far into it the player is, how wide it is, and the fraction for the bar.
static func level_for(lifetime: BigNumber, curve: PlayerLevelCurve = null) -> Dictionary:
	var level := level_of(lifetime, curve)
	var prev := requirement(level, curve)
	var req := requirement(level + 1, curve)
	return {
		"level": level,
		"into": lifetime.sub(prev),
		"need": req.sub(prev),
		"pct": _pct(lifetime, prev, req),
	}

## The bar's fill, measured in log space rather than as into.div(need).
##
## Both ends of a level are exponentials, and past float range the ratio of two
## BigNumbers collapses to 0 or inf - the bar would stick at one end for the
## whole late game. In log space it stays exact at any size.
##
## BigNumber.log10() push_errors on zero, so both zero cases are spelled out
## rather than left to it: an untouched save, and the level-0 floor, whose
## requirement is zero by definition.
static func _pct(lifetime: BigNumber, prev: BigNumber, req: BigNumber) -> float:
	if lifetime.mantissa <= 0.0:
		return 0.0
	var hi := req.log10()
	var lo := prev.log10() if prev.mantissa > 0.0 else 0.0
	if hi <= lo:
		return 1.0
	return clampf((lifetime.log10() - lo) / (hi - lo), 0.0, 1.0)
