class_name MissionSystem
extends RefCounted
## MODEL: the mission board - what may be sent, how long an errand takes, and what
## bringing one home pays.
##
## Two boards, not one. An EXPEDITION is sent by hand, collected once ever, and
## pays both its currency and a permanent upgrade through the expedition reward
## track; finishing one is also what opens the farms that name it. A FARM is
## assigned a creature once and then loops on its own, paying per cycle and never
## needing another press. What limits them is the roster, not a board: a creature
## can only be on one thing at a time, so a creature tied to a farm is one the
## expeditions cannot have. Only the farms carry a further cap of their own,
## &"farm_slots" - a farm is left alone, so how many can be left alone at once is
## a thing to buy.
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
## now_provider. That holds for the farms too: settle_farms() derives whole
## cycles from two timestamps in O(1) rather than replaying them, so a farm left
## running for a day costs the same to settle as one left for a minute.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation.

## Farms running at once before any &"farm_slots" upgrade widens the board. One,
## so the first expedition that raises it is felt.
const BASE_FARM_SLOTS := 1

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
## The track expedition rewards are granted on. Never bought from, never saved:
## sync_expedition_rewards() projects RuinsData.completed_expeditions onto it.
var _expedition_upgrades: UpgradeSystem
var _missions: Array[MissionDef] = []
var _by_id: Dictionary = {}   # StringName -> MissionDef

func _init(data: RuinsData, player_data: PlayerData, biomes_data: BiomesData,
		production: ProductionSystem, creatures: CreatureSystem, list: MissionList,
		prestige_upgrades: UpgradeSystem = null,
		expedition_upgrades: UpgradeSystem = null) -> void:
	_data = data
	_player_data = player_data
	_biomes_data = biomes_data
	_production = production
	_creatures = creatures
	_prestige_upgrades = prestige_upgrades if prestige_upgrades != null else UpgradeSystem.new()
	_expedition_upgrades = expedition_upgrades if expedition_upgrades != null else UpgradeSystem.new()
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

## True once this expedition has been brought home. It never opens again - that
## is what one-shot means - and the reward it granted stays granted.
func is_completed(mission_id: StringName) -> bool:
	return _data.is_expedition_done(mission_id)

## Read off the run's own unlocked set rather than is_ever_unlocked, matching
## WaterSystem.is_pumping(): a run that has not bought the Ruins back cannot send
## anyone, however many times an earlier run walked them. What was already earned
## - the currencies, the roster, the tally - is untouched.
func is_controlling() -> bool:
	return _biomes_data.is_unlocked(RUINS_KEY)

## Expeditions in flight. Uncapped: what stops a player sending another is having
## nobody left to send, which is a limit they can already see on the roster and
## can lift by taking another creature over.
func expeditions_out() -> int:
	var count := 0
	for entry in _data.active:
		if not bool(entry["is_farm"]):
			count += 1
	return count

## Farms the player may have running at once.
func farm_slots() -> int:
	var bonus := 0
	if _production != null:
		bonus = _production.farm_slots()
	return maxi(1, BASE_FARM_SLOTS + bonus)

func farm_slots_used() -> int:
	var count := 0
	for entry in _data.active:
		if bool(entry["is_farm"]):
			count += 1
	return count

func has_free_farm_slot() -> bool:
	return farm_slots_used() < farm_slots()

