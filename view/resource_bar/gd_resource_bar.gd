extends PanelContainer
## VIEW: the top bar's resource strip. Shows only the currencies the current
## screen actually earns or spends (authored per screen on ScreenDefinition),
## and folds the tick countdown into the same row instead of giving it a block
## of its own - the progress bar underneath spans the whole strip.

const PILL_SCENE := preload("res://view/resource_pill/sc_resource_pill.tscn")

@export var pill_container: HBoxContainer
@export var progress_rect: ColorRect
@export var lbl_time_left: Label

var _vm: ScreensViewModel
var _tick_timer: Timer

func _ready() -> void:
	_tick_timer = App.tick_timer
	if App.screens_vm:
		bind(App.screens_vm)

func bind(vm: ScreensViewModel) -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
	_vm = vm
	_vm.property_changed.connect(_on_property_changed)
	_rebuild_pills()

func _exit_tree() -> void:
	if _vm:
		_vm.property_changed.disconnect(_on_property_changed)
		_vm = null

func _process(_delta: float) -> void:
	var time_left := _tick_timer.time_left
	var tick_duration := _tick_timer.wait_time
	progress_rect.material.set_shader_parameter("tick_progress", 1.0 - time_left / tick_duration)
	lbl_time_left.text = "%.1fs" % [time_left]

# --- VM -> View ---
func _on_property_changed(property: StringName) -> void:
	match property:
		ScreensViewModel.PROP_SCREEN_CHANGED_TEXT:
			_rebuild_pills()

## Chips are rebuilt from scratch on every screen switch. There are at most a
## handful, and a pill binds its ViewModels in _ready(), so respawning is both
## cheaper and less stateful than hiding and rebinding the full set.
func _rebuild_pills() -> void:
	for child in pill_container.get_children():
		pill_container.remove_child(child)
		child.queue_free()

	for currency_def in _vm.current_currencies:
		var pill := PILL_SCENE.instantiate()
		pill.currency_def = currency_def
		pill_container.add_child(pill)
