class_name MissionDef
extends Resource
## MODEL: static definition of one mission. How long it runs, who may run it, and
## what it pays. Parallel to ProjectDef / BoostDef.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String

## Seconds one run takes before any &"mission_speed" upgrade shortens it. Real
## seconds, not ticks: a mission is a wall-clock errand, so it finishes while the
## game is closed and its length does not stretch with the tick rate.
@export var base_duration_seconds: float = 60.0

## Rank a creature must have reached to be sent here. Rank 1 is a fresh recruit.
@export var min_creature_rank: int = 1

## Missions collected, across every mission, before this one opens. The whole
## ladder is reachable by a player who never sporates again - same contract as
## ProjectDef.min_project_levels.
@export var min_missions_completed: int = 0

## Optional perk gate on top of the ladder, for a mission that is meant to be
## prestige-locked rather than progress-locked. Empty means no perk is needed.
## Mirrors BoostDef.unlock_perk_id.
@export var unlock_perk_id: StringName = &""

@export var payouts: Array[MissionPayoutDef] = []
