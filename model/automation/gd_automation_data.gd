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
## Append-only, apart from dropping the last step or clearing outright. Neither
## of those shifts a surviving step's index, and the editor refuses to append a
## step whose point gate is above the length so far, so every step in a sequence
## the player built is reachable by construction. Inserting or reordering would
## break that, which is why neither exists.
##
## Empty by default. A biome with no sequence is simply skipped, rather than
## falling back to grid order and buying something the player never asked for.
var upgrade_sequences: Dictionary = {}

## biome key -> {src, size, revision} of the last sequence_for() reconcile, so a
## sequence nothing has touched is not rebuilt on every read. Transient and
## rebuilt on demand, never saved.
var _reconciled: Dictionary = {}
## Bumped by every mutator below. Size and object identity already catch most
## edits; this catches the one they cannot, an append and a removal between two
## reads leaving the array the same length.
var _revision: int = 0

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
##
## The reconcile is cached, not skipped. It is one authored_ids scan per step -
## a linear one, since the ids are an authored Array - and the automation reads
## a biome's sequence on every action it takes, so on a filled-in plan the walk
## was costing more than the purchase it led to. The stored array is the
## reconciled one after the first call, so a cache hit is "this is still the
## array I reconciled, unchanged": same object, same length, same revision.
func sequence_for(biome_key: StringName, authored_ids: Array[StringName]) -> Array[StringName]:
	# Untyped on purpose: a saved sequence arrives as a plain Array, and only the
	# reconciled one written back below is Array[StringName].
	var stored: Array = upgrade_sequences.get(biome_key, [] as Array[StringName])
	var cached: Variant = _reconciled.get(biome_key)
	if cached != null and cached["revision"] == _revision \
			and cached["size"] == stored.size() and is_same(cached["src"], stored):
		return stored
	var reconciled: Array[StringName] = []
	for id: StringName in stored:
		if authored_ids.has(id):
			reconciled.append(id)
	upgrade_sequences[biome_key] = reconciled
	_reconciled[biome_key] = {
		"src": reconciled, "size": reconciled.size(), "revision": _revision,
	}
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
	_revision += 1
	sequence_changed.emit(biome_key)

## Drops the last step. The only removal there is: taking one out of the middle
## would pull every step below it up by one, past the gate it was recorded
## against, and the replay would then skip it without saying so.
func remove_last_from_sequence(biome_key: StringName) -> bool:
	var sequence := _sequence(biome_key)
	if sequence.is_empty():
		return false
	sequence.resize(sequence.size() - 1)
	_revision += 1
	sequence_changed.emit(biome_key)
	return true

func clear_sequence(biome_key: StringName) -> void:
	upgrade_sequences[biome_key] = [] as Array[StringName]
	_revision += 1
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
	_revision += 1
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
	# All three dictionaries were replaced, so all three have to announce it. Only
	# levels_changed fired here, which left a toggle or a recorded sequence bound
	# to whatever the view had before the load.
	levels_changed.emit()
	for id: StringName in enabled:
		enabled_changed.emit(id)
	for biome_key: StringName in upgrade_sequences:
		sequence_changed.emit(biome_key)

static func from_save(d: Dictionary) -> AutomationData:
	var data := AutomationData.new()
	data.load_from_save(d)
	return data
