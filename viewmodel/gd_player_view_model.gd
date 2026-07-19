class_name PlayerViewModel
extends ViewModel
## VIEWMODEL — adapts PlayerData for display and exposes commands.
## Owns formatting, derived/display state, and enabled/disabled logic.
## Holds a reference to the model; never to any Node.

const PROP_NUTRIENT_TEXT := &"nutrient_text"
const PROP_BIOMASS_TEXT := &"biomass_text"
const PROP_WATER_TEXT := &"water_text"

var _model: PlayerData

# --- Read-only display properties the View binds to ---

var nutrient_text: String:
	get:
		return "%s" % _format_number(_model.nutrients)

var biomass_text: String:
	get:
		return "%s" % _format_number(_model.biomass)
		
var water_text: String:
	get:
		return "%s" % _format_number(_model.water)
# --- Lifecycle ---

func _init(model: PlayerData) -> void:
	_model = model
	_model.nutrients_changed.connect(_on_nutrients_changed)
	_model.biomass_changed.connect(_on_biomass_changed)
	_model.water_changed.connect(_on_water_changed)

func dispose() -> void:
	_model.nutrients_changed.disconnect(_on_nutrients_changed)
	_model.biomass_changed.connect(_on_biomass_changed)
	_model.water_changed.connect(_on_water_changed)

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_NUTRIENT_TEXT)

func _on_biomass_changed(_value: BigNumber) -> void:
	_notify(PROP_BIOMASS_TEXT)

func _on_water_changed(_value: BigNumber) -> void:
	_notify(PROP_WATER_TEXT)

# --- Formatting (replace with your BigNumber formatter) ---

func _format_number(value: BigNumber) -> String:
	return value._to_string()
