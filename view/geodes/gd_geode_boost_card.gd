extends PanelContainer
## VIEW: one geode boost in the Geode menu. Bound to a persistent
## GeodeBoostViewModel owned by App.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_bonus: Label
@export var lbl_level: Label
@export var lbl_tier: Label
@export var lbl_next: Label
@export var lbl_cost: Label
@export var btn_buy: Button

var _vm: GeodeBoostViewModel

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)

func bind(vm: GeodeBoostViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_bonus.text = _vm.bonus_text
	lbl_level.text = _vm.level_text
	lbl_tier.text = _vm.tier_text
	lbl_next.text = _vm.next_level_text
	lbl_cost.text = _vm.cost_text
	btn_buy.disabled = not _vm.can_buy
	btn_buy.text = "Maxed" if _vm.is_maxed else "Buy"

func _on_buy_pressed() -> void:
	_vm.buy()
