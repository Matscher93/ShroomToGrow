class_name OfflineIncomeViewModel
extends ViewModel
## VIEWMODEL — tracks save game snapshots shown in the offline income viewmodel

const PROP_SNAPSHOTS_CHANGED := &"snapshots_changed"
const PROP_CALCULATING_CHANGED := &"calculating_changed"
const PROP_CALC_PROGRESS_CHANGED := &"calc_progress_changed"

var _save_data_snapshots: Array[Dictionary]
var _total_offline_ticks: int
var _offline_time: float
var _is_calculating: bool
var _calc_ticks_done: int
var _calc_ticks_total: int

func set_save_data(in_save_data_snapshots: Array[Dictionary], in_total_offline_ticks: int, in_offline_time: float) -> void:
	_save_data_snapshots = in_save_data_snapshots
	_total_offline_ticks = in_total_offline_ticks
	_offline_time = in_offline_time
	_notify(PROP_SNAPSHOTS_CHANGED)

## Lets the popup show up immediately when the (timesliced) offline catch-up
## starts, rather than only once it finishes, while blocking collection until
## the result is actually ready.
func set_calculating(value: bool) -> void:
	if _is_calculating == value:
		return
	_is_calculating = value
	_notify(PROP_CALCULATING_CHANGED)

## Reported once per timesliced batch while the offline catch-up loop runs,
## so the popup can show live progress instead of a static "calculating" state.
func set_calc_progress(ticks_done: int, ticks_total: int) -> void:
	_calc_ticks_done = ticks_done
	_calc_ticks_total = ticks_total
	_notify(PROP_CALC_PROGRESS_CHANGED)

## Called once the player collects the popup. total_offline_ticks otherwise
## keeps its last completed value forever, so any later check for "is there
## something to show" (e.g. the next app resume, even with nothing new to
## report) would misread leftover data from this run as a fresh one.
func clear() -> void:
	_save_data_snapshots = []
	_total_offline_ticks = 0
	_offline_time = 0.0
	_notify(PROP_SNAPSHOTS_CHANGED)

var save_data_snapshots: Array[Dictionary]:
	get: return _save_data_snapshots

var total_offline_ticks: int:
	get: return _total_offline_ticks

var offline_time: float:
	get: return _offline_time

var is_calculating: bool:
	get: return _is_calculating

var calc_ticks_done: int:
	get: return _calc_ticks_done

var calc_ticks_total: int:
	get: return _calc_ticks_total
