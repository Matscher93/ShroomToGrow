class_name OfflineIncomeViewModel
extends ViewModel
## VIEWMODEL — tracks save game snapshots shown in the offline income viewmodel

const PROP_SNAPSHOTS_CHANGED := "snapshots_changed"

var _save_data_snapshots: Array[Dictionary]
var _total_offline_ticks: int
var _offline_time: float

func set_save_data(save_data_snapshots: Array[Dictionary], total_offline_ticks: int, offline_time: float) -> void:
	_save_data_snapshots = save_data_snapshots
	_total_offline_ticks = total_offline_ticks
	_offline_time = offline_time
	_notify(PROP_SNAPSHOTS_CHANGED)
	
func get_save_data_snapshots() -> Array[Dictionary]:
	return _save_data_snapshots
 
func get_total_offline_ticks() -> int:
	return _total_offline_ticks

func get_offline_time() -> float:
	return _offline_time
