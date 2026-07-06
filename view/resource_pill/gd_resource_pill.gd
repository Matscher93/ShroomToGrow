@tool
extends MarginContainer

@export var ItemColor : Color :
	set(value):
		ItemColor = value
		_update_colors()
		
@export var ValueColor : Color :
	set(value):
		ValueColor = value
		_update_colors()
		
@export var LabelColor : Color :
	set(value):
		LabelColor = value
		_update_colors()
		
@export var image_background: ColorRect
@export var image_header: ColorRect
@export var label_title: Label
@export var label_amount: Label
	
var _vm: PlayerViewModel
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_colors()
	if App.player_vm:
		bind(App.player_vm)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _update_colors():
	var child := get_node_or_null("ColorRect")
	if is_instance_valid(child):
		image_background._set_color(ItemColor)
		image_header._set_color(ItemColor)
		label_title.label_settings.font_color = LabelColor
		label_amount.label_settings.font_color = ValueColor

func bind(vm: PlayerViewModel) -> void:
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
		PlayerViewModel.PROP_GOLD_TEXT:
			label_amount.text = _vm.gold_text

func _refresh_all() -> void:
	label_amount.text = _vm.gold_text
