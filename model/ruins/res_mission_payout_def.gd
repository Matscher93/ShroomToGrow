class_name MissionPayoutDef
extends Resource
## MODEL: one currency a mission pays, and how much of it.
##
## A mission holds a list of these rather than a single currency and amount, so
## "which resource does this kind of mission yield" is authored data and not a
## branch in MissionSystem. A dig that pays relics and a rite that pays glyphs and
## ichor are the same code path.

@export var currency: CurrencyDef

## The stat scaling this payout on its own, on top of the shared &"mission_reward"
## multiplier - &"relic_gain", &"ichor_gain", &"glyph_gain". Empty for a payout no
## boost may single out.
@export var gain_stat: StringName = &""

@export var _amount_mantissa: float = 1.0
@export var _amount_exponent: int = 0
var amount: BigNumber:
	get: return BigNumber.new(_amount_mantissa, _amount_exponent)
	set(value):
		_amount_mantissa = value.mantissa
		_amount_exponent = value.exponent
