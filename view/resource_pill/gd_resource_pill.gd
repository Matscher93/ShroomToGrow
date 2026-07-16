@tool
extends MarginContainer

@export var currency_def: CurrencyDef:
	set(value):
		if currency_def:
			currency_def.changed.disconnect(_update_visuals)
		currency_def = value
		if currency_def:
			currency_def.changed.connect(_update_visuals)
		_update_visuals()
		
@export var image_background: ColorRect
@export var image_header: ColorRect
@export var label_title: Label
@export var label_amount: Label
@export var label_change_per_tick: Label
	
var _vm: PlayerViewModel
var _vm_change: MyceliumNodeViewModel 
	
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_update_colors()
	if App.player_vm:
		bind(App.player_vm)
		if(App.mycelium_node_vms.size() > 0):
			bind_change(App.mycelium_node_vms[0])
		_refresh_all()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _update_visuals():
	_update_colors()
	label_title.text = currency_def.currency_name
	
func _update_colors():
	var child := get_node_or_null("ColorRect")
	if is_instance_valid(child):
		image_background._set_color(currency_def.main_color)
		image_header._set_color(currency_def.main_color)
		label_title.label_settings.font_color = currency_def.label_color
		label_amount.label_settings.font_color = currency_def.currency_color

func bind(vm: PlayerViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	
	
func bind_change(vm: MyceliumNodeViewModel) -> void:
	if _vm_change:
		_vm_change.property_changed.disconnect(_on_property_changed)
	_vm_change = vm
	_vm_change.property_changed.connect(_on_property_changed)
	

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
	if _vm_change:
		_vm_change.property_changed.disconnect(_on_property_changed)
		_vm_change = null

# --- VM -> View ---
func _on_property_changed(property: StringName) -> void:
	match property:
		PlayerViewModel.PROP_GOLD_TEXT:
			label_amount.text = _vm.gold_text
		MyceliumNodeViewModel.PROP_PRODUCTION_TEXT:
			label_change_per_tick.text = _vm_change.production_text_short

func _refresh_all() -> void:
	label_amount.text = _vm.gold_text
	label_change_per_tick.text = _vm_change.production_text_short
