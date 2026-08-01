class_name BiomesData
extends RefCounted
## MODEL: pure state. Which biomes are unlocked and how many upgrade points are
## spent in each. Knows nothing about cost, XP or UI.

signal biome_unlocked(key: StringName)

var unlocked: Dictionary = {}       # StringName -> bool, only true entries matter, cleared on prestige
var ever_unlocked: Dictionary = {}  # StringName -> bool, permanent, survives prestige reset
var spent_points: Dictionary = {}   # StringName -> int
var size: Dictionary = {}           # StringName -> int, purchased Biome Size, cleared on prestige

func is_unlocked(key: StringName) -> bool:
	return unlocked.get(key, false)

func biome_size(key: StringName) -> int:
	return size.get(key, 0)

func increase_size(key: StringName) -> void:
	size[key] = biome_size(key) + 1

## True once a biome has been unlocked at least once, across prestige resets.
## Keeps its bottom-bar tab reachable, does not grant features.
func is_ever_unlocked(key: StringName) -> bool:
	return ever_unlocked.get(key, false)

func unlock(key: StringName) -> void:
	if is_unlocked(key):
		return
	unlocked[key] = true
	ever_unlocked[key] = true
	biome_unlocked.emit(key)

func points_spent(key: StringName) -> int:
	return spent_points.get(key, 0)

func spend_points(key: StringName, amount: int) -> void:
	spent_points[key] = points_spent(key) + amount

func reset() -> void:
	unlocked.clear()
	spent_points.clear()
	size.clear()

func to_save() -> Dictionary:
	var unlocked_out := {}
	for key in unlocked:
		if unlocked[key]:
			unlocked_out[String(key)] = true
	var ever_unlocked_out := {}
	for key in ever_unlocked:
		if ever_unlocked[key]:
			ever_unlocked_out[String(key)] = true
	var spent_out := {}
	for key in spent_points:
		spent_out[String(key)] = spent_points[key]
	var size_out := {}
	for key in size:
		if size[key] > 0:
			size_out[String(key)] = size[key]
	return {"unlocked": unlocked_out, "ever_unlocked": ever_unlocked_out, "spent_points": spent_out, "size": size_out}

static func from_save(d: Dictionary) -> BiomesData:
	var data := BiomesData.new()
	var unlocked_in: Dictionary = d.get("unlocked", {})
	for key in unlocked_in:
		if unlocked_in[key]:
			data.unlocked[StringName(key)] = true
	var ever_unlocked_in: Dictionary = d.get("ever_unlocked", {})
	for key in ever_unlocked_in:
		if ever_unlocked_in[key]:
			data.ever_unlocked[StringName(key)] = true
	# Older saves predate ever_unlocked, so backfill from unlocked to keep
	# tabs reached before this feature shipped.
	for key in data.unlocked:
		if data.unlocked[key]:
			data.ever_unlocked[key] = true
	var spent_in: Dictionary = d.get("spent_points", {})
	for key in spent_in:
		data.spent_points[StringName(key)] = int(spent_in[key])
	var size_in: Dictionary = d.get("size", {})
	for key in size_in:
		data.size[StringName(key)] = int(size_in[key])
	return data
