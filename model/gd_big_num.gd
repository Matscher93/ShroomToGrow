class_name BigNumber

## Arbitrary-large number for idle/incremental games.
## Stored as  mantissa * 10^exponent,  where  1.0 ≤ |mantissa| < 1000.0
##
## GDScript has no operator overloading, so arithmetic uses method calls:
##   var a := BigNumber.from_value(1_000_000.0)   # 1 M
##   var b := BigNumber.new(2.5, 9)               # 2.5 B  (2.5e9)
##   var total := a.add(b)
##   print(total.to_display())                     # "2.50B"

var mantissa: float  ## Normalised to [1.0, 10.0)  (or 0)
var exponent: int    ## Power of 10

## Suffix table: one entry per 3 exponent steps.
## Extend as needed — currently covers up to 10^(23*3) = 10^69.
const SUFFIXES: Array[String] = [
	"",    "K",   "M",   "B",   "T",
	"Qa",  "Qi",  "Sx",  "Sp",  "Oc",  "No",
	"Dc"
]

# ─── Construction ────────────────────────────────────────────────────────────

func _init(m: float = 0.0, e: int = 0) -> void:
	mantissa = m
	exponent = e
	_normalize()

## Build from a plain float or integer (e.g.  BigNumber.from_value(1000.0)).
static func from_value(value: float) -> BigNumber:
	if value == 0.0:
		return BigNumber.new(0.0, 0)
	var num_sign := 1.0 if value > 0.0 else -1.0
	var abs_val := absf(value)
	var e := int(floor(log(abs_val) / log(10.0)))
	return BigNumber.new((abs_val / pow(10.0, float(e))) * num_sign, e)

## Shallow copy.
func copy() -> BigNumber:
	return BigNumber.new(mantissa, exponent)

# Keeps mantissa in [1, 10) by shifting the exponent, so every value has exactly
# one representation. The looser [1, 1000) this used to allow meant 1000 could be
# either (1.0, 3) or (100.0, 1): equals() compared exponents and so called those
# two unequal, and gt() couldn't use the exponent alone to order two numbers.
func _normalize() -> void:
	if mantissa == 0.0:
		exponent = 0
		return
	var num_sign := 1.0 if mantissa > 0.0 else -1.0
	var m := absf(mantissa)
	while m >= 10.0:
		m /= 10.0
		exponent += 1
	while m > 0.0 and m < 1.0:
		m *= 10.0
		exponent -= 1
	mantissa = m * num_sign

# ─── Arithmetic ──────────────────────────────────────────────────────────────

func add(other: BigNumber) -> BigNumber:
	if mantissa == 0.0: return other.copy()
	if other.mantissa == 0.0: return copy()
	var diff := exponent - other.exponent
	# When the exponents differ by 17+ the smaller number is lost in float noise.
	if diff >= 17: return copy()
	if diff <= -17: return other.copy()
	if diff >= 0:
		return BigNumber.new(mantissa + other.mantissa / pow(10.0, float(diff)),  exponent)
	else:
		return BigNumber.new(mantissa / pow(10.0, float(-diff)) + other.mantissa, other.exponent)

func sub(other: BigNumber) -> BigNumber:
	var neg := other.copy()
	neg.mantissa = -neg.mantissa
	return add(neg)

func mul(other: BigNumber) -> BigNumber:
	return BigNumber.new(mantissa * other.mantissa, exponent + other.exponent)

func div(other: BigNumber) -> BigNumber:
	if other.mantissa == 0.0:
		push_error("BigNumber: division by zero")
		return BigNumber.new(0.0, 0)
	return BigNumber.new(mantissa / other.mantissa, exponent - other.exponent)

## Integer exponentiation via fast squaring — handy for upgrade cost curves.
## e.g.  base_cost.pow_int(level)
func pow_int(p: int) -> BigNumber:
	if p == 0: return BigNumber.new(1.0, 0)
	if p == 1: return copy()
	var result := BigNumber.new(1.0, 0)
	var base   := copy()
	var n      := p
	while n > 0:
		if n & 1:
			result = result.mul(base)
		base = base.mul(base)
		n >>= 1
	return result

## Multiply by a plain float scalar (cheaper than wrapping in a BigNumber).
func scale(factor: float) -> BigNumber:
	return BigNumber.new(mantissa * factor, exponent)

