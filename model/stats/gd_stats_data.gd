class_name StatsData
extends RefCounted
## MODEL: pure state for the statistics overlay - personal bests, when the big
## moments happened, and what every finished run looked like. Knows no rules and
## reads no clock; StatsSystem writes all of it.
##
## Kept in open-ended dictionaries rather than in PlayerData's reflected field
## lists, the same way AchievementProgress holds its two maps: a peak is keyed by
## the currency or counter it belongs to, and a new one should cost a key rather
## than a field, a save entry and a migration.

## Peaks that are BigNumbers: the eight currencies, keyed by their PlayerData
## field name, plus &"production" - the most nutrients a single tick has ever
## paid out.
var peaks: Dictionary = {}        # StringName -> BigNumber

## Peaks that are plain counts: run length, nodes, biomes, levels, streaks.
var peak_counts: Dictionary = {}  # StringName -> int

## When the big moments happened, oldest first. Append-only: a milestone is a
## fact about the past, and nothing that happens later unmakes one.
##
## {"kind": String, "key": String, "at": float, "run": int}
##   kind &"biome"    - key is the biome key, recorded the first time it unlocks
##   kind &"node"     - key is the node id, recorded the first time it is bought
##   kind &"prestige" - key is the prestige index, recorded as the run ends
var milestones: Array = []

## Finished runs, oldest first. See StatsSystem.record_run() for the shape.
##
## Capped, because this rides in the save file and a long account is hundreds of
## runs of a dozen fields each. Nothing all-time is lost to the cap: the bests
## live in peaks/peak_counts, which no cap touches.
var runs: Array = []
const MAX_RUNS := 50

## Unix seconds. Zero means unknown - a save written before stats existed - and
## StatsSystem seeds both on the first tick it sees.
var run_started_at: float = 0.0
var first_played_at: float = 0.0

const _PEAK_KEYS: Array[String] = ["nutrients", "biomass", "water", "crystals",
	"fertilizer", "relics", "ichor", "glyphs", "production"]

## Raises a BigNumber peak, and says whether it moved. A peak only ever goes up,
## so this is the only way anything writes one.
func raise_peak(key: StringName, value: BigNumber) -> bool:
	if value == null:
		return false
	var current: BigNumber = peaks.get(key)
	if current != null and current.gte(value):
		return false
	peaks[key] = value
	return true

## The recorded peak, or zero for one nothing has reached yet.
func peak(key: StringName) -> BigNumber:
	var current: BigNumber = peaks.get(key)
	return current if current != null else BigNumber.new(0.0, 0)

func raise_count(key: StringName, value: int) -> bool:
	if value <= int(peak_counts.get(key, 0)):
		return false
	peak_counts[key] = value
	return true

func count(key: StringName) -> int:
	return int(peak_counts.get(key, 0))

## True once this milestone has been recorded, so the caller can skip a repeat.
## Biomes unlock again every run and a node tier is re-bought after every
## prestige; only the first of each is a moment.
func has_milestone(kind: String, key: String) -> bool:
	for row: Dictionary in milestones:
		if row.get("kind", "") == kind and row.get("key", "") == key:
			return true
	return false

func add_milestone(kind: String, key: String, at: float, run: int) -> void:
	milestones.append({"kind": kind, "key": key, "at": at, "run": run})

func add_run(record: Dictionary) -> void:
	runs.append(record)
	if runs.size() > MAX_RUNS:
		runs = runs.slice(runs.size() - MAX_RUNS)

# ---------------------------------------------------------------- save

func to_save() -> Dictionary:
	var saved_peaks := {}
	for key: String in peaks:
		saved_peaks[key] = (peaks[key] as BigNumber).to_save()
	return {
		"peaks": saved_peaks,
		"peak_counts": peak_counts.duplicate(),
		"milestones": milestones.duplicate(true),
		"runs": runs.duplicate(true),
		"run_started_at": run_started_at,
		"first_played_at": first_played_at,
	}

## Applies a save dict onto this instance in place, so anything already holding a
## reference keeps seeing the live object.
##
## Unknown peak keys are dropped rather than kept: a key that left _PEAK_KEYS is
## a record the game no longer has a name for, and carrying it forward would put
## an unlabelled row in the overlay forever.
func load_from_save(d: Dictionary) -> void:
	peaks.clear()
	var saved_peaks: Dictionary = d.get("peaks", {})
	for key: String in _PEAK_KEYS:
		if saved_peaks.has(key):
			peaks[key] = BigNumber.from_save(saved_peaks.get(key, {}))
	peak_counts = (d.get("peak_counts", {}) as Dictionary).duplicate()
	milestones = (d.get("milestones", []) as Array).duplicate(true)
	runs = (d.get("runs", []) as Array).duplicate(true)
	if runs.size() > MAX_RUNS:
		runs = runs.slice(runs.size() - MAX_RUNS)
	run_started_at = float(d.get("run_started_at", 0.0))
	first_played_at = float(d.get("first_played_at", 0.0))

static func from_save(d: Dictionary) -> StatsData:
	var stats := StatsData.new()
	stats.load_from_save(d)
	return stats
