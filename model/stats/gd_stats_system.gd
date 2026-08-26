class_name StatsSystem
extends RefCounted
## MODEL: everything the statistics overlay records. Watches the run go by and
## writes peaks, milestones and finished-run records into StatsData.
##
## Holds only its inputs, no App reference, so it can be built and exercised in
## isolation. It connects nothing itself - App wires its note_* methods to the
## signals, the same way every other system here is driven.
##
## Nothing in here is derivable after the fact. A peak is gone the moment the
## value falls, a milestone is gone the moment the run resets, and a finished run
## is gone the moment prestige() wipes it - which is why this listens rather than
## computing on demand like the rest of the read-only surfaces.

const MILESTONE_BIOME := "biome"
const MILESTONE_NODE := "node"
const MILESTONE_PRESTIGE := "prestige"

## The eight PlayerData currencies whose held peak is worth a record, in the
## order the overlay lists them. Field names, so the peak key, the save key and
## the PlayerData property are all one string.
const CURRENCY_FIELDS: Array[String] = ["nutrients", "biomass", "water", "crystals",
	"fertilizer", "relics", "ichor", "glyphs"]

var _stats: StatsData
var _player_data: PlayerData
var _biomes: BiomeList
var _biomes_data: BiomesData
var _nodes: Array[MyceliumNode]
var _tick_system: TickSystem
var _symbiosis: UpgradeSystem
var _perks: UpgradeSystem
var _levels: PlayerLevelSystem
var _daily: DailyRewardData

## Best single tick this run has paid out, for the run record. Kept apart from
## the all-time peak in StatsData: the record says what *that* run reached, and
## an earlier, better run must not lend it its number.
var _run_peak_production: BigNumber = BigNumber.new(0.0, 0)

## Wall clock, injectable so a test can run a year of milestones without waiting
## for one. Same shape as SaveManager and MissionSystem.
var now_provider: Callable = func() -> float: return Time.get_unix_time_from_system()

func _init(stats: StatsData, player_data: PlayerData, biomes: BiomeList,
		biomes_data: BiomesData, nodes: Array[MyceliumNode], tick_system: TickSystem,
		symbiosis: UpgradeSystem, perks: UpgradeSystem, levels: PlayerLevelSystem,
		daily: DailyRewardData) -> void:
	_stats = stats
	_player_data = player_data
	_biomes = biomes
	_biomes_data = biomes_data
	_nodes = nodes
	_tick_system = tick_system
	_symbiosis = symbiosis
	_perks = perks
	_levels = levels
	_daily = daily

func _now() -> float:
	return float(now_provider.call())

# ---------------------------------------------------------------- sampling

## Per tick, and deliberately only the two things a tick can move on its own.
##
## This runs inside the offline catch-up loop as well, which drives tens of
## thousands of ticks in a few frames, so nothing that walks a dictionary or the
## node array belongs here - see sample_counts() for the rest.
func handle_tick() -> void:
	var now := _now()
	if _stats.first_played_at <= 0.0:
		_stats.first_played_at = now
	if _stats.run_started_at <= 0.0:
		_stats.run_started_at = now

	var gain := _tick_system.last_tick_gain
	if gain.gt(_run_peak_production):
		_run_peak_production = gain
	_stats.raise_peak(&"production", gain)
	_stats.raise_count(&"tick_count", _player_data.tick_count)

## The structural peaks - counts that only a purchase or an unlock can move.
##
## Driven off App's once-a-frame dirty flag rather than off the tick, because
## every source here is a purchase and the catch-up loop buys nothing.
func sample_counts() -> void:
	_stats.raise_count(&"manual_nodes", _manual_nodes())
	_stats.raise_count(&"biomes_unlocked", _biomes_unlocked())
	_stats.raise_count(&"biome_size", _biome_size_total())
	_stats.raise_count(&"player_level", _levels.level())
	_stats.raise_count(&"symbiosis_levels", _symbiosis.total_levels())
	_stats.raise_count(&"perk_levels", _perks.total_levels())
	_stats.raise_count(&"daily_streak", _daily.streak)

## Raises one currency's held peak. Bound per currency by App, so a spike that is
## spent again before the next tick still lands.
func note_currency(value: BigNumber, field: StringName) -> void:
	_stats.raise_peak(field, value)

# ---------------------------------------------------------------- milestones

## A biome reaching the map for the first time ever. BiomesData.biome_unlocked
## fires again every run once the prestige reset has cleared it, so anything
## already recorded is left alone - the moment was the first one.
func note_biome_unlocked(key: StringName) -> void:
	if _stats.has_milestone(MILESTONE_BIOME, String(key)):
		return
	_stats.add_milestone(MILESTONE_BIOME, String(key), _now(), _player_data.prestige_count)

## The first purchase of a node tier, ever. Fed by MyceliumNodeData.node_bought,
## which only a real purchase raises.
func note_node_bought(node: MyceliumNode) -> void:
	var key := str(node.node_id)
	if _stats.has_milestone(MILESTONE_NODE, key):
		return
	_stats.add_milestone(MILESTONE_NODE, key, _now(), _player_data.prestige_count)

## The run ending. Called from PrestigeSystem.prestiging, i.e. before anything is
## reset, so everything read here is still the run's final state.
##
## The index is prestige_count + 1 because the counter has not moved yet: this is
## the run that is about to become the Nth.
func note_prestige(gain: BigNumber) -> void:
	var now := _now()
	var index := _player_data.prestige_count + 1
	var record := {
		"index": index,
		"started_at": _stats.run_started_at,
		"ended_at": now,
		"ticks": _player_data.tick_count,
		"biomass_gained": gain.to_save(),
		"biomass_after": _player_data.biomass.add(gain).to_save(),
		"peak_production": _run_peak_production.to_save(),
		"manual_nodes": _manual_nodes(),
		"biomes": _biomes_unlocked(),
		"deepest_biome": _deepest_biome(),
		"perk_levels": _perks.total_levels(),
		"symbiosis_levels": _symbiosis.total_levels(),
	}
	# Every currency's closing balance, off the same list the peaks are taken
	# from, so a currency added there lands in the run records too instead of
	# being remembered in one of the two places and forgotten in the other.
	#
	# Most of these survive the sporation - only nutrients and water are reset -
	# so on those the number is a running total at the moment the run ended
	# rather than what the run itself earned. Which is what a comparison across
	# runs wants: it is the balance the next run started from.
	for field: String in CURRENCY_FIELDS:
		record[field] = (_player_data.get(field) as BigNumber).to_save()
	_stats.add_run(record)
	_stats.add_milestone(MILESTONE_PRESTIGE, str(index), now, index)
	_stats.run_started_at = now
	_run_peak_production = BigNumber.new(0.0, 0)

# ---------------------------------------------------------------- reads

func _manual_nodes() -> int:
	var total := 0
	for node in _nodes:
		total += node.manual_nodes
	return total

func _biomes_unlocked() -> int:
	var total := 0
	for def in _biomes.biomes:
		if _biomes_data.is_unlocked(def.key):
			total += 1
	return total

func _biome_size_total() -> int:
	var total := 0
	for def in _biomes.biomes:
		total += _biomes_data.biome_size(def.key)
	return total

## The furthest biome currently open, by the authored BiomeList order - which is
## the order they unlock in, so the last one open is the deepest reached.
func _deepest_biome() -> String:
	var deepest := ""
	for def in _biomes.biomes:
		if _biomes_data.is_unlocked(def.key):
			deepest = def.display_name
	return deepest
