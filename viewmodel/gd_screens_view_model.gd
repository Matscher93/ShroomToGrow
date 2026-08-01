class_name ScreensViewModel
extends ViewModel
## VIEWMODEL: adapts PlayerData for display and exposes commands.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.

const PROP_SCREEN_CHANGED_TEXT := &"screen_changed"

var _model: ScreensData

# --- View -> ViewModel ---
func set_current_screen(type: ScreenTypes.Types) -> void:
	_model.current_screen = type

# --- Read-only display properties bound by the View ---

var current_screen: ScreenTypes.Types:
	get: return _model.current_screen

var all_screen_data: Dictionary[ScreenTypes.Types, ScreenDefinition]:
	get: return _model.screen_data

func get_screen_data(type: ScreenTypes.Types) -> ScreenDefinition:
	return _model.screen_data.get(type)

# --- Lifecycle ---

func _init(model: ScreensData) -> void:
	_model = model
	_model.screen_changed.connect(_on_screen_changed)

func dispose() -> void:
	_model.screen_changed.disconnect(_on_screen_changed)

# --- Model -> notification plumbing ---

func _on_screen_changed(_type: ScreenTypes.Types) -> void:
	_notify(PROP_SCREEN_CHANGED_TEXT)
