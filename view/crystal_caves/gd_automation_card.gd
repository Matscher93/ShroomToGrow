extends PanelContainer
## VIEW: one automation in the Crystal Caves shop. Bound to a persistent
## AutomationViewModel owned by App.
##
## The SPEND_BIOME_POINTS card is the only one with a plan section under it; the
## rest hide it. CrystalCavesPanel owns the plan rows themselves, because
## reordering rebuilds the whole list and that is its job, not this card's.

signal plan_section_requested(container: VBoxContainer)

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_level: Label
@export var lbl_rate: Label
@export var lbl_cost: Label
@export var btn_buy: Button
@export var btn_enabled: Button
@export var plan_section: VBoxContainer
@export var plan_container: VBoxContainer

var _vm: AutomationViewModel

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)
	btn_enabled.pressed.connect(_on_enabled_pressed)

func bind(vm: AutomationViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	if _vm.edits_point_plan:
		plan_section_requested.emit(plan_container)
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_level.text = _vm.level_text
	lbl_cost.text = _vm.cost_text
	lbl_rate.text = _vm.rate_text
	btn_buy.disabled = not _vm.can_buy
	btn_enabled.visible = _vm.is_owned
	btn_enabled.text = "On" if _vm.is_enabled else "Off"
	# Only the point-spending card has a plan, and only once it can act on one.
	plan_section.visible = _vm.edits_point_plan and _vm.is_owned

func _on_buy_pressed() -> void:
	_vm.buy()

func _on_enabled_pressed() -> void:
	_vm.toggle_enabled()
