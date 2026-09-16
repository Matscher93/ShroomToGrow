class_name DailyRewardData
extends RefCounted
## MODEL: pure state. Which day the last daily reward was claimed on, and how
## long the streak is. Knows nothing about producers, rewards or UI.
##
## What the reward *bought* is not here: it is levels in the growth UpgradeSystem
## track, the same as an invested Level Point, so a stack keeps paying out
## through everything ProductionSystem already stacks.
##
## Deliberately has no reset(): every field is permanent and survives prestige,
## the same contract AchievementProgress documents for its tiers. track_day is
## reset by a missed day, never by a sporation.

signal last_claim_day_changed(value: int)
signal streak_changed(value: int)
signal track_day_changed(value: int)
signal track_claim_day_changed(value: int)
## A producer's claim day moved. Its own signal because only the first claim of a
## day moves last_claim_day - the second and third producer claimed that day
## would otherwise leave their chips looking claimable until the next tick.
signal claim_day_changed(currency: int)

## DailyCalendar day index of the last day *any* producer was claimed on. 0 is
## 1970-01-01, so a fresh save - and every save written before this system
## existed - reads as never claimed and has a reward waiting on first launch.
##
## The day rather than the claim: each producer is claimable once a day and the
## track steps once a day, so what this marks is the last day the player turned
## up. Which producers they spent it on is claim_days below.
var last_claim_day: int = 0:
	set(value):
		if last_claim_day == value:
			return
		last_claim_day = value
		last_claim_day_changed.emit(last_claim_day)

## Days turned up on, ever - one per day however many producers were claimed on
## it. Deliberately never broken by a missed day: the streak is a record of
## turning up, and an idle game played in bursts would reset it constantly for no
## gain the player can act on.
var streak: int = 0:
	set(value):
		if streak == value:
			return
		streak = value
		streak_changed.emit(streak)

## The day the track was last stepped on. Its own day rather than last_claim_day:
## the track is claimed separately from the producer chips, so a day spent only on
## chips must leave the step waiting - and a day spent only on the step must not
## count as a chip claim either.
var track_claim_day: int = 0:
	set(value):
		if track_claim_day == value:
			return
		track_claim_day = value
		track_claim_day_changed.emit(track_claim_day)

## How far into the fourteen-day reward track the last step got, 1-based, 0 on a
## save that has never claimed one. Unlike the streak this one *is* broken by a
## missed day - DailyTrackSystem says why, and works that out by comparing
## track_claim_day against today rather than by writing a zero here on some day
## nothing ran.
var track_day: int = 0:
	set(value):
		if track_day == value:
			return
		track_day = value
		track_day_changed.emit(track_day)

## Which day each producer was last claimed on, keyed by CurrencyTypes ordinal.
## A producer absent from this reads as never claimed.
##
## Per producer rather than one shared day: all three are claimable every day,
## and claiming nutrients must not spend the water chip. The day the *track*
## steps on is still last_claim_day, which is the first of those claims.
##
## JSON has string keys, so this round-trips through them - see to_save().
var claim_days: Dictionary = {}

## The day a producer was last claimed on, 0 for one that never was.
func claim_day(currency: CurrencyTypes.Types) -> int:
	return int(claim_days.get(int(currency), 0))

func set_claim_day(currency: CurrencyTypes.Types, day: int) -> void:
	if claim_day(currency) == day:
		return
	claim_days[int(currency)] = day
	claim_day_changed.emit(int(currency))

## Single source of truth for which fields round-trip through a save file.
## Add a new field here, and nowhere else, to have it saved and loaded.
const _PLAIN_FIELDS: Array[String] = ["last_claim_day", "streak", "track_day",
	"track_claim_day"]

func to_save() -> Dictionary:
	var save_state := {}
	for field in _PLAIN_FIELDS:
		save_state[field] = get(field)
	var days := {}
	for currency: int in claim_days:
		days[str(currency)] = int(claim_days[currency])
	save_state["claim_days"] = days
	return save_state

## Applies a save dict onto this instance in place through each field's setter,
## so *_changed signals fire as usual. Use this rather than replacing
## App.daily_reward_data: ViewModels hold a reference, swapping the instance
## orphans them.
## A save written before the per-producer days existed carries none, which reads
## as every producer unclaimed. That hands a player who saved mid-day one extra
## claim each, once, which is the cheapest of the ways to be wrong here: the
## alternative is inventing which producer they had already spent the day on.
func load_from_save(d: Dictionary) -> void:
	for field in _PLAIN_FIELDS:
		set(field, d.get(field, 0))
	claim_days = {}
	var saved: Dictionary = d.get("claim_days", {})
	for key in saved:
		claim_days[int(str(key))] = int(saved[key])

static func from_save(d: Dictionary) -> DailyRewardData:
	var data := DailyRewardData.new()
	data.load_from_save(d)
	return data