## Collapses back to a plain float. Only safe for values known to stay in
## float range (e.g. tick duration, point counts) — anything that can grow
## unbounded (nutrients, biomass) should stay a BigNumber and use to_display().
func to_float() -> float:
	return mantissa * pow(10.0, float(exponent))

## Real-exponent power via log10 space — unlike pow_int, handles fractional
## and arbitrarily large exponents without overflowing (e.g. cost curves with
## a growth exponent, or per-level compounding at high levels). Assumes a
## positive base (true for growth rates like cost_growth / 1+per_level).
func pow_float(float_exp: float) -> BigNumber:
	if mantissa <= 0.0:
		return BigNumber.new(0.0, 0)
	var log10_value := log(mantissa) / log(10.0) + exponent
	var log10_result := log10_value * float_exp
	var result_exponent := int(floor(log10_result))
	var result_mantissa := pow(10.0, log10_result - result_exponent)
	return BigNumber.new(result_mantissa, result_exponent)

# ─── Comparison ──────────────────────────────────────────────────────────────

func gt(other: BigNumber) -> bool:   # self > other
	if mantissa == 0.0 and other.mantissa == 0.0: return false
	var self_negative := mantissa < 0.0
	var other_negative := other.mantissa < 0.0
	if self_negative != other_negative:
		return other_negative        # exactly one is negative; self wins iff that's the other
	if mantissa == 0.0:
		return other_negative        # 0 beats a negative, loses to a positive
	if other.mantissa == 0.0:
		return not self_negative
	# Same sign, both non-zero. Normalisation keeps |mantissa| in [1, 10), so
	# 10^e <= |value| < 10^(e+1) and a differing exponent decides on its own.
	# The old version scaled both mantissas into a common exponent first, which
	# overflowed to INF once the exponents were a few hundred apart — and
	# INF > INF is false, so gt() returned false for values that were genuinely
	# greater, silently inverting affordability checks late in a run.
	if exponent != other.exponent:
		return (exponent > other.exponent) != self_negative
	return mantissa > other.mantissa

func lt(other: BigNumber)  -> bool: return other.gt(self)
func gte(other: BigNumber) -> bool: return not lt(other)
func lte(other: BigNumber) -> bool: return not gt(other)

func equals(other: BigNumber) -> bool:
	return exponent == other.exponent and is_equal_approx(mantissa, other.mantissa)

## Exact field-for-field comparison, for "did this actually change?" guards in
## property setters. Unlike equals() it never treats two distinct values as the
## same, so a real (if tiny) gain can't be swallowed by an approximate compare.
## Being a RefCounted, == on two BigNumbers is an identity check and is useless
## for this — every arithmetic result is a fresh instance.
func same_value(other: BigNumber) -> bool:
	return other != null and exponent == other.exponent and mantissa == other.mantissa

# ─── Display ─────────────────────────────────────────────────────────────────

## Human-readable, suffix-based string.
## Examples:  "0"  "42"  "1.50K"  "999.99M"  "2.72e99"
func to_display(decimals: int = 1) -> String:
	if mantissa == 0.0: return "0"
	@warning_ignore("integer_division")
	var idx := floori(exponent / 3)
	if idx >= 0 and idx < SUFFIXES.size():
		# exponent - idx*3 is 0, 1 or 2, and |mantissa| < 10, so scaled stays
		# inside [1, 1000) — the suffix picked by idx is always the right one.
		var scaled := mantissa * pow(10.0, float(exponent - idx * 3))
		if idx == 0:
			return "%.1f" % scaled           # plain float, no suffix
		return "%.*f%s" % [decimals, scaled, SUFFIXES[idx]]
	# Beyond the suffix table → scientific notation
	return to_scientific()

## Always scientific notation:  "1.234e56"
## Normalisation already guarantees |mantissa| < 10, so it is the scientific
## coefficient as-is — no re-scaling needed.
func to_scientific(decimals: int = 2) -> String:
	return "%.*fe%d" % [decimals, mantissa, exponent]

## Godot calls this for str(bignum) and print(bignum).
func _to_string() -> String:
	return to_display()

func to_save() -> Dictionary:
	return {"m": mantissa, "e": exponent}

static func from_save(d: Dictionary) -> BigNumber:
	return BigNumber.new(d.get("m", 0.0), d.get("e", 0))
