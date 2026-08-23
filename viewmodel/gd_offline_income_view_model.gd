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

## The live state the catch-up is growing, captured when it starts so the popup
## can show what has accrued so far.
##
## Here rather than in the popup because it is model state: the view was reading
## App.player_data.nutrients / .water and App.mycelium_node_data[i].node.auto_nodes
## directly, every progress batch, for the whole catch-up.
var _capture_taken := false
var _start_nutrients: BigNumber
var _start_water: BigNumber
var _start_node_counts: Array[BigNumber] = []

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

## Takes the baseline the live deltas below are measured against. Idempotent: the
## popup asks on every progress batch and only the first one may land.
func capture_live_baseline() -> void:
	if _capture_taken:
		return
	_capture_taken = true
	_start_nutrients = App.player_data.nutrients
	_start_water = App.player_data.water
	_start_node_counts.clear()
	for node_data in App.mycelium_node_data:
		_start_node_counts.append(node_data.node.auto_nodes)

## Drops the baseline so the next catch-up takes a fresh one.
func release_live_baseline() -> void:
	_capture_taken = false

## What the catch-up has produced since the baseline was taken. Zero before
## capture_live_baseline() has run.
var live_nutrient_delta: BigNumber:
	get:
		if not _capture_taken: return BigNumber.new(0.0, 0)
		return App.player_data.nutrients.sub(_start_nutrients)

var live_water_delta: BigNumber:
	get:
		if not _capture_taken: return BigNumber.new(0.0, 0)
		return App.player_data.water.sub(_start_water)

## One entry per node tier, in the order App holds them.
var live_node_deltas: Array[BigNumber]:
	get:
		var out: Array[BigNumber] = []
		for i in App.mycelium_node_data.size():
			if not _capture_taken or i >= _start_node_counts.size():
				out.append(BigNumber.new(0.0, 0))
				continue
			out.append(App.mycelium_node_data[i].node.auto_nodes.sub(_start_node_counts[i]))
		return out

## The node tiers themselves, for the rows' names and colours. A static registry
## read: nothing here changes at runtime.
var node_defs: Array[MyceliumNode]:
	get: return App.nodes.mycelium_nodes

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
