extends PanelContainer

var _vm : ScreensViewModel
@export var screen_container: PanelContainer
@export var button_container: HBoxContainer
@export var button_scene: PackedScene

var button_dictionary: Dictionary[ScreenTypes.Types, PanelContainer]

## Screens are rebuilt from scratch on every switch and freed on leaving. View
## state (the perk web's pan, zoom and selection, expanded biome cards, scroll
## positions) is deliberately not kept: a cached screen misses everything that
## changed while it was hidden, so a biome unlock or a prestige reset left stale
## content on screens the player was not looking at. MenuWarmup preloads the
## scenes at boot, so the respawn cost is instantiate plus first layout only.
var _current_screen_instance: Control = null

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

## Unlocking a biome can reveal a new nav button. Rebuilds buttons only, the
## active screen's content and state stay untouched.
func _on_biome_unlocked(_key: StringName) -> void:
	_rebuild_nav_buttons()

func update_visuals() -> void:
	_show_screen(_vm.current_screen)
	_rebuild_nav_buttons()

## Frees whatever screen is up and builds the requested one fresh.
func _show_screen(screen_type: ScreenTypes.Types) -> void:
	# remove_child before queue_free: the free itself only lands at the end of
	# the frame, and until then the outgoing screen would still be laid out
	# alongside the incoming one.
	if _current_screen_instance:
		screen_container.remove_child(_current_screen_instance)
		_current_screen_instance.queue_free()
		_current_screen_instance = null

	var screen_data := _vm.get_screen_data(screen_type)
	if screen_data == null or screen_data.screen_scene == null:
		push_error("No screen scene registered for screen type %d." % screen_type)
		return
	_current_screen_instance = screen_data.screen_scene.instantiate() as Control
	screen_container.add_child(_current_screen_instance)

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
			continue  # screen type with no definition authored, nothing to show
		var button := button_scene.instantiate()
		button.set_button_text(button_data.screen_name)
		button.pressed.connect(_on_screen_selected.bind(screen_key))
		button.set_selected(_vm.current_screen == screen_key)

		button_dictionary[screen_key] = button
		button_container.add_child(button)

func _on_screen_selected(selected_screen: ScreenTypes.Types) -> void:
	_vm.set_current_screen(selected_screen)
	for button_key in button_dictionary:
		button_dictionary.get(button_key).set_selected(_vm.current_screen == button_key)
