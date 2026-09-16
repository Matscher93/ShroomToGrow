class_name PlayerLevelCurve
extends Resource
## MODEL: the shape of the account-wide level ladder - what the first level costs
## in lifetime nutrients, and what each one after it multiplies that by.
##
## Authored rather than compiled in. These two numbers were consts on
## PlayerLevelCalculator, which put the one curve the whole Growth sheet hangs
## off out of reach of the balance editor: it reads and writes res://data/**.tres
## and nothing else, so a knob that lives in a .gd cannot be tuned beside the
## numbers it has to be tuned against.
##
## The defaults below are the values those consts held, so a save, a test or a
## system built without a curve behaves exactly as it did before.

const DEFAULT_BASE := 1000.0
const DEFAULT_GROWTH := 3.0
const DEFAULT_GROWTH_EXPONENT := 1.0

## Lifetime nutrients the first level costs. A fresh save sits at level 0, so the
## first Level Point lands the moment lifetime nutrients reach this.
@export var base: float = DEFAULT_BASE

## What every level after the first multiplies the requirement by. At 3.0 the
## tenth level costs 3^9 times the first, which is the pacing the ladder was
## tuned at - below about 1.5 the levels arrive faster than points can be spent.
@export var growth: float = DEFAULT_GROWTH

## Bends the ladder itself: level n costs base * growth^((n-1)^growth_exponent).
## Same curve shape as AchievementDef.goal_growth_exponent, UpgradeSystem.cost()
## and BiomeSystem.size_cost(), and named to match them.
##
## At 1.0 - the shipped value, and the shape the ladder has always had - every
## level multiplies the one before it by exactly `growth`, so the requirement is
## exponential in the level but the *gap between levels* is a flat ratio. Above
## 1.0 that ratio itself climbs: the step from level 20 to 21 is worth more
## growths than the step from 1 to 2, which is what stretches the late ladder
## without touching the early one. Below 1.0 the ladder flattens out instead.
##
## Level Points stay one per level, so this is the only knob that decides how
## fast the Growth sheet's budget fills up late.
##
## Must be > 0.0. At or below zero there is no monotone ladder to walk, and
## PlayerLevelCalculator falls back to DEFAULT_GROWTH_EXPONENT rather than
## reading a requirement curve that runs backwards.
@export var growth_exponent: float = DEFAULT_GROWTH_EXPONENT
