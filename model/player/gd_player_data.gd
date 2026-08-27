class_name PlayerData
extends RefCounted
## MODEL: pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)
signal biomass_changed(value: BigNumber)
signal water_changed(value: BigNumber)
signal crystals_changed(value: BigNumber)
signal fertilizer_changed(value: BigNumber)
signal relics_changed(value: BigNumber)
signal ichor_changed(value: BigNumber)
signal glyphs_changed(value: BigNumber)
signal tick_count_changed(value: int)
signal prestige_count_changed(value: int)
signal achievement_tiers_changed(value: int)
signal well_project_levels_changed(value: int)
signal missions_completed_changed(value: int)

## Open batches, and the fields written while they were open. Same idiom and the
## same rationale as UpgradeSystem.begin_batch(): a caller moving these many
## times for one visible change collapses to one emit per field. See
## begin_batch().
var _batch_depth := 0
var _batch_pending: Dictionary = {}

## Suppresses this run of writes' change signals until the outermost end_batch(),
## which then emits once per field that actually moved, with the value it ended
## on. The fields themselves are written as they happen, so any read in between
## sees the new value - only the notification waits.
##
## What this is for: the offline catch-up drives tens of thousands of ticks, and
## every nutrients/tick_count write fans out through the bound ViewModels into
## label rebuilds on the screen behind the popup. The player sees one catch-up,
## so they get one refresh per frame of it.
##
## Always pair with end_batch(). Nesting is counted, only the outermost emits.
func begin_batch() -> void:
	_batch_depth += 1

func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth > 0 or _batch_pending.is_empty():
		return
	var pending := _batch_pending.keys()
	_batch_pending.clear()
	for field: StringName in pending:
		emit_signal("%s_changed" % field, get(field))

## True when the setter calling this should stay quiet, having recorded that its
## field needs an emit at end_batch(). A plain dictionary write per tick in place
## of a signal fan-out, and idempotent across the whole batch.
func _defer(field: StringName) -> bool:
	if _batch_depth <= 0:
		return false
	_batch_pending[field] = true
	return true

## The BigNumber setters below guard with same_value(), not ==. BigNumber is a
## RefCounted, so == is an identity check, false for every freshly built
## instance, and its arithmetic never mutates in place. With ==, the guards are
## dead and every assignment emits to every bound ViewModel once per tick.
var nutrients: BigNumber = BigNumber.from_value(1.0):
	set(value):
		if value == null or nutrients.same_value(value):
			return
		nutrients = value
		if _defer(&"nutrients"): return
		nutrients_changed.emit(nutrients)

var biomass: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or biomass.same_value(value):
			return
		biomass = value
		if _defer(&"biomass"): return
		biomass_changed.emit(biomass)

var water: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or water.same_value(value):
			return
		water = value
		if _defer(&"water"): return
		water_changed.emit(water)

## Achievement reward currency, spent on automations. Permanent: prestige() never
## touches it, the same way it leaves biomass alone.
var crystals: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or crystals.same_value(value):
			return
		crystals = value
		if _defer(&"crystals"): return
		crystals_changed.emit(crystals)

## Random-event reward currency, spent on the fertilizer upgrade track. Permanent:
## prestige() never touches it, the same way it leaves biomass and crystals alone.
##
## A BigNumber like every other currency even though events pay it out in single
## digits - that is what lets UpgradeSystem.buy() spend it by field name, with no
## second purchase path for a currency that behaves like the rest.
var fertilizer: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or fertilizer.same_value(value):
			return
		fertilizer = value
		if _defer(&"fertilizer"): return
		fertilizer_changed.emit(fertilizer)

## The three Ruins currencies, paid out by missions. Permanent: prestige() never
## touches them, the same way it leaves biomass, crystals and fertilizer alone.
##
## Three rather than one because a mission's payouts are authored per currency,
## which is what lets a boost ladder branch on which kind of mission fed it.
var relics: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or relics.same_value(value):
			return
		relics = value
		if _defer(&"relics"): return
		relics_changed.emit(relics)

var ichor: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or ichor.same_value(value):
			return
		ichor = value
		if _defer(&"ichor"): return
		ichor_changed.emit(ichor)

var glyphs: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or glyphs.same_value(value):
			return
		glyphs = value
		if _defer(&"glyphs"): return
		glyphs_changed.emit(glyphs)

var tick_count: int = 0:
	set(value):
		if tick_count == value:
			return
		tick_count = value
		if _defer(&"tick_count"): return
		tick_count_changed.emit(tick_count)

var prestige_count: int = 0:
	set(value):
		if prestige_count == value:
			return
		prestige_count = value
		if _defer(&"prestige_count"): return
		prestige_count_changed.emit(prestige_count)

