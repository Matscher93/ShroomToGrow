class_name MissionDef
extends Resource
## MODEL: static definition of one mission. How long it runs, who may run it, and
## what it pays. Parallel to ProjectDef / BoostDef.
##
## Two kinds share this shape, told apart by is_farm:
##
## An EXPEDITION is one-shot. It is sent by hand, collected once ever, and pays
## both its payouts and its `rewards` - a permanent upgrade that reaches the rest
## of the game. Finishing one is also what opens the farms that name it.
##
## A FARM is worked by a pool of workers and loops on its own, paying `payouts`
## per cycle and never granting a reward. base_duration_seconds is one cycle at
## one worker; each further worker divides it.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## True for a looping farm, false for a one-shot expedition. The two are run by
## different halves of the roster: an expedition by its chain's hero, a farm by
## workers. Only farms are capped, by &"farm_slots".
@export var is_farm: bool = false

## The hero whose chain this expedition belongs to. Empty on a farm, which
## belongs to no chain.
##
## A chain is walked in the order the missions are authored in, so the step
## before this one is derived rather than named - see MissionSystem.chain(). With
## twenty steps per hero, hand-linking each to its predecessor would be a hundred
## and forty chances to point at the wrong one.
@export var hero_id: StringName = &""

## Seconds one run takes before any &"mission_speed" upgrade shortens it. Real
## seconds, not ticks: a mission is a wall-clock errand, so it finishes while the
## game is closed and its length does not stretch with the tick rate.
@export var base_duration_seconds: float = 60.0

## Level this chain's hero must have reached to be sent here. Level 1 is a fresh
## recruit, which is what most steps ask for.
##
## This is the chain gate. Every fifth step asks for one level more than the
## block before it, so walking a chain to its end means levelling its hero rather
## than only running errands with it.
@export var min_hero_level: int = 1

## Missions collected, across every mission, before this one opens. Farms only:
## an expedition's ladder is its own chain, and nothing else.
@export var min_missions_completed: int = 0

## Optional perk gate on top of the ladder, for a mission that is meant to be
## prestige-locked rather than progress-locked. Empty means no perk is needed.
## Mirrors BoostDef.unlock_perk_id.
@export var unlock_perk_id: StringName = &""

## The expedition that must have been completed before this farm opens. Empty
## means no expedition is needed. The gate lives on the gated def rather than on
## the one that opens it, the same way unlock_perk_id does, so what a mission
## needs is readable from the mission.
##
## Farms only. An expedition's predecessor is its own chain's previous step, and
## an integrity test holds it to that.
@export var requires_mission_id: StringName = &""

## What collecting this pays into the player's balances. On an expedition, once
## ever; on a farm, once per cycle.
@export var payouts: Array[MissionPayoutDef] = []

## The permanent upgrade completing this expedition grants, held at level 1
## forever after - the reason to run the ladder at all, and what makes the Ruins
## matter to a player who never opens the screen again.
##
## Carried into an UpgradeDef untouched by ExpeditionRewardTree, so an effect
## naming &"node_production" reaches the colony and one naming &"mission_speed"
## reaches the board through the same ProductionSystem stack, with nothing here
## knowing the difference.
##
## Ignored on a farm: a reward that could be earned twice is not permanent.
@export var rewards: Array[UpgradeEffectDef] = []
