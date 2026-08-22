class_name MissionSystem
extends RefCounted
## MODEL: the mission board - what may be sent, how long an errand takes, and what
## bringing one home pays.
##
## Deliberately wall-clock driven rather than tick driven, and deliberately the
## opposite call to the one EventSystem makes. An event is an interruption aimed
## at the player, so it must not accrue while they are away; a mission is an
## errand they set going before they left, so it must. Completion is derived -
## `now >= started_at + duration` - which means offline progress costs nothing:
## there is no catch-up loop, nothing to replay, and no (before, count) shape to
## keep in step with TickSystem.
##
## Nothing here is driven from the tick loop at all. The only clock is
## now_provider.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## Missions in flight at once before any &"mission_slots" upgrade widens the
## board. One, so the first perk that raises it is felt.
const BASE_SLOTS := 1

## The biome whose unlock opens Parasitic Control. Its screen is the Ruins.
const RUINS_KEY := &"ruins"

## Wall clock, injectable for the same reason DailyRewardSystem.now_provider is: a
## test cannot wait out a duration, and a mission that finishes in a minute would
## otherwise take a minute to assert on.
##
## Its own Callable rather than SaveManager's, on purpose. One captured at
## construction goes stale the moment a test swaps the one on SaveManager, and
## reading SaveManager directly would put an autoload reference inside a model.
var now_provider: Callable = func() -> float: return Time.get_unix_time_from_system()

var _data: RuinsData
var _player_data: PlayerData
var _biomes_data: BiomesData
var _production: ProductionSystem
var _creatures: CreatureSystem
var _prestige_upgrades: UpgradeSystem
var _missions: Array[MissionDef] = []
var _by_id: Dictionary = {}   # StringName -> MissionDef

func _init(data: RuinsData, player_data: PlayerData, biomes_data: BiomesData,
		production: ProductionSystem, creatures: CreatureSystem, list: MissionList,
		prestige_upgrades: UpgradeSystem = null) -> void:
	_data = data
	_player_data = player_data
	_biomes_data = biomes_data
	_production = production
	_creatures = creatures
	_prestige_upgrades = prestige_upgrades if prestige_upgrades != null else UpgradeSystem.new()
	if list != null:
		_missions = list.missions
	for mission in _missions:
		if mission == null:
			push_error("MissionList holds a null entry, skipping it.")
			continue
		_by_id[mission.id] = mission

func _now() -> float:
	return float(now_provider.call())

# ---------------------------------------------------------------- lookup

func missions() -> Array[MissionDef]:
	return _missions

func mission_def(mission_id: StringName) -> MissionDef:
	return _by_id.get(mission_id)

## Read off the run's own unlocked set rather than is_ever_unlocked, matching
## WaterSystem.is_pumping(): a run that has not bought the Ruins back cannot send
## anyone, however many times an earlier run walked them. What was already earned
## - the currencies, the roster, the tally - is untouched.
func is_controlling() -> bool:
	return _biomes_data.is_unlocked(RUINS_KEY)

## Missions the player may have in flight at once.
func slots() -> int:
	var bonus := 0
	if _production != null:
		bonus = _production.mission_slots()
	return maxi(1, BASE_SLOTS + bonus)

func slots_used() -> int:
	return _data.count()

func has_free_slot() -> bool:
	return slots_used() < slots()

