extends PanelContainer
## VIEW: one biome's "auto-buy after sporation" purchase, on the Crystal Caves
## Automations tab. Bound to the same persistent BiomeSequenceViewModel that
## backs the biome's section on the Sequences tab.
##
## It sits with the automations rather than with the sequences because that is
## what it is: a crystal purchase that does something for you every run, with the
## same buy-then-switch shape as the cards above it. On the sequence sections it
## was one buy button repeated per biome, competing with the slot grid.

@export var lbl_name: Label
@export var lbl_status: Label
@export var lbl_cost: Label
@export var btn_buy: Button
@export var btn_enabled: Button

var _vm: BiomeSequenceViewModel

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)
	btn_enabled.pressed.connect(_on_enabled_pressed)

func bind(vm: BiomeSequenceViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_name.modulate = _vm.biome_color
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

## Buy and switch are never both up: the purchase is one-off, so its button gives
## way to the switch it unlocks rather than sitting there disabled forever.
func refresh() -> void:
	lbl_status.text = _vm.auto_unlock_text
	var for_sale := not _vm.has_auto_unlock
	lbl_cost.visible = for_sale
	btn_buy.visible = for_sale
	btn_enabled.visible = not for_sale
	if for_sale:
		lbl_cost.text = _vm.auto_unlock_cost_text
		btn_buy.disabled = not _vm.can_buy_auto_unlock
	else:
		btn_enabled.text = _vm.auto_unlock_toggle_text

func _on_buy_pressed() -> void:
	_vm.buy_auto_unlock()

func _on_enabled_pressed() -> void:
	_vm.toggle_auto_unlock()
