class_name PlayerData
extends RefCounted
## MODEL — pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)
signal biomass_changed(value: BigNumber)
signal water_changed(value: BigNumber)
signal tick_count_changed(value: int)

var nutrients: BigNumber = BigNumber.from_value(1.0):
	set(value):
		if nutrients == value:
			return
		nutrients = value
		nutrients_changed.emit(nutrients)
		
var biomass: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if biomass == value:
			return
		biomass = value
		biomass_changed.emit(biomass)
		
var water: BigNumber = BigNumber.from_value(0.0):
	set(value):
		if water == value:
			return
		water = value
		water_changed.emit(water)

var tick_count: int = 0:
	set(value):
		if tick_count == value:
			return
		tick_count = value
		tick_count_changed.emit(tick_count)

func to_save() -> Dictionary:
	var save_state = {
		"tick_count": tick_count,
		"nutrients": nutrients.to_save(),
		"biomass": biomass.to_save(),
		"water": water.to_save()
	}
	return save_state

static func from_save(d: Dictionary) -> PlayerData:
	var player_data = PlayerData.new()
	player_data.tick_count = d.get("tick_count", 0)
	player_data.nutrients = BigNumber.from_save(d.get("nutrients", {}))
	player_data.biomass = BigNumber.from_save(d.get("biomass", {}))
	player_data.water = BigNumber.from_save(d.get("water", {}))
	return player_data
