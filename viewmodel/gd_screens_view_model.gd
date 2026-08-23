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

## Currencies the resource bar should show for the screen that is up right now.
var current_currencies: Array[CurrencyDef]:
	get:
		var definition := get_screen_data(_model.current_screen)
		if definition == null:
			return []
		return definition.currencies

func get_screen_data(type: ScreenTypes.Types) -> ScreenDefinition:
	return _model.screen_data.get(type)

# --- The tick countdown ---
#
# Read every frame by the resource bar's strip, which used to hold App.tick_timer
# and pull time_left off it directly. Deliberately not notified: a countdown moves
# continuously, so the view polls these in _process() rather than the VM emitting
# sixty notifications a second for it.

## How far through the current tick, 0 at the start and 1 at the payout.
var tick_progress: float:
	get:
		var duration := App.tick_duration()
		if duration <= 0.0:
			return 0.0
		return clampf(1.0 - App.tick_time_left() / duration, 0.0, 1.0)

var tick_time_left_text: String:
	get: return "%.1fs" % App.tick_time_left()

var tick_duration_text: String:
	get: return "/ %.1fs" % App.tick_duration()

# --- Lifecycle ---

func _init(model: ScreensData) -> void:
	_model = model
	_model.screen_changed.connect(_on_screen_changed)

func dispose() -> void:
	_model.screen_changed.disconnect(_on_screen_changed)

# --- Model -> notification plumbing ---

func _on_screen_changed(_type: ScreenTypes.Types) -> void:
	_notify(PROP_SCREEN_CHANGED_TEXT)
