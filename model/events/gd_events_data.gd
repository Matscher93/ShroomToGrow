class_name EventsData
extends RefCounted
## MODEL: pure state - the queue of events currently on offer. Knows nothing about
## what they pay or whether the player can afford them.
##
## An instance is a def id, a tick counter, an identity and its fertilizer roll,
## and nothing else. The resource amounts are computed from the def and the live
## balance whenever they are read (see EventSystem), so an event that sat in the
## queue overnight is still worth what its rule says rather than a percentage of a
## balance from hours ago.
##
## The fertilizer roll is the one thing stored rather than recomputed: rolling it
## again at collect time would pay a number the card never showed.
##
## Deliberately has no reset(): fertilizer is permanent, so the offers that pay it
## survive a prestige alongside it.

signal events_changed

## Array[Dictionary] of
## {"def_id": StringName, "progress": int, "instance_id": int, "roll": int}.
## Ordered oldest first, which is the order the sheet lists them in.
var events: Array[Dictionary] = []

## Never reused within a session or across a load, so a card freed while its
## payout is in flight cannot be matched by a later event taking its slot.
var _next_instance_id: int = 1

func count() -> int:
	return events.size()

func is_empty() -> bool:
	return events.is_empty()

func add(def_id: StringName, roll: int) -> int:
	var instance_id := _next_instance_id
	_next_instance_id += 1
	events.append({"def_id": def_id, "progress": 0, "instance_id": instance_id, "roll": roll})
	events_changed.emit()
	return instance_id

func find(instance_id: int) -> Dictionary:
	for event in events:
		if event["instance_id"] == instance_id:
			return event
	return {}

func remove(instance_id: int) -> bool:
	for i in events.size():
		if events[i]["instance_id"] != instance_id:
			continue
		events.remove_at(i)
		events_changed.emit()
		return true
	return false

## Advances every progress counter by one and reports the instance ids that have
## reached `goal_for`. Emits once for the whole sweep rather than once per event:
## a tick can complete several, and the sheet only redraws once either way.
##
## The caller removes and pays out the ids it gets back - this holds state, not
## rules.
func advance_progress(goal_for: Callable) -> Array[int]:
	var completed: Array[int] = []
	if events.is_empty():
		return completed
	var moved := false
	for event in events:
		var goal: int = goal_for.call(event["def_id"])
		if goal <= 0:
			continue
		event["progress"] = int(event["progress"]) + 1
		moved = true
		if event["progress"] >= goal:
			completed.append(int(event["instance_id"]))
	if moved:
		events_changed.emit()
	return completed

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var out: Array = []
	for event in events:
		out.append({
			"def_id": String(event["def_id"]),
			"progress": int(event["progress"]),
			"instance_id": int(event["instance_id"]),
			"roll": int(event["roll"]),
		})
	return {"events": out, "next_instance_id": _next_instance_id}

## Applies a save dict onto this instance in place, so EventSystem's reference
## stays valid. Same reason PlayerData.load_from_save exists.
##
## Entries that are not Dictionaries are skipped rather than assigned: a corrupt
## save must degrade to a shorter queue, not take the whole load down.
func load_from_save(d: Dictionary) -> void:
	events.clear()
	_next_instance_id = 1
	var saved: Array = d.get("events", [])
	for entry in saved:
		if not entry is Dictionary:
			push_warning("Saved event entry is not a Dictionary, skipping it.")
			continue
		var event: Dictionary = entry
		var instance_id := int(event.get("instance_id", 0))
		if instance_id <= 0:
			continue
		events.append({
			"def_id": StringName(event.get("def_id", "")),
			"progress": int(event.get("progress", 0)),
			"instance_id": instance_id,
			"roll": int(event.get("roll", 0)),
		})
		_next_instance_id = maxi(_next_instance_id, instance_id + 1)
	# Saved explicitly as well as derived above, so a queue emptied before the
	# save still cannot hand out an id an in-flight card remembers.
	_next_instance_id = maxi(_next_instance_id, int(d.get("next_instance_id", 1)))
	events_changed.emit()

static func from_save(d: Dictionary) -> EventsData:
	var data := EventsData.new()
	data.load_from_save(d)
	return data
