class_name MissionSystem
extends RefCounted
## MODEL: the mission board - what may be sent, how long an errand takes, and what
## bringing one home pays.
##
## Two boards run by two different halves of the roster.
##
## An EXPEDITION belongs to a CHAIN - twenty of them per hero, walked in the order
## they are authored - and is run by that chain's hero and nobody else. It is
## collected once ever and pays both its currency and a permanent upgrade through
## the expedition reward track; finishing one is also what opens the farms that
## name it. Every fifth step asks the hero for one more level than the block
## before it, so a chain is walked by levelling its hero as much as by running it.
##
## A FARM is worked by a pool of workers and loops on its own, paying per cycle
## and never needing another press. More workers divide its cycle. Farms are
## capped by &"farm_slots" - a farm is left alone, so how many can be left alone
## at once is a thing to buy - and each one is capped again by how many workers it
## will hold.
##
## The two halves never compete: a hero cannot work a farm and a worker cannot run
## an expedition.
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
var _heroes: HeroSystem
var _prestige_upgrades: UpgradeSystem
## The worker pool, for the two questions the farms ask of it: how many are free,
## and how many this farm will hold.
var _workers: WorkerSystem
## The track expedition rewards are granted on. Never bought from, never saved:
## sync_expedition_rewards() projects RuinsData.completed_expeditions onto it.
var _expedition_upgrades: UpgradeSystem
var _missions: Array[MissionDef] = []
var _by_id: Dictionary = {}   # StringName -> MissionDef
## StringName hero id -> Array[MissionDef], in authored order. Built once here
## rather than filtered on every read: a chain is walked step by step, so this is
## asked for on every repaint of every card on the screen.
var _chains: Dictionary = {}

func _init(data: RuinsData, player_data: PlayerData, biomes_data: BiomesData,
		production: ProductionSystem, heroes: HeroSystem, list: MissionList,
		prestige_upgrades: UpgradeSystem = null,
		expedition_upgrades: UpgradeSystem = null,
		workers: WorkerSystem = null) -> void:
	_data = data
	_player_data = player_data
	_biomes_data = biomes_data
	_production = production
	_heroes = heroes
	_prestige_upgrades = prestige_upgrades if prestige_upgrades != null else UpgradeSystem.new()
	_expedition_upgrades = expedition_upgrades if expedition_upgrades != null else UpgradeSystem.new()
	_workers = workers
	if list != null:
		_missions = list.missions
	for mission in _missions:
		if mission == null:
			push_error("MissionList holds a null entry, skipping it.")
			continue
		_by_id[mission.id] = mission
		if mission.is_farm:
			continue
		if mission.hero_id.is_empty():
			push_error("Expedition '%s' names no hero, so it belongs to no chain." % mission.id)
			continue
		if not _chains.has(mission.hero_id):
			_chains[mission.hero_id] = [] as Array[MissionDef]
		_chains[mission.hero_id].append(mission)

func _now() -> float:
	return float(now_provider.call())

# ---------------------------------------------------------------- lookup

func missions() -> Array[MissionDef]:
	return _missions

func mission_def(mission_id: StringName) -> MissionDef:
	return _by_id.get(mission_id)

## One hero's expeditions, in the order they are authored - which is the order
## they are walked in. Built once at construction: the mission list is a static
## registry, so a chain cannot change while the game is running.
func chain(hero_id: StringName) -> Array[MissionDef]:
	var out: Array[MissionDef] = _chains.get(hero_id, [])
	return out

func chain_length(hero_id: StringName) -> int:
	return chain(hero_id).size()

## How far along its chain this hero has walked - the number of its expeditions
## already brought home. Also the index of the step it would run next, since a
## chain is walked in order and cannot be walked out of it.
func chain_position(hero_id: StringName) -> int:
	var walked := 0
	for def in chain(hero_id):
		if not is_completed(def.id):
			break
		walked += 1
	return walked

## The one expedition this hero could run next, or null at the end of its chain.
## There is never a choice: the chain says which, and the hero says whose.
func next_step(hero_id: StringName) -> MissionDef:
	var steps := chain(hero_id)
	var at := chain_position(hero_id)
	return steps[at] if at < steps.size() else null

