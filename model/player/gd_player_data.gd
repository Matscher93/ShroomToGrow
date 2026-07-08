class_name PlayerData
extends RefCounted
## MODEL — pure state and game rules. Knows nothing about ViewModels or UI.

signal nutrients_changed(value: BigNumber)
signal tick_count_changed(value: int)

var nutrients: BigNumber = BigNumber.new(1, 0):
	set(value):
		if nutrients == value:
			return
		nutrients = value
		nutrients_changed.emit(nutrients)

var tick_count: int = 0:
	set(value):
		if tick_count == value:
			return
		tick_count = value
		tick_count_changed.emit(tick_count)

func to_save() -> Dictionary:
	var save_state = {
		"tick_count": tick_count,
		"nutrients": nutrients.to_save()
	}
	return save_state

static func from_save(d: Dictionary) -> PlayerData:
	var player_data = PlayerData.new()
	player_data.nutrients = BigNumber.from_save(d.get("nutrients", BigNumber.new(0.0, 0)))
	player_data.tick_count = d.get("tick_count", 0)
	return player_data
