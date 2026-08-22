class_name PlayerData
extends RefCounted
## MODEL: pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)
signal biomass_changed(value: BigNumber)
signal water_changed(value: BigNumber)
signal crystals_changed(value: BigNumber)
signal fertilizer_changed(value: BigNumber)
signal tick_count_changed(value: int)
signal prestige_count_changed(value: int)
signal achievement_tiers_changed(value: int)
signal well_project_levels_changed(value: int)

## The BigNumber setters below guard with same_value(), not ==. BigNumber is a
## RefCounted, so == is an identity check, false for every freshly built
## instance, and its arithmetic never mutates in place. With ==, the guards are
## dead and every assignment emits to every bound ViewModel once per tick.
var nutrients: BigNumber = BigNumber.from_value(1.0):
	set(value):
		if value == null or nutrients.same_value(value):
			return
		nutrients = value
		nutrients_changed.emit(nutrients)

var biomass: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or biomass.same_value(value):
			return
		biomass = value
		biomass_changed.emit(biomass)

var water: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or water.same_value(value):
			return
		water = value
		water_changed.emit(water)

## Achievement reward currency, spent on automations. Permanent: prestige() never
## touches it, the same way it leaves biomass alone.
var crystals: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if value == null or crystals.same_value(value):
			return
		crystals = value
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
		fertilizer_changed.emit(fertilizer)

var tick_count: int = 0:
	set(value):
		if tick_count == value:
			return
		tick_count = value
		tick_count_changed.emit(tick_count)

var prestige_count: int = 0:
	set(value):
		if prestige_count == value:
			return
		prestige_count = value
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
		well_project_levels_changed.emit(well_project_levels)

## Lifetime totals the achievement ladder measures against. Unlike tick_count and
## the currencies above, these are never reset, so an achievement goal stays
## meaningful across prestiges. Plain fields, no signal: AchievementSystem is
## driven by App's dirty flag rather than by per-field notifications.
var lifetime_nutrients: BigNumber = BigNumber.from_value(0.0)
var lifetime_crystals: BigNumber = BigNumber.from_value(0.0)
var lifetime_fertilizer: BigNumber = BigNumber.from_value(0.0)
var lifetime_ticks: int = 0
var lifetime_manual_nodes: int = 0
var lifetime_biome_size: int = 0

## Random events collected or fulfilled, ever. Skipped events do not count - the
## ladder measures offers taken, not offers seen.
var events_resolved: int = 0

## Single source of truth for which fields round-trip through a save file.
## Add a new field here, and nowhere else, to have it saved and loaded.
const _BIG_NUMBER_FIELDS: Array[String] = ["nutrients", "biomass", "water", "crystals",
	"fertilizer", "lifetime_nutrients", "lifetime_crystals", "lifetime_fertilizer"]
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