## Where this expedition sits in its own chain, counting from zero, or -1 for a
## farm or an unknown id.
func chain_index(mission_id: StringName) -> int:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or def.is_farm:
		return -1
	return chain(def.hero_id).find(def)

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
## can lift by taking another hero over.
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
	if not def.unlock_perk_id.is_empty() and _prestige_upgrades.level(def.unlock_perk_id) <= 0:
		return false
	if def.is_farm:
		if _data.missions_completed < def.min_missions_completed:
			return false
		return def.requires_mission_id.is_empty() or is_completed(def.requires_mission_id)
	# An expedition's ladder is its own chain and nothing else: it opens when
	# every step before it is home, and only for a hero levelled far enough to
	# take it.
	if is_completed(mission_id):
		return false
	if chain_index(mission_id) != chain_position(def.hero_id):
		return false
	if _heroes == null or not _heroes.is_recruited(def.hero_id):
		return false
	return _heroes.level(def.hero_id) >= def.min_hero_level

## Missions still owed before this one opens. Zero once it has. Says nothing about
## the perk gate, which is not a countdown.
func missions_until_unlock(mission_id: StringName) -> int:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return 0
	return maxi(0, def.min_missions_completed - _data.missions_completed)

## The level this expedition's hero still has to reach, or 0 once it has. Says
## nothing about the steps before it, which is the other half of a chain gate.
func levels_until_unlock(mission_id: StringName) -> int:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or def.is_farm or _heroes == null:
		return 0
	return maxi(0, def.min_hero_level - _heroes.level(def.hero_id))

# ---------------------------------------------------------------- rates

## Seconds this mission would take if it were sent right now with this hero.
## What a running mission has left comes from its own snapshot instead - see
## seconds_remaining().
## Seconds this mission would take if it were started right now - by this hero on
## an expedition, or by this many workers on a farm. What a running mission has
## left comes from its own snapshot instead - see seconds_remaining().
##
## The two halves of the roster divide the clock the same way: a level-3 hero and
## three workers are both a x3 on their own board.
func duration_for(mission_id: StringName, hero_id: StringName, workers: int = 0) -> float:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return 0.0
	var speed := 1.0
	if _production != null:
		speed = _production.mission_speed(mission_id)
	if def.is_farm:
		speed *= float(maxi(1, workers))
	elif _heroes != null:
		speed *= _heroes.speed_multiplier(hero_id)
	return maxf(1.0, def.base_duration_seconds / maxf(0.01, speed))

