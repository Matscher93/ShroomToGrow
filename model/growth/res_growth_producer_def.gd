class_name GrowthProducerDef
extends Resource
## MODEL: static definition of one producer the player level and the daily
## reward can boost - which currency it stands for, which stat carries the
## bonus, and how much one stack of each is worth.
##
## The label and the colours are not repeated here: `currency` points at the
## CurrencyDef the resource pill already uses, so a producer renamed or
## recoloured once is renamed and recoloured everywhere.

## The currency this producer makes. Supplies the display name and colours, and
## its `currency_type` is what the generated upgrade ids are keyed on.
@export var currency: CurrencyDef

## The stat both stacks write into, e.g. &"water_production". Must be one
## ProductionSystem already stacks, or the producer is a no-op.
@export var stat: StringName

## How far the bonus reaches, and what it reaches. GLOBAL with an empty target is
## the usual case.
##
## NODE with target &"0" is how a &"node_production" bonus is kept to nutrient
## output alone - the same reason BoostDef documents at length. Tier 0 is the
## only node whose production becomes nutrients and every tier above it feeds the
## tier below, so a global &"node_production" bonus is applied once per tier: a
## x1.05 lands as x1.05^10.
@export var scope: UpgradeEffectDef.Scope = UpgradeEffectDef.Scope.GLOBAL
@export var target: StringName = &""

## Fraction one invested Level Point adds, on top of 1.0. Stacks add rather than
## compound - ten points is x1.5, not x1.63 - because the compounding in this
## system lives in the global doubling instead.
@export var lp_per_level: float = 0.05

## Fraction one claimed daily reward adds, on top of 1.0. Additive for the same
## reason as lp_per_level.
@export var daily_per_level: float = 0.02
