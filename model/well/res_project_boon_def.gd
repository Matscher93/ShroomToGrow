class_name ProjectBoonDef
extends Resource
## MODEL: one payoff of a well project. A project starts out offering only its
## first boon; funding it far enough opens the next.
##
## The effect is an ordinary UpgradeEffectDef, so a boon can raise any stat
## ProductionSystem already stacks, with any op and any scope, without a line of
## code per boon.

@export var display_name: String
@export_multiline var description: String

## Project level this boon opens at. The first boon of a project must be 1 - it
## is the one carrying the project's own level and water price (see ProjectTree).
##
## A boon opening at level 5 takes its first level exactly when the project
## reaches 5, so its own level is (project level - unlock_at_level + 1). Nothing
## computes that: it falls out of WellSystem.invest() only levelling the boons
## that are open.
@export var unlock_at_level: int = 1

@export var effect: UpgradeEffectDef
