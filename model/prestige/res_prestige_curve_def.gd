class_name PrestigeCurveDef
extends Resource
## MODEL: how a finished run is priced - the two storage ladders it fills and
## what a filled area pays out.
##
## Two stats fill storage: the nutrients the run *produced* (not the balance it
## happens to be holding) and the ticks it survived. Each ladder's areas cost
## exponentially more than the last, so a run that doubles its output fills a
## fixed number of extra areas rather than an unbounded pile of them - which is
## what keeps the payout finite while nutrient output is not.
##
## Every number the payout depends on lives here rather than in
## PrestigeCalculator, so the balance editor can tune the whole prestige loop
## without a code change. See tools/balance_editor/game_prestige.js.

## Run nutrients the first nutrient area needs, as a BigNumber's two halves.
## Stored as a pair because BigNumber is not an @export type - the same shape
## UpgradeDef prices with.
@export var _nutrient_base_mantissa: float = 1.0
@export var _nutrient_base_exponent: int = 3
## Factor each nutrient area past the first costs over the one below it.
@export var nutrient_growth: float = 10.0

## Ticks the first tick area needs, and the factor per area after it.
@export var _tick_base_mantissa: float = 6.0
@export var _tick_base_exponent: int = 1
@export var tick_growth: float = 2.0

## Biomass a run with exactly one filled area (of either kind) pays, and the
## factor every further area multiplies that by.
@export var _payout_base_mantissa: float = 1.0
@export var _payout_base_exponent: int = 0
@export var payout_growth: float = 1.6

## Hard ceiling on the areas one ladder may report. A growth of 1.0 or below
## makes the ladder flat and every amount infinitely deep, and the payout is an
## exponential of the total: without this a mistyped growth is not a bad curve
## but a hang.
@export var max_areas: int = 200

func nutrient_base() -> BigNumber:
	return BigNumber.new(_nutrient_base_mantissa, _nutrient_base_exponent)

func tick_base() -> BigNumber:
	return BigNumber.new(_tick_base_mantissa, _tick_base_exponent)

func payout_base() -> BigNumber:
	return BigNumber.new(_payout_base_mantissa, _payout_base_exponent)