## False while the board has not been worked enough - or the gating perk not
## bought - to open this mission. Only blocks sending: a mission already in flight
## when a threshold moved still pays out.
func is_unlocked(mission_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return false
	if _data.missions_completed < def.min_missions_completed:
		return false
	if not def.unlock_perk_id.is_empty() and _prestige_upgrades.level(def.unlock_perk_id) <= 0:
		return false
	return true

## Missions still owed before this one opens. Zero once it has. Says nothing about
## the perk gate, which is not a countdown.
func missions_until_unlock(mission_id: StringName) -> int:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return 0
	return maxi(0, def.min_missions_completed - _data.missions_completed)

# ---------------------------------------------------------------- rates

## Seconds this mission would take if it were sent right now with this creature.
## What a running mission has left comes from its own snapshot instead - see
## seconds_remaining().
func duration_for(mission_id: StringName, creature_id: StringName) -> float:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return 0.0
	var speed := 1.0
	if _production != null:
		speed = _production.mission_speed()
	if _creatures != null:
		speed *= _creatures.speed_multiplier(creature_id, mission_id)
	return maxf(1.0, def.base_duration_seconds / maxf(0.01, speed))

## What this mission would pay if it were sent right now with this creature, as
## the save-shaped payout rows RuinsData stores: {currency, m, e}.
##
## Resolved here rather than at collect time because the value is snapshotted onto
## the instance - the card shows what it will pay, and it pays what it showed.
func payouts_for(mission_id: StringName, creature_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return out
	var creature_bonus := 1.0
	if _creatures != null:
		creature_bonus = _creatures.yield_multiplier(creature_id, mission_id)
	for payout in def.payouts:
		if payout == null or payout.currency == null:
			push_error("MissionDef '%s' has a payout with no currency, skipping it." % def.id)
			continue
		var amount := payout.amount.scale(creature_bonus)
		if _production != null:
			amount = _production.modify_mission_reward(amount, payout.gain_stat)
		out.append({
			"currency": int(payout.currency.currency_type),
			"m": amount.mantissa,
			"e": amount.exponent,
		})
	return out

# ---------------------------------------------------------------- the board

func active() -> Array[Dictionary]:
	return _data.active

func seconds_remaining(entry: Dictionary) -> float:
	if entry.is_empty():
		return 0.0
	var ends_at := float(entry["started_at"]) + float(entry["duration"])
	return maxf(0.0, ends_at - _now())

## How far through its errand a mission is, 0.0 to 1.0, for the card's bar.
func progress_ratio(entry: Dictionary) -> float:
	if entry.is_empty():
		return 0.0
	var duration := float(entry["duration"])
	if duration <= 0.0:
		return 1.0
	return clampf((duration - seconds_remaining(entry)) / duration, 0.0, 1.0)

func is_complete(entry: Dictionary) -> bool:
	return not entry.is_empty() and seconds_remaining(entry) <= 0.0

func completed_count() -> int:
	var count := 0
	for entry in _data.active:
		if is_complete(entry):
			count += 1
	return count

func has_collectable() -> bool:
	return completed_count() > 0

# ---------------------------------------------------------------- sending

func can_send(mission_id: StringName, creature_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or not is_controlling() or not has_free_slot():
		return false
	if not is_unlocked(mission_id):
		return false
	if _creatures == null:
		return false
	if not _creatures.is_recruited(creature_id) or _creatures.is_busy(creature_id):
		return false
	return _creatures.rank(creature_id) >= def.min_creature_rank

## Sends a creature out, snapshotting the duration and the payouts onto the
## instance. Returns the instance id, or 0 when the send was refused.
func send(mission_id: StringName, creature_id: StringName) -> int:
	if not can_send(mission_id, creature_id):
		return 0
	return _data.add(mission_id, creature_id, _now(),
		duration_for(mission_id, creature_id),
		payouts_for(mission_id, creature_id))

# ---------------------------------------------------------------- collecting

## Brings one finished mission home: pays every snapshotted payout, frees the
## creature and the slot, and counts the mission. Refuses a mission still out, so
## a card left enabled by a stale refresh cannot be cashed early.
func collect(instance_id: int) -> bool:
	var entry := _data.find(instance_id)
	if entry.is_empty() or not is_complete(entry):
		return false
	for payout: Dictionary in entry["payouts"]:
		_grant(int(payout["currency"]), BigNumber.new(float(payout["m"]), int(payout["e"])))
	_data.remove(instance_id)
	_data.missions_completed += 1
	sync_missions_completed()
	return true

## Collects every finished mission and reports how many were brought home. The
## board's header button is the one caller.
func collect_all() -> int:
	var ready_ids: Array[int] = []
	for entry in _data.active:
		if is_complete(entry):
			ready_ids.append(int(entry["instance_id"]))
	var collected := 0
	for instance_id in ready_ids:
		if collect(instance_id):
			collected += 1
	return collected

## The currencies whose lifetime total moves when a mission pays them out. Water
## and biomass are deliberately absent: neither has a lifetime counter, because
## nothing measures them across runs.
const _LIFETIME_FIELDS := {
	CurrencyTypes.Types.NUTRIENTS: &"lifetime_nutrients",
	CurrencyTypes.Types.CRYSTALS: &"lifetime_crystals",
	CurrencyTypes.Types.RELICS: &"lifetime_relics",
	CurrencyTypes.Types.ICHOR: &"lifetime_ichor",
	CurrencyTypes.Types.GLYPHS: &"lifetime_glyphs",
}

## Pays one currency out, moving its lifetime total with it. The one entry point:
## nothing writes a balance directly, so no payout can reach the player without
## also reaching the stat that measures it. Mirrors FertilizerSystem.grant().
func _grant(currency: int, amount: BigNumber) -> void:
	if amount == null or amount.mantissa <= 0.0:
		return
	var type := currency as CurrencyTypes.Types
	var field := CurrencyTypes.field_for(type)
	var balance: BigNumber = _player_data.get(field)
	_player_data.set(field, balance.add(amount))
	if not _LIFETIME_FIELDS.has(type):
		return
	var lifetime: StringName = _LIFETIME_FIELDS[type]
	var total: BigNumber = _player_data.get(lifetime)
	_player_data.set(lifetime, total.add(amount))

# ---------------------------------------------------------------- projection

## Rewrites PlayerData's cached copy of the tally, the Ruins' XP source. Called
## after every collection and again after a save load, the same way
## WellSystem.sync_project_levels() is.
func sync_missions_completed() -> void:
	_player_data.missions_completed = _data.missions_completed

## Pulls any mission whose start sits in the future back to now, after a save
## load.
##
## Only reachable by the device clock moving backwards - set forward, sent, set
## back. Without this the creature is stuck until real time catches up to wherever
## the clock had been, which can be years. With it the errand runs its authored
## length from now.
##
## A fairness guard, not anti-cheat: a clock set forward still finishes a mission
## early, exactly as the offline catch-up is already exposed to one.
func sync_clock_rollback() -> void:
	var now := _now()
	for entry in _data.active:
		if float(entry["started_at"]) <= now:
			continue
		push_warning("Mission %d started at %f, ahead of now (%f). Clamping to now."
			% [int(entry["instance_id"]), float(entry["started_at"]), now])
		entry["started_at"] = now
