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
signal sequence_changed(biome_key: StringName)

var levels: Dictionary = {}      # StringName -> int
var enabled: Dictionary = {}     # StringName -> bool

## StringName (biome key) -> Array[StringName], the upgrade ids in the order the
## point-spending automation should buy them.
##
## Repeats are how levels are expressed: [A, A, B] means "take A to level 2,
## then B to level 1". That makes a sequence a build order rather than a set of
## targets, and makes replaying one after a prestige the same operation as
## running it the first time - see AutomationSystem's next_sequence_step().
##
## Empty by default. A biome with no sequence is simply skipped, rather than
## falling back to grid order and buying something the player never asked for.
var upgrade_sequences: Dictionary = {}

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

# ---------------------------------------------------------------- sequences

## One biome's sequence, reconciled against `authored_ids` on every read so an
## upgrade renamed or dropped from a biome cannot strand a saved sequence. New
## upgrades are *not* appended: the sequence is the player's, and silently
## adding steps to it would spend their points on something they never picked.
func sequence_for(biome_key: StringName, authored_ids: Array[StringName]) -> Array[StringName]:
	var reconciled: Array[StringName] = []
	for id: StringName in upgrade_sequences.get(biome_key, [] as Array[StringName]):
		if authored_ids.has(id):
			reconciled.append(id)
	upgrade_sequences[biome_key] = reconciled
	return reconciled

func _sequence(biome_key: StringName) -> Array[StringName]:
	if not upgrade_sequences.has(biome_key):
		upgrade_sequences[biome_key] = [] as Array[StringName]
	return upgrade_sequences[biome_key]

## Appends `count` steps of the same upgrade, emitting once rather than once per
## step: a single tap can add ten at a time, and a signal per step would rebuild
## the whole list ten times over.
func append_to_sequence(biome_key: StringName, id: StringName, count: int = 1) -> void:
	if count <= 0:
		return
	var sequence := _sequence(biome_key)
	for i in range(count):
		sequence.append(id)
	sequence_changed.emit(biome_key)

func remove_from_sequence(biome_key: StringName, index: int) -> bool:
	var sequence := _sequence(biome_key)
	if index < 0 or index >= sequence.size():
		return false
	sequence.remove_at(index)
	sequence_changed.emit(biome_key)
	return true

func move_sequence_entry(biome_key: StringName, from_index: int, to_index: int) -> bool:
	var sequence := _sequence(biome_key)
	if from_index < 0 or from_index >= sequence.size():
		return false
	if to_index < 0 or to_index >= sequence.size() or to_index == from_index:
		return false
	var id := sequence[from_index]
	sequence.remove_at(from_index)
	sequence.insert(to_index, id)
	sequence_changed.emit(biome_key)
	return true

func clear_sequence(biome_key: StringName) -> void:
	upgrade_sequences[biome_key] = [] as Array[StringName]
	sequence_changed.emit(biome_key)

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var levels_out := {}
	for id in levels:
		if levels[id] > 0:
			levels_out[String(id)] = levels[id]
	var enabled_out := {}
	for id in enabled:
		enabled_out[String(id)] = bool(enabled[id])
	var sequences_out := {}
	for biome_key in upgrade_sequences:
		var steps: Array = []
		for id: StringName in upgrade_sequences[biome_key]:
			steps.append(String(id))
		if not steps.is_empty():
			sequences_out[String(biome_key)] = steps
	return {"levels": levels_out, "enabled": enabled_out, "upgrade_sequences": sequences_out}

## Applies a save dict onto this instance in place, so AutomationSystem's
## reference stays valid. Same reason PlayerData.load_from_save exists.
func load_from_save(d: Dictionary) -> void:
	levels.clear()
	enabled.clear()
	upgrade_sequences.clear()
	var levels_in: Dictionary = d.get("levels", {})
	for key in levels_in:
		levels[StringName(key)] = int(levels_in[key])
	var enabled_in: Dictionary = d.get("enabled", {})
	for key in enabled_in:
		enabled[StringName(key)] = bool(enabled_in[key])
	var sequences_in: Dictionary = d.get("upgrade_sequences", {})
	for key in sequences_in:
		var steps: Array[StringName] = []
		for id in sequences_in[key]:
			steps.append(StringName(id))
		upgrade_sequences[StringName(key)] = steps
	levels_changed.emit()

static func from_save(d: Dictionary) -> AutomationData:
	var data := AutomationData.new()
	data.load_from_save(d)
	return data
