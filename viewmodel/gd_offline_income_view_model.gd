class_name OfflineIncomeViewModel
extends ViewModel
## VIEWMODEL: tracks the save snapshots the offline income popup diffs.

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

## Lets the popup appear as soon as the timesliced catch-up starts rather than
## when it finishes, while blocking collection until the result is ready.
func set_calculating(value: bool) -> void:
	if _is_calculating == value:
		return
	_is_calculating = value
	_notify(PROP_CALCULATING_CHANGED)

## Reported once per timesliced batch while the catch-up loop runs, so the popup
## shows live progress instead of a static "calculating" state.
func set_calc_progress(ticks_done: int, ticks_total: int) -> void:
	_calc_ticks_done = ticks_done
	_calc_ticks_total = ticks_total
	_notify(PROP_CALC_PROGRESS_CHANGED)

## Called once the player collects the popup. Without this, total_offline_ticks
## keeps its last value forever and a later "is there something to show" check
## (the next app resume) misreads leftover data as a fresh run.
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
