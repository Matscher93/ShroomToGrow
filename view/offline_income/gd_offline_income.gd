extends PanelContainer

var _vm: OfflineIncomeViewModel
var _snapshots: Array[Dictionary]
var _total_offline_ticks: int
var _total_offline_time: float

@export var label_ticks: Label
@export var label_time: Label
@export var nutrient_panel: PanelContainer
@export var offline_income_button: PanelContainer
@export var vbox_node_change: VBoxContainer
@export var mycelium_node_change_item: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if App.offline_income_vm:
		bind(App.offline_income_vm)

func bind(vm: OfflineIncomeViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_update_visuals()
	offline_income_button.on_button_pressed.connect(hide_panel)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
	
func _on_property_changed(property: StringName) -> void:
	match property:
		OfflineIncomeViewModel.PROP_SNAPSHOTS_CHANGED:
			_update_visuals()

func _update_visuals() -> void:
	_snapshots = _vm.get_save_data_snapshots()
	_total_offline_ticks = _vm.get_total_offline_ticks()
	_total_offline_time = _vm.get_offline_time()
	
	if _total_offline_ticks == 0:
		self.visible = false
	label_ticks.text = "%d" % [_total_offline_ticks]
	label_time.text = format_duration(_total_offline_time)
	if _snapshots.size() > 0:
		var initial_nutrient = _get_nutrient_count(_snapshots[0])
		var final_nutrient = _get_nutrient_count(_snapshots[_snapshots.size()-1])
		nutrient_panel.set_currency_change(final_nutrient.sub(initial_nutrient))
		
		var nodes = App.nodes.mycelium_nodes
		
		for child in vbox_node_change.get_children():
			vbox_node_change.remove_child(child)
			child.queue_free()
		
		for i in range(nodes.size()):
			var node = nodes[i]
			var node_scene_instance = mycelium_node_change_item.instantiate()
			var initial_node_count = _get_node_count(_snapshots[0], i)
			var final_node_count = _get_node_count(_snapshots[_snapshots.size()-1], i)
			
			node_scene_instance.set_data(node, i, final_node_count.sub(initial_node_count))
			
			vbox_node_change.add_child(node_scene_instance)

	
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
	if days > 0:    parts.append("%dd" % days)
	if hours > 0:   parts.append("%dh" % hours)
	if minutes > 0: parts.append("%dm" % minutes)
	if seconds > 0: parts.append("%ds" % seconds)

	return " ".join(parts.slice(0, max_units))

func hide_panel() -> void:
	self.visible = false

func _get_node_count(save_data: Dictionary, index: int) -> BigNumber:
	var mycelium_nodes = save_data.get("mycelium_nodes", [])
	var auto_nodes = BigNumber.from_save(mycelium_nodes[index].get("auto_nodes", BigNumber.from_value(0.0)))
	return auto_nodes
	
func _get_nutrient_count(save_data: Dictionary) -> BigNumber:
	var player_data = PlayerData.from_save(save_data.get("player_data", PlayerData.new()))
	return player_data.nutrients