## Total achievement tiers ever completed. Doubles as the Crystal Caves XP
## source (BiomeDef.XpSource.ACHIEVEMENT_TIERS), so it needs a change signal.
##
## Deliberately not in _PLAIN_FIELDS: AchievementProgress is the one source of
## truth and this is a cached projection of its total_tiers(), rewritten by
## AchievementSystem and by SaveManager after the progress bucket is loaded.
## Saving it too would let the two drift.
var achievement_tiers: int = 0:
	set(value):
		if achievement_tiers == value:
			return
		achievement_tiers = value
		if _defer(&"achievement_tiers"): return
		achievement_tiers_changed.emit(achievement_tiers)

## Times any well project has been funded, summed. Doubles as the Underground
## Lake's XP source (BiomeDef.XpSource.WELL_PROJECTS), so it needs a change
## signal.
##
## Same contract as achievement_tiers above: a cached projection of the project
## UpgradeSystem's levels, rewritten by WellSystem and re-synced after the
## project bucket is loaded. Deliberately not in _PLAIN_FIELDS - saving it too
## would let the two drift.
var well_project_levels: int = 0:
	set(value):
		if well_project_levels == value:
			return
		well_project_levels = value
		if _defer(&"well_project_levels"): return
		well_project_levels_changed.emit(well_project_levels)

## Missions collected across the whole account. Doubles as the Ruins' XP source
## (BiomeDef.XpSource.MISSIONS_COMPLETED), so it needs a change signal.
##
## Same contract as achievement_tiers and well_project_levels above: a cached
## projection of RuinsData.missions_completed, rewritten by MissionSystem and
## re-synced after the ruins bucket is loaded. Deliberately not in _PLAIN_FIELDS -
## saving it too would let the two drift.
var missions_completed: int = 0:
	set(value):
		if missions_completed == value:
			return
		missions_completed = value
		if _defer(&"missions_completed"): return
		missions_completed_changed.emit(missions_completed)

## Lifetime totals the achievement ladder measures against. Unlike tick_count and
## the currencies above, these are never reset, so an achievement goal stays
## meaningful across prestiges. Plain fields, no signal: AchievementSystem is
## driven by App's dirty flag rather than by per-field notifications.
var lifetime_nutrients: BigNumber = BigNumber.from_value(0.0)
var lifetime_crystals: BigNumber = BigNumber.from_value(0.0)
var lifetime_fertilizer: BigNumber = BigNumber.from_value(0.0)
var lifetime_relics: BigNumber = BigNumber.from_value(0.0)
var lifetime_ichor: BigNumber = BigNumber.from_value(0.0)
var lifetime_glyphs: BigNumber = BigNumber.from_value(0.0)
var lifetime_ticks: int = 0
var lifetime_manual_nodes: int = 0
var lifetime_biome_size: int = 0

## Random events collected or fulfilled, ever. Skipped events do not count - the
## ladder measures offers taken, not offers seen.
var events_resolved: int = 0

## Single source of truth for which fields round-trip through a save file.
## Add a new field here, and nowhere else, to have it saved and loaded.
const _BIG_NUMBER_FIELDS: Array[String] = ["nutrients", "biomass", "water", "crystals",
	"fertilizer", "relics", "ichor", "glyphs",
	"lifetime_nutrients", "lifetime_crystals", "lifetime_fertilizer",
	"lifetime_relics", "lifetime_ichor", "lifetime_glyphs"]
const _PLAIN_FIELDS: Array[String] = ["tick_count", "prestige_count",
	"lifetime_ticks", "lifetime_manual_nodes", "lifetime_biome_size", "events_resolved"]

func to_save() -> Dictionary:
	var save_state := {}
	for field in _BIG_NUMBER_FIELDS:
		save_state[field] = (get(field) as BigNumber).to_save()
	for field in _PLAIN_FIELDS:
		save_state[field] = get(field)
	return save_state

## Applies a save dict onto this instance in place through each field's setter,
## so *_changed signals fire as usual. Use this rather than replacing
## App.player_data: ViewModels hold a reference, swapping the instance orphans
## them.
func load_from_save(d: Dictionary) -> void:
	for field in _BIG_NUMBER_FIELDS:
		set(field, BigNumber.from_save(d.get(field, {})))
	for field in _PLAIN_FIELDS:
		set(field, d.get(field, 0))

## Builds a fresh, disconnected PlayerData from a save dict. For reading a past
## snapshot's values (e.g. offline-income deltas), not for live state.
static func from_save(d: Dictionary) -> PlayerData:
	var player_data := PlayerData.new()
	player_data.load_from_save(d)
	return player_data
