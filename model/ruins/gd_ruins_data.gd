class_name RuinsData
extends RefCounted
## MODEL: pure state - which creatures are under control, which missions are in
## flight, and how many have ever been collected. Knows nothing about what a
## mission pays or whether it has finished.
##
## An in-flight mission is a def id, the creature carrying it, the wall-clock
## second it left, the seconds it takes and the payouts it will hand back. All
## five are snapshotted when the mission is sent, and none of them is recomputed
## afterwards: the card promises a finish time and a reward, and neither may move
## under the player while the creature is out. A &"mission_speed" or
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
signal creatures_changed
signal missions_completed_changed(value: int)

## Array[Dictionary] of
## {"mission_id": StringName, "creature_id": StringName, "started_at": float,
##  "duration": float, "instance_id": int, "payouts": Array[Dictionary]}.
## A payout entry is {"currency": int, "m": float, "e": int} - the CurrencyTypes
## ordinal and a BigNumber's two halves, which is the shape that round-trips
## through JSON without a second serialiser.
## Ordered oldest first, which is the order the board lists them in.
var active: Array[Dictionary] = []

## StringName creature id -> rank. A creature absent from this dictionary, or at
## rank 0, has not been taken over yet.
var creature_ranks: Dictionary = {}

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

func add(mission_id: StringName, creature_id: StringName, started_at: float,
		duration: float, payouts: Array[Dictionary]) -> int:
	var instance_id := _next_instance_id
	_next_instance_id += 1
	active.append({
		"mission_id": mission_id,
		"creature_id": creature_id,
		"started_at": started_at,
		"duration": duration,
		"instance_id": instance_id,
		"payouts": payouts,
	})
	active_changed.emit()
	return instance_id

func find(instance_id: int) -> Dictionary:
	for entry in active:
		if entry["instance_id"] == instance_id:
			return entry
	return {}

## The in-flight mission this creature is carrying, or {} when it is idle.
func find_by_creature(creature_id: StringName) -> Dictionary:
	for entry in active:
		if entry["creature_id"] == creature_id:
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

# ---------------------------------------------------------------- creatures

func rank(creature_id: StringName) -> int:
	return int(creature_ranks.get(creature_id, 0))

func set_rank(creature_id: StringName, value: int) -> void:
	if rank(creature_id) == value:
		return
	creature_ranks[creature_id] = value
	creatures_changed.emit()

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var out: Array = []
	for entry in active:
		out.append({
			"mission_id": String(entry["mission_id"]),
			"creature_id": String(entry["creature_id"]),
			"started_at": float(entry["started_at"]),
			"duration": float(entry["duration"]),
			"instance_id": int(entry["instance_id"]),
			"payouts": entry["payouts"].duplicate(true),
		})
	var ranks := {}
	for creature_id: StringName in creature_ranks:
		ranks[String(creature_id)] = int(creature_ranks[creature_id])
	return {
		"active": out,
		"creature_ranks": ranks,
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
			"creature_id": StringName(entry.get("creature_id", "")),
			"started_at": float(entry.get("started_at", 0.0)),
			"duration": float(entry.get("duration", 0.0)),
			"instance_id": instance_id,
			"payouts": _payouts_from_save(entry.get("payouts", [])),
		})
		_next_instance_id = maxi(_next_instance_id, instance_id + 1)
	# Saved explicitly as well as derived above, so a board emptied before the
	# save still cannot hand out an id an in-flight card remembers.
	_next_instance_id = maxi(_next_instance_id, int(d.get("next_instance_id", 1)))

	creature_ranks.clear()
	var ranks: Dictionary = d.get("creature_ranks", {})
	for key: Variant in ranks:
		creature_ranks[StringName(key)] = int(ranks[key])

	missions_completed = int(d.get("missions_completed", 0))
	active_changed.emit()
	creatures_changed.emit()

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
