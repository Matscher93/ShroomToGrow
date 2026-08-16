extends PanelContainer
## VIEW: the Well screen - the pump's status line over the list of projects water
## is spent on.
##
## Binds App.well_vm for what is shared across the screen; the cards carry their
## own per-project VMs. The water balance is in the top bar, from the screen
## definition's currencies, so no header repeats it.

@export var lbl_pump: Label
@export var vbox_projects: VBoxContainer
@export var scroll: ScrollContainer
@export var project_card_scene: PackedScene

var _vm: WellViewModel

func _ready() -> void:
	bind(App.well_vm)

func bind(vm: WellViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_build_projects()
	_refresh_pump()
	# The scroll position is restored a frame late: the cards have not been laid
	# out yet, so the container's scroll range is still zero and any offset set
	# now is clamped straight back to it.
	scroll.scroll_vertical = 0
	call_deferred("_restore_scroll")

func _exit_tree() -> void:
	if _vm:
		_vm.scroll_offset = float(scroll.scroll_vertical)
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(_property: StringName) -> void:
	_refresh_pump()

func _refresh_pump() -> void:
	lbl_pump.text = _vm.pump_text
	lbl_pump.modulate = Color(1.0, 1.0, 1.0, 1.0 if _vm.is_pumping else 0.55)

func _build_projects() -> void:
	for child in vbox_projects.get_children():
		vbox_projects.remove_child(child)
		child.queue_free()
	for vm in _vm.project_vms_ordered:
		var card := project_card_scene.instantiate()
		vbox_projects.add_child(card)
		card.bind(vm)

func _restore_scroll() -> void:
	if _vm:
		scroll.scroll_vertical = int(_vm.scroll_offset)
