class_name AutomationData
extends RefCounted
## MODEL: pure state. Which automations are owned, which are switched on, and the
## order the point-spending automation should work through a biome's upgrades.
## Knows nothing about cost, intervals or UI.
##
## Deliberately has no reset(): automations are bought with crystals, which are
## permanent, so a prestige leaves them owned and running.

signal levels_changed
signal enabled_changed(id: StringName)
signal point_plan_changed(biome_key: StringName)

var levels: Dictionary = {}      # StringName -> int
var enabled: Dictionary = {}     # StringName -> bool
## StringName (biome key) -> Array[Dictionary], each {"id": StringName, "target": int}.
## Order is the order the automation buys in; target 0 means "until maxed".
## Seeded lazily from the biome's authored upgrade_ids, see plan_for().
var point_plan: Dictionary = {}

func level(id: StringName) -> int:
	return levels.get(id, 0)

func add_level(id: StringName) -> void:
	levels[id] = level(id) + 1
	levels_changed.emit()

## Owned automations default to on, so buying one starts it without a second tap.
func is_enabled(id: StringName) -> bool:
	return enabled.get(id, true)

func set_enabled(id: StringName, value: bool) -> void:
	if is_enabled(id) == value:
		return
	enabled[id] = value
	enabled_changed.emit(id)

# ---------------------------------------------------------------- point plan

## The plan for one biome, seeded from `authored_ids` (the biome's grid order) the
## first time it is asked for. Reconciled on every read so an upgrade added to or
## removed from a biome later doesn't strand a saved plan: unknown ids drop out,
## new ones are appended in grid order.
func plan_for(biome_key: StringName, authored_ids: Array[StringName]) -> Array:
	var stored: Array = point_plan.get(biome_key, [])
	var by_id := {}
	for entry: Dictionary in stored:
		by_id[StringName(entry.get("id", &""))] = entry

	var reconciled: Array = []
	for entry: Dictionary in stored:
		if authored_ids.has(StringName(entry.get("id", &""))):
			reconciled.append(entry)
	for id in authored_ids:
		if not by_id.has(id):
			reconciled.append({"id": id, "target": 0})

	point_plan[biome_key] = reconciled
	return reconciled

func move_entry(biome_key: StringName, from_index: int, to_index: int) -> bool:
	var plan: Array = point_plan.get(biome_key, [])
	if from_index < 0 or from_index >= plan.size():
		return false
	if to_index < 0 or to_index >= plan.size() or to_index == from_index:
		return false
	var entry: Dictionary = plan[from_index]
	plan.remove_at(from_index)
	plan.insert(to_index, entry)
	point_plan[biome_key] = plan
	point_plan_changed.emit(biome_key)
	return true

func set_target_level(biome_key: StringName, index: int, target: int) -> bool:
	var plan: Array = point_plan.get(biome_key, [])
	if index < 0 or index >= plan.size():
		return false
	var entry: Dictionary = plan[index]
	entry["target"] = max(0, target)
	point_plan_changed.emit(biome_key)
	return true

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var levels_out := {}
	for id in levels:
		if levels[id] > 0:
			levels_out[String(id)] = levels[id]
	var enabled_out := {}
	for id in enabled:
		enabled_out[String(id)] = bool(enabled[id])
	var plan_out := {}
	for biome_key in point_plan:
		var entries: Array = []
		for entry: Dictionary in point_plan[biome_key]:
			entries.append({"id": String(entry.get("id", &"")), "target": int(entry.get("target", 0))})
		plan_out[String(biome_key)] = entries
	return {"levels": levels_out, "enabled": enabled_out, "point_plan": plan_out}

## Applies a save dict onto this instance in place, so AutomationSystem's
## reference stays valid. Same reason PlayerData.load_from_save exists.
func load_from_save(d: Dictionary) -> void:
	levels.clear()
	enabled.clear()
	point_plan.clear()
	var levels_in: Dictionary = d.get("levels", {})
	for key in levels_in:
		levels[StringName(key)] = int(levels_in[key])
	var enabled_in: Dictionary = d.get("enabled", {})
	for key in enabled_in:
		enabled[StringName(key)] = bool(enabled_in[key])
	var plan_in: Dictionary = d.get("point_plan", {})
	for key in plan_in:
		var entries: Array = []
		for entry: Dictionary in plan_in[key]:
			entries.append({
				"id": StringName(entry.get("id", "")),
				"target": int(entry.get("target", 0)),
			})
		point_plan[StringName(key)] = entries
	levels_changed.emit()

static func from_save(d: Dictionary) -> AutomationData:
	var data := AutomationData.new()
	data.load_from_save(d)
	return data
