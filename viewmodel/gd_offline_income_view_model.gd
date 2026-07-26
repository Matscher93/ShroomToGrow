class_name OfflineIncomeViewModel
extends ViewModel
## VIEWMODEL — tracks save game snapshots shown in the offline income viewmodel

const PROP_SNAPSHOTS_CHANGED := &"snapshots_changed"

var _save_data_snapshots: Array[Dictionary]
var _total_offline_ticks: int
var _offline_time: float

func set_save_data(in_save_data_snapshots: Array[Dictionary], in_total_offline_ticks: int, in_offline_time: float) -> void:
	_save_data_snapshots = in_save_data_snapshots
	_total_offline_ticks = in_total_offline_ticks
	_offline_time = in_offline_time
	_notify(PROP_SNAPSHOTS_CHANGED)

var save_data_snapshots: Array[Dictionary]:
	get: return _save_data_snapshots

var total_offline_ticks: int:
	get: return _total_offline_ticks

var offline_time: float:
	get: return _offline_time
