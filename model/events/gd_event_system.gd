class_name EventSystem
extends RefCounted
## MODEL: the random-event queue - what may spawn, what an offer is currently
## worth, and what taking one pays.
##
## Deliberately wall-clock driven rather than tick driven, unlike the well's pump:
## an event is an interruption aimed at the player, so its cadence should be the
## one they experience, not one that stretches and shrinks with every &"tick_rate"
## upgrade. App owns the Timer; this owns how long to set it for.
##
## Equally deliberately, nothing here is driven by the offline catch-up. A night
## away would otherwise arrive as a full queue and several auto-completed progress
## quests, which is a reward for being absent - App gates both entry points on
## `events_running`, the same flag pattern automations already use.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## Offers on the board at once. A full queue simply skips a spawn rather than
## dropping the oldest: an offer the player has not answered is theirs to keep.
const MAX_QUEUE := 5

## Seconds between spawns, drawn uniformly. Randomised so the interruption does
## not land on a predictable metronome the player learns to pre-empt.
const MIN_INTERVAL := 45.0
const MAX_INTERVAL := 90.0

## Injectable for the same reason DailyRewardSystem.now_provider is: a test cannot
## wait out an interval or a coin flip, and a seeded generator is the only way to
## assert on which event spawned.
var rng := RandomNumberGenerator.new()

var _data: EventsData
var _player_data: PlayerData
var _biomes_data: BiomesData
var _fertilizer: FertilizerSystem
var _defs: Dictionary = {}      # StringName -> RandomEventDef
var _pool: Array[RandomEventDef] = []

func _init(data: EventsData, player_data: PlayerData, biomes_data: BiomesData,
		fertilizer: FertilizerSystem, list: RandomEventList) -> void:
	_data = data
	_player_data = player_data
	_biomes_data = biomes_data
	_fertilizer = fertilizer
	if list != null:
		for def in list.events:
			if def == null:
				continue
			_defs[def.id] = def
			_pool.append(def)

# ---------------------------------------------------------------- spawning

func next_interval() -> float:
	return rng.randf_range(MIN_INTERVAL, MAX_INTERVAL)

## Puts one event on the board, or reports false when it could not. Uniform over
## the eligible pool - a weighting field would be the first thing to add here, and
## deliberately is not there yet.
func try_spawn() -> bool:
	if _data.count() >= MAX_QUEUE:
		return false
	var eligible := _eligible()
	if eligible.is_empty():
		return false
	var def := eligible[rng.randi_range(0, eligible.size() - 1)]
	_data.add(def.id, _roll_fertilizer(def))
	return true

## The defs whose biome gate is open. Read off the run's own unlocked set rather
## than is_ever_unlocked, matching WaterSystem.is_pumping(): an offer of crystals
## has nothing to give a run that has not bought the caves back.
func _eligible() -> Array[RandomEventDef]:
	var eligible: Array[RandomEventDef] = []
	for def in _pool:
		if def.requires_biome.is_empty() or _biomes_data.is_unlocked(def.requires_biome):
			eligible.append(def)
	return eligible

func _roll_fertilizer(def: RandomEventDef) -> int:
	var low := int(def.fertilizer_min)
	var high := int(def.fertilizer_max)
	if high <= low:
		return low
	return rng.randi_range(low, high)

# ---------------------------------------------------------------- reading

func events() -> Array[Dictionary]:
	return _data.events

func def_for(def_id: StringName) -> RandomEventDef:
	return _defs.get(def_id)

