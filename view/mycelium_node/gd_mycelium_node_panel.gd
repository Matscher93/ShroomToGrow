@tool
class_name MyceliumNodePanel
extends PanelContainer
## VIEW — dumb by design. Reads display properties from the VM,
## forwards input to VM commands. No game logic, no formatting.
##
## Expected scene structure (assign in inspector or match node names):
##   PlayerPanel (this script)
##   └── VBoxContainer
##       ├── GoldLabel : Label
##       └── UpgradeButton : Button

@export var ColorParam: String
@export var upgrade_button: Button
@export var auto_nodes: Label
@export var manual_nodes: Label
@export var node_level: int = 0
var _vm: MyceliumNodeViewModel

func _ready() -> void:
	_update_shader()
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	# Bind from the composition root (autoload). Views pull their VM,
	# which keeps scenes instantiable in isolation for testing too.
	if App.mycelium_node_vms[node_level]:
		bind(App.mycelium_node_vms[node_level])

func bind(vm: MyceliumNodeViewModel) -> void:
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
		MyceliumNodeViewModel.PROP_UPGRADE_TEXT:
			upgrade_button.text = _vm.upgrade_button_text
		MyceliumNodeViewModel.PROP_CAN_BUY:
			upgrade_button.disabled = not _vm.can_buy_upgrade
		MyceliumNodeViewModel.PROP_AUTO_NODE_TEXT:
			auto_nodes.text =_vm.auto_node_text
		MyceliumNodeViewModel.PROP_MANUAL_NODE_TEXT:
			manual_nodes.text = _vm.manual_node_text

func _refresh_all() -> void:
	upgrade_button.text = _vm.upgrade_button_text
	upgrade_button.disabled = not _vm.can_buy_upgrade
	auto_nodes.text =_vm.auto_node_text
	manual_nodes.text = _vm.manual_node_text
	_set_color(_vm._mycelium_data._node.color)

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()

func _notification(what):
	if what == NOTIFICATION_RESIZED:
		_update_shader()

func _update_shader():
	if material:
		material.set_shader_parameter("rect_size", size * get_global_transform().get_scale())

func _set_color(inColor : Color):
	if material:
		material.set_shader_parameter(ColorParam, inColor)
