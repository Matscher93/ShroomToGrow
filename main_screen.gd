extends Control
## VIEW — top-level screen orchestration. Currently: spawns the offline
## income popup into popup_layer whenever there's something to show, and
## clears it again once the player dismisses it.

@export var popup_layer: PopupLayer

const OFFLINE_INCOME_SCENE := preload("res://view/offline_income/sc_offline_income.tscn")

func _ready() -> void:
	if App.offline_income_vm:
		App.offline_income_vm.property_changed.connect(_on_offline_income_changed)
		# SaveManager computes offline progress in its own _ready(), which runs
		# before this scene even exists — the signal for that first batch is
		# long gone by the time we connect. Check current state too, not just
		# future signals.
		_check_pending_offline_income()

func _on_offline_income_changed(property: StringName) -> void:
	if property != OfflineIncomeViewModel.PROP_SNAPSHOTS_CHANGED:
		return
	_check_pending_offline_income()

func _check_pending_offline_income() -> void:
	if App.offline_income_vm.total_offline_ticks <= 0:
		return
	var popup := popup_layer.show_popup(OFFLINE_INCOME_SCENE)
	popup.dismissed.connect(popup_layer.clear, CONNECT_ONE_SHOT)
