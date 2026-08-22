class_name PlayerViewModel
extends ViewModel
## VIEWMODEL: adapts PlayerData for display and exposes commands.
## Owns formatting, derived state and enabled/disabled logic.
## References the model, never a Node.

const PROP_NUTRIENT_TEXT := &"nutrient_text"
const PROP_BIOMASS_TEXT := &"biomass_text"
const PROP_WATER_TEXT := &"water_text"
const PROP_CRYSTALS_TEXT := &"crystals_text"
const PROP_RELICS_TEXT := &"relics_text"
const PROP_ICHOR_TEXT := &"ichor_text"
const PROP_GLYPHS_TEXT := &"glyphs_text"

var _model: PlayerData

# --- Read-only display properties bound by the View ---

var nutrient_text: String:
	get:
		return "%s" % _format_number(_model.nutrients)

var biomass_text: String:
	get:
		return "%s" % _format_number(_model.biomass)

var water_text: String:
	get:
		return "%s" % _format_number(_model.water)

var crystals_text: String:
	get:
		return "%s" % _format_number(_model.crystals)

var relics_text: String:
	get:
		return "%s" % _format_number(_model.relics)

var ichor_text: String:
	get:
		return "%s" % _format_number(_model.ichor)

var glyphs_text: String:
	get:
		return "%s" % _format_number(_model.glyphs)

## Any currency's balance by type, for a view holding a CurrencyDef rather than a
## fixed currency - the resource pill, which is spawned per screen from whatever
## that screen lists. A method rather than a property because it takes an
## argument; the per-currency properties above stay for the views that know which
## one they show.
func currency_text(currency: CurrencyTypes.Types) -> String:
	return "%s" % _format_number(_model.get(CurrencyTypes.field_for(currency)))

# --- Lifecycle ---

func _init(model: PlayerData) -> void:
	_model = model
	_model.nutrients_changed.connect(_on_nutrients_changed)
	_model.biomass_changed.connect(_on_biomass_changed)
	_model.water_changed.connect(_on_water_changed)
	_model.crystals_changed.connect(_on_crystals_changed)
	_model.relics_changed.connect(_on_relics_changed)
	_model.ichor_changed.connect(_on_ichor_changed)
	_model.glyphs_changed.connect(_on_glyphs_changed)

func dispose() -> void:
	_model.nutrients_changed.disconnect(_on_nutrients_changed)
	_model.biomass_changed.disconnect(_on_biomass_changed)
	_model.water_changed.disconnect(_on_water_changed)
	_model.crystals_changed.disconnect(_on_crystals_changed)
	_model.relics_changed.disconnect(_on_relics_changed)
	_model.ichor_changed.disconnect(_on_ichor_changed)
	_model.glyphs_changed.disconnect(_on_glyphs_changed)

# --- Model -> notification plumbing ---

func _on_nutrients_changed(_value: BigNumber) -> void:
	_notify(PROP_NUTRIENT_TEXT)

func _on_biomass_changed(_value: BigNumber) -> void:
	_notify(PROP_BIOMASS_TEXT)

func _on_water_changed(_value: BigNumber) -> void:
	_notify(PROP_WATER_TEXT)

func _on_crystals_changed(_value: BigNumber) -> void:
	_notify(PROP_CRYSTALS_TEXT)

func _on_relics_changed(_value: BigNumber) -> void:
	_notify(PROP_RELICS_TEXT)

func _on_ichor_changed(_value: BigNumber) -> void:
	_notify(PROP_ICHOR_TEXT)

func _on_glyphs_changed(_value: BigNumber) -> void:
	_notify(PROP_GLYPHS_TEXT)

# --- Formatting ---

func _format_number(value: BigNumber) -> String:
	return value.to_display()
