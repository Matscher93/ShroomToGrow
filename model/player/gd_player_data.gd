class_name PlayerData
extends RefCounted
## MODEL: pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)
signal biomass_changed(value: BigNumber)
signal water_changed(value: BigNumber)
signal tick_count_changed(value: int)
signal prestige_count_changed(value: int)

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

## Single source of truth for which fields round-trip through a save file.
## Add a new field here, and nowhere else, to have it saved and loaded.
const _BIG_NUMBER_FIELDS: Array[String] = ["nutrients", "biomass", "water"]
const _PLAIN_FIELDS: Array[String] = ["tick_count", "prestige_count"]

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
