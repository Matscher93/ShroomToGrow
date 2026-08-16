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
		if not _initial_state_captured:
			_capture_initial_state()
		var progress := float(_vm.calc_ticks_done) / float(max(1, _vm.calc_ticks_total))
		_set_tick_progress(progress)
		label_ticks.text = "%d / %d" % [_vm.calc_ticks_done, _vm.calc_ticks_total]
		label_time.text = "Calculating… %d%%" % [roundi(progress * 100.0)]
		_render_deltas(_initial_nutrients, App.player_data.nutrients,
			_initial_water, App.player_data.water, _initial_node_counts,
			func(i: int) -> BigNumber: return App.mycelium_node_data[i].node.auto_nodes)
		return
	_initial_state_captured = false
	_set_tick_progress(1.0)
	_update_visuals()

## Snapshot of live state when calculation starts, so growth so far can be
## diffed against it every time progress is reported.
var _initial_state_captured := false
var _initial_nutrients: BigNumber
var _initial_water: BigNumber
var _initial_node_counts: Array[BigNumber]

func _capture_initial_state() -> void:
	_initial_state_captured = true
	_initial_nutrients = App.player_data.nutrients
	_initial_water = App.player_data.water
	_initial_node_counts.clear()
	for node_data in App.mycelium_node_data:
		_initial_node_counts.append(node_data.node.auto_nodes)

func _set_tick_progress(progress: float) -> void:
	if offline_time_container and offline_time_container.material:
		offline_time_container.material.set_shader_parameter("tick_progress", clampf(progress, 0.0, 1.0))

## Rows are built once on first render, then updated and shown or hidden in
## place. This runs on every progress batch (~every 20ms) for the whole catch-up
## loop, so rebuilding the list each time would be allocation churn inside the
## loop SaveManager's frame budget is protecting.
func _render_deltas(initial_nutrient: BigNumber, final_nutrient: BigNumber,
		initial_water: BigNumber, final_water: BigNumber,
		initial_node_counts: Array[BigNumber], final_node_count_fn: Callable) -> void:
	nutrient_panel.set_currency_change(final_nutrient.sub(initial_nutrient))

	# The well pumps through the same handle_tick() the catch-up loop drives, so
	# a gap spent with the lake open has already produced this by the time the
	# popup renders. Shown only when there is some: see water_panel.
	var water_change := final_water.sub(initial_water)
	water_panel.visible = water_change.gt(BigNumber.from_value(0.0))
	if water_panel.visible:
		water_panel.set_currency_change(water_change)

	var nodes := App.nodes.mycelium_nodes
	_ensure_node_change_rows(nodes.size())

	var zero := BigNumber.from_value(0.0)
	for i in range(nodes.size()):
		var row := _node_change_rows[i]
		var node_change: BigNumber = final_node_count_fn.call(i).sub(initial_node_counts[i])
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
		var initial_nutrient := _get_nutrient_count(_snapshots[0])
		var initial_node_counts: Array[BigNumber] = []
		for i in range(App.nodes.mycelium_nodes.size()):
			initial_node_counts.append(_get_node_count(_snapshots[0], i))
		var last_snapshot := _snapshots[_snapshots.size()-1]
		_render_deltas(initial_nutrient, _get_nutrient_count(last_snapshot),
			_get_water_count(_snapshots[0]), _get_water_count(last_snapshot), initial_node_counts,
			func(i: int) -> BigNumber: return _get_node_count(last_snapshot, i))

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
