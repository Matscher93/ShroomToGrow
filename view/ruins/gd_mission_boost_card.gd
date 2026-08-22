extends PanelContainer
## VIEW: one rung of the Ruins boost ladder.
##
## Deliberately not an extension of BoostCard: that one is built around the
## crystal ladder's tier line, which this has no equivalent of, and its labels
## are bound by NodePath to a scene with a different set. What they share is a
## shape, not an implementation.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_bonus: Label
@export var lbl_level: Label
@export var lbl_kind: Label
@export var lbl_next: Label
@export var lbl_cost: Label
@export var btn_buy: Button

var _vm: MissionBoostViewModel

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)

func bind(vm: MissionBoostViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	lbl_name.text = _vm.display_name
	lbl_description.text = _vm.description
	# Which half of the ladder this sits in never changes: it is read off the
	# stats the rung writes, and those are authored.
	lbl_kind.text = "Colony" if _vm.is_general else "Control"
	refresh()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

# --- VM -> View ---

func _on_property_changed(_property: StringName) -> void:
	refresh()

func refresh() -> void:
	lbl_bonus.text = _vm.bonus_text
	lbl_level.text = _vm.level_text
	lbl_next.text = _vm.next_level_text
	lbl_cost.text = _vm.cost_text
	btn_buy.disabled = not _vm.can_buy
	btn_buy.text = "Maxed" if _vm.is_maxed else "Buy"
	modulate.a = 1.0 if _vm.is_unlocked else 0.5

# --- View -> VM ---

func _on_buy_pressed() -> void:
	_vm.buy()
