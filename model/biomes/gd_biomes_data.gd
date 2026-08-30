class_name BiomesData
extends RefCounted
## MODEL: pure state. Which biomes are unlocked and how many upgrade points are
## spent in each. Knows nothing about cost, XP or UI.

signal biome_unlocked(key: StringName)
## Raised the *first* time a biome is opened, ever, and never again. Its own
## signal rather than a flag read back off biome_unlocked, which fires again on
## every post-prestige re-unlock: "the player has just seen this for the first
## time" is a one-shot, and a listener that reveals something cannot tell the two
## apart after the fact.
signal biome_first_unlocked(key: StringName)
## Raised when a biome's auto-unlock is bought or switched on/off. Its own signal
## rather than leaning on the crystal deduction: a large enough balance swallows
## the cost whole (BigNumber normalises to a mantissa and exponent, so 1.5e25
## minus 250 is still 1.5e25), and PlayerData's same_value() guard then emits
## nothing at all. A purchase must not go unannounced because it was cheap.
signal auto_unlock_changed(key: StringName)

var unlocked: Dictionary = {}       # StringName -> bool, only true entries matter, cleared on prestige
var ever_unlocked: Dictionary = {}  # StringName -> bool, permanent, survives prestige reset
var spent_points: Dictionary = {}   # StringName -> int
var size: Dictionary = {}           # StringName -> int, purchased Biome Size, cleared on prestige
## StringName -> bool, permanent. Bought with crystals, so like every other
## crystal purchase it survives the reset that clears `unlocked`. That is the
## whole point: the biome comes back on its own next run.
var auto_unlock: Dictionary = {}
## StringName -> bool, permanent. Whether an owned auto-unlock actually fires.
## Absent means on, so a purchase is live the moment it is made and only an
## explicit switch-off is worth storing. Kept apart from `auto_unlock` so
## switching one off never reads as refunding it.
var auto_unlock_enabled: Dictionary = {}

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
	var is_first := not is_ever_unlocked(key)
	unlocked[key] = true
	ever_unlocked[key] = true
	biome_unlocked.emit(key)
	if is_first:
		biome_first_unlocked.emit(key)

## True once the crystal purchase that re-opens this biome every run is owned.
func is_auto_unlock(key: StringName) -> bool:
	return auto_unlock.get(key, false)

func set_auto_unlock(key: StringName) -> void:
	if is_auto_unlock(key):
		return
	auto_unlock[key] = true
	auto_unlock_changed.emit(key)

## True when an owned auto-unlock is switched on. Meaningless without the
## purchase, and defaults to on so buying one takes effect immediately.
func is_auto_unlock_enabled(key: StringName) -> bool:
	return auto_unlock_enabled.get(key, true)

func set_auto_unlock_enabled(key: StringName, value: bool) -> void:
	if is_auto_unlock_enabled(key) == value:
		return
	auto_unlock_enabled[key] = value
	auto_unlock_changed.emit(key)

func points_spent(key: StringName) -> int:
	return spent_points.get(key, 0)

func spend_points(key: StringName, amount: int) -> void:
	spent_points[key] = points_spent(key) + amount

## Wipes the run. ever_unlocked and the auto_unlock pair are deliberately
## untouched: one is a permanent record, the other a permanent purchase and the
## switch that arms it.
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
	var auto_unlock_out := {}
	for key in auto_unlock:
		if auto_unlock[key]:
			auto_unlock_out[String(key)] = true
	# Both values matter here, unlike the sets above: `false` is the whole point
	# of the entry, and dropping it would silently re-arm a switched-off unlock.
	var auto_unlock_enabled_out := {}
	for key in auto_unlock_enabled:
		auto_unlock_enabled_out[String(key)] = bool(auto_unlock_enabled[key])
	return {"unlocked": unlocked_out, "ever_unlocked": ever_unlocked_out,
		"spent_points": spent_out, "size": size_out, "auto_unlock": auto_unlock_out,
		"auto_unlock_enabled": auto_unlock_enabled_out}

static func from_save(d: Dictionary) -> BiomesData:
	var data := BiomesData.new()
	data.load_from_save(d)
	return data

## Fills this instance from a save, in place, so the live object the app's views
## and systems already hold keeps its identity. The one field list, so a field
## added above cannot be forgotten by a caller copying a hand-picked subset -
## which is exactly how auto_unlock came back unowned on every boot.
##
## Merges rather than clears: unlock_free_biomes() has already opened the starter
## biomes by the time a save lands, and they must stay open even for a save
## written before one of them existed.
func load_from_save(d: Dictionary) -> void:
	# Set directly rather than through unlock(), which would also open the biome
	# for the current run. What was reached in some past run is not what is open
	# now, and only `unlocked` below decides that.
	var ever_unlocked_in: Dictionary = d.get("ever_unlocked", {})
	for key in ever_unlocked_in:
		if ever_unlocked_in[key]:
			ever_unlocked[StringName(key)] = true
	# Announced, unlike the rest: the bottom bar and the biome screens are bound
	# to this and have nothing else to tell them a load happened.
	var unlocked_in: Dictionary = d.get("unlocked", {})
	for key in unlocked_in:
		if unlocked_in[key]:
			unlock(StringName(key))
	# Older saves predate ever_unlocked, so backfill from unlocked to keep
	# tabs reached before this feature shipped.
	for key in unlocked:
		if unlocked[key]:
			ever_unlocked[key] = true
	var spent_in: Dictionary = d.get("spent_points", {})
	for key in spent_in:
		spent_points[StringName(key)] = int(spent_in[key])
	var size_in: Dictionary = d.get("size", {})
	for key in size_in:
		size[StringName(key)] = int(size_in[key])
	var auto_unlock_in: Dictionary = d.get("auto_unlock", {})
	for key in auto_unlock_in:
		if auto_unlock_in[key]:
			set_auto_unlock(StringName(key))
	# After the purchases above, since the switch means nothing without one.
	# Absent in saves written before the switch existed, which is exactly the
	# default: every auto-unlock owned back then was permanently on.
	var auto_unlock_enabled_in: Dictionary = d.get("auto_unlock_enabled", {})
	for key in auto_unlock_enabled_in:
		set_auto_unlock_enabled(StringName(key), bool(auto_unlock_enabled_in[key]))
