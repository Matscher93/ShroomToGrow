extends PanelContainer
## VIEW: the achievement archive, shown as a full-screen overlay over whatever
## screen the player is on. Opened from the top bar, which is why it is an
## overlay and not a screen: claims pile up while the player is off doing
## something else, and walking to another screen to collect them was the friction
## worth removing.
##
## The root is the dimmed backdrop; tapping it closes, exactly like the close
## button. The sheet inside it is a PanelContainer, so it swallows its own
## presses and a tap on a row never reaches the backdrop.

## Emitted when the player dismisses the overlay. Whoever spawned this instance
## owns freeing it. This view never queue_frees itself, so it can't desync the
## PopupLayer's tracked ref.
signal dismissed

@export var lbl_tiers: Label
@export var btn_close: Button
@export var btn_claim_all: Button
@export var vbox_achievements: VBoxContainer
@export var achievement_row_scene: PackedScene

var _vm: AchievementsViewModel

func _ready() -> void:
	btn_close.pressed.connect(_on_dismiss_pressed)
	btn_claim_all.pressed.connect(_on_claim_all_pressed)
	bind(App.achievements_vm)
	_build_achievements()

func bind(vm: AchievementsViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_refresh_header()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	match property:
		AchievementsViewModel.PROP_TIERS_TEXT, AchievementsViewModel.PROP_CLAIM_ALL, \
		AchievementsViewModel.PROP_HAS_CLAIMS:
			_refresh_header()

func _refresh_header() -> void:
	lbl_tiers.text = _vm.tiers_text
	btn_claim_all.text = _vm.claim_all_text
	btn_claim_all.disabled = not _vm.has_claims

func _build_achievements() -> void:
	for child in vbox_achievements.get_children():
		vbox_achievements.remove_child(child)
		child.queue_free()
	for vm in _vm.achievement_vms_ordered:
		var row := achievement_row_scene.instantiate()
		vbox_achievements.add_child(row)
		row.bind(vm)

## Presses that reached the backdrop missed the sheet, so they are a tap outside
## the overlay.
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_dismiss_pressed()

func _on_claim_all_pressed() -> void:
	_vm.claim_all()

func _on_dismiss_pressed() -> void:
	dismissed.emit()
