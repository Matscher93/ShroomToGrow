class_name BiomesData
extends RefCounted
## MODEL — pure state: which biomes are unlocked, and how many upgrade
## points have been spent in each. Knows nothing about cost, XP, or UI.

signal biome_unlocked(key: StringName)

var unlocked: Dictionary = {}       # StringName -> bool (true entries only matter)
var spent_points: Dictionary = {}   # StringName -> int

func is_unlocked(key: StringName) -> bool:
	return unlocked.get(key, false)

func unlock(key: StringName) -> void:
	if is_unlocked(key):
		return
	unlocked[key] = true
	biome_unlocked.emit(key)

func points_spent(key: StringName) -> int:
	return spent_points.get(key, 0)

func spend_points(key: StringName, amount: int) -> void:
	spent_points[key] = points_spent(key) + amount

func to_save() -> Dictionary:
	var unlocked_out := {}
	for key in unlocked:
		if unlocked[key]:
			unlocked_out[String(key)] = true
	var spent_out := {}
	for key in spent_points:
		spent_out[String(key)] = spent_points[key]
	return {"unlocked": unlocked_out, "spent_points": spent_out}

static func from_save(d: Dictionary) -> BiomesData:
	var data := BiomesData.new()
	var unlocked_in: Dictionary = d.get("unlocked", {})
	for key in unlocked_in:
		if unlocked_in[key]:
			data.unlocked[StringName(key)] = true
	var spent_in: Dictionary = d.get("spent_points", {})
	for key in spent_in:
		data.spent_points[StringName(key)] = int(spent_in[key])
	return data
