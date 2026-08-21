class_name DailyRewardSystem
extends RefCounted
## MODEL: one claim per local calendar day, granting a permanent stack to one
## producer of the player's choosing.
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

func can_claim() -> bool:
	return today() > _data.last_claim_day

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

func can_claim_into(currency: CurrencyTypes.Types) -> bool:
	return can_claim() and _upgrades.has_def(GrowthTree.daily_id(currency))

## Spends today's claim on one producer. The stack is permanent; the claim is
## not repeatable until the local day rolls over.
func claim(currency: CurrencyTypes.Types) -> bool:
	if not can_claim_into(currency):
		return false
	if not _upgrades.buy_with_points(GrowthTree.daily_id(currency), true):
		return false
	_data.last_claim_day = today()
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
	if _data.last_claim_day <= current:
		return
	push_warning("Daily reward was last claimed on day %d, ahead of today (%d). Clamping to today."
		% [_data.last_claim_day, current])
	_data.last_claim_day = current
