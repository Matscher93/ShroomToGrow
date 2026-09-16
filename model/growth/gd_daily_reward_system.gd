class_name DailyRewardSystem
extends RefCounted
## MODEL: one claim per producer per local calendar day, each granting that
## producer a permanent stack.
##
## Every producer rather than a choice between them: the chips were a pick-one,
## which made the daily a small decision taken in a second and then a closed
## sheet.
##
## Knows nothing about the fourteen-day track that sits under it in the same
## sheet. That is claimed on its own day by its own press - see DailyTrackSystem.
##
## Claim-driven, not accrual-driven: nothing ticks, nothing banks up, and a
## missed day is simply a day not claimed. That is deliberate - stacking missed
## days would turn a week away into a burst of free multipliers, which is the
## opposite of a reason to come back tomorrow.
##
## Holds no App reference, so it can be built and exercised in isolation.

## Wall clock and local offset, injectable for the same reason
## SaveManager.now_provider is: a day boundary has to be crossable in a test
## without sleeping through one.
##
## Its own pair rather than SaveManager's, on purpose. A Callable captured at
## construction goes stale the moment a test swaps the one on SaveManager, and
## reading SaveManager directly would put an autoload reference inside a model.
var now_provider: Callable = func() -> float: return Time.get_unix_time_from_system()
var tz_bias_provider: Callable = func() -> int:
	var zone := Time.get_time_zone_from_system()
	return int(zone.get("bias", 0))

var _data: DailyRewardData
var _upgrades: UpgradeSystem
var _producers: Array[GrowthProducerDef] = []

func _init(data: DailyRewardData, upgrades: UpgradeSystem, list: GrowthProducerList) -> void:
	_data = data
	_upgrades = upgrades
	if list != null:
		_producers = list.producers

# ---------------------------------------------------------------- clock

func today() -> int:
	return DailyCalendar.day_index(float(now_provider.call()), int(tz_bias_provider.call()))

## Whether anything is left to claim today - any producer whose own day has not
## caught up with this one. This is what lights the notification dot, so it has to
## stay true while two of the three chips are still unpressed.
func can_claim() -> bool:
	var current := today()
	for producer in _producers:
		if producer == null or producer.currency == null:
			continue
		if current > _data.claim_day(producer.currency.currency_type):
			return true
	return false

func streak() -> int:
	return _data.streak

## Seconds from now to the next local midnight, which is when the next claim
## opens.
##
## Exposed for the balance simulator: its stride skips idle ticks in bulk, and it
## has to stop on the tick the day rolls over exactly as it stops on the tick a
## well project becomes fundable. A countdown in the sheet would read the same
## number.
func seconds_until_next_day() -> float:
	var local := float(now_provider.call()) + float(int(tz_bias_provider.call())) * 60.0
	return DailyCalendar.SECONDS_PER_DAY - fposmod(local, DailyCalendar.SECONDS_PER_DAY)

# ---------------------------------------------------------------- claiming

## Daily stacks bought into one producer so far.
func stacks(currency: CurrencyTypes.Types) -> int:
	return _upgrades.level(GrowthTree.daily_id(currency))

## Per producer, against that producer's own last claim day. A chip pressed today
## goes quiet until tomorrow; its neighbours do not.
func can_claim_into(currency: CurrencyTypes.Types) -> bool:
	if today() <= _data.claim_day(currency):
		return false
	return _upgrades.has_def(GrowthTree.daily_id(currency))

## Claims one producer's stack for today. The stack is permanent; that producer
## is not claimable again until the local day rolls over, and its neighbours are
## untouched.
##
## The first claim of the day also takes the day itself, adding the streak and
## stamping the day; the two claims after it do neither.
func claim(currency: CurrencyTypes.Types) -> bool:
	if not can_claim_into(currency):
		return false
	if not _upgrades.buy_with_points(GrowthTree.daily_id(currency), true):
		return false
	var current := today()
	_data.set_claim_day(currency, current)
	if current > _data.last_claim_day:
		_data.last_claim_day = current
		_data.streak += 1
	return true

## Pulls a last-claim day that sits in the future back to today, after a save
## load.
##
## Only reachable by the device clock moving backwards - set forward, claimed,
## set back. Without this the player is locked out until real time catches up to
## wherever the clock had been, which can be years. With it they wait for the
## next real day like everyone else.
##
## A fairness guard, not anti-cheat: a clock set forward still yields an early
## claim, exactly as the offline catch-up is already exposed to one and caps it
## at OfflineProgress.MAX_SECONDS rather than trying to detect it.
func sync_clock_rollback() -> void:
	var current := today()
	# The per-producer days are clamped too, or the chip stays dead until real
	# time catches up even once the shared day has been pulled back.
	for currency: int in _data.claim_days.keys():
		if int(_data.claim_days[currency]) > current:
			_data.set_claim_day(currency, current)
	if _data.last_claim_day <= current:
		return
	push_warning("Daily reward was last claimed on day %d, ahead of today (%d). Clamping to today."
		% [_data.last_claim_day, current])
	_data.last_claim_day = current
