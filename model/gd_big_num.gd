class_name BigNumber

## Arbitrary-large number for idle/incremental games.
## Stored as  mantissa * 10^exponent,  where  1.0 ≤ |mantissa| < 1000.0
##
## GDScript has no operator overloading, so arithmetic uses method calls:
##   var a := BigNumber.from_value(1_000_000.0)   # 1 M
##   var b := BigNumber.new(2.5, 9)               # 2.5 B  (2.5e9)
##   var total := a.add(b)
##   print(total.to_display())                     # "2.50B"

var mantissa: float  ## Normalised to [1.0, 1000.0)  (or 0)
var exponent: int    ## Power of 10

## Suffix table: one entry per 3 exponent steps.
## Extend as needed — currently covers up to 10^(23*3) = 10^69.
const SUFFIXES: Array[String] = [
	"",    "K",   "M",   "B",   "T",
	"Qa",  "Qi",  "Sx",  "Sp",  "Oc",  "No",
	"Dc",  "Ud"
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
	var sign := 1.0 if value > 0.0 else -1.0
	var abs_val := absf(value)
	var e := int(floor(log(abs_val) / log(10.0)))
	return BigNumber.new((abs_val / pow(10.0, float(e))) * sign, e)


## Shallow copy.
func copy() -> BigNumber:
	return BigNumber.new(mantissa, exponent)


# Keeps mantissa in [1, 1000) by shifting the exponent.
func _normalize() -> void:
	if mantissa == 0.0:
		exponent = 0
		return
	var sign := 1.0 if mantissa > 0.0 else -1.0
	var m := absf(mantissa)
	while m >= 1000.0:
		m /= 10.0
		exponent += 1
	while m > 0.0 and m < 1.0:
		m *= 10.0
		exponent -= 1
	mantissa = m * sign


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


# ─── Comparison ──────────────────────────────────────────────────────────────

func gt(other: BigNumber) -> bool:   # self > other
	if mantissa == 0.0 and other.mantissa == 0.0: return false
	if mantissa < 0.0 and other.mantissa >= 0.0: return false
	var min_exp = min(exponent, other.exponent)
	var scaled_mantissa = mantissa * pow(10.0, float(exponent - min_exp))
	var scaled_other_mantissa = other.mantissa * pow(10.0, float(other.exponent - min_exp))
	return scaled_mantissa > scaled_other_mantissa

func lt(other: BigNumber)  -> bool: return other.gt(self)
func gte(other: BigNumber) -> bool: return not lt(other)
func lte(other: BigNumber) -> bool: return not gt(other)

func equals(other: BigNumber) -> bool:
	return exponent == other.exponent and is_equal_approx(mantissa, other.mantissa)


# ─── Display ─────────────────────────────────────────────────────────────────

## Human-readable, suffix-based string.
## Examples:  "0"  "42"  "1.50K"  "999.99M"  "2.72e99"
func to_display(decimals: int = 1) -> String:
	if mantissa == 0.0: return "0"
	var idx := exponent / 3
	if idx >= 0 and idx < SUFFIXES.size():
		var scaled := mantissa * pow(10.0, float(exponent - idx * 3))
		if scaled >= 1000:
			scaled = scaled/1000
			idx += 1
		if idx == 0:
			return str(int(scaled))           # plain integer, no suffix
		return "%.*f%s" % [decimals, scaled, SUFFIXES[idx]]
	# Beyond the suffix table → scientific notation
	return to_scientific()


## Always scientific notation:  "1.234e56"
func to_scientific(decimals: int = 2) -> String:
	var length_mantissa = str(abs(int(mantissa))).length()
	var scaled := mantissa / pow(10.0, float(length_mantissa - 1))
	
	return "%.*fe%d" % [decimals, scaled, exponent + length_mantissa - 1]


## Godot calls this for str(bignum) and print(bignum).
func _to_string() -> String:
	return to_display()

func to_save() -> Dictionary:
	return {"m": mantissa, "e": exponent}

static func from_save(d: Dictionary) -> BigNumber:
	return BigNumber.new(d.get("m", 0.0), d.get("e", 0))
