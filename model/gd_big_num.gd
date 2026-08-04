class_name BigNumber
extends RefCounted

## Arbitrary-large number for idle/incremental games.
## Stored as  mantissa * 10^exponent,  where  1.0 ≤ |mantissa| < 10.0
##
## GDScript has no operator overloading, so arithmetic uses method calls:
##   var a := BigNumber.from_value(1_000_000.0)   # 1 M
##   var b := BigNumber.new(2.5, 9)               # 2.5 B  (2.5e9)
##   var total := a.add(b)
##   print(total.to_display())                     # "2.50B"

var mantissa: float  ## Normalised to [1.0, 10.0)  (or 0)
var exponent: int    ## Power of 10

## Suffix table: one entry per 3 exponent steps, ending at Decillion. 12 entries
## cover exponents 0..35, anything at or above 10^36 falls back to scientific
## notation. Extend the table (Ud, Dd, Td, ...) to push that cutoff higher.
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
# one representation. A looser range would let 1000 be either (1.0, 3) or
# (100.0, 1), breaking equals() and exponent-only ordering in gt().
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

## Integer exponentiation via fast squaring, for upgrade cost curves.
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

## Collapses back to a plain float. Only safe for values that stay in float
## range (tick duration, point counts). Anything unbounded (nutrients, biomass)
## stays a BigNumber and uses to_display().
func to_float() -> float:
	return mantissa * pow(10.0, float(exponent))

## Base-10 logarithm, which stays exact across the whole range: the exponent is
## already the integer part, so nothing has to survive a to_float() round trip.
## Undefined for zero and negatives, as log10 is, so callers guard first.
func log10() -> float:
	if mantissa <= 0.0:
		push_error("BigNumber: log10 of a non-positive value")
		return 0.0
	return log(mantissa) / log(10.0) + float(exponent)

## Real-exponent power via log10 space. Unlike pow_int it handles fractional and
## arbitrarily large exponents without overflowing (cost curves with a growth
## exponent, per-level compounding). Assumes a positive base, true for growth
## rates like cost_growth and 1+per_level.
func pow_float(float_exp: float) -> BigNumber:
	if mantissa <= 0.0:
		return BigNumber.new(0.0, 0)
	var log10_result := log10() * float_exp
	var result_exponent := int(floor(log10_result))
	var result_mantissa := pow(10.0, log10_result - result_exponent)
	return BigNumber.new(result_mantissa, result_exponent)

# ─── Comparison ──────────────────────────────────────────────────────────────

func gt(other: BigNumber) -> bool:   # self > other
	if mantissa == 0.0 and other.mantissa == 0.0: return false
	var self_negative := mantissa < 0.0
	var other_negative := other.mantissa < 0.0
	if self_negative != other_negative:
		return other_negative        # exactly one is negative, self wins iff that's the other
	if mantissa == 0.0:
		return other_negative        # 0 beats a negative, loses to a positive
	if other.mantissa == 0.0:
		return not self_negative
	# Same sign, both non-zero. Normalisation keeps |mantissa| in [1, 10), so
	# 10^e <= |value| < 10^(e+1) and a differing exponent decides on its own.
	# Do not scale both mantissas to a common exponent instead: that overflows to
	# INF a few hundred exponents apart, and INF > INF is false, which inverts
	# affordability checks late in a run.
	if exponent != other.exponent:
		return (exponent > other.exponent) != self_negative
	return mantissa > other.mantissa

func lt(other: BigNumber)  -> bool: return other.gt(self)
func gte(other: BigNumber) -> bool: return not lt(other)
func lte(other: BigNumber) -> bool: return not gt(other)

func equals(other: BigNumber) -> bool:
	return exponent == other.exponent and is_equal_approx(mantissa, other.mantissa)

## Exact field-for-field comparison, for "did this change?" guards in property
## setters. Unlike equals() it never treats two distinct values as the same, so
## a tiny but real gain can't be swallowed by an approximate compare. == is no
## use here: BigNumber is RefCounted and every result is a fresh instance.
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
		# exponent - idx*3 is 0, 1 or 2 and |mantissa| < 10, so scaled stays
		# inside [1, 1000) and the suffix idx picks is always right.
		var scaled := mantissa * pow(10.0, float(exponent - idx * 3))
		if idx == 0:
			return "%.*f" % [decimals, scaled]   # plain float, no suffix
		return "%.*f%s" % [decimals, scaled, SUFFIXES[idx]]
	# Beyond the suffix table, use scientific notation
	return to_scientific()

## Always scientific notation:  "1.234e56"
## Normalisation guarantees |mantissa| < 10, so it is already the scientific
## coefficient and needs no re-scaling.
func to_scientific(decimals: int = 2) -> String:
	return "%.*fe%d" % [decimals, mantissa, exponent]

## Godot calls this for str(bignum) and print(bignum).
func _to_string() -> String:
	return to_display()

func to_save() -> Dictionary:
	return {"m": mantissa, "e": exponent}

static func from_save(d: Dictionary) -> BigNumber:
	return BigNumber.new(d.get("m", 0.0), d.get("e", 0))
