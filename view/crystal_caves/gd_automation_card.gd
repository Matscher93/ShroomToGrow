extends PanelContainer
## VIEW: one automation in the Crystal Caves shop. Bound to a persistent
## AutomationViewModel owned by App.
##
## What the point-spending automation actually buys lives in the per-biome
## sections on the Sequences tab, not on this card: a sequence belongs to its
## biome, and there is one card but several biomes.

@export var lbl_name: Label
@export var lbl_description: Label
@export var lbl_lock: Label
@export var lbl_level: Label
@export var lbl_rate: Label
@export var lbl_next_rate: Label
@export var lbl_cost: Label
@export var btn_buy: Button
@export var btn_enabled: CheckButton

## How long the card stays lit after a purchase. A level ticking over is easy to
## miss on a card that is otherwise unchanged, and with a hold-to-repeat Buy on a
## steep cost curve the player cannot otherwise tell one purchase from none.
const BUY_FLASH_SECONDS := 0.35

var _vm: AutomationViewModel
var _flash_tween: Tween

func _ready() -> void:
	btn_buy.pressed.connect(_on_buy_pressed)
	btn_enabled.toggled.connect(_on_enabled_toggled)

func bind(vm: AutomationViewModel) -> void:
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
	lbl_level.text = _vm.level_text
	lbl_cost.text = _vm.cost_text
	lbl_cost.visible = not lbl_cost.text.is_empty()
	lbl_rate.text = _vm.rate_text
	lbl_next_rate.text = _vm.next_rate_text
	lbl_lock.text = _vm.lock_text
	lbl_lock.visible = not lbl_lock.text.is_empty()
	btn_buy.disabled = not _vm.can_buy
	btn_enabled.visible = _vm.is_owned
	# No-signal: refresh runs on every property change, and a plain assignment
	# would report a toggle straight back at the model it just read from.
	btn_enabled.set_pressed_no_signal(_vm.is_enabled)

func _on_buy_pressed() -> void:
	if _vm.buy():
		_flash()

func _on_enabled_toggled(pressed: bool) -> void:
	if pressed != _vm.is_enabled:
		_vm.toggle_enabled()

## Brief lift and settle on the whole card. Cheaper to read at a glance than a
## number change, and it cannot be confused with the dimming that marks state.
func _flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	modulate = Color(1.35, 1.35, 1.35)
	_flash_tween = create_tween()
	_flash_tween.tween_property(self, "modulate", Color.WHITE, BUY_FLASH_SECONDS)
