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

## Lifetime nutrients the first level costs. A fresh save sits at level 0, so the
## first Level Point lands the moment lifetime nutrients reach this.
@export var base: float = DEFAULT_BASE

## What every level after the first multiplies the requirement by. At 3.0 the
## tenth level costs 3^9 times the first, which is the pacing the ladder was
## tuned at - below about 1.5 the levels arrive faster than points can be spent.
@export var growth: float = DEFAULT_GROWTH
