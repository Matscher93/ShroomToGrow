class_name RuinsData
extends RefCounted
## MODEL: pure state - which heroes are under control, which missions are in
## flight, and how many have ever been collected. Knows nothing about what a
## mission pays or whether it has finished.
##
## An in-flight mission is a def id, the hero carrying it, the wall-clock
## second it left, the seconds it takes and the payouts it will hand back. All
## five are snapshotted when the mission is sent, and none of them is recomputed
## afterwards: the card promises a finish time and a reward, and neither may move
## under the player while the hero is out. A &"mission_speed" or
## &"mission_reward" upgrade bought mid-flight applies to the next send.
##
## That snapshot is also what makes offline progress free. Completion is
## `now >= started_at + duration`, so a mission left running when the game closed
## is simply finished when it opens again - there is no catch-up loop to run and
## nothing to replay.
##
## Deliberately has no reset(): the mission currencies are permanent, so the
## roster and the tally that feed them survive a prestige alongside them.

signal active_changed
signal heroes_changed
signal missions_completed_changed(value: int)
## An expedition was finished for the first and only time. Split from
## active_changed because it moves what the ladder offers and what the reward
## track holds, neither of which a send or a collect on its own touches.
signal expeditions_changed
## A worker was hired, or moved on or off a farm. Split from active_changed
## because hiring moves neither the board nor the ladder.
signal workers_changed

## Array[Dictionary] of
## {"mission_id": StringName, "hero_id": StringName, "started_at": float,
##  "duration": float, "instance_id": int, "is_farm": bool, "workers": int,
##  "payouts": Array[Dictionary]}.
## An expedition carries a hero_id and no workers; a farm carries workers and an
## empty hero_id. The two halves of the roster never mix on one entry.
## A payout entry is {"currency": int, "m": float, "e": int} - the CurrencyTypes
## ordinal and a BigNumber's two halves, which is the shape that round-trips
## through JSON without a second serialiser.
## Ordered oldest first, which is the order the board lists them in.
##
## Expeditions and farms share the one array rather than splitting into two: the
## instance ids stay unique across both boards, and every read that does not care
## which kind it is looking at - the clock, the save, the settle sweep - stays a
## single walk. What the two kinds do not share is a cap: farms are limited by
## &"farm_slots" and expeditions only by the heroes free to send.
var active: Array[Dictionary] = []

## Expeditions already brought home, which is what makes them one-shot. Also the
## source of truth for the reward track: MissionSystem.sync_expedition_rewards()
## projects this onto it after every collect and after every load, so the two can
## never disagree and the track itself is never saved.
var completed_expeditions: Array[StringName] = []

## StringName hero id -> level. A hero absent from this dictionary, or at
## level 0, has not been taken over yet.
var hero_levels: Dictionary = {}

## Workers hired, ever. Where they are is read off the board - see
## WorkerSystem.assigned() - so this is only ever the total, and a farm removed
## hands its workers back to the pool by simply no longer counting them.
var workers_owned: int = 0:
	set(value):
		if workers_owned == value:
			return
		workers_owned = value
		workers_changed.emit()

var missions_completed: int = 0:
	set(value):
		if missions_completed == value:
			return
		missions_completed = value
		missions_completed_changed.emit(missions_completed)

## Never reused within a session or across a load, so a card freed while its
## payout is in flight cannot be matched by a later mission taking its slot.
var _next_instance_id: int = 1

# ---------------------------------------------------------------- missions

func count() -> int:
	return active.size()

func add(mission_id: StringName, hero_id: StringName, started_at: float,
		duration: float, payouts: Array[Dictionary], is_farm: bool = false,
		workers: int = 0) -> int:
	var instance_id := _next_instance_id
	_next_instance_id += 1
	active.append({
		"mission_id": mission_id,
		"hero_id": hero_id,
		"started_at": started_at,
		"duration": duration,
		"instance_id": instance_id,
		"is_farm": is_farm,
		"workers": workers,
		"payouts": payouts,
	})
	active_changed.emit()
	return instance_id

## Moves workers on or off a running farm. The caller owns re-snapshotting the
## cycle around the new count - see MissionSystem.set_farm_workers().
func set_workers(instance_id: int, workers: int) -> bool:
	var entry := find(instance_id)
	if entry.is_empty() or not bool(entry["is_farm"]):
		return false
	if int(entry["workers"]) == workers:
		return false
	entry["workers"] = workers
	active_changed.emit()
	workers_changed.emit()
	return true

func find(instance_id: int) -> Dictionary:
	for entry in active:
		if entry["instance_id"] == instance_id:
			return entry
	return {}

## The in-flight instance of this mission, or {} when none is out. One-shot
## expeditions may only be out once at a time - see MissionSystem.can_send().
func find_by_mission(mission_id: StringName) -> Dictionary:
	for entry in active:
		if entry["mission_id"] == mission_id:
			return entry
	return {}

## The in-flight mission this hero is carrying, or {} when it is idle.
func find_by_hero(hero_id: StringName) -> Dictionary:
	for entry in active:
		if entry["hero_id"] == hero_id:
			return entry
	return {}

