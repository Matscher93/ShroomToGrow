extends PanelContainer

## Emitted when the player dismisses the popup (collect button pressed).
## The PopupLayer that spawned this instance owns freeing it. This view never
## queue_frees itself, so it can't desync PopupLayer's tracked ref.
signal dismissed

var _vm: OfflineIncomeViewModel
var _snapshots: Array[Dictionary]
var _total_offline_ticks: int
var _total_offline_time: float
var _node_change_rows: Array[MyceliumNodeChangePanel] = []

@export var label_ticks: Label
@export var label_time: Label
@export var nutrient_panel: PanelContainer
## Hidden whenever the gap produced no water, which is every run before the
## Underground Lake is open. A "+0 Water" row on a save that has never seen the
## biome is a line about a feature the player has not met yet.
@export var water_panel: PanelContainer
@export var offline_income_button: PanelContainer
@export var vbox_node_change: VBoxContainer
@export var mycelium_node_change_item: PackedScene
@export var offline_time_container: PanelContainer  # drives tick_progress's shader param while calculating
@export var label_away_for: Label

func _ready() -> void:
	if App.offline_income_vm:
		bind(App.offline_income_vm)

## App owns this ViewModel for the app's lifetime while the popup is freed on
## every dismiss, so the binding has to be undone here. This was the one
## VM-binding view in the codebase relying on Godot's implicit free-time
## disconnect instead of the contract every sibling follows.
func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func bind(vm: OfflineIncomeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	# Authored visible so the row can be laid out in the editor. Nothing knows
	# whether the gap produced any water until the first _render_deltas, and the
	# placeholder text it ships with would read as a real payout until then.
	water_panel.visible = false
	_refresh()
	if not offline_income_button.pressed.is_connected(_on_dismiss_pressed):
		offline_income_button.pressed.connect(_on_dismiss_pressed)

func _on_property_changed(property: StringName) -> void:
	match property:
		OfflineIncomeViewModel.PROP_SNAPSHOTS_CHANGED, OfflineIncomeViewModel.PROP_CALCULATING_CHANGED, \
		OfflineIncomeViewModel.PROP_CALC_PROGRESS_CHANGED:
			_refresh()

## The popup spawns as soon as the offline calculation starts, so the player sees
## it instead of a blank screen. Collection stays blocked until the viewmodel has
## real data, but growth so far is shown live, read straight off the game state
## the offline tick loop is mutating in place.
func _refresh() -> void:
	offline_income_button.set_disabled(_vm.is_calculating)
	label_away_for.visible = not _vm.is_calculating
	if _vm.is_calculating:
		_vm.capture_live_baseline()
		var progress := float(_vm.calc_ticks_done) / float(max(1, _vm.calc_ticks_total))
		_set_tick_progress(progress)
		label_ticks.text = "%d / %d" % [_vm.calc_ticks_done, _vm.calc_ticks_total]
		label_time.text = "Calculating… %d%%" % [roundi(progress * 100.0)]
		_render_deltas(_vm.live_nutrient_delta, _vm.live_water_delta, _vm.live_node_deltas)
		return
	_vm.release_live_baseline()
	_set_tick_progress(1.0)
	_update_visuals()

func _set_tick_progress(progress: float) -> void:
	if offline_time_container and offline_time_container.material:
		offline_time_container.material.set_shader_parameter("tick_progress", clampf(progress, 0.0, 1.0))

## Rows are built once on first render, then updated and shown or hidden in
## place. This runs on every progress batch (~every 20ms) for the whole catch-up
## loop, so rebuilding the list each time would be allocation churn inside the
## loop SaveManager's frame budget is protecting.
## Takes the differences already worked out rather than the pairs to subtract:
## the live path gets them from the ViewModel and the finished one from the
## snapshots, and the rendering is the same either way.
func _render_deltas(nutrient_change: BigNumber, water_change: BigNumber,
		node_changes: Array[BigNumber]) -> void:
	nutrient_panel.set_currency_change(nutrient_change)

	# The well pumps through the same handle_tick() the catch-up loop drives, so
	# a gap spent with the lake open has already produced this by the time the
	# popup renders. Shown only when there is some: see water_panel.
	water_panel.visible = water_change.gt(BigNumber.from_value(0.0))
	if water_panel.visible:
		water_panel.set_currency_change(water_change)

	var nodes := _vm.node_defs
	_ensure_node_change_rows(nodes.size())

	var zero := BigNumber.from_value(0.0)
	for i in range(nodes.size()):
		var row := _node_change_rows[i]
		var node_change: BigNumber = node_changes[i]
		if node_change.equals(zero):
			row.visible = false
			continue
		row.visible = true
		row.set_data(nodes[i], i, node_change)

func _ensure_node_change_rows(count: int) -> void:
	# sc_offline_income.tscn authors placeholder rows into vbox_node_change so
	# the popup can be laid out in the editor. They must go before the real rows
	# are added, or the list renders placeholders followed by node changes.
	if _node_change_rows.is_empty():
		for child in vbox_node_change.get_children():
			vbox_node_change.remove_child(child)
			child.queue_free()

	while _node_change_rows.size() < count:
		var row: MyceliumNodeChangePanel = mycelium_node_change_item.instantiate()
		vbox_node_change.add_child(row)
		_node_change_rows.append(row)

func _update_visuals() -> void:
	_snapshots = _vm.save_data_snapshots
	_total_offline_ticks = _vm.total_offline_ticks
	_total_offline_time = _vm.offline_time

	label_ticks.text = "%d" % [_total_offline_ticks]
	label_time.text = format_duration(_total_offline_time)
	if _snapshots.size() > 0:
		var first := _snapshots[0]
		var last := _snapshots[_snapshots.size() - 1]
		var node_changes: Array[BigNumber] = []
		for i in range(_vm.node_defs.size()):
			node_changes.append(_get_node_count(last, i).sub(_get_node_count(first, i)))
		_render_deltas(
			_get_nutrient_count(last).sub(_get_nutrient_count(first)),
			_get_water_count(last).sub(_get_water_count(first)),
			node_changes)

static func format_duration(total_seconds: float, max_units := 2) -> String:
	var s := int(total_seconds)
	if s <= 0:
		return "0s"

	@warning_ignore_start("integer_division")
	var days := s / 86400
	var hours := (s % 86400) / 3600
	var minutes := (s % 3600) / 60
	var seconds := s % 60
	@warning_ignore_restore("integer_division")

	var parts: Array[String] = []
	if days > 0:
		parts.append("%dd" % days)
	if hours > 0:
		parts.append("%dh" % hours)
	if minutes > 0:
		parts.append("%dm" % minutes)
	if seconds > 0:
		parts.append("%ds" % seconds)

	return " ".join(parts.slice(0, max_units))

func _on_dismiss_pressed() -> void:
	dismissed.emit()

## A snapshot taken before a node tier existed carries fewer entries than the
## live node list, so an out-of-range tier had nothing then: zero.
func _get_node_count(save_data: Dictionary, index: int) -> BigNumber:
	var mycelium_nodes: Array = save_data.get("mycelium_nodes", [])
	if index < 0 or index >= mycelium_nodes.size():
		return BigNumber.new(0.0, 0)
	return BigNumber.from_save(mycelium_nodes[index].get("auto_nodes", {}))

func _get_nutrient_count(save_data: Dictionary) -> BigNumber:
	var player_data := PlayerData.from_save(save_data.get("player_data", {}))
	return player_data.nutrients

func _get_water_count(save_data: Dictionary) -> BigNumber:
	var player_data := PlayerData.from_save(save_data.get("player_data", {}))
	return player_data.water
