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

@export var gold_label: Label
@export var upgrade_button: Button

var _vm: PlayerViewModel

func _ready() -> void:
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	# Bind from the composition root (autoload). Views pull their VM,
	# which keeps scenes instantiable in isolation for testing too.
	if App.player_vm:
		bind(App.player_vm)

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
			gold_label.text = _vm.gold_text
		PlayerViewModel.PROP_UPGRADE_TEXT:
			upgrade_button.text = _vm.upgrade_button_text
		PlayerViewModel.PROP_CAN_BUY:
			upgrade_button.disabled = not _vm.can_buy_upgrade

func _refresh_all() -> void:
	gold_label.text = _vm.gold_text
	upgrade_button.text = _vm.upgrade_button_text
	upgrade_button.disabled = not _vm.can_buy_upgrade

# --- View -> VM ---

func _on_upgrade_pressed() -> void:
	_vm.buy_upgrade()
