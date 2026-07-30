extends PanelContainer

var _vm : ScreensViewModel
@export var screen_container: PanelContainer
@export var button_container: HBoxContainer
@export var button_scene: PackedScene

var button_dictionary: Dictionary[ScreenTypes.Types, PanelContainer]

## Screens are built once and then shown/hidden, never freed on switch. They
## used to be queue_free()'d and re-instantiated every time a tab was tapped,
## which threw away all of that screen's view state on each switch — the perk
## web's pan/zoom and selected perk, expanded biome cards, scroll positions —
## and paid for a full scene instantiate + _ready + first layout each time.
var _screen_instances: Dictionary[ScreenTypes.Types, Control] = {}
var _current_screen_instance: Control = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if App.screens_vm:
		bind(App.screens_vm)
	App.biomes_data.biome_unlocked.connect(_on_biome_unlocked)

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
	if App.biomes_data.biome_unlocked.is_connected(_on_biome_unlocked):
		App.biomes_data.biome_unlocked.disconnect(_on_biome_unlocked)

func _on_property_changed(property: StringName) -> void:
	match property:
		ScreensViewModel.PROP_SCREEN_CHANGED_TEXT:
			update_visuals()

## Unlocking a biome can reveal a new nav button — rebuild buttons only,
## the currently active screen's content/state stays untouched.
func _on_biome_unlocked(_key: StringName) -> void:
	_rebuild_nav_buttons()

func update_visuals() -> void:
	_show_screen(_vm.current_screen)
	_rebuild_nav_buttons()

## Reveals a screen, instantiating it on first visit only.
func _show_screen(screen_type: ScreenTypes.Types) -> void:
	if _current_screen_instance:
		_current_screen_instance.visible = false
		_current_screen_instance = null

	if not _screen_instances.has(screen_type):
		var screen_data := _vm.get_screen_data(screen_type)
		if screen_data == null or screen_data.screen_scene == null:
			push_error("No screen scene registered for screen type %d." % screen_type)
			return
		var instance := screen_data.screen_scene.instantiate() as Control
		screen_container.add_child(instance)
		_screen_instances[screen_type] = instance

	_current_screen_instance = _screen_instances[screen_type]
	_current_screen_instance.visible = true

func _rebuild_nav_buttons() -> void:
	for child in button_container.get_children():
		button_container.remove_child(child)
		child.queue_free()
	button_dictionary.clear()

	var all_screens := _vm.all_screen_data
	for screen_key in ScreenTypes.Types.size():
		if not App.is_screen_unlocked(screen_key):
			continue
		var button_data: ScreenDefinition = all_screens.get(screen_key)
		if button_data == null:
			continue  # screen type with no definition authored — nothing to show
		var button := button_scene.instantiate()
		button.set_button_text(button_data.screen_name)
		button.pressed.connect(on_screen_selected.bind(screen_key))
		button.set_selected(_vm.current_screen == screen_key)

		button_dictionary[screen_key] = button
		button_container.add_child(button)

func on_screen_selected(selected_screen : ScreenTypes.Types) -> void:
	_vm.set_current_screen(selected_screen)
	for button_key in button_dictionary:
		button_dictionary.get(button_key).set_selected(_vm.current_screen == button_key)
