extends PanelContainer
## VIEW: one creature on the roster. Takes it over, then ranks it up.
##
## One button, not two: a creature is only ever in one of two states worth acting
## on, and the ViewModel already picks which. See CreatureViewModel.action_text.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_rank: Label
@export var lbl_bonus: Label
@export var lbl_affinity: Label
@export var lbl_status: Label
@export var btn_action: Button

var _vm: CreatureViewModel

func _ready() -> void:
	btn_action.pressed.connect(_on_action_pressed)

func bind(vm: CreatureViewModel) -> void:
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
	lbl_rank.text = _vm.rank_text
	lbl_bonus.text = _vm.bonus_text
	lbl_affinity.text = _vm.affinity_text
	lbl_status.text = _vm.status_text
	btn_action.text = _vm.action_text
	btn_action.disabled = not _vm.can_act
	# A creature not yet taken over has no rank line and no bonuses to show, so
	# the two rows collapse rather than printing empty labels.
	lbl_bonus.visible = _vm.is_recruited
	modulate.a = 1.0 if _vm.is_unlocked else 0.5

# --- View -> VM ---

func _on_action_pressed() -> void:
	if _vm.is_recruited:
		_vm.rank_up()
		return
	_vm.recruit()
