extends Control
## VIEW — top-level screen orchestration. Currently: spawns the offline
## income popup into popup_layer whenever there's something to show, and
## clears it again once the player dismisses it.

@export var popup_layer: PopupLayer

const OFFLINE_INCOME_SCENE := preload("res://view/offline_income/sc_offline_income.tscn")

var _offline_popup_active := false

func _ready() -> void:
	if App.offline_income_vm:
		App.offline_income_vm.property_changed.connect(_on_offline_income_changed)
		# SaveManager only records that offline progress is pending during
		# load_game(), which runs before this scene even exists. Kick off the
		# (timesliced) calculation now that something is actually here to
		# show its result, instead of blocking game start on it.
		SaveManager.offline_progress_pending.connect(_check_pending_offline_income)
		_check_pending_offline_income()

func _on_offline_income_changed(property: StringName) -> void:
	if property != OfflineIncomeViewModel.PROP_SNAPSHOTS_CHANGED:
		return
	_check_pending_offline_income()

func _check_pending_offline_income() -> void:
	if SaveManager.has_pending_offline_progress():
		# Show the popup right away — it starts in its "calculating" state
		# (collect button blocked) and updates itself once the timesliced
		# calculation finishes and populates the viewmodel.
		_show_offline_income_popup()
		SaveManager.run_offline_progress_calculation()
		return
	if App.offline_income_vm.total_offline_ticks <= 0:
		return
	_show_offline_income_popup()

func _show_offline_income_popup() -> void:
	if _offline_popup_active:
		return
	_offline_popup_active = true
	var popup := popup_layer.show_popup(OFFLINE_INCOME_SCENE)
	popup.dismissed.connect(func() -> void:
		App.offline_income_vm.clear()
		popup_layer.clear()
		_offline_popup_active = false
	, CONNECT_ONE_SHOT)