## What a BOON pays, or what a SPEND asks for, against the balance as it stands
## right now: max(min_amount, pct_of_balance * balance + flat_amount). The floor
## is what keeps an offer worth answering at the start of a run, where a
## percentage of nothing is nothing.
func amount_for(def: RandomEventDef) -> BigNumber:
	if def == null or def.currency == null:
		return BigNumber.new(0.0, 0)
	var field := CurrencyTypes.field_for(def.currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	var scaled := balance.scale(def.pct_of_balance).add(BigNumber.from_value(def.flat_amount))
	var floor_value := BigNumber.from_value(def.min_amount)
	if scaled.lt(floor_value):
		return floor_value
	return scaled

## The fertilizer this instance pays, as rolled when it spawned.
func reward_for(event: Dictionary) -> BigNumber:
	return BigNumber.from_value(float(int(event.get("roll", 0))))

func can_fulfil(event: Dictionary) -> bool:
	var def := def_for(event.get("def_id", &""))
	if def == null or def.kind != RandomEventDef.Kind.SPEND:
		return false
	# RandomEventDef documents currency as nullable, and nothing pins it down for
	# a SPEND. One mis-authored .tres would otherwise crash on the card's first
	# tap rather than leaving the button dead. fulfil() runs this before it reads
	# the currency itself, so this is the only place the check is needed.
	if def.currency == null:
		push_error("SPEND event '%s' names no currency, so it cannot be fulfilled." % def.id)
		return false
	var field := CurrencyTypes.field_for(def.currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	return balance.gte(amount_for(def))

# ---------------------------------------------------------------- answering

## Takes a BOON: pays it out and clears the card.
func collect(instance_id: int) -> bool:
	var event := _data.find(instance_id)
	if event.is_empty():
		return false
	var def := def_for(event["def_id"])
	if def == null or def.kind != RandomEventDef.Kind.BOON:
		return false
	if def.pays_fertilizer():
		_fertilizer.grant(reward_for(event))
	elif def.currency != null:
		_pay(def.currency, amount_for(def))
	else:
		# A BOON that pays neither fertilizer nor a currency pays nothing. Clear
		# the card anyway rather than leaving one that can never be answered.
		push_error("BOON event '%s' pays neither fertilizer nor a currency." % def.id)
	_data.remove(instance_id)
	_player_data.events_resolved += 1
	return true

## Takes a SPEND quest: charges the resource and pays the fertilizer. Refuses and
## mutates nothing when the balance is short, so a card left enabled by a stale
## refresh cannot overdraw.
func fulfil(instance_id: int) -> bool:
	var event := _data.find(instance_id)
	if event.is_empty():
		return false
	if not can_fulfil(event):
		return false
	var def := def_for(event["def_id"])
	var field := CurrencyTypes.field_for(def.currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.sub(amount_for(def)))
	_fertilizer.grant(reward_for(event))
	_data.remove(instance_id)
	_player_data.events_resolved += 1
	return true

## Dismisses an offer unanswered. Does not count towards events_resolved - the
## ladder measures offers taken, not offers seen.
func skip(instance_id: int) -> bool:
	return _data.remove(instance_id)

## One live tick of progress for every PROGRESS event, paying out the ones that
## reach their goal.
##
## Deliberately not the (before, count) shape WaterSystem uses. That shape exists
## so a strided span pays what walking it would; here the opposite is wanted -
## progress must not accrue at all while the player is away, so this is only ever
## called one live tick at a time.
func handle_tick() -> void:
	var completed := _data.advance_progress(_goal_for)
	for instance_id in completed:
		var event := _data.find(instance_id)
		if event.is_empty():
			continue
		_fertilizer.grant(reward_for(event))
		_data.remove(instance_id)
		_player_data.events_resolved += 1

func _goal_for(def_id: StringName) -> int:
	var def := def_for(def_id)
	if def == null or def.kind != RandomEventDef.Kind.PROGRESS:
		return 0
	return def.goal_ticks

## Pays one currency out, moving its lifetime total with it.
##
## Which currencies have a lifetime counter is CurrencyTypes' answer, not a match
## written out here: this used to name nutrients and crystals only, so a BOON
## authored on relics, ichor or glyphs would have moved the balance and left the
## stat the achievement ladder reads standing still. Mirrors MissionSystem._grant().
func _pay(currency: CurrencyDef, amount: BigNumber) -> void:
	var field := CurrencyTypes.field_for(currency.currency_type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.add(amount))
	var lifetime := CurrencyTypes.lifetime_field_for(currency.currency_type)
	if lifetime == &"": return
	var total: BigNumber = _player_data.get(lifetime)
	_player_data.set(lifetime, total.add(amount))