func remove(instance_id: int) -> bool:
	for i in active.size():
		if active[i]["instance_id"] != instance_id:
			continue
		active.remove_at(i)
		active_changed.emit()
		return true
	return false

# ---------------------------------------------------------------- expeditions

func is_expedition_done(mission_id: StringName) -> bool:
	return completed_expeditions.has(mission_id)

## Records an expedition as finished. Idempotent: collect() is the only caller
## and it removes the entry straight after, but a double-collect must never leave
## the ladder holding the same id twice - the reward track projects off this list.
func mark_expedition_done(mission_id: StringName) -> void:
	if completed_expeditions.has(mission_id):
		return
	completed_expeditions.append(mission_id)
	expeditions_changed.emit()

# ---------------------------------------------------------------- heroes

func level(hero_id: StringName) -> int:
	return int(hero_levels.get(hero_id, 0))

func set_level(hero_id: StringName, value: int) -> void:
	if level(hero_id) == value:
		return
	hero_levels[hero_id] = value
	heroes_changed.emit()

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var out: Array = []
	for entry in active:
		out.append({
			"mission_id": String(entry["mission_id"]),
			"hero_id": String(entry["hero_id"]),
			"started_at": float(entry["started_at"]),
			"duration": float(entry["duration"]),
			"instance_id": int(entry["instance_id"]),
			"is_farm": bool(entry["is_farm"]),
			"workers": int(entry["workers"]),
			"payouts": entry["payouts"].duplicate(true),
		})
	var levels := {}
	for hero_id: StringName in hero_levels:
		levels[String(hero_id)] = int(hero_levels[hero_id])
	var done: Array = []
	for mission_id: StringName in completed_expeditions:
		done.append(String(mission_id))
	return {
		"active": out,
		"hero_levels": levels,
		"workers_owned": workers_owned,
		"completed_expeditions": done,
		"missions_completed": missions_completed,
		"next_instance_id": _next_instance_id,
	}

## Applies a save dict onto this instance in place, so the systems holding a
## reference stay valid. Same reason PlayerData.load_from_save exists.
##
## Entries that are not Dictionaries are skipped rather than assigned: a corrupt
## save must degrade to a shorter board, not take the whole load down.
func load_from_save(d: Dictionary) -> void:
	active.clear()
	_next_instance_id = 1
	var saved: Array = d.get("active", [])
	for raw: Variant in saved:
		if not raw is Dictionary:
			push_warning("Saved mission entry is not a Dictionary, skipping it.")
			continue
		var entry: Dictionary = raw
		var instance_id := int(entry.get("instance_id", 0))
		if instance_id <= 0:
			continue
		active.append({
			"mission_id": StringName(entry.get("mission_id", "")),
			"hero_id": StringName(entry.get("hero_id", "")),
			"started_at": float(entry.get("started_at", 0.0)),
			"duration": float(entry.get("duration", 0.0)),
			"instance_id": instance_id,
			# A save written before farms existed holds expeditions only, which is
			# what the default says.
			"is_farm": bool(entry.get("is_farm", false)),
			# Likewise: a farm saved before the workers arrived is one the v9
			# migration has already given a worker, and an expedition carries none.
			"workers": int(entry.get("workers", 0)),
			"payouts": _payouts_from_save(entry.get("payouts", [])),
		})
		_next_instance_id = maxi(_next_instance_id, instance_id + 1)
	# Saved explicitly as well as derived above, so a board emptied before the
	# save still cannot hand out an id an in-flight card remembers.
	_next_instance_id = maxi(_next_instance_id, int(d.get("next_instance_id", 1)))

	hero_levels.clear()
	var levels: Dictionary = d.get("hero_levels", {})
	for key: Variant in levels:
		hero_levels[StringName(key)] = int(levels[key])

	# Absent from a save written before expeditions were one-shot, which leaves
	# the ladder open. That hands a returning player the new permanent rewards
	# rather than silently denying them the only chance to earn them.
	completed_expeditions.clear()
	var done: Array = d.get("completed_expeditions", [])
	for raw: Variant in done:
		var mission_id := StringName(raw)
		if mission_id.is_empty() or completed_expeditions.has(mission_id):
			continue
		completed_expeditions.append(mission_id)

	workers_owned = int(d.get("workers_owned", 0))
	missions_completed = int(d.get("missions_completed", 0))
	active_changed.emit()
	heroes_changed.emit()
	expeditions_changed.emit()
	workers_changed.emit()

## Same guard as the entry loop above, one level down: a payout that is not a
## Dictionary is dropped rather than crashing the load, which costs that one
## mission part of its reward instead of costing the player the whole save.
func _payouts_from_save(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not raw is Array:
		return out
	for item: Variant in raw:
		if not item is Dictionary:
			push_warning("Saved mission payout is not a Dictionary, skipping it.")
			continue
		var payout: Dictionary = item
		out.append({
			"currency": int(payout.get("currency", 0)),
			"m": float(payout.get("m", 0.0)),
			"e": int(payout.get("e", 0)),
		})
	return out

static func from_save(d: Dictionary) -> RuinsData:
	var data := RuinsData.new()
	data.load_from_save(d)
	return data
