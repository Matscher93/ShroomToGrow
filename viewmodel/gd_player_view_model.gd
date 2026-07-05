class_name PlayerViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_GOLD_TEXT := &"gold_text"

var _model: PlayerData

# --- Read-only display properties the View binds to ---

var gold_text: String:
	get:
		return "%s" % _format_number(_model.nutrients)

# --- Lifecycle ---

func _init(model: PlayerData) -> void:
	_model = model
	_model.nutrients_changed.connect(_on_nutrients_changed)


func dispose() -> void:
	_model.nutrients_changed.disconnect(_on_nutrients_changed)

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_GOLD_TEXT)


# --- Formatting (replace with your BigNumber formatter) ---

func _format_number(value: BigNumber) -> String:
	return value._to_string()
