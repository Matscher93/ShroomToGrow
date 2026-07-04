@tool
extends MarginContainer

@export var ItemColor : Color :
	set(value):
		ItemColor = value
		_update_colors(value)
		
@export var image_background: ColorRect
@export var image_header: ColorRect
@export var label_title: Label
@export var label_amount: Label
	
var _vm: MyceliumNodesViewModel
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_colors(ItemColor)
	if App.mycelium_nodes_vm:
		bind(App.mycelium_nodes_vm)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _update_colors(in_color: Color):
	var child := get_node_or_null("ColorRect")
	if is_instance_valid(child):
		image_background._set_color(in_color)
		image_header._set_color(in_color)
		label_title.label_settings.font_color = in_color
		label_amount.label_settings.font_color = in_color

func bind(vm: MyceliumNodesViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_all()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---
func _on_property_changed(property: StringName) -> void:
	match property:
		MyceliumNodesViewModel.PROP_GOLD_TEXT:
			label_amount.text = _vm.gold_text

func _refresh_all() -> void:
	label_amount.text = _vm.gold_text
