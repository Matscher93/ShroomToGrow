class_name WorkerCostDef
extends Resource
## MODEL: what the next worker costs, as one curve per currency.
##
## A worker is priced in all three mission currencies at once rather than in one
## of them. The three are earned from different chains - the first heroes each
## pay a single currency - so a price that names all three is what makes the
## whole roster worth walking rather than only the chain paying for whatever the
## player happens to want next.
##
## Every row grows on the same owned count, so the three prices stay in the ratio
## they were authored in however many workers have been hired.

## One row per currency: the def, and the base of its curve.
@export var prices: Array[MissionPayoutDef] = []

## Multiplier per worker already owned. Applied to every row alike:
## `base * growth^owned`, so the first worker costs exactly the authored base.
@export var cost_growth: float = 1.35
