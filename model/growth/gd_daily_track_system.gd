class_name DailyTrackSystem
extends RefCounted
## MODEL: the fourteen-day reward track that rides along with the daily claim.
##
## One slot per day, paid in order, each worth more than the last. Claimed on its
## own: pressing today's slot takes it, and the producer chips above are a
## separate daily with a separate day of their own. A player who only presses the
## chips leaves the step waiting, and vice versa.
##
## A missed day resets the track to day one. That is the whole point of it: the
## producer stacks are a record of turning up ever, deliberately unbreakable, and
## this is the part that asks for tomorrow specifically. The two live on the same
## DailyRewardData because they are driven by the same claim.
##
## Holds no clock of its own. Every method takes today's day index from the
## caller, which is what makes a day boundary testable without waiting for one -
## and what stops the sheet and the claim reading two different "today"s.

var _data: DailyRewardData
var _player_data: PlayerData
var _biomes_data: BiomesData
var _homes: CurrencyHomes
var _slots: Array[DailyTrackSlotDef] = []

func _init(data: DailyRewardData, player_data: PlayerData, list: DailyTrackList,
		homes: CurrencyHomes = null, biomes_data: BiomesData = null) -> void:
	_data = data
	_player_data = player_data
	_biomes_data = biomes_data
	_homes = homes if homes != null else CurrencyHomes.new()
	if list != null:
		_slots = list.slots

func count() -> int:
	return _slots.size()

func slots() -> Array[DailyTrackSlotDef]:
	return _slots

func slot(day: int) -> DailyTrackSlotDef:
	if day < 1 or day > _slots.size():
		return null
	return _slots[day - 1]

# ---------------------------------------------------------------- the pass

## Slots already claimed in the pass that is still running, 0 when the track has
## been broken or finished.
##
## Read off the last step's day rather than stored, so a track broken by a missed
## day reads as broken the moment that day passes - the player opens the sheet on
## Wednesday and sees day one waiting, without anything having run on Tuesday to
## notice. Nothing ticks here and nothing has to.
func claimed_days(today: int) -> int:
	if _data.track_claim_day == today:
		return _data.track_day
	# Yesterday's step keeps the pass alive, unless it was the last slot: a
	# finished track starts over rather than sitting complete forever.
	if _data.track_claim_day == today - 1 and _data.track_day < count():
		return _data.track_day
	return 0

## The day today's claim would pay, or 0 when today's claim is already spent.
func pending_day(today: int) -> int:
	if _data.track_claim_day >= today:
		return 0
	if count() == 0:
		return 0
	return claimed_days(today) + 1

## Whether the track is sitting on its last slot, for a sheet that wants to say
## so before the player spends the claim.
func is_final_day(today: int) -> bool:
	return pending_day(today) == count()

# ---------------------------------------------------------------- payout

## What a slot is worth right now: max(min_amount, pct_of_balance * balance +
## flat_amount), off the balance of the currency it actually pays.
func amount_for(day: int) -> BigNumber:
	var def := slot(day)
	if def == null:
		return BigNumber.from_value(0.0)
	var currency := currency_for(day)
	var balance: BigNumber = _player_data.get(CurrencyTypes.field_for(currency))
	var scaled := balance.scale(def.pct_of_balance).add(BigNumber.from_value(def.flat_amount))
	var floor_value := BigNumber.from_value(def.min_amount)
	if scaled.lt(floor_value):
		return floor_value
	return scaled.floored()

## The currency a slot pays, after the unlock gate.
##
## An authored slot names the resource the day is *about*, and the later days
## name the later resources - which a player two days into the game has no screen
## for. Rather than skip the day or pay something they cannot see, it pays the
## deepest resource they have reached. The track is the same fourteen days for
## everyone; only what it hands over moves with them.
func currency_for(day: int) -> CurrencyTypes.Types:
	var def := slot(day)
	if def == null or def.currency == null:
		return CurrencyTypes.Types.NUTRIENTS
	var authored := def.currency.currency_type
	if _homes.is_reachable(authored, _biomes_data):
		return authored
	return _homes.deepest_reachable(_biomes_data)

# ---------------------------------------------------------------- claiming

## Pays today's slot and moves the track on. The day is worked out before either
## field is written: every rule above is written against the previous step, so
## stamping first would read the pass as already continued and skip a slot.
##
## Returns the day paid, or 0 when there was nothing to pay.
func claim(today: int) -> int:
	var day := pending_day(today)
	if day == 0:
		return 0
	_pay(currency_for(day), amount_for(day))
	_data.track_day = day
	_data.track_claim_day = today
	return day

## Same two writes EventSystem._pay() makes, for the same reason: a payout that
## moves a balance without moving its lifetime counter is a payout the
## achievement ladder never sees.
func _pay(currency: CurrencyTypes.Types, amount: BigNumber) -> void:
	var field := CurrencyTypes.field_for(currency)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.add(amount))
	var lifetime := CurrencyTypes.lifetime_field_for(currency)
	if lifetime == &"":
		return
	var total: BigNumber = _player_data.get(lifetime)
	_player_data.set(lifetime, total.add(amount))
