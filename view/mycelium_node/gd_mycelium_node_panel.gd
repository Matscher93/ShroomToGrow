class_name PlayerPanel
extends PanelContainer
## VIEW — dumb by design. Reads display properties from the VM,
## forwards input to VM commands. No game logic, no formatting.
##
## Expected scene structure (assign in inspector or match node names):
##   PlayerPanel (this script)
##   └── VBoxContainer
##       ├── GoldLabel : Label
##       └── UpgradeButton : Button

@export var upgrade_button: Button

var _vm: MyceliumNodesViewModel

func _ready() -> void:
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	# Bind from the composition root (autoload). Views pull their VM,
	# which keeps scenes instantiable in isolation for testing too.
	if App.mycelium_nodes_vm:
		bind(App.mycelium_nodes_vm)

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
		MyceliumNodesViewModel.PROP_UPGRADE_TEXT:
			upgrade_button.text = _vm.upgrade_button_text
		MyceliumNodesViewModel.PROP_CAN_BUY:
			upgrade_button.disabled = not _vm.can_buy_upgrade

func _refresh_all() -> void:
	upgrade_button.text = _vm.upgrade_button_text
	upgrade_button.disabled = not _vm.can_buy_upgrade

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()