## False while the board has not been worked enough - or the gating perk not
## bought, or the expedition it waits on not finished - to open this mission.
## Also false for an expedition already collected, which is what stops it being
## run a second time.
##
## Only blocks sending: a mission already in flight when a threshold moved still
## pays out.
func is_unlocked(mission_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return false
	if not def.is_farm and is_completed(mission_id):
		return false
	if _data.missions_completed < def.min_missions_completed:
		return false
	if not def.unlock_perk_id.is_empty() and _prestige_upgrades.level(def.unlock_perk_id) <= 0:
		return false
	if not def.requires_mission_id.is_empty() and not is_completed(def.requires_mission_id):
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

## Finished expeditions waiting on a press. Farms are excluded on purpose: one is
## never waiting, because settle_farms() has already paid it. Counting them would
## put a permanent badge on the nav row and a Collect all button that collects
## nothing.
func completed_count() -> int:
	var count := 0
	for entry in _data.active:
		if not bool(entry["is_farm"]) and is_complete(entry):
			count += 1
	return count

func has_collectable() -> bool:
	return completed_count() > 0

## The two boards, split out for the panel that draws them as separate sections.
func active_expeditions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _data.active:
		if not bool(entry["is_farm"]):
			out.append(entry)
	return out

func active_farms() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in _data.active:
		if bool(entry["is_farm"]):
			out.append(entry)
	return out

# ---------------------------------------------------------------- sending

func can_send(mission_id: StringName, creature_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or def.is_farm:
		return false
	# An expedition is collected once ever, so having two of the same one out at
	# once would pay its one-time reward twice. Only reachable since the board
	# stopped being capped - a second creature is now always allowed out, and this
	# is what stops it being sent after the same thing.
	if not _data.find_by_mission(mission_id).is_empty():
		return false
	return _can_run(def, creature_id)

## Sends a creature out, snapshotting the duration and the payouts onto the
## instance. Returns the instance id, or 0 when the send was refused.
func send(mission_id: StringName, creature_id: StringName) -> int:
	if not can_send(mission_id, creature_id):
		return 0
	return _data.add(mission_id, creature_id, _now(),
		duration_for(mission_id, creature_id),
		payouts_for(mission_id, creature_id))

# ---------------------------------------------------------------- farming

func can_start_farm(mission_id: StringName, creature_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or not def.is_farm or not has_free_farm_slot():
		return false
	return _can_run(def, creature_id)

## Puts a creature on a farm, snapshotting the cycle length and what one cycle
## pays exactly as send() does. Returns the instance id, or 0 when refused.
##
## Nothing else has to happen for it to start earning: the next settle_farms()
## reads the two timestamps and pays whatever has elapsed.
func start_farm(mission_id: StringName, creature_id: StringName) -> int:
	if not can_start_farm(mission_id, creature_id):
		return 0
	return _data.add(mission_id, creature_id, _now(),
		duration_for(mission_id, creature_id),
		payouts_for(mission_id, creature_id), true)

## Takes a creature off a farm, freeing it and the plot. Settles first, so
## stopping never costs the player a cycle already earned but not yet swept.
##
## The part-finished cycle is forfeited, which is the same deal the player
## already gets for cancelling anything: what is banked is what is whole.
func stop_farm(instance_id: int) -> bool:
	var entry := _data.find(instance_id)
	if entry.is_empty() or not bool(entry["is_farm"]):
		return false
	_settle_farm(entry, _now())
	return _data.remove(instance_id)

## Pays every whole cycle each running farm has turned since it was last swept,
## and reports how many were paid. The one call the idle board needs, from the
## tick and again on load.
##
## O(1) per farm however long the gap: whole cycles are divided out of the
## elapsed seconds rather than replayed, so a farm left running overnight settles
## as fast as one left for a minute. That is the same call MissionSystem already
## makes for a mission finishing while the game is closed - there is no catch-up
## loop here either.
func settle_farms() -> int:
	var now := _now()
	var cycles := 0
	for entry in _data.active:
		if not bool(entry["is_farm"]):
			continue
		cycles += _settle_farm(entry, now)
	if cycles > 0:
		_data.missions_completed += cycles
		sync_missions_completed()
		# The entries were mutated in place, which RuinsData cannot see.
		_data.active_changed.emit()
	return cycles

## One farm's share of the above. Returns the cycles paid.
func _settle_farm(entry: Dictionary, now: float) -> int:
	var duration := float(entry["duration"])
	if duration <= 0.0:
		return 0
	var elapsed := now - float(entry["started_at"])
	if elapsed <= 0.0:
		return 0
	# The same 24h ceiling the offline income screen collects against, for the
	# same reason: a farm is worth checking on, and a fortnight away must not pay
	# a fortnight's relics.
	var window := OfflineProgress.capped(elapsed)
	var cycles := int(floor(window / duration))
	if cycles <= 0:
		return 0
	for payout: Dictionary in entry["payouts"]:
		var amount := BigNumber.new(float(payout["m"]), int(payout["e"])).scale(float(cycles))
		_grant(int(payout["currency"]), amount)
	# Rewritten against now rather than advanced by the cycles paid. Advancing
	# would leave started_at still behind the cap on a long gap, and the next
	# sweep would pay the overflow this one just refused - the cap has to be
	# forfeited to mean anything. What is kept is the part-cycle in progress, so
	# a farm swept every tick never loses ground.
	entry["started_at"] = now - fmod(window, duration)
	return cycles

## How far through its current cycle a farm is, 0.0 to 1.0, for the card's bar.
## Unlike progress_ratio() this never reaches a finished state and stays there: a
## farm's bar wraps, because the farm does.
func farm_progress_ratio(entry: Dictionary) -> float:
	if entry.is_empty():
		return 0.0
	var duration := float(entry["duration"])
	if duration <= 0.0:
		return 0.0
	var elapsed := maxf(0.0, _now() - float(entry["started_at"]))
	return clampf(fmod(elapsed, duration) / duration, 0.0, 1.0)

# ---------------------------------------------------------------- selection

## What can carry this mission, shared by can_send() and can_start_farm(). The
## two differ only in which board they need a free place on.
func _can_run(def: MissionDef, creature_id: StringName) -> bool:
	if not is_controlling():
		return false
	if not is_unlocked(def.id):
		return false
	if _creatures == null:
		return false
	if not _creatures.is_recruited(creature_id) or _creatures.is_busy(creature_id):
		return false
	return _creatures.rank(creature_id) >= def.min_creature_rank

## The free creature this mission is best off with, or &"" when none can take it.
##
## Ranked on speed x yield, which is the whole of what a creature brings: both
## multipliers already fold the affinity bonus in, so a specialist wins here
## without affinity needing a rule of its own. Ties go to the earlier creature in
## the authored roster, which is the order the player already reads them in.
func best_creature_for(mission_id: StringName) -> StringName:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or _creatures == null:
		return &""
	var best := &""
	var best_score := 0.0
	for creature in _creatures.available_for(def):
		var score := _creatures.speed_multiplier(creature.id, mission_id) \
			* _creatures.yield_multiplier(creature.id, mission_id)
		if best.is_empty() or score > best_score:
			best = creature.id
			best_score = score
	return best

# ---------------------------------------------------------------- collecting

## Brings one finished expedition home: pays every snapshotted payout, grants the
## permanent reward, closes the expedition for good, and frees the creature and
## the slot. Refuses a mission still out, so a card left enabled by a stale
## refresh cannot be cashed early, and refuses a farm, which settle_farms() pays
## instead.
func collect(instance_id: int) -> bool:
	var entry := _data.find(instance_id)
	if entry.is_empty() or bool(entry["is_farm"]) or not is_complete(entry):
		return false
	for payout: Dictionary in entry["payouts"]:
		_grant(int(payout["currency"]), BigNumber.new(float(payout["m"]), int(payout["e"])))
	# Marked before the entry goes, so the id is still readable, and synced right
	# after: the reward has to be standing by the time the cards repaint on
	# active_changed, or the board shows a collected expedition paying nothing.
	_data.mark_expedition_done(entry["mission_id"])
	sync_expedition_rewards()
	_data.remove(instance_id)
	_data.missions_completed += 1
	sync_missions_completed()
	return true

## Collects every finished expedition and reports how many were brought home. The
## board's header button is the one caller.
func collect_all() -> int:
	var ready_ids: Array[int] = []
	for entry in _data.active:
		if not bool(entry["is_farm"]) and is_complete(entry):
			ready_ids.append(int(entry["instance_id"]))
	var collected := 0
	for instance_id in ready_ids:
		if collect(instance_id):
			collected += 1
	return collected

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
	var lifetime := CurrencyTypes.lifetime_field_for(type)
	if lifetime == &"": return
	var total: BigNumber = _player_data.get(lifetime)
	_player_data.set(lifetime, total.add(amount))

# ---------------------------------------------------------------- projection

## Rewrites PlayerData's cached copy of the tally, the Ruins' XP source. Called
## after every collection and again after a save load, the same way
## WellSystem.sync_project_levels() is.
func sync_missions_completed() -> void:
	_player_data.missions_completed = _data.missions_completed

## Rewrites the expedition reward track from the list of expeditions finished,
## the same way the line above rewrites PlayerData's copy of the tally. Called
## after every collect and again after a save load.
##
## A projection, not save data: RuinsData.completed_expeditions is the only
## record, so the track is never written to the save and the two can never
## disagree. It also means a reward whose effects were re-authored takes its new
## shape on the next load rather than being frozen at whatever was granted.
##
## Every registered def is written, not just the finished ones, so an expedition
## that somehow lost its place in the list loses its reward with it.
func sync_expedition_rewards() -> void:
	for def in _missions:
		if def == null or def.is_farm or def.rewards.is_empty():
			continue
		_expedition_upgrades.grant_level(def.id, 1 if is_completed(def.id) else 0)

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
	var clamped := false
	for entry in _data.active:
		if float(entry["started_at"]) <= now:
			continue
		push_warning("Mission %d started at %f, ahead of now (%f). Clamping to now."
			% [int(entry["instance_id"]), float(entry["started_at"]), now])
		entry["started_at"] = now
		clamped = true
	# The entries are mutated in place, which RuinsData cannot see. App calls this
	# after ruins_data.load_from_save() has already announced itself, so without
	# this every card would sit on the start time the clamp just replaced.
	if clamped:
		_data.active_changed.emit()
