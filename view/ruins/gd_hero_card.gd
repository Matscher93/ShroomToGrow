extends PanelContainer
## VIEW: one hero on the roster. Takes it over, then levels it up.
##
## One button, not two: a hero is only ever in one of two states worth acting
## on, and the ViewModel already picks which. See HeroViewModel.action_text.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_level: Label
@export var lbl_bonus: Label
@export var lbl_chain: Label
@export var lbl_gate: Label
@export var lbl_status: Label
@export var btn_action: Button

var _vm: HeroViewModel

func _ready() -> void:
	btn_action.pressed.connect(_on_action_pressed)

func bind(vm: HeroViewModel) -> void:
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

# --- VM -> View ---

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_level.text = _vm.level_text
	lbl_bonus.text = _vm.bonus_text
	lbl_chain.text = _vm.chain_text
	lbl_chain.visible = not lbl_chain.text.is_empty()
	lbl_gate.text = _vm.gate_text
	lbl_gate.visible = not lbl_gate.text.is_empty()
	lbl_status.text = _vm.status_text
	btn_action.text = _vm.action_text
	btn_action.disabled = not _vm.can_act
	# A hero not yet taken over has no level line and no bonuses to show, so
	# the two rows collapse rather than printing empty labels.
	lbl_bonus.visible = _vm.is_recruited
	modulate.a = 1.0 if _vm.is_unlocked else 0.5

# --- View -> VM ---

func _on_action_pressed() -> void:
	if _vm.is_recruited:
		_vm.level_up()
		return
	_vm.recruit()