## What this mission would pay if it were sent right now with this hero, as
## the save-shaped payout rows RuinsData stores: {currency, m, e}.
##
## Resolved here rather than at collect time because the value is snapshotted onto
## the instance - the card shows what it will pay, and it pays what it showed.
func payouts_for(mission_id: StringName, hero_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: MissionDef = _by_id.get(mission_id)
	if def == null:
		return out
	# A farm pays its authored rate per cycle however many workers turn it: the
	# workers are already paid for in cycles, and paying them twice would make
	# stacking one farm strictly better than running two.
	var hero_bonus := 1.0
	if not def.is_farm and _heroes != null:
		hero_bonus = _heroes.yield_multiplier(hero_id)
	for payout in def.payouts:
		if payout == null or payout.currency == null:
			push_error("MissionDef '%s' has a payout with no currency, skipping it." % def.id)
			continue
		var amount := payout.amount.scale(hero_bonus)
		if _production != null:
			amount = _production.modify_mission_reward(amount, payout.gain_stat, mission_id)
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

func can_send(mission_id: StringName, hero_id: StringName) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or def.is_farm:
		return false
	# Only the chain's own hero. Nothing on screen offers another, but the model
	# is what makes that true rather than the screen.
	if def.hero_id != hero_id:
		return false
	# An expedition is collected once ever, so having two of the same one out at
	# once would pay its one-time reward twice.
	if not _data.find_by_mission(mission_id).is_empty():
		return false
	return _can_run(def, hero_id)

## The expedition this hero would be sent on, or &"" when it has none to run -
## its chain is finished, it is already out, or the next step wants a level it
## has not reached. One command's worth of decision, made in the model.
func sendable_step(hero_id: StringName) -> StringName:
	if _heroes == null or not _heroes.is_available(hero_id):
		return &""
	var step := next_step(hero_id)
	if step == null or not can_send(step.id, hero_id):
		return &""
	return step.id

## Sends a hero out, snapshotting the duration and the payouts onto the
## instance. Returns the instance id, or 0 when the send was refused.
func send(mission_id: StringName, hero_id: StringName) -> int:
	if not can_send(mission_id, hero_id):
		return 0
	return _data.add(mission_id, hero_id, _now(),
		duration_for(mission_id, hero_id),
		payouts_for(mission_id, hero_id))

# ---------------------------------------------------------------- farming

func can_start_farm(mission_id: StringName, workers: int = 1) -> bool:
	var def: MissionDef = _by_id.get(mission_id)
	if def == null or not def.is_farm or not has_free_farm_slot():
		return false
	if not _data.find_by_mission(mission_id).is_empty():
		return false
	if not is_controlling() or not is_unlocked(mission_id):
		return false
	if _workers == null:
		return false
	return workers >= 1 and workers <= _workers.most_available_for(mission_id, 0)

## Puts workers on a farm, snapshotting the cycle length and what one cycle pays
## exactly as send() does. Returns the instance id, or 0 when refused.
##
## Nothing else has to happen for it to start earning: the next settle_farms()
## reads the two timestamps and pays whatever has elapsed.
func start_farm(mission_id: StringName, workers: int = 1) -> int:
	if not can_start_farm(mission_id, workers):
		return 0
	return _data.add(mission_id, &"", _now(),
		duration_for(mission_id, &"", workers),
		payouts_for(mission_id, &""), true, workers)

## Moves workers on or off a running farm and re-snapshots its cycle around the
## new count.
##
## Settled first, so the cycles already turned at the old rate are paid at the old
## rate and the part-cycle in progress is what the new one starts from. Without
## that, adding a worker would retroactively speed up time the farm had already
## spent - or, worse, taking one away would slow it.
func set_farm_workers(instance_id: int, workers: int) -> bool:
	var entry := _data.find(instance_id)
	if entry.is_empty() or not bool(entry["is_farm"]) or _workers == null:
		return false
	var mission_id: StringName = entry["mission_id"]
	var here := int(entry["workers"])
	if workers == here:
		return false
	if workers < 1 or workers > _workers.most_available_for(mission_id, here):
		return false

	var now := _now()
	var paid := _settle_farm(entry, now)
	if paid > 0:
		_data.missions_completed += paid
		sync_missions_completed()
	# Measured before the new duration is written, because it is a share of the
	# cycle the farm has been serving, not of the one it is about to.
	var carried := _carried(entry, now)
	entry["duration"] = duration_for(mission_id, &"", workers)
	entry["payouts"] = payouts_for(mission_id, &"")
	entry["started_at"] = now - carried * float(entry["duration"])
	return _data.set_workers(instance_id, workers)

## Clears a farm, handing its workers back to the pool and freeing the plot.
## Settles first, so stopping never costs the player a cycle already earned but
## not yet swept.
##
## The workers need no releasing of their own: where a worker is, is read off the
## board, so an entry that is gone is workers that are idle.
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

## How far through its current cycle a farm is, as a fraction of it.
##
## Carried across a worker change as a fraction rather than as seconds: half a
## slow cycle is half a fast one, so a worker added mid-cycle neither costs the
## player the time already served nor hands them any.
func _carried(entry: Dictionary, now: float) -> float:
	var duration := float(entry["duration"])
	if duration <= 0.0:
		return 0.0
	return fmod(maxf(0.0, now - float(entry["started_at"])), duration) / duration

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

## Whether this hero could take this expedition right now. Farms have their own
## check: they are worked by workers, who are neither recruited nor busy.
func _can_run(def: MissionDef, hero_id: StringName) -> bool:
	if not is_controlling():
		return false
	if not is_unlocked(def.id):
		return false
	if _heroes == null:
		return false
	return _heroes.is_available(hero_id)

# ---------------------------------------------------------------- collecting

## Brings one finished expedition home: pays every snapshotted payout, grants the
## permanent reward, closes the expedition for good, and frees the hero and
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
## back. Without this the hero is stuck until real time catches up to wherever
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
