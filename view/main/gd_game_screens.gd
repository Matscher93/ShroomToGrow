extends PanelContainer
## VIEW: hosts whichever game screen is up. Switching is driven from the nav menu
## (see view/navigation/), which writes through NavigationViewModel; this only
## reacts to the screen having changed.

var _vm: ScreensViewModel
@export var screen_container: PanelContainer

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

func bind(vm: ScreensViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_show_screen(_vm.current_screen)

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _on_property_changed(property: StringName) -> void:
	if property != ScreensViewModel.PROP_SCREEN_CHANGED_TEXT:
		return
	_show_screen(_vm.current_screen)

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
