extends Control
## VIEW: top-level screen orchestration. Spawns the offline income popup into
## popup_layer whenever there's something to show, and clears it again once the
## player dismisses it. Also owns the top bar's three overlays, which get their
## own layer above the popup one: the offline popup lands at boot without asking, and
## sharing a layer would let an overlay opened on top of it free it out from
## under the collect flow.
##
## The nav menu gets a third layer of its own, below both of those. It is the one
## overlay the player opens constantly, and anything that lands on top of it -
## the offline popup at boot, an achievements claim - should stay on top rather
## than be freed by the next tap on the menu disc.

@export var popup_layer: PopupLayer
@export var overlay_layer: PopupLayer
@export var nav_layer: PopupLayer
@export var top_bar: Control
@export var nav_disc: Control

const OFFLINE_INCOME_SCENE := preload("res://view/offline_income/sc_offline_income.tscn")
const ACHIEVEMENTS_SCENE := preload("res://view/achievements/sc_achievements_panel.tscn")
const GROWTH_SCENE := preload("res://view/growth/sc_growth_panel.tscn")
const EVENTS_SCENE := preload("res://view/events/sc_events_panel.tscn")
const NAV_MENU_SCENE := preload("res://view/navigation/sc_nav_menu.tscn")

var _offline_popup_active := false

func _ready() -> void:
	add_child(ShaderWarmup.new())
	add_child(MenuWarmup.new())
	top_bar.achievements_pressed.connect(_on_achievements_pressed)
	top_bar.growth_pressed.connect(_on_growth_pressed)
	top_bar.events_pressed.connect(_on_events_pressed)
	nav_disc.pressed.connect(_on_nav_pressed)
	if App.offline_income_vm:
		App.offline_income_vm.property_changed.connect(_on_offline_income_changed)
		# SaveManager only records pending offline progress during load_game(),
		# which runs before this scene exists. Kick off the timesliced
		# calculation now that something is here to show its result, instead
		# of blocking game start on it.
		SaveManager.offline_progress_pending.connect(_check_pending_offline_income)
		_check_pending_offline_income()

func _on_offline_income_changed(property: StringName) -> void:
	if property != OfflineIncomeViewModel.PROP_SNAPSHOTS_CHANGED:
		return
	_check_pending_offline_income()

func _check_pending_offline_income() -> void:
	# A catch-up in flight owns the pending gap: it reports its own progress
	# into the viewmodel and the popup is already up. This runs on every
	# snapshots_changed, including the finishing run's, so starting again here
	# would replay the same gap.
	if SaveManager.is_offline_calc_running():
		return
	if SaveManager.has_pending_offline_progress():
		# Show the popup right away. It starts in its "calculating" state with
		# the collect button blocked, and updates itself once the timesliced
		# calculation populates the viewmodel.
		_show_offline_income_popup()
		SaveManager.run_offline_progress_calculation()
		return
	if App.offline_income_vm.total_offline_ticks <= 0:
		return
	_show_offline_income_popup()

## Tapping the top bar's achievement button toggles: a second tap on an open
## overlay closes it, the same as the backdrop or the close button.
func _on_achievements_pressed() -> void:
	if overlay_layer.has_popup():
		overlay_layer.clear()
		return
	var overlay := overlay_layer.show_popup(ACHIEVEMENTS_SCENE)
	overlay.dismissed.connect(overlay_layer.clear, CONNECT_ONE_SHOT)

## Same toggle as the achievements button, and deliberately the same layer: the
## two overlays are alternative views of "what is waiting for me", so opening one
## replaces the other rather than stacking on it.
func _on_growth_pressed() -> void:
	if overlay_layer.has_popup():
		overlay_layer.clear()
		return
	var overlay := overlay_layer.show_popup(GROWTH_SCENE)
	overlay.dismissed.connect(overlay_layer.clear, CONNECT_ONE_SHOT)

## Same toggle and the same layer again, for the same reason: the events sheet is
## a third answer to "what is waiting for me", so opening it replaces whichever of
## the other two was up.
func _on_events_pressed() -> void:
	if overlay_layer.has_popup():
		overlay_layer.clear()
		return
	var overlay := overlay_layer.show_popup(EVENTS_SCENE)
	overlay.dismissed.connect(overlay_layer.clear, CONNECT_ONE_SHOT)

## Tapping the disc toggles, the same as the achievements button. The open menu's
## backdrop covers the disc, so a second tap lands on the backdrop and closes
## there - this is for the case where something else cleared the layer first.
func _on_nav_pressed() -> void:
	if nav_layer.has_popup():
		nav_layer.clear()
		return
	var menu := nav_layer.show_popup(NAV_MENU_SCENE)
	menu.dismissed.connect(nav_layer.clear, CONNECT_ONE_SHOT)

func _show_offline_income_popup() -> void:
	if _offline_popup_active:
		return
	_offline_popup_active = true
	var popup := popup_layer.show_popup(OFFLINE_INCOME_SCENE)
	popup.dismissed.connect(func() -> void:
		# Tear the popup down *before* clearing the viewmodel. clear() notifies
		# synchronously, landing back in _check_pending_offline_income(), and
		# with the popup still marked active that check can start a catch-up
		# whose popup is then freed out from under it, burning frame budget on
		# ticks with nothing on screen.
		popup_layer.clear()
		_offline_popup_active = false
		App.offline_income_vm.clear()
	, CONNECT_ONE_SHOT)
