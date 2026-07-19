extends PanelContainer

var _vm : ScreensViewModel
@export var screen_container: PanelContainer
@export var button_container: HBoxContainer
@export var button_scene: PackedScene

var button_dictonary: Dictionary[ScreenTypes.Types, PanelContainer]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if App.screens_vm:
		bind(App.screens_vm)

func bind(vm: ScreensViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	update_visuals()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null
		
func _on_property_changed(property: StringName) -> void:
	match property:
		ScreensViewModel.PROP_SCREEN_CHANGED_TEXT:
			update_visuals()

func update_visuals() -> void:
	var screen_data = _vm.get_screen_data(_vm.get_current_screen())
	for child in screen_container.get_children():
		screen_container.remove_child(child)
		child.queue_free()
	
	var node_scene_instance = screen_data.screen_scene.instantiate()
	screen_container.add_child(node_scene_instance)

	for child in button_container.get_children():
		button_container.remove_child(child)
		child.queue_free()
	
	var all_screens = _vm.get_all_screen_data()
	for screen_key : ScreenTypes.Types in ScreenTypes.Types.size():
		var button_data = all_screens.get(screen_key)
		var button = button_scene.instantiate()
		button.set_button_text(button_data.screen_name)
		button.on_button_pressed.connect(on_screen_selected.bind(screen_key))
		button.set_selected(_vm.get_current_screen() == screen_key)
		
		button_dictonary[screen_key] = button
		button_container.add_child(button)
		
	

func on_screen_selected(selected_screen : ScreenTypes.Types) -> void:
	_vm.set_current_screen(selected_screen)
	for button_key in button_dictonary:
		button_dictonary.get(button_key).set_selected(_vm.get_current_screen() == button_key)
