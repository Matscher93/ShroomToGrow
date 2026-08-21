class_name DailyRewardData
extends RefCounted
## MODEL: pure state. Which day the last daily reward was claimed on, and how
## long the streak is. Knows nothing about producers, rewards or UI.
##
## What the reward *bought* is not here: it is levels in the growth UpgradeSystem
## track, the same as an invested Level Point, so a stack keeps paying out
## through everything ProductionSystem already stacks.
##
## Deliberately has no reset(): both fields are permanent and survive prestige,
## the same contract AchievementProgress documents for its tiers.

signal last_claim_day_changed(value: int)
signal streak_changed(value: int)

## DailyCalendar day index of the last claim. 0 is 1970-01-01, so a fresh save -
## and every save written before this system existed - reads as never claimed and
## has a reward waiting on first launch.
var last_claim_day: int = 0:
	set(value):
		if last_claim_day == value:
			return
		last_claim_day = value
		last_claim_day_changed.emit(last_claim_day)

## Claims made, ever. Deliberately never broken by a missed day: the streak is a
## record of turning up, and an idle game played in bursts would reset it
## constantly for no gain the player can act on.
var streak: int = 0:
	set(value):
		if streak == value:
			return
		streak = value
		streak_changed.emit(streak)

## Single source of truth for which fields round-trip through a save file.
## Add a new field here, and nowhere else, to have it saved and loaded.
const _PLAIN_FIELDS: Array[String] = ["last_claim_day", "streak"]

func to_save() -> Dictionary:
	var save_state := {}
	for field in _PLAIN_FIELDS:
		save_state[field] = get(field)
	return save_state

## Applies a save dict onto this instance in place through each field's setter,
## so *_changed signals fire as usual. Use this rather than replacing
## App.daily_reward_data: ViewModels hold a reference, swapping the instance
## orphans them.
func load_from_save(d: Dictionary) -> void:
	for field in _PLAIN_FIELDS:
		set(field, d.get(field, 0))

static func from_save(d: Dictionary) -> DailyRewardData:
	var data := DailyRewardData.new()
	data.load_from_save(d)
	return data
